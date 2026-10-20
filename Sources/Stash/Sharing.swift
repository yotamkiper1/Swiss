import AppKit

/// Share: the Mac's own share sheet — AirDrop, Mail, Messages, WhatsApp and every other app that takes shared things.
/// Pictures and files go as themselves (with their real names), links as links, and notes as text — and as a small
/// .txt for AirDrop, which can't send plain text.
struct Shareable {
    var objects: [Any] = []
    /// Notes only: what AirDrop sends instead of the text.
    var textFile: URL?
    var isEmpty: Bool { objects.isEmpty }
}

@MainActor
enum Sharing {
    private static var picker: NSSharingServicePicker?
    private static let delegate = ShareDelegate()

    // MARK: What goes out

    private struct Parts {
        var files: [URL] = []
        var links: [URL] = []
        var notes: [String] = []
    }

    private static func add(_ item: Item, to parts: inout Parts, store: Store) {
        switch item.kind {
        case .text:
            if let text = item.text, !text.isEmpty { parts.notes.append(text) }
        case .link:
            if let url = item.linkURL { parts.links.append(url) }
        case .image, .file:
            if let file = store.dragFile(for: item) { parts.files.append(Store.handOut(file)) }
        }
    }

    private static func finish(_ parts: Parts) -> Shareable {
        var out = Shareable()
        out.objects = parts.files.map { $0 as NSURL } + parts.links.map { $0 as NSURL }
        guard !parts.notes.isEmpty else { return out }
        let text = parts.notes.joined(separator: "\n\n")
        let file = textFile(text, title: parts.notes.count == 1 ? parts.notes[0] : "Notes")
        if out.objects.isEmpty {
            out.objects = [text as NSString]   // Mail, Messages, WhatsApp… take the words themselves
            out.textFile = file                // AirDrop gets them as a file
        } else if let file {
            out.objects.append(file as NSURL)  // mixed with pictures or links: the notes ride along as a file
        }
        return out
    }

    static func shareable(items: [Item], store: Store = .shared) -> Shareable {
        var parts = Parts()
        for item in items { add(item, to: &parts, store: store) }
        return finish(parts)
    }

    static func shareable(recent entries: [RecentItem], store: Store = .shared) -> Shareable {
        var parts = Parts()
        for entry in entries {
            if let id = entry.itemID, let saved = store.items.first(where: { $0.id == id }) { add(saved, to: &parts, store: store); continue }
            switch entry.kind {
            case .files:
                for url in entry.fileURLs where FileManager.default.fileExists(atPath: url.path) { parts.files.append(Store.handOut(url)) }
            case .screenshot:
                if let url = entry.fileURLs.first, FileManager.default.fileExists(atPath: url.path) { parts.files.append(url) }
            case .image:
                if let blob = RecentStore.shared.blobURL(entry), let named = namedCopy(of: blob, as: "Picture") { parts.files.append(named) }
            case .link:
                if let url = entry.text.flatMap(URL.init(string:)) { parts.links.append(url) }
            case .text:
                if let text = entry.text, !text.isEmpty { parts.notes.append(text) }
            }
        }
        return finish(parts)
    }

    static func shareable(files urls: [URL]) -> Shareable {
        var parts = Parts()
        parts.files = urls.filter { FileManager.default.fileExists(atPath: $0.path) }
        return finish(parts)
    }

    // MARK: Temporary files

