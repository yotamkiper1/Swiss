import AppKit
import SwiftUI

/// What's selected in the connected folder on screen (shared with the keyboard: Space, Return, ⌫).
@MainActor
final class ConnectedSelection: ObservableObject {
    static let shared = ConnectedSelection()
    @Published var paths: Set<String> = []
    var entries: [ConnectedEntry] = []

    var selectedURLs: [URL] { entries.filter { paths.contains($0.url.path) }.map(\.url) }
    /// The last thing clicked, where a ⇧-click range starts.
    var anchor: String?
    /// The order things are shown in (set by the view), for ⇧-click ranges.
    var shownOrder: [String] = []

    /// Click = just this, ⌘-click = add / remove, ⇧-click = everything from the last click to this one.
    func click(_ path: String, flags: NSEvent.ModifierFlags) {
        let order = shownOrder.isEmpty ? entries.map(\.url.path) : shownOrder
        if flags.contains(.shift), let b = order.firstIndex(of: path),
           let a = anchor.flatMap({ paths.contains($0) ? order.firstIndex(of: $0) : nil })
            ?? order.indices.filter({ paths.contains(order[$0]) }).min(by: { abs($0 - b) < abs($1 - b) }) {
            paths.formUnion(order[min(a, b)...max(a, b)])
            return
        }
        if flags.contains(.command) {
            if paths.contains(path) { paths.remove(path) } else { paths.insert(path) }
        } else {
            paths = [path]
        }
        anchor = path
    }
}

