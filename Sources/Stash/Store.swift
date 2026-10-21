import AppKit
import SwiftUI

/// Holds the library and saves it to ~/Library/Application Support/Stash.
@MainActor
final class Store: ObservableObject {
    static let shared = Store()

    @Published var projects: [Project] = []
    @Published var folders: [Folder] = [] { didSet { foldersVersion &+= 1 } }
    @Published var pages: [NotebookPage] = []
    @Published var items: [Item] = [] { didSet { itemsVersion &+= 1 } }
    /// Bumped on every change to items / folders, so lookups built from them know when to rebuild.
    var itemsVersion = 0
    var foldersVersion = 0
    var libraryIndex = LibraryIndex()
    var visibleCache = VisibleCache()
    var searchIndex = SearchIndex()
    @Published var filter: Filter = .inbox {
        didSet {
            guard oldValue != filter else { return }
            clipboardHint = nil // moved to another project: the "you copied…" banner is done
            openFolderID = nil
            selection = []
            pendingDelete = nil
            if case .project(let id) = filter, let index = projects.firstIndex(where: { $0.id == id }) {
                projects[index].lastOpened = Date()
                projects[index].tabClosed = nil // opened again: its tab is back
            }
            save(touchesFiles: false)
        }
    }
    /// The folder the board is currently showing, if any.
    @Published var openFolderID: UUID? {
        didSet {
            guard oldValue != openFolderID else { return }
            selection = []
            clipboardHint = nil // moved between folders (prepareForClipboard sets the banner after it opens its folder)
        }
    }
    /// The paste banner for something you just copied. It goes away when you close the window, move to another
    /// project, folder, Recent or All Items, or after 15 seconds.
    @Published var clipboardHint: ClipboardHint? { didSet { scheduleHintExpiry() } }
    private var hintExpiry: DispatchWorkItem?

