import AppKit
import Darwin
import os
import SwiftUI

// MARK: - Big files: linked, not copied

/// Files bigger than a limit (250 MB by default) stay where they are: Stash keeps a link to the original
/// (a shortcut in its folder in Documents) instead of a copy, so a 20 GB video costs no space and no waiting.
/// Smaller files are copied in, as before. Copies already made are never turned back into links.
enum BigFiles {
    static let thresholdKey = "files.linkAboveMB"
    static let defaultMB = 250
    /// The choices in Settings (0 = no limit: copy everything, if copying is on).
    static let choices = [100, 250, 1_000, 5_000, 0]

    static var thresholdBytes: Int64? {
        let mb = UserDefaults.standard.object(forKey: thresholdKey) as? Int ?? defaultMB
        return mb > 0 ? Int64(mb) * 1_000_000 : nil
    }

    static func label(_ mb: Int) -> String {
        mb == 0 ? "No limit" : mb >= 1_000 ? "\(mb / 1_000) GB" : "\(mb) MB"
    }

    /// The file's size (0 for folders and things that can't be read).
    nonisolated static func size(of url: URL) -> Int64 {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .isDirectoryKey])
        guard values?.isDirectory != true else { return 0 }
        return Int64(values?.fileSize ?? 0)
    }

    /// True when it's big enough to be linked rather than copied.
    nonisolated static func isBig(_ url: URL) -> Bool {
        let limit = UserDefaults.standard.object(forKey: thresholdKey) as? Int ?? defaultMB
        return limit > 0 && size(of: url) >= Int64(limit) * 1_000_000
    }

    nonisolated static func sameVolume(_ a: URL, _ b: URL) -> Bool {
        let ka = try? a.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        let kb = try? b.resourceValues(forKeys: [.volumeIdentifierKey]).volumeIdentifier as? NSObject
        guard let ka, let kb else { return false }
        return ka.isEqual(kb)
    }

    /// Free space where a copy would go, for things that matter (macOS counts purgeable space too).
    nonisolated static func freeSpace(at url: URL) -> Int64? {
        var probe = url
        while !FileManager.default.fileExists(atPath: probe.path), probe.path != "/" { probe.deleteLastPathComponent() }
        return (try? probe.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]))?.volumeAvailableCapacityForImportantUsage
    }
}

/// What a file card is right now.
enum FileState {
    /// Stash has its own copy.
    case stored
    /// A link to the original, which is there.
    case linked(URL)
    /// A link to an original that isn't there any more (moved, renamed, deleted, or on a drive that's not connected).
    case missing(URL)
}

extension Store {
    func fileState(_ item: Item) -> FileState? {
        guard item.kind == .file, let url = item.linkURL, url.isFileURL else { return nil }
        if url.path.hasPrefix(rootDir.path + "/") || url.path.hasPrefix(dataDir.path + "/") { return .stored }
        return FileManager.default.fileExists(atPath: url.path) ? .linked(url) : .missing(url)
    }

    /// The original moved: find it again from its bookmark, or ask where it is. The link in Documents follows.
    func findOriginal(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), item.kind == .file else { return }
        if let data = item.bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                relink(id, to: url)
                flash("Found it: \(url.lastPathComponent)")
                return
            }
        }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.prompt = "Use This File"
        panel.message = "Where is “\(item.title ?? "the file")” now?"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        relink(id, to: url)
    }

    /// Points a linked file at its original's new place (and re-makes the shortcut in Documents).
    func relink(_ id: UUID, to url: URL) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        checkpoint("Find Original")
        if let stored = items[index].storedPath {
            let link = absolute(stored)
            if (try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil {
                try? FileManager.default.removeItem(at: link)
                try? FileManager.default.createSymbolicLink(at: link, withDestinationURL: url)
            }
        }
        items[index].url = url.absoluteString
        items[index].bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        save()
    }

    /// Every few minutes (with the mirror's full check): linked files whose original moved are followed by
    /// their bookmark, quietly. Nothing is moved or changed on disk except Stash's own shortcut.
    func followMovedOriginals() {
        for item in items where item.kind == .file && item.bookmark != nil {
            guard case .missing? = fileState(item), let data = item.bookmark else { continue }
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI, .withoutMounting], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                relink(item.id, to: url)
            }
        }
    }

    /// What to give another app when a file is dragged or copied out of Stash. Linked files: the original itself
    /// (the other app copies it — no waiting, even for 20 GB). Stash's own files: a visible clone (instant on the
    /// same disk), made only when the drop actually happens.
    nonisolated static func handOut(_ url: URL) -> URL {
        let fm = FileManager.default
        if let target = try? fm.destinationOfSymbolicLink(atPath: url.path) {
            let resolved = URL(fileURLWithPath: target, relativeTo: url.deletingLastPathComponent()).standardizedFileURL
            return fm.fileExists(atPath: resolved.path) ? resolved : url
        }
        let library = Store.libraryRootPath
        guard url.path.hasPrefix(library) else { return url } // not inside the hidden library: hand it out as it is
        // A copy on another disk would take as long as the file is big; give the file itself rather than freeze.
        if !BigFiles.sameVolume(url, TestMode.temp("StashOut")), BigFiles.size(of: url) > 500_000_000 { return url }
        return visibleCopy(of: url)
    }
}

