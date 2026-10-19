import SwiftUI

// MARK: - Which projects get a tab

extension Store {
    func togglePin(_ id: UUID) {
        guard let index = projects.firstIndex(where: { $0.id == id }) else { return }
        projects[index].pinned = projects[index].pinned == true ? nil : true
        save(touchesFiles: false)
    }

    /// How much is in a project (or Not Selected): things and folders, anywhere inside.
    func contents(of project: UUID?) -> (items: Int, folders: Int) {
        (items.lazy.filter { $0.projectID == project }.count, folders.lazy.filter { $0.projectID == project }.count)
    }

    /// A few pictures from a project, for its card.
    func previewImages(ofProject project: UUID?, limit: Int = 3) -> [NSImage] {
        Array(items.lazy.filter { $0.projectID == project && ($0.kind == .image || $0.kind == .link) }
            .compactMap { self.displayImage($0) }.prefix(limit))
    }
}

// MARK: - The button and the overview

/// Next to the tabs: a small ▾ with how many projects you have. Opens the list of all of them.
struct AllProjectsButton: View {
    @EnvironmentObject var store: Store
    let total: Int
    private var showing: Binding<Bool> { Binding(get: { store.showingAllProjects }, set: { store.showingAllProjects = $0 }) }

    var body: some View {
        Button { store.showingAllProjects.toggle() } label: {
            HStack(spacing: 2) {
                Image(systemName: "chevron.down.circle").font(.system(size: 11))
                if total > 0 {
                    Text("\(total)").font(.system(size: 10, weight: .semibold, design: .rounded)).monospacedDigit()
                }
            }
            .padding(.horizontal, 5)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .foregroundStyle(.secondary)
        .help("All \(total) projects — see them all, pin the ones you want as tabs")
        .accessibilityLabel("All \(total) projects")
        .popover(isPresented: showing, arrowEdge: .bottom) {
            AllProjectsView { store.showingAllProjects = false }
        }
    }
}

/// Every project in a small list: its name, how much is in it, and a pin to keep its tab. Click to open.
struct AllProjectsView: View {
    @EnvironmentObject var store: Store
    let close: () -> Void
    @State private var query = ""

    private var shown: [Project] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = store.projects.sorted { ($0.lastOpened ?? $0.createdAt) > ($1.lastOpened ?? $1.createdAt) }
        return q.isEmpty ? list : list.filter { $0.name.lowercased().contains(q) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if store.projects.count > 6 {
                HStack(spacing: 4) {
                    Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                    TextField("Find a project", text: $query).textFieldStyle(.plain).font(.system(size: 11.5))
                }
                .padding(.horizontal, 7)
                .frame(height: 24)
                .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                .padding(.bottom, 2)
            }
            ScrollView {
                VStack(spacing: 1) {
                    ForEach(shown) { ProjectRow(project: $0, close: close) }
                }
            }
            .frame(maxHeight: 320)
            Divider().padding(.vertical, 2)
            Button {
                close()
                AppDelegate.shared.newProject()
            } label: {
                Label("New Project", systemImage: "plus").font(.system(size: 11.5))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 6).frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(QuietButtonStyle())
            .foregroundStyle(.secondary)
        }
        .padding(8)
        .frame(width: 250)
    }
}

private struct ProjectRow: View {
    @EnvironmentObject var store: Store
    let project: Project?
    let close: () -> Void
    @State private var hovering = false

    private var filter: Filter { project.map { .project($0.id) } ?? .inbox }

    var body: some View {
        let selected = store.filter == filter
        let count = store.contents(of: project?.id)
        HStack(spacing: 7) {
            Image(systemName: selected ? "checkmark" : "folder")
                .font(.system(size: 10, weight: selected ? .bold : .regular))
                .foregroundStyle(selected ? Color.accentColor : .secondary)
                .frame(width: 14)
            Text(project?.name ?? "Not Selected")
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .lineLimit(1)
            Spacer(minLength: 4)
            Text("\(count.items + count.folders)")
                .font(.system(size: 10.5)).monospacedDigit()
                .foregroundStyle(.tertiary)
            if let project, hovering {
                Button { close(); store.requestDeleteProject(project.id) } label: {
                    Image(systemName: "trash").font(.system(size: 10)).frame(width: 18, height: 18).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Delete Project…")
                .accessibilityLabel("Delete \(project.name)")
            }
            if let project {
                Button { store.togglePin(project.id) } label: {
                    Image(systemName: project.pinned == true ? "pin.fill" : "pin")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(project.pinned == true ? 0 : 45))
                        .foregroundStyle(project.pinned == true ? Color.accentColor : .secondary)
                        .frame(width: 18, height: 18)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .opacity(hovering || project.pinned == true ? 1 : 0)
                .help(project.pinned == true ? "Unpin — tab only when recent" : "Pin — always keep a tab")
            } else {
                Color.clear.frame(width: 18, height: 18)
            }
        }
        .padding(.horizontal, 6)
        .frame(height: 26)
        .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(Color.primary.opacity(hovering ? 0.07 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            store.filter = filter
            close()
        }
        .contextMenu {
            if let project {
                Button(project.pinned == true ? "Unpin Tab" : "Pin Tab") { store.togglePin(project.id) }
                Button("Rename") {
                    store.filter = filter
                    close()
                    AppDelegate.shared.renameProject(project)
                }
                Divider()
                Button("Delete Project…", role: .destructive) { close(); store.requestDeleteProject(project.id) }
            }
        }
    }
}