    private func scheduleHintExpiry() {
        hintExpiry?.cancel()
        guard let shown = clipboardHint else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.clipboardHint == shown else { return }
                withAnimation(.easeOut(duration: 0.2)) { self.clipboardHint = nil }
            }
        }
        hintExpiry = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: work)
    }
    /// Clipboard change count Stash has already reacted to (so old copies don't re-trigger).
    var clipboardSeenCount = NSPasteboard.general.changeCount
    /// Selected cards and folders. Kept apart from the store (see SelectionCenter): selecting redraws only the
    /// tiles that change, not every view that watches the store.
    var selection: Set<Selectable> {
        get { SelectionCenter.shared.ids }
        set { SelectionCenter.shared.set(newValue) }
    }
    /// The image open in the preview window.
    @Published var previewItemID: UUID?
    /// Scrolls the board to this card or folder (after arrow-key moves).
    @Published var scrollTarget: Selectable?
    private var selectionAnchor: Selectable?
    /// Card and folder frames per window, in the board's scrolling coordinates (for box selection).
    var boardFrames: [Bool: [Selectable: CGRect]] = [:]
    /// The visible board area in each window (top-left based), and where the mouse was when a drag began.
    var boardViewports: [Bool: CGRect] = [:]
    var dragStart: NSPoint?
    /// Where the board's contents start in each window (moves as you scroll).
    var boardContentOrigins: [Bool: CGPoint] = [:]
    /// The Recent tab is showing (instead of a project's board).
    @Published var showingRecent = false {
        didSet {
            if showingRecent && !oldValue { keepPlace = currentPlace }
            if showingRecent { connectedView = nil; clipboardHint = nil }
        }
    }
    /// A connected folder (a real folder elsewhere on the Mac) is on screen instead of a board.
    @Published var connectedView: ConnectedLocation? { didSet { if connectedView != nil { clipboardHint = nil } } }
    /// Where the sidebar's Connected heading is (drop a folder there to connect it).
    var connectDropFrame: CGRect?
    @Published var connectDropTargeted = false
    /// The big window's sidebar can show everything at once: All Items, or everything with one colour tag.
    @Published var libraryView: LibraryView? {
        didSet { if libraryView != nil { connectedView = nil; clipboardHint = nil } }
    }
    /// Where Keep puts things: the project/folder you were in before opening Recent.
    var keepPlace = Place()
    /// How much the small board is zoomed (the floating frame; 1 in the pop-up). Drag maths divides by it.
    var boardZoom: CGFloat = 1
    /// The All Projects overview (the grid button by the tabs).
    @Published var showingAllProjects = false
    @Published var search = ""
    @Published var isDropTargeted = false
    @Published var toast: String?
    /// The toast offers Undo (for deletes, moves, renames, clears, restores, downloads).
    @Published var toastUndo = false
    @Published var focusRequest = 0
    /// The note composer is open.
    @Published var composingNote = false
    /// Names of existing folders the organize button would add to, while it asks what to do.
    @Published var organizePrompt: [String]?
    /// Things waiting for "keep the folders' items or delete them too?"
    @Published var pendingDelete: Set<Selectable>?
    /// A project waiting for "keep its things or delete them?"
    @Published var pendingProjectDelete: UUID?
    /// A folder whose name is being edited inline.
    @Published var renamingFolderID: UUID?
    /// A project tab whose name is being edited inline.
    @Published var renamingProjectID: UUID?
    /// "Rename N Items…" is open for these.
    @Published var pendingBatchRename: Set<Selectable>?
    /// A picture, file or link whose name is being edited.
    @Published var renamingItemID: UUID?
    /// The folder a drag is currently hovering over.
    @Published var dropFolderID: UUID?
    /// The card or folder being dragged inside Stash.
    var draggingItemID: UUID?
    var draggingFolderID: UUID?
    /// Drop target meaning "the project's board" (used by the Back arrow and the path).
    static let boardDropID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    /// Folder tile frames per window (compact or not), in the window's top-left coordinates.
    var folderFrames: [Bool: [UUID: CGRect]] = [:]

    /// ~/Documents/.Stash — the folder that mirrors the app.
    let rootDir: URL
    /// ~/Documents/.Stash/.stash — Stash's own data.
    let dataDir: URL
    /// Link and file previews.
    let imagesDir: URL
    var libraryURL: URL { dataDir.appendingPathComponent("library.json") }
    /// Things deleted in the last 30 days, newest first (Recently Deleted).
    @Published var recentlyDeleted: [DeletedRecord] = []
    @Published var showingRecentlyDeleted = false
    /// Goes up with every save; the newest one wins if several are waiting to be written.
    var revision = 0
    var mirrorPaths: [UUID: String] = [:]
    var mirrorDirs: [String: String] = [:]
    var mirrorScheduled = false
    /// What the mirror last wrote for each thing (path, content, tags), so ordinary changes only touch what changed.
    var mirrorPrints: [UUID: String] = [:]
    var folderPrints: [UUID: String] = [:]
    /// The last time the mirror checked every file on disk (at launch, then every few minutes).
    var lastFullMirror: Date?
    /// Files being copied in right now.
    var copying: Set<UUID> = []
    /// What All Items (or a tag) shows right now, in order — for Select All.
    var libraryShown: [UUID] = []
    /// Files whose copy was cancelled or couldn't be made (no room…): kept as links for now.
    var keepLinked: Set<UUID> = []
    /// Files being converted to MP3/MP4 right now.
    @Published var converting: Set<UUID> = []
    /// Downloads/conversions that didn't work, by the link or file they were made from.
    @Published var jobFailures: [UUID: JobFailure] = [:]
    /// The project tab (or sidebar project) something is being dragged over, and where those are on screen.
    @Published var dropProjectID: UUID?
    var projectDropFrames: [UUID: CGRect] = [:]
    /// Running downloads (so they can be cancelled) and ones you cancelled.
    var jobProcesses: [UUID: Process] = [:]
    var cancelledJobs: Set<UUID> = []
    /// MP3s/MP4s still being made (shown as loading cards).
    @Published var pending: [PendingResult] = []
    /// After a link download: asking whether to delete the link.
    @Published var linkCleanup: LinkCleanup?
    /// Pictures on screen, kept in memory up to a limit (macOS frees them when it needs room).
    /// The library folder (with a trailing /), for code off the main thread.
    nonisolated(unsafe) static var libraryRootPath = ""
    let thumbCache: NSCache<NSString, NSImage> = {
        let cache = NSCache<NSString, NSImage>()
        cache.countLimit = 500
        cache.totalCostLimit = 200 * 1024 * 1024
        return cache
    }()
    var undoStack: [UndoStep] = []
    var redoStack: [UndoStep] = []
    var undoGroupDepth = 0
    /// False if library.json existed but couldn't be read — then no files get cleaned up.
    var libraryReadable = true
    /// Set when the library had to be restored from a backup at launch (shown once).
    var recoveryNote: String?
    private var toastTask: Task<Void, Never>?

    struct Library: Codable {
        /// Format version and a counter that goes up with every save (both optional so older files still load).
        var schemaVersion: Int?
        var revision: Int?
        var projects: [Project]
        var folders: [Folder]?
        var pages: [NotebookPage]?
        var items: [Item]
        var filter: Filter
    }

    private init() {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        // STASH_LIBRARY points a test run at a separate folder (Swiss Test only).
        rootDir = (TestMode.isOn ? ProcessInfo.processInfo.environment["STASH_LIBRARY"] : nil).map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? (TestMode.isOn ? TestMode.defaultLibrary : documents.appendingPathComponent(".Stash", isDirectory: true))
        dataDir = rootDir.appendingPathComponent(".stash", isDirectory: true)
        Store.libraryRootPath = rootDir.path + "/"
        imagesDir = dataDir.appendingPathComponent("previews", isDirectory: true)
        try? FileManager.default.createDirectory(at: imagesDir, withIntermediateDirectories: true)
        // Only you can open Swiss's folders (not other accounts on this Mac).
        for dir in [rootDir, dataDir, TestMode.supportDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
        }
        Store.migrateOldLibrary(into: dataDir, thumbs: imagesDir)
        // Copies handed out last time (drags, Quick Look, link notes) aren't needed any more.
        Store.removeTemporaryFiles()
        DispatchQueue.global(qos: .utility).async { Store.removeDuplicateDownloader() }
        load()
        loadDeleted()
        if libraryReadable {
            if filter == .inbox || items.contains(where: { $0.projectID == nil })
                || folders.contains(where: { $0.projectID == nil }) { ensureProjectHome(makeIfNone: false); writeLibrary() }
            cleanUpFiles()
            mirrorPaths = Dictionary(uniqueKeysWithValues: items.compactMap { item in item.storedPath.map { (item.id, $0) } })
            resetOldPopUpSpots()
            shrinkOldPreviews()
            syncMirror()
            exportSavedProjects()
        }
    }

    // MARK: Persistence

    private func load() {
        let fm = FileManager.default
        // The library, then the previous good version, then the hourly backups (newest first).
        let candidates = [libraryURL, previousLibraryURL] + Self.backupFiles(in: backupsDir)
        guard candidates.contains(where: { fm.fileExists(atPath: $0.path) }) else { return } // a brand-new library
        var loaded: (Library, URL)?
        for url in candidates {
            if let lib = Self.decodeLibrary(at: url) { loaded = (lib, url); break }
        }
        guard let (lib, source) = loaded else {
            // Nothing readable at all: keep every file as it is and don't save over them.
            libraryReadable = false
            return
        }
        if source != libraryURL {
            // Recovered from a backup. Keep the damaged file aside, never overwrite it.
            if fm.fileExists(atPath: libraryURL.path) {
                let aside = dataDir.appendingPathComponent("library-unreadable-\(Int(Date().timeIntervalSince1970)).json")
                try? fm.moveItem(at: libraryURL, to: aside)
            }
            try? fm.copyItem(at: source, to: libraryURL)
            let when = ((try? source.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? Date())
                .formatted(date: .abbreviated, time: .shortened)
            recoveryNote = "Your library was damaged — Swiss restored it from a backup (\(when))."
        }
        revision = lib.revision ?? 0
        projects = lib.projects
        folders = (lib.folders ?? []).map(Self.renamingOldDefault).map { folder in
            // Kraft, Pastel and Midnight folders are Classic now.
            var f = folder
            if [.kraft, .pastel, .midnight].contains(f.style) { f.style = .classic }
            return f
        }
        pages = lib.pages ?? []
        items = lib.items
        filter = lib.filter == .all ? .inbox : lib.filter // there's no "All" tab any more
    }

    /// Folders the organize button made under the old names ("Photos", "Note Hanger 2"…) get the new ones.
    private static func renamingOldDefault(_ folder: Folder) -> Folder {
        let old: [FolderStyle: String] = [.photos: "Photos", .noteHanger: "Note Hanger"]
        guard let oldName = old[folder.style] else { return folder }
        var renamed = folder
        if folder.name == oldName {
            renamed.name = folder.style.name
        } else if folder.name.hasPrefix(oldName + " "), Int(folder.name.dropFirst(oldName.count + 1)) != nil {
            renamed.name = folder.style.name + folder.name.dropFirst(oldName.count)
        }
        return renamed
    }

    /// Saves the library, then brings the folder in Documents in line with it.
    /// Saves the library. `touchesFiles: false` is for changes nothing on disk depends on (which tab is open,
    /// where tiles sit, pins), so the mirror in Documents isn't checked over again for them.
    func save(touchesFiles: Bool = true) {
        // No "Not Selected" any more: anything without a project goes to Unsorted first.
        if libraryReadable, filter == .inbox || items.contains(where: { $0.projectID == nil })
            || folders.contains(where: { $0.projectID == nil }) {
            ensureProjectHome(makeIfNone: false) // no projects at all is fine: Recent is there
        }
        Perf.measure("writeLibrary (main-thread part)") { writeLibrary() }
        if libraryReadable, touchesFiles { scheduleMirror() }
    }

    /// Hands a snapshot of the library to the background writer (see Persistence.swift). Never saves over
    /// a library that couldn't be read.
    func writeLibrary() {
        guard libraryReadable else { return }
        revision += 1
        let lib = Library(schemaVersion: Self.schemaVersion, revision: revision, projects: projects, folders: folders,
                          pages: pages, items: items, filter: filter)
        Self.persist(lib, to: libraryURL, previous: previousLibraryURL, backups: backupsDir)
    }

    // MARK: Queries

    var openFolder: Folder? { openFolderID.flatMap(folder) }

    func folder(_ id: UUID) -> Folder? { folders.first { $0.id == id } }

    /// Where new things go: the open folder, else the selected project (or Not Selected).
    var currentPlace: Place {
        if let folder = openFolder { return Place(project: folder.projectID, folder: folder.id) }
        if case .project(let id) = filter { return Place(project: id) }
        return Place()
    }

    var dropTargetName: String {
        if let folder = openFolder { return folder.displayName }
        return name(for: currentPlace.project)
    }

    func name(for projectID: UUID?) -> String {
        guard let projectID else { return "Not Selected" }
        return projects.first { $0.id == projectID }?.name ?? "Not Selected"
    }

    /// The tabs: Not Selected (things in no project), then each project.
    /// ⌃Tab steps through the open tabs only (a closed tab stays closed until you open its project).
    var allFilters: [Filter] {
        let open = projects.filter { $0.tabClosed != true || filter == .project($0.id) }.map { Filter.project($0.id) }
        return open.isEmpty ? [filter] : open
    }

    func matches(_ projectID: UUID?, _ filter: Filter) -> Bool {
        switch filter {
        case .all: true
        case .inbox: projectID == nil
        case .project(let id): projectID == id
        }
    }

    func count(_ filter: Filter) -> Int {
        switch filter {
        case .project(let id): index.itemsInProject[id] ?? 0
        default: items.lazy.filter { self.matches($0.projectID, filter) }.count
        }
    }

    func count(in folder: Folder) -> Int { index.itemsInFolder[folder.id] ?? 0 }

    var isSearching: Bool { !search.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Folders shown on the board: the ones in the folder you're in (or on the board itself). None while searching.
    /// The tab's name, for "Search Project…".
    var tabTitle: String {
        if let location = connectedView { return ConnectedRegistry.shared.folder(location.folderID)?.name ?? "Folder" }
        switch libraryView {
        case .allItems?: return "All Items"
        case .tag(let tag)?: return tag.title
        case nil: break
        }
        if case .project(let id) = filter { return projects.first { $0.id == id }?.name ?? "Project" }
        return "Not Selected"
    }

    var visibleFolders: [Folder] {
        let key = visibleKey
        if let hit = visibleCache.folders, visibleCache.foldersKey == key { return hit }
        let result = computeVisibleFolders()
        visibleCache.folders = result
        visibleCache.foldersKey = key
        return result
    }

    private func computeVisibleFolders() -> [Folder] {
        if isSearching {
            // Search: folders anywhere in this tab (the project, or Not Selected) whose name matches.
            let terms = search.lowercased().split(separator: " ").map(String.init)
            return folders.filter { folder in
                matches(folder.projectID, filter) && terms.allSatisfy { folder.name.lowercased().contains($0) }
            }
        }
        let here = folders.filter { matches($0.projectID, filter) && $0.parentID == openFolderID }
        switch BoardSort.current {
        case .manual:
            // Numbered in reading order of where you've put them; new ones after.
            let compact = !(AppDelegate.shared?.panel?.isVisible ?? false)
            func rank(_ f: Folder) -> (Int, Double) {
                guard let p = spot(of: f, compact: compact) else { return (Int.max, 0) }
                return (Int(p.y / 60), p.x)
            }
            return here.enumerated().sorted { a, b in
                let ra = rank(a.element), rb = rank(b.element)
                return ra != rb ? ra < rb : a.offset < b.offset
            }.map(\.element)
        case .added: return here.sorted { $0.createdAt > $1.createdAt }
        case .name: return here.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind: return here.sorted { ($0.style.rawValue, $0.name) < ($1.style.rawValue, $1.name) }
        case .tags: return here.sorted { (BoardSort.tagRank($0.colorTags), $0.name) < (BoardSort.tagRank($1.colorTags), $1.name) }
        }
    }

    func subfolderCount(in folder: Folder) -> Int { index.foldersInFolder[folder.id] ?? 0 }

    /// These folders plus every folder inside them, however deep.
    func withDescendants(_ ids: Set<UUID>) -> Set<UUID> {
        var result = ids, frontier = ids
        while !frontier.isEmpty {
            let next = Set(folders.filter { $0.parentID.map(frontier.contains) ?? false }.map(\.id)).subtracting(result)
            result.formUnion(next)
            frontier = next
        }
        return result
    }

    /// The folders above this one, outermost first.
    func ancestors(of id: UUID) -> [Folder] {
        var chain: [Folder] = []
        var current = folder(id)?.parentID
        while let id = current, let f = folder(id), !chain.contains(where: { $0.id == id }) {
            chain.insert(f, at: 0)
            current = f.parentID
        }
        return chain
    }

    /// Cards shown on the board: the open folder's, or loose ones. Search looks everywhere.
    var visibleItems: [Item] {
        let key = visibleKey
        if let hit = visibleCache.items, visibleCache.itemsKey == key { return hit }
        let result = computeVisibleItems()
        visibleCache.items = result
        visibleCache.itemsKey = key
        return result
    }

    private func computeVisibleItems() -> [Item] {
        let terms = search.lowercased().split(separator: " ").map(String.init)
        if !terms.isEmpty {
            return items.filter { item in
                matches(item.projectID, filter) && terms.allSatisfy { searchableText(item).contains($0) }
            }
        }
        let here = openFolderID.map { id in items.filter { $0.folderID == id } }
            ?? items.filter { $0.folderID == nil && matches($0.projectID, filter) }
        return BoardSort.current.sorted(here)
    }

    /// Show in Finder: the folder in Documents for where you are.
    func revealCurrentFolder() {
        let key = openFolderID.map { "f:" + $0.uuidString } ?? "p:" + (currentPlace.project?.uuidString ?? "none")
        let url = mirrorDirs[key].map(absolute) ?? rootDir
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A few images from a folder, shown peeking out of its icon.
    func previewImages(for folder: Folder, limit: Int = 3) -> [NSImage] {
        items.lazy
            .filter { $0.folderID == folder.id }
            .compactMap { self.displayImage($0) }
            .prefix(limit)
            .map { $0 }
    }

    // MARK: Items

    func add(_ item: Item) {
        checkpoint("Add")
        var item = item
        if item.projectID == nil { item.projectID = currentPlace.project ?? ensureProjectHome() }
        withAnimation(.spring(duration: 0.3)) { items.insert(item, at: 0) }
        save()
        RecentStore.shared.noteSaved(item.id) // it shows in Recent too — the same thing, not a copy
        let place = item.folderID.flatMap(folder)?.displayName ?? name(for: item.projectID)
        flash("Saved to \(place)")
        NotificationCenter.default.post(name: .stashDidSave, object: nil)
    }

    func update(_ id: UUID, _ change: (inout Item) -> Void) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        change(&items[index])
        save()
    }

    // MARK: Folders

    func addFolder(_ folder: Folder) {
        checkpoint("New Folder")
        folders.append(folder)
        save()
    }

    /// Creates a folder where you are and starts renaming it.
    func newFolder(style: FolderStyle = .classic) {
        checkpoint("New Folder")
        // Made inside the folder you're in.
        let project = currentPlace.project
        let base = style == .classic ? "New Folder" : style.name
        let folder = Folder(name: uniqueFolderName(base, in: project), style: style, projectID: project, parentID: openFolderID)
        let chosen = selectedHere
        withAnimation(.spring(duration: 0.3)) {
            folders.append(folder)
            adopt(chosen, into: folder)
        }
        selection = [.folder(folder.id)]
        renamingFolderID = folder.id // name it now — Return keeps the plain name
        save()
    }

    /// Naming a folder shows the name under its icon; an empty name goes back to just the icon.
    func renameFolder(_ id: UUID, to name: String) {
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed != folders[index].name else { return } // kept its name
        checkpoint("Rename")
        if trimmed.isEmpty {
            return // keeps its name
        } else {
            folders[index].name = trimmed
            folders[index].isNamed = true
        }
        save()
    }

    /// Renames a picture, file or link (its file in Documents is renamed too). Notes are named by their first line.
    func renameItem(_ id: UUID, to name: String) {
        renamingItemID = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, let item = items.first(where: { $0.id == id }), item.kind != .text else { return }
        checkpoint("Rename")
        update(id) { item in
            if item.kind == .file || item.kind == .image {
                // Keep the file type: "poster" → "poster.jpg".
                let ext = ((item.title ?? item.storedPath ?? "") as NSString).pathExtension
                item.title = ext.isEmpty || (trimmed as NSString).pathExtension.lowercased() == ext.lowercased() ? trimmed : trimmed + "." + ext
            } else {
                item.title = trimmed
            }
        }
    }

    /// Return on the board: rename what's selected (like Finder). Notes open for editing instead.
    func renameSelection() {
        guard selection.count == 1, let target = selection.first else { return }
        switch target {
        case .folder(let id): renamingFolderID = id
        case .item(let id): renamingItemID = id
        }
    }

    func setStyle(_ style: FolderStyle, for id: UUID) {
        checkpoint("Folder Style")
        guard let index = folders.firstIndex(where: { $0.id == id }) else { return }
        withAnimation { folders[index].style = style }
        save()
    }

    // MARK: Deleting

    /// Deletes cards and folders. If a folder still has things inside, asks first
    /// whether to keep them on the board or delete them too.
    /// Deleting just deletes — folders go with everything inside them. (⌘Z brings it back.)
    func requestDelete(_ targets: Set<Selectable>) {
        guard !targets.isEmpty else { return }
        performDelete(targets, keepFolderContents: false)
    }

    /// Deletes cards and folders. Keeping contents moves what was inside up one level;
    /// otherwise folders inside are deleted too, with everything in them.
    /// Everything in this tab (the project, or Not Selected): its folders with all they hold, and loose things.
    var tabContents: Set<Selectable> {
        Set(folders.filter { $0.parentID == nil && matches($0.projectID, filter) }.map { Selectable.folder($0.id) }
            + items.filter { $0.folderID == nil && matches($0.projectID, filter) }.map { Selectable.item($0.id) })
    }

    /// The bottom bar's Clear: empties this tab. ⌘Z brings it all back.
    func clearCurrentTab() {
        let all = tabContents
        guard !all.isEmpty else { NSSound.beep(); return }
        openFolderID = nil
        performDelete(all, keepFolderContents: false)
        flash("Cleared — it's in Recently Deleted", undo: true)
    }

    /// Clear in All Items (or a color tag's list): everything it shows is deleted from its project. Connected folders
    /// aren't part of it. ⌘Z brings it all back.
    func clearLibraryShown() {
        let all = Set(libraryShown.map { Selectable.item($0) })
        guard !all.isEmpty else { NSSound.beep(); return }
        performDelete(all, keepFolderContents: false)
        flash("Deleted \(plural(all.count, "item")) from their projects — they're in Recently Deleted", undo: true)
    }

    func performDelete(_ targets: Set<Selectable>, keepFolderContents: Bool) {
        if !targets.isEmpty { DeleteSound.play() }
        guard !targets.isEmpty else { pendingDelete = nil; return }
        checkpoint("Delete")
        pendingDelete = nil
        let picked = Set(targets.folderIDs)
        let gone = keepFolderContents ? picked : withDescendants(picked)
        let doomedItems = Set(targets.itemIDs).union(
            keepFolderContents ? [] : items.filter { $0.folderID.map(gone.contains) ?? false }.map(\.id)
        )
        // Recently Deleted keeps them (and their files) for 30 days.
        recordDeletion(folders: folders.filter { gone.contains($0.id) }, items: items.filter { doomedItems.contains($0.id) })
        // Where things inside a deleted folder go: the nearest folder above that stays.
        let parents = Dictionary(uniqueKeysWithValues: folders.map { ($0.id, $0.parentID) })
        func survivor(_ id: UUID?) -> UUID? {
            var current = id
            while let c = current, gone.contains(c) { current = parents[c] ?? nil }
            return current
        }
        withAnimation(.spring(duration: 0.3)) {
            for item in items where doomedItems.contains(item.id) && item.kind != .image {
                if let file = item.imageFile {
                    trashImage(file)
                    thumbCache.removeObject(forKey: file as NSString)
                }
            }
            items.removeAll { doomedItems.contains($0.id) }
            for index in items.indices where items[index].folderID.map(gone.contains) ?? false {
                items[index].folderID = survivor(items[index].folderID)
            }
            for index in folders.indices where !gone.contains(folders[index].id) && (folders[index].parentID.map(gone.contains) ?? false) {
                folders[index].parentID = survivor(folders[index].parentID)
            }
            folders.removeAll { gone.contains($0.id) }
            selection.subtract(targets)
            if let open = openFolderID, gone.contains(open) { openFolderID = survivor(open) }
        }
        save()
        var parts: [String] = []
        if !gone.isEmpty { parts.append(plural(gone.count, "folder")) }
        if !doomedItems.isEmpty { parts.append(plural(doomedItems.count, "item")) }
        flash("Deleted " + parts.joined(separator: " and "), undo: true)
    }

    func plural(_ n: Int, _ word: String) -> String { "\(n) \(word)\(n == 1 ? "" : "s")" }

    // MARK: Selection

    /// Everything on the board, in the order you see it (for shift-click ranges).
    var visibleOrder: [Selectable] {
        visibleFolders.map { .folder($0.id) } + visibleItems.map { .item($0.id) }
    }

    /// Click = select just this, ⌘-click = add/remove, shift-click = select the range.
    func click(_ target: Selectable, modifiers: NSEvent.ModifierFlags) {
        if modifiers.contains(.command) {
            if selection.contains(target) { selection.remove(target) } else { selection.insert(target) }
            selectionAnchor = target
        } else if modifiers.contains(.shift), let b = clickOrder.firstIndex(of: target),
                  let a = rangeAnchor(in: clickOrder, near: b) {
            // From the last thing clicked (or, after a box or ⌘A, the nearest selected thing) to this one.
            selection.formUnion(clickOrder[min(a, b)...max(a, b)])
        } else {
            selection = [target]
            selectionAnchor = target
        }
    }

    /// The order things are shown in, for ⇧-click ranges: the board, or the All Items / tag list.
    private var clickOrder: [Selectable] {
        libraryView != nil && !showingRecent ? libraryShown.map { Selectable.item($0) } : visibleOrder
    }

    private func rangeAnchor(in order: [Selectable], near index: Int) -> Int? {
        if let anchor = selectionAnchor, selection.contains(anchor), let a = order.firstIndex(of: anchor) { return a }
        let picked = order.indices.filter { selection.contains(order[$0]) }
        return picked.min { abs($0 - index) < abs($1 - index) }
    }

    /// ⌘A / ⌃A: everything you're looking at — the board, or the All Items / tag list.
    func selectAll() {
        if showingRecent {
            RecentStore.shared.selection = Set(RecentStore.shared.shownIDs)
        } else if libraryView != nil {
            selection = Set(libraryShown.map { Selectable.item($0) })
        } else {
            selection = Set(visibleOrder)
        }
    }

    // MARK: Color tags

    func tags(of target: Selectable) -> [TagColor] {
        switch target {
        case .item(let id): items.first { $0.id == id }?.colorTags ?? []
        case .folder(let id): folder(id)?.colorTags ?? []
        }
    }

    func allHave(_ tag: TagColor, _ targets: Set<Selectable>) -> Bool {
        !targets.isEmpty && targets.allSatisfy { tags(of: $0).contains(tag) }
    }

    /// Adds the tag to all of them — or, if they all have it already, takes it off.
    func toggleTag(_ tag: TagColor, on targets: Set<Selectable>) {
        let remove = allHave(tag, targets)
        setTags(on: targets) { tags in
            if remove { tags.removeAll { $0 == tag } } else if !tags.contains(tag) { tags.append(tag) }
        }
    }

    func clearTags(on targets: Set<Selectable>) { setTags(on: targets) { $0.removeAll() } }

    private func setTags(on targets: Set<Selectable>, _ change: (inout [TagColor]) -> Void) {
        checkpoint("Tags")
        for index in items.indices where targets.contains(.item(items[index].id)) {
            var tags = items[index].colorTags ?? []
            change(&tags)
            items[index].colorTags = tags.isEmpty ? nil : tags
        }
        for index in folders.indices where targets.contains(.folder(folders[index].id)) {
            var tags = folders[index].colorTags ?? []
            change(&tags)
            folders[index].colorTags = tags.isEmpty ? nil : tags
        }
        save()
    }

    // MARK: Renaming several at once

    /// "Rename N Items…": base name + a number, in the order they're shown ("Poster 1", "Poster 2"…).
    /// Pictures and files keep their type; notes are named by their text, so they're left alone.
    func batchRename(_ targets: Set<Selectable>, base: String, start: Int) {
        let name = base.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        checkpoint("Rename")
        var number = start
        for target in visibleOrder where targets.contains(target) {
            switch target {
            case .folder(let id):
                guard let index = folders.firstIndex(where: { $0.id == id }) else { continue }
                folders[index].name = "\(name) \(number)"
                folders[index].isNamed = true
            case .item(let id):
                guard let index = items.firstIndex(where: { $0.id == id }), items[index].kind != .text else { continue }
                let ext = ((items[index].title ?? items[index].storedPath ?? "") as NSString).pathExtension
                let keepsType = items[index].kind == .file || items[index].kind == .image
                items[index].title = keepsType && !ext.isEmpty ? "\(name) \(number).\(ext)" : "\(name) \(number)"
            }
            number += 1
        }
        pendingBatchRename = nil
        save()
        flash("Renamed \(describe(targets))", undo: true)
    }

    /// 1–9 on the board: open the folder with that number (the order they're shown in).
    /// ⌥1–⌥9: puts what's selected into the folder with that number (folders can go in too, not into themselves).
    func putSelection(intoFolderNumber number: Int) {
        let shown = visibleFolders
        guard number <= shown.count else { NSSound.beep(); return }
        let target = shown[number - 1]
        var moving = selection
        moving.remove(.folder(target.id))
        guard !moving.isEmpty else { flash("Select something first, then ⌥\(number) puts it in \(target.displayName)"); return }
        put(moving, into: target.id)
    }

    func openFolder(number: Int) {
        let folders = visibleFolders
        guard number <= folders.count else { NSSound.beep(); return }
        openFolderID = folders[number - 1].id
    }

    /// ⌃Tab: the next project tab (wraps around).
    func stepTab(_ offset: Int) {
        let tabs = allFilters
        guard let index = tabs.firstIndex(of: filter) else { return }
        filter = tabs[(index + offset + tabs.count) % tabs.count]
    }

    var previewItem: Item? { previewItemID.flatMap { id in items.first { $0.id == id } } }

    /// The images the preview window steps through: the ones on the board right now.
    var previewableItems: [Item] { visibleItems.filter { $0.kind == .image && contentURL($0) != nil } }

    func stepPreview(_ offset: Int) {
        let list = previewableItems
        guard !list.isEmpty else { return }
        let index = list.firstIndex { $0.id == previewItemID } ?? 0
        let next = list[(index + offset + list.count) % list.count]
        previewItemID = next.id
        selection = [.item(next.id)]
        selectionAnchor = .item(next.id)
        scrollTarget = .item(next.id)
    }

    /// Return / double-click: open a folder, preview an image, open a link or file.
    func openSelection() {
        if selection.count == 1, let id = selection.folderIDs.first {
            withAnimation(.spring(duration: 0.3)) { openFolderID = id }
            return
        }
        let chosen = items.filter { selection.contains(.item($0.id)) }
        if chosen.count == 1, chosen[0].kind == .image {
            AppDelegate.shared.preview(chosen[0].id)
            return
        }
        chosen.forEach(open)
    }

    enum Direction { case left, right, up, down }

    /// Arrow keys: select the nearest card or folder in that direction (shift extends the selection).
    func moveSelection(_ direction: Direction, extend: Bool, compact: Bool) {
        let order = visibleOrder
        guard let first = order.first else { return }
        let frames = boardFrames[compact] ?? [:]
        guard let current = selectionAnchor.flatMap({ order.contains($0) && selection.contains($0) ? $0 : nil }) ?? selection.first,
              let from = frames[current] else {
            select(first, extend: false)
            return
        }
        var best: (Selectable, CGFloat)?
        for target in order where target != current {
            guard let frame = frames[target] else { continue }
            let dx = frame.midX - from.midX, dy = frame.midY - from.midY
            let ahead: Bool, along: CGFloat, across: CGFloat
            switch direction {
            case .right: (ahead, along, across) = (dx > 1, dx, dy)
            case .left: (ahead, along, across) = (dx < -1, -dx, dy)
            case .down: (ahead, along, across) = (dy > 1, dy, dx)
            case .up: (ahead, along, across) = (dy < -1, -dy, dx)
            }
            guard ahead else { continue }
            let score = along + abs(across) * 2
            if best == nil || score < best!.1 { best = (target, score) }
        }
        if let target = best?.0 { select(target, extend: extend) }
    }

    private func select(_ target: Selectable, extend: Bool) {
        if extend { selection.insert(target) } else { selection = [target] }
        selectionAnchor = target
        scrollTarget = target
    }

    func clearSelection() {
        if !selection.isEmpty { selection = [] }
    }

    /// What a right-click acts on: the whole selection if you clicked inside it, else just that thing.
    func targets(for target: Selectable) -> Set<Selectable> {
        selection.contains(target) ? selection : [target]
    }

    /// Moves cards and folders (with everything inside them) to a project.
    func moveToProject(_ targets: Set<Selectable>, project: UUID?) {
        checkpoint("Move")
        let picked = Set(targets.folderIDs)
        let moving = withDescendants(picked)
        let itemIDs = Set(targets.itemIDs)
        withAnimation(.spring(duration: 0.3)) {
            for index in folders.indices where moving.contains(folders[index].id) {
                folders[index].projectID = project
                // Picked folders land on the project's board; folders inside them stay where they are.
                if picked.contains(folders[index].id), !(folders[index].parentID.map(moving.contains) ?? false) {
                    folders[index].parentID = nil
                }
            }
            for index in items.indices {
                if items[index].folderID.map(moving.contains) ?? false {
                    items[index].projectID = project
                } else if itemIDs.contains(items[index].id) {
                    items[index].projectID = project
                    items[index].folderID = nil
                }
            }
            selection.subtract(targets)
        }
        save()
        flash("Moved \(describe(targets)) to \(name(for: project))", undo: true)
    }

    /// Puts several cards into a folder (nil = onto the project's board).
    func putInFolder(_ itemIDs: [UUID], folder folderID: UUID?) {
        put(Set(itemIDs.map { .item($0) }), into: folderID)
    }

    /// What's selected on the board you're looking at (a new folder takes it in, like Finder's New Folder with Selection).
    var selectedHere: Set<Selectable> {
        guard !selection.isEmpty, !showingRecent, connectedView == nil, libraryView == nil else { return [] }
        let here = Set(visibleOrder)
        return selection.filter { here.contains($0) }
    }

    /// Moves cards and folders into a folder that was just made in the same place (part of its "New Folder" undo step).
    func adopt(_ targets: Set<Selectable>, into folder: Folder) {
        guard !targets.isEmpty else { return }
        let ids = Set(targets.itemIDs), folderIDs = Set(targets.folderIDs).subtracting([folder.id])
        for index in items.indices where ids.contains(items[index].id) { items[index].folderID = folder.id }
        for index in folders.indices where folderIDs.contains(folders[index].id) { folders[index].parentID = folder.id }
        flash("Put \(describe(targets)) in the new folder")
    }

    /// Puts cards and folders into a folder (nil = onto the project's board).
    /// A folder can't go inside itself or a folder within it.
    func put(_ targets: Set<Selectable>, into folderID: UUID?) {
        checkpoint("Move")
        let target = folderID.flatMap(folder)
        let ids = Set(targets.itemIDs)
        let folderIDs = targets.folderIDs.filter { id in
            guard let target else { return true }
            return !withDescendants([id]).contains(target.id)
        }
        withAnimation(.spring(duration: 0.3)) {
            for index in items.indices where ids.contains(items[index].id) {
                items[index].folderID = target?.id
                if let target { items[index].projectID = target.projectID }
            }
            let moving = withDescendants(Set(folderIDs))
            for index in folders.indices where folderIDs.contains(folders[index].id) {
                folders[index].parentID = target?.id
            }
            if let target {
                for index in folders.indices where moving.contains(folders[index].id) { folders[index].projectID = target.projectID }
                for index in items.indices where items[index].folderID.map(moving.contains) ?? false { items[index].projectID = target.projectID }
            }
            selection.subtract(targets)
        }
        save()
        let count = ids.count + folderIDs.count
        flash(target.map { "Moved \(plural(count, count == ids.count ? "item" : "thing")) to \($0.displayName)" } ?? "Moved up", undo: true)
    }

    func describe(_ targets: Set<Selectable>) -> String {
        let f = targets.folderIDs.count, i = targets.itemIDs.count
        if f > 0 && i > 0 { return "\(plural(f, "folder")) and \(plural(i, "item"))" }
        if f > 0 { return f == 1 ? (folder(targets.folderIDs[0])?.name ?? "folder") : plural(f, "folder") }
        return plural(i, "item")
    }

    // MARK: Organizing

    /// Where the wand works: the folder you're in (default), or the project's board.
    private var organizeContainer: Folder? {
        OrganizerSettings.wandWorksInOpenFolder ? openFolder : nil
    }

    /// The loose things the wand would sort, each with the folder level its kind folder belongs in.
    /// Inside a Linker/PhotoBook/Notepad/Files folder, things that already fit stay put and the
    /// rest go to the right kind folder next to it.
    private func organizePlan() -> [(index: Int, style: FolderStyle, project: UUID?, parent: UUID?)] {
        let container = organizeContainer
        return items.indices.compactMap { index in
            let item = items[index]
            guard item.folderID == container?.id, matches(item.projectID, filter) else { return nil }
            let style = item.organizeStyle
            if let container, container.style.isKind {
                if container.style == style { return nil }
                return (index, style, item.projectID, container.parentID)
            }
            return (index, style, item.projectID, container?.id)
        }
    }

    private func existingFolder(_ style: FolderStyle, project: UUID?, parent: UUID?) -> Folder? {
        folders.first { $0.style == style && $0.projectID == project && $0.parentID == parent }
    }

    /// The wand. If some of the folders it would use already exist, asks (or follows the
    /// setting) whether to add to them or make new ones.
    func requestOrganize() {
        if connectedView != nil, !showingRecent { ConnectedEditor.shared.organize(); return } // sorts the real folder
        let plan = organizePlan()
        guard !plan.isEmpty else {
            flash(organizeContainer == nil ? "Everything is already in folders" : "Everything here is already sorted")
            return
        }
        switch OrganizerSettings.existingFolders {
        case .add: return autoOrganize(reuseExisting: true)
        case .new: return autoOrganize(reuseExisting: false)
        case .ask: break
        }
        var names: [String] = []
        for step in plan {
            if let folder = existingFolder(step.style, project: step.project, parent: step.parent), !names.contains(folder.name) {
                names.append(folder.name)
            }
        }
        if names.isEmpty {
            autoOrganize(reuseExisting: true)
        } else {
            withAnimation(.easeOut(duration: 0.15)) { organizePrompt = names }
        }
    }

    /// Sorts the loose things where you are into a folder for their kind — links into Linker,
    /// images into PhotoBook, notes into Notepad, files into Files — either adding to those
    /// folders when they exist, or making fresh ones ("PhotoBook 2"…).
    func autoOrganize(reuseExisting: Bool) {
        organizePrompt = nil
        let plan = organizePlan()
        guard !plan.isEmpty else { return }
        checkpoint("Organize")
        var madeThisRun: [String: UUID] = [:]
        var created = 0
        withAnimation(.spring(duration: 0.45)) {
            for step in plan {
                let key = "\(step.style.rawValue)|\(step.project?.uuidString ?? "-")|\(step.parent?.uuidString ?? "-")"
                let folderID: UUID
                if let made = madeThisRun[key] {
                    folderID = made
                } else if reuseExisting, let existing = existingFolder(step.style, project: step.project, parent: step.parent) {
                    folderID = existing.id
                } else {
                    let folder = Folder(name: uniqueFolderName(step.style.name, in: step.project), style: step.style,
                                        projectID: step.project, parentID: step.parent)
                    folders.append(folder)
                    madeThisRun[key] = folder.id
                    folderID = folder.id
                    created += 1
                }
                items[step.index].folderID = folderID
            }
        }
        save()
        flash("Organized \(plural(plan.count, "item"))" + (created > 0 ? " into \(plural(created, "new folder"))" : ""), undo: true)
    }

    /// Deep Organize (in Settings): goes through every folder, at every level, and puts each thing
    /// into the folder for its kind. Kind folders sitting inside a different kind move out a level,
    /// and things in the wrong kind folder move to the right one next to it.
    @discardableResult
    func deepOrganize(allProjects: Bool, includeOwnFolders: Bool, fixWrongKind: Bool) -> (moved: Int, made: Int) {
        let project = currentPlace.project
        func inScope(_ p: UUID?) -> Bool { allProjects || p == project }
        checkpoint("Deep Organize")
        var moved = 0, made = 0
        var cache: [String: UUID] = [:]
        func kindFolder(_ style: FolderStyle, project: UUID?, parent: UUID?) -> UUID {
            let key = "\(style.rawValue)|\(project?.uuidString ?? "-")|\(parent?.uuidString ?? "-")"
            if let id = cache[key] { return id }
            let id = existingFolder(style, project: project, parent: parent)?.id ?? {
                let folder = Folder(name: uniqueFolderName(style.name, in: project), style: style, projectID: project, parentID: parent)
                folders.append(folder)
                made += 1
                return folder.id
            }()
            cache[key] = id
            return id
        }
        withAnimation(.spring(duration: 0.45)) {
            // 1. A kind folder inside a different kind of folder moves out a level.
            if fixWrongKind {
                var changed = true
                while changed {
                    changed = false
                    for index in folders.indices where inScope(folders[index].projectID) && folders[index].style.isKind {
                        guard let parent = folders[index].parentID.flatMap(folder), parent.style.isKind,
                              parent.style != folders[index].style else { continue }
                        folders[index].parentID = parent.parentID
                        moved += 1
                        changed = true
                    }
                }
            }
            // 2. Every thing goes into the folder for its kind, at the level where it is.
            for index in items.indices where inScope(items[index].projectID) {
                let item = items[index]
                let style = item.organizeStyle
                let parent: UUID?
                if let container = item.folderID.flatMap(folder) {
                    if container.style.isKind {
                        guard container.style != style, fixWrongKind else { continue }
                        parent = container.parentID
                    } else {
                        guard includeOwnFolders else { continue }
                        parent = container.id
                    }
                } else {
                    parent = nil
                }
                items[index].folderID = kindFolder(style, project: item.projectID, parent: parent)
                moved += 1
            }
        }
        if moved == 0 && made == 0 { undoStack.removeLast() }
        save()
        flash(moved == 0 ? "Everything is already in the right folder" : "Deep Organize: moved \(plural(moved, "thing"))" + (made > 0 ? ", made \(plural(made, "folder"))" : ""))
        return (moved, made)
    }

    /// "PhotoBook", or "PhotoBook 2", "PhotoBook 3"… if that name is taken in the project.
    func uniqueFolderName(_ base: String, in project: UUID?) -> String {
        let taken = Set(folders.filter { $0.projectID == project }.map(\.name))
        guard taken.contains(base) else { return base }
        var number = 2
        while taken.contains("\(base) \(number)") { number += 1 }
        return "\(base) \(number)"
    }

    // MARK: Projects

    @discardableResult
    func addProject(named name: String) -> Project {
        checkpoint("New Project")
        let taken = Set(projects.map { $0.name.lowercased() })
        var unique = name, n = 2
        while taken.contains(unique.lowercased()) { unique = "\(name) \(n)"; n += 1 }
        let project = Project(name: unique)
        projects.append(project)
        filter = .project(project.id)
        save()
        return project
    }

    func renameProject(_ id: UUID, to name: String) {
        renamingProjectID = nil
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, projects.first(where: { $0.id == id })?.name != trimmed else { return }
        checkpoint("Rename Project")
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].name = trimmed
        save()
    }

    /// Deleting a project keeps its items and folders: they go to Not Selected.
    /// Deleting a project: keep its things (they move to Not Selected) or delete everything in it.
    func deleteProject(_ id: UUID, keepContents: Bool = true) {
        checkpoint("Delete Project")
        pendingProjectDelete = nil
        if keepContents {
            for index in pages.indices where pages[index].projectID == id { pages[index].projectID = nil }
            for index in items.indices where items[index].projectID == id { items[index].projectID = nil }
            for index in folders.indices where folders[index].projectID == id { folders[index].projectID = nil }
        } else {
            recordDeletion(projects: projects.filter { $0.id == id }, folders: folders.filter { $0.projectID == id },
                           items: items.filter { $0.projectID == id })
            for item in items where item.projectID == id && item.kind != .image {
                if let file = item.imageFile { trashImage(file) }
            }
            items.removeAll { $0.projectID == id }
            folders.removeAll { $0.projectID == id }
            pages.removeAll { $0.projectID == id }
        }
        let name = name(for: id)
        let wasUnsorted = projects.first { $0.id == id }?.name == "Unsorted"
        projects.removeAll { $0.id == id }
        if wasUnsorted { // its things had nowhere to go but a new Unsorted: they go to Recently Deleted instead
            recordDeletion(projects: [], folders: folders.filter { $0.projectID == nil }, items: items.filter { $0.projectID == nil })
            items.removeAll { $0.projectID == nil }
            folders.removeAll { $0.projectID == nil }
            pages.removeAll { $0.projectID == nil }
        }
        if filter == .project(id) {
            // On to another open project, or Recent if there's none.
            if let next = projects.first(where: { $0.tabClosed != true }) ?? projects.first { filter = .project(next.id) } else { filter = .inbox; showingRecent = true }
        }
        save()
        flash("Deleted \(name)", undo: true)
    }

    /// Asks first if the project has anything in it.
    func requestDeleteProject(_ id: UUID) {
        let hasThings = items.contains { $0.projectID == id } || folders.contains { $0.projectID == id }
            || pages.contains { $0.projectID == id && !$0.notes.isEmpty }
        if hasThings { pendingProjectDelete = id } else { deleteProject(id) }
    }

    // MARK: Images

    func fileURL(for name: String) -> URL { imagesDir.appendingPathComponent(name) }

    /// A downsampled, cached image for display on the board (made in the background; nil until it's ready).
    func thumbnail(_ name: String) -> NSImage? { thumbnail(at: fileURL(for: name)) }

    /// What a card shows: the picture itself for images, the saved preview for links and files — at about the
    /// size it's shown (256 px for small tiles, 900 for big cards). Made in the background; nil until ready.
    func displayImage(_ item: Item, maxPixels: Int = 900) -> NSImage? {
        guard let url = displayImageURL(item) else { return nil }
        return ThumbnailService.shared.image(at: url, maxPixels: maxPixels)
    }

    /// The same, made right away (for one-off windows like Get Info and the preview).
    func displayImageNow(_ item: Item, maxPixels: Int = 900) -> NSImage? {
        guard let url = displayImageURL(item) else { return nil }
        return ThumbnailService.shared.imageNow(at: url, maxPixels: maxPixels)
    }

    private func displayImageURL(_ item: Item) -> URL? {
        item.kind == .image ? contentURL(item) : item.imageFile.map(fileURL(for:))
    }

    func thumbnail(at url: URL) -> NSImage? { ThumbnailService.shared.image(at: url, maxPixels: 900) }

    func storeImageData(_ data: Data, ext: String) -> String? {
        let name = UUID().uuidString + "." + (ext.isEmpty ? "png" : ext)
        do {
            try data.write(to: fileURL(for: name))
            return name
        } catch {
            return nil
        }
    }

    // MARK: Projects only

    /// There's no "Not Selected" any more — everything lives in a project. Things without one move into
    /// "Unsorted" (made only when needed), there's always at least one project, and the board always shows one.
    @discardableResult
    func ensureProjectHome(makeIfNone: Bool = true) -> UUID {
        let homeless = items.contains { $0.projectID == nil } || folders.contains { $0.projectID == nil }
            || pages.contains { $0.projectID == nil && !$0.notes.isEmpty }
        var home = projects.first { $0.name == "Unsorted" }?.id
        if homeless || (makeIfNone && projects.isEmpty) {
            if home == nil {
                let unsorted = Project(name: "Unsorted")
                projects.append(unsorted)
                home = unsorted.id
            }
            for i in items.indices where items[i].projectID == nil { items[i].projectID = home }
            for i in folders.indices where folders[i].projectID == nil { folders[i].projectID = home }
            for i in pages.indices where pages[i].projectID == nil { pages[i].projectID = home }
        }
        let valid: Bool = { if case .project(let id) = filter { projects.contains { $0.id == id } } else { false } }()
        if !valid {
            let next = projects.max { ($0.lastOpened ?? $0.createdAt) < ($1.lastOpened ?? $1.createdAt) }
            if let next { filter = .project(next.id) } else { showingRecent = true } // every project deleted: Recent
        }
        return home ?? projects.first?.id ?? UUID()
    }

    // MARK: Feedback

    /// A short message at the bottom. With `undo`, it has an Undo button and stays a little longer.
    func flash(_ message: String, undo: Bool = false) {
        toastTask?.cancel()
        withAnimation(.spring(duration: 0.25)) {
            toast = message
            toastUndo = undo && !undoStack.isEmpty
        }
        toastTask = Task {
            try? await Task.sleep(for: .seconds(undo ? 4 : 1.8))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.3)) { toast = nil; toastUndo = false }
        }
        // VoiceOver reads it out too.
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

extension Notification.Name {
    static let stashDidSave = Notification.Name("stashDidSave")
}


extension Store {
    /// The tab's ×, like a browser: the tab closes, the project stays (sidebar, ⌄, Go menu; Delete is on right-click).
    func closeTab(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].tabClosed = true
        projects[index].pinned = nil
        if filter == .project(id), !showingRecent, connectedView == nil, libraryView == nil {
            // On to the next open tab — or, with none left, Recent (which is always there and can't be closed).
            if let next = projects.first(where: { $0.tabClosed != true && $0.id != id }) {
                filter = .project(next.id)
            } else {
                showingRecent = true
            }
        }
        save(touchesFiles: false)
    }
}