    private static func scratch() -> URL {
        let dir = TestMode.temp("StashOut").appendingPathComponent("share-" + UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private static func textFile(_ text: String, title: String) -> URL? {
        let first = title.split(whereSeparator: \.isNewline).first.map(String.init) ?? "Note"
        let safe = String(first.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .trimmingCharacters(in: .whitespaces).prefix(40))
        let url = scratch().appendingPathComponent((safe.isEmpty ? "Note" : safe) + ".txt")
        return (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil ? url : nil
    }

    private static func namedCopy(of file: URL, as name: String) -> URL? {
        let url = scratch().appendingPathComponent(name + "." + (file.pathExtension.isEmpty ? "png" : file.pathExtension))
        return (try? FileManager.default.copyItem(at: file, to: url)) != nil ? url : nil
    }

    // MARK: Showing the share sheet

    static func share(targets: Set<Selectable>, store: Store = .shared) {
        let ids = Set(targets.itemIDs)
        let chosen = store.items.filter { ids.contains($0.id) }
        if chosen.isEmpty, !targets.folderIDs.isEmpty { store.flash("Folders can't be shared yet — pick the things inside") }
        present(shareable(items: chosen, store: store))
    }

    static func share(item: Item) { share(targets: Store.shared.targets(for: .item(item.id))) }

    static func share(recent entries: [RecentItem]) { present(shareable(recent: entries)) }

    static func share(files urls: [URL]) { present(shareable(files: urls)) }

    /// WhatsApp's Mac app has no share extension, so macOS never lists it. This entry does the job: words and links open
    /// WhatsApp's own "send to…" chooser; pictures and files are copied, WhatsApp opens, and you paste them into a chat.
    static func sendToWhatsApp(_ items: [Any], app: URL) {
        let urls = items.compactMap { ($0 as? NSURL) as URL? }
        let files = urls.filter { $0.isFileURL }
        let words = items.compactMap { ($0 as? NSString) as String? } + urls.filter { !$0.isFileURL }.map(\.absoluteString)
        if files.isEmpty, !words.isEmpty {
            var parts = URLComponents(string: "whatsapp://send")!
            parts.queryItems = [URLQueryItem(name: "text", value: words.joined(separator: "\n"))]
            if let link = parts.url { NSWorkspace.shared.open(link); return }
        }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects(files as [NSURL])
        Store.shared.clipboardSeenCount = pb.changeCount // our own copy: no "you copied…" banner
        NSWorkspace.shared.openApplication(at: app, configuration: NSWorkspace.OpenConfiguration())
        Store.shared.flash("Copied. Open the chat in WhatsApp and paste (⌘V)")
    }

    /// A Swiss window to hang the sheet from.
    private static var anchorWindow: NSWindow? {
        // The window you're in: a Swiss window, or the picture preview (double-click).
        if let key = NSApp.keyWindow, key is StashPanel || key is PreviewPanel { return key }
        return NSApp.windows.first { $0 is StashPanel && $0.isVisible }
    }

    static func present(_ shareable: Shareable) {
        guard !shareable.isEmpty else { NSSound.beep(); Store.shared.flash("Nothing to share"); return }
        guard let window = anchorWindow, let content = window.contentView else { return }
        let picker = NSSharingServicePicker(items: shareable.objects)
        delegate.textFile = shareable.textFile
        picker.delegate = delegate
        // Under the pointer (where you pressed Share); the top middle if that was a menu.
        let mouse = content.convert(window.mouseLocationOutsideOfEventStream, from: nil)
        let at = content.bounds.contains(mouse) ? mouse : NSPoint(x: content.bounds.midX, y: content.bounds.maxY - 40)
        picker.show(relativeTo: NSRect(x: at.x - 8, y: at.y - 8, width: 16, height: 16), of: content, preferredEdge: .minY)
        self.picker = picker
    }
}

/// Makes sure Mail and AirDrop are on the list for whatever is shared.
@MainActor
final class ShareDelegate: NSObject, NSSharingServicePickerDelegate {
    var textFile: URL?

    func sharingServicePicker(_ sharingServicePicker: NSSharingServicePicker, sharingServicesForItems items: [Any],
                              proposedSharingServices proposedServices: [NSSharingService]) -> [NSSharingService] {
        var list = proposedServices
        func has(_ title: String) -> Bool { list.contains { $0.title == title } }
        if !has("AirDrop"), let file = textFile, let air = NSSharingService(named: .sendViaAirDrop) {
            // AirDrop can't take plain text: this entry sends the notes as a .txt instead.
            let custom = NSSharingService(title: "AirDrop", image: air.image, alternateImage: air.alternateImage) { air.perform(withItems: [file]) }
            list.insert(custom, at: 0)
        }
        if !has("Mail"), let mail = NSSharingService(named: .composeEmail) { list.insert(mail, at: min(1, list.count)) }
        if !has("WhatsApp"), let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "net.whatsapp.WhatsApp") {
            let icon = (NSWorkspace.shared.icon(forFile: app.path).copy() as? NSImage) ?? NSImage()
            icon.size = NSSize(width: 18, height: 18)
            let whatsApp = NSSharingService(title: "WhatsApp", image: icon, alternateImage: nil) { Sharing.sendToWhatsApp(items, app: app) }
            let after = (list.firstIndex { $0.title == "Messages" } ?? min(1, list.count - 1)) + 1
            list.insert(whatsApp, at: max(0, min(after, list.count)))
        }
        return list
    }
}
