import AppKit
import SwiftUI

/// Something you deleted: what it was (so it can come back exactly) and when.
struct DeletedRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var date = Date()
    var title: String
    /// Where it was, for the list ("Mammoth ▸ PhotoBook").
    var origin: String
    var projects: [Project] = []
    var folders: [Folder] = []
    var items: [Item] = []
}

/// Recently Deleted: deleted things stay recoverable for 30 days — across restarts — instead of vanishing when
/// Stash restarts. Their files wait in .stash/trash/<item id>; the list lives in .stash/trash/deleted.json.
/// Restore puts them back where they were (or on the board, if their folder or project is gone).
extension Store {
    static let keepDeletedDays = 30

    private var deletedListURL: URL { trashDir.appendingPathComponent("deleted.json") }

    func loadDeleted() {
        recentlyDeleted = (try? JSONDecoder.iso.decode([DeletedRecord].self, from: Data(contentsOf: deletedListURL))) ?? []
    }

    private func saveDeleted() {
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        try? JSONEncoder.iso.encode(recentlyDeleted).write(to: deletedListURL, options: .atomic)
    }

    /// Call just before things are removed from the library.
    func recordDeletion(projects: [Project] = [], folders: [Folder], items: [Item]) {
        guard !(projects.isEmpty && folders.isEmpty && items.isEmpty) else { return }
        var parts: [String] = []
        if let p = projects.first { parts.append(projects.count == 1 ? p.name : "\(projects.count) projects") }
        if !folders.isEmpty { parts.append(folders.count == 1 && projects.isEmpty ? folders[0].name : plural(folders.count, "folder")) }
        let looseItems = items.filter { item in !folders.contains { $0.id == item.folderID } }
        if folders.isEmpty && projects.isEmpty, items.count == 1 {
            parts.append(items[0].displayTitle.isEmpty ? "1 item" : items[0].displayTitle)
        } else if !items.isEmpty {
            parts.append(plural(items.count, "item"))
        }
        let anchor = folders.first.map { ($0.projectID, $0.parentID) } ?? looseItems.first.map { ($0.projectID, $0.folderID) }
            ?? items.first.map { ($0.projectID, $0.folderID) } ?? (nil, nil)
        var origin = anchor.0.flatMap { id in self.projects.first { $0.id == id }?.name } ?? "Not Selected"
        if let folderID = anchor.1 {
            origin += (ancestors(of: folderID) + [folder(folderID)].compactMap { $0 }).map { " ▸ " + $0.name }.joined()
        }
        if !projects.isEmpty { origin = "Projects" }
        recentlyDeleted.insert(DeletedRecord(title: parts.joined(separator: " and "), origin: origin,
                                             projects: projects, folders: folders, items: items), at: 0)
        saveDeleted()
    }

    /// After undo/redo: anything back in the library leaves the list.
    func pruneRecentlyDeleted() {
        let itemIDs = Set(items.map(\.id)), folderIDs = Set(folders.map(\.id)), projectIDs = Set(projects.map(\.id))
        var changed = false
        recentlyDeleted = recentlyDeleted.compactMap { record in
            var r = record
            r.items.removeAll { itemIDs.contains($0.id) }
            r.folders.removeAll { folderIDs.contains($0.id) }
            r.projects.removeAll { projectIDs.contains($0.id) }
            if r != record { changed = true }
            return r.items.isEmpty && r.folders.isEmpty && r.projects.isEmpty ? nil : r
        }
        if changed { saveDeleted() }
    }

    /// Puts a deleted group back. Folders/projects that no longer exist fall back to the board.
    func restoreDeleted(_ id: UUID) {
        guard let record = recentlyDeleted.first(where: { $0.id == id }) else { return }
        checkpoint("Restore")
        let fm = FileManager.default
        for project in record.projects where !projects.contains(where: { $0.id == project.id }) { projects.append(project) }
        let projectIDs = Set(projects.map(\.id))
        let folderIDs = Set(folders.map(\.id)).union(record.folders.map(\.id))
        for var folder in record.folders where !folders.contains(where: { $0.id == folder.id }) {
            if let p = folder.projectID, !projectIDs.contains(p) { folder.projectID = nil }
            if let parent = folder.parentID, !folderIDs.contains(parent) { folder.parentID = nil }
            folders.append(folder)
        }
        for var item in record.items where !items.contains(where: { $0.id == item.id }) {
            if let p = item.projectID, !projectIDs.contains(p) { item.projectID = nil }
            if let f = item.folderID, !folderIDs.contains(f) { item.folderID = nil }
            // Link and file previews wait in the trash too; pictures come back through the mirror.
            if item.kind != .image, let file = item.imageFile {
                let trashed = trashDir.appendingPathComponent(file), preview = fileURL(for: file)
                if !fm.fileExists(atPath: preview.path), fm.fileExists(atPath: trashed.path) { try? fm.moveItem(at: trashed, to: preview) }
            }
            items.insert(item, at: 0)
        }
        recentlyDeleted.removeAll { $0.id == id }
        saveDeleted()
        save() // the mirror brings each file back from .stash/trash/<item id>
        flash("Restored \(record.title)", undo: true)
    }

