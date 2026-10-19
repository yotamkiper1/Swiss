import SwiftUI

// MARK: - Folder icon designs

extension FolderStyle {
    var color: Color {
        switch self {
        case .classic: Color(red: 0.22, green: 0.54, blue: 0.87)
        case .kraft: Color(red: 0.78, green: 0.60, blue: 0.42)
        case .pastel: Color(red: 0.95, green: 0.68, blue: 0.78)
        case .midnight: Color(red: 0.24, green: 0.26, blue: 0.36)
        case .linker: Color(red: 0.11, green: 0.62, blue: 0.46)
        case .photos: Color(red: 0.85, green: 0.35, blue: 0.19)
        case .noteHanger: Color(red: 0.94, green: 0.62, blue: 0.15)
        case .files: Color(red: 0.53, green: 0.53, blue: 0.50)
        }
    }

    /// Small symbol for menus and on the icon.
    var symbol: String {
        switch self {
        case .classic: "folder.fill"
        case .kraft: "shippingbox.fill"
        case .pastel: "heart.fill"
        case .midnight: "moon.fill"
        case .linker: "link"
        case .photos: "photo"
        case .noteHanger: "book.closed"
        case .files: "doc"
        }
    }
}

/// The folder icon (design "Dot"): every folder is the same quiet gray shape, and a small colored dot in the
/// corner says what kind it is — blue for a plain folder, green Linker, coral PhotoBook, amber Notepad, gray Files.
struct FolderIcon: View {
    let style: FolderStyle
    var size: CGFloat = 56

    /// Blue, like Finder's folders: a darker back and tab, a lighter front (a little deeper at night).
    static let back = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.24, green: 0.49, blue: 0.80, alpha: 1)
            : NSColor(srgbRed: 0.38, green: 0.65, blue: 0.93, alpha: 1)
    })
    static let front = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0.33, green: 0.60, blue: 0.90, alpha: 1)
            : NSColor(srgbRed: 0.52, green: 0.76, blue: 0.98, alpha: 1)
    })
    /// Kept for anything that still asks for "the folder color".
    static let body = front

    var body: some View {
        let s = size
        ZStack(alignment: .bottomTrailing) {
            // The back with its tab, and the front panel over it — Finder's blue folder, flat.
            ZStack(alignment: .topLeading) {
                UnevenRoundedRectangle(topLeadingRadius: s * 0.06, topTrailingRadius: s * 0.06)
                    .fill(Self.back)
                    .frame(width: s * 0.4, height: s * 0.16)
                RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                    .fill(Self.back)
                    .padding(.top, s * 0.1)
                RoundedRectangle(cornerRadius: s * 0.08, style: .continuous)
                    .fill(Self.front)
                    .padding(.top, s * 0.24)
            }
            .frame(width: s, height: s * 0.8)
            // A plain folder is just a folder; Linker, PhotoBook, Notepad and Files have their dot.
            if style != .classic {
                dot
                    .offset(x: s * 0.04, y: s * 0.04)
            }
        }
        .frame(width: s, height: s * 0.8)
    }

    /// The colored mark: a plain dot when tiny, with the type's little symbol when there's room.
    private var dot: some View {
        let d = max(6, size * (size < 30 ? 0.36 : 0.3))
        return Circle()
            .fill(style.color)
            .frame(width: d, height: d)
            .overlay {
                if size >= 30, style != .classic {
                    Image(systemName: style.dotSymbol)
                        .font(.system(size: d * 0.5, weight: .bold))
                        .foregroundStyle(.white)
                }
            }
            .overlay(Circle().strokeBorder(Color.white.opacity(size >= 30 ? 0.9 : 0), lineWidth: size * 0.025))
    }
}

extension FolderStyle {
    /// The symbol inside the dot.
    var dotSymbol: String {
        switch self {
        case .classic: "circle.fill"
        case .kraft: "shippingbox.fill"
        case .pastel: "heart.fill"
        case .midnight: "moon.fill"
        case .linker: "link"
        case .photos: "photo.fill"
        case .noteHanger: "text.alignleft"
        case .files: "doc.fill"
        }
    }
}

// MARK: - Folder tile on the board

extension Folder {
    /// Folders only show a name once you've named them yourself (right-click → Name).
    /// Folders always show their name ("PhotoBook", "PhotoBook 2", or whatever you call it).
    var showsName: Bool { true }
    var displayName: String { name }
}

