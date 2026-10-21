import AppKit
@preconcurrency import LinkPresentation
import QuickLookThumbnailing
import UniformTypeIdentifiers
import Vision

/// Turns whatever was dropped or pasted into library items.
extension Store {
    static let acceptedTypes: [NSPasteboard.PasteboardType] =
        [.fileURL, .URL, .png, .tiff, .string, .init("public.jpeg"), .init("public.heic"), .init("com.compuserve.gif"), .init("org.webmproject.webp")]
        + NSFilePromiseReceiver.readableDraggedTypes.map { NSPasteboard.PasteboardType($0) }

    static let imageExtensions: Set<String> = ["png", "jpg", "jpeg", "gif", "webp", "heic", "tiff", "tif", "bmp", "avif"]

    @discardableResult
    func ingest(_ pb: NSPasteboard, into place: Place) -> Bool {
        // Everything from one drop or paste is one undo step.
        var saved = false
        undoGroup("Add") { saved = ingestContents(pb, into: place) }
        return saved
    }

    private func ingestContents(_ pb: NSPasteboard, into place: Place) -> Bool {
        if pb == .general {
            clipboardSeenCount = pb.changeCount
            clipboardHint = nil
        }
        // 1. Files from Finder, the desktop, screenshots…
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            urls.forEach { addFile($0, place: place) }
            return true
        }

