import AppKit

// MARK: - Moving between the pop-up, the big window and the Frame

/// Switching between the pop-up, the big window and the Frame (and filling the screen or not): a picture of
/// the window you're leaving glides and grows into the new one while the new one fades in. A picture, not the
/// live window: resizing the real board on every frame would stutter with thousands of things on it.
/// With Reduce Motion on, it's a short cross-fade instead.
@MainActor
enum WindowMorph {
    private static var overlay: NSWindow?

    /// `change` hides `source` and shows `target` at its final place, as it did before; this animates between them.
    static func run(from source: NSWindow?, to target: NSWindow, change: () -> Void) {
        overlay?.orderOut(nil) // a switch during a switch: start from where things are now
        overlay = nil
        guard let source, source.isVisible, let image = snapshot(of: source) else { change(); return }
        let start = source.frame
        let shot = makeOverlay(image, frame: start, corner: source.contentView?.layer?.cornerRadius ?? 10,
                               level: NSWindow.Level(rawValue: max(source.level.rawValue, target.level.rawValue) + 1))
        overlay = shot
        target.alphaValue = 0
        change()
        // Not shown after all (Swiss is locked and asks for Touch ID first): nothing to animate to.
        guard target.isVisible else {
            target.alphaValue = 1
            shot.orderOut(nil)
            overlay = nil
            return
        }
        // Draw the new window now, so the glide starts after that work instead of being held up by it halfway.
        target.contentView?.layoutSubtreeIfNeeded()
        target.displayIfNeeded()
        let end = target.frame
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // And once more after this turn: SwiftUI draws a window it just showed at the end of the turn, the first
        // time most of all. Starting then, the glide runs on a free main thread from its first frame.
        DispatchQueue.main.async { MainActor.assumeIsolated { glide(shot, to: end, target: target, reduce: reduce) } }
    }

    private static func glide(_ shot: NSWindow, to end: NSRect, target: NSWindow, reduce: Bool) {
        guard overlay === shot else { return } // another switch came first
        NSAnimationContext.runAnimationGroup { context in
            context.duration = reduce ? 0.12 : 0.22 // short and even, like the Mac's own window zoom
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            if !reduce { shot.animator().setFrame(end, display: true) }
            shot.animator().alphaValue = 0
            target.animator().alphaValue = 1
        } completionHandler: {
            MainActor.assumeIsolated {
                shot.orderOut(nil)
                if overlay === shot { overlay = nil }
                target.alphaValue = 1
            }
        }
    }

    private static func snapshot(of window: NSWindow) -> CGImage? {
        guard let view = window.contentView, view.bounds.width > 1,
              let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return nil }
        view.cacheDisplay(in: view.bounds, to: rep)
        return rep.cgImage
    }

    private static func makeOverlay(_ image: CGImage, frame: NSRect, corner: CGFloat, level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = true
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        let view = NSView(frame: NSRect(origin: .zero, size: frame.size))
        view.wantsLayer = true
        view.layer?.contents = image
        view.layer?.contentsGravity = .resize
        view.layer?.cornerRadius = corner
        view.layer?.masksToBounds = true
        view.autoresizingMask = [.width, .height]
        window.contentView = view
        window.orderFront(nil)
        return window
    }
}
