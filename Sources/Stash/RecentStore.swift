import AppKit
import SwiftUI

// MARK: - Recent: the temporary inbox

/// Something that landed in Recent: copied text or a link, copied files (only linked — nothing is copied until you
/// Keep them), a copied picture, or a screenshot from the folder you chose. Recent is temporary: items expire
/// after the time you set (7 days by default), and the oldest go first if Recent grows past its size limit.
/// **Keep** turns one into a real, permanent thing in a project.
struct RecentItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case text, link, files, image, screenshot }
    var id = UUID()
    var firstSeen = Date()
    var lastSeen = Date()
    /// How many times the same thing was copied (repeats collapse into one entry).
    var count = 1
    var kind: Kind
    var text: String?
    /// Files and screenshots: where the originals are (linked, not copied).
    var paths: [String]?
    /// A copied picture: the picture itself (it has nowhere else to live until you Keep it).
    var blob: String?
    /// A small preview (JPEG, a few dozen KB).
    var preview: String?
    var width: Int?
    var height: Int?
    /// The app it came from ("Safari").
    var sourceApp: String?
    /// Where it was kept ("Poster Series ▸ PhotoBook"), once you've kept it.
    var keptIn: String?
    /// The thing in a project this entry is (saved into a project, or kept): Recent shows that same thing —
    /// no second copy. Removing it from Recent leaves it in its project.
    var itemID: UUID?

    var fileURLs: [URL] { (paths ?? []).map { URL(fileURLWithPath: $0) } }
    var filesExist: Bool { fileURLs.allSatisfy { FileManager.default.fileExists(atPath: $0.path) } }

    /// What makes two captures "the same".
    var signature: String {
        if let itemID { return "item" + itemID.uuidString }
        switch kind {
        case .text, .link: return kind.rawValue + (text ?? "")
        case .files, .screenshot: return kind.rawValue + (paths ?? []).joined(separator: "|")
        case .image: return "image\(width ?? 0)x\(height ?? 0)-\(text ?? "")"
        }
    }

    var title: String {
        switch kind {
        case .text: return (text ?? "").replacingOccurrences(of: "\n", with: " ")
        case .link: return URL(string: text ?? "")?.host.map { $0.replacingOccurrences(of: "www.", with: "") } ?? (text ?? "")
        case .files: return fileURLs.count == 1 ? fileURLs[0].lastPathComponent : "\(fileURLs.count) files"
        case .image: return "Picture" + (width.map { " · \($0) × \(height ?? 0)" } ?? "")
        case .screenshot: return fileURLs.first?.deletingPathExtension().lastPathComponent ?? "Screenshot"
        }
    }
}

/// The settings for capturing, all off until you turn them on.
enum CaptureSettings {
    static let clipboardKey = "capture.clipboard"
    static let screenshotsKey = "capture.screenshots"
    static let screenshotFolderKey = "capture.screenshotFolder"
    static let pausedKey = "capture.paused"
    static let retentionKey = "recent.retentionDays" // 1, 3 (the default), 7, 30, or 0 = until you clear it
    static let maxMBKey = "recent.maxMB"
    static let excludedKey = "capture.excludedApps"

    /// Password managers and the like: never captured from.
    static let defaultExcluded = ["com.1password.1password", "com.agilebits.onepassword7", "com.bitwarden.desktop",
                                  "com.lastpass.LastPass", "com.dashlane.dashlanephonefinal", "com.apple.keychainaccess",
                                  "com.apple.Passwords"]

    static func register() {
        UserDefaults.standard.register(defaults: [clipboardKey: false, screenshotsKey: false, pausedKey: false,
                                                  retentionKey: 3, maxMBKey: 500, excludedKey: defaultExcluded])
    }

    static var clipboardOn: Bool { UserDefaults.standard.bool(forKey: clipboardKey) }
    static var screenshotsOn: Bool { UserDefaults.standard.bool(forKey: screenshotsKey) }
    static var paused: Bool { UserDefaults.standard.bool(forKey: pausedKey) }
    static var excluded: [String] { UserDefaults.standard.stringArray(forKey: excludedKey) ?? defaultExcluded }

    /// The screenshot folder you chose, or where macOS saves screenshots.
    static var screenshotFolder: URL {
        if let chosen = UserDefaults.standard.string(forKey: screenshotFolderKey) { return URL(fileURLWithPath: chosen, isDirectory: true) }
        let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        return URL(fileURLWithPath: saved.map { ($0 as NSString).expandingTildeInPath } ?? NSHomeDirectory() + "/Desktop", isDirectory: true)
    }
}

