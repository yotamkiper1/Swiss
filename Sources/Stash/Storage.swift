import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Small previews

/// Previews (link pictures, file and video thumbnails) are only for showing on the board, so they're kept small:
/// at most 600 px, JPEG — or PNG when they have see-through parts (like file icons). The pictures you add yourself
/// are never touched.
extension Store {
    nonisolated static let previewMaxSide: CGFloat = 600

    nonisolated static func previewData(from image: CGImage) -> (data: Data, ext: String)? {
        let w = CGFloat(image.width), h = CGFloat(image.height)
        let factor = min(1, previewMaxSide / max(w, h))
        let width = max(1, Int(w * factor)), height = max(1, Int(h * factor))
        let alpha: Bool = {
            switch image.alphaInfo {
            case .none, .noneSkipFirst, .noneSkipLast: return false
            default: return true
            }
        }()
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let small = context.makeImage() else { return nil }
        let out = NSMutableData()
        let type = (alpha ? UTType.png : UTType.jpeg).identifier as CFString
        guard let dest = CGImageDestinationCreateWithData(out, type, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, small, alpha ? nil : [kCGImageDestinationLossyCompressionQuality: 0.75] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return (out as Data, alpha ? "png" : "jpg")
    }

    /// Saves a preview (small) and returns its file name.
    func storePreview(_ image: CGImage) -> String? {
        guard let (data, ext) = Self.previewData(from: image) else { return nil }
        return storeImageData(data, ext: ext)
    }

    /// Once: shrinks previews saved before they were kept small. Runs in the background.
    func shrinkOldPreviews() {
        let marker = dataDir.appendingPathComponent("previews-v2")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        // Only link and file previews — a picture's imageFile can be the picture itself.
        let previews = Array(Set(items.filter { $0.kind == .link || $0.kind == .file }.compactMap(\.imageFile)))
        let dir = imagesDir
        DispatchQueue.global(qos: .utility).async {
            var renamed: [String: String] = [:]
            for name in previews {
                let url = dir.appendingPathComponent(name)
                guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize, size > 80_000,
                      let source = CGImageSourceCreateWithURL(url as CFURL, nil),
                      let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
                      let (data, ext) = Store.previewData(from: image), data.count < size else { continue }
                let newName = UUID().uuidString + "." + ext
                guard (try? data.write(to: dir.appendingPathComponent(newName))) != nil else { continue }
                renamed[name] = newName
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let store = Store.shared
                    for index in store.items.indices {
                        if let old = store.items[index].imageFile, let new = renamed[old] { store.items[index].imageFile = new }
                    }
                    if !renamed.isEmpty { store.save() }
                    for old in renamed.keys { try? FileManager.default.removeItem(at: dir.appendingPathComponent(old)) }
                    FileManager.default.createFile(atPath: marker.path, contents: Data())
                }
            }
        }
    }

    /// Temporary copies from drags and Quick Look, generated link notes — none are needed after a restart.
    nonisolated static func removeTemporaryFiles() {
        for name in ["StashOut", "StashDrag"] { try? FileManager.default.removeItem(at: TestMode.temp(name)) }
    }

    /// The downloader is used straight from inside Stash; a second copy is only made when you update it.
    /// An earlier, identical copy in Application Support is removed (it was 35 MB).
    nonisolated static func removeDuplicateDownloader() {
        let fm = FileManager.default
        let installed = Converter.updatedYtdlp
        guard let bundled = Converter.bundledTools?.appendingPathComponent("yt-dlp"),
              fm.fileExists(atPath: installed.path), fm.fileExists(atPath: bundled.path),
              fm.contentsEqual(atPath: installed.path, andPath: bundled.path) else { return }
        try? fm.removeItem(at: installed)
    }
}

// MARK: - Storage report

struct StorageReport {
    struct Row: Identifiable { var id: String { name }; let name: String; let detail: String; let bytes: Int64 }
    var rows: [Row] = []
    var total: Int64 { rows.reduce(0) { $0 + $1.bytes } }
    var oldLibrary: Int64 = 0
    var updatedDownloader: Int64 = 0
    /// Linked files: their originals' size (not stored by Stash, so not in the total), how many, and how many are missing.
    var linkedBytes: Int64 = 0
    var linkedCount = 0
    var linkedMissing = 0

