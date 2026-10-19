import AppKit
import SwiftUI

/// A Swiss window opened from the Frame (the canvas): the pop-up beside it, which can grow to the window and full
/// screen like any other — while the canvas stays open. It has no Frame button (you're already in one), and closing
/// it just goes back to the canvas.
@MainActor
final class Companion: ObservableObject {
    static let shared = Companion()
    @Published private(set) var on = false

    func set(_ value: Bool) { if on != value { on = value } }
}

extension AppDelegate {
    var companion: Bool { Companion.shared.on }

    /// From the canvas's top row: Swiss's pop-up, next to the Frame.
    func openCompanion() {
        guard floating.isVisible else { return }
        Companion.shared.set(true)
        panel.orderOut(nil)
        Store.shared.boardZoom = 1
        let size = compact.frame.size
        let frame = floating.frame
        let screen = (floating.screen ?? NSScreen.main)?.visibleFrame ?? .zero
        // To the right of the Frame if it fits, else to its left; kept on screen.
        var x = frame.maxX + 10
        if x + size.width > screen.maxX - 8 { x = frame.minX - size.width - 10 }
        x = min(max(x, screen.minX + 8), screen.maxX - size.width - 8)
        let y = min(max(frame.maxY - size.height, screen.minY + 8), screen.maxY - size.height - 8)
        compact.setFrameOrigin(NSPoint(x: x, y: y))
        compact.makeKeyAndOrderFront(nil)
        compact.invalidateShadow()
        NSApp.activate()
        Store.shared.focusRequest += 1
    }

    /// The companion closed (red): back to the canvas, which stays as it was.
    func closeCompanion() {
        Companion.shared.set(false)
        compact.orderOut(nil)
        panel.orderOut(nil)
        Store.shared.clipboardHint = nil
        if floating.isVisible { floating.makeKeyAndOrderFront(nil) }
    }
}
