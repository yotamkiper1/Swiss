import AppKit
import SwiftUI

/// Dragging in a connected folder, like the board's: press a file or folder and its picture follows the pointer.
/// Let go on a folder to move it inside, on the path above to move it back up, on empty space to leave it there,
/// on a project tab to move it into that project, or outside the window to move it there (the Desktop, a Finder
/// folder — ⌥ copies instead, like Finder).
@MainActor
final class ConnectedDrag: NSObject, NSDraggingSource {
    static let shared = ConnectedDrag()

    /// On-screen frames (window, top-left based) of the tiles / rows shown, and which of them are folders.
    var tileFrames: [String: CGRect] = [:]
    var folderPaths: Set<String> = []
    /// The path's parts (subpath → frame), for dragging back up.
    var crumbFrames: [String: CGRect] = [:]
    /// Every tile's frame on the board (board points), and where the board starts in the window.
    var boardFrames: [String: CGRect] = [:]
    var boardOrigin: CGPoint = .zero
    var viewport: CGRect = .zero

    private var pressed: String?
    private var moving: Set<String> = []
    private var downPoint: NSPoint = .zero
    private var active = false
    private var ghost: NSImageView?
    private var ghostOrigin: NSPoint = .zero
    /// Same safety as the board's drag: if the mouse-up never reaches Swiss, the drag and its picture go away.
    private var watchdog: Timer?

    /// The window is closing: any drag in it stops.
    func cancel() { if active || ghost != nil { reset() } }

