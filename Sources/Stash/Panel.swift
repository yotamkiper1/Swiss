import AppKit
import Quartz
import Carbon.HIToolbox
import SwiftUI

/// Stash's windows: the movable board, and the compact preview under the menu bar icon.
/// Both are non-activating panels, so they take the keyboard (typing, ⌘V) even while
/// another app stays in front — macOS won't always let a menu bar app activate itself.
final class StashPanel: NSPanel {
    /// The pop-up and the floating frame share the small board (only one of them is ever open).
    let isCompact: Bool
    /// The floating frame: stays above every app, resizable, its board can zoom.
    let isFloating: Bool

    /// Which of Stash's windows this is (WindowGate draws a window's contents only while it's on screen).
    var gateKey: String { isFloating ? "floating" : isCompact ? "popup" : "window" }

    /// Shown or hidden: the contents start or stop following changes. Set before the window appears,
    /// so its first frame already has everything in it.
    override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
        if place != .out { ShownWindows.shared.set(gateKey, shown: true) }
        super.order(place, relativeTo: otherWin)
        if place == .out {
            ShownWindows.shared.set(gateKey, shown: false)
            BoardDrag.shared.cancel() // a drag can't outlive its window (its picture would stay stuck)
            ConnectedDrag.shared.cancel()
        }
    }

    init(contentRect: NSRect, compact: Bool = false, floating: Bool = false) {
        isCompact = compact || floating
        isFloating = floating
        super.init(
            contentRect: contentRect,
            styleMask: compact && !floating
                ? [.borderless, .nonactivatingPanel]
                : [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = compact && !floating ? .popUpMenu : .floating
        becomesKeyOnlyIfNeeded = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if compact && !floating {
            isMovable = false
        } else {
            titleVisibility = .hidden
            titlebarAppearsTransparent = true
            minSize = floating ? NSSize(width: 260, height: 300) : NSSize(width: 460, height: 380)
            [.closeButton, .miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        }
    }

    override var canBecomeKey: Bool { true }

    /// The search box only takes the keyboard when you click it (or press ⌘F) — never on its own,
    /// so typing on the board doesn't land in search by surprise.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        if let field = responder as? NSTextField, field.placeholderString?.hasPrefix("Search") == true {
            let event = NSApp.currentEvent
            let clicked = event?.type == .leftMouseDown && field.bounds.contains(field.convert(event!.locationInWindow, from: nil))
            let commandF = event?.type == .keyDown && event?.modifierFlags.contains(.command) == true
            if !clicked && !commandF { return false }
        }
        return super.makeFirstResponder(responder)
    }

    // Quick Look (Space) asks the key window who supplies the previews.
    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool { true }
    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) { QuickLook.shared.begin(panel) }
    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) { QuickLook.shared.end(panel) }
    override var canBecomeMain: Bool { !isCompact }

    /// Esc stops typing in the notebook, else clears the selection, else closes.
    override func cancelOperation(_ sender: Any?) {
        let store = Store.shared
        if !store.selection.isEmpty {
            store.clearSelection()
        } else if isCompact {
            AppDelegate.shared.closeCompact()
        } else {
            AppDelegate.shared.hidePanel()
        }
    }

    /// Delete, arrows, Space and Return act on the selection (unless you're typing).
    /// Caught here, before SwiftUI, which would otherwise swallow Space and Delete.
    override func sendEvent(_ event: NSEvent) {
        // Where a drag on the board starts, so the thing lands exactly where you let go.
        if event.type == .leftMouseDown {
            Store.shared.dragStart = NSEvent.mouseLocation
            // A click in a Swiss window brings Swiss to the front, so its menus are in the Mac's menu bar.
            // (Things dropped in from other apps don't click, so they never take focus away.)
            if !NSApp.isActive { NSApp.activate() }
        }
        // Clicking anywhere outside a name box being edited saves it, like Finder.
        // Search too: click outside it and typing stops going there until you click it again.
        if event.type == .leftMouseDown || event.type == .rightMouseDown,
           let editor = firstResponder as? NSTextView, let field = editor.delegate as? NSTextField,
           !field.bounds.contains(field.convert(event.locationInWindow, from: nil)) {
            _ = makeFirstResponder(nil)
        }
        if isFloating {
            // The Frame is the canvas: no board, no Recent — its keys and scrolling are the canvas's.
            if event.type == .leftMouseDown {
                CanvasStore.shared.pressTime = event.timestamp
                selectPlayer(at: event) // the click still goes to the player's own controls
            }
            if event.type == .keyDown, !(firstResponder is NSTextView), handleCanvasKey(event) { return }
            if event.type == .scrollWheel, canvasScroll(event) { return }
            super.sendEvent(event)
            return
        }
        if event.type == .keyDown, handleKey(event) { return }
        if [.leftMouseDown, .leftMouseDragged, .leftMouseUp].contains(event.type),
           RecentDrag.shared.handle(event, in: self) || ConnectedDrag.shared.handle(event, in: self)
            || BoardDrag.shared.handle(event, in: self) { return }
        super.sendEvent(event)
    }

    /// Canvas keys: ⌫ deletes what's selected, Esc lets go, arrows nudge it (⇧ further), Return edits a note.
    private func handleCanvasKey(_ event: NSEvent) -> Bool {
        let canvas = CanvasStore.shared
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        let step: Double = event.modifierFlags.contains(.shift) ? 20 : 4
        switch Int(event.keyCode) {
        case kVK_Delete where flags.isEmpty || flags == .command, kVK_ForwardDelete where flags.isEmpty || flags == .command:
            guard !canvas.selection.isEmpty else { return false }
            canvas.delete(canvas.selection)
        case kVK_ANSI_A where flags == .control || flags == .command:
            canvas.selection = Set(canvas.items.map(\.id)) // ⌃A / ⌘A: everything
        case kVK_ANSI_V where flags.isEmpty: canvas.tool = .select
        case kVK_ANSI_H where flags.isEmpty: canvas.tool = .hand
        case kVK_Space where flags.isEmpty:
            // A library row picked (and nothing on the canvas): Space looks at it. Otherwise Space is held to drag around.
            if !event.isARepeat, canvas.selection.isEmpty { _ = CanvasLibraryPick.shared.previewIfPicked() }
            return true
        case kVK_Escape:
            if canvas.selection.isEmpty { return false }
            canvas.selection = []
            canvas.editingID = nil
        case kVK_Return where canvas.selection.count == 1:
            if let id = canvas.selection.first, canvas.items.first(where: { $0.id == id })?.kind == .text { canvas.editingID = id }
        case kVK_ANSI_Equal where !canvas.selection.isEmpty && !flags.contains(.command), kVK_ANSI_KeypadPlus where !canvas.selection.isEmpty:
            canvas.scale(canvas.selection, by: 1.15) // + : bigger
        case kVK_ANSI_Minus where !canvas.selection.isEmpty && !flags.contains(.command), kVK_ANSI_KeypadMinus where !canvas.selection.isEmpty:
            canvas.scale(canvas.selection, by: 1 / 1.15) // − : smaller
        case kVK_LeftArrow where !canvas.selection.isEmpty: canvas.move(canvas.selection, by: CGSize(width: -step, height: 0))
        case kVK_RightArrow where !canvas.selection.isEmpty: canvas.move(canvas.selection, by: CGSize(width: step, height: 0))
        case kVK_UpArrow where !canvas.selection.isEmpty: canvas.move(canvas.selection, by: CGSize(width: 0, height: -step))
        case kVK_DownArrow where !canvas.selection.isEmpty: canvas.move(canvas.selection, by: CGSize(width: 0, height: step))
        default: return false
        }
        return true
    }

    /// A click on a video player selects it (⌘ / ⇧ adds), without taking the click from its controls.
    private func selectPlayer(at event: NSEvent) {
        guard let content = contentView else { return }
        let p = content.convert(event.locationInWindow, from: nil)
        let canvas = CanvasStore.shared
        let point = CGPoint(x: p.x - canvas.viewOrigin.x, y: content.bounds.height - p.y - canvas.viewOrigin.y)
        guard point.y >= 0, point.x >= 0, let player = canvas.items.sorted(by: { $0.z > $1.z })
            .first(where: { canvas.viewFrame($0).contains(point) }), player.kind == .video else { return }
        if event.modifierFlags.contains(.command) || event.modifierFlags.contains(.shift) {
            canvas.selection.insert(player.id)
        } else if !canvas.selection.contains(player.id) {
            canvas.selection = [player.id]
        }
        canvas.editingID = nil
    }

    /// Two-finger scroll moves around the canvas; ⌘-scroll zooms (around the pointer). Players scroll themselves.
    private func canvasScroll(_ event: NSEvent) -> Bool {
        guard let content = contentView else { return false }
        let p = content.convert(event.locationInWindow, from: nil)
        let canvas = CanvasStore.shared
        let point = CGPoint(x: p.x - canvas.viewOrigin.x, y: content.bounds.height - p.y - canvas.viewOrigin.y)
        guard point.y >= 0, point.x >= 0 else { return false } // over the top bar or the library
        if canvas.items.contains(where: { $0.kind == .video && canvas.viewFrame($0).contains(point) }) { return false }
        let dx = event.hasPreciseScrollingDeltas ? event.scrollingDeltaX : event.scrollingDeltaX * 10
        let dy = event.hasPreciseScrollingDeltas ? event.scrollingDeltaY : event.scrollingDeltaY * 10
        if event.modifierFlags.contains(.command) {
            canvas.zoom(by: pow(1.01, dy), around: point)
        } else {
            canvas.panBy(CGSize(width: dx, height: dy))
        }
        return true
    }

    /// Lets BoardDrag hand SwiftUI an event without going through the checks above again.
    func passToSuper(_ event: NSEvent) { super.sendEvent(event) }

    /// Keys in a connected folder: Space looks, Return renames, ⌘↓ opens, ⌫ / ⌘[ / ⌘↑ goes up, ⌘⌫ moves to the Trash,
    /// ⌘C copies the files.
    private func handleConnectedKey(_ event: NSEvent) -> Bool {
        let store = Store.shared, selection = ConnectedSelection.shared
        guard let location = store.connectedView else { return false }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let up = { store.connectedView = ConnectedLocation(folderID: location.folderID,
                                                           subpath: location.subpath.split(separator: "/").dropLast().joined(separator: "/")) }
        switch Int(event.keyCode) {
        case kVK_Space where flags.isEmpty:
            QuickLook.shared.show(selection.selectedURLs.filter { url in !(selection.entries.first { $0.url == url }?.isFolder ?? false) })
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // Return renames (like Finder); double-click or ⌘↓ opens.
            if selection.paths.count == 1, let path = selection.paths.first { ConnectedEditor.shared.renamingPath = path } else { openSelected(store, selection, location) }
            return true
        case kVK_Delete where flags == .command, kVK_ForwardDelete where flags == .command:
            ConnectedEditor.shared.trash(selection.selectedURLs) // ⌘⌫: Move to Trash
            return true
        case kVK_ANSI_C where flags == .command:
            guard !selection.selectedURLs.isEmpty else { return false }
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(selection.selectedURLs as [NSURL])
            store.flash("Copied")
            return true
        case kVK_DownArrow where flags == .command:
            openSelected(store, selection, location)
            return true
        case kVK_Delete where flags.isEmpty, kVK_UpArrow where flags == .command, kVK_ANSI_LeftBracket where flags == .command:
            if !location.subpath.isEmpty { up() }
            return true
        case kVK_ANSI_A where flags == .command:
            selection.paths = Set(selection.entries.map(\.url.path))
            return true
        default:
            return false
        }
    }

    private func openSelected(_ store: Store, _ selection: ConnectedSelection, _ location: ConnectedLocation) {
        let chosen = selection.entries.filter { selection.paths.contains($0.url.path) }
        if chosen.count == 1, let only = chosen.first, only.isFolder {
            let name = only.url.lastPathComponent
            store.connectedView = ConnectedLocation(folderID: location.folderID, subpath: location.subpath.isEmpty ? name : location.subpath + "/" + name)
        } else {
            chosen.filter { !$0.isFolder }.forEach { Safety.open($0.url) }
        }
    }

    /// Keys in the Recent tab: ↑↓ move, Space looks, Return or ⌘K keeps, ⌘⌫/⌫ removes, ⌘C copies again, ⌘A selects all.
    private func handleRecentKey(_ event: NSEvent) -> Bool {
        let recent = RecentStore.shared
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let ids = recent.items.map(\.id)
        let current = recent.cursor.flatMap { c in ids.firstIndex(of: c) } ?? recent.items.firstIndex { recent.selection.contains($0.id) }
        if Shortcut.keep.combo?.matches(event) == true { // ⌘K, or what you set in Settings → Shortcuts
            recent.keepOrAsk(recent.selection)
            return true
        }
        switch Int(event.keyCode) {
        case kVK_DownArrow, kVK_UpArrow:
            guard !ids.isEmpty else { return true }
            let step = event.keyCode == UInt16(kVK_DownArrow) ? 1 : -1
            let next = current.map { min(max($0 + step, 0), ids.count - 1) } ?? 0
            if flags.contains(.shift) { recent.selection.insert(ids[next]) } else { recent.selection = [ids[next]] }
            recent.cursor = ids[next] // the list scrolls to keep it in sight
            return true
        case kVK_Space:
            RecentQuickLook.show(recent.items.filter { recent.selection.contains($0.id) })
            return true
        case kVK_Return, kVK_ANSI_KeypadEnter:
            recent.keepOrAsk(recent.selection)
            return true
        case kVK_Delete, kVK_ForwardDelete:
            recent.remove(recent.selection)
            return true
        case kVK_ANSI_C where flags == .command:
            if let first = recent.items.first(where: { recent.selection.contains($0.id) }) { recent.copyAgain(first) }
            return true
        case kVK_ANSI_A where flags == .command || flags == .control: // ⌘A / ⌃A: everything in Recent
            recent.selection = Set(ids)
            return true
        default:
            return false
        }
    }

    /// 1–9 from the number row or the keypad (works whatever the keyboard layout or modifiers).
    static func digit(_ code: UInt16) -> Int? {
        let row: [Int: Int] = [kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5, kVK_ANSI_6: 6,
                               kVK_ANSI_7: 7, kVK_ANSI_8: 8, kVK_ANSI_9: 9, kVK_ANSI_Keypad1: 1, kVK_ANSI_Keypad2: 2,
                               kVK_ANSI_Keypad3: 3, kVK_ANSI_Keypad4: 4, kVK_ANSI_Keypad5: 5, kVK_ANSI_Keypad6: 6,
                               kVK_ANSI_Keypad7: 7, kVK_ANSI_Keypad8: 8, kVK_ANSI_Keypad9: 9]
        return row[Int(code)]
    }

    private func handleKey(_ event: NSEvent) -> Bool {
        let store = Store.shared
        if store.showingRecent, !(firstResponder is NSTextView) { return handleRecentKey(event) }
        if store.connectedView != nil, !(firstResponder is NSTextView) { return handleConnectedKey(event) }
        let typing = firstResponder is NSTextView
        let busy = store.renamingProjectID != nil || store.renamingFolderID != nil || store.renamingItemID != nil || store.composingNote || store.organizePrompt != nil || store.pendingDelete != nil || store.pendingProjectDelete != nil || store.linkCleanup != nil || store.pendingBatchRename != nil
        let flags = event.modifierFlags.intersection([.command, .option, .control])
        guard !typing, !busy else { return false }
        if flags == .command, Int(event.keyCode) == kVK_Delete || Int(event.keyCode) == kVK_ForwardDelete {
            guard !store.selection.isEmpty else { return false }
            store.requestDelete(store.selection) // ⌘⌫ deletes what's selected
            return true
        }
        if flags == .command, Int(event.keyCode) == kVK_DownArrow {
            store.openSelection() // ⌘↓ opens, like Finder
            return true
        }
        if flags.isEmpty, !event.modifierFlags.contains(.shift), Int(event.keyCode) == kVK_Tab, let open = store.openFolder {
            store.openFolderID = open.parentID // Tab: back up to the folder holding this one
            return true
        }
        if flags == .control, Int(event.keyCode) == kVK_ANSI_A {
            store.selectAll() // ⌃A, like ⌘A
            return true
        }
        if flags == .control, Int(event.keyCode) == kVK_Tab {
            store.stepTab(event.modifierFlags.contains(.shift) ? -1 : 1) // ⌃Tab / ⌃⇧Tab: next / previous project tab, like a browser
            return true
        }
        // ⌥1–⌥9: put what's selected (or being dragged) into the folder with that number.
        if flags == .option, let n = Self.digit(event.keyCode) {
            BoardDrag.shared.cancelForKeyboardMove()
            store.putSelection(intoFolderNumber: n)
            return true
        }
        guard flags.isEmpty else { return false }
        let shift = event.modifierFlags.contains(.shift)
        switch Int(event.keyCode) {
        case kVK_Delete, kVK_ForwardDelete:
            // Delete on its own: back up to the folder holding this one. (⌘⌫ deletes, like the Mac.)
            guard let open = store.openFolder else { return false }
            store.openFolderID = open.parentID
        case kVK_LeftArrow: store.moveSelection(.left, extend: shift, compact: isCompact)
        case kVK_RightArrow: store.moveSelection(.right, extend: shift, compact: isCompact)
        case kVK_UpArrow: store.moveSelection(.up, extend: shift, compact: isCompact)
        case kVK_DownArrow: store.moveSelection(.down, extend: shift, compact: isCompact)
        case kVK_Space:
            // Space opens a folder, or a note for editing (like double-clicking them); anything else gets Quick Look.
            if store.selection.count == 1, case .folder(let id)? = store.selection.first {
                withAnimation(.spring(duration: 0.3)) { store.openFolderID = id }
            } else if store.selection.count == 1, case .item(let id)? = store.selection.first,
               store.items.first(where: { $0.id == id })?.kind == .text {
                store.renamingItemID = id // a note's card turns this into editing
            } else {
                QuickLook.shared.toggle() // the real macOS Quick Look
            }
        case kVK_Return:
            // Return renames (like Finder); double-click or ⌘↓ opens.
            guard store.selection.count == 1 else { return false }
            store.renameSelection()
        default:
            // 1–9: open the folders on the board, in order (each folder shows its number).
            guard !shift, let key = event.charactersIgnoringModifiers?.first, let n = key.wholeNumberValue, n >= 1 else { return false }
            store.openFolder(number: n)
        }
        return true
    }
}

