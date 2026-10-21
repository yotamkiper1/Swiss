import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static private(set) var shared: AppDelegate!

    private var statusItem: NSStatusItem!
    private(set) var panel: StashPanel!
    private(set) var floating: StashPanel!
    /// Open Get Info windows.
    var infoWindows: [NSWindow] = []
    private(set) var compact: StashPanel!
    private var previewPanel: PreviewPanel!
    private var settingsWindow: NSPanel?
    private let screenshots = ScreenshotCatcher()
    /// The window to give focus back to when the preview closes.
    private weak var windowBeforePreview: NSWindow?
    var hotKey: HotKey?
    var quickSaveKey: HotKey?
    var hotKeyCombo: KeyCombo?
    var quickSaveCombo: KeyCombo?
    private let savedHUD = SavedHUD()
    private var linksBeforeLaunch: [URL] = []
    private var iconReset: Task<Void, Never>?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        withExtendedLifetime(delegate) { app.run() }
    }

    /// Says so (once) if the library had to be restored from a backup, or couldn't be read at all.
    private func reportLibraryProblems() {
        let store = Store.shared
        let message: String?
        if !store.libraryReadable {
            message = "Swiss couldn't read your library or any of its backups, so it hasn't changed anything. Your files are untouched in \(store.dataDir.path)."
        } else {
            message = store.recoveryNote
        }
        guard let message else { return }
        DispatchQueue.main.async {
            let alert = NSAlert()
            alert.messageText = store.libraryReadable ? "Library restored" : "Library couldn't be opened"
            alert.informativeText = message
            NSApp.activate()
            alert.runModal()
        }
    }

    /// Everything waiting to be saved is written before Stash quits.
    func applicationWillTerminate(_ notification: Notification) {
        Store.flushSaves()
        CanvasStore.shared.flush()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppDelegate.shared = self
        if TestMode.isOn, ProcessInfo.processInfo.environment["STASH_COUNTERS"] != nil { Perf.startCounterLog() }
        OrganizerSettings.register()
        AppLock.start() // Settings ▸ Privacy ▸ Require Touch ID
        MainMenu.shared.install() // Swiss's tools in the Mac menu bar
        NSApp.servicesProvider = self // Finder / browsers: right-click ▸ Services ▸ Add to Swiss Recent
        NSUpdateDynamicServices()
        setUpPanel()
        setUpCompact()
        setUpFloating()
        previewPanel = PreviewPanel()
        setUpStatusItem()
        registerHotKeys() // ⌥Space and quick save, or whatever you set in Settings → Shortcuts
        reportLibraryProblems()
        if !linksBeforeLaunch.isEmpty {
            let links = linksBeforeLaunch
            linksBeforeLaunch = []
            DispatchQueue.main.async { AppDelegate.shared.application(NSApp, open: links) }
        }
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared.registerHotKeys() }
        }
        NotificationCenter.default.addObserver(forName: .stashDidSave, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared.flashStatusIcon() }
        }
        // Let the status item settle into the menu bar before anchoring to it.
        // (Not when Swiss is locked: it may be opening at login, and Touch ID would ask for nothing.)
        if !AppLock.enabled { DispatchQueue.main.async { AppDelegate.shared.showCompact() } }
        // The first time: a short tour of the tools.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { MainActor.assumeIsolated { WelcomeTour.showIfFirstLaunch() } }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { showCompact() }
        return true
    }

    /// stash://clipboard saves the clipboard, stash://add?text=… saves text or a link, stash://open shows the panel.
    func application(_ application: NSApplication, open urls: [URL]) {
        // A swiss:// link that launched Swiss arrives before its windows exist: handle it once they do.
        guard compact != nil else { linksBeforeLaunch += urls; return }
        let store = Store.shared
        for url in urls where TestMode.isOn ? url.scheme == "stashtest" : ["swiss", "stash"].contains(url.scheme ?? "") {
            // Any web page can open these links, so they're limited: a few at a time, text only, cleaned up.
            if ["clipboard", "recent", "add"].contains(url.host ?? ""), !Safety.allowLink() { continue }
            let text = (URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == "text" }?.value)
                .map(Safety.cleanText) ?? ""
            switch url.host {
            case "clipboard":
                // Never a password or anything private an app put on the clipboard.
                if Safety.isPrivate(.general) || !store.ingest(.general, into: store.currentPlace) { NSSound.beep() }
            case "recent":
                // swiss://recent?text=… — a link or words from a browser's right-click, straight into Recent.
                if !text.isEmpty { RecentStore.shared.addExplicit(text: text, source: "Browser") }
            case "add":
                if !text.isEmpty { store.addText(text, place: store.currentPlace) }
            #if SWISS_TEST
            case let host? where host.hasPrefix("debug") && TestMode.isOn:
                handleDebug(url, compact: compact, panel: panel) // test hooks exist only in Swiss Test
            #endif
            default:
                if !panel.isVisible { showCompact() }
            }
        }
    }

    // MARK: Panel

    private func makeContainer<Content: View>(_ root: Content, size: NSSize, onCancel: @escaping () -> Void) -> DropView {
        let container = DropView(frame: NSRect(origin: .zero, size: size))
        container.onCancel = onCancel
        let host = FirstClickHostingView(rootView: root.environmentObject(Store.shared))
        host.sizingOptions = []
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        return container
    }

    private func setUpPanel() {
        StashAppearance.apply() // day or night, by the clock
        RecentStore.shared.start() // Recent: what you copy and screenshot (only once you turn capture on)
        // A drive connected or ejected: linked files on it show as there / not found, and moved ones are followed.
        for name in [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification] {
            NSWorkspace.shared.notificationCenter.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    Store.shared.objectWillChange.send()
                    if name == NSWorkspace.didMountNotification { Store.shared.followMovedOriginals() }
                }
            }
        }
        panel = StashPanel(contentRect: NSRect(x: 0, y: 0, width: 760, height: 580))
        panel.contentView = makeContainer(WindowGate(key: "window") { RootView() }, size: NSSize(width: 760, height: 580)) {
            AppDelegate.shared.hidePanel()
        }
        if !panel.setFrameUsingName("StashPanel") { panel.center() }
        panel.setFrameAutosaveName("StashPanel")
        applyPanelLock() // a frame you drew stays put
    }

    /// The small preview hanging from the menu bar icon. It stays open while you drag
    /// things in from other apps, and closes when you click the icon again or press Esc.
    /// The floating frame (third mode).
    private func setUpFloating() {
        let size = NSSize(width: 380, height: 520)
        floating = StashPanel(contentRect: NSRect(origin: .zero, size: size), floating: true)
        floating.contentView = makeContainer(WindowGate(key: "floating") { CanvasView() }, size: size) { AppDelegate.shared.hideFloating() }
        if !floating.setFrameUsingName("StashFloating"), let screen = NSScreen.main?.visibleFrame {
            floating.setFrameOrigin(NSPoint(x: screen.maxX - size.width - 24, y: screen.maxY - size.height - 24))
        }
        floating.setFrameAutosaveName("StashFloating")
        applyFloatingLock()
    }

    private func setUpCompact() {
        let size = NSSize(width: 300, height: 400)
        compact = StashPanel(contentRect: NSRect(origin: .zero, size: size), compact: true)
        let container = makeContainer(WindowGate(key: "popup") { CompactView() }, size: size) { AppDelegate.shared.closeCompact() }
        container.wantsLayer = true
        container.layer?.cornerRadius = 12
        container.layer?.masksToBounds = true
        compact.contentView = container
        NotificationCenter.default.addObserver(forName: NSWindow.didMoveNotification, object: compact, queue: .main) { _ in
            MainActor.assumeIsolated { AppDelegate.shared.rememberPinnedSpot() }
        }
    }

    func showCompact() {
        guard AppLock.allow({ AppDelegate.shared.showCompact() }) else { return }
        guard let button = statusItem.button else { return }
        // Stash opens in the mode you used last: the pop-up, the window, or the floating frame.
        switch WindowMode.current {
        case .window: showPanel(); return
        case .floating: showFloating(); return
        case .popup: break
        }
        if panel.isVisible { panel.orderOut(nil) } // one Stash window at a time
        if floating.isVisible { floating.orderOut(nil) }
        Store.shared.boardZoom = 1
        if let pinned = pinnedOrigin {
            compact.setFrameOrigin(pinned) // pinned: reopen where you left it
        } else {
            placeCompactUnderIcon()
        }
        compact.makeKeyAndOrderFront(nil)
        compact.invalidateShadow()
        NSApp.activate()
        button.highlight(!isPinned)
        Store.shared.focusRequest += 1
    }

    /// Hang the preview just under the icon, kept on screen.
    private func placeCompactUnderIcon() {
        guard let button = statusItem.button, let iconFrame = button.window?.frame else { return }
        let size = compact.frame.size
        let screen = (button.window?.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        var x = iconFrame.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        compact.setFrameOrigin(NSPoint(x: x, y: iconFrame.minY - size.height - 6))
    }

    // MARK: Locking the windows in place

    /// The small pop-up is locked where you put it (it no longer hangs under the menu bar icon).
    static let pinnedKey = "compact.pinned"
    private static let pinnedOriginKey = "compact.pinnedOrigin"
    /// The big window is locked and was the last one open.
    static let pinnedBigKey = "compact.pinnedBig"

    var isPinned: Bool { UserDefaults.standard.bool(forKey: Self.pinnedKey) }
    var isBigLocked: Bool { UserDefaults.standard.string(forKey: FrameDrawer.lockedKey) != nil }

    /// Where the pinned preview sits — only if that spot is still on a connected screen.
    private var pinnedOrigin: NSPoint? {
        guard isPinned, let saved = UserDefaults.standard.string(forKey: Self.pinnedOriginKey) else { return nil }
        let parts = saved.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let origin = NSPoint(x: parts[0], y: parts[1])
        let frame = NSRect(origin: origin, size: compact.frame.size)
        return NSScreen.screens.contains { $0.frame.intersects(frame) } ? origin : nil
    }

    /// Lock the pop-up: it stays exactly where it is now (drag it there first by its top bar) and reopens there.
    /// Unlock: back under the menu bar icon.
    func setPinned(_ pinned: Bool) {
        UserDefaults.standard.set(pinned, forKey: Self.pinnedKey)
        if pinned {
            rememberPinnedSpot()
            statusItem.button?.highlight(false)
            Store.shared.flash("Locked here")
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pinnedOriginKey)
            placeCompactUnderIcon()
            statusItem.button?.highlight(compact.isVisible)
            Store.shared.flash("Unlocked — back under the menu bar")
        }
    }

    fileprivate func rememberPinnedSpot() {
        guard isPinned else { return }
        let origin = compact.frame.origin
        UserDefaults.standard.set("\(origin.x),\(origin.y)", forKey: Self.pinnedOriginKey)
    }

    func closeCompact() {
        guard compact.isVisible else { return }
        if companion { closeCompanion(); return }
        Store.shared.clipboardHint = nil
        compact.orderOut(nil)
        statusItem.button?.highlight(false)
        if !panel.isVisible && NSApp.isActive { NSApp.hide(nil) } // hand focus back to the app you came from
    }

    // MARK: Settings

    @objc private func showSettingsAction() { showSettings() }

    /// Organizer options and Deep Organize. Kept out of the main window on purpose.
    func showSettings() {
        guard AppLock.allow({ AppDelegate.shared.showSettings() }) else { return } // so the lock can't be switched off by someone else
        if settingsWindow == nil {
            let window = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 520, height: 620),
                                 styleMask: [.titled, .closable, .nonactivatingPanel], backing: .buffered, defer: false)
            window.title = "Swiss Settings"
            window.isReleasedWhenClosed = false
            window.hidesOnDeactivate = false
            window.becomesKeyOnlyIfNeeded = false
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1) // above the menu bar preview
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.contentView = NSHostingView(rootView: SettingsView().environmentObject(Store.shared))
            window.center()
            settingsWindow = window
        }
        settingsWindow?.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    // MARK: Image preview

    func preview(_ itemID: UUID) {
        let store = Store.shared
        guard let item = store.items.first(where: { $0.id == itemID }), item.kind == .image else { return }
        if !previewPanel.isVisible {
            windowBeforePreview = compact.isVisible ? compact : panel
            // Big, but fitted to the image and the screen.
            let screen = (NSApp.keyWindow?.screen ?? NSScreen.main)?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            var size = NSSize(width: screen.width * 0.7, height: screen.height * 0.8)
            if let image = store.displayImageNow(item), image.size.height > 0 {
                let ratio = image.size.width / image.size.height
                let fitted = min(size.width, (size.height - 60) * ratio)
                size = NSSize(width: max(fitted, 420), height: max(fitted / ratio + 60, 320))
            }
            previewPanel.setFrame(NSRect(x: screen.midX - size.width / 2, y: screen.midY - size.height / 2,
                                         width: size.width, height: size.height), display: false)
        }
        store.previewItemID = itemID
        store.selection = [.item(itemID)]
        previewPanel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    /// Space on the board: preview the selected image.
    func previewSelection() {
        let store = Store.shared
        let selected = store.visibleItems.first { store.selection.contains(.item($0.id)) && $0.kind == .image }
        if let selected { preview(selected.id) } else { NSSound.beep() }
    }

    func closePreview() {
        previewPanel.orderOut(nil)
        Store.shared.previewItemID = nil
        windowBeforePreview?.makeKey()
    }

    /// Small preview → big movable window.
    func expand() {
        if !companion { WindowMode.set(.window) } // opened from the canvas: the canvas stays the mode you use
        compact.orderOut(nil) // one Stash window at a time (the canvas's companion: besides the canvas)
        if !companion { floating.orderOut(nil) }
        statusItem.button?.highlight(false)
        showPanel()
    }

    /// Big window → back into the menu bar.
    func collapse() {
        if companion { panel.orderOut(nil); openCompanion(); return }
        WindowMode.set(.popup)
        panel.orderOut(nil)
        floating.orderOut(nil)
        showCompact()
    }

    // MARK: Floating frame

    /// Floating mode: one frame above every app, wherever you put it.
    func float() {
        guard !companion else { return } // already in the Frame
        WindowMode.set(.floating)
        compact.orderOut(nil)
        panel.orderOut(nil)
        statusItem.button?.highlight(false)
        showFloating()
    }

    func showFloating() {
        guard AppLock.allow({ AppDelegate.shared.showFloating() }) else { return }
        if panel.isVisible { panel.orderOut(nil) }
        if compact.isVisible { compact.orderOut(nil) }
        floating.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Store.shared.focusRequest += 1
    }

    func hideFloating() {
        if companion { closeCompanion() } // its companion window goes with it
        Store.shared.clipboardHint = nil
        floating.orderOut(nil)
        if NSApp.isActive { NSApp.hide(nil) }
    }

    /// Clicking the icon closes whatever is open, or opens the preview.
    private func iconClicked() {
        if floating.isVisible {
            hideFloating()
        } else if panel.isVisible {
            hidePanel()
        } else if compact.isVisible {
            closeCompact()
        } else {
            Store.shared.prepareForClipboard()
            showCompact()
        }
    }

    /// ⌥Space works like the icon, but first brings an open window to the front if it's behind other apps.
    /// Also: right after a screenshot, ⌥Space saves it to the open project and shows it.
    func hotKeyPressed() {
        if screenshots.catchRecent(into: Store.shared.currentPlace) {
            if !panel.isVisible && !compact.isVisible && !floating.isVisible { showCompact() }
            return
        }
        if floating.isVisible && !floating.isKeyWindow {
            Store.shared.prepareForClipboard()
            showFloating()
        } else if panel.isVisible && !panel.isKeyWindow {
            Store.shared.prepareForClipboard()
            showPanel()
        } else {
            iconClicked()
        }
    }

    func showPanel() {
        guard AppLock.allow({ AppDelegate.shared.showPanel() }) else { return }
        if compact.isVisible { compact.orderOut(nil) }
        if floating?.isVisible == true, !companion { floating.orderOut(nil) }
        Store.shared.boardZoom = 1
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Store.shared.focusRequest += 1
        // Don't start in the Search box, so 1–5, Delete and the arrows work right away (⌘F goes to search).
        DispatchQueue.main.async { [panel] in
            if panel?.firstResponder is NSTextView { _ = panel?.makeFirstResponder(nil) }
        }
    }

    func hidePanel() {
        if companion { closeCompanion(); return }
        Store.shared.clipboardHint = nil
        panel.orderOut(nil)
        if NSApp.isActive { NSApp.hide(nil) } // hand focus back to the app you came from
    }

    @objc private func closeAction() {
        if panel.isVisible { hidePanel() } else { closeCompact() }
    }
    @objc private func showCompactAction() { showCompact() }
    @objc private func showPanelAction() { showPanel() }

    // MARK: Projects

    /// + : a new tab right there, with its name box open ("Project" if you just press Return).
    func newProject() {
        let store = Store.shared
        let project = store.addProject(named: "Project")
        store.renamingProjectID = project.id
    }

    func renameProject(_ project: Project) {
        Store.shared.renamingProjectID = project.id
    }

    private func prompt(_ title: String, initial: String = "", confirm: String, completion: @escaping (String) -> Void) {
        let alert = NSAlert()
        alert.messageText = title
        alert.addButton(withTitle: confirm)
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = initial
        field.placeholderString = "Project name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        let finish: (NSApplication.ModalResponse) -> Void = { response in
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if response == .alertFirstButtonReturn, !name.isEmpty { completion(name) }
        }
        if panel.isVisible {
            alert.beginSheetModal(for: panel, completionHandler: finish)
        } else {
            alert.window.level = .popUpMenu
            finish(alert.runModal())
        }
    }

    // MARK: Menu bar icon

    private func setUpStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        setStatusIcon(nil)
        if let button = statusItem.button {
            button.target = self
            button.action = #selector(statusItemClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.toolTip = "Swiss — click to open (⌥Space), drop anything here to save it. ⌥Space right after a screenshot saves it."
            // The status bar window forwards drags to its delegate.
            button.window?.registerForDraggedTypes(Store.acceptedTypes)
            button.window?.delegate = self
        }
    }

    /// The menu bar icon: Swiss's multi-tool (or a symbol for a moment, like the ✓ after saving). One color — macOS
    /// makes it black or white to suit the menu bar.
    private func setStatusIcon(_ symbol: String?) {
        let image = symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: "Swiss") } ?? Self.menuBarIcon
        image.isTemplate = true
        statusItem.button?.image = image
    }

    /// The app icon's knife in one color: the red handle with its rivet cut out, the blade and the little tool out.
    static let menuBarIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 16), flipped: true) { _ in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            // Drawn in the logo's own picture units (1254 square; the knife spans x 175…1078, y 285…922),
            // fitted 16 points wide.
            let scale: CGFloat = 16 / 903
            ctx.translateBy(x: 1 - 175 * scale, y: (16 - 637 * scale) / 2 - 285 * scale)
            ctx.scaleBy(x: scale, y: scale)
            ctx.setFillColor(NSColor.black.cgColor)
            // The blade: a long leaf rising to the right.
            let blade = CGMutablePath()
            blade.move(to: CGPoint(x: 445, y: 660))
            blade.addCurve(to: CGPoint(x: 1020, y: 285), control1: CGPoint(x: 640, y: 480), control2: CGPoint(x: 840, y: 300))
            blade.addCurve(to: CGPoint(x: 698, y: 660), control1: CGPoint(x: 990, y: 420), control2: CGPoint(x: 860, y: 530))
            blade.closeSubpath()
            ctx.addPath(blade); ctx.fillPath()
            // The little tool, tilted back on the left.
            let tool = CGMutablePath()
            tool.move(to: CGPoint(x: 327, y: 540))
            tool.addLine(to: CGPoint(x: 410, y: 660))
            tool.addLine(to: CGPoint(x: 487, y: 592))
            tool.addLine(to: CGPoint(x: 399, y: 482))
            tool.addQuadCurve(to: CGPoint(x: 330, y: 495), control: CGPoint(x: 365, y: 462))
            tool.closeSubpath()
            ctx.addPath(tool); ctx.fillPath()
            // The handle: a long pill.
            ctx.addPath(CGPath(roundedRect: CGRect(x: 175, y: 653, width: 903, height: 269), cornerWidth: 134, cornerHeight: 134, transform: nil))
            ctx.fillPath()
            ctx.setBlendMode(.clear) // the rivet is a hole, and a hair of space keeps the tool apart from the blade
            ctx.fillEllipse(in: CGRect(x: 941 - 62, y: 789 - 62, width: 124, height: 124))
            let gap = CGMutablePath()
            gap.move(to: CGPoint(x: 412, y: 653)); gap.addLine(to: CGPoint(x: 500, y: 579))
            ctx.addPath(gap); ctx.setLineWidth(34); ctx.setStrokeColor(NSColor.black.cgColor); ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Swiss"
        return image
    }()

    func flashStatusIcon() {
        iconReset?.cancel()
        setStatusIcon("checkmark.circle.fill")
        iconReset = Task {
            try? await Task.sleep(for: .seconds(1.2))
            guard !Task.isCancelled else { return }
            setStatusIcon(nil)
        }
    }

    @objc private func statusItemClicked() {
        let event = NSApp.currentEvent
        if event?.type == .rightMouseUp || event?.modifierFlags.contains(.control) == true {
            statusItem.menu = makeStatusMenu()
            statusItem.button?.performClick(nil)
            statusItem.menu = nil
        } else {
            iconClicked()
        }
    }

    @objc private func togglePauseCapture() { RecentStore.shared.setPaused(!RecentStore.shared.paused) }

    /// Finder's Services menu: "Add to Swiss Recent" for files, links and words (see Info.plist ▸ NSServices).
    @objc func addToRecent(_ pboard: NSPasteboard, userData: String, error: AutoreleasingUnsafeMutablePointer<NSString>) {
        MainActor.assumeIsolated { RecentStore.shared.addExplicit(pboard, source: "Services") }
    }

    /// Shows Downloads ▸ Swiss in Finder (made if it isn't there yet).
    @objc func showSwissDownloads() {
        NSWorkspace.shared.open(RecentStore.prepareSwissFolder())
    }

    private func makeStatusMenu() -> NSMenu {
        let menu = NSMenu()
        let open = menu.addItem(withTitle: "Open Swiss", action: #selector(showCompactAction), keyEquivalent: " ")
        open.keyEquivalentModifierMask = [.option]
        menu.addItem(withTitle: "Open Full Window", action: #selector(showPanelAction), keyEquivalent: "")
        let quick = menu.addItem(withTitle: "Save Clipboard to \(Store.shared.describe(Store.shared.suggestedPlace(for: Store.clipboardKind(.general)?.0)))",
                                 action: #selector(saveClipboard), keyEquivalent: "")
        quick.toolTip = "Same as the quick-save shortcut (\(Shortcut.quickSave.combo?.display ?? "off"))"
        if CaptureSettings.clipboardOn || CaptureSettings.screenshotsOn || CaptureSettings.downloadsOn {
            let paused = RecentStore.shared.paused
            menu.addItem(withTitle: paused ? "Resume Capture" : "Pause Capture", action: #selector(togglePauseCapture), keyEquivalent: "")
        }
        menu.addItem(.separator())
        let login = menu.addItem(withTitle: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        login.state = SMAppService.mainApp.status == .enabled ? .on : .off
        menu.addItem(withTitle: "Open Swiss Folder (Documents)", action: #selector(showLibrary), keyEquivalent: "")
        menu.addItem(withTitle: "Open Downloads ▸ Swiss (save here to add to Recent)", action: #selector(showSwissDownloads), keyEquivalent: "")
        menu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",")
        for shortcut in [Shortcut.open, .quickSave] where isRegistered(shortcut) == false {
            let warning = menu.addItem(withTitle: "\(shortcut.combo?.display ?? "") is used by another app", action: nil, keyEquivalent: "")
            warning.isEnabled = false
        }
        menu.addItem(.separator())
        menu.addItem(withTitle: "Report a Problem…", action: #selector(reportProblem), keyEquivalent: "")
        menu.addItem(withTitle: "Send Feedback…", action: #selector(sendFeedback), keyEquivalent: "")
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit Swiss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        for item in menu.items where item.action != #selector(NSApplication.terminate(_:)) { item.target = self }
        return menu
    }

    @objc private func saveClipboard() { quickSavePressed() }
    @objc private func reportProblem() { Feedback.reportProblem() }
    @objc private func sendFeedback() { Feedback.sendFeedback() }

    @objc private func toggleLaunchAtLogin() {
        do {
            if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            } else {
                try SMAppService.mainApp.register()
            }
        } catch {
            NSAlert(error: error).runModal()
        }
    }

    @objc private func showLibrary() {
        NSWorkspace.shared.open(Store.shared.rootDir)
    }

    // MARK: Drops on the menu bar icon

    func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        statusItem.button?.highlight(true)
        return .copy
    }

    func draggingExited(_ sender: NSDraggingInfo?) {
        statusItem.button?.highlight(compact.isVisible)
    }

    /// Drops on the icon go where quick save would put them (the open project, in its Files/PhotoBook/… folder).
    func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        statusItem.button?.highlight(compact.isVisible)
        let store = Store.shared
        let place = store.suggestedPlace(for: Store.clipboardKind(sender.draggingPasteboard)?.0)
        guard store.ingest(sender.draggingPasteboard, into: place) else { return false }
        if !compact.isVisible && !panel.isVisible { savedHUD.show("Saved to \(store.describe(place))", below: statusItem.button?.window?.frame) }
        return true
    }

    // MARK: Quick save

    func quickSavePressed() {
        let store = Store.shared
        if let place = store.quickSave() {
            savedHUD.show("Saved to \(store.describe(place))", below: statusItem.button?.window?.frame)
        } else {
            savedHUD.show("Nothing copied to save", symbol: "exclamationmark.circle", below: statusItem.button?.window?.frame)
        }
    }

    // MARK: Main menu (makes ⌘C, ⌘A, ⌘Z work in text fields)

    private func buildMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "Close Window", action: #selector(closeAction), keyEquivalent: "w").target = self
        appMenu.addItem(withTitle: "Settings…", action: #selector(showSettingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit Swiss", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        main.addItem(editItem)

        NSApp.mainMenu = main
    }
}

extension AppDelegate: NSDraggingDestination {}

/// Buttons and cards answer the very first click, even before the window is in front.
final class FirstClickHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}