struct FolderTile: View {
    @EnvironmentObject var store: Store
    let folder: Folder
    let compact: Bool
    @State private var hovering = false
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool
    @ObservedObject private var mark: SelectFlag
    private var selected: Bool { mark.on }
    private var dropTarget: Bool { store.dropFolderID == folder.id }

    var asRow = false
    /// Position in the list, for the alternating stripes.
    var rowIndex: Int? = nil
    /// Its number on the board: pressing it (1–9) opens the folder.
    var number: Int? = nil
    /// Far off-screen on a big board: only its shape and name, same size (see CardView.lite).
    var lite = false

    init(folder: Folder, compact: Bool, asRow: Bool = false, rowIndex: Int? = nil, number: Int? = nil, lite: Bool = false) {
        self.folder = folder
        self.compact = compact
        self.asRow = asRow
        self.rowIndex = rowIndex
        self.number = number
        self.lite = lite
        _mark = ObservedObject(wrappedValue: SelectionCenter.shared.flag(.folder(folder.id)))
    }

    /// The small key hint: "1" … "9".
    @ViewBuilder private var numberBadge: some View {
        if let number, number <= 9 {
            Text("\(number)")
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(selected && asRow ? Color.white.opacity(0.8) : Color.secondary.opacity(0.7))
                .frame(width: 14, height: 14)
                .background(
                    RoundedRectangle(cornerRadius: 3).strokeBorder(selected && asRow ? Color.white.opacity(0.5) : Color.primary.opacity(0.15))
                )
                .help("Press \(number) to open")
        }
    }

    var body: some View {
        if TestMode.isOn { Perf.folderBodies += 1 }
        return Group {
            if lite { if asRow { row } else { tile } } else { fullBody }
        }
    }