/// A connected folder, like a Finder window inside Swiss — and you can change it like a project: new folders and
/// notes, drop or paste things in, rename (Return), drag to move into a folder / back up the path / anywhere on the
/// board, Move to Trash (⌘⌫), the wand. It all happens in the real folder, and changes made in Finder show up here
/// (always the same). ⌘Z undoes Swiss's last change.
struct ConnectedFolderView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var registry = ConnectedRegistry.shared
    @ObservedObject private var thumbs = ConnectedThumbnails.shared
    @ObservedObject private var selection = ConnectedSelection.shared
    @ObservedObject private var editor = ConnectedEditor.shared
    @StateObject private var listing = ConnectedListing()
    @AppStorage(BoardLayout.key) private var layout = BoardLayout.icons.rawValue
    @AppStorage(BoardSort.key) private var sort = BoardSort.manual.rawValue
    @State private var query = ""
    @State private var scrollTop: CGFloat = 0
    @State private var noteDraft = ""
    let location: ConnectedLocation
    let compact: Bool

    private var folder: ConnectedFolder? { registry.folder(location.folderID) }
    private var rootURL: URL? { registry.resolve(location.folderID) }
    private var currentURL: URL? {
        guard let root = rootURL else { return nil }
        return location.subpath.isEmpty ? root : root.appendingPathComponent(location.subpath, isDirectory: true)
    }

    private var tileSize: CGSize { compact ? CGSize(width: 72, height: 104) : CGSize(width: 84, height: 112) }

    /// What's shown, in the order Arrange By asks for (None: folders first, then by name — and where you put them).
    private var shown: [ConnectedEntry] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let list = q.isEmpty ? listing.entries : listing.entries.filter { $0.name.lowercased().contains(q) }
        switch BoardSort(rawValue: sort) ?? .manual {
        case .manual, .tags: return list
        case .name: return list.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        case .kind: return list.sorted { ($0.isFolder ? "" : $0.url.pathExtension.lowercased(), $0.name) < ($1.isFolder ? "" : $1.url.pathExtension.lowercased(), $1.name) }
        case .added: return list.sorted { ($0.modified ?? .distantPast) > ($1.modified ?? .distantPast) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            if rootURL == nil || listing.missing {
                unavailable
            } else if shown.isEmpty && !listing.loading {
                VStack(spacing: 6) {
                    Text(query.isEmpty ? "This folder is empty." : "Nothing here matches “\(query)”.").font(.system(size: 12)).foregroundStyle(.secondary)
                    if query.isEmpty {
                        Text("Drop or paste things here — they go into the real folder.").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if layout == BoardLayout.list.rawValue {
                let entries = shown
                let _ = selection.shownOrder = entries.map(\.url.path)
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in row(entry, index: index) }
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { selection.paths = [] }
            } else {
                board
            }
        }
        .onAppear(perform: refresh)
        .onChange(of: location) { refresh() }
        .onChange(of: listing.entries) { selection.entries = listing.entries; publishFolders() }
        .onPreferenceChange(ConnectedTileFramesKey.self) { frames in MainActor.assumeIsolated { ConnectedDrag.shared.tileFrames = frames } }
        .onPreferenceChange(ConnectedCrumbFramesKey.self) { frames in MainActor.assumeIsolated { ConnectedDrag.shared.crumbFrames = frames } }
    }

    private func refresh() {
        selection.paths = []
        query = ""
        editor.renamingPath = nil
        listing.show(currentURL)
        registry.remember(location)
        publishFolders()
    }

    private func publishFolders() {
        ConnectedDrag.shared.folderPaths = Set(listing.entries.filter(\.isFolder).map(\.url.path))
    }

    // MARK: The board

    /// Icons: every place worked out first; only what's near the screen is made into views (big folders stay quick).
    private var board: some View {
        GeometryReader { geo in
            let width = max(tileSize.width, geo.size.width - 24)
            let entries = shown
            let _ = selection.shownOrder = entries.map(\.url.path)
            let manual = BoardSort(rawValue: sort) == .manual && query.isEmpty
            let tiles = entries.map { BoardPlacement.Tile(size: tileSize, tileSized: true, spot: manual ? editor.spot(of: $0.url) : nil) }
            let frames = BoardPlacement(folderWidth: tileSize.width, cardWidth: tileSize.width, columns: 1, spacing: 8).frames(width: width, tiles: tiles)
            let height = frames.map(\.maxY).max() ?? 0
            let band = CGRect(x: -10_000, y: scrollTop - 500, width: 20_000, height: geo.size.height + 1_000)
            let _ = ConnectedDrag.shared.boardFrames = Dictionary(zip(entries.map(\.url.path), frames), uniquingKeysWith: { a, _ in a })
            ScrollView {
                PlacedLayout(size: CGSize(width: width, height: height)) {
                    ForEach(Array(zip(entries, frames)).filter { band.intersects($0.1) }, id: \.0.id) { entry, frame in
                        tile(entry).layoutValue(key: BoardFrameKey.self, value: frame)
                    }
                }
                .background(GeometryReader { g in Color.clear.preference(key: ConnectedOriginKey.self, value: g.frame(in: .global).origin) })
                .padding(12)
                .frame(minWidth: geo.size.width, minHeight: geo.size.height, alignment: .topLeading)
                .contentShape(Rectangle())
                .onTapGesture { selection.paths = []; editor.renamingPath = nil }
            }
            .onPreferenceChange(ConnectedOriginKey.self) { origin in
                MainActor.assumeIsolated {
                    let viewport = geo.frame(in: .global)
                    ConnectedDrag.shared.boardOrigin = origin
                    ConnectedDrag.shared.viewport = viewport
                    let top = ((viewport.minY - origin.y) / 300).rounded(.down) * 300
                    if top != scrollTop { scrollTop = top }
                }
            }
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: 6) {
            if !location.subpath.isEmpty {
                Button { goUp() } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22) }
                    .buttonStyle(QuietButtonStyle()).help("Back up (⌫) — or drag things here to move them up").accessibilityLabel("Back up a folder")
            }
            Image(systemName: "externaldrive.connected.to.line.below").font(.system(size: 11)).foregroundStyle(.secondary)
            // The path: click any part to go there, or drop things on it to move them there.
            let parts = location.subpath.split(separator: "/").map(String.init)
            crumb(folder?.name ?? "Folder", subpath: "", current: parts.isEmpty)
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold)).foregroundStyle(.tertiary)
                crumb(part, subpath: parts.prefix(index + 1).joined(separator: "/"), current: index == parts.count - 1)
            }
            Spacer(minLength: 4)
            Label("In sync with Finder", systemImage: "arrow.triangle.2.circlepath").labelStyle(.iconOnly).font(.system(size: 10)).foregroundStyle(.tertiary)
                .help("This is the real folder: changes here happen in Finder, and changes in Finder show up here")
            Button { editor.newFolder() } label: { Image(systemName: "folder.badge.plus").font(.system(size: 11)).frame(width: 22, height: 22) }
                .buttonStyle(QuietButtonStyle()).help("New folder (⌘2)").accessibilityLabel("New folder")
            Button { noteDraft = ""; editor.composing = true } label: { Image(systemName: "square.and.pencil").font(.system(size: 11)).frame(width: 22, height: 22) }
                .buttonStyle(QuietButtonStyle()).help("New note — saved as a text file here (⌘1)").accessibilityLabel("New note")
                .popover(isPresented: $editor.composing, arrowEdge: .bottom) { noteComposer }
            HStack(spacing: 3) {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 10)).foregroundStyle(.tertiary)
                TextField("Filter", text: $query).textFieldStyle(.plain).font(.system(size: 11)).frame(width: compact ? 50 : 90)
            }
            .padding(.horizontal, 6).frame(height: 22)
            .background(Capsule().fill(Color.primary.opacity(0.05)))
            Button { if let url = currentURL { NSWorkspace.shared.activateFileViewerSelecting(selection.selectedURLs.isEmpty ? [url] : selection.selectedURLs) } } label: {
                Image(systemName: "folder").font(.system(size: 11)).frame(width: 22, height: 22)
            }
            .buttonStyle(QuietButtonStyle()).help("Reveal in Finder").accessibilityLabel("Reveal in Finder")
            Button { ConnectedRegistry.shared.closeTab(location.folderID) } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22)
            }
            .buttonStyle(QuietButtonStyle()).help("Close this folder (it stays connected)").accessibilityLabel("Close folder")
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
    }

    private func crumb(_ title: String, subpath: String, current: Bool) -> some View {
        let target = (subpath.isEmpty ? rootURL : rootURL?.appendingPathComponent(subpath, isDirectory: true))?.path
        return Button(title) { go(to: subpath) }
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: current ? .semibold : .regular))
            .lineLimit(1)
            .padding(.horizontal, 3)
            .background(RoundedRectangle(cornerRadius: 4).fill(Color.accentColor.opacity(target != nil && editor.dropTargetPath == target ? 0.25 : 0)))
            .background(GeometryReader { Color.clear.preference(key: ConnectedCrumbFramesKey.self, value: current ? [:] : [subpath: $0.frame(in: .global)]) })
    }

    private var noteComposer: some View {
        VStack(alignment: .trailing, spacing: 8) {
            TextEditor(text: $noteDraft)
                .font(.system(size: 13))
                .environment(\.layoutDirection, noteDraft.isRightToLeft ? .rightToLeft : .leftToRight)
                .frame(width: 260, height: 120)
            HStack {
                Text("Saved as a .txt file in this folder").font(.system(size: 10.5)).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { editor.composing = false }
                Button("Save") {
                    if !noteDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, let url = editor.writeNote(noteDraft) {
                        selection.paths = [url.path]
                    }
                    editor.composing = false
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(10)
    }

    private var unavailable: some View {
        VStack(spacing: 10) {
            Image(systemName: "questionmark.folder").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
            Text("Folder unavailable").font(.system(size: 13, weight: .semibold))
            Text("“\(folder?.name ?? "This folder")” isn't where it was — maybe it was moved, renamed, or its drive isn't connected. Nothing was changed or deleted.")
                .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 280)
            HStack {
                Button("Try Again") { listing.show(currentURL); listing.reload() }
                Button("Locate…") { registry.locate(location.folderID) }.buttonStyle(.borderedProminent)
                Button("Remove Shortcut") { registry.remove(location.folderID) }
            }
            .controlSize(.small)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Items

    private func tile(_ entry: ConnectedEntry) -> some View {
        let selected = selection.paths.contains(entry.url.path)
        let target = editor.dropTargetPath == entry.url.path
        let side: CGFloat = compact ? 50 : 58
        return VStack(spacing: 5) {
            icon(entry, size: side)
                .frame(width: side, height: side)
                .padding(7)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(target ? Color.accentColor.opacity(0.25) : Color.primary.opacity(selected ? 0.1 : 0)))
            name(entry, selected: selected, centered: true)
        }
        .frame(width: tileSize.width, height: tileSize.height, alignment: .top)
        .background(GeometryReader { Color.clear.preference(key: ConnectedTileFramesKey.self, value: [entry.url.path: $0.frame(in: .global)]) })
        .modifier(EntryInteractions(entry: entry, open: open))
    }

    @ViewBuilder private func name(_ entry: ConnectedEntry, selected: Bool, centered: Bool) -> some View {
        if editor.renamingPath == entry.url.path {
            RenameField(initial: entry.url.lastPathComponent, alignment: centered ? .center : .left, onDark: selected && !centered,
                        commit: { editor.rename(entry.url, to: $0) },
                        cancel: { editor.renamingPath = nil })
                .frame(width: centered ? tileSize.width + 20 : 220, height: 20)
        } else {
            Text(entry.name).font(.system(size: centered ? 11 : 12, weight: centered ? .medium : .regular))
                .multilineTextAlignment(centered ? .center : .leading).lineLimit(centered ? 2 : 1).truncationMode(.middle)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, centered ? 5 : 0).padding(.vertical, centered ? 1.5 : 0)
                .background(RoundedRectangle(cornerRadius: 4, style: .continuous).fill(selected && centered ? Color.accentColor.opacity(0.72) : .clear))
        }
    }

    private func row(_ entry: ConnectedEntry, index: Int) -> some View {
        let selected = selection.paths.contains(entry.url.path)
        let target = editor.dropTargetPath == entry.url.path
        return HStack(spacing: 8) {
            icon(entry, size: 18).frame(width: 18, height: 18)
            name(entry, selected: selected, centered: false)
            Spacer()
            if let size = entry.size, !entry.isFolder {
                Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            if let date = entry.modified {
                Text(date.formatted(date: .abbreviated, time: .shortened)).font(.system(size: 10.5)).foregroundStyle(.secondary).frame(width: 130, alignment: .trailing)
            }
        }
        .foregroundStyle(selected ? Color.white : Color.primary)
        .padding(.horizontal, 12).frame(height: 24)
        .background(target ? Color.accentColor.opacity(0.3) : selected ? Color.accentColor : (index % 2 == 1 ? Color.primary.opacity(0.03) : .clear))
        .background(GeometryReader { Color.clear.preference(key: ConnectedTileFramesKey.self, value: [entry.url.path: $0.frame(in: .global)]) })
        .modifier(EntryInteractions(entry: entry, open: open))
    }

    @ViewBuilder private func icon(_ entry: ConnectedEntry, size: CGFloat) -> some View {
        let _ = thumbs.version // redraw when a thumbnail arrives
        if entry.isFolder {
            // Its Finder color tag shows as the kind's dot (Green → Linker, Red → PhotoBook…).
            FolderIcon(style: .fromFinderTags(entry.tags), size: size)
        } else if size > 30, let image = thumbs.image(for: entry, size: size) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
        } else {
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.url.path)).resizable().aspectRatio(contentMode: .fit)
        }
    }

    // MARK: Moving around

    private func open(_ entry: ConnectedEntry) {
        if entry.isFolder {
            let name = entry.url.lastPathComponent
            go(to: location.subpath.isEmpty ? name : location.subpath + "/" + name)
        } else {
            Safety.open(entry.url) // in the app it belongs to (apps and scripts are asked about first)
        }
    }

    private func go(to subpath: String) {
        store.connectedView = ConnectedLocation(folderID: location.folderID, subpath: subpath)
    }

    private func goUp() {
        go(to: location.subpath.split(separator: "/").dropLast().joined(separator: "/"))
    }
}

