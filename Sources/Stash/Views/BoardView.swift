import SwiftUI

/// Folders and cards, used by both the compact preview and the big window.
/// Right-click empty space for New Note, New Folder and Organize; drag on it to box-select.
struct BoardView: View {
    @EnvironmentObject var store: Store
    let compact: Bool
    /// The selection box while you draw it. Its own little object (not the board's state), so moving the mouse only
    /// redraws the box — the board redraws only when something new is selected.
    @State private var box = MarqueeBox()
    @AppStorage(BoardLayout.key) private var layout = BoardLayout.icons.rawValue
    @AppStorage(BoardSort.key) private var sort = BoardSort.manual.rawValue // redraws when the order changes
    /// Which tiles are near the visible part of the board (the rest are drawn lite).
    @State private var boardToken = UUID()
    @State private var gridPlan = BoardGridPlan()
    /// Where the arrow keys are taking you, on the small-tile grid (it may not have a view yet).
    @State private var scrollAnchor: CGRect?
    private var asList: Bool { layout == BoardLayout.list.rawValue }

    var body: some View {
        if store.showingRecent {
            RecentView(compact: compact)
        } else if let location = store.connectedView {
            ConnectedFolderView(location: location, compact: compact)
        } else if let view = store.libraryView, !compact {
            AllItemsView(view: view)
        } else {
            board
        }
    }