@MainActor
final class RecentStore: ObservableObject {
    static let shared = RecentStore()

    @Published private(set) var items: [RecentItem] = []
    @Published var selection: Set<UUID> = []
    /// What Recent shows, top to bottom (set by its list), and the last thing clicked — for ⇧-click ranges.
    var shownIDs: [UUID] = []
    private var anchor: UUID?

    /// Click = just this, ⌘-click = add / remove, ⇧-click = everything from the last click to this one.
    func click(_ id: UUID, flags: NSEvent.ModifierFlags) {
        if flags.contains(.shift), let b = shownIDs.firstIndex(of: id),
           let a = anchor.flatMap({ selection.contains($0) ? shownIDs.firstIndex(of: $0) : nil })
            ?? shownIDs.indices.filter({ selection.contains(shownIDs[$0]) }).min(by: { abs($0 - b) < abs($1 - b) }) {
            selection.formUnion(shownIDs[min(a, b)...max(a, b)])
            return
        }
        if flags.contains(.command) {
            if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
        } else {
            selection = [id]
        }
        anchor = id
    }
    /// Where the arrow keys are (the list follows it).
    @Published var cursor: UUID?
    /// Capture paused from the menu bar or the Recent list (mirrors the setting so views update).
    @Published var paused = CaptureSettings.paused

    private var lastCount = NSPasteboard.general.changeCount
    private var clipboardTimer: Timer?
    private var screenshotTimer: Timer?
    /// Screenshots newer than this are picked up. Starts 10 minutes back, so one you took just before turning
    /// screenshots on (or before Stash started) still lands in Recent.
    private var screenshotsSince = Date().addingTimeInterval(-600)
    private var screenshotsWereOn = CaptureSettings.screenshotsOn
    private var seenScreenshots: Set<String> = []
    private var sizesSeen: [String: Int] = [:]
    private var lastScreenshotAt = Date.distantPast
    /// While Keep is saving into a project, those saves aren't added to Recent again.
    private var keeping = false

    var dir: URL { Store.shared.dataDir.appendingPathComponent("recent", isDirectory: true) }
    private var listURL: URL { dir.appendingPathComponent("recent.json") }
    private var blobsDir: URL { dir.appendingPathComponent("blobs", isDirectory: true) }
    private var previewsDir: URL { dir.appendingPathComponent("previews", isDirectory: true) }

    // MARK: Start