/// Wraps a SwiftUI view: accepts drops from other apps, saves the clipboard on ⌘V, closes on Esc.
final class DropView: NSView {
    var onCancel: (() -> Void)?

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes(Store.acceptedTypes)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func cancelOperation(_ sender: Any?) {
        onCancel?()
    }

    /// ⌘V saves whatever is on the clipboard, unless you're in the middle of typing.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let typing = (window?.firstResponder as? NSTextView) != nil
        if isCanvas, flags.subtracting(.shift) == .command, !typing, let key = event.charactersIgnoringModifiers?.lowercased() {
            let canvas = CanvasStore.shared
            switch key {
            case "v": if !canvas.ingest(.general) { NSSound.beep() }; return true
            case "c": canvas.copySelection(); return true
            case "a": canvas.selection = Set(canvas.items.map(\.id)); return true
            case "z": // ⌘Z undoes the last change on the canvas, ⇧⌘Z redoes it
                let done = flags.contains(.shift) ? canvas.redo() : canvas.undo()
                if !done { NSSound.beep() }
                return true
            case "=", "+": canvas.zoom(by: 1.25); return true
            case "-": canvas.zoom(by: 1 / 1.25); return true
            case "0": canvas.fitAll(); return true
            case "1", "n": canvas.newNote(); return true
            case ",": AppDelegate.shared.showSettings(); return true
            default: break
            }
        }
        // ⌘Z / Ctrl Z undo, ⌘⇧Z / Ctrl ⇧Z redo (text fields keep their own undo while typing).
        if event.charactersIgnoringModifiers?.lowercased() == "z", !typing || flags.contains(.control) {
            let base = flags.subtracting(.shift)
            if base == .command || base == .control {
                if flags.contains(.shift) { Store.shared.redo() } else { Store.shared.undo() }
                return true
            }
        }
        // ⌘1–⌘6: New Note, New Folder, Linker, PhotoBook, Notepad, Files.
        if flags == .command, !typing, let key = event.charactersIgnoringModifiers?.first,
           let action = QuickAction.allCases.first(where: { $0.key == key }) {
            Store.shared.perform(action)
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "," {
            AppDelegate.shared.showSettings()
            return true
        }
        // ⌘C: copy what's selected — a note's text, a link, a picture or file.
        if flags == .command, event.charactersIgnoringModifiers == "c", !typing, !Store.shared.selection.isEmpty {
            Store.shared.copySelection()
            return true
        }
        // ⌘I: Get Info on what's selected.
        if flags == .command, event.charactersIgnoringModifiers == "i", !typing, !Store.shared.selection.isEmpty {
            AppDelegate.shared.showInfo(for: Store.shared.selection)
            return true
        }
        if flags == .command, event.charactersIgnoringModifiers == "a", !typing {
            Store.shared.selectAll()
            return true
        }
        guard flags == .command, event.charactersIgnoringModifiers == "v" else {
            return super.performKeyEquivalent(with: event)
        }
        if let editor = window?.firstResponder as? NSTextView, !editor.string.isEmpty {
            return super.performKeyEquivalent(with: event)
        }
        let store = Store.shared
        if store.connectedView != nil, !store.showingRecent {
            if !ConnectedEditor.shared.ingest(.general) { NSSound.beep() } // ⌘V: into the real folder
            return true
        }
        if SwissClipboard.isCurrent {
            // Copied in Swiss: copies of the cards and folders, right here (numbered if the name is taken).
            if store.canCreateHere { store.pasteCopies(into: store.currentPlace) } else { NSSound.beep() }
        } else if store.clipboardHint != nil {
            store.saveClipboardHint() // into the folder Stash picked for what you copied
        } else if !store.ingest(.general, into: store.currentPlace) {
            NSSound.beep()
        }
        return true
    }