    @ViewBuilder private var board: some View {
        let _ = TestMode.isOn ? Perf.boardBodies += 1 : ()
        let folders = store.visibleFolders
        let items = store.visibleItems
        let pending = store.visiblePending
        VStack(spacing: 0) {
            if let folder = store.openFolder, !store.isSearching {
                FolderHeader(folder: folder)
                    .transition(.move(edge: .top).combined(with: .opacity))
                if let hint = store.clipboardHint, hint.folderID == folder.id || hint.folderID == nil {
                    ClipboardBanner(hint: hint)
                }
            } else if let hint = store.clipboardHint, hint.folderID == nil, !store.isSearching {
                ClipboardBanner(hint: hint).padding(.top, 6)
            }
            GeometryReader { geo in
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            if asList, !(items.isEmpty && folders.isEmpty && pending.isEmpty) {
                                // List: folders first, then everything else, one row each — only the rows on screen are made.
                                LazyVStack(spacing: 0) {
                                    ForEach(Array(folders.enumerated()), id: \.element.id) { index, folder in
                                        FolderTile(folder: folder, compact: compact, asRow: true, rowIndex: index, number: index + 1)
                                            .id(Selectable.folder(folder.id))
                                    }
                                    ForEach(pending) { PendingCard(pending: $0, asRow: true) }
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                        CardView(item: item, asRow: true, rowIndex: folders.count + pending.count + index)
                                            .id(Selectable.item(item.id))
                                    }
                                }
                            }
                            let _ = asList ? publishRowFrames(folders: folders, pending: pending.count, items: items,
                                                              width: geo.size.width - Store.boardPadding * 2) : ()
                            if items.isEmpty && folders.isEmpty && pending.isEmpty {
                                EmptyBoard(searching: store.isSearching, inFolder: store.openFolderID != nil)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: geo.size.height - 40)
                            } else if !asList {
                                // Icons: drag anything anywhere (Arrange By: None) — or lined up in order.
                                // Only what's near the screen is made into views.
                                if !pending.isEmpty {
                                    HStack(alignment: .top, spacing: compact ? 10 : 12) { ForEach(pending) { PendingCard(pending: $0) } }
                                }
                                BoardGrid(folders: folders, items: items, compact: compact,
                                          width: geo.size.width - Store.boardPadding * 2, token: boardToken, plan: gridPlan,
                                          anchor: scrollAnchor)
                            }
                        }
                        .padding(Store.boardPadding)
                        .frame(maxWidth: .infinity, minHeight: geo.size.height, alignment: .top)
                        .contentShape(Rectangle())
                        .onTapGesture { store.clearSelection() }
                        .gesture(boxSelect)
                        .overlay(alignment: .topLeading) { MarqueeOverlay(box: box) }
                        .background(GeometryReader { g in
                            // Where the board's contents start (it moves as you scroll) — told directly, not gathered from every tile.
                            Color.clear
                                .onAppear { reportContent(g.frame(in: .global).origin) }
                                .onChange(of: g.frame(in: .global).origin) { reportContent(g.frame(in: .global).origin) }
                        })
                        .coordinateSpace(name: "board")
                        .contextMenu { BoardMenu() }
                    }
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { reportViewport(g.frame(in: .global)) }
                            .onChange(of: g.frame(in: .global)) { reportViewport(g.frame(in: .global)) }
                    })
                    .onChange(of: store.scrollTarget) {
                        guard let target = store.scrollTarget else { return }
                        store.scrollTarget = nil
                        if !asList, let frame = gridPlan.frames[target] {
                            // The grid only has views near the screen: scroll to a marker where the tile goes.
                            scrollAnchor = frame
                            DispatchQueue.main.async { proxy.scrollTo(BoardGrid.anchorID) }
                        } else {
                            proxy.scrollTo(target) // instant, like Finder: an animation per arrow press stutters when held
                        }
                    }
                }
            }
        }
        .onPreferenceChange(FolderFramesKey.self) { frames in
            MainActor.assumeIsolated { store.folderFrames[compact] = frames }
        }

    }

    /// List view: every row is the same height, so where each one is (box selection, arrow keys) is worked out
    /// from its place in the list — rows off screen included, and nothing left over from another view.
    private func publishRowFrames(folders: [Folder], pending: Int, items: [Item], width: CGFloat) {
        let pad = Store.boardPadding, h = Self.rowHeight
        var frames: [Selectable: CGRect] = [:]
        frames.reserveCapacity(folders.count + items.count)
        func frame(_ index: Int) -> CGRect { CGRect(x: pad, y: pad + CGFloat(index) * h, width: width, height: h) }
        for (i, folder) in folders.enumerated() { frames[.folder(folder.id)] = frame(i) }
        for (i, item) in items.enumerated() { frames[.item(item.id)] = frame(folders.count + pending + i) }
        if store.boardFrames[compact] != frames { store.boardFrames[compact] = frames }
    }

    /// A List view row's height (CardView / FolderTile rows).
    static let rowHeight: CGFloat = 22

    private func reportContent(_ origin: CGPoint) {
        store.boardContentOrigins[compact] = origin
        BoardNearby.shared.scrolled(boardToken, compact: compact)
    }

    private func reportViewport(_ frame: CGRect) {
        store.boardViewports[compact] = frame
        BoardNearby.shared.scrolled(boardToken, compact: compact)
    }

    /// Drag on empty space to draw a box; everything it touches gets selected.
    /// Hold ⌘ or shift to add to what's already selected.
    private var boxSelect: some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .named("board"))
            .onChanged { value in
                let frames = store.boardFrames[compact] ?? [:]
                if box.rect == nil && !box.ignored {
                    // A drag that starts on a card is the card being dragged, not a box.
                    // In List view, like Finder, only the icon-and-name part of a row drags it; the rest of the row draws a box.
                    let grab: (CGRect) -> CGRect = asList ? { CGRect(x: $0.minX, y: $0.minY, width: min($0.width, 240), height: $0.height) } : { $0 }
                    if frames.values.contains(where: { grab($0).contains(value.startLocation) }) {
                        box.ignored = true
                        return
                    }
                    let flags = NSEvent.modifierFlags
                    box.base = flags.contains(.command) || flags.contains(.shift) ? store.selection : []
                }
                guard !box.ignored else { return }
                let rect = CGRect(
                    x: min(value.startLocation.x, value.location.x),
                    y: min(value.startLocation.y, value.location.y),
                    width: abs(value.location.x - value.startLocation.x),
                    height: abs(value.location.y - value.startLocation.y)
                )
                box.rect = rect
                var picked = Set<Selectable>()
                for (id, frame) in frames where frame.intersects(rect) { picked.insert(id) }
                if picked != box.picked { // only when a tile comes in or goes out of the box
                    box.picked = picked
                    // Selected live, like Finder: only the tiles going in or out of the box redraw.
                    store.selection = box.base.union(picked)
                }
            }
            .onEnded { _ in
                box.rect = nil
                box.picked = []
                box.ignored = false
            }
    }
}

