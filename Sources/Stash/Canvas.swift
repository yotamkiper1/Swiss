import AppKit
@preconcurrency import LinkPresentation
import SwiftUI
import UniformTypeIdentifiers

// MARK: - The Frame: a free canvas

/// The Frame (the window that stays on top of every app) is its own tool: a free canvas, like a Miro board, separate
/// from projects. Put photos, notes, links, videos (a YouTube link plays right there) and files anywhere; move around
/// it, zoom in and out, resize things, clear it all. Saved on its own (canvas.json and a folder for its files).
struct CanvasItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable { case image, text, link, video, file }
    var id = UUID()
    var kind: Kind
    /// Place and size on the canvas, in canvas points (zoom 100 %).
    var x: Double
    var y: Double
    var width: Double
    var height: Double
    /// A note's text, or a link's title.
    var text: String?
    /// A link or web video's address, or the original file of something linked (not copied).
    var url: String?
    /// The file in the canvas's own folder (pictures, and files cloned in).
    var asset: String?
    var z: Int = 0
    /// A name you gave it (right-click → Name…), shown under it.
    var name: String?
    /// A note's text size (canvas points), set once it's resized: the text grows and shrinks with the note.
    var fontSize: Double?
    /// Text you copied and pasted in: shown as a white quote card, not a yellow note.
    var quote: Bool?
    /// A link showing its web page, live, right on the canvas (Show Page Here).
    var page: Bool?

    /// A note's text size: what resizing made it, or (never resized) the size notes always had for their width.
    var textSize: Double { fontSize ?? 13 * min(3, max(0.7, width / 200)) }

    var frame: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var link: URL? { url.flatMap(URL.init(string:)) }
    var showsPage: Bool { kind == .link && page == true && link.map(Safety.isWebURL) == true }
}

private struct CanvasFile: Codable {
    var items: [CanvasItem]
    var zoom: Double
    var panX: Double
    var panY: Double
}

@MainActor
final class CanvasStore: ObservableObject {
    static let shared = CanvasStore()

    @Published private(set) var items: [CanvasItem] = []
    @Published var zoom: Double = 1
    /// Where the canvas's (0, 0) is in the view.
    @Published var pan: CGSize = .zero
    @Published var selection: Set<UUID> = []
    @Published var editingID: UUID?
    /// What Clear took away (Undo brings it back for a little while).
    @Published private(set) var cleared: [CanvasItem]?
    @Published var clearArmed = false

    /// When the mouse went down (seconds since startup).
    var pressTime: TimeInterval = 0

    /// What dragging on empty space does: draw a selection box (Select, V) or move around the canvas (Hand, H).
    enum Tool: String { case select, hand }
    @Published var tool: Tool = Tool(rawValue: UserDefaults.standard.string(forKey: "canvas.tool") ?? "") ?? .select {
        didSet { UserDefaults.standard.set(tool.rawValue, forKey: "canvas.tool") }
    }

    /// The canvas area's size, and its top-left in the window (top-left based), set by the view.
    var viewSize: CGSize = CGSize(width: 380, height: 480)
    var viewOrigin: CGPoint = .zero

    static let minZoom = 0.2, maxZoom = 4.0

    private var dir: URL { Store.shared.dataDir.appendingPathComponent("canvas", isDirectory: true) }
    private var file: URL { Store.shared.dataDir.appendingPathComponent("canvas.json") }
    private var saveWork: DispatchWorkItem?

    init() { load() }

    // MARK: Saving