    private var fullBody: some View {
        Group {
            if asRow { row } else { tile }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            let event = NSApp.currentEvent
            if (event?.clickCount ?? 1) >= 2 {
                open()
            } else {
                store.click(.folder(folder.id), modifiers: event?.modifierFlags ?? [])
            }
        }
        .simultaneousGesture(LongPressGesture(minimumDuration: asRow ? 0.6 : 100_000).onEnded { _ in store.renamingFolderID = folder.id })
        // Folders can be dragged onto other folders (or the Back arrow) too.
        .onDrag {
            store.draggingItemID = nil
            store.draggingFolderID = folder.id
            return store.folderProvider(for: folder)
        }
        .contextMenu { menu }
        .background(
            GeometryReader { geo in
                Color.clear.preference(key: FolderFramesKey.self, value: [folder.id: geo.frame(in: .global)])
            }
        )
        .help(tooltip)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(folder.style.isKind ? folder.style.name + " folder" : "Folder"): \(folder.displayName), \(store.plural(store.count(in: folder) + store.subfolderCount(in: folder), "thing")) inside")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open") { open() }
    }

    /// Like Finder: when selected, a soft gray square behind the icon and the name in a blue pill.
    private var tile: some View {
        VStack(spacing: 5) {
            FullnessIcon(style: folder.style, size: compact ? 50 : 58,
                         count: store.count(in: folder) + store.subfolderCount(in: folder))
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(dropTarget ? Color.accentColor.opacity(0.22)
                              : Color.primary.opacity(selected ? 0.1 : (hovering ? 0.045 : 0)))
                )
                .overlay(alignment: .topLeading) { numberBadge.padding(2) }
            name
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Finder-style row: tiny folder icon and the name.
    private var row: some View {
        HStack(spacing: 7) {
            FolderIcon(style: folder.style, size: 17)
            if store.renamingFolderID == folder.id {
                name
            } else {
                Text(folder.displayName)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .onTapGesture { slowClickRename() }
            }
            TagDots(tags: folder.colorTags ?? [])
            Spacer(minLength: 0)
            numberBadge
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(rowFill)
        )
    }

    private var rowFill: Color {
        if selected { return .accentColor }
        if dropTarget { return Color.accentColor.opacity(0.3) }
        if hovering { return Color.primary.opacity(0.06) }
        return (rowIndex ?? 0) % 2 == 1 ? Color.primary.opacity(0.035) : .clear
    }

    private var contentsLine: String {
        let items = store.count(in: folder), inner = store.subfolderCount(in: folder)
        var parts = [store.plural(items, "item")]
        if inner > 0 { parts.append(store.plural(inner, "folder")) }
        return parts.joined(separator: " · ")
    }


    private var tooltip: String {
        let items = store.count(in: folder), inner = store.subfolderCount(in: folder)
        var parts = [store.plural(items, "item")]
        if inner > 0 { parts.append(store.plural(inner, "folder")) }
        return "\(folder.displayName) · \(parts.joined(separator: ", ")) — double-click to open, drag cards here to put them inside"
    }

    @ViewBuilder private var name: some View {
        if store.renamingFolderID == folder.id {
            RenameField(initial: folder.name, alignment: asRow ? .left : .center, onDark: selected && asRow,
                        commit: { name in
                            store.renameFolder(folder.id, to: name)
                            store.renamingFolderID = nil
                        },
                        cancel: { store.renamingFolderID = nil })
                .frame(width: asRow ? 220 : 110, height: 22)
        } else if !asRow {
            HStack(spacing: 4) {
            TagDots(tags: folder.colorTags ?? [])
            Text(folder.name)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.72) : .clear) // a lighter blue than Finder's
                )
                .onTapGesture { slowClickRename() }
            }
        }
    }

    /// Like Finder: clicking the name of a folder that's already selected starts renaming it
    /// (a double-click opens it instead).
    private func slowClickRename() {
        let event = NSApp.currentEvent
        guard selected, store.selection.count == 1, (event?.clickCount ?? 1) == 1 else {
            store.click(.folder(folder.id), modifiers: event?.modifierFlags ?? [])
            if (event?.clickCount ?? 1) >= 2 { open() }
            return
        }
        let id = folder.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
            // Still the only thing selected, and not opened in the meantime.
            if store.selection == [.folder(id)], store.openFolderID != id { store.renamingFolderID = id }
        }
    }

    private func finishRename() {
        guard store.renamingFolderID == folder.id else { return }
        store.renameFolder(folder.id, to: draftName)
        store.renamingFolderID = nil
    }

    private func open() {
        guard store.renamingFolderID != folder.id else { return }
        if store.isSearching { store.search = "" } // a search result: go into it
        store.openFolderID = folder.id
    }

    @ViewBuilder private var menu: some View {
        let targets = store.targets(for: .folder(folder.id))
        if targets.count > 1 {
            SelectionMenu(targets: targets)
        } else {
            singleMenu
        }
    }

    @ViewBuilder private var singleMenu: some View {
        Button("Open") { open() }
        Button("Rename") { store.renamingFolderID = folder.id }
        Button("Get Info") { AppDelegate.shared.showInfo(for: [.folder(folder.id)]) }
        Menu("Style") {
            ForEach(FolderStyle.choices) { style in
                Button {
                    store.setStyle(style, for: folder.id)
                } label: {
                    Label(style.name, systemImage: folder.style == style ? "checkmark" : style.symbol)
                }
            }
        }
        TagMenu(targets: [.folder(folder.id)])
        PutInFolderMenu(targets: [.folder(folder.id)])
        Menu("Move to Project") {
            ProjectChoices(current: folder.projectID) { store.moveToProject([.folder(folder.id)], project: $0) }
        }
        Divider()
        Button("Delete Folder", role: .destructive) { store.requestDelete([.folder(folder.id)]) }
    }
}

/// "Put in Folder": the folders next to these things, plus moving up a level.
struct PutInFolderMenu: View {
    @EnvironmentObject var store: Store
    let targets: Set<Selectable>

    var body: some View {
        // Where these things are now: the folder they sit in (all the same when chosen together).
        let container: UUID? = {
            switch targets.first {
            case .item(let id)?: return store.items.first { $0.id == id }?.folderID
            case .folder(let id)?: return store.folder(id)?.parentID
            case nil: return store.openFolderID
            }
        }()
        let project: UUID? = {
            switch targets.first {
            case .item(let id)?: return store.items.first { $0.id == id }?.projectID
            case .folder(let id)?: return store.folder(id)?.projectID
            case nil: return store.currentPlace.project
            }
        }()
        let choices = store.folders.filter {
            $0.projectID == project && $0.parentID == container && !targets.folderIDs.contains($0.id)
        }
        Menu("Put in Folder") {
            if let container {
                let up = store.folder(container)?.parentID
                Button {
                    store.put(targets, into: up)
                } label: {
                    Label(up.flatMap(store.folder).map { "Move Up to \($0.displayName)" } ?? "Move Out to the Board", systemImage: "arrow.up")
                }
                if !choices.isEmpty { Divider() }
            }
            ForEach(choices) { folder in
                Button { store.put(targets, into: folder.id) } label: {
                    Label(folder.displayName, systemImage: folder.style.symbol)
                }
            }
            if choices.isEmpty && container == nil { Text("No folders here yet") }
        }
    }
}