/// The selection box being drawn (board or canvas).
@MainActor
final class MarqueeBox: ObservableObject {
    @Published var rect: CGRect?
    /// What the box touches right now, shown highlighted by the box itself — the real selection is set once,
    /// when you let go, so the board doesn't redraw while you sweep across it.
    @Published var hits: [CGRect] = []
    var base: Set<Selectable> = []
    var picked: Set<Selectable> = []
    var canvasBase: Set<UUID> = []
    var canvasPicked: Set<UUID> = []
    var ignored = false
}

/// Draws just the box — the only thing that redraws while you drag it.
struct MarqueeOverlay: View {
    @ObservedObject var box: MarqueeBox

    var body: some View {
        ForEach(Array(box.hits.enumerated()), id: \.offset) { _, frame in
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.16))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).strokeBorder(Color.accentColor.opacity(0.6), lineWidth: 1.5))
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
                .allowsHitTesting(false)
        }
        if let rect = box.rect {
            Rectangle()
                .fill(Color.accentColor.opacity(0.12))
                .overlay(Rectangle().strokeBorder(Color.accentColor.opacity(0.8), lineWidth: 1))
                .frame(width: rect.width, height: rect.height)
                .offset(x: rect.minX, y: rect.minY)
                .allowsHitTesting(false)
        }
    }
}

/// The visible board area in the window, so drops on the header or bottom bar don't move things.
struct BoardViewportKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next } // other views pass the empty default
    }
}

/// Where the board's contents start in the window.
struct BoardContentKey: PreferenceKey {
    static let defaultValue: CGPoint = CGPoint(x: -1, y: -1)
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) {
        let next = nextValue()
        if next != defaultValue { value = next }
    }
}

/// Dims a tile while it's being dragged. Only knows which things are being dragged (that changes once per drag),
/// so a mouse move doesn't redraw the board.
private struct FollowsBoardDrag: ViewModifier {
    @ObservedObject private var selection = DragSelection.shared
    let target: Selectable

    func body(content: Content) -> some View {
        // While dragged, the real tile stays put, dimmed; its picture follows the pointer (BoardDrag's ghost).
        content.opacity(selection.ids.contains(target) ? 0 : 1)
    }
}

extension View {
    func followsBoardDrag(_ target: Selectable) -> some View { modifier(FollowsBoardDrag(target: target)) }

}

/// The right-click menu when several things are selected.
struct SelectionMenu: View {
    @EnvironmentObject var store: Store
    let targets: Set<Selectable>

    var body: some View {
        let project = store.currentPlace.project
        Text("\(store.describe(targets)) selected")
        Menu("Move to Project") {
            ProjectChoices(current: store.filter == .inbox ? nil : project) { store.moveToProject(targets, project: $0) }
        }
        Button("Rename \(store.describe(targets))…") { store.pendingBatchRename = targets }
        Button("Share \(store.describe(targets))…") { Sharing.share(targets: targets) }
        Button("Get Info") { AppDelegate.shared.showInfo(for: targets) }
        TagMenu(targets: targets)
        PutInFolderMenu(targets: targets)
        let pictures = targets.itemIDs.filter { id in store.items.first { $0.id == id }?.kind == .image }
        if pictures.count > 1 {
            Button("Make PDF of \(pictures.count) Pictures") { store.combineIntoPDF(store.visibleItems.map(\.id).filter(pictures.contains)) }
        }
        Divider()
        Button("Delete \(store.describe(targets))", role: .destructive) { store.requestDelete(targets) }
    }
}

/// Every project, for Move to Project menus.
struct ProjectChoices: View {
    @EnvironmentObject var store: Store
    let current: UUID?
    let choose: (UUID?) -> Void

