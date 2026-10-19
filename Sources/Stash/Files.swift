import AppKit

/// Videos, music, 3D models and other files are copied into the library (when the setting is on),
/// so they stay in Stash even after you delete or move the original from Downloads.
extension Store {
    /// Copies wait here for a moment before the mirror moves them into their folder.
    var filesDir: URL { dataDir.appendingPathComponent("incoming", isDirectory: true) }

    /// The folder holding an item's stored copy (files/<id>/name.ext), if it has one.
    func storedCopyFolder(_ item: Item) -> URL? {
        guard item.kind == .file, let url = item.linkURL, url.isFileURL,
              url.path.hasPrefix(filesDir.path + "/") else { return nil }
        return url.deletingLastPathComponent()
    }

    /// Copies a file into the library in the background (two at a time, with progress and Cancel on the card),
    /// then points the card at the copy. If it can't be copied (no room, cancelled, the drive went away) the card
    /// keeps a link to the original instead — nothing is lost either way.
    func storeCopy(of original: URL, for id: UUID) {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: original.path, isDirectory: &isDirectory), !isDirectory.boolValue else { return }
        let destination = filesDir.appendingPathComponent(id.uuidString, isDirectory: true).appendingPathComponent(original.lastPathComponent)
        copying.insert(id)
        FileCopies.shared.copy(original, to: destination, for: id) { copy, problem in
            let store = Store.shared
            store.copying.remove(id)
            guard let index = store.items.firstIndex(where: { $0.id == id }) else {
                if let copy { try? FileManager.default.removeItem(at: copy.deletingLastPathComponent()) } // deleted meanwhile
                return
            }
            if let copy {
                // A link already in Documents (Keep a Copy on a linked file) makes room for the real file.
                if let stored = store.items[index].storedPath, store.isSymlink(store.absolute(stored)) {
                    try? FileManager.default.removeItem(at: store.absolute(stored))
                }
                store.keepLinked.remove(id)
                store.update(id) { $0.url = copy.absoluteString; $0.storedPath = nil; $0.bookmark = nil }
            } else {
                store.keepLinked.insert(id)
                let name = original.lastPathComponent
                store.flash(problem == "Cancelled" ? "Kept as a link to the original" : "Couldn't copy \(name) — kept as a link (\(problem ?? "unknown problem"))")
                store.scheduleMirror() // puts the link in its folder
            }
        }
    }

    /// Linked file → a real copy in Stash (for when the original's drive won't always be there).
    func keepCopy(_ id: UUID) {
        guard let item = items.first(where: { $0.id == id }), case .linked(let original)? = fileState(item) else { return }
        storeCopy(of: original, for: id)
    }

    /// At launch: remove copies that never made it into a folder and that no card points at.
    func cleanUpStoredCopies() {
        let used = Set((items + recentlyDeleted.flatMap(\.items)).compactMap { $0.linkURL?.path.hasPrefix(filesDir.path) == true ? $0.linkURL?.deletingLastPathComponent().lastPathComponent : nil })
        guard let folders = try? FileManager.default.contentsOfDirectory(atPath: filesDir.path) else { return }
        for name in folders where !used.contains(name) {
            try? FileManager.default.removeItem(at: filesDir.appendingPathComponent(name))
        }
    }
}
