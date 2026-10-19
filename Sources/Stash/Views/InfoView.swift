import AppKit
import AVFoundation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Get Info (⌘I)

/// Like Finder's Get Info: name, size, kind, where it is, dates, tags and a preview.
struct InfoView: View {
    @EnvironmentObject var store: Store
    let target: Selectable
    @State private var facts = InfoFacts()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                header
                section("Tags") {
                    HStack(spacing: 6) {
                        ForEach(TagColor.allCases) { tag in
                            let on = store.tags(of: target).contains(tag)
                            Button { store.toggleTag(tag, on: [target]) } label: {
                                Circle().fill(tag.color)
                                    .frame(width: 14, height: 14)
                                    .overlay(Circle().strokeBorder(Color.primary.opacity(on ? 0.7 : 0), lineWidth: 2).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .help(on ? "Remove \(tag.title)" : tag.title)
                        }
                    }
                    .padding(.leading, 4)
                }
                section("General") {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 8, verticalSpacing: 4) {
                        row("Kind", facts.kind)
                        row("Size", facts.sizeDetail)
                        row("Where", stashPath)
                        if let link = facts.link { row("Link", link) }
                        if let dims = facts.dimensions { row("Dimensions", dims) }
                        if let duration = facts.duration { row("Duration", duration) }
                        row("Added", long(facts.created))
                        if let modified = facts.modified { row("Modified", long(modified)) }
                    }
                    if facts.fileURL != nil {
                        Button("Show in Finder") { if let url = facts.fileURL { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                            .controlSize(.small)
                            .padding(.top, 8)
                    }
                }
                section("Preview") { preview.frame(maxWidth: .infinity) }
            }
            .padding(14)
        }
        .frame(minWidth: 320, minHeight: 420)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear(perform: load)
        .onReceive(store.objectWillChange) { DispatchQueue.main.async(execute: load) }
    }

    // MARK: Parts

    private var header: some View {
        HStack(alignment: .top, spacing: 10) {
            icon.frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 2) {
                Text(facts.name).font(.system(size: 14, weight: .semibold)).lineLimit(2)
                if let modified = facts.modified ?? Optional(facts.created) {
                    Text("Modified: \(short(modified))").font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 4)
            Text(facts.size).font(.system(size: 13, weight: .semibold))
        }
        .padding(.bottom, 10)
    }