    nonisolated static func size(of url: URL, skipping skip: Set<String> = []) -> Int64 {
        let fm = FileManager.default
        var isDir: ObjCBool = false
        guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { return 0 }
        if !isDir.boolValue { return Int64((try? url.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0) }
        var total: Int64 = 0
        guard let walker = fm.enumerator(at: url, includingPropertiesForKeys: [.totalFileAllocatedSizeKey, .isDirectoryKey]) else { return 0 }
        for case let file as URL in walker {
            if skip.contains(file.lastPathComponent) { walker.skipDescendants(); continue }
            total += Int64((try? file.resourceValues(forKeys: [.totalFileAllocatedSizeKey]))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }

    nonisolated static func measure(root: URL, data: URL, bundle: URL?, linked: [URL] = []) -> StorageReport {
        let support = TestMode.supportDir
        var report = StorageReport()
        report.rows = [
            Row(name: "Your files", detail: "Projects and folders, as real files", bytes: size(of: root, skipping: [".stash"])),
            Row(name: "Previews", detail: "Small pictures for links and files", bytes: size(of: data.appendingPathComponent("previews"))),
            Row(name: "Recently Deleted", detail: "Kept 30 days", bytes: size(of: data.appendingPathComponent("trash"))),
            Row(name: "Frame", detail: "Pictures and files on the Frame's canvas", bytes: size(of: data.appendingPathComponent("canvas"))),
            Row(name: "Library and backups", detail: "library.json, the previous version, hourly backups",
                bytes: size(of: data.appendingPathComponent("library.json")) + size(of: data.appendingPathComponent("library.prev.json"))
                    + size(of: data.appendingPathComponent("backups"))),
            Row(name: "Recent", detail: "What you copied and screenshotted lately (temporary)", bytes: size(of: data.appendingPathComponent("recent"))),
            Row(name: "Temporary", detail: "Copies for drags, files on their way in", bytes: size(of: TestMode.temp("StashOut"))
                + size(of: TestMode.temp("StashDrag")) + size(of: data.appendingPathComponent("incoming"))
                + size(of: data.appendingPathComponent("staging"))),
            Row(name: "Built-in tools", detail: "Downloader and MP3 encoder (inside the app)", bytes: bundle.map { size(of: $0) } ?? 0),
        ]
        report.updatedDownloader = size(of: support.appendingPathComponent("tools"))
        for url in linked {
            report.linkedCount += 1
            if FileManager.default.fileExists(atPath: url.path) { report.linkedBytes += BigFiles.size(of: url) } else { report.linkedMissing += 1 }
        }
        report.oldLibrary = size(of: support.appendingPathComponent("library.json")) + size(of: support.appendingPathComponent("images"))
        return report
    }
}

/// Settings → Storage: what Stash uses on disk, and safe ways to free some.
struct StorageSettings: View {
    @EnvironmentObject var store: Store
    @State private var report: StorageReport?
    @State private var message: String?

    var body: some View {
        Section {
            if let report {
                ForEach(report.rows) { row in
                    LabeledContent {
                        Text(Self.bytes(row.bytes)).monospacedDigit().foregroundStyle(.secondary)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.name)
                            Text(row.detail).font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                if report.updatedDownloader > 0 {
                    LabeledContent("Updated downloader") { Text(Self.bytes(report.updatedDownloader)).foregroundStyle(.secondary) }
                }
                LabeledContent { Text(Self.bytes(report.total + report.updatedDownloader)).monospacedDigit().bold() } label: { Text("Total").bold() }
                if report.linkedCount > 0 {
                    LabeledContent {
                        Text(Self.bytes(report.linkedBytes)).monospacedDigit().foregroundStyle(.tertiary)
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Linked files (not stored by Swiss)")
                            Text("\(report.linkedCount) big file\(report.linkedCount == 1 ? "" : "s") shown from where they are" + (report.linkedMissing > 0 ? " · \(report.linkedMissing) not found right now" : "") + " — not in the total")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                }
                HStack {
                    Button("Clear Temporary Files") {
                        Store.removeTemporaryFiles()
                        try? FileManager.default.removeItem(at: store.dataDir.appendingPathComponent("staging"))
                        done("Temporary files cleared")
                    }
                    Button("Empty Recently Deleted…") { store.showingRecentlyDeleted = true }
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([store.rootDir]) }
                }
                if report.oldLibrary > 0 {
                    HStack {
                        Text("Old library from an earlier Swiss version: \(Self.bytes(report.oldLibrary))")
                            .font(.system(size: 11)).foregroundStyle(.secondary)
                        Spacer()
                        Button("Move to Trash") { trashOldLibrary() }
                    }
                }
                if let message { Text(message).font(.system(size: 11)).foregroundStyle(.secondary) }
            } else {
                ProgressView().controlSize(.small)
            }
        } header: {
            Label("Storage", systemImage: "internaldrive")
        } footer: {
            Text("Previews are kept small automatically and temporary copies are removed at each launch. Clearing never touches your own files.")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
        .task { await refresh() }
    }

    private func refresh() async {
        let root = store.rootDir, data = store.dataDir, bundle = Converter.bundledTools
        let linked: [URL] = store.items.compactMap { item in
            switch store.fileState(item) {
            case .linked(let url)?, .missing(let url)?: url
            default: nil
            }
        }
        report = await Task.detached { StorageReport.measure(root: root, data: data, bundle: bundle, linked: linked) }.value
    }

    private func done(_ text: String) {
        message = text
        Task { await refresh() }
    }

    /// The library from before Stash moved to Documents (copied over long ago). Goes to the macOS Trash.
    private func trashOldLibrary() {
        let support = TestMode.supportDir
        for name in ["library.json", "images"] {
            try? FileManager.default.trashItem(at: support.appendingPathComponent(name), resultingItemURL: nil)
        }
        done("Old library moved to the Trash")
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }
}