    var body: some View {
        ForEach(store.projects) { project in
            Button(project.name) { choose(project.id) }
                .disabled(current == project.id)
        }
    }
}

/// How the board is arranged (the Arrange By button, or right-click → Arrange By).
/// `manual` is Finder's "None": you place things yourself.
enum BoardSort: String, CaseIterable, Identifiable {
    case manual = "none", name, kind, added, tags
    static let key = "board.sort"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .manual: "None"
        case .name: "Name"
        case .kind: "Kind"
        case .added: "Date Added"
        case .tags: "Tags"
        }
    }
    static var current: BoardSort { BoardSort(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .manual }

    /// Each thing's name is worked out once, then sorted (not again for every comparison — big boards stay quick).
    func sorted(_ items: [Item]) -> [Item] {
        switch self {
        case .manual: return items // newest first, as they were saved
        case .added: return items.sorted { $0.createdAt > $1.createdAt }
        case .name:
            return items.map { ($0, $0.displayTitle) }
                .sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }.map(\.0)
        case .kind:
            return items.map { ($0, $0.kind.rawValue, $0.displayTitle.lowercased()) }
                .sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
        case .tags:
            return items.map { ($0, Self.tagRank($0.colorTags), $0.displayTitle.lowercased()) }
                .sorted { ($0.1, $0.2) < ($1.1, $1.2) }.map(\.0)
        }
    }

    /// Tagged things first, in Finder's color order.
    static func tagRank(_ tags: [TagColor]?) -> Int {
        tags?.first.flatMap { TagColor.allCases.firstIndex(of: $0) } ?? TagColor.allCases.count
    }
}

extension Item {
    /// The name it's sorted by: a link's title, a note's first line, a file's name.
    var displayTitle: String {
        switch kind {
        case .text: text.map { t in t.firstIndex(of: "\n").map { String(t[..<$0]) } ?? t } ?? ""
        case .link: title ?? host
        default: title ?? ""
        }
    }
}

/// The right-click menu on empty board space — short groups, like Finder's.
struct BoardMenu: View {
    @EnvironmentObject var store: Store
    @AppStorage(BoardLayout.key) private var layout = BoardLayout.icons.rawValue

    var body: some View {
        Button("New Note") { store.perform(.newNote) }
            .keyboardShortcut("1", modifiers: .command)
        Button("New Folder") { store.perform(.newFolder) }
            .keyboardShortcut("2", modifiers: .command)
        Menu("New") {
            ForEach([QuickAction.linker, .photoBook, .notepad, .files]) { action in
                Button(action.title) { store.perform(action) }
                    .keyboardShortcut(KeyEquivalent(action.key), modifiers: .command)
            }
        }

        Divider()

        Menu("View") {
            Picker("View", selection: $layout) {
                Text("as Icons").tag(BoardLayout.icons.rawValue)
                Text("as List").tag(BoardLayout.list.rawValue)
            }
            .pickerStyle(.inline)
            .labelsHidden()
        }
        Menu("Arrange By") { ArrangeChoices() }
        // The magic tools are only in full screen (the big window), not the pop-up or the frame.
        if WindowMode.current == .window {
            Button("Clean Up") { store.requestOrganize() }
            Button("Deep Clean Up…") { AppDelegate.shared.showSettings() }
        }

        Divider()

        Button("Paste") {
            if !store.ingest(.general, into: store.currentPlace) { NSSound.beep() }
        }
        Button("Show in Finder") { store.revealCurrentFolder() }
        Button("Recently Deleted…") { store.showingRecentlyDeleted = true }
    }
}

/// The magic button: sorts loose things into Linker, PhotoBook, Notepad and Files.
struct OrganizeButton: View {
    @EnvironmentObject var store: Store

    var body: some View {
        Button { store.requestOrganize() } label: {
            Image(systemName: "wand.and.stars")
                .font(.system(size: 12))
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .foregroundStyle(.secondary)
        .help("Organize automatically: links → Linker, photos → PhotoBook, notes → Notepad, files → Files")
        .accessibilityLabel("Organize")
    }
}

/// Asked when the organize button finds folders like Photos already there.
struct OrganizePrompt: View {
    @EnvironmentObject var store: Store
    let names: [String]