    func start() {
        guard clipboardTimer == nil else { return }
        CaptureSettings.register()
        try? FileManager.default.createDirectory(at: blobsDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: previewsDir, withIntermediateDirectories: true)
        load()
        migrateRecentCopies()
        prune()
        clipboardTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { _ in
            MainActor.assumeIsolated { RecentStore.shared.checkClipboard() }
        }
        screenshotTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            MainActor.assumeIsolated { RecentStore.shared.checkScreenshots() }
        }
        Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            MainActor.assumeIsolated { RecentStore.shared.prune() }
        }
    }

    func setPaused(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: CaptureSettings.pausedKey)
        paused = value
        lastCount = NSPasteboard.general.changeCount // nothing copied while paused is picked up afterwards
        Store.shared.flash(value ? "Capture paused" : "Capture on")
    }

    // MARK: Clipboard

    private func checkClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != lastCount else { return }
        lastCount = pb.changeCount
        guard CaptureSettings.clipboardOn, !paused else { return }
        // A moment's wait: some apps put several versions on the clipboard one after another.
        let count = pb.changeCount
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            MainActor.assumeIsolated {
                guard NSPasteboard.general.changeCount == count else { return }
                RecentStore.shared.capture(NSPasteboard.general)
            }
        }
    }

    private func capture(_ pb: NSPasteboard) {
        let types = Set((pb.types ?? []).map(\.rawValue))
        // Never keep passwords or anything apps mark as private or temporary.
        if types.contains("org.nspasteboard.ConcealedType") || types.contains("org.nspasteboard.TransientType")
            || types.contains("org.nspasteboard.AutoGeneratedType") || types.contains("com.agilebits.onepassword") { return }
        let app = NSWorkspace.shared.frontmostApplication
        if let id = app?.bundleIdentifier, CaptureSettings.excluded.contains(id) { return }
        let source = app?.localizedName

        var item: RecentItem?
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            item = RecentItem(kind: .files, paths: urls.map(\.path)) // linked, nothing copied
            item?.preview = urls.count == 1 ? previewFile(of: urls[0]) : nil
        } else if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            let isLink = !string.contains(where: \.isWhitespace)
                && (URL(string: string)?.scheme.map { ["http", "https"].contains($0.lowercased()) } ?? false)
            item = RecentItem(kind: isLink ? .link : .text, text: String(string.prefix(20_000)))
        } else if let image = NSImage(pasteboard: pb), let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) {
            // A screenshot that was also just saved to the folder: don't take it twice.
            if Date().timeIntervalSince(lastScreenshotAt) < 4 { return }
            let id = UUID()
            let png = pb.data(forType: .png) ?? NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
            guard let png, (try? png.write(to: blobsDir.appendingPathComponent(id.uuidString + ".png"))) != nil else { return }
            item = RecentItem(id: id, kind: .image, text: "\(png.count)", blob: id.uuidString + ".png",
                              preview: savePreview(cg), width: cg.width, height: cg.height)
        }
        guard var item else { return }
        item.sourceApp = source
        add(item)
    }

    // MARK: Screenshots

    /// Watches only the folder you chose, and only files macOS marks as screenshots, once they've finished writing.
    private func checkScreenshots() {
        guard CaptureSettings.screenshotsOn, !paused else { screenshotsWereOn = false; screenshotsSince = Date(); return }
        if !screenshotsWereOn { // just turned on: include the last 10 minutes
            screenshotsWereOn = true
            screenshotsSince = Date().addingTimeInterval(-600)
        }
        let folder = CaptureSettings.screenshotFolder
        watch(folder)
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.creationDateKey, .fileSizeKey],
                                                                         options: [.skipsHiddenFiles]) else { return }
        for url in files where Store.imageExtensions.contains(url.pathExtension.lowercased()) && !seenScreenshots.contains(url.path) {
            let values = try? url.resourceValues(forKeys: [.creationDateKey, .fileSizeKey])
            guard let created = values?.creationDate, created >= screenshotsSince,
                  getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0 else { continue }
            // Still being written? Take it the moment it reads as a whole picture (macOS usually moves a finished
            // screenshot into place); otherwise look again in a moment.
            let size = values?.fileSize ?? 0
            let whole = CGImageSourceCreateWithURL(url as CFURL, nil).map { CGImageSourceGetStatus($0) == .statusComplete } ?? false
            guard size > 0, whole || sizesSeen[url.path] == size else {
                sizesSeen[url.path] = size
                lookSoon(after: 0.25)
                continue
            }
            sizesSeen[url.path] = nil
            seenScreenshots.insert(url.path)
            // Already in Recent (e.g. picked up before Stash restarted): don't count it twice.
            if items.contains(where: { $0.kind == .screenshot && $0.paths == [url.path] }) { continue }
            lastScreenshotAt = Date()
            var item = RecentItem(kind: .screenshot, paths: [url.path]) // a reference until you Keep it
            item.preview = previewFile(of: url)
            if let source = CGImageSourceCreateWithURL(url as CFURL, nil),
               let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
                item.width = props[kCGImagePropertyPixelWidth] as? Int
                item.height = props[kCGImagePropertyPixelHeight] as? Int
            }
            item.sourceApp = "Screenshot"
            add(item)
            if TestMode.isOn { FileHandle.standardError.write(String(format: "screenshot in Recent %.0f ms after it was saved\n", Date().timeIntervalSince(created) * 1000).data(using: .utf8)!) }
        }
    }

    /// The screenshot folder, watched: a new screenshot is picked up as soon as it lands, not on the next 2-second
    /// check (which stays as a backup).
    private var folderWatch: DispatchSourceFileSystemObject?
    private var watchedPath: String?
    private var lookPending = false

    private func watch(_ folder: URL) {
        guard watchedPath != folder.path else { return }
        folderWatch?.cancel()
        folderWatch = nil
        watchedPath = folder.path
        let fd = open(folder.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .extend], queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { RecentStore.shared.lookSoon(after: 0.05) } }
        source.setCancelHandler { close(fd) }
        source.resume()
        folderWatch = source
    }

    private func lookSoon(after delay: TimeInterval) {
        guard !lookPending else { return }
        lookPending = true
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated {
                RecentStore.shared.lookPending = false
                RecentStore.shared.checkScreenshots()
            }
        }
    }

    // MARK: Adding, limits

    private func add(_ item: RecentItem) {
        var list = items
        if let same = list.firstIndex(where: { $0.signature == item.signature }) {
            drop(files: item) // the new copy's preview/picture isn't needed
            var existing = list.remove(at: same)
            existing.lastSeen = Date()
            existing.count += 1
            list.insert(existing, at: 0)
        } else {
            list.insert(item, at: 0)
        }
        items = list
        prune()
        save()
    }

    /// Removes what's past its time, then the oldest until Recent fits its size limit.
    func prune() {
        dropMissingReferences()
        let days = UserDefaults.standard.integer(forKey: CaptureSettings.retentionKey)
        if days > 0 {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
            for old in items where old.lastSeen < cutoff { drop(files: old) }
            items.removeAll { $0.lastSeen < cutoff }
        }
        let limit = Int64(max(50, UserDefaults.standard.integer(forKey: CaptureSettings.maxMBKey))) * 1_000_000
        var total = items.reduce(Int64(0)) { $0 + bytes(of: $1) }
        while total > limit, let oldest = items.last {
            total -= bytes(of: oldest)
            drop(files: oldest)
            items.removeLast()
        }
        selection = selection.intersection(items.map(\.id))
        save()
    }

    private func bytes(of item: RecentItem) -> Int64 {
        [item.blob.map { blobsDir.appendingPathComponent($0) }, item.preview.map { previewsDir.appendingPathComponent($0) }]
            .compactMap { $0 }
            .reduce(0) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0) }
    }

    private func drop(files item: RecentItem) {
        if let blob = item.blob { try? FileManager.default.removeItem(at: blobsDir.appendingPathComponent(blob)) }
        if let preview = item.preview { try? FileManager.default.removeItem(at: previewsDir.appendingPathComponent(preview)) }
    }

    func remove(_ ids: Set<UUID>) {
        for item in items where ids.contains(item.id) { drop(files: item) }
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        save()
    }

    func clear() {
        items.forEach(drop)
        items = []
        selection = []
        save()
        Store.shared.flash("Recent cleared")
    }

    /// Something was saved into a project (pasted, dropped, quick-saved…): it shows in Recent as that same thing.
    func noteSaved(_ id: UUID) {
        guard !keeping, !items.contains(where: { $0.itemID == id }),
              let item = Store.shared.items.first(where: { $0.id == id }),
              item.kind != .text else { return } // notes you write in Stash aren't "recent copies"
        let kind: RecentItem.Kind = switch item.kind {
        case .text: .text
        case .link: .link
        case .image: .image
        case .file: .files
        }
        var entry = RecentItem(kind: kind, itemID: id)
        entry.sourceApp = "Saved"
        items.insert(entry, at: 0)
        prune()
    }

    /// Entries that point at things no longer in any project drop out.
    func dropMissingReferences() {
        let alive = Set(Store.shared.items.map(\.id))
        let before = items.count
        items.removeAll { $0.itemID.map { !alive.contains($0) } ?? false }
        if items.count != before { selection = selection.intersection(items.map(\.id)); save() }
    }

    // MARK: Keep, copy, look

    /// Makes them permanent in `place`: notes and links as themselves; pictures, files and screenshots are copied
    /// into the project (only now). The Recent entry stays, marked "Kept in …", until it expires.
    func keep(_ ids: Set<UUID>, in place: Place) {
        let store = Store.shared
        // Already in a project (it *is* a project item): nothing to keep.
        let chosen = items.filter { ids.contains($0.id) && $0.itemID == nil }
        guard !chosen.isEmpty else { return }
        var made: [UUID: UUID] = [:] // Recent entry → the new project item
        keeping = true
        store.undoGroup("Keep") {
            for item in chosen {
                let before = Set(store.items.map(\.id))
                switch item.kind {
                case .text, .link:
                    store.addText(item.text ?? "", place: place)
                case .image:
                    if let blob = item.blob, let data = try? Data(contentsOf: blobsDir.appendingPathComponent(blob)) {
                        store.addImage(data: data, ext: "png", source: nil, title: nil, place: place)
                    }
                case .files, .screenshot:
                    let pb = NSPasteboard(name: .init("stash.keep"))
                    pb.clearContents()
                    pb.writeObjects(item.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) } as [NSURL])
                    _ = store.ingest(pb, into: place)
                }
                if let new = store.items.first(where: { !before.contains($0.id) })?.id { made[item.id] = new }
            }
        }
        keeping = false
        let name = store.describe(place)
        // Recent now shows the kept thing itself: its own picture/preview copy is deleted — no double copy.
        for index in items.indices {
            guard let new = made[items[index].id] else { continue }
            drop(files: items[index])
            items[index].blob = nil
            items[index].preview = nil
            items[index].itemID = new
            items[index].keptIn = name
        }
        save()
        store.flash(chosen.count == 1 ? "Kept in \(name)" : "Kept \(chosen.count) in \(name)", undo: true)
    }

    func copyAgain(_ item: RecentItem) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text, .link: pb.setString(item.text ?? "", forType: .string)
        case .files, .screenshot: pb.writeObjects(item.fileURLs as [NSURL])
        case .image: if let url = blobURL(item), let image = NSImage(contentsOf: url) { pb.writeObjects([image]) }
        }
        lastCount = pb.changeCount // Stash's own copy isn't a new capture
        Store.shared.flash("Copied")
    }

    func blobURL(_ item: RecentItem) -> URL? { item.blob.map { blobsDir.appendingPathComponent($0) } }

    func previewImage(_ item: RecentItem) -> NSImage? {
        item.preview.flatMap { NSImage(contentsOf: previewsDir.appendingPathComponent($0)) }
    }

    /// The real file behind it (for Quick Look and dragging out).
    func fileURL(_ item: RecentItem) -> URL? {
        switch item.kind {
        case .image: return blobURL(item)
        case .files, .screenshot: return item.fileURLs.first
        default: return nil
        }
    }

    var diskBytes: Int64 { StorageReport.size(of: dir) }

    // MARK: Previews

    private func savePreview(_ image: CGImage) -> String? {
        guard let (data, ext) = Store.previewData(from: image) else { return nil }
        let name = UUID().uuidString + "." + ext
        return (try? data.write(to: previewsDir.appendingPathComponent(name))) != nil ? name : nil
    }

    private func previewFile(of url: URL) -> String? {
        guard Store.imageExtensions.contains(url.pathExtension.lowercased()),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true,
                                                                        kCGImageSourceCreateThumbnailWithTransform: true,
                                                                        kCGImageSourceThumbnailMaxPixelSize: 600] as CFDictionary)
        else { return nil }
        return savePreview(cg)
    }

    // MARK: Saving

    private func load() {
        items = (try? JSONDecoder.iso.decode([RecentItem].self, from: Data(contentsOf: listURL))) ?? []
    }

    private func save() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(items).write(to: listURL, options: .atomic)
    }

    /// Once: the old "Recent copies" list (last 5 copies) moves into Recent.
    private func migrateRecentCopies() {
        let old = Store.shared.dataDir.appendingPathComponent("clips", isDirectory: true)
        let list = old.appendingPathComponent("history.json")
        guard FileManager.default.fileExists(atPath: list.path) else { return }
        struct OldClip: Decodable { var date: Date; var kind: String; var text: String?; var paths: [String]?; var imageFile: String? }
        let clips = (try? JSONDecoder().decode([OldClip].self, from: Data(contentsOf: list))) ?? []
        for clip in clips.reversed() {
            var item = RecentItem(firstSeen: clip.date, lastSeen: clip.date, kind: RecentItem.Kind(rawValue: clip.kind) ?? .text,
                                  text: clip.text, paths: clip.paths)
            if let file = clip.imageFile, let data = try? Data(contentsOf: old.appendingPathComponent(file)) {
                let name = UUID().uuidString + ".jpg"
                try? data.write(to: previewsDir.appendingPathComponent(name))
                item.preview = name
                item.blob = nil
                item.kind = .image
                if let blob = try? Data(contentsOf: old.appendingPathComponent(file)) {
                    let blobName = item.id.uuidString + ".jpg"
                    try? blob.write(to: blobsDir.appendingPathComponent(blobName))
                    item.blob = blobName
                }
            }
            if !items.contains(where: { $0.signature == item.signature }) { items.insert(item, at: 0) }
        }
        items.sort { $0.lastSeen > $1.lastSeen }
        save()
        try? FileManager.default.removeItem(at: old)
    }
}
