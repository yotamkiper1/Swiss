import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Between connected folders and projects (moves, not copies)

extension Store {
    /// Files from a connected folder into a project: they move (out of the folder, into the project's folder in
    /// Documents) — no copy is left behind. ⌘Z (in the connected folder) puts them back.
    func moveIntoProject(_ urls: [URL], project: UUID) {
        let fm = FileManager.default
        var made: [(id: UUID, from: URL)] = []
        for url in urls {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else { continue } // folders stay in Finder
            let isImage = UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) ?? false
            if isImage {
                let name = UUID().uuidString + "." + url.pathExtension.lowercased()
                guard (try? fm.moveItem(at: url, to: fileURL(for: name))) != nil else { continue }
                var item = Item(kind: .image, projectID: project, folderID: nil)
                item.imageFile = name
                item.title = url.lastPathComponent
                items.append(item)
                made.append((item.id, url))
            } else {
                let id = UUID()
                let folder = filesDir.appendingPathComponent(id.uuidString, isDirectory: true)
                try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
                let target = folder.appendingPathComponent(url.lastPathComponent)
                guard (try? fm.moveItem(at: url, to: target)) != nil else { try? fm.removeItem(at: folder); continue }
                var item = Item(kind: .file, projectID: project, folderID: nil)
                item.id = id
                item.url = target.absoluteString
                item.title = url.lastPathComponent
                items.append(item)
                made.append((item.id, url))
                makeThumbnail(for: id, from: target)
            }
        }
        guard !made.isEmpty else { NSSound.beep(); return }
        save() // the mirror puts them in the project's folder
        ConnectedSelection.shared.paths = []
        let name = projects.first { $0.id == project }?.name ?? "the project"
        flash(made.count == 1 ? "Moved into \(name)" : "Moved \(made.count) into \(name)")
        ConnectedEditor.shared.rememberExternal("Move to Project") {
            let store = Store.shared
            for (id, original) in made {
                guard let item = store.items.first(where: { $0.id == id }), let file = store.contentURL(item) else { continue }
                if (try? FileManager.default.moveItem(at: file, to: original)) != nil {
                    store.items.removeAll { $0.id == id }
                }
            }
            store.save()
        }
    }

    /// Cards from a project onto a connected folder's tab: they move out of Swiss into the real folder — files and
    /// pictures as themselves, notes as .txt, links as .webloc.
    func moveOut(_ targets: Set<Selectable>, toConnected folderID: UUID) {
        guard let dir = ConnectedRegistry.shared.resolve(folderID) else { flash("That folder isn't available right now"); return }
        let fm = FileManager.default
        var movedIDs: Set<UUID> = []
        for id in targets.itemIDs {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            func unique(_ name: String) -> URL {
                var url = dir.appendingPathComponent(name), n = 2
                let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
                while fm.fileExists(atPath: url.path) { url = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)"); n += 1 }
                return url
            }
            switch item.kind {
            case .image, .file:
                // A linked file's original moves; Stash's own copy moves.
                guard let file = item.kind == .file ? (linkedOriginal(item) ?? contentURL(item)) : contentURL(item) else { continue }
                if (try? fm.moveItem(at: file, to: unique(item.title ?? file.lastPathComponent))) != nil { movedIDs.insert(id) }
            case .text:
                let first = (item.text ?? "Note").split(separator: "\n").first.map(String.init) ?? "Note"
                let name = String(first.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-").prefix(50))
                if (try? (item.text ?? "").write(to: unique(name + ".txt"), atomically: true, encoding: .utf8)) != nil { movedIDs.insert(id) }
            case .link:
                guard let link = item.url,
                      let data = try? PropertyListSerialization.data(fromPropertyList: ["URL": link], format: .xml, options: 0) else { continue }
                if (try? data.write(to: unique((item.title ?? item.host).replacingOccurrences(of: "/", with: "-") + ".webloc"))) != nil { movedIDs.insert(id) }
            }
        }
        guard !movedIDs.isEmpty else { NSSound.beep(); return }
        checkpoint("Move to Folder")
        items.removeAll { movedIDs.contains($0.id) }
        selection.subtract(movedIDs.map { Selectable.item($0) })
        save()
        flash(movedIDs.count == 1 ? "Moved into \(dir.lastPathComponent)" : "Moved \(movedIDs.count) into \(dir.lastPathComponent)")
    }

    private func linkedOriginal(_ item: Item) -> URL? {
        if case .linked(let url)? = fileState(item) { return url }
        return nil
    }
}