    private func load() {
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        guard let data = try? Data(contentsOf: file), let saved = try? JSONDecoder().decode(CanvasFile.self, from: data) else { return }
        items = saved.items
        zoom = min(Self.maxZoom, max(Self.minZoom, saved.zoom))
        pan = CGSize(width: saved.panX, height: saved.panY)
        // Files left over from a Clear that Swiss quit during (before its Undo time was up): not needed any more.
        let used = Set(items.compactMap(\.asset))
        for name in (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? [] where !used.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    /// Saved a moment after the last change (dragging doesn't write on every move), off the main thread.
    func save() {
        WebPages.shared.keepOnly(Set(items.filter(\.showsPage).map(\.id))) // a page whose card went is closed
        saveWork?.cancel()
        let snapshot = CanvasFile(items: items, zoom: zoom, panX: pan.width, panY: pan.height)
        let file = file
        let work = DispatchWorkItem {
            DispatchQueue.global(qos: .utility).async {
                if let data = try? JSONEncoder().encode(snapshot) { try? data.write(to: file, options: .atomic) }
            }
        }
        saveWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    func flush() {
        saveWork?.perform()
        saveWork = nil
    }

    // MARK: Files

    /// The file behind a picture, video or file: its copy in the canvas folder, or the original it links to.
    func fileURL(_ item: CanvasItem) -> URL? {
        if let asset = item.asset { return dir.appendingPathComponent(asset) }
        if let link = item.link, link.isFileURL { return link }
        return nil
    }

    // MARK: Coordinates

    /// A point in the view → the same point on the canvas.
    func canvasPoint(_ p: CGPoint) -> CGPoint {
        CGPoint(x: (p.x - pan.width) / zoom, y: (p.y - pan.height) / zoom)
    }

    var visibleCenter: CGPoint { canvasPoint(CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)) }

    func viewFrame(_ item: CanvasItem) -> CGRect {
        CGRect(x: item.x * zoom + pan.width, y: item.y * zoom + pan.height, width: item.width * zoom, height: item.height * zoom)
    }

    // MARK: Moving around

    func setZoom(_ value: Double, around viewPoint: CGPoint? = nil) {
        let new = min(Self.maxZoom, max(Self.minZoom, value))
        guard new != zoom else { return }
        let p = viewPoint ?? CGPoint(x: viewSize.width / 2, y: viewSize.height / 2)
        // The point under the pointer (or the middle) stays where it is.
        pan = CGSize(width: p.x - (p.x - pan.width) * new / zoom, height: p.y - (p.y - pan.height) * new / zoom)
        zoom = new
        save()
    }

    func zoom(by factor: Double, around viewPoint: CGPoint? = nil) { setZoom(zoom * factor, around: viewPoint) }

    func panBy(_ delta: CGSize) {
        pan = CGSize(width: pan.width + delta.width, height: pan.height + delta.height)
        save()
    }

    /// Everything in view (or back to 100 % at the start if it's empty).
    func fitAll() {
        guard let first = items.first else { zoom = 1; pan = .zero; save(); return }
        let bounds = items.dropFirst().reduce(first.frame) { $0.union($1.frame) }.insetBy(dx: -30, dy: -30)
        let fit = Double(min(viewSize.width / bounds.width, viewSize.height / bounds.height))
        let z = min(Self.maxZoom, max(Self.minZoom, fit))
        zoom = z
        let w = Double(viewSize.width), h = Double(viewSize.height)
        pan = CGSize(width: (w - Double(bounds.width) * z) / 2 - Double(bounds.minX) * z,
                     height: (h - Double(bounds.height) * z) / 2 - Double(bounds.minY) * z)
        save()
    }

    // MARK: Changing things

    private var topZ: Int { (items.map(\.z).max() ?? 0) + 1 }

    /// The free place closest to a point (searching outward in rings), with a little room around everything.
    private func freeSpot(near center: CGPoint, size: CGSize) -> CGPoint {
        let taken = items.map { $0.frame.insetBy(dx: -12, dy: -12) }
        let start = CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2)
        func free(_ p: CGPoint) -> Bool { !taken.contains { $0.intersects(CGRect(origin: p, size: size)) } }
        if free(start) { return start }
        let step: CGFloat = 24
        for ring in 1...60 {
            let r = CGFloat(ring) * step
            var best: CGPoint?
            var bestDistance = CGFloat.infinity
            for i in 0..<(ring * 8) {
                let angle = CGFloat(i) / CGFloat(ring * 8) * 2 * .pi
                let p = CGPoint(x: start.x + cos(angle) * r, y: start.y + sin(angle) * r)
                if free(p), hypot(p.x - start.x, p.y - start.y) < bestDistance { best = p; bestDistance = hypot(p.x - start.x, p.y - start.y) }
            }
            if let best { return best }
        }
        return start
    }

    // MARK: Undo

    /// The canvas before each change (⌘Z), and what ⌘Z took back (⇧⌘Z). Quick runs of changes — typing, a few
    /// nudges — count as one step.
    private var history: [[CanvasItem]] = []
    private var future: [[CanvasItem]] = []
    private var lastRemembered: TimeInterval = 0

    func remember() {
        let now = ProcessInfo.processInfo.systemUptime
        defer { lastRemembered = now }
        if now - lastRemembered < 0.35, !history.isEmpty { return }
        history.append(items)
        if history.count > 100 { history.removeFirst() }
        future = []
    }

    @discardableResult
    func undo() -> Bool { step(from: &history, to: &future) }

    @discardableResult
    func redo() -> Bool { step(from: &future, to: &history) }

    private func step(from: inout [[CanvasItem]], to: inout [[CanvasItem]]) -> Bool {
        guard let back = from.popLast() else { return false }
        to.append(items)
        items = back
        selection = selection.intersection(Set(back.map(\.id)))
        editingID = nil
        cleared = nil
        lastRemembered = 0
        save()
        return true
    }

    @discardableResult
    func add(_ kind: CanvasItem.Kind, at point: CGPoint? = nil, size: CGSize, text: String? = nil, url: String? = nil, asset: String? = nil) -> UUID {
        remember()
        let center = point ?? visibleCenter
        // Dropped somewhere: right there. Pasted or added: the nearest free spot to the middle, so nothing lands on top.
        let origin = point != nil ? CGPoint(x: center.x - size.width / 2, y: center.y - size.height / 2) : freeSpot(near: center, size: size)
        let item = CanvasItem(kind: kind, x: origin.x, y: origin.y,
                              width: size.width, height: size.height, text: text, url: url, asset: asset, z: topZ)
        items.append(item)
        selection = [item.id]
        cleared = nil
        save()
        return item.id
    }

    func update(_ id: UUID, undoable: Bool = true, _ change: (inout CanvasItem) -> Void) {
        guard let i = items.firstIndex(where: { $0.id == id }) else { return }
        var next = items[i]
        change(&next)
        guard next != items[i] else { return }
        if undoable { remember() }
        items[i] = next
        save()
    }

    func move(_ ids: Set<UUID>, by delta: CGSize) {
        remember()
        for i in items.indices where ids.contains(items[i].id) {
            items[i].x += delta.width
            items[i].y += delta.height
        }
        save()
    }

    func resize(_ id: UUID, to size: CGSize, keepAspect: Bool) {
        update(id) { item in
            var w = max(40, size.width), h = max(30, size.height)
            if keepAspect, item.width > 0 { h = w * item.height / item.width }
            if item.kind == .text, item.width > 0 { item.fontSize = item.textSize * w / item.width } // the text grows with it
            item.width = w
            item.height = h
        }
    }

    /// Bigger or smaller by a step (keeps its shape and its middle where it is).
    func scale(_ ids: Set<UUID>, by factor: Double) {
        remember()
        for i in items.indices where ids.contains(items[i].id) {
            let w = max(40, items[i].width * factor), h = max(30, items[i].height * factor)
            if items[i].kind == .text, items[i].width > 0 { items[i].fontSize = items[i].textSize * w / items[i].width }
            items[i].x += (items[i].width - w) / 2
            items[i].y += (items[i].height - h) / 2
            items[i].width = w
            items[i].height = h
        }
        save()
    }

    /// Show Page Here / Show as Link. A page gets room to be read (and keeps the card's corner where it was).
    func togglePage(_ id: UUID) {
        update(id) { item in
            guard item.kind == .link else { return }
            if item.page == true {
                item.page = nil
                item.width = 240
                item.height = 58
            } else {
                item.page = true
                item.width = max(item.width, 720)
                item.height = max(item.height, 480)
            }
        }
        bringToFront(id)
    }

    func bringToFront(_ id: UUID) {
        let z = topZ
        update(id, undoable: false) { $0.z = z } // coming to the front isn't a step to undo
    }

    func delete(_ ids: Set<UUID>) {
        let gone = items.filter { ids.contains($0.id) }
        guard !gone.isEmpty else { return }
        DeleteSound.play()
        remember()
        items.removeAll { ids.contains($0.id) }
        selection.subtract(ids)
        save() // its files stay until Swiss next starts, so ⌘Z can bring it back
    }

    /// Clear: everything goes; Undo brings it back for 10 seconds, then its files are removed.
    func clear() {
        guard !items.isEmpty else { return }
        DeleteSound.play()
        lastRemembered = 0
        remember()
        cleared = items
        items = []
        selection = []
        editingID = nil
        clearArmed = false
        save()
        let snapshot = cleared
        DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            MainActor.assumeIsolated {
                // The Undo Clear button goes; ⌘Z still brings it back (files are tidied when Swiss next starts).
                guard let self = Optional(CanvasStore.shared), self.cleared == snapshot else { return }
                self.cleared = nil
            }
        }
    }

