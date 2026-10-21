import SwiftUI

/// The five numbered actions: press 1–5 on the board, use the bar at the bottom, or right-click.
enum QuickAction: Int, CaseIterable, Identifiable {
    case newNote = 1, newFolder, linker, photoBook, notepad, files

    var id: Int { rawValue }
    var key: Character { Character(String(rawValue)) }

    var title: String {
        switch self {
        case .newNote: "New Note"
        case .newFolder: "New Folder"
        case .linker: "Linker"
        case .photoBook: "PhotoBook"
        case .notepad: "Notepad"
        case .files: "Files"
        }
    }

    /// A tiny version of the real icon: the note pad, or the folder it makes.
    @ViewBuilder var icon: some View {
        switch self {
        case .newNote: NotePadIcon(size: 16)
        case .newFolder: FolderIcon(style: .classic, size: 17).frame(width: 17, height: 16)
        case .linker: FolderIcon(style: .linker, size: 17).frame(width: 17, height: 16)
        case .photoBook: FolderIcon(style: .photos, size: 17).frame(width: 17, height: 16)
        case .notepad: FolderIcon(style: .noteHanger, size: 17).frame(width: 17, height: 16)
        case .files: FolderIcon(style: .files, size: 17).frame(width: 17, height: 16)
        }
    }

    /// For the bottom bar.
    var shortTitle: String {
        switch self {
        case .newNote: "Note"
        case .newFolder: "Folder"
        default: title
        }
    }

    var symbol: String {
        switch self {
        case .newNote: "square.and.pencil"
        case .newFolder: "folder.badge.plus"
        case .linker: FolderStyle.linker.symbol
        case .photoBook: FolderStyle.photos.symbol
        case .notepad: "book.closed"
        case .files: FolderStyle.files.symbol
        }
    }

    var help: String {
        switch self {
        case .newNote: "Write a new note on the board"
        case .newFolder: "Make a new folder (inside the folder you're in)"
        case .linker: "Make a new Linker folder (for links)"
        case .photoBook: "Make a new PhotoBook folder (for images)"
        case .notepad: "Make a new Notepad folder (for notes)"
        case .files: "Make a new Files folder (videos, music, 3D, any file)"
        }
    }
}

extension Store {
    /// Recent and All Items only show what's saved elsewhere: no new notes or folders there.
    var canCreateHere: Bool { !showingRecent && (libraryView == nil || connectedView != nil) }

    func perform(_ action: QuickAction) {
        guard canCreateHere else { NSSound.beep(); return }
        if connectedView != nil, !showingRecent {
            // In a connected folder: a real note file, or a real folder ("Linker", "PhotoBook"… by name).
            let editor = ConnectedEditor.shared
            switch action {
            case .newNote: editor.composing = true
            case .newFolder: editor.newFolder()
            case .linker: editor.newFolder(named: "Linker")
            case .photoBook: editor.newFolder(named: "PhotoBook")
            case .notepad: editor.newFolder(named: "Notepad")
            case .files: editor.newFolder(named: "Files")
            }
            return
        }
        switch action {
        case .newNote: withAnimation(.easeOut(duration: 0.15)) { composingNote = true }
        case .newFolder: newFolder()
        case .linker: addStyledFolder(.linker)
        case .photoBook: addStyledFolder(.photos)
        case .notepad: addStyledFolder(.noteHanger)
        case .files: addStyledFolder(.files)
        }
    }

    /// Makes a new Linker / PhotoBook / Notepad every time ("PhotoBook 2"…), inside the folder you're in.
    func addStyledFolder(_ style: FolderStyle) {
        let project = currentPlace.project
        let folder = Folder(name: uniqueFolderName(style.name, in: project), style: style, projectID: project, parentID: openFolderID)
        let chosen = selectedHere
        addFolder(folder)
        if !chosen.isEmpty { adopt(chosen, into: folder); save() } // what was selected goes inside
        selection = [.folder(folder.id)]
        scrollTarget = .folder(folder.id)
        renamingFolderID = folder.id // name it now — Return keeps "\(folder.name)"
    }
}

/// Along the bottom of the window: the numbered actions, and ? for what everything does.
struct QuickBar: View {
    @EnvironmentObject var store: Store
    let compact: Bool
    @State private var showingIndex = false
    /// Which of the bar's four shapes fits the window's width (see `fitting`).
    @State private var shape = 0
    private static let shapes: [(labels: Bool, hint: Bool)] = [(true, true), (true, false), (false, true), (false, false)]
    /// Each shape's narrowest width, measured once. (ViewThatFits made all four bars over again on every change —
    /// most of the delay when switching projects.)
    private static var widths: [CGFloat] = []

