import AppKit
import SwiftUI

extension Store {
    /// Where something of this kind goes when you save it without looking: the project you last had
    /// open (or Not Selected) — inside its Files / PhotoBook / Linker / Notepad folder if there is one.
    func suggestedPlace(for kind: ItemKind?) -> Place {
        let place = currentPlace
        guard let kind else { return place }
        let style = FolderStyle.forKind(kind)
        let project = place.project
        if let open = openFolder {
            if open.style == style { return Place(project: project, folder: open.id) }
            if let inside = folders.first(where: { $0.style == style && $0.projectID == project && $0.parentID == open.id }) {
                return Place(project: project, folder: inside.id)
            }
        }
        if let onBoard = folders.first(where: { $0.style == style && $0.projectID == project && $0.parentID == nil }) {
            return Place(project: project, folder: onBoard.id)
        }
        return place
    }

    func describe(_ place: Place) -> String {
        let project = name(for: place.project)
        guard let folder = place.folder.flatMap(folder) else { return project }
        return "\(project) › \(folder.displayName)"
    }

    /// The quick-save shortcut: saves what's on the clipboard without opening Stash.
    /// Returns where it went, or nil if there was nothing to save.
    @discardableResult
    func quickSave() -> Place? {
        let pb = NSPasteboard.general
        let place = suggestedPlace(for: Self.clipboardKind(pb)?.0)
        guard ingest(pb, into: place) else { return nil }
        return place
    }
}

/// A little "Saved to …" bubble under the menu bar icon, for saves that happen without the window.
@MainActor
final class SavedHUD {
    private var panel: NSPanel?
    private var hide: Task<Void, Never>?

    func show(_ message: String, symbol: String = "checkmark.circle.fill", below iconFrame: NSRect?) {
        let view = NSHostingView(rootView:
            Label(message, systemImage: symbol)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 9)
                .background(.regularMaterial, in: Capsule())
                .fixedSize()
        )
        let size = view.fittingSize
        let panel = self.panel ?? {
            let p = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            p.isOpaque = false
            p.backgroundColor = .clear
            p.hasShadow = true
            p.level = .popUpMenu
            p.ignoresMouseEvents = true
            p.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            self.panel = p
            return p
        }()
        panel.contentView = view
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let anchor = iconFrame ?? NSRect(x: screen.midX, y: screen.maxY, width: 0, height: 0)
        var x = anchor.midX - size.width / 2
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        panel.setFrame(NSRect(x: x, y: anchor.minY - size.height - 8, width: size.width, height: size.height), display: true)
        panel.orderFrontRegardless()
        hide?.cancel()
        hide = Task { [weak panel] in
            try? await Task.sleep(for: .seconds(1.8))
            guard !Task.isCancelled else { return }
            panel?.orderOut(nil)
        }
    }
}
