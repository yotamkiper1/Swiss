import AppKit
import SwiftUI
import UniformTypeIdentifiers

// MARK: - Editing connected folders (in the real folder)

/// A connected folder works like a project, but everything happens in the real folder on the Mac — new folders,
/// adding things, renaming, moving into a folder or back up, Move to Trash, organizing. Finder sees it at once, and
/// changes made in Finder show up here (the view watches the folder), so the two are always the same. Nothing is
/// copied into Swiss's library. ⌘Z undoes Swiss's last change. Only where tiles sit is Swiss's own (kept next to the
/// connection, not in your folder). Nothing outside the connected folder is ever touched.
@MainActor
final class ConnectedEditor: ObservableObject {
    static let shared = ConnectedEditor()

    /// The file being renamed right now (its path).
    @Published var renamingPath: String?
    /// The folder tile something is being dragged over.
    @Published var dropTargetPath: String?
    /// The note being written (New Note in a connected folder).
    @Published var composing = false

    private var undoStack: [(label: String, undo: () -> Void)] = []
    /// Where tiles were put by hand: "folderID|subpath" → file name → spot (board points).
    @Published private var spots: [String: [String: CGPoint]] = [:]
    private var spotsURL: URL { Store.shared.dataDir.appendingPathComponent("connected-spots.json") }

    init() {
        if let data = try? Data(contentsOf: spotsURL),
           let saved = try? JSONDecoder().decode([String: [String: [Double]]].self, from: data) {
            spots = saved.mapValues { $0.compactMapValues { $0.count == 2 ? CGPoint(x: $0[0], y: $0[1]) : nil } }
        }
    }

    private func saveSpots() {
        let plain = spots.mapValues { $0.mapValues { [Double($0.x), Double($0.y)] } }
        let url = spotsURL
        DispatchQueue.global(qos: .utility).async { try? JSONEncoder().encode(plain).write(to: url, options: .atomic) }
    }

    // MARK: Where we are

    var location: ConnectedLocation? { Store.shared.connectedView }

    /// The folder on screen.
    var currentURL: URL? {
        guard let location, let root = ConnectedRegistry.shared.resolve(location.folderID) else { return nil }
        return location.subpath.isEmpty ? root : root.appendingPathComponent(location.subpath, isDirectory: true)
    }

    private var root: URL? { location.flatMap { ConnectedRegistry.shared.resolve($0.folderID) } }

    /// Only inside the connected folder — never anything else on the Mac.
    private func inside(_ url: URL) -> Bool {
        guard let root else { return false }
        let r = root.standardizedFileURL.path, p = url.standardizedFileURL.path
        return p == r || p.hasPrefix(r + "/")
    }

    // MARK: Positions

    private func boardKey(for dir: URL) -> String? {
        guard let location, let root else { return nil }
        let r = root.standardizedFileURL.path, d = dir.standardizedFileURL.path
        let sub = d == r ? "" : String(d.dropFirst(r.count + 1))
        return location.folderID.uuidString + "|" + sub
    }

    func spot(of url: URL) -> CGPoint? {
        guard let key = boardKey(for: url.deletingLastPathComponent()) else { return nil }
        return spots[key]?[url.lastPathComponent]
    }

    /// Dragged on the board: these go where you let go, and everything else on it stays where it is now.
    func place(_ moving: Set<String>, by delta: CGSize, frames: [String: CGRect], in dir: URL) {
        guard let key = boardKey(for: dir) else { return }
        var board = spots[key] ?? [:]
        for (path, frame) in frames {
            let shift = moving.contains(path) ? delta : .zero
            board[(path as NSString).lastPathComponent] = CGPoint(x: max(0, frame.minX + shift.width), y: max(0, frame.minY + shift.height))
        }
        spots[key] = board
        UserDefaults.standard.set(BoardSort.manual.rawValue, forKey: BoardSort.key)
        saveSpots()
    }

    /// Arrange By (anything but None) lines this folder up again.
    func forgetSpots() {
        guard let dir = currentURL, let key = boardKey(for: dir) else { return }
        spots[key] = nil
        saveSpots()
    }

    private func renameSpot(from old: URL, to new: URL) {
        guard let oldKey = boardKey(for: old.deletingLastPathComponent()), let spot = spots[oldKey]?[old.lastPathComponent] else { return }
        spots[oldKey]?[old.lastPathComponent] = nil
        if let newKey = boardKey(for: new.deletingLastPathComponent()), newKey == oldKey { spots[newKey, default: [:]][new.lastPathComponent] = spot }
        saveSpots()
    }

