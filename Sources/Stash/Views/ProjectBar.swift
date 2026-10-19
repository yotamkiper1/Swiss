import SwiftUI

/// Project tabs, like browser tabs: each project, + for a new one. The selected tab is where new things are saved.
/// × closes a tab (the project stays, and its tab comes back when you open it again). Projects are deleted from
/// All Projects (the list button) or the sidebar — never from a tab.
struct ProjectBar: View {
    @EnvironmentObject var store: Store
    /// The most project tabs to show (the pop-up has room for fewer).
    var limit = 6

    @ObservedObject private var connected = ConnectedRegistry.shared

    /// Every project gets a tab, pinned ones first, then in the order they were made (they don't jump around).
    /// Pinned first; closed tabs stay out until you open the project again (the one you're on always shows).
    private var tabs: [Project] {
        // The project on screen always has its tab (even one you closed and opened again from the list).
        let viewing = !store.showingRecent && store.connectedView == nil && store.libraryView == nil
        let current: UUID? = { if viewing, case .project(let id) = store.filter { id } else { nil } }()
        let open = store.projects.filter { $0.tabClosed != true || $0.id == current }
        return open.filter { $0.pinned == true } + open.filter { $0.pinned != true }
    }

    var body: some View {
        bar.onPreferenceChange(ProjectDropKey.self) { frames in MainActor.assumeIsolated { Store.shared.projectDropFrames = frames } }
            .onPreferenceChange(ConnectedTabDropKey.self) { frames in MainActor.assumeIsolated { ConnectedTabs.frames = frames } }
    }

    /// Like Chrome: tabs share the room and shrink as there are more, down to a smallest size; past that, the
    /// strip scrolls sideways (swipe, or shift-scroll) and ⌄ lists them all. The tab you're on is always scrolled into view.
    private var bar: some View {
        let small = limit <= 3
        let projects = tabs
        let openConnected = connected.openTabs.compactMap(connected.folder)
        return HStack(spacing: 2) {
            RecentTab(iconOnly: small)
            GeometryReader { geo in
                let count = CGFloat(max(1, projects.count + openConnected.count))
                let width = min(small ? 120 : 170, max(small ? 68 : 84, (geo.size.width - 2) / count - 1))
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 1) {
                            ForEach(projects) { project in
                                ProjectTab(title: project.name, filter: .project(project.id), project: project, width: width)
                                    .id(project.id)
                            }
                            // Connected folders you've opened: their own tabs, until you close them.
                            ForEach(openConnected, id: \.id) { folder in
                                ConnectedTab(folder: folder, width: width).id(folder.id)
                            }
                        }
                        .frame(minWidth: geo.size.width, alignment: .leading)
                    }
                    .onAppear { reveal(proxy) }
                    .onChange(of: store.filter) { reveal(proxy) }
                    .onChange(of: store.connectedView?.folderID) { reveal(proxy) }
                }
            }
            .frame(height: 30)
            AllProjectsButton(total: store.projects.count, labelled: projects.isEmpty && openConnected.isEmpty)
            Button { AppDelegate.shared.newProject() } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(.secondary)
            .help("New project")
        .accessibilityLabel("New project")
        }
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        let id: UUID? = store.connectedView?.folderID ?? { if case .project(let id) = store.filter { id } else { nil } }()
        guard let id else { return }
        DispatchQueue.main.async { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id) } }
    }
}

private struct ProjectTab: View {
    @EnvironmentObject var store: Store
    let title: String
    let filter: Filter
    let project: Project?
    var width: CGFloat = 150
    @State private var hovering = false

    /// Soft, grayish colors for projects (Not Selected stays plain gray).
    static let tints: [Color] = [
        Color(red: 0.55, green: 0.66, blue: 0.80), // blue-gray
        Color(red: 0.60, green: 0.74, blue: 0.62), // sage
        Color(red: 0.82, green: 0.70, blue: 0.52), // sand
        Color(red: 0.80, green: 0.60, blue: 0.64), // rose
        Color(red: 0.68, green: 0.62, blue: 0.80), // lavender
        Color(red: 0.52, green: 0.74, blue: 0.74), // teal
    ]

    private var tint: Color? {
        guard let project, let index = store.projects.firstIndex(where: { $0.id == project.id }) else { return nil }
        return Self.tints[index % Self.tints.count]
    }