struct FolderFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue()) { $1 }
    }
}

/// Shown at the top of the board while a folder is open: Back goes up one level,
/// and the path shows where you are (click any part to jump there).
struct FolderHeader: View {
    @EnvironmentObject var store: Store
    let folder: Folder

    var body: some View {
        let path = store.ancestors(of: folder.id)
        HStack(spacing: 6) {
            Button {
                store.openFolderID = folder.parentID
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: 22, height: 22)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .background(dropHighlight(folder.parentID))
            .dropZone(folder.parentID ?? Store.boardDropID)
            .keyboardShortcut("[", modifiers: .command)
            .help("Back up one level (⌘[) · drag things here to take them out")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    crumb(store.name(for: store.currentPlace.project), symbol: nil, target: nil) { store.openFolderID = nil }
                    ForEach(path) { parent in
                        separator
                        crumb(parent.displayName, symbol: parent.style, target: parent.id) { store.openFolderID = parent.id }
                    }
                    separator
                    HStack(spacing: 4) {
                        FolderIcon(style: folder.style, size: 18)
                        Text(folder.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                    }
                }
            }
            Spacer(minLength: 0)
            Button { store.requestDelete([.folder(folder.id)]) } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Delete this folder")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var separator: some View {
        Image(systemName: "chevron.compact.right")
            .font(.system(size: 11))
            .foregroundStyle(.tertiary)
    }

    private func crumb(_ title: String, symbol: FolderStyle?, target: UUID?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let symbol { FolderIcon(style: symbol, size: 16) }
                Text(title).font(.system(size: 12)).lineLimit(1)
            }
            .padding(.horizontal, 4)
            .padding(.vertical, 2)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .background(dropHighlight(target))
        .dropZone(target ?? Store.boardDropID)
    }

    /// Lights up while something is dragged over this spot.
    private func dropHighlight(_ target: UUID?) -> some View {
        RoundedRectangle(cornerRadius: 5)
            .fill(Color.accentColor.opacity(store.dropFolderID == (target ?? Store.boardDropID) ? 0.25 : 0))
    }
}

/// Asked when deleting folders that still have things in them.
struct DeletePrompt: View {
    @EnvironmentObject var store: Store
    let targets: Set<Selectable>

    var body: some View {
        let folders = targets.folderIDs.compactMap(store.folder)
        let all = store.withDescendants(Set(targets.folderIDs))
        let inside = store.items.filter { $0.folderID.map(all.contains) ?? false }.count
        let innerFolders = all.count - folders.count
        let looseItems = targets.itemIDs.count
        ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture(perform: cancel)
            VStack(spacing: 12) {
                if let first = folders.first {
                    FolderIcon(style: first.style, size: 48)
                }
                Text(folders.count == 1 && looseItems == 0 ? "Delete “\(folders[0].displayName)”?" : "Delete \(store.describe(targets))?")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(message(folders: folders.count, inside: inside, innerFolders: innerFolders))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 6) {
                    Button { store.performDelete(targets, keepFolderContents: true) } label: {
                        Text("Keep What's Inside").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    Button(role: .destructive) { store.performDelete(targets, keepFolderContents: false) } label: {
                        Text("Delete Everything Inside Too")
                            .foregroundStyle(.red)
                            .frame(maxWidth: .infinity)
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
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            )
        }
    }

    private func message(folders: Int, inside: Int, innerFolders: Int) -> String {
        var parts: [String] = []
        if inside > 0 { parts.append(store.plural(inside, "item")) }
        if innerFolders > 0 { parts.append(store.plural(innerFolders, "folder")) }
        let what = parts.joined(separator: " and ")
        let subject = folders == 1 ? "It has" : "They have"
        return "\(subject) \(what) inside. Keep those (they move up a level), or delete them with the folder\(folders == 1 ? "" : "s")?"
    }

    private func cancel() {
        store.pendingDelete = nil
    }
}

/// Asked when deleting a project that has things in it.
struct DeleteProjectPrompt: View {
    @EnvironmentObject var store: Store
    let projectID: UUID
    private var isUnsorted: Bool { store.name(for: projectID) == "Unsorted" }