// MARK: - Copying files in, safely and in the background

/// Copies files into Stash two at a time, off the main thread, with progress on the card and a Cancel button.
/// The copy is written under a temporary name and only renamed into place when it's complete, so a cancelled,
/// failed or interrupted copy never looks like a real file. There has to be room for it first.
@MainActor
final class FileCopies: ObservableObject {
    static let shared = FileCopies()
    /// 0…1 per card while its file is being copied.
    @Published private(set) var progress: [UUID: Double] = [:]
    private var cancelled: Set<UUID> = []
    /// The same, readable from the copying threads without waiting for the main thread.
    nonisolated private static let stopFlags = OSAllocatedUnfairLock(initialState: Set<UUID>())
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .utility
        q.name = "Swiss file copies"
        return q
    }()

    func isCopying(_ id: UUID) -> Bool { progress[id] != nil }

    func cancel(_ id: UUID) {
        guard progress[id] != nil else { return }
        cancelled.insert(id)
        Self.stopFlags.withLock { _ = $0.insert(id) }
    }

    /// Copies `source` to `destination` (whose folder is made if needed). `done` gets the finished file, or nil.
    func copy(_ source: URL, to destination: URL, for id: UUID, done: @escaping @MainActor (URL?, String?) -> Void) {
        let total = max(1, BigFiles.size(of: source))
        if let free = BigFiles.freeSpace(at: destination), free < total + 500_000_000 {
            done(nil, "Not enough space for a copy (\(ByteCountFormatter.string(fromByteCount: total, countStyle: .file)))")
            return
        }
        progress[id] = 0
        cancelled.remove(id)
        Self.stopFlags.withLock { _ = $0.remove(id) }
        queue.addOperation {
            let result = FileCopies.run(source, destination, total: total, id: id)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let wasCancelled = self.cancelled.remove(id) != nil
                    Self.stopFlags.withLock { _ = $0.remove(id) }
                    self.progress[id] = nil
                    if wasCancelled { done(nil, "Cancelled") } else { done(result.url, result.error) }
                }
            }
        }
    }

    /// Progress from the copy, at most every 1% or so.
    fileprivate func report(_ id: UUID, _ fraction: Double) {
        guard let old = progress[id], fraction - old >= 0.01 || fraction >= 1 else { return }
        progress[id] = fraction
    }

    private final class Context {
        let id: UUID
        let total: Int64
        var lastReported: Double = 0
        var stop = false
        init(id: UUID, total: Int64) { self.id = id; self.total = total }
    }

    /// The copy itself: macOS's copyfile, which clones instantly on the same disk and streams otherwise
    /// (the file is never read into memory). Runs off the main thread.
    nonisolated private static func run(_ source: URL, _ destination: URL, total: Int64, id: UUID) -> (url: URL?, error: String?) {
        let fm = FileManager.default
        let folder = destination.deletingLastPathComponent()
        let partial = folder.appendingPathComponent("." + destination.lastPathComponent + ".stashpart")
        do {
            try fm.createDirectory(at: folder, withIntermediateDirectories: true)
            try? fm.removeItem(at: partial)
        } catch {
            return (nil, error.localizedDescription)
        }
        let context = Context(id: id, total: total)
        let state = copyfile_state_alloc()
        defer { copyfile_state_free(state) }
        let callback: copyfile_callback_t = { what, stage, state, _, _, ctx in
            guard let ctx else { return COPYFILE_CONTINUE }
            let context = Unmanaged<Context>.fromOpaque(ctx).takeUnretainedValue()
            if what == COPYFILE_COPY_DATA, stage == COPYFILE_PROGRESS {
                var copied: off_t = 0
                copyfile_state_get(state, UInt32(COPYFILE_STATE_COPIED), &copied)
                let fraction = min(1, Double(copied) / Double(context.total))
                if fraction - context.lastReported >= 0.01 {
                    context.lastReported = fraction
                    let id = context.id
                    DispatchQueue.main.async { MainActor.assumeIsolated { FileCopies.shared.report(id, fraction) } }
                }
                // Cancel asks politely; the next chunk stops.
                if FileCopies.stopFlags.withLock({ $0.contains(context.id) }) { context.stop = true; return COPYFILE_QUIT }
            }
            return COPYFILE_CONTINUE
        }
        let unmanaged = Unmanaged.passRetained(context)
        defer { unmanaged.release() }
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CB), unsafeBitCast(callback, to: UnsafeRawPointer.self))
        copyfile_state_set(state, UInt32(COPYFILE_STATE_STATUS_CTX), unmanaged.toOpaque())
        let status = copyfile(source.path, partial.path, state, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE))
        guard status == 0, !context.stop else {
            let reason = context.stop ? "Cancelled" : String(cString: strerror(errno))
            try? fm.removeItem(at: partial)
            return (nil, reason)
        }
        // Complete: give it its real name (never over a file that's already there).
        var final = destination
        var n = 2
        while fm.fileExists(atPath: final.path) {
            let ext = destination.pathExtension
            let stem = destination.deletingPathExtension().lastPathComponent
            final = folder.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        do {
            try fm.moveItem(at: partial, to: final)
            return (final, nil)
        } catch {
            try? fm.removeItem(at: partial)
            return (nil, error.localizedDescription)
        }
    }
}