    func undoClear() {
        guard let back = cleared else { return }
        remember()
        items = back + items
        cleared = nil
        save()
    }

    private func removeFiles(of gone: [CanvasItem]) {
        let stillUsed = Set(items.compactMap(\.asset))
        for name in gone.compactMap(\.asset) where !stillUsed.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    // MARK: Bringing things in

    /// Drops and pastes: files, pictures, links (a YouTube link becomes a player), text. At the point given (on the canvas).
    @discardableResult
    func ingest(_ pb: NSPasteboard, at point: CGPoint? = nil) -> Bool {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach { addFile($0, at: point) }
            return true
        }
        let web = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first { Safety.isWebURL($0) }
        if let web, CanvasStore.youTubeID(web) != nil {
            addLink(web, at: point)
            return true
        }
        if case let (data, ext)? = Store.imageData(in: pb) {
            addImageData(data, ext: ext, at: point)
            return true
        }
        if let web {
            addLink(web, at: point)
            return true
        }
        if let string = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty {
            // Copied text comes in as a quote; a note from the library (its double-click) stays a note.
            if let url = Store.webURL(from: string) { addLink(url, at: point) } else {
                addText(string, at: point, quote: !pb.name.rawValue.hasPrefix("swiss.canvas.library"))
            }
            return true
        }
        return false
    }

