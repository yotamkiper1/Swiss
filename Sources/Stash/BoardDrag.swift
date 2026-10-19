import AppKit
import SwiftUI

/// Finder-style dragging in Icons view, handled before SwiftUI sees the mouse:
/// press on a card or folder and it moves with the pointer straight away (selected or not).
/// Let go on a folder to put it inside, on empty space to leave it there, or drag it out of the
/// window to hand a copy to another app. Press, hold and let go without moving renames.
/// What's being dragged on the board. Kept out of Store on purpose: the board and its cards don't redraw while you
/// drag — only the dragged tiles follow the pointer.
@MainActor final class DragSelection: ObservableObject {
    static let shared = DragSelection()
    @Published var ids: Set<Selectable> = []
}

/// How far the drag has gone (top-left based). Nothing on the board watches it: the moving picture is an AppKit
/// view, so a mouse move costs almost nothing however big the board is.
@MainActor final class DragOffset {
    static let shared = DragOffset()
    var value: CGSize = .zero
}

@MainActor
final class BoardDrag: NSObject, NSDraggingSource {
    static let shared = BoardDrag()

    private var downPoint: NSPoint = .zero // window coordinates (bottom-left based)
    private var downTime: TimeInterval = 0
    private var target: Selectable?
    private var compact = false
    private var startFrames: [Selectable: CGRect] = [:]
    private var moving: Set<Selectable> = []
    private var active = false
    /// The picture of the dragged tiles that follows the pointer (like Finder's drag image).
    private var ghost: NSImageView?
    private var ghostOrigin: NSPoint = .zero

    private var store: Store { Store.shared }

    /// True when the event was used here and shouldn't go on to SwiftUI.
    func handle(_ event: NSEvent, in window: StashPanel) -> Bool {
        switch event.type {
        case .leftMouseDown:
            reset()
            guard event.clickCount == 1, let hit = hitTarget(event, in: window) else { return false }
            target = hit
            compact = window.isCompact
            downPoint = event.locationInWindow
            downTime = event.timestamp
            return false
        case .leftMouseDragged:
            guard let target else { return false }
            let dx = event.locationInWindow.x - downPoint.x, dy = event.locationInWindow.y - downPoint.y
            if !active {
                guard hypot(dx, dy) >= 3 else { return true }
                begin(with: target, in: window)
            }
            if let content = window.contentView, !content.bounds.insetBy(dx: -2, dy: -2).contains(content.convert(event.locationInWindow, from: nil)) {
                handOff(event, in: window) // out of the window: becomes a normal drag to other apps
                return true
            }
            let zoom = compact ? store.boardZoom : 1
            DragOffset.shared.value = CGSize(width: dx / zoom, height: -dy / zoom) // board units
            ghost?.setFrameOrigin(NSPoint(x: ghostOrigin.x + dx, y: ghostOrigin.y + dy))
            let overProject = topLeft(event, in: window).flatMap(store.project(at:))
            let over = overProject == nil ? folder(under: event, in: window) : nil
            if store.dropFolderID != over { store.dropFolderID = over }
            if store.dropProjectID != overProject { store.dropProjectID = overProject }
            return true
        case .leftMouseUp:
            guard let target else { return false }
            defer { reset() }
            if !active {
                // Press, hold, let go: rename (notes open for editing).
                if event.timestamp - downTime >= 0.6, event.modifierFlags.intersection([.command, .shift]).isEmpty {
                    DispatchQueue.main.async { [store] in
                        switch target {
                        case .item(let id): store.renamingItemID = id
                        case .folder(let id): store.renamingFolderID = id
                        }
                    }
                }
                return false
            }
            finish(event, in: window)
            // SwiftUI still gets a mouse-up (so it isn't left waiting), but far away, so no button or tap fires.
            if let away = NSEvent.mouseEvent(with: .leftMouseUp, location: NSPoint(x: -10_000, y: -10_000), modifierFlags: [],
                                             timestamp: event.timestamp, windowNumber: event.windowNumber, context: nil,
                                             eventNumber: event.eventNumber, clickCount: 1, pressure: 0) {
                window.passToSuper(away)
            }
            return true
        default:
            return false
        }
    }

    // MARK: Steps