    var body: some View {
        Group {
            if compact {
                // The pop-up keeps it simple: one New menu, Clear and ?.
                simpleBar
            } else {
                // Uses the room it has: names and the hint, then names only, then just icons with their ⌘ numbers.
                bar(labels: Self.shapes[shape].labels, hint: Self.shapes[shape].hint)
                    .frame(maxWidth: .infinity)
                    .background(GeometryReader { g in
                        Color.clear
                            .onAppear { fit(g.size.width) }
                            .onChange(of: g.size.width) { fit(g.size.width) }
                    })
            }
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
    }

    private func fit(_ width: CGFloat) {
        if Self.widths.isEmpty {
            Self.widths = Self.shapes.map { shape in
                NSHostingView(rootView: QuickBar(compact: false).bar(labels: shape.labels, hint: shape.hint)
                    .environmentObject(Store.shared)).fittingSize.width
            }
        }
        let next = Self.widths.firstIndex { $0 <= width } ?? Self.shapes.count - 1
        if next != shape { shape = next }
    }

    private var simpleBar: some View {
        HStack(spacing: 4) {
            Button {
                PopMenu.show(QuickAction.allCases.map { action in
                    MenuEntry(title: "\(action.title)    ⌘\(action.key)", symbol: action.symbol) { store.perform(action) }
                })
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                    Text("New").font(.system(size: 11.5, weight: .medium))
                    Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.7)
                }
                .padding(.horizontal, 8).frame(height: 24).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .disabled(!store.canCreateHere)
            .opacity(store.canCreateHere ? 1 : 0.35)
            .help("New note, folder, Linker, PhotoBook, Notepad or Files (⌘1–⌘6)")
            .accessibilityLabel("New")
            .accessibilityHint("Opens a menu: note, folder, Linker, PhotoBook, Notepad, Files")
            Spacer(minLength: 6)
            ClearTabButton(labels: false)
            // Settings: small, in the corner, next to Help.
            Button { AppDelegate.shared.showSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 11.5, weight: .medium))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            Button { showingIndex.toggle() } label: {
                Image(systemName: "questionmark").font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .help("What every button does")
            .accessibilityLabel("Help: what every button does")
            .popover(isPresented: $showingIndex, arrowEdge: .top) { ButtonIndex() }
        }
    }