        let webURL = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }

        // 2. Raw image data (copied images, images dragged from Safari…)
        if case let (data, ext)? = Self.imageData(in: pb) {
            addImage(data: data, ext: ext, source: webURL, title: nil, place: place)
            return true
        }

        // 3. Promised files (images dragged out of Chrome and other apps)
        if let promises = pb.readObjects(forClasses: [NSFilePromiseReceiver.self], options: nil) as? [NSFilePromiseReceiver],
           !promises.isEmpty {
            receive(promises, source: webURL, place: place)
            return true
        }

        // 4. Links
        if let webURL {
            addLink(webURL, place: place)
            return true
        }

        // 5. Plain text
        if let string = pb.string(forType: .string), !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            addText(string, place: place)
            return true
        }
        return false
    }

    // MARK: Adding

    func addText(_ raw: String, place: Place) {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        if let url = Self.webURL(from: text) {
            addLink(url, place: place)
            return
        }
        var item = Item(kind: .text, projectID: place.project, folderID: place.folder)
        item.text = text
        item.tags = Self.tags(in: text)
        add(item)
    }

    func addLink(_ url: URL, place: Place) {
        if Self.imageExtensions.contains(url.pathExtension.lowercased()) {
            downloadImage(url, place: place)
        } else {
            addLinkItem(url, place: place)
        }
    }

    func addFile(_ url: URL, place: Place, source: URL? = nil) {
        let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
        // Pictures are cloned into Stash in the background — never read into memory here. Huge ones
        // (over the big-file limit, like a 300 MB camera RAW) are linked like other big files.
        if isImage, !BigFiles.isBig(url) {
            addImageFile(url, source: source, place: place)
            return
        }
        // Other files (videos, music, 3D models, PDFs…) get a Quick Look thumbnail and, unless
        // turned off in Settings or too big, a copy kept in Stash. Folders are saved as a reference.
        var item = Item(kind: .file, projectID: place.project, folderID: place.folder)
        item.url = url.absoluteString
        item.title = url.lastPathComponent
        item.bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        add(item)
        makeFileThumbnail(item.id, url)
        // (The mirror copies it into its folder in Documents — or links it, when it's big.)
    }

    /// A picture file: its card appears at once; the file is cloned in (instant on the same disk, streamed from
    /// another one) off the main thread, and only then read — at thumbnail size, and for text if it isn't huge.
    private func addImageFile(_ url: URL, source: URL?, place: Place) {
        let ext = url.pathExtension.lowercased()
        let name = UUID().uuidString + "." + (ext.isEmpty ? "png" : ext)
        var item = Item(kind: .image, projectID: place.project, folderID: place.folder)
        item.imageFile = name
        item.title = url.lastPathComponent
        item.sourceURL = source?.absoluteString
        add(item)
        let id = item.id
        let destination = fileURL(for: name)
        DispatchQueue.global(qos: .userInitiated).async {
            let ok = copyfile(url.path, destination.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_CLONE)) == 0
            let pixels = ok ? ThumbnailService.pixelCount(destination) : 0
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let store = Store.shared
                    guard ok else {
                        // Couldn't bring it in: keep it as a linked file instead.
                        store.update(id) { $0.kind = .file; $0.imageFile = nil; $0.url = url.absoluteString }
                        store.makeFileThumbnail(id, url)
                        return
                    }
                    ThumbnailService.shared.forget(destination)
                    store.save() // the mirror moves it into its folder now that it's here
                    if pixels <= 50_000_000 { store.recognizeText(id, at: destination) } // text search, unless it's enormous
                }
            }
        }
    }

    func addImage(data: Data, ext: String, source: URL?, title: String?, place: Place) {
        guard let name = storeImageData(data, ext: ext) else { return }
        if let source, Safety.isWebURL(source) { Safety.quarantine(fileURL(for: name), from: source) } // came from the web
        var item = Item(kind: .image, projectID: place.project, folderID: place.folder)
        item.imageFile = name
        item.title = title
        item.sourceURL = source?.absoluteString
        add(item)
        recognizeText(item.id, data)
    }

    private func addLinkItem(_ url: URL, place: Place) {
        var item = Item(kind: .link, projectID: place.project, folderID: place.folder)
        item.url = url.absoluteString
        add(item)
        fetchMetadata(item.id, url)
    }

    private func receive(_ promises: [NSFilePromiseReceiver], source: URL?, place: Place) {
        let dest = FileManager.default.temporaryDirectory.appendingPathComponent("StashDrop-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        for promise in promises {
            promise.receivePromisedFiles(atDestination: dest, options: [:], operationQueue: .main) { url, error in
                MainActor.assumeIsolated {
                    let store = Store.shared
                    let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
                    if error == nil, isImage {
                        store.addFile(url, place: place, source: source)
                    } else if let source {
                        store.addLink(source, place: place)
                    }
                }
            }
        }
    }

    // MARK: Background work

    private func downloadImage(_ url: URL, place: Place) {
        Task {
            if case let (data, response)? = try? await URLSession.shared.data(from: url),
               ((response as? HTTPURLResponse)?.statusCode ?? 200) < 400,
               NSImage(data: data) != nil {
                addImage(data: data, ext: url.pathExtension.lowercased(), source: url, title: nil, place: place)
            } else {
                addLinkItem(url, place: place)
            }
        }
    }

    private func fetchMetadata(_ id: UUID, _ url: URL) {
        nonisolated(unsafe) let provider = LPMetadataProvider() // only kept alive by the closure, never used from it
        provider.timeout = 15
        provider.startFetchingMetadata(for: url) { metadata, _ in
            _ = provider // keep the provider alive until it finishes
            guard let metadata else { return }
            let title = metadata.title
            Task { @MainActor in
                // At most 300 characters: a page can't fill the card with an endless title.
                Store.shared.update(id) { if let title, !title.isEmpty { $0.title = String(title.prefix(300)) } }
            }
            metadata.imageProvider?.loadObject(ofClass: NSImage.self) { object, _ in
                guard let cg = (object as? NSImage)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return }
                Task { @MainActor in
                    let store = Store.shared
                    if let name = store.storePreview(cg) {
                        store.update(id) { $0.imageFile = name }
                    }
                }
            }
        }
    }

    func makeThumbnail(for id: UUID, from url: URL) { makeFileThumbnail(id, url) }

    func makeFileThumbnail(_ id: UUID, _ url: URL) {
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 400, height: 400), scale: 2, representationTypes: .all)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { representation, _ in
            guard let cg = representation?.cgImage else { return }
            Task { @MainActor in
                let store = Store.shared
                if let name = store.storePreview(cg) {
                    store.update(id) { $0.imageFile = name }
                }
            }
        }
    }

    /// Reads text inside a picture file (one at a time, in the background) so it can be found by search.
    func recognizeText(_ id: UUID, at url: URL) {
        Self.ocrQueue.addOperation {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(url: url).perform([request])
            let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
            guard !text.isEmpty else { return }
            Task { @MainActor in Store.shared.update(id) { $0.ocrText = text } }
        }
    }

    static let ocrQueue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .utility
        q.name = "Swiss text recognition"
        return q
    }()

    /// Reads text inside images so they can be found by search.
    private func recognizeText(_ id: UUID, _ data: Data) {
        DispatchQueue.global(qos: .utility).async {
            let request = VNRecognizeTextRequest()
            request.recognitionLevel = .accurate
            request.automaticallyDetectsLanguage = true
            try? VNImageRequestHandler(data: data).perform([request])
            let text = (request.results ?? [])
                .compactMap { $0.topCandidates(1).first?.string }
                .joined(separator: " ")
            guard !text.isEmpty else { return }
            Task { @MainActor in Store.shared.update(id) { $0.ocrText = text } }
        }
    }

    // MARK: Helpers

    static func imageData(in pb: NSPasteboard) -> (Data, String)? {
        let types: [(String, String)] = [
            ("public.png", "png"), ("public.jpeg", "jpg"), ("com.compuserve.gif", "gif"),
            ("org.webmproject.webp", "webp"), ("public.heic", "heic"), ("public.tiff", "tiff"),
        ]
        for (type, ext) in types {
            guard let data = pb.data(forType: NSPasteboard.PasteboardType(type)) else { continue }
            if ext == "tiff", let png = NSBitmapImageRep(data: data)?.representation(using: .png, properties: [:]) {
                return (png, "png")
            }
            return (data, ext)
        }
        return nil
    }

    static func webURL(from string: String) -> URL? {
        guard !string.contains(where: \.isWhitespace) else { return nil }
        let candidate = string.lowercased().hasPrefix("www.") ? "https://" + string : string
        guard let url = URL(string: candidate),
              let scheme = url.scheme?.lowercased(), ["http", "https"].contains(scheme),
              url.host != nil else { return nil }
        return url
    }

    static func tags(in string: String) -> [String] {
        guard let regex = try? NSRegularExpression(pattern: "#([\\p{L}\\p{N}_-]+)") else { return [] }
        let ns = string as NSString
        var seen: [String] = []
        for match in regex.matches(in: string, range: NSRange(location: 0, length: ns.length)) {
            let tag = ns.substring(with: match.range(at: 1)).lowercased()
            if !seen.contains(tag) { seen.append(tag) }
        }
        return seen
    }

    // MARK: Getting items back out

    func open(_ item: Item) {
        switch item.kind {
        case .link:
            if let url = item.linkURL { Safety.openLink(url) }
        case .file:
            if let url = contentURL(item) ?? item.linkURL { Safety.open(url) } // apps and scripts are asked about first
        case .image:
            if let url = contentURL(item) { NSWorkspace.shared.open(url) }
        case .text:
            break
        }
    }

    func reveal(_ item: Item) {
        if let url = contentURL(item) ?? item.storedPath.map(absolute) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }

    func copy(_ item: Item) {
        let pb = NSPasteboard.general
        pb.clearContents()
        switch item.kind {
        case .text:
            pb.setString(item.text ?? "", forType: .string)
        case .link, .file:
            if let url = item.linkURL { pb.writeObjects([url as NSURL]) }
        case .image:
            // Huge pictures go as the file (pasting it is the same), so a 100-megapixel photo isn't decoded here.
            if let url = contentURL(item), ThumbnailService.pixelCount(url) > 40_000_000 {
                pb.writeObjects([Store.handOut(url) as NSURL])
            } else if let url = contentURL(item), let image = NSImage(contentsOf: url) {
                pb.writeObjects([image])
            }
        }
        flash("Copied")
    }

    /// ⌘C: everything selected. Several notes and links paste as text, one after another.
    func copySelection() {
        let picked = selection
        defer { if !picked.isEmpty { rememberCopied(picked) } } // and ⌘V in Swiss pastes copies of them
        let chosen = items.filter { selection.contains(.item($0.id)) }
        if chosen.count == 1 && picked.folderIDs.isEmpty { copy(chosen[0]); return }
        guard !chosen.isEmpty else {
            // Only folders: other apps get their names; Swiss pastes the folders.
            guard !picked.isEmpty else { NSSound.beep(); return }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(picked.folderIDs.compactMap { folder($0)?.name }.joined(separator: "\n"), forType: .string)
            flash(picked.folderIDs.count == 1 ? "Copied" : "Copied \(picked.folderIDs.count) folders")
            return
        }
        var texts: [String] = [], files: [NSURL] = []
        for item in chosen {
            switch item.kind {
            case .text: if let text = item.text { texts.append(text) }
            case .link: if let url = item.url { texts.append(url) }
            case .image, .file: if let url = contentURL(item) { files.append(url as NSURL) }
            }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        var objects: [NSPasteboardWriting] = files
        if !texts.isEmpty { objects.insert(texts.joined(separator: "\n\n") as NSString, at: 0) }
        pb.writeObjects(objects)
        flash("Copied \(chosen.count + picked.folderIDs.count) things")
    }

    /// What a card carries when dragged out into another app.
    /// What you get when you drag a card out: the real file from its folder in Documents
    /// (a note's .txt/.rtf, a link's .webloc, the picture, the file) — and, for apps that take
    /// text or links instead of files, the text or the link too.
    /// The file that leaves Stash when you drag this out. A link comes out as a little note you can read:
    /// its title, and the link (clickable, easy to copy).
    func dragFile(for item: Item) -> URL? {
        (item.kind == .link ? linkNote(for: item) : nil) ?? item.storedPath.map(absolute).flatMap { FileManager.default.fileExists(atPath: $0.path) ? $0 : nil }
            ?? (item.kind == .image || item.kind == .file ? contentURL(item) : nil)
    }

    /// What a card carries when it's dragged to another app: its file (linked files: the original; Stash's own:
    /// a visible clone), and its text or link.
    func pasteboardItem(for thing: Item) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        var any = false
        if let file = dragFile(for: thing) {
            item.setString(Store.handOut(file).absoluteString, forType: .fileURL)
            any = true
        }
        switch thing.kind {
        case .text:
            if let text = thing.text { item.setString(text, forType: .string); any = true }
        case .link:
            if let url = thing.url { item.setString(url, forType: .URL); item.setString(url, forType: .string); any = true }
        default: break
        }
        return any ? item : nil
    }

    func itemProvider(for item: Item) -> NSItemProvider {
        let file = dragFile(for: item)
        let provider = file.map(copyingProvider) ?? NSItemProvider()
        switch item.kind {
        case .text: provider.registerObject((item.text ?? "") as NSString, visibility: .all)
        case .link: if let url = item.linkURL { provider.registerObject(url as NSURL, visibility: .all) }
        default: break
        }
        return provider
    }

    /// A link as a readable note (.rtf): the title in bold, then the clickable link and any note on it.
    private func linkNote(for item: Item) -> URL? {
        guard let url = item.linkURL else { return nil }
        let title = item.title?.isEmpty == false ? item.title! : item.host
        let note = NSMutableAttributedString(string: title + "\n", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        note.append(NSAttributedString(string: url.absoluteString, attributes: [.link: url, .font: NSFont.systemFont(ofSize: 13)]))
        if let text = item.text, !text.isEmpty {
            note.append(NSAttributedString(string: "\n\n" + text, attributes: [.font: NSFont.systemFont(ofSize: 13)]))
        }
        guard let data = note.rtf(from: NSRange(location: 0, length: note.length), documentAttributes: [.documentType: NSAttributedString.DocumentType.rtf])
        else { return nil }
        let name = String(title.map { "/:".contains($0) ? "-" : $0 }.prefix(80)).trimmingCharacters(in: .whitespaces)
        let dir = TestMode.temp("StashDrag").appendingPathComponent(item.id.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent((name.isEmpty ? "Link" : name) + ".rtf")
        return (try? data.write(to: file)) != nil ? file : nil
    }

    /// Dragging a project tab out: its folder in Documents, with everything in it.
    func projectProvider(_ id: UUID?) -> NSItemProvider {
        guard let path = mirrorDirs["p:" + (id?.uuidString ?? "none")] else { return NSItemProvider() }
        return copyingProvider(absolute(path))
    }

    /// Dragging a folder out: the real folder, with everything in it (Finder copies it).
    func folderProvider(for folder: Folder) -> NSItemProvider {
        guard let path = mirrorDirs["f:" + folder.id.uuidString] else { return NSItemProvider(object: folder.name as NSString) }
        return copyingProvider(absolute(path))
    }

    /// Hands out a copy of the file or folder, never Stash's own — so dragging something out of Stash (even onto
    /// the same disk, where Finder would normally move it) leaves Stash's copy in place. The copy is only made when
    /// the drop happens, off the main thread, so starting a drag never waits. Linked files hand out the original
    /// (the other app copies it), however big.
    func copyingProvider(_ original: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        let type = (try? original.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            DispatchQueue.global(qos: .userInitiated).async {
                // Not coordinated: the system makes a copy for whoever receives it.
                done(Store.handOut(original), false, nil)
            }
            return nil
        }
        provider.suggestedName = original.lastPathComponent
        return provider
    }
}

extension NSImage {
    var pngData: Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