/// The ring and Cancel button on a card whose file is still being copied in. Only this little view follows
/// the copy's progress, so the board doesn't redraw for it.
struct CopyProgressBadge: View {
    @ObservedObject private var copies = FileCopies.shared
    let id: UUID

    var body: some View {
        if let fraction = copies.progress[id] {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35))
                VStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 3)
                        Circle().trim(from: 0, to: fraction)
                            .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                            .rotationEffect(.degrees(-90))
                    }
                    .frame(width: 24, height: 24)
                    Text("\(Int(fraction * 100))%").font(.system(size: 9, weight: .bold, design: .rounded)).foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { FileCopies.shared.cancel(id) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15).background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Stop copying — the card keeps a link to the original instead")
                .accessibilityLabel("Cancel copying")
            }
            .help("Copying into Swiss…")
        }
    }
}

// MARK: - Pictures for the board, made in the background

/// Thumbnails for cards: made off the main thread (two at a time), at the size they're shown, and kept in a
/// memory cache with a limit. A card shows its placeholder until its picture is ready; nothing waits for it.
@MainActor
final class ThumbnailService: ObservableObject {
    static let shared = ThumbnailService()
    /// Bumped (a few times a second at most) when new pictures are ready.
    @Published private(set) var version = 0
    private var pending: Set<String> = []
    private var failed: Set<String> = []
    private var bumpScheduled = false
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 2
        q.qualityOfService = .userInitiated
        q.name = "Swiss thumbnails"
        return q
    }()

    private static func key(_ url: URL, _ pixels: Int) -> String { "\(url.path)|\(pixels)" }

    /// The picture if it's ready; otherwise starts making it and returns nil.
    func image(at url: URL, maxPixels: Int) -> NSImage? {
        let key = Self.key(url, maxPixels)
        if let hit = Store.shared.thumbCache.object(forKey: key as NSString) { return hit }
        guard !pending.contains(key), !failed.contains(key) else { return nil }
        pending.insert(key)
        queue.addOperation {
            let cg = ThumbnailService.make(url, maxPixels: maxPixels)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.pending.remove(key)
                    if let cg {
                        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                        Store.shared.thumbCache.setObject(image, forKey: key as NSString, cost: cg.width * cg.height * 4)
                        self.scheduleBump()
                    } else {
                        self.failed.insert(key)
                    }
                }
            }
        }
        return nil
    }

    /// Right now, on this thread (for one-off uses like the Info window).
    func imageNow(at url: URL, maxPixels: Int) -> NSImage? {
        let key = Self.key(url, maxPixels)
        if let hit = Store.shared.thumbCache.object(forKey: key as NSString) { return hit }
        guard let cg = Self.make(url, maxPixels: maxPixels) else { return nil }
        let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
        Store.shared.thumbCache.setObject(image, forKey: key as NSString, cost: cg.width * cg.height * 4)
        return image
    }

    /// The file changed or just arrived: try it again.
    func forget(_ url: URL) {
        failed = failed.filter { !$0.hasPrefix(url.path + "|") }
    }

    private func scheduleBump() {
        guard !bumpScheduled else { return }
        bumpScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            MainActor.assumeIsolated {
                self.bumpScheduled = false
                self.version &+= 1
            }
        }
    }

    /// ImageIO: decodes only what's needed for that size (camera RAW files use their own preview when it's big enough).
    nonisolated static func make(_ url: URL, maxPixels: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageIfAbsent: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixels,
        ]
        if let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
           max(cg.width, cg.height) >= min(maxPixels, Self.pixelSize(source)) * 3 / 4 {
            return cg
        }
        // The built-in preview was too small: make one from the picture itself.
        var always = options
        always[kCGImageSourceCreateThumbnailFromImageAlways] = true
        return CGImageSourceCreateThumbnailAtIndex(source, 0, always as CFDictionary)
    }

    /// The picture's longer side, read from its header (nothing is decoded).
    nonisolated static func pixelSize(_ source: CGImageSource) -> Int {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        let w = props[kCGImagePropertyPixelWidth] as? Int ?? 0, h = props[kCGImagePropertyPixelHeight] as? Int ?? 0
        return max(w, h)
    }

    /// Pixels in a picture file, from its header.
    nonisolated static func pixelCount(_ url: URL) -> Int {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] else { return 0 }
        return (props[kCGImagePropertyPixelWidth] as? Int ?? 0) * (props[kCGImagePropertyPixelHeight] as? Int ?? 0)
    }
}