struct ConnectedOriginKey: PreferenceKey {
    static let defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Click to select (⌘/⇧ for more), double-click to open, right-click for more. (Dragging is ConnectedDrag's.)
private struct EntryInteractions: ViewModifier {
    @ObservedObject private var selection = ConnectedSelection.shared
    let entry: ConnectedEntry
    let open: (ConnectedEntry) -> Void

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .onTapGesture {
                let event = NSApp.currentEvent
                if (event?.clickCount ?? 1) >= 2 { open(entry); return }
                selection.click(entry.url.path, flags: event?.modifierFlags ?? [])
            }
            .contextMenu {
                let chosen = selection.paths.contains(entry.url.path) ? selection.selectedURLs : [entry.url]
                Button(entry.isFolder ? "Open" : "Open in Its App") { open(entry) }
                if !entry.isFolder { Button("Quick Look") { QuickLook.shared.show([entry.url]) } }
                Button("Rename") { ConnectedEditor.shared.renamingPath = entry.url.path }
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([entry.url]) }
                Button("Copy Path") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(entry.url.path, forType: .string)
                }
                ConnectedFileMenu(urls: chosen, folders: selection.entries.filter(\.isFolder))
                Divider()
                Button("New Folder") { ConnectedEditor.shared.newFolder() }
                if entry.isFolder {
                    Button("Connect This Folder Too") {
                        if let f = ConnectedRegistry.shared.connect(entry.url) { ConnectedRegistry.shared.open(f.id) }
                    }
                }
                Divider()
                Button(chosen.count > 1 ? "Move \(chosen.count) to Trash" : "Move to Trash", role: .destructive) { ConnectedEditor.shared.trash(chosen) }
            }
            .help(entry.isFolder ? "\(entry.name) — double-click to open, drag things onto it to move them in" : "\(entry.name) — double-click to open, Space to look, drag to move")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(entry.isFolder ? "Folder" : "File"): \(entry.name)")
            .accessibilityAddTraits(selection.paths.contains(entry.url.path) ? [.isButton, .isSelected] : .isButton)
            .accessibilityAction(named: "Open") { open(entry) }
    }
}

extension ConnectedFolderView {
    /// Dragging out hands over the real file — the receiving app makes its own copy, the original stays put.
    static func provider(for url: URL) -> NSItemProvider {
        let provider = NSItemProvider()
        let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType ?? .data
        provider.registerFileRepresentation(forTypeIdentifier: type.identifier, fileOptions: [], visibility: .all) { done in
            done(url, false, nil) // not coordinated: the system copies it for whoever receives it
            return nil
        }
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
