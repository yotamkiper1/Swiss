import AppKit
import Quartz
import Carbon.HIToolbox

#if SWISS_TEST // Swiss Test only (./build.sh test): not in the real app at all

/// Test hooks (stashtest://debug…). They only run inside "Stash Test" (see TestMode); the real Stash ignores them.
extension AppDelegate {
    func handleDebug(_ url: URL, compact: NSWindow, panel: NSWindow) {
        guard TestMode.isOn else { return }
        let store = Store.shared
        func log(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }
        switch url.host {
        case "debugshot":
            let view = (floating?.isVisible == true ? floating! : compact.isVisible ? compact : panel).contentView!
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
            }
        case "debugexpand": expand()
        case "debugcollapse": collapse()
        case "debugdefaults": UserDefaults.standard.set("from-test", forKey: "test.marker")
        case "debugstate":
            log("state projects=\(store.projects.count) folders=\(store.folders.count) items=\(store.items.count) deleted=\(store.recentlyDeleted.count)")
        case "debugseed":
            let p = store.addProject(named: "Seed"); store.renamingProjectID = nil
            store.newFolder(style: .photos); store.renamingFolderID = nil
            if let f = store.folders.last {
                for i in 0..<3 { store.addText("Note \(i) in folder", place: Place(project: p.id, folder: f.id)) }
            }
            store.addText("Loose note", place: Place(project: p.id))
            store.addText("https://example.com/page", place: Place(project: p.id))
        case "debugdeletefolder":
            if let f = store.folders.last { store.requestDelete([.folder(f.id)]) }
        case "debugdeleteitem":
            if let i = store.items.first(where: { $0.folderID == nil }) { store.requestDelete([.item(i.id)]) }
        case "debugrestoreall":
            for record in store.recentlyDeleted { store.restoreDeleted(record.id) }
        case "debugundo": store.undo()
        case "debughammer":
            // Lots of quick saves (for crash tests).
            for i in 0..<400 {
                if let index = store.items.indices.first { store.items[index].title = "Hammer \(i)"; store.save() }
            }
            log("hammer done")
        case "debugbig":
            // A big test library: one project, 20 folders, 2,000 notes and links.
            let p = store.addProject(named: "Big"); store.renamingProjectID = nil
            var newFolders: [Folder] = []
            for i in 0..<20 { newFolders.append(Folder(name: "Folder \(i)", style: i % 4 == 0 ? .linker : .classic, projectID: p.id)) }
            store.folders += newFolders
            var newItems: [Item] = []
            for i in 0..<2000 {
                let inFolder = i % 3 != 0 ? newFolders[i % 20].id : nil
                if i % 4 == 0 {
                    var item = Item(kind: .link, projectID: p.id, folderID: inFolder)
                    item.url = "https://example.com/page/\(i)"; item.title = "Example page \(i)"
                    newItems.append(item)
                } else {
                    var item = Item(kind: .text, projectID: p.id, folderID: inFolder)
                    item.text = "Note number \(i)\nSome words about the idea \(i)."
                    newItems.append(item)
                }
            }
            store.items = newItems + store.items
            store.filter = .project(p.id)
            store.save()
        case "debugrename":
            if let i = store.items.firstIndex(where: { $0.kind == .text }) {
                Perf.measure("rename one note (save call)") {
                    store.items[i].text = "Renamed \(Int.random(in: 0...9999))\nbody"
                    store.save()
                }
            }
        case "debugperform":
            if let action = QuickAction(rawValue: Int(url.query ?? "1") ?? 1) { store.perform(action) }
            log("perform: composing=\(store.composingNote) recent=\(store.showingRecent) library=\(String(describing: store.libraryView))")
        case "debugcanvaslib":
            // Adds the first ?n things of Seed to the canvas, the way the library's double-click does.
            let pb = NSPasteboard(name: NSPasteboard.Name("swiss.canvas.library.test"))
            pb.clearContents()
            let seed = store.projects.first { $0.name == "Seed" }?.id
            pb.writeObjects(store.items.filter { $0.projectID == seed }.prefix(Int(url.query ?? "3") ?? 3).compactMap { store.pasteboardItem(for: $0) })
            log("canvaslib ingest=\(CanvasStore.shared.ingest(pb)) items=\(CanvasStore.shared.items.map(\.kind.rawValue))")
        case "debugcopysel": store.copySelection()
        case "debugpaste":
            if SwissClipboard.isCurrent { store.pasteCopies(into: store.currentPlace) } else { log("paste: clipboard isn't Swiss's") }
            let here = store.currentPlace
            let fs = store.folders.filter { $0.projectID == here.project && $0.parentID == here.folder }.map { f in "\(f.name)(\(store.items.filter { $0.folderID == f.id }.count))" }
            let its = store.items.filter { $0.projectID == here.project && $0.folderID == here.folder }.map(\.displayTitle)
            log("paste here: folders=\(fs) items=\(its.prefix(12))")
        case "debugcompanion":
            // ?open, ?expand, ?full, ?collapse, ?close, ?closecanvas — then which windows are showing.
            switch url.query ?? "open" {
            case "open": openCompanion()
            case "expand": expand()
            case "full": setFullScreen(true)
            case "collapse": collapse()
            case "close": if panel.isVisible { hidePanel() } else { closeCompact() }
            case "closecanvas": hideFloating()
            default: break
            }
            log("companion=\(companion) canvas=\(floating.isVisible) popup=\(compact.isVisible) window=\(panel.isVisible) mode=\(WindowMode.current)")
        case "debugtabs":
            // ?close=Name closes its tab, ?delete=Name deletes the project (Delete Everything), then lists what shows.
            for q in URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? [] {
                guard let p = store.projects.first(where: { $0.name == q.value }) else { continue }
                if q.name == "close" { store.closeTab(p.id) }
                if q.name == "delete" { store.deleteProject(p.id, keepContents: false) }
                if q.name == "open" { store.showingRecent = false; store.filter = .project(p.id) }
            }
            log("tabs: open=\(store.projects.filter { $0.tabClosed != true }.map(\.name)) all=\(store.projects.map(\.name)) recent=\(store.showingRecent) filter=\(store.name(for: { if case .project(let id) = store.filter { id } else { nil } }()))")
        case "debugtour":
            // Shows the tour on page ?n and saves a picture of it to the path.
            WelcomeTour.show()
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { MainActor.assumeIsolated {
                guard let w = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible && $0.frame.width == 540 }),
                      let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { log("tour: no window"); return }
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
                log("tour shot")
            } }
        case "debugsize":
            // The big window at ?w,h points, centered on the screen.
            let d = (url.query ?? "1100,720").split(separator: ",").compactMap { Double($0) }
            if d.count == 2, let screen = NSScreen.main?.visibleFrame {
                panel.setFrame(NSRect(x: screen.midX - d[0] / 2, y: screen.midY - d[1] / 2, width: d[0], height: d[1]), display: true)
            }
        case "debugrecentclear": RecentStore.shared.clear()
        case "debugorganize": store.autoOrganize(reuseExisting: true)
        case "debugmess":
            // A project with everything loose on the board (for the wand): the files in the path, links and notes.
            let dir = URL(fileURLWithPath: url.path)
            let project = store.addProject(named: "Brand Refresh"); store.renamingProjectID = nil
            store.filter = .project(project.id)
            let place = Place(project: project.id)
            let pb = NSPasteboard(name: .init("swiss.mess"))
            for name in ["Poster draft — orange.jpg", "Poster draft — blue.jpg", "Color study.jpg", "Green mood.jpg", "Intro sting.aiff"] {
                pb.clearContents(); pb.writeObjects([dir.appendingPathComponent(name) as NSURL]); _ = store.ingest(pb, into: place)
            }
            for link in ["https://www.are.na", "https://en.wikipedia.org/wiki/Swiss_Style_(design)", "https://www.apple.com/design/"] { store.addText(link, place: place) }
            for note in ["Typeface shortlist: Helvetica Now, Söhne, GT America", "Print run: 50 copies, A2, matte 170 g", "Send files to the print shop Thursday"] { store.addText(note, place: place) }
            store.selection = []
        case "debugopenproject":
            // Opens the named project the way the list / tabs do, then reports where we are.
            if let p = store.projects.first(where: { $0.name == url.query?.removingPercentEncoding }) { store.openProject(p.id) }
            log("openproject: recent=\(store.showingRecent) tabClosed=\(store.projects.filter { $0.tabClosed == true }.map(\.name)) filter=\(store.name(for: { if case .project(let id) = store.filter { id } else { nil } }()))")
        case "debugshare":
            // ?file|link|text|image|recent: what would be shared, and which share services this Mac offers for it.
            let kind = url.query ?? "file"
            var shareable = Shareable()
            if kind == "recent" {
                shareable = Sharing.shareable(recent: Array(RecentStore.shared.items.prefix(3)))
            } else {
                let k: ItemKind = ["link": .link, "text": .text, "image": .image][kind] ?? .file
                if let it = store.items.first(where: { $0.kind == k }) { shareable = Sharing.shareable(items: [it]) }
            }
            let names = NSSharingService.sharingServices(forItems: shareable.objects).map(\.title)
            let what = shareable.objects.map { o -> String in (o as? NSURL).map { $0.lastPathComponent ?? "url" } ?? (o is NSString ? "text" : "other") }
            log("share \(kind): \(what) textFile=\(shareable.textFile?.lastPathComponent ?? "-") services=\(names)")
        case "debugshareshow":
            // Opens the real share sheet for the first thing of that kind (to look at it).
            let k: ItemKind = ["link": .link, "text": .text, "image": .image][url.query ?? "file"] ?? .file
            if let it = store.items.first(where: { $0.kind == k }) { Sharing.share(item: it) }
        case "debugclipprepare": store.prepareForClipboard(); log("clip hint=\(store.clipboardHint != nil)")
        case "debugcliphint": log("clip hint=\(store.clipboardHint != nil) project=\(store.name(for: { if case .project(let id) = store.filter { id } else { nil } }()))")
        case "debugrenamesel":
            // Starts renaming the one selected thing (like pressing Return).
            switch store.selection.first {
            case .folder(let id)?: store.renamingFolderID = id
            case .item(let id)?: store.renamingItemID = id
            case nil: break
            }
        case "debugtag":
            if let i = store.items.indices.first { store.items[i].colorTags = [.red]; store.save() }
        case "debugdragtimer":
            // A real-time drag of 10 tiles: one step per frame (60 Hz). Gaps longer than ~17 ms mean dropped frames.
            let w = compact.isVisible ? compact : panel
            let ids = Set(store.visibleItems.prefix(10).map { Selectable.item($0.id) })
            Perf.cardBodies = 0
            BoardDrag.shared.testBegin(ids, in: w)
            var step = 0, last = DispatchTime.now().uptimeNanoseconds
            var gaps: [Double] = []
            let steps = url.query.flatMap(Int.init) ?? 60
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
                MainActor.assumeIsolated {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if step > 0 { gaps.append(Double(now - last) / 1_000_000) }
                    last = now
                    step += 1
                    BoardDrag.shared.testMove(dx: CGFloat(step % 200), dy: -CGFloat(step % 100))
                    if step > steps {
                        timer.invalidate()
                        BoardDrag.shared.testEnd()
                        let sorted = gaps.sorted()
                        log(String(format: "realtime drag: median frame gap %.1f ms, slowest %.1f ms, frames over 20 ms: %d of %d", sorted[sorted.count / 2], sorted.last!, gaps.filter { $0 > 20 }.count, gaps.count))
                        log("card bodies during drag: \(Perf.cardBodies)")
                    }
                }
            }
        case "debugidletimer":
            var step = 0, last = DispatchTime.now().uptimeNanoseconds
            var gaps: [Double] = []
            Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
                MainActor.assumeIsolated {
                    let now = DispatchTime.now().uptimeNanoseconds
                    if step > 0 { gaps.append(Double(now - last) / 1_000_000) }
                    last = now; step += 1
                    if step > 60 {
                        timer.invalidate()
                        let sorted = gaps.sorted()
                        log(String(format: "empty timer: median gap %.1f ms", sorted[sorted.count / 2]))
                    }
                }
            }
        case "debugsettingsshot":
            showSettings()
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                if let w = NSApp.windows.first(where: { $0.title == "Swiss Settings" }), let view = w.contentView,
                   let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                    view.cacheDisplay(in: view.bounds, to: rep)
                    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
                }
            }
        case "debugpreviewitem":
            // A link with a big old-style PNG preview, to test shrinking.
            var item = Item(kind: .link, projectID: nil, folderID: nil)
            item.url = "https://example.com/big-preview"; item.title = "Big preview"
            item.imageFile = url.path.split(separator: "/").last.map(String.init)
            store.items.insert(item, at: 0); store.save()
        case "debugfail":
            // A download that fails on purpose (a link nothing can download).
            var item = Item(kind: .link, projectID: store.currentPlace.project, folderID: store.currentPlace.folder)
            item.url = "https://www.youtube.com/watch?v=invalid000000"; item.title = "Broken video"
            store.items.insert(item, at: 0); store.save()
            store.download(item.id, as: .mp3)
        case "debugfailstate":
            log("failures=\(store.jobFailures.values.map { "\($0.target.rawValue): \($0.reason)" }) converting=\(store.converting.count) toast=\(store.toast ?? "-") undo=\(store.toastUndo)")
        case "debugcancel":
            var item = Item(kind: .link, projectID: store.currentPlace.project, folderID: store.currentPlace.folder)
            item.url = "https://www.youtube.com/watch?v=dQw4w9WgXcQ"; item.title = "Cancel me"
            store.items.insert(item, at: 0); store.save()
            store.download(item.id, as: .mp4)
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { store.cancelJob(item.id) }
        case "debugdemo":
            // A realistic demo library for screenshots (from the files in the given folder).
            let dir = URL(fileURLWithPath: url.path)
            func file(_ name: String) -> URL { dir.appendingPathComponent(name) }
            func ingest(_ names: [String], _ place: Place) {
                let pb = NSPasteboard(name: .init("stash.demo"))
                pb.clearContents()
                pb.writeObjects(names.map { file($0) as NSURL })
                _ = store.ingest(pb, into: place)
            }
            let poster = store.addProject(named: "Poster Series"); store.renamingProjectID = nil
            let video = store.addProject(named: "Music Video"); store.renamingProjectID = nil
            let thesis = store.addProject(named: "Thesis"); store.renamingProjectID = nil
            store.togglePin(poster.id)
            store.filter = .project(poster.id)
            store.newFolder(style: .photos); store.renamingFolderID = nil
            let photos = store.folders.last!.id
            store.newFolder(style: .linker); store.renamingFolderID = nil
            let links = store.folders.last!.id
            store.newFolder(style: .noteHanger); store.renamingFolderID = nil
            let notes = store.folders.last!.id
            store.newFolder(style: .files); store.renamingFolderID = nil
            let files = store.folders.last!.id
            store.newFolder(style: .classic); store.renamingFolderID = nil
            if let i = store.folders.indices.last { store.folders[i].name = "Print shop"; store.folders[i].colorTags = [.orange] }
            store.newFolder(style: .classic); store.renamingFolderID = nil
            if let i = store.folders.indices.last { store.folders[i].name = "Archive" }
            ingest(["Poster draft — orange.jpg", "Poster draft — blue.jpg", "Color study.jpg", "Green mood.jpg"], Place(project: poster.id, folder: photos))
            ingest(["Intro sting.aiff", "Bass hit.aiff"], Place(project: poster.id, folder: files))
            for link in ["https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://www.apple.com/macos/", "https://www.are.na", "https://en.wikipedia.org/wiki/Swiss_Style_(design)"] {
                store.addText(link, place: Place(project: poster.id, folder: links))
            }
            for note in ["Print run: 50 copies, A2, matte 170 g. Ask about the blue spot colour.",
                         "Typeface shortlist — Helvetica Now, Söhne, GT America",
                         "Deadline: send files to the print shop Thursday"] {
                store.addText(note, place: Place(project: poster.id, folder: notes))
            }
            store.addText("“Design is not just what it looks like and feels like. Design is how it works.” — Steve Jobs", place: Place(project: poster.id))
            store.addText("Ideas for the opening: start on the blue poster, slow push in, cut on the bass hit.", place: Place(project: poster.id))
            store.addText("https://www.youtube.com/watch?v=dQw4w9WgXcQ", place: Place(project: poster.id))
            ingest(["Sonoma reference.jpg"], Place(project: poster.id))
            store.addText("Shot list: 1 wide, 2 close, 3 hands on the poster", place: Place(project: video.id))
            store.addText("Chapter 2 — the history of the grid", place: Place(project: thesis.id))
            store.selection = []
        case "debugopenfolder":
            let name = url.path.replacingOccurrences(of: "/", with: "")
            store.openFolderID = store.visibleFolders.first { $0.name == name }?.id
        case "debugup": store.openFolderID = nil
        case "debuglayout": UserDefaults.standard.set(url.path == "/list" ? BoardLayout.list.rawValue : BoardLayout.icons.rawValue, forKey: BoardLayout.key)
        case "debugappearance": NSApp.appearance = NSAppearance(named: url.path == "/dark" ? .darkAqua : .aqua)
        case "debugarrange": store.arrange(by: BoardSort(rawValue: url.path.replacingOccurrences(of: "/", with: "")) ?? .manual)
        case "debugselectname":
            let name = url.query?.removingPercentEncoding ?? ""
            if let f = store.visibleFolders.first(where: { $0.name == name }) { store.selection = [.folder(f.id)] }
            else if let i = store.visibleItems.first(where: { $0.displayTitle.hasPrefix(name) }) { store.selection = [.item(i.id)] }
        case "debugcopy":
            let pb = NSPasteboard.general
            pb.clearContents(); pb.setString(url.query?.removingPercentEncoding ?? "", forType: .string)
        case "debugdiag": log("diagnostics=\(Feedback.writeDiagnostics()?.path ?? "-")")
        case "debuglockstate": log("lock enabled=\(AppLock.enabled) unlocked=\(AppLock.isUnlocked) windows=\(NSApp.windows.filter { $0.isVisible && !$0.className.contains("StatusBar") }.map { "\($0.className):\($0.title)" })")
        case "debuglocknow": AppLock.lock()
        case "debugfeedback": Feedback.sendFeedback()
        case "debugmorph": // stashtest://debugmorph/expand (or collapse, float, fill, unfill): what's on screen during and after
            switch url.path {
            case "/collapse": collapse()
            case "/float": float()
            case "/fill": setFullScreen(true)
            case "/unfill": setFullScreen(false)
            default: expand()
            }
            func windows(_ when: String) {
                let list = NSApp.windows.filter { $0.isVisible && !$0.className.contains("StatusBar") }
                    .map { "\($0 is StashPanel ? ($0 as! StashPanel).gateKey : "overlay") a=\(String(format: "%.2f", $0.alphaValue)) w=\(Int($0.frame.width))" }
                log("morph \(url.path) \(when): \(list.joined(separator: ", "))")
            }
            windows("start")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) { windows("mid") }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { windows("end") }
        case "debugagerecent": // stashtest://debugagerecent?2 → the newest Recent entry was last seen 2 hours ago
            RecentStore.shared.age(hours: Double(url.query ?? "1") ?? 1)
            log("retention=\(UserDefaults.standard.integer(forKey: CaptureSettings.retentionKey)) recent=\(RecentStore.shared.items.count)")
        case "debugrecentselect": RecentStore.shared.selection = Set(RecentStore.shared.items.prefix(Int(url.query ?? "1") ?? 1).map(\.id))
        case "debugkeeptitle":
            log("keep sure=\(RecentStore.shared.sureKeepPlace.map { store.describe($0) } ?? "ask") projects=\(store.projects.count)")
        case "debugrecent": store.showingRecent = url.path != "/off"
        case "debugcapture":
            UserDefaults.standard.set(url.path.contains("clip"), forKey: CaptureSettings.clipboardKey)
            UserDefaults.standard.set(url.path.contains("shot"), forKey: CaptureSettings.screenshotsKey)
            UserDefaults.standard.set(url.path.contains("dl"), forKey: CaptureSettings.downloadsKey)
            if let folder = url.query?.removingPercentEncoding { UserDefaults.standard.set(folder, forKey: CaptureSettings.screenshotFolderKey) }
        case "debugrecentstate":
            let r = RecentStore.shared
            log("recent items=\(r.items.count) paused=\(r.paused) bytes=\(r.diskBytes) :: " + r.items.map { "\($0.kind.rawValue)|\($0.title.prefix(30))|x\($0.count)|\($0.sourceApp ?? "-")|kept=\($0.keptIn ?? "-")" }.joined(separator: " ;; "))
        case "debugkeepfirst":
            if let first = RecentStore.shared.items.first { RecentStore.shared.keep([first.id], in: Place()) }
        case "debugpause": RecentStore.shared.setPaused(url.path != "/off")
        case "debugretention":
            UserDefaults.standard.set(Int(url.query ?? "7") ?? 7, forKey: CaptureSettings.retentionKey); RecentStore.shared.prune()
        case "debugall": store.showingAllProjects = url.path != "/off"
        case "debugdeleted": store.showingRecentlyDeleted = url.path != "/off"
        case "debuginfo": showInfo(for: store.selection)
        case "debugghost":
            let w = compact.isVisible ? compact : panel
            if url.path == "/missedup" {
                // A real drag whose mouse-up never arrives: the picture must clear itself.
                BoardDrag.shared.testBegin(store.selection, in: w, asIfReal: true)
                log("ghost after begin: \(BoardDrag.shared.hasGhost)")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { MainActor.assumeIsolated {
                    log("ghost 0.8 s later (button not held): \(BoardDrag.shared.hasGhost), dimmed: \(DragSelection.shared.ids.count)")
                } }
            } else if url.path == "/off" { BoardDrag.shared.testEnd() } else {
                BoardDrag.shared.testBegin(store.selection, in: w)
                BoardDrag.shared.testMove(dx: 90, dy: -70)
            }
        case "debugwinshot":
            // Any visible window by kind: popover, info, settings.
            let kind = url.query ?? "popover"
            let match: (NSWindow) -> Bool = { w in
                switch kind {
                case "info": return w.title.hasSuffix(" Info")
                case "settings": return w.title == "Swiss Settings"
                default: return String(describing: type(of: w)).contains("Popover")
                }
            }
            if let w = NSApp.windows.last(where: { $0.isVisible && match($0) }) {
                if kind == "settings" { w.setContentSize(NSSize(width: 480, height: 1500)) }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                    if let view = w.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                        view.cacheDisplay(in: view.bounds, to: rep)
                        try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
                    }
                }
            }
        case "debugwindows":
            log("windows " + NSApp.windows.filter(\.isVisible).map { String(describing: type(of: $0)) + "(" + $0.title + ")" }.joined(separator: ", "))
        case "debuglibrary":
            switch url.path {
            case "/all": store.showingRecent = false; store.libraryView = .allItems
            case "/tag": store.showingRecent = false; store.libraryView = .tag(.orange)
            default: store.libraryView = nil
            }
        case "debugtagsome":
            for i in store.items.indices.prefix(3) { store.items[i].colorTags = [.orange] }
            if let i = store.items.indices.dropFirst(4).first { store.items[i].colorTags = [.blue] }
            store.save()
        case "debugshortcut":
            // Checks the recorder's rules without a keyboard: ?code=49&mods=256&which=open
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            let code = Int(q.first { $0.name == "code" }?.value ?? "") ?? 0, mods = Int(q.first { $0.name == "mods" }?.value ?? "") ?? 0
            let which = Shortcut(rawValue: q.first { $0.name == "which" }?.value ?? "open") ?? .open
            let combo = KeyCombo(keyCode: code, modifiers: mods)
            log("shortcut \(which.rawValue) \(combo.display): \(which.problem(with: combo) ?? "OK")")
        case "debuglock": setPinned(url.path != "/off")
        case "debugwritenote":
            // A note written in Swiss (not pasted): shows as the yellow note.
            var note = Item(kind: .text, projectID: store.currentPlace.project, folderID: store.currentPlace.folder)
            note.text = url.query?.removingPercentEncoding ?? "A note I wrote"
            store.add(note)
        case "debugsavetext": store.addText(url.query?.removingPercentEncoding ?? "Saved note", place: store.currentPlace)
        case "debugkeepimage":
            if let img = RecentStore.shared.items.first(where: { $0.kind == .image && $0.itemID == nil }) {
                RecentStore.shared.keep([img.id], in: store.currentPlace)
            }
        case "debuglibstate":
            let deletedURL = store.dataDir.appendingPathComponent("trash/deleted.json")
            var why = "ok"
            do { _ = try JSONDecoder.iso.decode([DeletedRecord].self, from: Data(contentsOf: deletedURL)) } catch { why = "\(error)" }
            log("deleted records=\(store.recentlyDeleted.count) decode=\(why.prefix(300))")
            log("lib projects=\(store.projects.map(\.name)) homeless=\(store.items.filter { $0.projectID == nil }.count) filter=\(store.filter) tab=\(store.tabTitle)")
        case "debugfloat": float()
        case "debugshotany":
            let w = [floating, panel, compact].compactMap { $0 }.first { $0.isVisible }
            if let view = w?.contentView, let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
            }
        case "debugoptionkey":
            // Sends ⌥ + a number key to the visible Stash window, like pressing it.
            let codes = [1: kVK_ANSI_1, 2: kVK_ANSI_2, 3: kVK_ANSI_3, 4: kVK_ANSI_4, 5: kVK_ANSI_5]
            let n = Int(url.query ?? "1") ?? 1
            if let w = [floating, panel, compact].compactMap({ $0 }).first(where: { $0.isVisible }),
               let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: .option, timestamp: 0, windowNumber: w.windowNumber,
                                        context: nil, characters: "¡", charactersIgnoringModifiers: "\(n)", isARepeat: false, keyCode: UInt16(codes[n] ?? kVK_ANSI_1)) {
                w.sendEvent(e)
            }
        case "debugselectloose":
            let n = Int(url.query ?? "2") ?? 2
            store.selection = Set(store.visibleItems.prefix(n).map { Selectable.item($0.id) })
        case "debugdropfile":
            // A drop from another app into the visible window: the file in the path, at ?x,y (points from the window's top-left).
            guard let w = [floating, panel, compact].compactMap({ $0 }).first(where: { $0.isVisible }),
                  let view = w.contentView as? DropView else { break }
            let xy = (url.query ?? "190,260").split(separator: ",").compactMap { Double($0) }
            let board = NSPasteboard(name: NSPasteboard.Name("stash.test.drop.\(UUID().uuidString)"))
            board.clearContents()
            board.writeObjects([URL(fileURLWithPath: url.path) as NSURL])
            let drag = TestDrop(board: board, location: NSPoint(x: xy[0], y: view.bounds.height - xy[1]), window: w)
            let op = view.draggingEntered(drag)
            let ok = view.performDragOperation(drag)
            log("drop op=\(op.rawValue) accepted=\(ok)")
        case "debugnewfolder": store.newFolder(); store.renamingFolderID = nil
            log("new folder: \(store.folders.last.map { f in store.items.filter { $0.folderID == f.id }.count } ?? -1) items inside, selection \(store.selection.count)")
        case "debugselbench":
            // 20 selection changes (like sweeping a box): main-thread time and how many tiles redrew.
            let order = store.visibleOrder, n = Int(url.query ?? "20") ?? 20
            let cpu0 = AppDelegate.mainThreadCPU(), c0 = Perf.cardBodies, b0 = Perf.boardBodies, f0 = Perf.folderBodies
            for i in 0..<n {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05 * Double(i)) { MainActor.assumeIsolated {
                    store.selection = Set(order.prefix(i + 1))
                } }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { MainActor.assumeIsolated {
                log(String(format: "selbench: %d changes cpu %.1f ms; cards %d folders %d boards %d", n, (AppDelegate.mainThreadCPU() - cpu0) * 1000,
                           Perf.cardBodies - c0, Perf.folderBodies - f0, Perf.boardBodies - b0))
            } }
        case "debugswitchbench":
            // Switches to the named project (?Name) and measures until the window has drawn it.
            let wanted = url.query?.removingPercentEncoding ?? ""
            let conn = ConnectedRegistry.shared.folders.first { "connected:" + $0.name == wanted }
            let project = store.projects.first { $0.name == wanted }
            guard conn != nil || project != nil else { log("switch: no such project"); break }
            let target = (name: conn?.name ?? project?.name ?? "", id: project?.id)
            let cpu0 = AppDelegate.mainThreadCPU(), t0 = Perf.now, c0 = Perf.cardBodies, f0 = Perf.folderBodies, b0 = Perf.boardBodies
            if let conn { ConnectedRegistry.shared.open(conn.id) } else if let id = target.id { store.connectedView = nil; store.filter = .project(id) }
            let setCPU = (AppDelegate.mainThreadCPU() - cpu0) * 1000
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated {
                log(String(format: "switch to %@: set %.1f ms, over 0.6 s %.1f ms wall / %.1f ms cpu; boards %d folders %d cards %d", target.name, setCPU,
                           Double(Perf.now - t0) / 1e6, (AppDelegate.mainThreadCPU() - cpu0) * 1000,
                           Perf.boardBodies - b0, Perf.folderBodies - f0, Perf.cardBodies - c0))
            } }
        case "debughuge": makeHugeLibrary()
        case "debugonechange":
            let cpu0 = AppDelegate.mainThreadCPU(), b0 = Perf.boardBodies, c0 = Perf.cardBodies, f0 = Perf.folderBodies
            let t0 = Perf.now
            store.objectWillChange.send()
            DispatchQueue.main.async { MainActor.assumeIsolated {
                log(String(format: "one change: first hop cpu %.1f ms wall %.1f ms", (AppDelegate.mainThreadCPU() - cpu0) * 1000, Double(Perf.now - t0) / 1e6))
            } }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { MainActor.assumeIsolated {
                log(String(format: "one change: 0.3 s cpu %.1f ms; boards %d folders %d cards %d", (AppDelegate.mainThreadCPU() - cpu0) * 1000,
                           Perf.boardBodies - b0, Perf.folderBodies - f0, Perf.cardBodies - c0))
            } }
        case "debuggrid":
            let frames = store.boardFrames[!panel.isVisible] ?? [:]
            let fs = store.visibleFolders.prefix(4).map { f in "\(f.name)=\(frames[.folder(f.id)].map { NSStringFromRect($0) } ?? "none") spot=\(String(describing: store.spot(of: f, compact: !panel.isVisible)))" }
            log("grid frames=\(frames.count) near=\(BoardNearby.shared.near.values.map(\.count)) \(fs)")
        case "debugtabchurn":
            // Switches between the first two projects 24 times (sample the app meanwhile).
            if case .project(let here) = store.filter, let other = store.projects.first(where: { $0.id != here })?.id {
                for i in 0..<24 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.4 * Double(i)) { store.filter = .project(i % 2 == 0 ? other : here) } }
            }
        case "debugmove":
            // Moves what's selected on the board by ?dx,dy (like letting go of a drag there).
            let d = (url.query ?? "0,0").split(separator: ",").compactMap { Double($0) }
            store.moveOnBoard(store.selection, by: CGSize(width: d[0], height: d[1]), compact: !panel.isVisible)
        case "debugscrollto":
            // Selects the board's last thing and scrolls to it, like arrow keys going past the edge.
            let compactNow = !panel.isVisible
            let before = store.boardContentOrigins[compactNow]
            if let last = store.visibleOrder.last {
                store.selection = [last]
                store.scrollTarget = last
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated {
                    let frame = store.boardFrames[compactNow]?[last]
                    log("scrollto frame=\(frame.map { NSStringFromRect($0) } ?? "none") origin before=\(String(describing: before)) after=\(String(describing: store.boardContentOrigins[compactNow]))")
                    store.moveSelection(.left, extend: false, compact: compactNow)
                    log("arrow left: selection=\(store.selection.count) target=\(String(describing: store.scrollTarget))")
                } }
            }
        case "debugfiles":
            // Every file and picture card: what it is, where its file is, and whether it's linked.
            for item in store.items where item.kind == .file || item.kind == .image {
                let state: String
                switch store.fileState(item) {
                case .stored?: state = "stored"
                case .linked?: state = "linked"
                case .missing?: state = "MISSING"
                case nil: state = "-"
                }
                let stored = item.storedPath.map { store.absolute($0) }
                let link = stored.flatMap { try? FileManager.default.destinationOfSymbolicLink(atPath: $0.path) }
                log("file \(item.title ?? "?") kind=\(item.kind) state=\(state) copying=\(FileCopies.shared.progress[item.id].map { String(format: "%.0f%%", $0 * 100) } ?? "no") stored=\(item.storedPath ?? "none") symlink=\(link ?? "no") thumb=\(store.displayImage(item) != nil) ocr=\(item.ocrText?.count ?? 0)")
            }
        case "debugcancelcopies":
            for id in FileCopies.shared.progress.keys { FileCopies.shared.cancel(id) }
        case "debughandout":
            // How long handing a file out (drag/copy) takes, for each file card.
            for item in store.items where item.kind == .file || item.kind == .image {
                guard let file = store.dragFile(for: item) else { continue }
                let t = Perf.now
                let out = Store.handOut(file)
                log(String(format: "handout %@ %.1f ms → %@", item.title ?? "?", Double(Perf.now - t) / 1e6, out.path))
            }
        case "debugfollow": store.followMovedOriginals()
        case "debugconvert":
            // Converts the selected card (?mp3 or ?mp4).
            if let id = store.selection.itemIDs.first, let target = ConvertTarget(rawValue: url.query ?? "mp3") {
                let t = Date()
                store.convert(id, to: target)
                func check() {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated {
                        if store.converting.contains(id) { check() } else { log(String(format: "convert %@ done in %.1f s, failures=%@", target.rawValue, Date().timeIntervalSince(t), store.jobFailures[id]?.reason ?? "none")) }
                    } }
                }
                check()
            }
        case "debugcanvas":
            // ?text=…, ?url=…, ?clear, ?undo, ?zoom=1.5, ?fit, ?state
            let canvas = CanvasStore.shared
            let q = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            for item in q {
                switch item.name {
                case "text": canvas.addText(item.value ?? "")
                case "paste": // as ⌘V does with copied text
                    let pb = NSPasteboard(name: NSPasteboard.Name("swiss.canvas.test.paste"))
                    pb.clearContents(); pb.setString(item.value ?? "", forType: .string)
                    canvas.ingest(pb)
                case "resize": // the selected thing to this width, as its sizer does
                    if let id = canvas.selection.first, let w = Double(item.value ?? "") { canvas.resize(id, to: CGSize(width: w, height: 1), keepAspect: true) }
                case "url": if let u = item.value.flatMap(URL.init(string:)) { canvas.addLink(u) }
                case "clear": canvas.clear()
                case "undo": canvas.undoClear()
                case "z": canvas.undo()
                case "redo": canvas.redo()
                case "delete": canvas.delete(canvas.selection)
                case "move": canvas.move(canvas.selection, by: CGSize(width: 100, height: 0))
                case "zoom": canvas.setZoom(Double(item.value ?? "1") ?? 1)
                case "fit": canvas.fitAll()
                case "select": canvas.selection = Set(canvas.items.map(\.id))
                case "scale": canvas.scale(canvas.selection, by: Double(item.value ?? "1") ?? 1)
                case "name": if let last = canvas.items.last { canvas.update(last.id) { $0.name = item.value }; canvas.selection = [last.id] }
                default: break
                }
            }
            if let id = canvas.selection.first, let it = canvas.items.first(where: { $0.id == id }), let w = floating {
                let vf = canvas.viewFrame(it)
                let screenH = NSScreen.screens[0].frame.height
                // The sizer's middle, in screen coordinates from the top-left (for a mouse test).
                let sx = w.frame.minX + canvas.viewOrigin.x + vf.maxX + 6 - 8 + 8
                let sy = screenH - w.frame.maxY + canvas.viewOrigin.y + vf.maxY + 6 - 8 + 8
                log("sizer at \(Int(sx)) \(Int(sy)) size \(Int(it.width))x\(Int(it.height))")
            }
            log("canvas items=\(canvas.items.map { "\($0.kind.rawValue)\($0.quote == true ? "(quote)" : ""):\(Int($0.width))x\(Int($0.height)) font=\(Int($0.textSize))@\(Int($0.x)),\(Int($0.y)) asset=\($0.asset != nil) url=\($0.url?.prefix(40) ?? "-")" }) zoom=\(canvas.zoom) pan=\(canvas.pan) cleared=\(canvas.cleared?.count ?? 0)")
        case "debugspace":
            // Selects the first picture anywhere (?pick) and presses Space in the visible window.
            if url.query == "pick", let photo = store.items.first(where: { $0.kind == .image }) { store.selection = [.item(photo.id)] }
            if let w = [floating, panel, compact].compactMap({ $0 }).first(where: { $0.isVisible }),
               let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: w.windowNumber,
                                        context: nil, characters: " ", charactersIgnoringModifiers: " ", isARepeat: false, keyCode: UInt16(kVK_Space)) {
                NSApp.activate(ignoringOtherApps: true) // like the click that selected it
                w.makeKey()
                w.sendEvent(e)
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { MainActor.assumeIsolated {
                log("quicklook visible=\(QLPreviewPanel.sharedPreviewPanelExists() && QLPreviewPanel.shared().isVisible)")
            } }
        case "debugmenuicon":
            // The menu bar icon, drawn big (black on white, then white on black) to look at.
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 200, pixelsHigh: 90, bitsPerSample: 8, samplesPerPixel: 4,
                                       hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSColor.white.setFill(); NSRect(x: 0, y: 0, width: 100, height: 90).fill()
            NSColor.black.setFill(); NSRect(x: 100, y: 0, width: 100, height: 90).fill()
            AppDelegate.menuBarIcon.draw(in: NSRect(x: 5, y: 5, width: 90, height: 81))
            let white = NSImage(size: AppDelegate.menuBarIcon.size, flipped: false) { r in
                AppDelegate.menuBarIcon.draw(in: r); NSColor.white.set(); r.fill(using: .sourceAtop); return true
            }
            white.draw(in: NSRect(x: 105, y: 5, width: 90, height: 81))
            NSGraphicsContext.restoreGraphicsState()
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: url.path))
        case "debugcedit":
            // Connected-folder editing: ?op=newfolder|note|rename&from=&to=|move&from=&into=|trash&path=|undo|organize|paste&text=|toproject&path=
            let q = Dictionary(uniqueKeysWithValues: (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []).map { ($0.name, $0.value ?? "") })
            let editor = ConnectedEditor.shared
            let dir = editor.currentURL
            func at(_ name: String?) -> URL? { name.flatMap { n in dir?.appendingPathComponent(n) } }
            switch q["op"] ?? "" {
            case "newfolder": editor.newFolder(named: q["name"] ?? "untitled folder", rename: false)
            case "note": editor.writeNote(q["text"] ?? "A note")
            case "rename": if let from = at(q["from"]) { editor.rename(from, to: q["to"] ?? "renamed") }
            case "move": if let from = at(q["from"]), let into = at(q["into"]) { editor.move([from], into: into) }
            case "trash": if let path = at(q["path"]) { editor.trash([path]) }
            case "undo": editor.undo()
            case "organize": editor.organize()
            case "paste":
                let pb = NSPasteboard(name: NSPasteboard.Name("swiss.test.paste"))
                pb.clearContents(); pb.setString(q["text"] ?? "", forType: .string)
                editor.ingest(pb)
            case "toproject": if let path = at(q["path"]), let p = store.projects.first { store.moveIntoProject([path], project: p.id) }
            case "place":
                if let path = at(q["path"]), let d = dir { editor.place([path.path], by: CGSize(width: 200, height: 150), frames: ConnectedDrag.shared.boardFrames, in: d) }
            default: break
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated {
                log("cedit dir=\(dir?.lastPathComponent ?? "-") entries=\(ConnectedSelection.shared.entries.map(\.name)) spot=\(q["path"].flatMap(at).flatMap(editor.spot(of:)).map { "\(Int($0.x)),\(Int($0.y))" } ?? "-")")
            } }
        case "debugconvfile":
            // Converts the file in the path with the conversion ?id (e.g. img-png, img-1024, vid-720, doc-pdf), next to it.
            let file = URL(fileURLWithPath: url.path)
            let options = FormatConverter.conversions(for: file)
            log("conversions for \(file.lastPathComponent): \(options.map(\.id))")
            if let option = options.first(where: { $0.id == url.query }) { store.convertFile(file, using: option) }
        case "debugselectall":
            // Presses ⌃A (or ?cmd: ⌘A) in the visible window, then logs how much is selected.
            let cmd = url.query == "cmd"
            if let w = [floating, panel, compact].compactMap({ $0 }).first(where: { $0.isVisible }),
               let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: cmd ? .command : .control, timestamp: 0, windowNumber: w.windowNumber,
                                        context: nil, characters: cmd ? "a" : "\u{1}", charactersIgnoringModifiers: "a", isARepeat: false, keyCode: UInt16(kVK_ANSI_A)) {
                NSApp.activate(ignoringOtherApps: true)
                w.makeKey()
                if cmd { _ = w.contentView?.performKeyEquivalent(with: e) } else { w.sendEvent(e) }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { MainActor.assumeIsolated {
                log("selected \(store.selection.count) of \(store.libraryShown.count) shown (all items view: \(store.libraryView != nil))")
            } }
        case "debugchurn":
            // "Something changed", 40 times, 0.25 s apart (sample the app meanwhile to see what redraws cost).
            for i in 0..<40 { DispatchQueue.main.asyncAfter(deadline: .now() + 0.25 * Double(i)) { store.objectWillChange.send() } }
        case "debugproject":
            if let p = store.projects.first(where: { $0.name == url.query?.removingPercentEncoding }) {
                store.connectedView = nil; store.showingRecent = false; store.libraryView = nil
                store.filter = .project(p.id); store.openFolderID = nil
            }
        case "debugbench": runBench(label: url.query ?? "run")
        case "debugmodes":
            log("modes popup=\(compact.isVisible) window=\(panel.isVisible) floating=\(floating.isVisible) mode=\(WindowMode.current.rawValue) zoom=\(store.boardZoom) frame=\(NSStringFromRect(floating.frame)) popupFrame=\(NSStringFromRect(compact.frame)) windowFrame=\(NSStringFromRect(panel.frame)) screenH=\(NSScreen.screens[0].frame.height) items=\(store.visibleItems.count) names=\(store.visibleItems.map(\.title).suffix(3))")
        case "debugconnect":
            if let f = ConnectedRegistry.shared.connect(URL(fileURLWithPath: url.path)) { ConnectedRegistry.shared.open(f.id) }
        case "debugconnectedgo":
            if let loc = store.connectedView { store.connectedView = ConnectedLocation(folderID: loc.folderID, subpath: url.query?.removingPercentEncoding ?? "") }
        case "debugconnectedstate":
            let names = ConnectedSelection.shared.entries.map(\.name)
            log("connected folders=\(ConnectedRegistry.shared.folders.map { $0.name + "@" + $0.path }) view=\(String(describing: store.connectedView?.subpath)) shown=\(names)")
        case "debugdisconnect":
            if let f = ConnectedRegistry.shared.folders.first { ConnectedRegistry.shared.remove(f.id) }
        default: break
        }
    }
}


