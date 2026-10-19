import AppKit

/// Stash is a real folder: ~/Documents/.Stash mirrors the app.
///
///     ~/Documents/.Stash/
///         Not Selected/                 ← things in no project
///         Mammoth/                      ← a project
///             PhotoBook/                ← a folder (folders inside folders become subfolders)
///                 7.jpg
///             Files/
///                 tv.mp4
///             Call the printer.txt      ← a note
///             Are.na.webloc             ← a link
///         .stash/                       ← Stash's own data (library.json, previews, trash)
///
/// After every change the mirror is brought in line: files move when things move, folders are
/// renamed with them, and deleting something in Stash removes it here too. Deleted files wait in
/// .stash/trash for 30 days (Recently Deleted), so they can be restored even after a restart.
extension Store {
    private var stagingDir: URL { dataDir.appendingPathComponent("staging", isDirectory: true) }

    /// Runs the mirror once after the current batch of changes.
    func scheduleMirror() {
        guard !mirrorScheduled else { return }
        mirrorScheduled = true
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                Store.shared.mirrorScheduled = false
                Perf.measure("syncMirror") { Store.shared.syncMirror() }
                Store.shared.exportSavedProjects() // projects saved to the Mac follow along
            }
        }
    }

    func absolute(_ relative: String) -> URL { rootDir.appendingPathComponent(relative) }

    /// Clears macOS's "hidden" flag on this item and everything inside it.
    nonisolated static func unhide(_ root: URL) {
        func clear(_ url: URL) {
            var u = url, values = URLResourceValues()
            values.isHidden = false
            try? u.setResourceValues(values)
        }
        clear(root)
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil) else { return }
        for case let url as URL in walker where !url.lastPathComponent.hasPrefix(".") { clear(url) }
    }

    /// What leaves Stash (dragged out, Quick Look): a fresh copy outside the library, never the library's own file.
    /// iCloud keeps everything inside the hidden library folder flagged "hidden", and copies would carry that flag —
    /// arriving invisible on the Desktop. The copy is instant on the same disk (APFS clones it).
    nonisolated static func visibleCopy(of url: URL) -> URL {
        let fm = FileManager.default
        let dir = TestMode.temp("StashOut").appendingPathComponent(UUID().uuidString, isDirectory: true)
        let copy = dir.appendingPathComponent(url.lastPathComponent)
        do {
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            try fm.copyItem(at: url, to: copy)
            unhide(copy)
            return copy
        } catch {
            return url
        }
    }

    /// The file that holds a thing's content, wherever it is right now.
    func contentURL(_ item: Item) -> URL? {
        if let stored = item.storedPath {
            let url = absolute(stored)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        switch item.kind {
        case .image: return item.imageFile.map(fileURL(for:))
        case .file: return item.linkURL
        default: return nil
        }
    }

    // MARK: Names

    private static func clean(_ raw: String, limit: Int = 60) -> String {
        var name = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() } // never a hidden file
        if name.count > limit { name = String(name.prefix(limit)).trimmingCharacters(in: .whitespaces) }
        return name.isEmpty ? "Untitled" : name
    }

    /// "name.ext", or "name 2.ext" if that's taken in the folder.
    private static func unique(_ base: String, ext: String, taken: inout Set<String>) -> String {
        func make(_ n: Int) -> String {
            let stem = n == 1 ? base : "\(base) \(n)"
            return ext.isEmpty ? stem : "\(stem).\(ext)"
        }
        var n = 1
        while taken.contains(make(n).lowercased()) { n += 1 }
        let name = make(n)
        taken.insert(name.lowercased())
        return name
    }

    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f
    }()

    /// What a thing is called on disk.
    private func diskName(_ item: Item) -> (base: String, ext: String) {
        switch item.kind {
        case .image:
            let source = item.storedPath ?? item.imageFile ?? ""
            let ext = (source as NSString).pathExtension.lowercased()
            let base = item.title.map { (($0 as NSString).deletingPathExtension) } ?? "Image \(Self.stamp.string(from: item.createdAt))"
            return (Self.clean(base), ext.isEmpty ? "png" : ext)
        case .file:
            let name = item.title ?? item.linkURL?.lastPathComponent ?? "File"
            return (Self.clean((name as NSString).deletingPathExtension, limit: 80), (name as NSString).pathExtension)
        case .text:
            let first = item.text?.split(separator: "\n").first.map(String.init) ?? "Note"
            return (Self.clean(first, limit: 50), item.richText == nil ? "txt" : "rtf")
        case .link:
            return (Self.clean(item.title ?? item.host, limit: 60), "webloc")
        }
    }

    // MARK: Sync

    /// Brings ~/Documents/.Stash in line with the library.
    func syncMirror() {
        let fm = FileManager.default
        // Usually only what changed is touched; every 5 minutes (and at launch) every file is checked,
        // which also catches files changed or removed outside Stash.
        let full = lastFullMirror.map { Date().timeIntervalSince($0) > 300 } ?? true
        let oldDirs = Set(mirrorDirs.values)
        func contentKey(_ item: Item) -> Int {
            switch item.kind {
            case .text: item.richText?.hashValue ?? item.text?.hashValue ?? 0
            case .link: item.url?.hashValue ?? 0
            default: 0
            }
        }
        func print(_ item: Item) -> String {
            "\(item.storedPath ?? "")|\(contentKey(item))|\((item.colorTags ?? []).map(\.rawValue).joined(separator: ","))"
        }
        func unchanged(_ item: Item) -> Bool { !full && mirrorPrints[item.id] == print(item) }

        // 1. Where every project and folder lives.
        var dirs: [String: String] = [:] // "p:<id>" / "f:<id>" → relative path
        var takenProjectNames: Set<String> = ["not selected", ".stash"]
        func projectKey(_ id: UUID?) -> String { "p:" + (id?.uuidString ?? "none") }
        // "Not Selected" is gone; its folder only exists while something still has no project.
        if items.contains(where: { $0.projectID == nil }) || folders.contains(where: { $0.projectID == nil }) {
            dirs[projectKey(nil)] = "Not Selected"
        }
        for project in projects {
            dirs[projectKey(project.id)] = Self.unique(Self.clean(project.name), ext: "", taken: &takenProjectNames)
        }
        var takenInDir: [String: Set<String>] = [:]
        func folderPath(_ folder: Folder, depth: Int = 0) -> String {
            if let known = dirs["f:" + folder.id.uuidString] { return known }
            let parentPath: String
            if depth < 40, let parent = folder.parentID.flatMap(self.folder) {
                parentPath = folderPath(parent, depth: depth + 1)
            } else {
                parentPath = dirs[projectKey(folder.projectID)] ?? "Not Selected"
            }
            var taken = takenInDir[parentPath] ?? []
            let name = Self.unique(Self.clean(folder.displayName), ext: "", taken: &taken)
            takenInDir[parentPath] = taken
            let path = parentPath + "/" + name
            dirs["f:" + folder.id.uuidString] = path
            return path
        }
        for folder in folders.sorted(by: { $0.createdAt < $1.createdAt }) { _ = folderPath(folder) }
        for path in Set(dirs.values) where full || !oldDirs.contains(path) {
            try? fm.createDirectory(at: absolute(path), withIntermediateDirectories: true)
        }

        // 2. Where every thing should be.
        var desired: [UUID: String] = [:]
        for item in items.sorted(by: { $0.createdAt < $1.createdAt }) {
            let dir = item.folderID.flatMap { dirs["f:" + $0.uuidString] } ?? dirs[projectKey(item.projectID)] ?? "Not Selected"
            let (base, ext) = diskName(item)
            var taken = takenInDir[dir] ?? []
            desired[item.id] = dir + "/" + Self.unique(base, ext: ext, taken: &taken)
            takenInDir[dir] = taken
        }

        // 3. Things that were deleted: their files go to the trash (⌘Z can bring them back).
        let current = Set(items.map(\.id))
        for (id, path) in mirrorPaths where !current.contains(id) {
            moveAside(absolute(path), to: trashDir.appendingPathComponent(id.uuidString, isDirectory: true))
        }

        // 4. Move what moved, in two steps so nothing bumps into anything else.
        var changed = false
        // `from` is the file waiting in staging, or nil when it has to be brought back another way.
        var staged: [(index: Int, from: URL?)] = []
        for index in items.indices {
            let item = items[index]
            guard let target = desired[item.id] else { continue }
            // Already where it belongs (trusted when nothing about it changed since the last pass).
            if item.storedPath == target, unchanged(item) || existing(absolute(target)) != nil { continue }
            if let stored = item.storedPath, stored != target, let from = existing(absolute(stored)) {
                let stage = stagingDir.appendingPathComponent(item.id.uuidString, isDirectory: true)
                if moveAside(from, to: stage) { staged.append((index, stage.appendingPathComponent(from.lastPathComponent))) }
            } else {
                staged.append((index, nil))
            }
        }
        for (index, staging) in staged {
            let item = items[index]
            guard let target = desired[item.id] else { continue }
            let destination = absolute(target)
            if let staging, staging.path.hasPrefix(stagingDir.path + "/"), existing(staging) != nil {
                try? fm.moveItem(at: staging, to: destination)
                try? fm.removeItem(at: staging.deletingLastPathComponent()) // its own folder inside staging
            } else if !bringBack(item, to: destination) {
                continue
            }
            items[index].storedPath = target
            if item.kind == .image { items[index].imageFile = nil } // the picture now lives in the folder
            if item.kind == .file, !isSymlink(destination) { items[index].url = destination.absoluteString }
            changed = true
        }

        // 5. Notes and links: keep their files' contents up to date.
        for item in items where item.kind == .text || item.kind == .link {
            guard let stored = item.storedPath, !unchanged(item) else { continue }
            let url = absolute(stored)
            if item.kind == .text, let rtf = item.richText {
                if (try? Data(contentsOf: url)) != rtf { try? rtf.write(to: url, options: .atomic) }
            } else if item.kind == .text {
                let text = item.text ?? ""
                if (try? String(contentsOf: url, encoding: .utf8)) != text { try? text.write(to: url, atomically: true, encoding: .utf8) }
            } else if !fm.fileExists(atPath: url.path) {
                writeWebloc(item, to: url)
            }
        }

        // 6. Folders that went away (or moved): leftovers you added yourself are kept —
        //    moved along if the folder still exists, otherwise put in the macOS Trash.
        let ownedDirs = Set(dirs.values)
        let ownedFiles = Set(desired.values)
        // Deepest first, so a folder inside another is handled before its parent.
        for (key, oldPath) in mirrorDirs.sorted(by: { $0.value.count > $1.value.count }) where dirs[key] != oldPath {
            // Another folder now uses this name (e.g. two "Notepad"s swapped): it's theirs, leave it alone.
            guard !ownedDirs.contains(oldPath) else { continue }
            let old = absolute(oldPath)
            guard fm.fileExists(atPath: old.path) else { continue }
            if let newPath = dirs[key] {
                for name in (try? fm.contentsOfDirectory(atPath: old.path)) ?? [] where name != ".DS_Store" {
                    let relative = oldPath + "/" + name
                    // Only things you put there yourself; Stash's own files and folders were placed above.
                    guard !ownedFiles.contains(relative), !ownedDirs.contains(relative) else { continue }
                    let from = old.appendingPathComponent(name)
                    let to = absolute(newPath).appendingPathComponent(name)
                    if !fm.fileExists(atPath: to.path) { try? fm.moveItem(at: from, to: to) }
                }
            }
            if isEffectivelyEmpty(old) {
                try? fm.removeItem(at: old)
            } else if dirs[key] == nil {
                try? fm.trashItem(at: old, resultingItemURL: nil)
            }
        }

        // 7. Color tags become real Finder tags on the files and folders.
        for item in items {
            guard let stored = item.storedPath, !unchanged(item) else { continue }
            setFinderTags(item.colorTags ?? [], on: absolute(stored))
        }
        var newFolderPrints: [UUID: String] = [:]
        for folder in folders {
            guard let path = dirs["f:" + folder.id.uuidString] else { continue }
            // Its own color tags, plus its kind's color (a Linker is tagged Green, a PhotoBook Red…), so the folder in
            // Documents — and any copy dragged out of Swiss — shows its kind in Finder.
            var tags = folder.colorTags ?? []
            if let kind = folder.style.finderTag, !tags.contains(kind) { tags.append(kind) }
            let folderPrint = path + "|" + tags.map(\.rawValue).joined(separator: ",")
            newFolderPrints[folder.id] = folderPrint
            if !full, folderPrints[folder.id] == folderPrint { continue }
            setFinderTags(tags, on: absolute(path))
        }
        folderPrints = newFolderPrints
        mirrorPrints = Dictionary(uniqueKeysWithValues: items.map { ($0.id, print($0)) })
        if full {
            lastFullMirror = Date()
            DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.followMovedOriginals() } }
        }

        // The old "Not Selected" folder, once nothing lives there: removed only if it holds no files at all.
        if dirs[projectKey(nil)] == nil {
            let old = absolute("Not Selected")
            if fm.fileExists(atPath: old.path), Self.holdsNoFiles(old) { try? fm.removeItem(at: old) }
        }

        mirrorDirs = dirs
        mirrorPaths = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.storedPath.map { (item.id, $0) } })
        try? fm.removeItem(at: stagingDir)
        if changed { writeLibrary() }
    }

    /// True when a folder (and everything inside it) has no files — only empty folders or .DS_Store.
    static func holdsNoFiles(_ url: URL) -> Bool {
        guard let walker = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey]) else { return false }
        for case let file as URL in walker where file.lastPathComponent != ".DS_Store" {
            if (try? file.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory != true { return false }
        }
        return true
    }

    /// Puts a thing's file back when it isn't in the mirror yet: from the trash (undo), from where it
    /// was saved first (pictures, copies), or by writing it (notes, links). Returns false if it can't.
    private func bringBack(_ item: Item, to destination: URL) -> Bool {
        let fm = FileManager.default
        let trashed = trashDir.appendingPathComponent(item.id.uuidString, isDirectory: true)
        if let name = (try? fm.contentsOfDirectory(atPath: trashed.path))?.first {
            try? fm.moveItem(at: trashed.appendingPathComponent(name), to: destination)
            try? fm.removeItem(at: trashed)
            return fm.fileExists(atPath: destination.path) || isSymlink(destination)
        }
        switch item.kind {
        case .image:
            guard let file = item.imageFile, fm.fileExists(atPath: fileURL(for: file).path) else { return false }
            return (try? fm.moveItem(at: fileURL(for: file), to: destination)) != nil
        case .file:
            guard let original = item.linkURL, original.isFileURL, fm.fileExists(atPath: original.path) else { return false }
            var isDirectory: ObjCBool = false
            fm.fileExists(atPath: original.path, isDirectory: &isDirectory)
            if original.path.hasPrefix(filesDir.path) {
                return (try? fm.moveItem(at: original, to: destination)) != nil // a copy Stash made
            }
            // Big files (over the limit in Settings) and ones whose copy was stopped stay linked to the original.
            if OrganizerSettings.copyFiles, !isDirectory.boolValue, !keepLinked.contains(item.id), !BigFiles.isBig(original) {
                // Copied in the background (big videos shouldn't freeze Stash); placed once it's done.
                if !copying.contains(item.id) {
                    copying.insert(item.id)
                    storeCopy(of: original, for: item.id)
                }
                return false
            }
            return (try? fm.createSymbolicLink(at: destination, withDestinationURL: original)) != nil
        case .text:
            if let rtf = item.richText { return (try? rtf.write(to: destination, options: .atomic)) != nil }
            return (try? (item.text ?? "").write(to: destination, atomically: true, encoding: .utf8)) != nil
        case .link:
            writeWebloc(item, to: destination)
            return fm.fileExists(atPath: destination.path)
        }
    }

    private func setFinderTags(_ tags: [TagColor], on url: URL) {
        let names = tags.map(\.finderName)
        let current = (try? url.resourceValues(forKeys: [.tagNamesKey]))?.tagNames ?? []
        guard current != names, FileManager.default.fileExists(atPath: url.path) else { return }
        try? (url as NSURL).setResourceValue(names, forKey: .tagNamesKey)
    }

    private func writeWebloc(_ item: Item, to url: URL) {
        guard let link = item.url else { return }
        let plist: [String: Any] = ["URL": link]
        if let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) {
            try? data.write(to: url)
        }
    }

    @discardableResult
    private func moveAside(_ file: URL, to folder: URL) -> Bool {
        let fm = FileManager.default
        guard existing(file) != nil else { return false }
        try? fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = folder.appendingPathComponent(file.lastPathComponent)
        try? fm.removeItem(at: destination)
        return (try? fm.moveItem(at: file, to: destination)) != nil
    }

    private func existing(_ url: URL) -> URL? {
        FileManager.default.fileExists(atPath: url.path) || isSymlink(url) ? url : nil
    }

    func isSymlink(_ url: URL) -> Bool {
        (try? FileManager.default.destinationOfSymbolicLink(atPath: url.path)) != nil
    }

    /// Nothing in it but .DS_Store files and empty folders.
    private func isEffectivelyEmpty(_ dir: URL) -> Bool {
        let fm = FileManager.default
        guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { return true }
        return names.allSatisfy { name in
            if name == ".DS_Store" { return true }
            var isDirectory: ObjCBool = false
            let url = dir.appendingPathComponent(name)
            return fm.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue && isEffectivelyEmpty(url)
        }
    }

    // MARK: Moving in from the old place

    /// The first time, the old library (~/Library/Application Support/Stash) is copied in.
    /// The old folder is left as it was, as a backup.
    static func migrateOldLibrary(into dataDir: URL, thumbs: URL) {
        let fm = FileManager.default
        // Stash Test never reads the real old library (unless a test asks for it with STASH_MIGRATE_FROM).
        if TestMode.isOn && ProcessInfo.processInfo.environment["STASH_MIGRATE_FROM"] == nil { return }
        let base = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = ProcessInfo.processInfo.environment["STASH_MIGRATE_FROM"].map { URL(fileURLWithPath: $0) }
            ?? base.appendingPathComponent("Stash", isDirectory: true)
        let oldLibrary = old.appendingPathComponent("library.json")
        let newLibrary = dataDir.appendingPathComponent("library.json")
        guard !fm.fileExists(atPath: newLibrary.path), fm.fileExists(atPath: oldLibrary.path) else { return }
        try? fm.copyItem(at: oldLibrary, to: newLibrary)
        let oldImages = old.appendingPathComponent("images")
        for name in (try? fm.contentsOfDirectory(atPath: oldImages.path)) ?? [] {
            try? fm.copyItem(at: oldImages.appendingPathComponent(name), to: thumbs.appendingPathComponent(name))
        }
    }
}