    private var list: String {
        switch names.count {
        case 1: names[0]
        case 2: "\(names[0]) and \(names[1])"
        default: names.dropLast().joined(separator: ", ") + " and " + names.last!
        }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
            VStack(spacing: 12) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 24))
                    .foregroundStyle(Color.accentColor)
                Text("You already have \(list)")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text("Add the new things to \(names.count == 1 ? "that folder" : "those folders"), or make new folders for them?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 6) {
                    Button { store.autoOrganize(reuseExisting: true) } label: {
                        Text("Add to Existing").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    Button { store.autoOrganize(reuseExisting: false) } label: {
                        Text("Make New Folders").frame(maxWidth: .infinity)
                    }
                    Button("Cancel", action: cancel)
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                        .padding(.top, 2)
                }
                .controlSize(.large)
            }
            .padding(18)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            )
        }
    }

    private func cancel() {
        withAnimation(.easeOut(duration: 0.15)) { store.organizePrompt = nil }
    }
}

/// Write a new note. Opens from the right-click menu or ⌘N.
struct NoteComposer: View {
    @EnvironmentObject var store: Store
    @State private var text = NSAttributedString()

    /// A plain gray sheet with a formatting toolbar.
    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture(perform: close)
            VStack(alignment: .leading, spacing: 8) {
                RichNoteEditor(text: $text, onSubmit: saveNote)
                    .frame(height: 190)
                HStack(spacing: 10) {
                    Text("↩ save · ⇧↩ new line · #tags · esc")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.tertiary)
                    Spacer()
                    Button(action: close) {
                        Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                    }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(QuietButtonStyle())
                    .help("Cancel (esc)")
                    Button(action: saveNote) {
                        Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .buttonStyle(QuietButtonStyle())
                    .help("Save (↩)")
                    .disabled(text.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                .font(.system(size: 12))
            }
            .padding(12)
            .frame(maxWidth: 400)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            )
            .padding(12)
        }
    }

    private func saveNote() {
        let plain = text.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !plain.isEmpty else { return }
        var item = Item(kind: .text, projectID: store.currentPlace.project, folderID: store.currentPlace.folder)
        item.text = plain
        item.richText = text.hasFormatting ? text.rtfData : nil
        item.tags = Store.tags(in: plain)
        store.add(item)
        close()
    }

    private func close() {
        store.composingNote = false
    }
}

struct EmptyBoard: View {
    let searching: Bool
    var inFolder = false

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: searching ? "magnifyingglass" : inFolder ? "folder" : "tray.and.arrow.down")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(.tertiary)
            Text(searching ? "Nothing matches" : inFolder ? "This folder is empty" : "Drop links, images and files here")
                .font(.system(size: 14, weight: .semibold))
            if !searching {
                Text(inFolder
                     ? "Drop or paste here, or drag cards onto the folder"
                     : "Paste with ⌘V · right-click for a new note or folder")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
        .padding()
    }
}

/// Which cards and folders are selected. Each tile watches only its own flag, so selecting one thing — or a box of
/// fifty — redraws just those tiles (and the ones that stop being selected), never the whole board.
@MainActor
final class SelectionCenter {
    static let shared = SelectionCenter()
    private(set) var ids: Set<Selectable> = []
    private var flags: [Selectable: SelectFlag] = [:]

    func flag(_ id: Selectable) -> SelectFlag {
        if let flag = flags[id] { return flag }
        let flag = SelectFlag(on: ids.contains(id))
        flags[id] = flag
        return flag
    }

    func set(_ next: Set<Selectable>) {
        guard next != ids else { return }
        let changed = ids.symmetricDifference(next)
        ids = next
        for id in changed { flags[id]?.on = next.contains(id) }
    }
}

@MainActor
final class SelectFlag: ObservableObject {
    @Published var on: Bool
    init(on: Bool) { self.on = on }
}