    // MARK: Undo

    func rememberStep(_ label: String, _ undo: @escaping () -> Void) { remember(label, undo) }

    private func remember(_ label: String, _ undo: @escaping () -> Void) {
        undoStack.append((label, undo))
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { NSSound.beep(); return }
        last.undo()
        Store.shared.flash("Undid \(last.label)")
    }

    // MARK: Names

    /// A free name in a folder: "name", "name 2", "name 3"…
    private func unique(_ name: String, in dir: URL) -> URL {
        let ext = (name as NSString).pathExtension, stem = (name as NSString).deletingPathExtension
        var candidate = dir.appendingPathComponent(name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) || (try? FileManager.default.destinationOfSymbolicLink(atPath: candidate.path)) != nil {
            candidate = dir.appendingPathComponent(ext.isEmpty ? "\(stem) \(n)" : "\(stem) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    private static func clean(_ raw: String) -> String {
        var name = raw.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespacesAndNewlines)
        while name.hasPrefix(".") { name.removeFirst() } // never a hidden file by accident
        return String(name.prefix(80))
    }

    // MARK: Changing things

    @discardableResult
    func newFolder(named name: String = "untitled folder", rename: Bool = true) -> URL? {
        guard let dir = currentURL else { return nil }
        let chosen = rename ? ConnectedSelection.shared.selectedURLs : [] // what's selected goes inside, like Finder's New Folder with Selection
        let url = unique(name, in: dir)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false) } catch {
            Store.shared.flash("Couldn't make a folder: \(error.localizedDescription)")
            return nil
        }
        // A Linker / PhotoBook / Notepad / Files: a normal folder with its kind's color tag.
        if let kind = FolderStyle.named(name)?.finderTag { try? (url as NSURL).setResourceValue([kind.finderName], forKey: .tagNamesKey) }
        remember("New Folder") { [weak self] in self?.trashSilently(url) }
        if !chosen.isEmpty { move(chosen, into: url) }
        ConnectedSelection.shared.paths = [url.path]
        if rename { renamingPath = url.path }
        return url
    }

    func rename(_ url: URL, to raw: String) {
        renamingPath = nil
        let name = Self.clean(raw)
        guard !name.isEmpty, name != url.lastPathComponent, inside(url) else { return }
        let target = url.deletingLastPathComponent().appendingPathComponent(name)
        guard !FileManager.default.fileExists(atPath: target.path) || target.path.lowercased() == url.path.lowercased() else {
            Store.shared.flash("“\(name)” is already there")
            return
        }
        do {
            try FileManager.default.moveItem(at: url, to: target)
            renameSpot(from: url, to: target)
            ConnectedSelection.shared.paths = [target.path]
            remember("Rename") { try? FileManager.default.moveItem(at: target, to: url) }
        } catch {
            Store.shared.flash("Couldn't rename: \(error.localizedDescription)")
        }
    }

    /// Into a folder (or back up to one above), inside the connected folder. A folder can't go into itself.
    func move(_ urls: [URL], into dir: URL) {
        guard inside(dir) else { return }
        var moved: [(from: URL, to: URL)] = []
        for url in urls where inside(url) {
            let d = dir.standardizedFileURL.path, u = url.standardizedFileURL.path
            guard d != u, !d.hasPrefix(u + "/"), url.deletingLastPathComponent().standardizedFileURL.path != d else { continue }
            let target = unique(url.lastPathComponent, in: dir)
            if (try? FileManager.default.moveItem(at: url, to: target)) != nil { moved.append((url, target)) }
        }
        guard !moved.isEmpty else { return }
        ConnectedSelection.shared.paths = []
        remember("Move") { for m in moved.reversed() { try? FileManager.default.moveItem(at: m.to, to: m.from) } }
        Store.shared.flash(moved.count == 1 ? "Moved into \(dir.lastPathComponent)" : "Moved \(moved.count) into \(dir.lastPathComponent)")
    }

    /// To the Mac's Trash (Finder's Put Back works too); ⌘Z brings them back.
    func trash(_ urls: [URL]) {
        var gone: [(from: URL, trashed: URL)] = []
        for url in urls where inside(url) {
            var result: NSURL?
            if (try? FileManager.default.trashItem(at: url, resultingItemURL: &result)) != nil, let result { gone.append((url, result as URL)) }
        }
        guard !gone.isEmpty else { return }
        DeleteSound.play()
        ConnectedSelection.shared.paths = []
        remember("Move to Trash") { for g in gone { try? FileManager.default.moveItem(at: g.trashed, to: g.from) } }
        Store.shared.flash(gone.count == 1 ? "Moved to the Trash" : "Moved \(gone.count) to the Trash")
    }

    private func trashSilently(_ url: URL) { try? FileManager.default.trashItem(at: url, resultingItemURL: nil) }

    // MARK: Bringing things in

    /// Drops and pastes: files are copied in (an instant clone on the same disk), pictures saved as files, links as
    /// .webloc (they open from Finder too), text as a .txt note. Into `dir`, or the folder on screen.
    @discardableResult
    func ingest(_ pb: NSPasteboard, into dir: URL? = nil) -> Bool {
        guard let dir = dir ?? currentURL, inside(dir) else { return false }
        var made: [URL] = []
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            made = copyIn(urls, to: dir)
        } else if case let (data, ext)? = Store.imageData(in: pb) {
            let url = unique("Image \(Self.stamp()).\(ext.isEmpty ? "png" : ext)", in: dir)
            if (try? data.write(to: url)) != nil { made = [url] }
        } else if let web = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?.first(where: { Safety.isWebURL($0) }) {
            made = [writeLink(web, in: dir)].compactMap { $0 }
        } else if let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty {
            if let url = Store.webURL(from: text) { made = [writeLink(url, in: dir)].compactMap { $0 } } else { made = [writeNote(text, in: dir)].compactMap { $0 } }
        }
        guard !made.isEmpty else { return false }
        ConnectedSelection.shared.paths = Set(made.map(\.path))
        remember("Add") { [weak self] in made.forEach { self?.trashSilently($0) } }
        Store.shared.flash(made.count == 1 ? "Saved into \(dir.lastPathComponent)" : "Saved \(made.count) into \(dir.lastPathComponent)")
        return true
    }

    /// Copies (never moves) files in. Big files from another drive copy in the background.
    private func copyIn(_ urls: [URL], to dir: URL) -> [URL] {
        var made: [URL] = []
        for url in urls {
            guard url.standardizedFileURL.deletingLastPathComponent().path != dir.standardizedFileURL.path else { continue } // already here
            let target = unique(url.lastPathComponent, in: dir)
            if BigFiles.sameVolume(url, dir) || BigFiles.size(of: url) < 200_000_000 {
                if copyfile(url.path, target.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE | COPYFILE_CLONE)) == 0 { made.append(target) }
            } else {
                Store.shared.flash("Copying \(url.lastPathComponent)…")
                DispatchQueue.global(qos: .utility).async {
                    let partial = target.deletingLastPathComponent().appendingPathComponent("." + target.lastPathComponent + ".swisspart")
                    let ok = copyfile(url.path, partial.path, nil, copyfile_flags_t(COPYFILE_ALL | COPYFILE_RECURSIVE)) == 0
                    if ok { try? FileManager.default.moveItem(at: partial, to: target) } else { try? FileManager.default.removeItem(at: partial) }
                    DispatchQueue.main.async { MainActor.assumeIsolated { Store.shared.flash(ok ? "Copied \(url.lastPathComponent)" : "Couldn't copy \(url.lastPathComponent)") } }
                }
            }
        }
        return made
    }

    @discardableResult
    func writeNote(_ text: String, in dir: URL? = nil) -> URL? {
        guard let dir = dir ?? currentURL, inside(dir) else { return nil }
        let first = Self.clean(text.split(separator: "\n").first.map(String.init) ?? "")
        let url = unique((first.isEmpty ? "Note \(Self.stamp())" : String(first.prefix(50))) + ".txt", in: dir)
        guard (try? text.write(to: url, atomically: true, encoding: .utf8)) != nil else { return nil }
        if dir == currentURL { remember("New Note") { [weak self] in self?.trashSilently(url) } }
        return url
    }

    private func writeLink(_ link: URL, in dir: URL) -> URL? {
        let url = unique(Self.clean(link.host ?? "Link") + ".webloc", in: dir)
        let plist: [String: Any] = ["URL": link.absoluteString]
        guard let data = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0),
              (try? data.write(to: url)) != nil else { return nil }
        return url
    }

    private static func stamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return f.string(from: Date())
    }

    // MARK: Organizing

    /// Documents: Office, iWork, OpenDocument, Google Drive shortcuts, PDF.
    static let documentExtensions: Set<String> = ["doc", "docx", "xls", "xlsx", "xlsm", "csv", "ppt", "pptx", "pages", "numbers", "key",
                                                  "odt", "ods", "odp", "gdoc", "gsheet", "gslides", "gform", "gdraw", "pdf"]

    /// The wand, in a connected folder: loose files go into PhotoBook (pictures), Linker (links), Notepad (notes and
    /// documents' text), Media (video and sound) and Files (the rest) — real folders, made only when needed.
    func organize() {
        guard let dir = currentURL else { return }
        let entries = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: [.isDirectoryKey, .contentTypeKey, .isPackageKey],
                                                                    options: [.skipsHiddenFiles])) ?? []
        var plan: [String: [URL]] = [:]
        for url in entries {
            let v = try? url.resourceValues(forKeys: [.isDirectoryKey, .contentTypeKey, .isPackageKey])
            if v?.isDirectory == true && v?.isPackage != true { continue } // folders stay
            let type = v?.contentType
            let ext = url.pathExtension.lowercased()
            let kind: String
            if type?.conforms(to: .image) == true { kind = "PhotoBook" }
            else if ["webloc", "url", "inetloc"].contains(ext) { kind = "Linker" }
            else if Self.documentExtensions.contains(ext) { kind = "Files" } // Office, iWork, Google, PDF: documents
            else if type?.conforms(to: .audiovisualContent) == true { kind = "Media" }
            else if type?.conforms(to: .plainText) == true || ["rtf", "rtfd", "md", "txt"].contains(ext) { kind = "Notepad" }
            else { kind = "Files" }
            plan[kind, default: []].append(url)
        }
        guard !plan.isEmpty else { Store.shared.flash("Everything here is already in folders"); return }
        var moved: [(from: URL, to: URL)] = []
        var madeFolders: [URL] = []
        for (kind, urls) in plan {
            let folder = dir.appendingPathComponent(kind, isDirectory: true)
            var isDir: ObjCBool = false
            if !FileManager.default.fileExists(atPath: folder.path, isDirectory: &isDir) {
                guard (try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)) != nil else { continue }
                if let tag = FolderStyle.named(kind)?.finderTag { try? (folder as NSURL).setResourceValue([tag.finderName], forKey: .tagNamesKey) }
                madeFolders.append(folder)
            } else if !isDir.boolValue { continue }
            for url in urls {
                let target = unique(url.lastPathComponent, in: folder)
                if (try? FileManager.default.moveItem(at: url, to: target)) != nil { moved.append((url, target)) }
            }
        }
        remember("Organize") {
            for m in moved.reversed() { try? FileManager.default.moveItem(at: m.to, to: m.from) }
            for f in madeFolders where ((try? FileManager.default.contentsOfDirectory(atPath: f.path)) ?? []).filter({ $0 != ".DS_Store" }).isEmpty {
                try? FileManager.default.removeItem(at: f)
            }
        }
        Store.shared.flash("Sorted \(moved.count) into folders — ⌘Z undoes it")
    }
}


