import AppKit
import QuickLookThumbnailing
import SwiftUI

// MARK: - Connected Folders (read-only)

/// A shortcut to a real folder anywhere on your Mac. Stash shows what's in it — browse, look, open, drag out —
/// but never copies it into the library and never changes it (this first version is read-only).
/// Removing a connection removes only the shortcut; the folder and its files stay exactly as they are.
struct ConnectedFolder: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var path: String
    /// Finds the folder again if it's moved or renamed.
    var bookmark: Data?
    /// The subfolder you were last looking at (relative to the folder).
    var lastSubpath: String = ""
    var addedAt = Date()
}

/// Which connected folder (and which subfolder in it) is on screen.
struct ConnectedLocation: Equatable {
    var folderID: UUID
    var subpath: String
}

/// One file or folder inside a connected folder.
struct ConnectedEntry: Identifiable, Equatable {
    var id: String { url.path }
    let url: URL
    let name: String
    let isFolder: Bool
    let modified: Date?
    let size: Int?
    /// Finder color tags (a folder's color decides the kind it shows as).
    var tags: [String] = []
}

@MainActor
final class ConnectedRegistry: ObservableObject {
    static let shared = ConnectedRegistry()

    @Published private(set) var folders: [ConnectedFolder] = []
    /// Connected folders with a tab open, in the order they were opened. A tab stays while you move between
    /// tabs, until you close it (closing the tab keeps the connection).
    @Published private(set) var openTabs: [UUID] = UserDefaults.standard.stringArray(forKey: "connected.tabs")?.compactMap(UUID.init) ?? []
    private var listURL: URL { Store.shared.dataDir.appendingPathComponent("connected.json") }

    private func saveTabs() { UserDefaults.standard.set(openTabs.map(\.uuidString), forKey: "connected.tabs") }

    /// Closes a connected folder's tab (the folder stays connected, in the sidebar and ··· menu).
    func closeTab(_ id: UUID) {
        openTabs.removeAll { $0 == id }
        saveTabs()
        if Store.shared.connectedView?.folderID == id { Store.shared.connectedView = nil }
    }

    init() { load() }

    private func load() {
        folders = (try? JSONDecoder.iso.decode([ConnectedFolder].self, from: Data(contentsOf: listURL))) ?? []
    }

    private func save() { try? JSONEncoder.iso.encode(folders).write(to: listURL, options: .atomic) }

    func folder(_ id: UUID) -> ConnectedFolder? { folders.first { $0.id == id } }

    /// Connects a folder (or opens it if it's already connected).
    @discardableResult
    func connect(_ url: URL) -> ConnectedFolder? {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        if let existing = folders.first(where: { $0.path == url.path }) { return existing }
        let folder = ConnectedFolder(name: FileManager.default.displayName(atPath: url.path), path: url.path,
                                     bookmark: try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil))
        folders.append(folder)
        save()
        return folder
    }

    /// Asks which folder to connect.
    func chooseAndConnect() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = "Connect"
        panel.message = "Swiss shows these folders as they are — nothing is copied or changed."
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        NSApp.activate()
        guard panel.runModal() == .OK else { return }
        var last: ConnectedFolder?
        for url in panel.urls { last = connect(url) }
        if let last { open(last.id) }
    }

    /// Only the shortcut goes; the folder itself is untouched.
    func remove(_ id: UUID) {
        folders.removeAll { $0.id == id }
        save()
        openTabs.removeAll { $0 == id }
        saveTabs()
        if Store.shared.connectedView?.folderID == id { Store.shared.connectedView = nil }
        Store.shared.flash("Removed the shortcut — the folder itself is untouched")
    }

    func rename(_ id: UUID, to name: String) {
        guard let i = folders.firstIndex(where: { $0.id == id }), !name.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        folders[i].name = name
        save()
    }

    /// Where the folder is now: from its bookmark if it moved, else its saved path. Nil when it can't be found.
    func resolve(_ id: UUID) -> URL? {
        guard let i = folders.firstIndex(where: { $0.id == id }) else { return nil }
        if let data = folders[i].bookmark {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: data, options: [.withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale),
               FileManager.default.fileExists(atPath: url.path) {
                if url.path != folders[i].path || stale {
                    folders[i].path = url.path
                    folders[i].bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                    save()
                }
                return url
            }
        }
        let url = URL(fileURLWithPath: folders[i].path, isDirectory: true)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// The folder went missing: point the shortcut at where it is now.
    func locate(_ id: UUID) {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Use This Folder"
        panel.message = "Where is “\(folder(id)?.name ?? "the folder")” now?"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url, let i = folders.firstIndex(where: { $0.id == id }) else { return }
        folders[i].path = url.path
        folders[i].bookmark = try? url.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
        folders[i].lastSubpath = ""
        save()
        open(id)
    }

    /// Shows it (in its last subfolder) in the window you're in.
    func open(_ id: UUID, subpath: String? = nil) {
        guard let folder = folder(id) else { return }
        let store = Store.shared
        store.showingRecent = false
        store.libraryView = nil
        store.connectedView = ConnectedLocation(folderID: id, subpath: subpath ?? folder.lastSubpath)
        if !openTabs.contains(id) { openTabs.append(id); saveTabs() }
    }

    func remember(_ location: ConnectedLocation) {
        guard let i = folders.firstIndex(where: { $0.id == location.folderID }), folders[i].lastSubpath != location.subpath else { return }
        folders[i].lastSubpath = location.subpath
        save()
    }
}