    func handle(_ event: NSEvent, in window: StashPanel) -> Bool {
        guard Store.shared.connectedView != nil, !Store.shared.showingRecent else { return false }
        switch event.type {
        case .leftMouseDown:
            reset()
            guard event.clickCount == 1, let p = topLeft(event, in: window), let hit = tileFrames.first(where: { $0.value.contains(p) })?.key,
                  ConnectedEditor.shared.renamingPath != hit else { return false }
            pressed = hit
            downPoint = event.locationInWindow
            return false
        case .leftMouseDragged:
            guard let pressed else { return false }
            let dx = event.locationInWindow.x - downPoint.x, dy = event.locationInWindow.y - downPoint.y
            if !active {
                guard hypot(dx, dy) >= 3 else { return true }
                begin(pressed, in: window)
            }
            if let content = window.contentView, !content.bounds.insetBy(dx: -2, dy: -2).contains(content.convert(event.locationInWindow, from: nil)) {
                handOff(event, in: window)
                return true
            }
            ghost?.setFrameOrigin(NSPoint(x: ghostOrigin.x + dx, y: ghostOrigin.y + dy))
            let target = folder(under: event, in: window)
            if ConnectedEditor.shared.dropTargetPath != target { ConnectedEditor.shared.dropTargetPath = target }
            return true
        case .leftMouseUp:
            guard pressed != nil else { return false }
            defer { reset() }
            guard active else { return false }
            finish(event, in: window)
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

    private func begin(_ path: String, in window: NSWindow) {
        let selection = ConnectedSelection.shared
        if !selection.paths.contains(path) { selection.paths = [path] }
        moving = selection.paths
        active = true
        showGhost(in: window)
        watchdog?.invalidate()
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
            MainActor.assumeIsolated {
                let drag = ConnectedDrag.shared
                if NSEvent.pressedMouseButtons & 1 == 0 { drag.cancel(); drag.watchdog?.invalidate(); drag.watchdog = nil }
            }
        }
    }

    /// A folder tile (not one being dragged, nor inside one), or a part of the path above.
    private func folder(under event: NSEvent, in window: NSWindow) -> String? {
        guard let p = topLeft(event, in: window) else { return nil }
        if let crumb = crumbFrames.first(where: { $0.value.insetBy(dx: -3, dy: -3).contains(p) })?.key, let url = crumbURL(crumb) {
            return url.path
        }
        return tileFrames.first { frame in
            folderPaths.contains(frame.key) && frame.value.contains(p)
                && !moving.contains { frame.key == $0 || frame.key.hasPrefix($0 + "/") }
        }?.key
    }

    /// The folder tile at a point (window, top-left based).
    func folder(at p: CGPoint) -> String? {
        tileFrames.first { folderPaths.contains($0.key) && $0.value.contains(p) }?.key
    }

    private func crumbURL(_ subpath: String) -> URL? {
        guard let location = Store.shared.connectedView, let root = ConnectedRegistry.shared.resolve(location.folderID) else { return nil }
        return subpath.isEmpty ? root : root.appendingPathComponent(subpath, isDirectory: true)
    }

    private func finish(_ event: NSEvent, in window: NSWindow) {
        let editor = ConnectedEditor.shared
        let target = folder(under: event, in: window)
        editor.dropTargetPath = nil
        removeGhost()
        let urls = moving.map { URL(fileURLWithPath: $0) }
        if let p = topLeft(event, in: window), let project = Store.shared.project(at: p) {
            Store.shared.moveIntoProject(urls, project: project) // out of the folder, into Swiss
            return
        }
        if let target {
            editor.move(urls, into: URL(fileURLWithPath: target, isDirectory: true))
        } else if let p = topLeft(event, in: window), viewport.contains(p), let dir = editor.currentURL,
                  UserDefaults.standard.string(forKey: BoardLayout.key) != BoardLayout.list.rawValue {
            // Let go on empty space: it stays right there (everything else stays where it is).
            let delta = CGSize(width: event.locationInWindow.x - downPoint.x, height: downPoint.y - event.locationInWindow.y)
            editor.place(moving, by: delta, frames: boardFrames, in: dir)
        }
    }

    /// Left the window: a normal drag to other apps, with the real files (they're copied, never moved).
    private func handOff(_ event: NSEvent, in window: NSWindow) {
        guard let content = window.contentView else { reset(); return }
        var items: [NSDraggingItem] = []
        for path in moving {
            guard let frame = tileFrames[path] else { continue }
            let item = NSPasteboardItem()
            item.setString(URL(fileURLWithPath: path).absoluteString, forType: .fileURL)
            item.setString(path, forType: .string)
            let dragItem = NSDraggingItem(pasteboardWriter: item)
            let rect = NSRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
            dragItem.setDraggingFrame(rect, contents: NSWorkspace.shared.icon(forFile: path))
            items.append(dragItem)
        }
        removeGhost()
        ConnectedEditor.shared.dropTargetPath = nil
        active = false
        pressed = nil
        guard !items.isEmpty else { return }
        content.beginDraggingSession(with: items, event: event, source: self)
    }

    private func showGhost(in window: NSWindow) {
        removeGhost()
        guard let content = window.contentView else { return }
        let rects = moving.compactMap { tileFrames[$0] }
        guard var union = rects.first else { return }
        for r in rects.dropFirst() { union = union.union(r) }
        let height = content.bounds.height
        func flipped(_ r: CGRect) -> NSRect { NSRect(x: r.minX, y: height - r.maxY, width: r.width, height: r.height) }
        let frame = flipped(union)
        let image = NSImage(size: frame.size)
        image.lockFocus()
        for r in rects {
            let rect = flipped(r)
            guard let rep = content.bitmapImageRepForCachingDisplay(in: rect) else { continue }
            content.cacheDisplay(in: rect, to: rep)
            rep.draw(in: NSRect(x: rect.minX - frame.minX, y: rect.minY - frame.minY, width: rect.width, height: rect.height))
        }
        image.unlockFocus()
        let view = NSImageView(frame: frame)
        view.image = image
        view.imageScaling = .scaleNone
        view.alphaValue = 0.85
        content.addSubview(view, positioned: .above, relativeTo: nil)
        ghost = view
        ghostOrigin = frame.origin
    }

    private func removeGhost() {
        ghost?.removeFromSuperview()
        ghost = nil
    }

    private func reset() {
        removeGhost()
        watchdog?.invalidate()
        watchdog = nil
        if active { ConnectedEditor.shared.dropTargetPath = nil }
        pressed = nil
        moving = []
        active = false
    }

    private func topLeft(_ event: NSEvent, in window: NSWindow) -> CGPoint? {
        guard let content = window.contentView else { return nil }
        let p = content.convert(event.locationInWindow, from: nil)
        return CGPoint(x: p.x, y: content.bounds.height - p.y)
    }

    /// Out of Swiss the files move (to the Desktop, a Finder folder…), like dragging them in Finder; hold ⌥ to copy.
    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? [.move, .copy, .generic] : [.move, .copy]
    }
}

struct ConnectedTileFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}

struct ConnectedCrumbFramesKey: PreferenceKey {
    static let defaultValue: [String: CGRect] = [:]
    static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) { value.merge(nextValue()) { $1 } }
}
