import AppKit

// MARK: - Save a project to the Mac (kept up to date live)

/// Right-click a project tab → Save to Mac…: pick a place and Stash makes a real folder for the project there,
/// then keeps it in step with every change (new things, renames, moves, deletes).
/// It only ever touches what it put there itself: files you add to that folder yourself are left alone,
/// and anything it removes goes to the Trash.
extension Store {
    /// "p:<id>" / "p:none" → folder path. Kept with the library (.stash/exports/targets.json).
    var exportPaths: [String: String] {
        get { (try? JSONDecoder().decode([String: String].self, from: Data(contentsOf: exportTargetsURL))) ?? [:] }
        set {
            try? FileManager.default.createDirectory(at: exportTargetsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? JSONEncoder().encode(newValue).write(to: exportTargetsURL, options: .atomic)
            objectWillChange.send()
        }
    }

    private var exportTargetsURL: URL {
        dataDir.appendingPathComponent("exports", isDirectory: true).appendingPathComponent("targets.json")
    }

    static func exportKey(_ project: UUID?) -> String { "p:" + (project?.uuidString ?? "none") }

    func exportURL(for project: UUID?) -> URL? {
        exportPaths[Self.exportKey(project)].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// Asks where to keep it, makes "<there>/<Project name>", and copies everything in.
    func chooseExportLocation(for project: UUID?) {
        let name = project.flatMap { id in projects.first { $0.id == id }?.name } ?? "Not Selected"
        let panel = NSOpenPanel()
        panel.title = "Save “\(name)” to your Mac"
        panel.message = "Swiss makes a “\(name)” folder here and keeps it up to date as you change things."
        panel.prompt = "Save Here"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        NSApp.activate()
        guard panel.runModal() == .OK, let parent = panel.url else { return }
        var target = parent.appendingPathComponent(name.replacingOccurrences(of: "/", with: "-"), isDirectory: true)
        var n = 2
        while FileManager.default.fileExists(atPath: target.path) {
            target = parent.appendingPathComponent("\(name) \(n)", isDirectory: true)
            n += 1
        }
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        var paths = exportPaths
        paths[Self.exportKey(project)] = target.path
        exportPaths = paths
        exportSavedProjects()
        flash("Saved to \(parent.lastPathComponent) — it stays up to date")
    }

    func stopExport(for project: UUID?) {
        var paths = exportPaths
        paths[Self.exportKey(project)] = nil
        exportPaths = paths
        try? FileManager.default.removeItem(at: exportManifestURL(Self.exportKey(project)))
        flash("Stopped updating the saved copy (it stays where it is)")
    }

    func revealExport(for project: UUID?) {
        guard let url = exportURL(for: project) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    private func exportManifestURL(_ key: String) -> URL {
        dataDir.appendingPathComponent("exports", isDirectory: true)
            .appendingPathComponent(key.replacingOccurrences(of: ":", with: "-") + ".json")
    }

    /// Runs after every change (once the folder in Documents is up to date). The copying happens in the background.
    func exportSavedProjects() {
        let paths = exportPaths
        guard !paths.isEmpty else { return }
        var jobs: [(source: URL, target: URL, manifest: URL)] = []
        for (key, path) in paths {
            // A project that's gone: stop, but leave the saved copy alone.
            if key != "p:none", !projects.contains(where: { "p:" + $0.id.uuidString == key }) { continue }
            guard let source = mirrorDirs[key].map(absolute) else { continue }
            jobs.append((source, URL(fileURLWithPath: path, isDirectory: true), exportManifestURL(key)))
        }
        Self.exportQueue.async {
            for job in jobs { Self.sync(from: job.source, to: job.target, manifest: job.manifest) }
        }
    }

    private static let exportQueue = DispatchQueue(label: "stash.export", qos: .utility)

    /// One-way sync. The manifest lists what Stash put there last time, so it never deletes anything else.
    nonisolated private static func sync(from source: URL, to target: URL, manifest: URL) {
        let fm = FileManager.default
        try? fm.createDirectory(at: target, withIntermediateDirectories: true)
        let before = Set((try? JSONDecoder().decode([String].self, from: Data(contentsOf: manifest))) ?? [])

        var now: [String] = []
        let base = source.standardizedFileURL.path
        if let walker = fm.enumerator(at: source, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]) {
            for case let url as URL in walker {
                let rel = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
                guard !rel.isEmpty, !rel.hasPrefix(".") else { continue }
                now.append(rel)
                let dest = target.appendingPathComponent(rel)
                let values = try? url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey])
                if values?.isDirectory == true {
                    try? fm.createDirectory(at: dest, withIntermediateDirectories: true)
                    Store.unhide(dest)
                    continue
                }
                let old = try? dest.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
                if old?.fileSize == values?.fileSize, old?.contentModificationDate == values?.contentModificationDate { continue }
                try? fm.createDirectory(at: dest.deletingLastPathComponent(), withIntermediateDirectories: true)
                if fm.fileExists(atPath: dest.path) { try? fm.removeItem(at: dest) }
                try? fm.copyItem(at: url, to: dest) // keeps the dates and Finder tags
                var visible = URLResourceValues(); visible.isHidden = false
                var copied = dest; try? copied.setResourceValues(visible)
            }
        }

        // Gone from Stash: to the Trash (deepest first, folders only once they're empty of other things).
        for rel in before.subtracting(now).sorted(by: { $0.count > $1.count }) {
            let url = target.appendingPathComponent(rel)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue, let inside = try? fm.contentsOfDirectory(atPath: url.path), inside.contains(where: { !$0.hasPrefix(".") }) { continue }
            try? fm.trashItem(at: url, resultingItemURL: nil)
        }

        try? fm.createDirectory(at: manifest.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(now).write(to: manifest, options: .atomic)
    }
}
