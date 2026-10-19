import AppKit
import SwiftUI

// MARK: - Dragging things out of Recent

/// Recent rows drag like board tiles: handled before SwiftUI sees the mouse, so it works in the pop-up and the
/// floating frame too (they never take focus from other apps). Drag out to another app for the real file (linked
/// files: the original), the link or the text — several at once if several are selected. Drop on a project tab
/// (or a project in the sidebar) to keep them there.
@MainActor
final class RecentDrag: NSObject, NSDraggingSource {
    static let shared = RecentDrag()

    /// Each row's frame, in its window's (top-left based) coordinates.
    var frames: [UUID: CGRect] = [:]
    /// The Recent entries in the drag that's going on (for drops inside Stash).
    private(set) var dragging: [UUID] = []
    private var pressed: UUID?
    private var downPoint: NSPoint = .zero
    private var started = false

    func handle(_ event: NSEvent, in window: StashPanel) -> Bool {
        guard Store.shared.showingRecent else { return false }
        switch event.type {
        case .leftMouseDown:
            started = false
            pressed = event.clickCount == 1 ? row(at: event, in: window) : nil
            downPoint = event.locationInWindow
            return false
        case .leftMouseDragged:
            guard let pressed else { return false }
            if started { return true }
            guard hypot(event.locationInWindow.x - downPoint.x, event.locationInWindow.y - downPoint.y) >= 4 else { return true }
            started = true
            begin(pressed, event: event, in: window)
            return true
        case .leftMouseUp:
            let used = started
            pressed = nil
            started = false
            return used
        default:
            return false
        }
    }

    private func row(at event: NSEvent, in window: NSWindow) -> UUID? {
        guard let content = window.contentView else { return nil }
        let p = content.convert(event.locationInWindow, from: nil)
        let point = CGPoint(x: p.x, y: content.bounds.height - p.y)
        return frames.first { $0.value.contains(point) }?.key
    }

    private func begin(_ id: UUID, event: NSEvent, in window: StashPanel) {
        let recent = RecentStore.shared
        let ids = recent.selection.contains(id) ? recent.items.map(\.id).filter(recent.selection.contains) : [id]
        if !recent.selection.contains(id) { recent.selection = [id] }
        guard let content = window.contentView else { return }
        var dragItems: [NSDraggingItem] = []
        for entry in ids.compactMap({ i in recent.items.first { $0.id == i } }) {
            guard let frame = frames[entry.id] else { continue }
            let rect = NSRect(x: frame.minX, y: content.bounds.height - frame.maxY, width: frame.width, height: frame.height)
            for writer in pasteboardItems(for: entry) {
                let item = NSDraggingItem(pasteboardWriter: writer)
                item.setDraggingFrame(rect, contents: snapshot(of: rect, in: content))
                dragItems.append(item)
            }
        }
        guard !dragItems.isEmpty else { return }
        dragging = ids
        Store.shared.draggingItemID = nil
        Store.shared.draggingFolderID = nil
        content.beginDraggingSession(with: dragItems, event: event, source: self)
    }

    /// One entry → what goes on the drag: one item per file, or its picture, link or text.
    func pasteboardItems(for entry: RecentItem) -> [NSPasteboardItem] {
        let store = Store.shared
        if let id = entry.itemID, let saved = store.items.first(where: { $0.id == id }) {
            return store.pasteboardItem(for: saved).map { [$0] } ?? []
        }
        switch entry.kind {
        case .files:
            return entry.fileURLs.filter { FileManager.default.fileExists(atPath: $0.path) }.map { url in
                let item = NSPasteboardItem()
                item.setString(Store.handOut(url).absoluteString, forType: .fileURL)
                return item
            }
        case .screenshot, .image:
            guard let url = RecentStore.shared.fileURL(entry) else { return [] }
            let item = NSPasteboardItem()
            item.setString(Store.handOut(url).absoluteString, forType: .fileURL)
            return [item]
        case .link:
            let item = NSPasteboardItem()
            if let text = entry.text { item.setString(text, forType: .URL); item.setString(text, forType: .string) }
            return [item]
        case .text:
            let item = NSPasteboardItem()
            item.setString(entry.text ?? "", forType: .string)
            return [item]
        }
    }

    private func snapshot(of rect: NSRect, in view: NSView) -> NSImage {
        let image = NSImage(size: rect.size)
        if let rep = view.bitmapImageRepForCachingDisplay(in: rect) {
            view.cacheDisplay(in: rect, to: rep)
            image.addRepresentation(rep)
        }
        return image
    }

    /// Dropped inside Stash: onto a project → kept there. Anywhere else inside Stash: nothing happens.
    func drop(onProject project: UUID) -> Bool {
        let ids = Set(dragging)
        dragging = []
        guard !ids.isEmpty else { return false }
        let recent = RecentStore.shared
        let store = Store.shared
        // Things already in a project move to this one; the rest are kept there.
        let saved = recent.items.filter { ids.contains($0.id) }.compactMap(\.itemID)
        if !saved.isEmpty { store.moveToProject(Set(saved.map { Selectable.item($0) }), project: project) }
        recent.keep(ids, in: Place(project: project))
        store.flash("Kept in \(store.projects.first { $0.id == project }?.name ?? "the project")")
        return true
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy // other apps always get copies; Recent keeps its things
    }

    nonisolated func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        DispatchQueue.main.async { MainActor.assumeIsolated { RecentDrag.shared.dragging = [] } }
    }
}

extension Store {
    /// The project tab / sidebar project at this point of the window (top-left based), if any.
    func project(at point: CGPoint) -> UUID? {
        projectDropFrames.first { $0.value.insetBy(dx: -2, dy: -3).contains(point) }?.key
    }
}

struct RecentFramesKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

/// Where each project tab / sidebar project is on screen (window coordinates, top-left based), for dropping onto it.
struct ProjectDropKey: PreferenceKey {
    static let defaultValue: [UUID: CGRect] = [:]
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) { value.merge(nextValue()) { $1 } }
}

extension View {
    /// This view is a project you can drop things onto (it lights up while something's over it).
    func projectDropTarget(_ id: UUID?) -> some View {
        modifier(ProjectDropTarget(id: id))
    }
}

private struct ProjectDropTarget: ViewModifier {
    @EnvironmentObject var store: Store
    let id: UUID?

    func body(content: Content) -> some View {
        if let id {
            content
                .background(GeometryReader { Color.clear.preference(key: ProjectDropKey.self, value: [id: $0.frame(in: .global)]) })
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Color.accentColor, lineWidth: 2)
                        .opacity(store.dropProjectID == id ? 1 : 0)
                )
        } else {
            content
        }
    }
}
