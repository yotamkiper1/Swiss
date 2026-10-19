import AppKit
import SwiftUI

// MARK: - The Mac menu bar

/// Swiss's tools in the Mac's menu bar (Swiss, File, Edit, View, Go, Window, Help) — like any Mac app. The
/// windows keep only what you use there and then: the window buttons and lock, where things go, Icons/List,
/// Arrange By, and (full screen only) the magic wand. Menus are rebuilt each time they open, so checkmarks and
/// lists (projects, connected folders) are always current. The menu bar shows while Swiss is the app in front —
/// clicking any Swiss window brings it there.
@MainActor
final class MainMenu: NSObject, NSMenuDelegate {
    static let shared = MainMenu()
    private var builders: [ObjectIdentifier: () -> [NSMenuItem]] = [:]
    private var store: Store { Store.shared }
    private var app: AppDelegate { AppDelegate.shared }

    func install() {
        let main = NSMenu()
        add(main, "Swiss", appMenu)
        add(main, "File", fileMenu)
        add(main, "Edit", editMenu)
        add(main, "View", viewMenu)
        add(main, "Go", goMenu)
        add(main, "Window", windowMenu)
        add(main, "Help", helpMenu)
        NSApp.mainMenu = main
    }

    private func add(_ main: NSMenu, _ title: String, _ build: @escaping () -> [NSMenuItem]) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.delegate = self
        builders[ObjectIdentifier(menu)] = build
        menu.items = build() // so key equivalents work before the menu is ever opened
        item.submenu = menu
        main.addItem(item)
    }

    nonisolated func menuNeedsUpdate(_ menu: NSMenu) {
        MainActor.assumeIsolated {
            guard let build = builders[ObjectIdentifier(menu)] else { return }
            menu.items = build()
        }
    }

    // MARK: Items

    private func item(_ title: String, _ key: String = "", _ modifiers: NSEvent.ModifierFlags = .command,
                      checked: Bool = false, enabled: Bool = true, action: @escaping () -> Void) -> NSMenuItem {
        let item = ActionItem(title: title, keyEquivalent: key, handler: action)
        item.keyEquivalentModifierMask = modifiers
        item.state = checked ? .on : .off
        item.isEnabled = enabled
        return item
    }

    private func submenu(_ title: String, _ items: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        let menu = NSMenu(title: title)
        menu.autoenablesItems = false
        menu.items = items
        item.submenu = menu
        return item
    }

    private var editingText: Bool { NSApp.keyWindow?.firstResponder is NSTextView }

    /// While typing, the text gets it (undo, copy…); otherwise it's for the board.
    private func text(_ action: Selector, otherwise: () -> Void) {
        if editingText { _ = NSApp.sendAction(action, to: nil, from: nil) } else { otherwise() }
    }
    private var mode: WindowMode { WindowMode.current }

    // MARK: Menus

    private func appMenu() -> [NSMenuItem] {
        let recent = RecentStore.shared
        let capture = CaptureSettings.self
        return [
            item("About Swiss") { NSApp.orderFrontStandardAboutPanel(nil); NSApp.activate() },
            .separator(),
            item("Settings…", ",") { self.app.showSettings() },
            .separator(),
            item("Catch Copies", checked: UserDefaults.standard.bool(forKey: capture.clipboardKey)) {
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: capture.clipboardKey), forKey: capture.clipboardKey)
                recent.start()
            },
            item("Catch Screenshots", checked: UserDefaults.standard.bool(forKey: capture.screenshotsKey)) {
                UserDefaults.standard.set(!UserDefaults.standard.bool(forKey: capture.screenshotsKey), forKey: capture.screenshotsKey)
                recent.start()
            },
            item(recent.paused ? "Resume Catching" : "Pause Catching") { recent.setPaused(!recent.paused) },
            .separator(),
            item("Hide Swiss", "h") { NSApp.hide(nil) },
            item("Quit Swiss", "q") { NSApp.terminate(nil) },
        ]
    }

    private func fileMenu() -> [NSMenuItem] {
        var items = QuickAction.allCases.map { action in
            item(action == .newNote || action == .newFolder ? action.title : "New \(action.title)", String(action.key),
                 enabled: self.store.canCreateHere) {
                self.store.perform(action)
            }
        }
        items += [
            item("New Project", "t") { self.app.newProject() },
            .separator(),
            item("Save From Clipboard", "v", [.command, .shift]) {
                if !self.store.ingest(.general, into: self.store.currentPlace) { NSSound.beep() }
            },
            item("Connect a Folder…") { ConnectedRegistry.shared.chooseAndConnect() },
            .separator(),
            item("Show in Finder", "r", [.command, .shift]) { self.store.revealCurrentFolder() },
            item("Save Project to Mac…") {
                if case .project(let id) = self.store.filter { self.store.chooseExportLocation(for: id) }
            },
            .separator(),
            item("Close Window", "w") { self.closeWindow() },
        ]
        return items
    }

    private func editMenu() -> [NSMenuItem] {
        let hasSelection = !store.selection.isEmpty
        return [
            item("Undo", "z") { self.text(Selector(("undo:"))) { self.store.undo() } },
            item("Redo", "z", [.command, .shift]) { self.text(Selector(("redo:"))) { self.store.redo() } },
            .separator(),
            item("Cut", "x") { _ = NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) },
            item("Copy", "c") { self.text(#selector(NSText.copy(_:))) { self.store.copySelection() } },
            item("Paste", "v") {
                if self.editingText { _ = NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
                else if !self.store.ingest(.general, into: self.store.currentPlace) { NSSound.beep() }
            },
            item("Select All", "a") { self.text(#selector(NSText.selectAll(_:))) { self.store.selectAll() } },
            .separator(),
            item("Rename", enabled: store.selection.count == 1 || (store.connectedView != nil && ConnectedSelection.shared.paths.count == 1)) {
                if self.store.connectedView != nil, let path = ConnectedSelection.shared.paths.first { ConnectedEditor.shared.renamingPath = path } else { self.store.renameSelection() }
            },
            item("Get Info", "i", enabled: hasSelection) { self.app.showInfo(for: self.store.selection) },
            item(store.connectedView != nil ? "Move to Trash" : "Delete", "\u{8}", enabled: hasSelection || !ConnectedSelection.shared.paths.isEmpty) {
                if self.store.connectedView != nil { ConnectedEditor.shared.trash(ConnectedSelection.shared.selectedURLs) }
                else { self.store.requestDelete(self.store.selection) }
            },
            .separator(),
            item("Recently Deleted…") { self.store.showingRecentlyDeleted = true },
        ]
    }

    private func viewMenu() -> [NSMenuItem] {
        let layout = UserDefaults.standard.string(forKey: BoardLayout.key) ?? BoardLayout.icons.rawValue
        let sort = BoardSort.current
        let sidebar = UserDefaults.standard.object(forKey: "window.sidebar") as? Bool ?? true
        return [
            item("as Icons", "1", [.command, .control], checked: layout == BoardLayout.icons.rawValue) {
                UserDefaults.standard.set(BoardLayout.icons.rawValue, forKey: BoardLayout.key)
            },
            item("as List", "2", [.command, .control], checked: layout == BoardLayout.list.rawValue) {
                UserDefaults.standard.set(BoardLayout.list.rawValue, forKey: BoardLayout.key)
            },
            submenu("Arrange By", BoardSort.allCases.map { option in
                item(option.title, checked: sort == option) { self.store.arrange(by: option) }
            }),
            .separator(),
            item(sidebar ? "Hide Sidebar" : "Show Sidebar", "s", [.command, .control], enabled: mode == .window) {
                UserDefaults.standard.set(!sidebar, forKey: "window.sidebar")
            },
            .separator(),
            item("Zoom In", "+", enabled: mode == .floating) { CanvasStore.shared.zoom(by: 1.25) },
            item("Zoom Out", "-", enabled: mode == .floating) { CanvasStore.shared.zoom(by: 1 / 1.25) },
            item("Show Everything", "0", enabled: mode == .floating) { CanvasStore.shared.fitAll() },
            item("Clear Frame", enabled: mode == .floating && !CanvasStore.shared.items.isEmpty) { CanvasStore.shared.clear() },
            .separator(),
            // The magic tools are for full screen only.
            item("Organize Into Folders", "o", [.command, .option], enabled: mode == .window && !store.showingRecent) { self.store.requestOrganize() },
        ]
    }

    private func goMenu() -> [NSMenuItem] {
        var items: [NSMenuItem] = [
            item("Recent", "0", [.command, .control], checked: store.showingRecent) {
                self.store.showingRecent = true; self.store.libraryView = nil
            },
            item("All Items", checked: !store.showingRecent && store.libraryView == .allItems, enabled: mode == .window) {
                self.store.showingRecent = false; self.store.libraryView = .allItems
            },
            .separator(),
        ]
        for (index, project) in store.projects.enumerated() {
            let here = !store.showingRecent && store.libraryView == nil && store.connectedView == nil && store.filter == .project(project.id)
            items.append(item(project.name, index < 9 ? String(index + 1) : "", [.command, .control], checked: here) {
                self.store.openProject(project.id)
            })
        }
        let connected = ConnectedRegistry.shared.folders
        if !connected.isEmpty {
            items.append(.separator())
            items += connected.map { folder in
                item(folder.name, checked: store.connectedView?.folderID == folder.id) { ConnectedRegistry.shared.open(folder.id) }
            }
        }
        items += [
            .separator(),
            item("Back", "[", enabled: store.openFolderID != nil) { self.store.openFolderID = self.store.openFolder?.parentID },
        ]
        return items
    }

    private func windowMenu() -> [NSMenuItem] {
        [
            item("Pop-up", "1", [.command, .option], checked: mode == .popup) { self.app.collapse() },
            item("Full Screen", "2", [.command, .option], checked: mode == .window) { self.app.expand() },
            item("Frame (on top of every app)", "3", [.command, .option], checked: mode == .floating) { self.app.float() },
            .separator(),
            item(isLocked ? "Unlock Window" : "Lock Window", "l", [.command, .option]) { self.toggleLock() },
            item("Draw Frame…") { self.app.drawFrame(for: self.mode) },
            .separator(),
            item("Close Window", "w") { self.closeWindow() },
        ]
    }

    private func helpMenu() -> [NSMenuItem] {
        [item("Welcome Tour") { WelcomeTour.show() },
         item("What Every Button Does") { self.app.showButtonIndex() }]
    }

    // MARK: Helpers

    private var isLocked: Bool {
        switch mode {
        case .popup: app.isPinned
        case .window: app.isBigLocked
        case .floating: UserDefaults.standard.bool(forKey: AppDelegate.floatingLockedKey)
        }
    }

    private func toggleLock() {
        switch mode {
        case .popup: app.setPinned(!app.isPinned)
        case .window: if app.isBigLocked { app.unlockPanel() } else { app.lockPanel(to: app.panel.frame) }
        case .floating: app.setFloatingLocked(!isLocked)
        }
    }

    private func closeWindow() {
        if let key = NSApp.keyWindow, !(key is StashPanel) { key.performClose(nil); return }
        switch mode {
        case .popup: app.closeCompact()
        case .window: app.hidePanel()
        case .floating: app.hideFloating()
        }
    }
}

/// A menu item that runs a closure.
private final class ActionItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, keyEquivalent: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        target = self
    }

    required init(coder: NSCoder) { fatalError("init(coder:) is not used") }

    @objc private func run() { MainActor.assumeIsolated { handler() } }
}

extension AppDelegate {
    /// Help → What Every Button Does, in its own small window.
    func showButtonIndex() {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520), styleMask: [.titled, .closable, .resizable],
                              backing: .buffered, defer: false)
        window.title = "Swiss — What Every Button Does"
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: ScrollView { ButtonIndex().padding() }.environmentObject(Store.shared))
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }
}
