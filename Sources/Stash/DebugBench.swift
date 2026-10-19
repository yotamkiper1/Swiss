import AppKit

// MARK: - Stash Test only: a 10,000-item library and timings on it

extension AppDelegate {
    /// A big test library like the performance guide's: one project, 200 folders (50 inside others),
    /// 10,000 notes and links — 1,000 loose on the board (a fifth of them moved by hand), the rest in folders.
    func makeHugeLibrary() {
        let store = Store.shared
        let p = store.addProject(named: "Huge"); store.renamingProjectID = nil
        var folders: [Folder] = []
        for i in 0..<150 { folders.append(Folder(name: "Folder \(i)", style: i % 5 == 0 ? .linker : .classic, projectID: p.id)) }
        for i in 0..<50 {
            var f = Folder(name: "Inner \(i)", style: .classic, projectID: p.id)
            f.parentID = folders[i].id
            folders.append(f)
        }
        let board = "p:" + p.id.uuidString
        let key = Store.windowKey(false)
        var items: [Item] = []
        items.reserveCapacity(10_000)
        let base = Date().addingTimeInterval(-86_400 * 60)
        for i in 0..<10_000 {
            let loose = i < 1_000
            var item = Item(kind: i % 4 == 0 ? .link : .text, projectID: p.id, folderID: loose ? nil : folders[i % 200].id)
            item.createdAt = base.addingTimeInterval(Double(i) * 500)
            if item.kind == .link {
                item.url = "https://example.com/page/\(i)"; item.title = "Example page \(i)"
            } else {
                item.text = "Note number \(i)\nSome words about the idea \(i)."
            }
            if i % 7 == 0 { item.tags = ["idea"] }
            if loose && i % 5 == 0 {
                // Moved by hand somewhere on the board.
                item.spots = [key: BoardSpot(x: Double((i * 37) % 600), y: Double((i * 53) % 4_000), board: board)]
            }
            items.append(item)
        }
        store.folders += folders
        store.items = items + store.items
        store.filter = .project(p.id)
        store.openFolderID = nil
        store.save()
        FileHandle.standardError.write("huge library: \(items.count) items, \(folders.count) folders\n".data(using: .utf8)!)
    }

    /// Seconds of CPU the main thread has used so far.
    static func mainThreadCPU() -> Double {
        var t = timespec()
        clock_gettime(CLOCK_THREAD_CPUTIME_ID, &t)
        return Double(t.tv_sec) + Double(t.tv_nsec) / 1e9
    }

    /// Times the things you do all the time, on whatever board the big window shows. Each step is repeated;
    /// the time is from the change until the window has drawn it (main-thread work, what you feel as lag).
    func runBench(label: String) {
        let store = Store.shared
        func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        guard case .project(let projectID) = store.filter else { log("bench: open a project first"); return }
        let rootItems = store.visibleItems.map(\.id)
        let folderIDs = store.visibleFolders.map(\.id)
        let other = store.projects.first { $0.id != projectID }?.id
        guard !rootItems.isEmpty, let folder = folderIDs.first else { log("bench: empty board"); return }

        var results: [(String, [Double], [Double], [Double])] = [] // name, total ms, layout ms, free-spot ms
        var steps: [(String, () -> Void)] = []
        for _ in 0..<3 { steps.append(("nothing (idle)", {})) }
        for i in 0..<3 { steps.append(("any change", { store.objectWillChange.send() })); _ = i }
        for i in 0..<3 { steps.append(("select a tile", { store.selection = [.item(rootItems[(i * 31) % rootItems.count])] })) }
        for _ in 0..<3 {
            steps.append(("open a folder", { store.openFolderID = folder }))
            steps.append(("back to the board", { store.openFolderID = nil }))
        }
        if let other {
            for _ in 0..<3 {
                steps.append(("switch tab away", { store.filter = .project(other) }))
                steps.append(("switch tab back", { store.filter = .project(projectID) }))
            }
        }
        for _ in 0..<1 {
            steps.append(("clear search", { store.search = "" }))
            for (n, _) in "idea 12".enumerated() {
                let typed = String("idea 12".prefix(n + 1))
                steps.append(("search keystroke", { store.search = typed }))
            }
        }
        steps.append(("clear search", { store.search = "" }))

        // Plain lookups, without drawing.
        let visible = store.visibleFolders
        var t = Perf.now
        for _ in 0..<10 { for f in visible { _ = store.count(in: f) + store.subfolderCount(in: f) } }
        log(String(format: "bench[%@] folder counts for %d folders: %.2f ms", label, visible.count, Double(Perf.now - t) / 10_000_000))
        t = Perf.now
        for _ in 0..<10 { _ = store.visibleItems; _ = store.visibleFolders }
        log(String(format: "bench[%@] board lists (items + folders): %.2f ms", label, Double(Perf.now - t) / 10_000_000))

        let window: NSWindow = panel
        var index = 0
        func next() {
            guard index < steps.count else {
                for (name, totals, layouts, frees) in results {
                    let s = totals.sorted(), l = layouts.sorted(), f = frees.sorted()
                    log(String(format: "bench[%@] %-18@ main-thread work median %7.1f ms  slowest %7.1f ms  (layout %6.1f, free-spot %6.1f)  n=%d",
                               label, name as NSString, s[s.count / 2], s.last!, l[l.count / 2], f[f.count / 2], s.count))
                }
                log("bench[\(label)] done")
                return
            }
            let (name, action) = steps[index]
            index += 1
            Perf.layoutNanos = 0; Perf.freeSpotNanos = 0
            let cpuStart = Self.mainThreadCPU()
            action()
            _ = window
            // Let the window update by itself, then count how much of the main thread's time it took
            // (CPU time, so waiting for the screen doesn't count — this is what makes the app feel stuck).
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated {
                        let ms = (Self.mainThreadCPU() - cpuStart) * 1000
                        let entry = (ms, Double(Perf.layoutNanos) / 1_000_000, Double(Perf.freeSpotNanos) / 1_000_000)
                        if let i = results.firstIndex(where: { $0.0 == name }) {
                            results[i].1.append(entry.0); results[i].2.append(entry.1); results[i].3.append(entry.2)
                        } else {
                            results.append((name, [entry.0], [entry.1], [entry.2]))
                        }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { MainActor.assumeIsolated { next() } }
                    }
                }
            }
        }
        next()
    }
}