    private var isCompact: Bool { (window as? StashPanel)?.isCompact ?? false }

    /// The folder (tile, row, Back arrow or path part) under the cursor, if any.
    /// A folder being dragged can't drop onto itself or anything inside it.
    private func folder(at info: NSDraggingInfo) -> UUID? {
        let store = Store.shared
        let p = convert(info.draggingLocation, from: nil)
        let point = CGPoint(x: p.x, y: bounds.height - p.y) // SwiftUI frames are top-left based
        let frames = store.folderFrames[isCompact] ?? [:]
        let blocked = info.draggingSource != nil ? store.draggingFolderID.map { store.withDescendants([$0]) } ?? [] : []
        return frames
            .filter { $0.value.contains(point) && !blocked.contains($0.key) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }

    /// Icons view: a card or folder let go on empty board space stays right there.
    private func movesOnBoard(_ info: NSDraggingInfo) -> Bool {
        let store = Store.shared
        guard info.draggingSource != nil, !store.isSearching,
              UserDefaults.standard.string(forKey: BoardLayout.key) != BoardLayout.list.rawValue,
              let viewport = store.boardViewports[isCompact] else { return false }
        let p = convert(info.draggingLocation, from: nil)
        return viewport.contains(CGPoint(x: p.x, y: bounds.height - p.y))
    }

    /// Things from other apps can drop anywhere (or onto a folder).
    /// Cards dragged within Stash drop onto a folder, or move to where you let go.
    /// A folder dropped on the sidebar's Connected heading connects it (it's not copied anywhere).
    private func overConnectHeading(_ info: NSDraggingInfo) -> [URL]? {
        guard info.draggingSource == nil, let frame = Store.shared.connectDropFrame else { return nil }
        let p = convert(info.draggingLocation, from: nil)
        guard frame.insetBy(dx: -4, dy: -6).contains(CGPoint(x: p.x, y: bounds.height - p.y)) else { return nil }
        let urls = (info.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        return folders.isEmpty ? nil : folders
    }

    /// The project tab (or sidebar project) under the drag.
    private func project(at info: NSDraggingInfo) -> UUID? {
        let p = convert(info.draggingLocation, from: nil)
        return Store.shared.project(at: CGPoint(x: p.x, y: bounds.height - p.y))
    }

    private var isCanvas: Bool { (window as? StashPanel)?.isFloating == true }

    /// Where a drop lands on the canvas.
    private func canvasPoint(_ info: NSDraggingInfo) -> CGPoint {
        let p = convert(info.draggingLocation, from: nil)
        let canvas = CanvasStore.shared
        return canvas.canvasPoint(CGPoint(x: p.x - canvas.viewOrigin.x, y: bounds.height - p.y - canvas.viewOrigin.y))
    }

    private func update(_ info: NSDraggingInfo) -> NSDragOperation {
        if isCanvas { return .copy } // anything can go on the canvas
        let store = Store.shared
        // Over a project tab: things go into that project.
        let overProject = project(at: info)
        if store.dropProjectID != overProject { store.dropProjectID = overProject }
        if overProject != nil {
            if store.isDropTargeted { store.isDropTargeted = false }
            if store.dropFolderID != nil { store.dropFolderID = nil }
            return info.draggingSource == nil || info.draggingSource is RecentDrag ? .copy : .move
        }
        if info.draggingSource is RecentDrag { return [] } // from Recent: only onto a project
        if store.connectedView != nil, !store.showingRecent { return .copy }
        let connecting = overConnectHeading(info) != nil
        if store.connectDropTargeted != connecting { store.connectDropTargeted = connecting }
        if connecting { if store.isDropTargeted { store.isDropTargeted = false }; return .link }
        let target = folder(at: info)
        if store.dropFolderID != target { store.dropFolderID = target }
        let external = info.draggingSource == nil
        let showOverlay = external && target == nil
        if store.isDropTargeted != showOverlay { store.isDropTargeted = showOverlay }
        if external || target != nil { return .copy }
        guard movesOnBoard(info) else { return [] }
        let mask = info.draggingSourceOperationMask
        return mask.contains(.move) ? .move : mask.contains(.generic) ? .generic : .copy
    }

    private func reset() {
        Store.shared.dropProjectID = nil
        Store.shared.connectDropTargeted = false
        Store.shared.isDropTargeted = false
        Store.shared.dropFolderID = nil
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }

    override func draggingExited(_ sender: NSDraggingInfo?) { reset() }

    override func draggingEnded(_ sender: NSDraggingInfo) { reset() }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        if isCanvas { return CanvasStore.shared.ingest(sender.draggingPasteboard, at: canvasPoint(sender)) }
        let store = Store.shared
        if let folders = overConnectHeading(sender) {
            store.connectDropTargeted = false
            var last: ConnectedFolder?
            for url in folders { last = ConnectedRegistry.shared.connect(url) }
            if let last { ConnectedRegistry.shared.open(last.id) }
            store.flash(folders.count == 1 ? "Connected \(folders[0].lastPathComponent)" : "Connected \(folders.count) folders")
            return true
        }
        if let project = project(at: sender) {
            reset()
            if sender.draggingSource is RecentDrag { return RecentDrag.shared.drop(onProject: project) }
            if sender.draggingSource != nil {
                // A card or folder from the board (List view): it, and the rest of the selection, go to that project.
                let dragged: Selectable? = store.draggingFolderID.map { .folder($0) } ?? store.draggingItemID.map { .item($0) }
                guard let dragged else { return false }
                store.moveToProject(store.selection.contains(dragged) ? store.selection : [dragged], project: project)
                store.draggingItemID = nil
                store.draggingFolderID = nil
                return true
            }
            return store.ingest(sender.draggingPasteboard, into: Place(project: project))
        }
        if sender.draggingSource is RecentDrag { reset(); return false }
        if store.connectedView != nil, !store.showingRecent {
            // Into the real folder (or the folder tile under the pointer): copied in, or moved if it came from here.
            reset()
            let p = convert(sender.draggingLocation, from: nil)
            let dir = ConnectedDrag.shared.folder(at: CGPoint(x: p.x, y: bounds.height - p.y)).map { URL(fileURLWithPath: $0, isDirectory: true) }
            if sender.draggingSource is ConnectedDrag, let dir {
                let urls = (sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL]) ?? []
                ConnectedEditor.shared.move(urls, into: dir)
                return true
            }
            return ConnectedEditor.shared.ingest(sender.draggingPasteboard, into: dir)
        }
        let target = folder(at: sender)
        reset()
        let destination = target == Store.boardDropID ? nil : target
        if sender.draggingSource != nil {
            // A card or folder from inside Stash: into the folder (or out, via Back / the path).
            let dragged: Selectable? = store.draggingFolderID.map { .folder($0) } ?? store.draggingItemID.map { .item($0) }
            guard let dragged else { return false }
            if target == nil {
                // Let go on empty space: it (and the rest of the selection) moves there.
                guard movesOnBoard(sender), let start = store.dragStart, let window else { return false }
                let from = window.convertPoint(fromScreen: start)
                let zoom = isCompact ? store.boardZoom : 1
                let delta = CGSize(width: (sender.draggingLocation.x - from.x) / zoom, height: (from.y - sender.draggingLocation.y) / zoom)
                store.moveOnBoard(store.selection.contains(dragged) ? store.selection : [dragged], by: delta, compact: isCompact)
                store.draggingItemID = nil
                store.draggingFolderID = nil
                return true
            }
            // Dragging one of several selected things moves them all.
            var moving = store.selection.contains(dragged) ? store.selection : [dragged]
            if let destination { moving.remove(.folder(destination)) }
            store.put(moving, into: destination)
            store.draggingItemID = nil
            store.draggingFolderID = nil
            return true
        }
        let place: Place
        if target == Store.boardDropID {
            place = Place(project: store.currentPlace.project)
        } else {
            place = destination.flatMap(store.folder).map { Place(project: $0.projectID, folder: $0.id) } ?? store.currentPlace
        }
        return store.ingest(sender.draggingPasteboard, into: place)
    }
}


/// Which Stash windows are on screen. A hidden window's SwiftUI contents would otherwise keep redrawing on
/// every change (three boards for one), so hidden ones draw nothing until they're shown again.
@MainActor
final class ShownWindows: ObservableObject {
    static let shared = ShownWindows()
    @Published private(set) var shown: Set<String> = []

    func set(_ key: String, shown on: Bool) {
        if on, !shown.contains(key) { shown.insert(key) }
        if !on, shown.contains(key) { shown.remove(key) }
    }
}

struct WindowGate<Content: View>: View {
    @ObservedObject private var windows = ShownWindows.shared
    let key: String
    let content: () -> Content

    init(key: String, @ViewBuilder content: @escaping () -> Content) {
        self.key = key
        self.content = content
    }

    var body: some View {
        if windows.shown.contains(key) { content() } else { Color.clear }
    }
}