/// A pretend drag from another app, for testing drops without a mouse.
final class TestDrop: NSObject, NSDraggingInfo {
    let board: NSPasteboard
    let location: NSPoint
    let window: NSWindow
    init(board: NSPasteboard, location: NSPoint, window: NSWindow) { self.board = board; self.location = location; self.window = window }
    var draggingDestinationWindow: NSWindow? { window }
    var draggingSourceOperationMask: NSDragOperation { .copy }
    var draggingLocation: NSPoint { location }
    var draggedImageLocation: NSPoint { location }
    var draggedImage: NSImage? { nil }
    var draggingPasteboard: NSPasteboard { board }
    var draggingSource: Any? { nil }
    var draggingSequenceNumber: Int { 1 }
    func slideDraggedImage(to screenPoint: NSPoint) {}
    var draggingFormation: NSDraggingFormation = .default
    var animatesToDestination = false
    var numberOfValidItemsForDrop = 1
    func enumerateDraggingItems(options enumOpts: NSDraggingItemEnumerationOptions = [], for view: NSView?, classes classArray: [AnyClass],
                                searchOptions: [NSPasteboard.ReadingOptionKey: Any] = [:], using block: (NSDraggingItem, Int, UnsafeMutablePointer<ObjCBool>) -> Void) {}
    var springLoadingHighlight: NSSpringLoadingHighlight { .none }
    func resetSpringLoading() {}
}
#endif