// MARK: - Arrange By, in Finder too

extension ConnectedEditor {
    /// Arrange By in a connected folder is Finder's too: the real folder is arranged the same way in Finder
    /// (icon view, and the list view's sort). Finder has no "Date Added" arrangement scripts can set, so that one
    /// becomes Date Created. The first time, macOS asks whether Swiss may control Finder.
    private static let finderQueue = DispatchQueue(label: "Swiss Finder arrange", qos: .userInitiated)

    func arrangeInFinder(_ sort: BoardSort) {
        guard let dir = currentURL else { return }
        let (arrangement, column): (String, String) = switch sort {
        case .manual: ("not arranged", "name column")
        case .name: ("arranged by name", "name column")
        case .kind: ("arranged by kind", "kind column")
        case .added: ("arranged by creation date", "creation date column")
        case .tags: ("arranged by label", "label column")
        }
        // The path goes in as a quoted string (backslashes and quotes escaped), so no file name can change the script.
        let path = dir.path.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = """
        tell application "Finder"
            set theFolder to (POSIX file "\(path)" as alias)
            set arrangement of icon view options of container window of theFolder to \(arrangement)
            try
                set sort column of list view options of container window of theFolder to \(column)
            end try
        end tell
        """
        Self.finderQueue.async { // one at a time, in order — so the last choice is the one Finder keeps
            var error: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&error)
            let failed = error?[NSAppleScript.errorMessage] as? String
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let failed {
                        Store.shared.flash("Finder wasn't arranged: \(failed.prefix(80))")
                    } else {
                        Store.shared.flash(sort == .manual ? "Not arranged — here and in Finder" : "Arranged by \(sort.title) — here and in Finder")
                    }
                }
            }
        }
    }
}
