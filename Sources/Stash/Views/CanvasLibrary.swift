import AppKit
import SwiftUI

/// The Frame's library: Recent, All Items or a project, down the side of the canvas. Drag anything onto the canvas
/// (or double-click it to drop it in the middle). Nothing leaves its project — the canvas gets its own copy.
struct CanvasLibrary: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var recent = RecentStore.shared
    @AppStorage("canvas.library.source") private var source = "recent"
    @State private var query = ""

    private enum Row: Identifiable {
        case saved(Item)
        case recent(RecentItem)
        var id: UUID { switch self { case .saved(let i): i.id; case .recent(let r): r.id } }
    }

    private var rows: [Row] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        switch source {
        case "recent":
            let list = recent.items.filter { entry in entry.itemID.map { store.index.itemIDs.contains($0) } ?? true }
            return list.filter { q.isEmpty || $0.title.lowercased().contains(q) }.map(Row.recent)
        case "all":
            return Array(store.items.lazy
                .filter { q.isEmpty || $0.displayTitle.lowercased().contains(q) }
                .sorted { $0.createdAt > $1.createdAt }
                .prefix(2000)
                .map(Row.saved))
        default:
            let id = UUID(uuidString: source)
            return store.items
                .filter { $0.projectID == id && (q.isEmpty || $0.displayTitle.lowercased().contains(q)) }
                .sorted { $0.createdAt > $1.createdAt }
                .map(Row.saved)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Picker("", selection: $source) {
                Label("Recent", systemImage: "clock.arrow.circlepath").tag("recent")
                Label("All Items", systemImage: "square.stack").tag("all")
                Divider()
                ForEach(store.projects) { project in
                    Label(project.name, systemImage: "folder").tag(project.id.uuidString)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            HStack(spacing: 4) {
                Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("Search", text: $query).textFieldStyle(.plain).font(.system(size: 11.5))
            }
            .padding(.horizontal, 7)
            .frame(height: 22)
            .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            let list = rows
            if list.isEmpty {
                Text(query.isEmpty ? "Nothing here yet." : "Nothing matches.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(list) { row in LibraryRow(row: row) }
                    }
                }
            }
            Text("Drag in · double-click adds · Space looks")
                .font(.system(size: 9.5)).foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
        }
        .padding(8)
        .background(Color.primary.opacity(0.03))
    }

    private struct LibraryRow: View {
        @EnvironmentObject var store: Store
        @ObservedObject private var pick = CanvasLibraryPick.shared
        let row: Row
        @State private var hovering = false

        /// A small picture of it: the photo, the video's frame, the page's preview — or its kind's icon.
        private var thumb: NSImage? {
            switch row {
            case .saved(let item): store.displayImage(item, maxPixels: 64)
            case .recent(let entry):
                entry.itemID.flatMap { id in store.items.first { $0.id == id } }.flatMap { store.displayImage($0, maxPixels: 64) }
                    ?? RecentStore.shared.previewImage(entry)
            }
        }

        private var title: String {
            switch row {
            case .saved(let item): item.displayTitle
            case .recent(let entry): entry.title
            }
        }

        private var symbol: String {
            let kind: String = switch row {
            case .saved(let item): item.kind.rawValue
            case .recent(let entry): entry.kind.rawValue
            }
            switch kind {
            case "link": return "link"
            case "image", "screenshot": return "photo"
            case "text": return "note.text"
            default: return "doc"
            }
        }

        var body: some View {
            let picked = pick.id == row.id
            HStack(spacing: 6) {
                Group {
                    if let thumb {
                        Image(nsImage: thumb).resizable().scaledToFill()
                    } else if symbol == "note.text" {
                        NotePadIcon(size: 18)
                    } else if let file = fileForIcon {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.path)).resizable().scaledToFit()
                    } else {
                        Image(systemName: symbol).font(.system(size: 10.5)).foregroundStyle(.secondary)
                    }
                }
                .frame(width: 22, height: 22)
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                Text(title.isEmpty ? "Untitled" : title).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6)
            .frame(height: 28)
            // The one you're looking at: a soft gray bar (Space shows it bigger).
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color.primary.opacity(picked ? 0.13 : hovering ? 0.06 : 0)))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .onTapGesture(count: 2) { addToCanvas() }
            .onTapGesture { pick.id = row.id; pick.preview = preview }
            .onDrag { provider() }
            .help("Drag onto the canvas, or double-click to add it")
        }

        private var pasteboardItems: [NSPasteboardItem] {
            switch row {
            case .saved(let item): store.pasteboardItem(for: item).map { [$0] } ?? []
            case .recent(let entry): RecentDrag.shared.pasteboardItems(for: entry)
            }
        }

        /// A file without a picture shows its real icon (a movie, a PDF, a song…).
        private var fileForIcon: URL? {
            switch row {
            case .saved(let item): item.kind == .file ? item.linkURL : nil
            case .recent(let entry): entry.kind == .files ? entry.fileURLs.first : nil
            }
        }

        /// Space: Quick Look, small, over everything.
        private func preview() {
            switch row {
            case .saved(let item):
                if let url = store.dragFile(for: item) { QuickLook.shared.show([url]) } else { NSSound.beep() }
            case .recent(let entry): RecentQuickLook.show([entry])
            }
        }

        private func addToCanvas() {
            let pb = NSPasteboard(name: NSPasteboard.Name("swiss.canvas.library"))
            pb.clearContents()
            pb.writeObjects(pasteboardItems)
            if !CanvasStore.shared.ingest(pb) { NSSound.beep() }
        }

        private func provider() -> NSItemProvider {
            if case .saved(let item) = row { return store.itemProvider(for: item) }
            guard let first = pasteboardItems.first else { return NSItemProvider() }
            if let file = first.string(forType: .fileURL).flatMap(URL.init(string:)), let p = NSItemProvider(contentsOf: file) { return p }
            if let link = first.string(forType: .URL).flatMap(URL.init(string:)) { return NSItemProvider(object: link as NSURL) }
            return NSItemProvider(object: (first.string(forType: .string) ?? "") as NSString)
        }
    }
}

/// The library row you clicked (a gray bar), and how to preview it with Space.
@MainActor
final class CanvasLibraryPick: ObservableObject {
    static let shared = CanvasLibraryPick()
    @Published var id: UUID?
    var preview: (() -> Void)?

    /// Space with nothing selected on the canvas: Quick Look for the row you clicked.
    func previewIfPicked() -> Bool {
        guard id != nil, let preview else { return false }
        preview()
        return true
    }
}
