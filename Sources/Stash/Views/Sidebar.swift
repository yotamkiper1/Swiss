import SwiftUI

/// What the big window's sidebar can show besides a project.
enum LibraryView: Equatable {
    case allItems
    case tag(TagColor)
}

/// The big window's sidebar, like Finder's: Recent, All Items, your projects (pinned first), and colour tags.
struct LibrarySidebar: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var recent = RecentStore.shared
    @ObservedObject private var connected = ConnectedRegistry.shared

    /// Pinned first, then in the order they were made — like the tabs, picking one doesn't move it.
    private var orderedProjects: [Project] {
        store.projects.filter { $0.pinned == true } + store.projects.filter { $0.pinned != true }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 1) {
                row("Recent", symbol: recent.paused ? "pause.circle" : "clock.arrow.circlepath", count: recent.items.count,
                    selected: store.showingRecent) {
                    store.showingRecent = true; store.libraryView = nil
                }
                row("All Items", symbol: "square.stack", count: store.items.count, selected: !store.showingRecent && store.libraryView == .allItems && store.connectedView == nil) {
                    store.showingRecent = false; store.libraryView = .allItems
                }

                header("Projects") {
                    Button { AppDelegate.shared.newProject() } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("New project").accessibilityLabel("New project")
                }
                ForEach(orderedProjects) { projectRow($0) }

                // Real folders elsewhere on the Mac, shown as they are (drop a folder on this heading to add it).
                header("Connected") {
                    Button { ConnectedRegistry.shared.chooseAndConnect() } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)) }
                        .buttonStyle(.plain).foregroundStyle(.secondary).help("Connect a folder").accessibilityLabel("Connect a folder")
                }
                .background(RoundedRectangle(cornerRadius: 6).fill(store.connectDropTargeted ? Color.accentColor.opacity(0.2) : .clear))
                .background(GeometryReader { geo in Color.clear.preference(key: ConnectDropKey.self, value: geo.frame(in: .global)) })
                if connected.folders.isEmpty {
                    Text("Drop a folder here, or +").font(.system(size: 10.5)).foregroundStyle(.tertiary).padding(.horizontal, 8)
                }
                ForEach(connected.folders) { folder in
                    let selected = store.connectedView?.folderID == folder.id
                    row(folder.name, symbol: "externaldrive.connected.to.line.below", count: 0, selected: selected) {
                        ConnectedRegistry.shared.open(folder.id)
                    }
                    .overlay(alignment: .trailing) {
                        // × takes it off Swiss's list (and closes its tab). The real folder in Finder stays as it is;
                        // + above connects it again.
                        Button { ConnectedRegistry.shared.remove(folder.id) } label: {
                            Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 16, height: 16).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain).foregroundStyle(.secondary).padding(.trailing, 6)
                        .help("Remove from Swiss (the folder itself stays in Finder)").accessibilityLabel("Remove \(folder.name) from Swiss")
                    }
                    .contextMenu {
                        Button("Reveal in Finder") { if let url = ConnectedRegistry.shared.resolve(folder.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
                        Divider()
                        Button("Remove Shortcut (the folder stays)", role: .destructive) { ConnectedRegistry.shared.remove(folder.id) }
                    }
                    .help(folder.path)
                }

                let used = TagColor.allCases.filter { tag in count(of: tag) > 0 }
                if !used.isEmpty {
                    header("Tags") { EmptyView() }
                    ForEach(used) { tag in
                        row(tag.title, dot: tag.color, count: count(of: tag), selected: !store.showingRecent && store.libraryView == .tag(tag)) {
                            store.showingRecent = false; store.libraryView = .tag(tag)
                        }
                    }
                }
            }
            .padding(.horizontal, 8).padding(.top, 10).padding(.bottom, 8)
        }
        .frame(maxHeight: .infinity)
        .background(Color.primary.opacity(0.03))
        .onPreferenceChange(ConnectDropKey.self) { frame in MainActor.assumeIsolated { store.connectDropFrame = frame == .zero ? nil : frame } }
        .onPreferenceChange(ProjectDropKey.self) { frames in MainActor.assumeIsolated { store.projectDropFrames = frames } }
    }

    private func count(of tag: TagColor) -> Int {
        store.index.tagged[tag] ?? 0
    }

    private func header<Accessory: View>(_ title: String, @ViewBuilder accessory: () -> Accessory) -> some View {
        HStack {
            Text(title).font(.system(size: 10.5, weight: .semibold)).foregroundStyle(.tertiary)
            Spacer()
            accessory()
        }
        .padding(.horizontal, 8).padding(.top, 12).padding(.bottom, 3)
    }

    @ViewBuilder private func projectRow(_ project: Project?) -> some View {
        let filter: Filter = project.map { .project($0.id) } ?? .inbox
        let selected = !store.showingRecent && store.libraryView == nil && store.connectedView == nil && store.filter == filter
        let count = store.index.thingsInProject[project?.id] ?? 0
        if let project, store.renamingProjectID == project.id {
            RenameField(initial: project.name, commit: { store.renameProject(project.id, to: $0) }, cancel: { store.renamingProjectID = nil })
                .frame(height: 22).padding(.horizontal, 8)
        } else {
            row(project?.name ?? "Not Selected", symbol: project == nil ? "tray" : "folder", dot: project.flatMap(tint),
                pinned: project?.pinned == true, count: count, selected: selected) {
                store.openProject(project?.id)
            }
            .projectDropTarget(project?.id) // drop things here to put them in this project
            .modifier(DeleteOnHover(enabled: project != nil) { if let project { store.requestDeleteProject(project.id) } })
            .contextMenu {
                if let project {
                    Button(project.pinned == true ? "Unpin Tab" : "Pin Tab") { store.togglePin(project.id) }
                    Button("Rename") { store.renamingProjectID = project.id }
                }
                if store.exportURL(for: project?.id) == nil {
                    Button("Save to Mac…") { store.chooseExportLocation(for: project?.id) }
                } else {
                    Button("Show Saved Copy in Finder") { store.revealExport(for: project?.id) }
                }

            }
        }
    }

    private func tint(_ project: Project) -> Color? {
        let tints: [Color] = [Color(red: 0.55, green: 0.66, blue: 0.80), Color(red: 0.60, green: 0.74, blue: 0.62),
                              Color(red: 0.82, green: 0.70, blue: 0.52), Color(red: 0.80, green: 0.60, blue: 0.64),
                              Color(red: 0.68, green: 0.62, blue: 0.80), Color(red: 0.52, green: 0.74, blue: 0.74)]
        guard let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        return tints[index % tints.count]
    }

    private func row(_ title: String, symbol: String? = nil, dot: Color? = nil, pinned: Bool = false, count: Int,
                     selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: 12)).frame(width: 16)
                        .foregroundStyle(selected ? Color.accentColor : Color.secondary)
                }
                if let dot, symbol == nil { Circle().fill(dot).frame(width: 9, height: 9).frame(width: 16) }
                Text(title).font(.system(size: 12.5)).lineLimit(1).truncationMode(.tail)
                if let dot, symbol != nil { Circle().fill(dot).frame(width: 6, height: 6) }
                if pinned { Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(.tertiary) }
                Spacer(minLength: 4)
                if count > 0 { Text("\(count)").font(.system(size: 10.5)).monospacedDigit().foregroundStyle(.tertiary) }
            }
            .padding(.horizontal, 8).frame(height: 26)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(selected ? Color.accentColor.opacity(0.16) : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title), \(count) items")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// Shows or hides the sidebar (with it hidden, the project tabs come back).