extension ConnectedEditor {
    /// An undo step for a change made outside this file (moving into a project).
    func rememberExternal(_ label: String, _ undo: @escaping () -> Void) { rememberStep(label, undo) }
}

// MARK: - Connected tabs as drop targets

/// Where each connected folder's tab is, for dropping cards onto it.
struct ConnectedTabDropKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

@MainActor
enum ConnectedTabs {
    static var frames: [UUID: CGRect] = [:]
    static func folder(at point: CGPoint) -> UUID? { frames.first { $0.value.insetBy(dx: -2, dy: -3).contains(point) }?.key }
}

// MARK: - The right-click tools for connected files

/// Tags (real Finder tags), Put in Folder, Convert to MP3 / MP4 (made next to the file), Copy, Move to Project.
struct ConnectedFileMenu: View {
    @EnvironmentObject var store: Store
    let urls: [URL]
    let folders: [ConnectedEntry]

    private var tagsHere: Set<String> {
        Set(urls.flatMap { (try? $0.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? [] })
    }

    var body: some View {
        Button("Copy") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls as [NSURL])
            store.flash("Copied")
        }
        let shareable = urls.filter { url in !folders.contains { $0.url == url } }
        if !shareable.isEmpty { Button("Share…") { Sharing.share(files: shareable) } }
        Menu("Tags") {
            ForEach(TagColor.allCases) { tag in
                Button { toggle(tag) } label: {
                    if tagsHere.contains(tag.finderName) { Label(tag.title, systemImage: "checkmark") } else { Text(tag.title) }
                }
            }
        }
        let targets = folders.filter { folder in !urls.contains(folder.url) }
        if !targets.isEmpty || ConnectedEditor.shared.currentURL?.deletingLastPathComponent() != nil {
            Menu("Put in Folder") {
                ForEach(targets) { folder in
                    Button(folder.name) { ConnectedEditor.shared.move(urls, into: folder.url) }
                }
                if store.connectedView?.subpath.isEmpty == false, let up = ConnectedEditor.shared.currentURL?.deletingLastPathComponent() {
                    Divider()
                    Button("Up to “\(up.lastPathComponent)”") { ConnectedEditor.shared.move(urls, into: up) }
                }
            }
        }
        let conversions = Array(Set(urls.flatMap { Converter.targets(for: $0) })).sorted { $0.rawValue < $1.rawValue }
        if !conversions.isEmpty {
            ForEach(conversions) { target in
                Button(target.title) { ConnectedEditor.shared.convert(urls, to: target) }
            }
        }
        let options = urls.count == 1 ? FormatConverter.conversions(for: urls[0]) : []
        if !options.isEmpty {
            Menu("Convert") {
                ForEach(options) { option in Button(option.title) { store.convertFile(urls[0], using: option) } }
            }
        }
        Menu("Move to Project") {
            ForEach(store.projects) { project in
                Button(project.name) { store.moveIntoProject(urls, project: project.id) }
            }
        }
    }

    private func toggle(_ tag: TagColor) {
        let on = !tagsHere.contains(tag.finderName)
        for url in urls {
            var names = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
            names.removeAll { $0 == tag.finderName }
            if on { names.append(tag.finderName) }
            try? (url as NSURL).setResourceValue(names, forKey: .tagNamesKey)
        }
    }
}

extension ConnectedEditor {
    /// MP3 / MP4 of files in the connected folder, made right next to them (one conversion at a time).
    func convert(_ urls: [URL], to target: ConvertTarget) {
        for url in urls where !Converter.targets(for: url).isEmpty {
            let dir = url.deletingLastPathComponent()
            var output = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + "." + target.rawValue)
            var n = 2
            while FileManager.default.fileExists(atPath: output.path) {
                output = dir.appendingPathComponent(url.deletingPathExtension().lastPathComponent + " \(n)." + target.rawValue)
                n += 1
            }
            let final = output
            Store.shared.flash("Making \(final.lastPathComponent)…")
            Task.detached {
                do {
                    try await Converter.convert(url, to: target, output: final)
                    await MainActor.run { Store.shared.flash("Made \(final.lastPathComponent)") }
                } catch {
                    try? FileManager.default.removeItem(at: final)
                    await MainActor.run { Store.shared.flash("Couldn't make the \(target.rawValue.uppercased()): \(error.localizedDescription)") }
                }
            }
        }
    }
}
