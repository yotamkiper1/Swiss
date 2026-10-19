import AppKit
import SwiftUI

/// Copy and paste inside Swiss: ⌘C on cards and folders, ⌘V in any project, folder or window makes copies there —
/// folders with everything in them. A name that's already taken there gets a number ("Poster 2.jpg", "PhotoBook 2").
/// Other apps still get the files, text and links on the clipboard, as before.
@MainActor
enum SwissClipboard {
    /// What was copied, and the clipboard's count right after — if something else is copied since, ⌘V pastes that.
    static var targets: Set<Selectable> = []
    static var changeCount = -1

    static var isCurrent: Bool { !targets.isEmpty && NSPasteboard.general.changeCount == changeCount }
}

extension Store {
    /// Remembers the selection for pasting inside Swiss (called after the clipboard is written for other apps).
    func rememberCopied(_ targets: Set<Selectable>) {
        SwissClipboard.targets = targets
        SwissClipboard.changeCount = NSPasteboard.general.changeCount
        clipboardSeenCount = NSPasteboard.general.changeCount // our own copy: no "save what you copied?" banner
    }

    /// ⌘V of things copied in Swiss: copies of them where you are.
    func pasteCopies(into place: Place) {
        let sources = SwissClipboard.targets
        var folderIDs = sources.folderIDs.filter { folder($0) != nil }
        // A folder copied along with something inside it: the folder brings it along already.
        folderIDs = folderIDs.filter { id in !ancestors(of: id).contains { folderIDs.contains($0.id) } }
        let itemIDs = sources.itemIDs.filter { id in
            guard let item = items.first(where: { $0.id == id }) else { return false }
            return !(item.folderID.map { f in folderIDs.contains(f) || ancestors(of: f).contains { folderIDs.contains($0.id) } } ?? false)
        }
        guard !folderIDs.isEmpty || !itemIDs.isEmpty else { NSSound.beep(); return }
        checkpoint("Paste")
        let project = place.project ?? ensureProjectHome()
        var newFolders: [Folder] = [], newItems: [Item] = []
        var pasted: Set<Selectable> = []

        // Names already used where they land (and by what's being pasted alongside).
        var folderNames = Set(folders.filter { $0.projectID == project }.map(\.name))
        var itemNames = Set(items.filter { $0.projectID == project && $0.folderID == place.folder }.map(\.displayTitle))

        func copyFolder(_ id: UUID, into parent: UUID?, rename: Bool) {
            guard let source = folder(id) else { return }
            var copy = source
            copy.id = UUID()
            copy.projectID = project
            copy.parentID = parent
            copy.spots = nil
            copy.createdAt = Date()
            if rename {
                copy.name = Self.numbered(source.name, taken: folderNames, keepExtension: false)
                folderNames.insert(copy.name)
                pasted.insert(.folder(copy.id))
            }
            newFolders.append(copy)
            for item in items where item.folderID == id {
                if let made = duplicate(item, project: project, folder: copy.id, title: nil) { newItems.append(made) }
            }
            for child in folders where child.parentID == id { copyFolder(child.id, into: copy.id, rename: false) }
        }

        for id in folderIDs { copyFolder(id, into: place.folder, rename: true) }
        for id in itemIDs {
            guard let item = items.first(where: { $0.id == id }) else { continue }
            var title: String?
            if item.kind != .text { // notes are named by their text
                title = Self.numbered(item.displayTitle, taken: itemNames, keepExtension: item.kind == .file || item.kind == .image)
                itemNames.insert(title!)
            }
            if let made = duplicate(item, project: project, folder: place.folder, title: title) {
                newItems.append(made)
                pasted.insert(.item(made.id))
            }
        }
        withAnimation(.spring(duration: 0.3)) {
            folders.append(contentsOf: newFolders)
            items.insert(contentsOf: newItems, at: 0)
        }
        selection = pasted
        save()
        let count = pasted.count
        flash(count == 1 ? "Pasted" : "Pasted \(count) things", undo: true)
    }

    /// A copy of a card with its own files (a linked big file stays a link to the same original).
    private func duplicate(_ item: Item, project: UUID, folder: UUID?, title: String?) -> Item? {
        let fm = FileManager.default
        var copy = item
        copy.id = UUID()
        copy.projectID = project
        copy.folderID = folder
        copy.createdAt = Date()
        copy.spots = nil
        copy.storedPath = nil // the mirror writes it out in Documents
        if let title { copy.title = title }
        // Its own picture / thumbnail, so deleting one never takes the other's.
        if let file = item.imageFile {
            let name = UUID().uuidString + "." + (file as NSString).pathExtension
            if (try? fm.copyItem(at: fileURL(for: file), to: fileURL(for: name))) != nil { copy.imageFile = name } else { copy.imageFile = nil }
        }
        if item.kind == .file, case .stored? = fileState(item), let source = item.linkURL {
            let dir = filesDir.appendingPathComponent(copy.id.uuidString, isDirectory: true)
            let target = dir.appendingPathComponent(title ?? source.lastPathComponent)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                try fm.copyItem(at: source, to: target) // APFS: a clone, instant even for big files
                copy.url = target.absoluteString
            } catch {
                try? fm.removeItem(at: dir)
                return nil
            }
        }
        return copy
    }

    /// "Poster.jpg" → "Poster 2.jpg", "PhotoBook" → "PhotoBook 2" — if the name is taken.
    static func numbered(_ name: String, taken: Set<String>, keepExtension: Bool) -> String {
        guard taken.contains(name) else { return name }
        let ext = keepExtension ? (name as NSString).pathExtension : ""
        var stem = ext.isEmpty ? name : (name as NSString).deletingPathExtension
        var n = 2
        // "Poster 2" copied again → "Poster 3", not "Poster 2 2".
        if let space = stem.lastIndex(of: " "), let number = Int(stem[stem.index(after: space)...]), number >= 2 {
            stem = String(stem[..<space])
            n = number + 1
        }
        func make(_ n: Int) -> String { ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)" }
        while taken.contains(make(n)) { n += 1 }
        return make(n)
    }
}