struct SidebarToggle: View {
    @AppStorage("window.sidebar") private var sidebar = true

    var body: some View {
        Button { sidebar.toggle() } label: {
            Image(systemName: "sidebar.left").font(.system(size: 12))
                .frame(width: 26, height: 24).contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .foregroundStyle(sidebar ? .primary : .secondary)
        .help(sidebar ? "Hide the sidebar (show project tabs)" : "Show the sidebar")
        .accessibilityLabel(sidebar ? "Hide sidebar" : "Show sidebar")
    }
}

/// All Items (or everything with one colour tag): every thing in every project, newest first, with filters.
struct AllItemsView: View {
    @EnvironmentObject var store: Store
    let view: LibraryView
    @State private var kind: ItemKind?

    private var shown: [Item] {
        let terms = store.search.lowercased().split(separator: " ").map(String.init)
        return store.items
            .filter { item in
                if case .tag(let tag) = view, item.colorTags?.contains(tag) != true { return false }
                if let kind, item.kind != kind { return false }
                return terms.allSatisfy { store.searchableText(item).contains($0) || item.displayTitle.lowercased().contains($0) }
            }
            .sorted { $0.createdAt > $1.createdAt }
    }

    private var taggedFolders: [Folder] {
        guard case .tag(let tag) = view else { return [] }
        return store.folders.filter { $0.colorTags?.contains(tag) == true }
    }