    var body: some View {
        let items = store.items.filter { $0.projectID == projectID }.count
        let folders = store.folders.filter { $0.projectID == projectID }.count
        var parts: [String] = []
        if items > 0 { parts.append(store.plural(items, "item")) }
        if folders > 0 { parts.append(store.plural(folders, "folder")) }
        let what = parts.isEmpty ? "notebook pages" : parts.joined(separator: " and ")
        return ZStack {
            Color.black.opacity(0.25)
                .ignoresSafeArea()
                .onTapGesture { store.pendingProjectDelete = nil }
            VStack(spacing: 12) {
                Image(systemName: "rectangle.stack.badge.minus")
                    .font(.system(size: 26))
                    .foregroundStyle(.secondary)
                Text("Delete the project “\(store.name(for: projectID))”?")
                    .font(.system(size: 14, weight: .semibold))
                    .multilineTextAlignment(.center)
                Text(isUnsorted ? "It has \(what). They'll go to Recently Deleted (you can bring them back)."
                     : "It has \(what). Keep them (they move to Unsorted), or delete everything in the project?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                VStack(spacing: 6) {
                    if !isUnsorted { // Unsorted is where kept things would go
                        Button { store.deleteProject(projectID, keepContents: true) } label: {
                            Text("Keep Its Things").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                    }
                    Button(role: .destructive) { store.deleteProject(projectID, keepContents: false) } label: {
                        Text("Delete Everything").foregroundStyle(.red).frame(maxWidth: .infinity)
                    }
                    Button("Cancel") { store.pendingProjectDelete = nil }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                        .keyboardShortcut(.cancelAction)
                        .padding(.top, 2)
                }
                .controlSize(.large)
            }
            .padding(18)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(.regularMaterial)
                    .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
            )
        }
    }
}

extension View {
    /// Makes this spot a place to drop cards and folders onto (a folder, or the board).
    func dropZone(_ id: UUID) -> some View {
        background(
            GeometryReader { geo in
                Color.clear.preference(key: FolderFramesKey.self, value: [id: geo.frame(in: .global)])
            }
        )
    }
}

/// A note: a small yellow pad with a red binding strip and a few lines.
struct NotePadIcon: View {
    var size: CGFloat = 17

    var body: some View {
        let s = size
        VStack(spacing: 0) {
            Rectangle().fill(Color(red: 0.86, green: 0.36, blue: 0.32)).frame(height: max(2, s * 0.16))
            ZStack {
                FolderStyle.noteHanger.color
                VStack(alignment: .leading, spacing: max(1.5, s * 0.1)) {
                    ForEach(0..<3, id: \.self) { i in
                        Capsule().fill(.black.opacity(0.22)).frame(width: s * (i == 2 ? 0.28 : 0.42), height: max(1, s * 0.035))
                    }
                }
            }
        }
        .frame(width: s * 0.72, height: s * 0.86)
        .clipShape(RoundedRectangle(cornerRadius: max(1.5, s * 0.08), style: .continuous))
        .frame(width: s, height: s)
    }
}

/// A folder icon that shows how full it is: empty stays flat, 1–5 things show a sheet peeking out,
/// more show a stack — and a small count (20+ after twenty). It eases between the looks as things come and go.
struct FullnessIcon: View {
    let style: FolderStyle
    let size: CGFloat
    let count: Int

    private var sheets: Int { count == 0 ? 0 : (count <= 5 ? 1 : 3) }

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: size * 0.06, style: .continuous)
                    .fill(Color.white)
                    .overlay(RoundedRectangle(cornerRadius: size * 0.06, style: .continuous).strokeBorder(Color.black.opacity(0.1)))
                    .frame(width: size * 0.62, height: size * 0.5)
                    .rotationEffect(.degrees(Double(index - 1) * 7))
                    .offset(x: CGFloat(index - 1) * size * 0.07,
                            y: index < sheets ? -size * (0.2 + CGFloat(index) * 0.04) : 0)
                    .opacity(index < sheets ? 1 : 0)
            }
            FolderIcon(style: style, size: size)
        }
        .overlay(alignment: .topTrailing) {
            if count > 0 {
                Text(count > 20 ? "20+" : "\(count)")
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4)
                    .frame(minWidth: 15, minHeight: 15)
                    .background(Capsule().fill(Color.black.opacity(0.45)))
                    .overlay(Capsule().strokeBorder(Color.white.opacity(0.7), lineWidth: 1))
                    .offset(x: 4, y: -3)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(duration: 0.35, bounce: 0.3), value: sheets)
        .animation(.spring(duration: 0.3), value: count)
        .help(count == 0 ? "Empty" : "\(count) thing\(count == 1 ? "" : "s") inside")
    }
}