    func addText(_ text: String, at point: CGPoint? = nil, quote: Bool = false) {
        let lines = max(1, min(12, text.count / 28 + text.filter { $0 == "\n" }.count + 1))
        // A quote has a line more on top, for its quote mark.
        let id = add(.text, at: point, size: CGSize(width: 200, height: 26 + Double(lines) * 17 + (quote ? 18 : 0)), text: text)
        if quote, let i = items.firstIndex(where: { $0.id == id }) { items[i].quote = true }
    }

    func newNote() {
        let id = add(.text, size: CGSize(width: 200, height: 90), text: "")
        editingID = id
    }

    func addLink(_ url: URL, at point: CGPoint? = nil) {
        if CanvasStore.youTubeID(url) != nil {
            add(.video, at: point, size: CGSize(width: 320, height: 180), url: url.absoluteString)
            return
        }
        let id = add(.link, at: point, size: CGSize(width: 240, height: 58), text: url.host, url: url.absoluteString)
        // The page's title, when it arrives.
        nonisolated(unsafe) let provider = LPMetadataProvider() // only kept alive by the closure, never used from it
        provider.timeout = 10
        provider.startFetchingMetadata(for: url) { metadata, _ in
            _ = provider
            guard let title = metadata?.title, !title.isEmpty else { return }
            Task { @MainActor in CanvasStore.shared.update(id) { $0.text = String(title.prefix(300)) } }
        }
    }