// MARK: - Heavy jobs one at a time

/// Video conversions are heavy (all the cores, lots of disk): one at a time, the rest wait their turn.
actor HeavyJobs {
    static let conversions = HeavyJobs(limit: 1)
    private let limit: Int
    private var running = 0
    private var waiting: [CheckedContinuation<Void, Never>] = []

    init(limit: Int) { self.limit = limit }

    func run<T: Sendable>(_ work: @Sendable () async throws -> T) async rethrows -> T {
        if running >= limit { await withCheckedContinuation { waiting.append($0) } } else { running += 1 }
        defer {
            if waiting.isEmpty { running -= 1 } else { waiting.removeFirst().resume() }
        }
        return try await work()
    }
}

// MARK: - Settings

struct BigFileSettings: View {
    @AppStorage(OrganizerSettings.copyFilesKey) private var copyFiles = true
    @AppStorage(BigFiles.thresholdKey) private var threshold = BigFiles.defaultMB

    var body: some View {
        Section {
            Toggle("Keep a copy of files in Swiss (videos, music, 3D…)", isOn: $copyFiles)
            Picker("Files bigger than this stay where they are (linked)", selection: $threshold) {
                ForEach(BigFiles.choices, id: \.self) { Text(BigFiles.label($0)).tag($0) }
            }
            .disabled(!copyFiles)
        } header: {
            Label("Big files", systemImage: "externaldrive")
        } footer: {
            Text("A linked file isn't copied: Swiss shows it, opens it, previews it and drags it out, straight from where it is — a 20 GB video costs no space and no waiting. If you move or rename the original, Swiss follows it; if it's on a drive that isn't connected, the card says so. Copies already in Swiss stay copies. Copying happens in the background with a Cancel button, and only when there's room.")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
    }
}