    /// The card or folder under the mouse, if dragging is possible here (Icons view, not searching).
    private func hitTarget(_ event: NSEvent, in window: StashPanel) -> Selectable? {
        guard !store.isSearching, !store.showingRecent, store.libraryView == nil, store.connectedView == nil,
              UserDefaults.standard.string(forKey: BoardLayout.key) != BoardLayout.list.rawValue,
              let p = topLeft(event, in: window),
              let viewport = store.boardViewports[window.isCompact], viewport.contains(p),
              let origin = store.boardContentOrigins[window.isCompact] else { return nil }
        let zoom = window.isCompact ? store.boardZoom : 1
        let point = CGPoint(x: (p.x - origin.x) / zoom, y: (p.y - origin.y) / zoom)
        // The one drawn on top: things later on the board are drawn over earlier ones.
        let frames = store.boardFrames[window.isCompact] ?? [:]
        return store.visibleOrder.last { frames[$0]?.contains(point) == true }
    }

    private func begin(with target: Selectable, in window: NSWindow) {
        // Like Finder: dragging something unselected picks just it; dragging a selected thing takes the whole selection.
        if !store.selection.contains(target) {
            let extend = NSEvent.modifierFlags.contains(.command) || NSEvent.modifierFlags.contains(.shift)
            if extend { store.selection.insert(target) } else { store.selection = [target] }
        }
        moving = store.selection
        startFrames = store.boardFrames[compact] ?? [:]
        store.renamingItemID = nil
        store.renamingFolderID = nil
        showGhost(in: window) // the picture first, before the real tiles dim
        DragSelection.shared.ids = moving
        active = true
    }

    /// Takes a picture of the dragged tiles (each one on its own, nothing in between) and lays it on top.
    private func showGhost(in window: NSWindow) {
        removeGhost()
        guard let content = window.contentView, let origin = store.boardContentOrigins[compact] else { return }
        let viewport = store.boardViewports[compact] ?? content.bounds
        let zoom = compact ? store.boardZoom : 1
        let tiles = moving.compactMap { startFrames[$0] }
            .map { CGRect(x: origin.x + $0.minX * zoom, y: origin.y + $0.minY * zoom, width: $0.width * zoom, height: $0.height * zoom).intersection(viewport) }
            .filter { !$0.isEmpty }
        guard var union = tiles.first else { return }
        for tile in tiles.dropFirst() { union = union.union(tile) }
        let height = content.bounds.height
        func flipped(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
        let frame = flipped(union)
        let image = NSImage(size: frame.size)
        image.lockFocus()
        for tile in tiles {
            let rect = flipped(tile)
            guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { continue }
            content.cacheDisplay(in: rect, to: rep)
            rep.draw(in: NSRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY, width: rect.width, height: rect.height))
        }
        image.unlockFocus()
        let view = NSImageView(frame: frame)
        view.image = image
        view.imageScaling = .scaleNone
        view.alphaValue = 0.9
        view.wantsLayer = true
        content.addSubview(view, positioned: .above, relativeTo: nil)
        ghost = view
        ghostOrigin = frame.origin
    }

    private func removeGhost() {
        ghost?.removeFromSuperview()
        ghost = nil
    }

    // MARK: Test hooks (Stash Test only)

    func testBegin(_ ids: Set<Selectable>, in window: NSWindow) {
        guard TestMode.isOn, let first = ids.first else { return }
        compact = (window as? StashPanel)?.isCompact ?? false
        store.selection = ids
        begin(with: first, in: window)
    }

    func testMove(dx: CGFloat, dy: CGFloat) {
        guard TestMode.isOn else { return }
        DragOffset.shared.value = CGSize(width: dx, height: -dy)
        ghost?.setFrameOrigin(NSPoint(x: ghostOrigin.x + dx, y: ghostOrigin.y + dy))
    }

    func testEnd() { guard TestMode.isOn else { return }; reset() }

    /// ⌥+number during a drag: the things go straight into that folder, so the drag stops here.
    func cancelForKeyboardMove() {
        guard active else { return }
        reset()
        target = nil
    }