    private func addImageData(_ data: Data, ext: String, at point: CGPoint?) {
        let name = UUID().uuidString + "." + (ext.isEmpty ? "png" : ext)
        guard (try? data.write(to: dir.appendingPathComponent(name))) != nil else { return }
        let size = NSImage(data: data)?.size ?? CGSize(width: 240, height: 180)
        add(.image, at: point, size: Self.fit(size, within: 260), asset: name)
    }

    /// Files: pictures and videos show themselves, anything else as its icon. Brought in as an instant clone on the
    /// same disk (no extra space); big files from another disk stay where they are, linked.
    private func addFile(_ url: URL, at point: CGPoint?) {
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType
        let isImage = type?.conforms(to: .image) ?? false
        let isVideo = type?.conforms(to: .movie) ?? false
        let link = !BigFiles.sameVolume(url, dir) && BigFiles.isBig(url)
        var asset: String?
        if !link {
            let name = UUID().uuidString + (url.pathExtension.isEmpty ? "" : "." + url.pathExtension)
            if copyfile(url.path, dir.appendingPathComponent(name).path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)) == 0 { asset = name }
        }
        let original = asset == nil ? url.absoluteString : nil
        if isImage {
            let pixels = CGImageSourceCreateWithURL(url as CFURL, nil).flatMap { CGImageSourceCopyPropertiesAtIndex($0, 0, nil) as? [CFString: Any] }
            let w = pixels?[kCGImagePropertyPixelWidth] as? Double ?? 240, h = pixels?[kCGImagePropertyPixelHeight] as? Double ?? 180
            add(.image, at: point, size: Self.fit(CGSize(width: w, height: h), within: 260), url: original, asset: asset)
        } else if isVideo {
            add(.video, at: point, size: CGSize(width: 320, height: 180), text: url.lastPathComponent, url: original, asset: asset)
        } else {
            add(.file, at: point, size: CGSize(width: 110, height: 110), text: url.lastPathComponent, url: original, asset: asset)
        }
    }

    private static func fit(_ size: CGSize, within side: Double) -> CGSize {
        guard size.width > 0, size.height > 0 else { return CGSize(width: side, height: side * 0.75) }
        let s = min(1, side / max(size.width, size.height))
        return CGSize(width: size.width * s, height: size.height * s)
    }

    /// The video id in a YouTube link (watch?v=, youtu.be/, shorts/, embed/, live/).
    nonisolated static func youTubeID(_ url: URL) -> String? {
        guard let host = url.host?.lowercased() else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        var id: String?
        if host.hasSuffix("youtu.be") {
            id = parts.first
        } else if host.hasSuffix("youtube.com") || host.hasSuffix("youtube-nocookie.com") {
            if let v = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "v" })?.value {
                id = v
            } else if parts.count >= 2, ["shorts", "embed", "live", "v"].contains(parts[0]) {
                id = parts[1]
            }
        }
        // Only the characters a YouTube id has (so nothing else ends up in the player's address).
        guard let id, (6...20).contains(id.count), id.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }) else { return nil }
        return id
    }

    // MARK: Copying out

    func copySelection() {
        let chosen = items.filter { selection.contains($0.id) }
        guard !chosen.isEmpty else { NSSound.beep(); return }
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = []
        var texts: [String] = []
        for item in chosen {
            switch item.kind {
            case .text: texts.append(item.text ?? "")
            case .link: if let url = item.link { objects.append(url as NSURL) }
            case .video, .image, .file:
                if let file = fileURL(item) { objects.append(Store.handOut(file) as NSURL) } else if let url = item.link { objects.append(url as NSURL) }
            }
        }
        if !objects.isEmpty { pb.writeObjects(objects) }
        if !texts.isEmpty { pb.setString(texts.joined(separator: "\n\n"), forType: .string) }
        Store.shared.flash("Copied")
    }
}
