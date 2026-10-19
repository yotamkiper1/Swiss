import AppKit
import SwiftUI

/// ⌘Z / ⌘⇧Z for everything you do in Stash. Each action saves a snapshot of the library first.
struct UndoStep {
    var name: String
    var projects: [Project]
    var folders: [Folder]
    var pages: [NotebookPage]
    var items: [Item]
}

extension Store {
    private static let maxUndoSteps = 60

    var trashDir: URL { dataDir.appendingPathComponent("trash", isDirectory: true) }

    /// Call at the start of anything you'd want to undo. Nested calls count as one step.
    func checkpoint(_ name: String) {
        guard undoGroupDepth == 0 else { return }
        undoStack.append(UndoStep(name: name, projects: projects, folders: folders, pages: pages, items: items))
        if undoStack.count > Self.maxUndoSteps { undoStack.removeFirst() }
        redoStack.removeAll()
    }

    /// Runs several changes as a single undo step.
    func undoGroup(_ name: String, _ body: () -> Void) {
        checkpoint(name)
        undoGroupDepth += 1
        defer { undoGroupDepth -= 1 }
        body()
    }

    func undo() {
        if connectedView != nil, !showingRecent { ConnectedEditor.shared.undo(); return } // the real folder's last change
        guard let step = undoStack.popLast() else {
            flash("Nothing to undo")
            return
        }
        redoStack.append(UndoStep(name: step.name, projects: projects, folders: folders, pages: pages, items: items))
        restore(step)
        flash("Undid \(step.name)")
    }

    func redo() {
        guard let step = redoStack.popLast() else {
            flash("Nothing to redo")
            return
        }
        undoStack.append(UndoStep(name: step.name, projects: projects, folders: folders, pages: pages, items: items))
        restore(step)
        flash("Redid \(step.name)")
    }

    private func restore(_ step: UndoStep) {
        // Keep what finished loading in the background since (link titles, previews, text in images).
        let current = Dictionary(items.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let restored = step.items.map { old -> Item in
            guard let now = current[old.id] else { return old }
            var item = old
            if item.title == nil { item.title = now.title }
            if item.imageFile == nil, item.kind != .image { item.imageFile = now.imageFile }
            // The file is where it is now; the mirror moves it back to where this step had it.
            item.storedPath = now.storedPath ?? item.storedPath
            if item.ocrText == nil { item.ocrText = now.ocrText }
            return item
        }
        // Bring back image files that were deleted (they wait in the trash until Stash restarts).
        // (Pictures and files come back through the mirror; link and file previews come back here.)
        for item in restored where item.kind != .image {
            guard let file = item.imageFile else { continue }
            let image = fileURL(for: file), trashed = trashDir.appendingPathComponent(file)
            if !FileManager.default.fileExists(atPath: image.path), FileManager.default.fileExists(atPath: trashed.path) {
                try? FileManager.default.moveItem(at: trashed, to: image)
            }
        }
        // Anything this undo/redo removes stays recoverable in Recently Deleted.
        let keptItems = Set(restored.map(\.id)), keptFolders = Set(step.folders.map(\.id)), keptProjects = Set(step.projects.map(\.id))
        recordDeletion(projects: projects.filter { !keptProjects.contains($0.id) },
                       folders: folders.filter { !keptFolders.contains($0.id) },
                       items: items.filter { !keptItems.contains($0.id) })
        withAnimation(.spring(duration: 0.3)) {
            projects = step.projects
            folders = step.folders
            pages = step.pages
            items = restored
            selection = []
            pendingDelete = nil
            clipboardHint = nil
            if let open = openFolderID, folder(open) == nil { openFolderID = nil }
            if case .project(let id) = filter, !projects.contains(where: { $0.id == id }) { filter = .inbox } // save() picks a project
        }
        pruneRecentlyDeleted()
        save()
    }

    /// Deleted images go to the library's trash so undo can bring them back.
    func trashImage(_ file: String) {
        try? FileManager.default.createDirectory(at: trashDir, withIntermediateDirectories: true)
        let destination = trashDir.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: destination)
        try? FileManager.default.moveItem(at: fileURL(for: file), to: destination)
    }

    /// At launch: clear what's been in Recently Deleted for over 30 days, and remove image files nothing uses
    /// (left over from things that were undone). Undo history doesn't survive a restart; Recently Deleted does.
    func cleanUpFiles() {
        cleanUpTrash() // only what's older than 30 days (Recently Deleted keeps the rest)
        cleanUpStoredCopies()
        let used = Set((items + recentlyDeleted.flatMap(\.items)).compactMap(\.imageFile))
        guard !items.isEmpty || used.isEmpty else { return }
        guard let files = try? FileManager.default.contentsOfDirectory(atPath: imagesDir.path) else { return }
        for file in files where !used.contains(file) {
            try? FileManager.default.removeItem(at: fileURL(for: file))
        }
    }
}