    var body: some View {
        let selected = store.filter == filter && !store.showingRecent && store.connectedView == nil && store.libraryView == nil
        HStack(spacing: 5) {
            if let tint, !selected {
                Circle().fill(tint).frame(width: 6, height: 6)
            }
            if project?.pinned == true {
                Image(systemName: "pin.fill").font(.system(size: 7)).foregroundStyle(.tertiary)
            }
            if let project, store.renamingProjectID == project.id {
                RenameField(initial: project.name,
                            commit: { store.renameProject(project.id, to: $0) },
                            cancel: { store.renamingProjectID = nil })
                    .frame(width: 110, height: 20)
            } else {
                Text(title)
                    .font(.system(size: 12, weight: selected ? .medium : .regular))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .lineLimit(1)
            }
            if let project, hovering || selected {
                Button { store.closeTab(project.id) } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 8, weight: .bold))
                        .frame(width: 14, height: 14)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close tab (the project stays — delete it from All Projects)")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, project == nil ? 12 : 7)
        .padding(.vertical, 6)
        .frame(width: selected ? max(width, min(150, width * 1.6)) : width, alignment: .leading) // the open tab stays readable
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(selected ? (tint.map { $0.opacity(0.38) } ?? Color.primary.opacity(0.09))
                      : Color.primary.opacity(hovering ? 0.04 : 0))
        )
        .projectDropTarget(project?.id) // drop things on a tab to put them in that project
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            if (NSApp.currentEvent?.clickCount ?? 1) >= 2, let project {
                AppDelegate.shared.renameProject(project)
            } else {
                store.openProject(project?.id)
            }
        }
        // Drag a tab out (to the Desktop, Finder…) for a copy of the whole project as a real folder.
        .onDrag {
            store.draggingItemID = nil
            store.draggingFolderID = nil
            return store.projectProvider(project?.id)
        }
        .contextMenu {
            if store.exportURL(for: project?.id) == nil {
                Button("Save to Mac…") { store.chooseExportLocation(for: project?.id) }
            } else {
                Button("Show Saved Copy in Finder") { store.revealExport(for: project?.id) }
                Button("Stop Updating Saved Copy") { store.stopExport(for: project?.id) }
            }
            Divider()
            if let project {
                Button(project.pinned == true ? "Unpin Tab" : "Pin Tab") { store.togglePin(project.id) }
                Button("Rename") { AppDelegate.shared.renameProject(project) }
                Button("Close Tab") { store.closeTab(project.id) }
            }
        }
        .help(project == nil ? "Things that aren't in a project" : "\(title) — double-click to rename")
    }
}

/// The first tab: Recent — what you copied and screenshotted lately. Shows how many arrived today.
private struct RecentTab: View {
    /// The pop-up has little room: just the clock (and the count).
    var iconOnly = false
    @EnvironmentObject var store: Store
    @ObservedObject private var recent = RecentStore.shared
    @State private var hovering = false

    var body: some View {
        let selected = store.showingRecent
        let today = recent.items.filter { Calendar.current.isDateInToday($0.lastSeen) && $0.keptIn == nil }.count
        HStack(spacing: 4) {
            Image(systemName: recent.paused ? "pause.circle" : "clock.arrow.circlepath")
                .font(.system(size: 11, weight: .medium))
            if !iconOnly { Text("Recent").font(.system(size: 12, weight: selected ? .medium : .regular)) }
            if today > 0 && !selected {
                Text("\(today)").font(.system(size: 9.5, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.white).padding(.horizontal, 5).frame(minWidth: 16, minHeight: 15)
                    .background(Capsule().fill(Color.accentColor.opacity(0.85)))
            }
        }
        .foregroundStyle(selected ? .primary : .secondary)
        .padding(.horizontal, iconOnly ? 7 : 10).padding(.vertical, 6)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.primary.opacity(selected ? 0.09 : (hovering ? 0.04 : 0))))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { store.showingRecent = true; store.libraryView = nil }
        .help("Recent — what you copied and screenshotted lately; Keep puts it in a project")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Recent, \(recent.items.count) items")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}


/// A connected folder's tab: teal, with a drive icon, so it's clearly a real folder elsewhere on the Mac (shown as it
/// is, never copied). × closes the tab; the folder stays connected.
private struct ConnectedTab: View {
    @EnvironmentObject var store: Store
    let folder: ConnectedFolder
    var width: CGFloat = 150
    @State private var hovering = false
    static let tint = Color(red: 0.20, green: 0.62, blue: 0.66)

    var body: some View {
        let selected = store.connectedView?.folderID == folder.id
        HStack(spacing: 5) {
            Image(systemName: "externaldrive.connected.to.line.below")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(Self.tint)
            Text(folder.name)
                .font(.system(size: 12, weight: selected ? .medium : .regular))
                .foregroundStyle(selected ? .primary : .secondary)
                .lineLimit(1)
            Button { ConnectedRegistry.shared.closeTab(folder.id) } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).frame(width: 14, height: 14).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .opacity(hovering || selected ? 1 : 0)
            .help("Close this tab (the folder stays connected)")
            .accessibilityLabel("Close tab")
        }
        .padding(.leading, 10).padding(.trailing, 7).padding(.vertical, 6)
        .frame(width: width, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Self.tint.opacity(selected ? 0.28 : (hovering ? 0.12 : 0.07)))
        )
        .overlay(RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Self.tint.opacity(selected ? 0.5 : 0.25), lineWidth: 1))
        .background(GeometryReader { Color.clear.preference(key: ConnectedTabDropKey.self, value: [folder.id: $0.frame(in: .global)]) })
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { ConnectedRegistry.shared.open(folder.id) }
        .contextMenu {
            Button("Reveal in Finder") { if let url = ConnectedRegistry.shared.resolve(folder.id) { NSWorkspace.shared.activateFileViewerSelecting([url]) } }
            Button("Close Tab") { ConnectedRegistry.shared.closeTab(folder.id) }
            Divider()
            Button("Remove Shortcut (the folder stays)", role: .destructive) { ConnectedRegistry.shared.remove(folder.id) }
        }
        .help("Connected folder: \(folder.path) — shown as it is, nothing copied")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Connected folder tab: \(folder.name)")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}