    private func finish(_ event: NSEvent, in window: StashPanel) {
        let overProject = topLeft(event, in: window).flatMap(store.project(at:))
        let over = folder(under: event, in: window)
        let delta = DragOffset.shared.value
        removeGhost()
        DragSelection.shared.ids = []
        DragOffset.shared.value = .zero
        store.dropFolderID = nil
        store.dropProjectID = nil
        if let overProject {
            // Onto a project tab: into that project (on its board).
            store.moveToProject(moving, project: overProject)
        } else if let p = topLeft(event, in: window), let connected = ConnectedTabs.folder(at: p) {
            // Onto a connected folder's tab: out of Swiss, into that real folder.
            store.moveOut(moving, toConnected: connected)
        } else if let over {
            var into = moving
            into.remove(.folder(over))
            store.put(into, into: over == Store.boardDropID ? nil : over)
        } else if let p = topLeft(event, in: window), store.boardViewports[compact]?.contains(p) == true {
            store.moveOnBoard(moving, by: delta, compact: compact, frames: startFrames)
        }
    }

    /// The folder (tile, Back arrow or path part) under the pointer. Never one being dragged, or anything inside it.
    private func folder(under event: NSEvent, in window: StashPanel) -> UUID? {
        guard let p = topLeft(event, in: window) else { return nil }
        let blocked = store.withDescendants(Set(moving.folderIDs))
        return (store.folderFrames[compact] ?? [:])
            .filter { $0.value.contains(p) && !blocked.contains($0.key) }
            .min { $0.value.width * $0.value.height < $1.value.width * $1.value.height }?
            .key
    }

    /// Left the window: carry on as a system drag with copies of the real files (and the text or link).
    private func handOff(_ event: NSEvent, in window: StashPanel) {
        guard let content = window.contentView, let origin = store.boardContentOrigins[compact] else { reset(); return }
        let offset = DragOffset.shared.value
        var dragItems: [NSDraggingItem] = []
        for target in store.visibleOrder where moving.contains(target) {
            guard let writer = pasteboardItem(for: target), let frame = startFrames[target] else { continue }
            // Where it is on screen right now, in the content view's (bottom-left) coordinates.
            let z = compact ? store.boardZoom : 1
            let topLeftRect = CGRect(x: origin.x + (frame.minX + offset.width) * z, y: origin.y + (frame.minY + offset.height) * z,
                                     width: frame.width * z, height: frame.height * z)
            let rect = NSRect(x: topLeftRect.minX, y: content.bounds.height - topLeftRect.maxY,
                              width: topLeftRect.width, height: topLeftRect.height)
            let item = NSDraggingItem(pasteboardWriter: writer)
            item.setDraggingFrame(rect, contents: snapshot(of: rect, in: content))
            dragItems.append(item)
        }
        // Coming back into the window still works: drops onto folders, or onto empty board space.
        if let first = moving.first(where: { startFrames[$0] != nil }) {
            switch first {
            case .item(let id): store.draggingItemID = id; store.draggingFolderID = nil
            case .folder(let id): store.draggingFolderID = id; store.draggingItemID = nil
            }
        }
        DragSelection.shared.ids = []
        DragOffset.shared.value = .zero
        store.dropFolderID = nil
        removeGhost()
        active = false
        target = nil
        guard !dragItems.isEmpty else { return }
        content.beginDraggingSession(with: dragItems, event: event, source: self)
    }

    private func pasteboardItem(for target: Selectable) -> NSPasteboardItem? {
        let item = NSPasteboardItem()
        var any = false
        switch target {
        case .folder(let id):
            if let path = store.mirrorDirs["f:" + id.uuidString] {
                item.setString(Store.visibleCopy(of: store.absolute(path)).absoluteString, forType: .fileURL)
                any = true
            }
        case .item(let id):
            guard let thing = store.items.first(where: { $0.id == id }) else { return nil }
            return store.pasteboardItem(for: thing)
        }
        return any ? item : nil
    }

    private func snapshot(of rect: NSRect, in view: NSView) -> NSImage {
        let image = NSImage(size: rect.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: rect) {
            view.cacheDisplay(in: rect, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    private func topLeft(_ event: NSEvent, in window: NSWindow) -> CGPoint? {
        guard let content = window.contentView else { return nil }
        let p = content.convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: content.bounds.height - p.y)
    }

    private func reset() {
        removeGhost()
        if active {
            DragSelection.shared.ids = []
            DragOffset.shared.value = .zero
            store.dropFolderID = nil
            store.dropProjectID = nil
        }
        target = nil
        active = false
        moving = []
        startFrames = [:]
    }

    // MARK: NSDraggingSource

    /// Other apps get copies (Stash keeps its own); inside Stash it's a move.
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.move, .generic, .copy]
    }
}