    /// Gone for good: its files are removed now.
    func deleteForever(_ id: UUID) {
        guard let record = recentlyDeleted.first(where: { $0.id == id }) else { return }
        removeTrashedFiles(of: record)
        recentlyDeleted.removeAll { $0.id == id }
        saveDeleted()
    }

    func emptyRecentlyDeleted() {
        recentlyDeleted.forEach(removeTrashedFiles)
        recentlyDeleted = []
        saveDeleted()
    }

    private func removeTrashedFiles(of record: DeletedRecord) {
        let fm = FileManager.default
        for item in record.items {
            try? fm.removeItem(at: trashDir.appendingPathComponent(item.id.uuidString, isDirectory: true))
            if let file = item.imageFile {
                try? fm.removeItem(at: trashDir.appendingPathComponent(file))
                if !items.contains(where: { $0.imageFile == file }) { try? fm.removeItem(at: fileURL(for: file)) }
            }
            if let url = item.linkURL, url.path.hasPrefix(filesDir.path) { try? fm.removeItem(at: url.deletingLastPathComponent()) }
        }
    }

    /// At launch: drop what's older than 30 days, and stray trash files nothing points to (only once they're
    /// older than 30 days too, so nothing recent can be lost).
    func cleanUpTrash() {
        let fm = FileManager.default
        let cutoff = Date().addingTimeInterval(-Double(Self.keepDeletedDays) * 86_400)
        let (old, keep) = (recentlyDeleted.filter { $0.date < cutoff }, recentlyDeleted.filter { $0.date >= cutoff })
        old.forEach(removeTrashedFiles)
        if !old.isEmpty { recentlyDeleted = keep; saveDeleted() }
        let referenced = Set(keep.flatMap { $0.items.flatMap { [$0.id.uuidString, $0.imageFile].compactMap { $0 } } })
            .union(["deleted.json"])
        for name in (try? fm.contentsOfDirectory(atPath: trashDir.path)) ?? [] where !referenced.contains(name) {
            let url = trashDir.appendingPathComponent(name)
            let date = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            if date < cutoff { try? fm.removeItem(at: url) }
        }
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}

extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

// MARK: - The list

/// Recently Deleted: everything deleted in the last 30 days, with Restore and Delete Forever.
struct RecentlyDeletedSheet: View {
    @EnvironmentObject var store: Store

    var body: some View {
        ZStack {
            Color.black.opacity(0.18).ignoresSafeArea().onTapGesture { store.showingRecentlyDeleted = false }
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: "trash").foregroundStyle(.secondary)
                    Text("Recently Deleted").font(.system(size: 13, weight: .semibold))
                    Spacer()
                    if !store.recentlyDeleted.isEmpty {
                        Button("Empty") { store.emptyRecentlyDeleted() }
                            .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.red)
                            .help("Delete everything here for good")
                    }
                    Button { store.showingRecentlyDeleted = false } label: {
                        Image(systemName: "xmark").font(.system(size: 11, weight: .semibold)).frame(width: 22, height: 22)
                    }
                    .buttonStyle(QuietButtonStyle()).foregroundStyle(.secondary).keyboardShortcut(.cancelAction)
                }
                if store.recentlyDeleted.isEmpty {
                    Text("Nothing deleted in the last \(Store.keepDeletedDays) days.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).padding(.vertical, 14)
                } else {
                    ScrollView {
                        VStack(spacing: 2) { ForEach(store.recentlyDeleted) { DeletedRow(record: $0) } }
                    }
                    .frame(maxHeight: 280)
                }
                Text("Deleted things stay here for \(Store.keepDeletedDays) days, even after Swiss restarts.")
                    .font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            .padding(12)
            .frame(width: 300)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            )
        }
    }
}

private struct DeletedRow: View {
    @EnvironmentObject var store: Store
    let record: DeletedRecord
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: record.projects.isEmpty ? (record.folders.isEmpty ? "doc" : "folder") : "square.stack")
                .font(.system(size: 12)).foregroundStyle(.secondary).frame(width: 18)
            VStack(alignment: .leading, spacing: 1) {
                Text(record.title).font(.system(size: 11.5)).lineLimit(1).truncationMode(.middle)
                Text("\(record.date.formatted(.relative(presentation: .named))) · from \(record.origin)")
                    .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Button("Restore") { store.restoreDeleted(record.id) }
                .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
            Button { store.deleteForever(record.id) } label: {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain).foregroundStyle(.secondary).opacity(hovering ? 1 : 0)
            .help("Delete for good")
        }
        .padding(.horizontal, 6).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(hovering ? 0.06 : 0)))
        .onHover { hovering = $0 }
    }
}
