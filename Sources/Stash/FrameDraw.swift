import AppKit
import SwiftUI

// MARK: - Draw the big window's frame

/// Big window: draw a box anywhere on screen and the window snaps to exactly that frame, then stays
/// locked there (no edge-dragging or moving) until you draw a new one or unlock it.
@MainActor
final class FrameDrawer {
    static let shared = FrameDrawer()
    static let lockedKey = "panel.lockedFrame"
    static let minSize = NSSize(width: 460, height: 380)

    private var overlays: [NSWindow] = []
    private var target: WindowMode = .window

    /// Covers every screen with a dimmed layer you draw on. Esc cancels.
    func start(target: WindowMode = .window) {
        guard overlays.isEmpty else { return }
        self.target = target
        let app = AppDelegate.shared!
        switch target {
        case .window: app.panel.orderOut(nil)
        case .popup: app.compact.orderOut(nil)
        case .floating: app.floating.orderOut(nil)
        }
        for screen in NSScreen.screens {
            let window = OverlayWindow(contentRect: screen.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.level = .screenSaver
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            window.isReleasedWhenClosed = false
            let view = FrameDrawView(frame: NSRect(origin: .zero, size: screen.frame.size))
            view.onDone = { [weak self] rect in self?.finish(rect) }
            window.contentView = view
            window.setFrame(screen.frame, display: true)
            window.orderFrontRegardless()
            overlays.append(window)
        }
        // The screen under the mouse takes the keyboard (for Esc).
        let mouse = NSEvent.mouseLocation
        let first = overlays.first { $0.frame.contains(mouse) } ?? overlays.first
        first?.makeKey()
        first?.makeFirstResponder(first?.contentView)
        NSApp.activate()
    }

    private func finish(_ rect: NSRect?) {
        overlays.forEach { $0.orderOut(nil) }
        overlays.removeAll()
        let app = AppDelegate.shared!
        switch target {
        case .window:
            if let rect { app.lockPanel(to: rect) }
            app.showPanel()
        case .popup:
            // The pop-up keeps its size: it moves to where the box starts (its top-left corner), locked there.
            if let rect {
                app.compact.setFrameTopLeftPoint(NSPoint(x: rect.minX, y: rect.maxY))
                app.setPinned(true)
            }
            app.showCompact()
        case .floating:
            if let rect {
                app.floating.setFrame(rect, display: true)
                app.setFloatingLocked(true)
            }
            app.showFloating()
        }
    }
}

private final class OverlayWindow: NSWindow {
    override var canBecomeKey: Bool { true }
}

/// The dimmed screen: drag to draw, the box stays clear with its size shown.
private final class FrameDrawView: NSView {
    var onDone: ((NSRect?) -> Void)?
    private var start: NSPoint?
    private var box: NSRect?

    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func resetCursorRects() { addCursorRect(bounds, cursor: .crosshair) }

    override func mouseDown(with event: NSEvent) {
        start = convert(event.locationInWindow, from: nil)
        box = nil
    }

    override func mouseDragged(with event: NSEvent) {
        guard let start else { return }
        let p = convert(event.locationInWindow, from: nil)
        box = NSRect(x: min(start.x, p.x), y: min(start.y, p.y), width: abs(p.x - start.x), height: abs(p.y - start.y))
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard var rect = box, let window, rect.width > 8, rect.height > 8 else { box = nil; needsDisplay = true; return }
        // Never smaller than the window can be.
        rect.size.width = max(rect.width, 260)
        rect.size.height = max(rect.height, 300)
        onDone?(window.convertToScreen(rect))
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onDone?(nil) } else { super.keyDown(with: event) } // Esc
    }

    override func draw(_ dirtyRect: NSRect) {
        let dim = NSBezierPath(rect: bounds)
        if let box { dim.append(NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)); dim.windingRule = .evenOdd }
        NSColor.black.withAlphaComponent(0.32).setFill()
        dim.fill()

        if let box {
            let outline = NSBezierPath(roundedRect: box, xRadius: 10, yRadius: 10)
            outline.lineWidth = 2
            NSColor.white.withAlphaComponent(0.9).setStroke()
            outline.stroke()
            let tooSmall = box.width < FrameDrawer.minSize.width || box.height < FrameDrawer.minSize.height
            let label = "\(Int(box.width)) × \(Int(box.height))" + (tooSmall ? "  (grows to \(Int(FrameDrawer.minSize.width)) × \(Int(FrameDrawer.minSize.height)))" : "")
            drawPill(label, at: NSPoint(x: box.midX, y: box.midY))
        } else {
            drawPill("Drag to draw where Swiss should sit  ·  Esc to cancel", at: NSPoint(x: bounds.midX, y: bounds.midY))
        }
    }

    private func drawPill(_ text: String, at center: NSPoint) {
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .medium), .foregroundColor: NSColor.white]
        let size = (text as NSString).size(withAttributes: attrs)
        let pill = NSRect(x: center.x - size.width / 2 - 12, y: center.y - size.height / 2 - 6, width: size.width + 24, height: size.height + 12)
        NSColor.black.withAlphaComponent(0.55).setFill()
        NSBezierPath(roundedRect: pill, xRadius: pill.height / 2, yRadius: pill.height / 2).fill()
        (text as NSString).draw(at: NSPoint(x: pill.minX + 12, y: pill.minY + 6), withAttributes: attrs)
    }
}

// MARK: - Locking the window

extension AppDelegate {
    /// Snaps the big window to this frame and keeps it there.
    func lockPanel(to rect: NSRect) {
        panel.setFrame(rect, display: true)
        UserDefaults.standard.set(NSStringFromRect(rect), forKey: FrameDrawer.lockedKey)
        WindowMode.set(.window) // reopens as the window, right here
        applyPanelLock()
        Store.shared.flash("Locked to this frame")
    }

    func unlockPanel() {
        UserDefaults.standard.removeObject(forKey: FrameDrawer.lockedKey)
        applyPanelLock()
        Store.shared.flash("Unlocked — drag the edges again")
    }

    /// Locked: no resizing at the edges and no moving. Restores the locked frame if it's still on a screen.
    func applyPanelLock() {
        if let saved = UserDefaults.standard.string(forKey: FrameDrawer.lockedKey) {
            let rect = NSRectFromString(saved)
            if NSScreen.screens.contains(where: { $0.frame.intersects(rect) }) { panel.setFrame(rect, display: true) }
            panel.styleMask.remove(.resizable)
            panel.isMovable = false
        } else {
            panel.styleMask.insert(.resizable)
            panel.isMovable = true
        }
    }
}