    @ViewBuilder private var icon: some View {
        switch target {
        case .folder(let id): FolderIcon(style: store.folder(id)?.style ?? .classic, size: 38)
        case .item(let id):
            if let item = store.items.first(where: { $0.id == id }), let image = store.displayImageNow(item) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 38, height: 38).clipShape(RoundedRectangle(cornerRadius: 5))
            } else if store.items.first(where: { $0.id == id })?.kind == .text {
                NotePadIcon(size: 34)
            } else {
                Image(systemName: "doc").font(.system(size: 28)).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var preview: some View {
        switch target {
        case .folder(let id): FolderIcon(style: store.folder(id)?.style ?? .classic, size: 120).padding(.vertical, 8)
        case .item(let id):
            if let item = store.items.first(where: { $0.id == id }) {
                if let image = store.displayImageNow(item) {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                        .frame(maxHeight: 220).clipShape(RoundedRectangle(cornerRadius: 6))
                } else if let text = item.text, !text.isEmpty {
                    Text(text).font(.system(size: 12)).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(Color(red: 1, green: 0.93, blue: 0.6).opacity(0.35), in: RoundedRectangle(cornerRadius: 6))
                } else {
                    Image(systemName: "doc").font(.system(size: 60, weight: .light)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider()
            Text(title + ":").font(.system(size: 12, weight: .semibold))
            content()
        }
        .padding(.bottom, 10)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label + ":").font(.system(size: 11.5)).foregroundStyle(.secondary).gridColumnAlignment(.trailing)
            Text(value).font(.system(size: 11.5)).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// Project ▸ Folder ▸ Folder, as you see it in Stash.
    private var stashPath: String {
        let project: UUID?, folderID: UUID?
        switch target {
        case .folder(let id): (project, folderID) = (store.folder(id)?.projectID, store.folder(id)?.parentID)
        case .item(let id):
            let item = store.items.first { $0.id == id }
            (project, folderID) = (item?.projectID, item?.folderID)
        }
        var parts = [project.flatMap { id in store.projects.first { $0.id == id }?.name } ?? "Not Selected"]
        if let folderID {
            parts += store.ancestors(of: folderID).map(\.name)
            if let f = store.folder(folderID) { parts.append(f.name) }
        }
        return parts.joined(separator: " ▸ ")
    }

    private func long(_ date: Date) -> String { date.formatted(date: .complete, time: .shortened) }
    private func short(_ date: Date) -> String { date.formatted(.relative(presentation: .named)) }

    private func load() { facts = InfoFacts(target, store: store) }
}

/// Everything Get Info shows, read from Stash and the real file in Documents.
struct InfoFacts {
    var name = ""
    var kind = ""
    var size = "–"
    var sizeDetail = "–"
    var created = Date()
    var modified: Date?
    var link: String?
    var dimensions: String?
    var duration: String?
    var fileURL: URL?

    init() {}

    @MainActor init(_ target: Selectable, store: Store) {
        let fm = FileManager.default
        switch target {
        case .folder(let id):
            guard let folder = store.folder(id) else { return }
            name = folder.name
            kind = folder.style.isKind ? "\(folder.style.name) folder" : "Folder"
            created = folder.createdAt
            fileURL = store.mirrorDirs["f:" + id.uuidString].map(store.absolute)
            let count = store.count(in: folder) + store.subfolderCount(in: folder)
            if let url = fileURL {
                modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                let bytes = Self.folderSize(url)
                size = Self.bytes(bytes)
                sizeDetail = "\(bytes.formatted()) bytes (\(size)) for \(count) item\(count == 1 ? "" : "s")"
            } else {
                sizeDetail = "\(count) item\(count == 1 ? "" : "s")"
            }
        case .item(let id):
            guard let item = store.items.first(where: { $0.id == id }) else { return }
            created = item.createdAt
            fileURL = item.storedPath.map(store.absolute).flatMap { fm.fileExists(atPath: $0.path) ? $0 : nil }
                ?? (item.kind == .image || item.kind == .file ? store.contentURL(item) : nil)
            switch item.kind {
            case .text:
                name = item.displayTitle.isEmpty ? "Note" : item.displayTitle
                let words = (item.text ?? "").split { $0.isWhitespace }.count
                kind = item.richText == nil ? "Note (plain text)" : "Note (rich text)"
                link = nil
                sizeDetail = "\(words) word\(words == 1 ? "" : "s"), \((item.text ?? "").count) characters"
            case .link:
                name = item.displayTitle
                kind = "Link — \(item.host)"
                link = item.url
            case .image, .file:
                name = item.title ?? fileURL?.lastPathComponent ?? "File"
                kind = fileURL.flatMap { (try? $0.resourceValues(forKeys: [.contentTypeKey]))?.contentType?.localizedDescription }
                    ?? (item.kind == .image ? "Image" : "File")
                if let source = item.sourceURL { link = source }
            }
            if let url = fileURL, let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]) {
                modified = values.contentModificationDate
                if let bytes = values.fileSize {
                    size = Self.bytes(Int64(bytes))
                    if item.kind != .text { sizeDetail = "\(bytes.formatted()) bytes (\(size))" }
                }
            }
            if item.kind == .image, let image = fileURL.flatMap({ NSImageRep(contentsOf: $0) }) {
                dimensions = "\(image.pixelsWide) × \(image.pixelsHigh)"
            }
            if let url = fileURL, let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
               type.conforms(to: .audiovisualContent) {
                let seconds = CMTimeGetSeconds(AVURLAsset(url: url).duration)
                if seconds.isFinite, seconds > 0 {
                    duration = Duration.seconds(seconds).formatted(.time(pattern: seconds >= 3600 ? .hourMinuteSecond : .minuteSecond))
                }
                if let track = AVURLAsset(url: url).tracks(withMediaType: .video).first {
                    let s = track.naturalSize.applying(track.preferredTransform)
                    dimensions = "\(Int(abs(s.width))) × \(Int(abs(s.height)))"
                }
            }
        }
    }

    static func bytes(_ n: Int64) -> String { ByteCountFormatter.string(fromByteCount: n, countStyle: .file) }

    static func folderSize(_ url: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
        }
        return total
    }
}

// MARK: - Window

extension AppDelegate {
    /// ⌘I: a small Info window for each selected thing (up to five), like Finder.
    func showInfo(for targets: Set<Selectable>) {
        let store = Store.shared
        let ordered = store.visibleOrder.filter(targets.contains) + targets.filter { !store.visibleOrder.contains($0) }
        guard !ordered.isEmpty else { NSSound.beep(); return }
        for (index, target) in ordered.prefix(5).enumerated() {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 520),
                                 styleMask: [.titled, .closable, .resizable, .nonactivatingPanel, .utilityWindow], backing: .buffered, defer: false)
            let facts = InfoFacts(target, store: store)
            window.title = "\(facts.name) Info"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1) // above the menu bar preview
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: InfoView(target: target).environmentObject(store))
            window.center()
            window.setFrameOrigin(NSPoint(x: window.frame.minX + CGFloat(index) * 24, y: window.frame.minY - CGFloat(index) * 24))
            infoWindows.append(window)
            window.makeKeyAndOrderFront(nil)
        }
        infoWindows.removeAll { !$0.isVisible }
        NSApp.activate()
    }
}