// MARK: - Live listing of one folder

/// The current folder's contents: read in the background, and refreshed by itself when anything changes in it
/// (from Finder or any app). Only this one level is read — never the whole tree.
@MainActor
final class ConnectedListing: ObservableObject {
    @Published private(set) var entries: [ConnectedEntry] = []
    @Published private(set) var loading = false
    @Published private(set) var missing = false

    private(set) var url: URL?
    private var source: DispatchSourceFileSystemObject?
    private var reloadWork: DispatchWorkItem?

    /// The last listing of folders you've looked at, so coming back to one shows it at once (then it's refreshed).
    private static var remembered: [URL: [ConnectedEntry]] = [:]

    func show(_ url: URL?) {
        guard url != self.url || missing else { return }
        self.url = url
        if let url, let known = Self.remembered[url] { entries = known; missing = false }
        watch(url)
        reload()
    }

    func reload() {
        guard let url else { entries = []; missing = true; return }
        loading = true
        DispatchQueue.global(qos: .userInitiated).async {
            let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .contentModificationDateKey, .fileSizeKey, .localizedNameKey, .tagNamesKey]
            let found = try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])
            let list: [ConnectedEntry] = (found ?? []).map { item in
                let v = try? item.resourceValues(forKeys: Set(keys))
                let folder = (v?.isDirectory ?? false) && !(v?.isPackage ?? false) // apps and bundles open like files
                return ConnectedEntry(url: item, name: v?.localizedName ?? item.lastPathComponent, isFolder: folder,
                                      modified: v?.contentModificationDate, size: v?.fileSize, tags: v?.tagNames ?? [])
            }
            .sorted { a, b in
                a.isFolder != b.isFolder ? a.isFolder : a.name.localizedStandardCompare(b.name) == .orderedAscending
            }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if found != nil {
                        if Self.remembered.count > 40 { Self.remembered.removeAll() }
                        Self.remembered[url] = list
                    }
                    guard self.url == url else { return }
                    if self.entries != list { self.entries = list }
                    self.missing = found == nil
                    self.loading = false
                }
            }
        }
    }

    /// Changes in the folder (a file added, renamed, removed) refresh the view — a few at once count as one.
    private func watch(_ url: URL?) {
        source?.cancel()
        source = nil
        guard let url else { return }
        let fd = open(url.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete, .extend], queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reloadWork?.cancel()
                let work = DispatchWorkItem { MainActor.assumeIsolated { self?.reload() } }
                self?.reloadWork = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
            }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
    }

    deinit { source?.cancel() }
}

/// Small pictures for files in connected folders (Quick Look thumbnails), kept in memory up to a limit.
@MainActor
final class ConnectedThumbnails: ObservableObject {
    static let shared = ConnectedThumbnails()
    private let cache: NSCache<NSString, NSImage> = {
        let c = NSCache<NSString, NSImage>()
        c.countLimit = 600
        c.totalCostLimit = 120 * 1024 * 1024
        return c
    }()
    private var pending: Set<String> = []
    @Published private(set) var version = 0

    func image(for entry: ConnectedEntry, size: CGFloat) -> NSImage? {
        let key = "\(entry.url.path)|\(entry.modified?.timeIntervalSince1970 ?? 0)|\(Int(size))" as NSString
        if let hit = cache.object(forKey: key) { return hit }
        guard !entry.isFolder, !pending.contains(key as String) else { return nil }
        pending.insert(key as String)
        let request = QLThumbnailGenerator.Request(fileAt: entry.url, size: CGSize(width: size, height: size),
                                                   scale: NSScreen.main?.backingScaleFactor ?? 2, representationTypes: .thumbnail)
        QLThumbnailGenerator.shared.generateBestRepresentation(for: request) { rep, _ in
            guard let cg = rep?.cgImage else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
                    self.cache.setObject(image, forKey: key, cost: cg.width * cg.height * 4)
                    self.pending.remove(key as String)
                    self.version += 1
                }
            }
        }
        return nil
    }
}