    var body: some View {
        let items = shown
        let _ = store.libraryShown = items.map(\.id)
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                if case .tag(let tag) = view { Circle().fill(tag.color).frame(width: 10, height: 10) }
                Text(store.tabTitle).font(.system(size: 13, weight: .semibold))
                Text("\(items.count)").font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
                Spacer()
                ForEach([nil, ItemKind.link, .image, .text, .file], id: \.self) { option in
                    chip(option)
                }
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(taggedFolders) { folder in
                        HStack {
                            FolderTile(folder: folder, compact: false, asRow: true)
                            location(project: folder.projectID, folder: folder.parentID)
                        }
                    }
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 6) {
                            CardView(item: item, asRow: true, rowIndex: index)
                            location(project: item.projectID, folder: item.folderID)
                            Button { reveal(item) } label: { Image(systemName: "arrow.right.circle").font(.system(size: 12)) }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Show it in its project").accessibilityLabel("Show in its project")
                                .padding(.trailing, 10)
                        }
                    }
                }
            }
            if items.isEmpty && taggedFolders.isEmpty {
                Text(store.search.isEmpty ? "Nothing here yet." : "Nothing matches.").font(.system(size: 12)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func chip(_ option: ItemKind?) -> some View {
        let title: String = switch option {
        case nil: "All"
        case .link?: "Links"
        case .image?: "Pictures"
        case .text?: "Notes"
        case .file?: "Files"
        }
        let on = kind == option
        return Button { kind = option } label: {
            Text(title).font(.system(size: 11, weight: on ? .semibold : .regular))
                .padding(.horizontal, 9).frame(height: 22)
                .background(Capsule().fill(on ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05)))
                .foregroundStyle(on ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private func location(project: UUID?, folder: UUID?) -> some View {
        var parts = [project.flatMap { id in store.projects.first { $0.id == id }?.name } ?? "Not Selected"]
        if let folder, let f = store.folder(folder) { parts.append(f.name) }
        return Text(parts.joined(separator: " ▸ ")).font(.system(size: 10.5)).foregroundStyle(.secondary)
            .lineLimit(1).frame(width: 150, alignment: .trailing)
    }

    /// Jumps to the thing in its own project and folder, selected.
    private func reveal(_ item: Item) {
        store.openProject(item.projectID)
        store.openFolderID = item.folderID
        store.selection = [.item(item.id)]
        store.scrollTarget = .item(item.id)
    }
}

/// Where the Connected heading sits, so a folder dropped on it connects.
struct ConnectDropKey: PreferenceKey {
    static let defaultValue: CGRect = .zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

/// A small trash button that shows while the pointer is over a project in a list — the place projects are deleted
/// (tabs only close). It asks first.
struct DeleteOnHover: ViewModifier {
    let enabled: Bool
    let action: () -> Void
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .trailing) {
                if enabled && hovering {
                    Button(action: action) {
                        Image(systemName: "trash").font(.system(size: 10.5))
                            .frame(width: 22, height: 20)
                            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(.regularMaterial))
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .padding(.trailing, 4)
                    .help("Delete Project…")
                    .accessibilityLabel("Delete project")
                }
            }
            .onHover { hovering = $0 }
    }
}