    private func bar(labels: Bool, hint: Bool) -> some View {
        HStack(spacing: labels ? 2 : 0) {
            ForEach(QuickAction.allCases) { action in
                Button { store.perform(action) } label: {
                    HStack(spacing: 3) {
                        action.icon // the same colors as the real folders
                        Text("⌘" + String(action.key))
                            .font(.system(size: 8.5, weight: .semibold, design: .rounded))
                            .foregroundStyle(.tertiary)
                            .baselineOffset(-4)
                        if labels {
                            Text(action.shortTitle).font(.system(size: 11))
                        }
                    }
                    .lineLimit(1)
                    .fixedSize()
                    .padding(.horizontal, labels ? 7 : 5)
                    .padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(QuietButtonStyle())
                // Store.shared, not the environment: the bar is also measured off-screen (see `fit`).
                .disabled(!Store.shared.canCreateHere)
                .opacity(Store.shared.canCreateHere ? 1 : 0.35)
                .help("⌘\(String(action.key)) · \(action.title) — \(action.help)")
                .accessibilityLabel(action.title)
                .accessibilityHint(action.help)
            }
            Spacer(minLength: 6)
            ClearTabButton(labels: labels)
            if hint {
                // The other number keys.
                Text(labels ? "1–9 open · ⌃Tab tabs" : "1–9 open")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .fixedSize()
                    .help("Press 1–9 to open the folder with that number · ⌃Tab / ⌃⇧Tab switch project tabs")
            }
            // Settings: small, in the corner, next to Help.
            Button { AppDelegate.shared.showSettings() } label: {
                Image(systemName: "gearshape").font(.system(size: 11.5, weight: .medium))
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
            Button { showingIndex.toggle() } label: {
                Image(systemName: "questionmark")
                    .font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .help("What every button does")
        .accessibilityLabel("Help: what every button does")
            .popover(isPresented: $showingIndex, arrowEdge: .top) { ButtonIndex() }
        }
    }
}

/// Clear: empties the tab you're on (the project, or Not Selected). The first click asks "Clear all?" right
/// in the button; a second click within a few seconds clears. ⌘Z undoes it.
struct ClearTabButton: View {
    @EnvironmentObject var store: Store
    let labels: Bool
    @State private var confirming = false

    var body: some View {
        let empty = store.showingRecent ? RecentStore.shared.items.isEmpty
            : store.libraryView != nil && store.connectedView == nil ? store.libraryShown.isEmpty : store.tabIsEmpty
        Button {
            if confirming {
                confirming = false
                if store.showingRecent { RecentStore.shared.clear() }
                else if store.libraryView != nil, store.connectedView == nil { store.clearLibraryShown() }
                else { store.clearCurrentTab() }
            } else {
                confirming = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) { confirming = false }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: confirming ? "trash.fill" : "trash")
                    .font(.system(size: 11, weight: .medium))
                if labels || confirming {
                    Text(confirming ? "Clear all?" : "Clear").font(.system(size: 11, weight: confirming ? .semibold : .regular))
                }
            }
            .foregroundStyle(confirming ? Color.red : Color.secondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .contextMenu { Button("Recently Deleted…") { store.showingRecentlyDeleted = true } }
        .disabled(empty && !confirming)
        .opacity(empty ? 0.4 : 1)
        .help(confirming ? "Click again to delete everything in \(store.dropTargetName) (⌘Z undoes it)"
              : "Clear — delete everything in \(store.dropTargetName)")
        .accessibilityLabel(confirming ? "Confirm clear all" : "Clear \(store.dropTargetName)")
    }
}

/// Plain icon buttons that only show a soft gray behind them while hovered or pressed.
struct QuietButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        QuietButton(configuration: configuration)
    }

    private struct QuietButton: View {
        let configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : (hovering ? 0.06 : 0)))
                )
                .onHover { hovering = $0 }
        }
    }
}

/// The ? index: what each button, key and click does.
struct ButtonIndex: View {
    private let sections: [(String, [(String, String)])] = [
        ("Bottom bar (or ⌘ + the number)", QuickAction.allCases.map { ("⌘\($0.key)  \($0.title)", $0.help) }),
        ("Numbers", [
            ("1 – 9", "Open the folder with that number on the board"),
            ("⌃Tab  ⌃⇧Tab", "Next / previous project tab"),
        ]),
        ("Top bar", [
            ("✨", "Organize — sort loose things into Linker, PhotoBook, Notepad, Files"),
            ("⤢ / ⤡", "Bigger window you can move / shrink back to the menu bar"),
            ("+", "New project"),
            ("⌘,", "Settings — organizer options and Deep Organize"),
        ]),
        ("Keys", [
            ("⌥Space", "Open or close Swiss · right after a screenshot, saves it"),
            ("⌥⌘V", "Quick save what you copied, without opening Swiss (change in Settings)"),
            ("⌘V", "Paste what you copied (into the folder Swiss suggests)"),
            ("⌘Z  ⌘⇧Z", "Undo · redo (Ctrl Z works too)"),
            ("Space", "Preview the selected image"),
            ("Delete", "Delete what's selected"),
            ("Arrows", "Move the selection (shift adds)"),
            ("⌘A  Esc", "Select everything · deselect / close"),
            ("⌘F", "Search (big window)"),
        ]),
        ("Mouse", [
            ("Double-click  ⌘↓", "Open a folder, preview an image, open a link"),
            ("Return", "Rename what's selected (or click a selected folder's name, or long-press)"),
            ("⌘-click  ⇧-click", "Add to the selection · select a range"),
            ("Drag on empty space", "Box-select"),
            ("Drag a card", "Onto a folder to put it inside, or out to another app"),
            ("Right-click", "Menus for moving, folders, converting, deleting"),
        ]),
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("What everything does")
                    .font(.system(size: 14, weight: .semibold))
                ForEach(sections, id: \.0) { section in
                    VStack(alignment: .leading, spacing: 5) {
                        Text(section.0.uppercased())
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                        ForEach(section.1, id: \.0) { row in
                            HStack(alignment: .firstTextBaseline, spacing: 10) {
                                Text(row.0)
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(width: 118, alignment: .leading)
                                Text(row.1)
                                    .font(.system(size: 12))
                                    .foregroundStyle(.secondary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
        .frame(width: 400, height: 460)
    }
}
