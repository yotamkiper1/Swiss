import AppKit

// MARK: - Moving between the pop-up, the big window and the Frame

/// Switching between the pop-up, the big window and the Frame (and filling the screen or not) resizes like a
/// Finder window: the new window starts where the old one was, at its size, and grows or shrinks to its own —
/// live, its contents laid out as it goes. (Measured with 10,000 things on the board: it keeps pace.)
/// With Reduce Motion on, it simply switches.
@MainActor
enum WindowMorph {
    /// `change` hides `source` and shows `target` at its final place, as it did before; this animates between them.
    static func run(from source: NSWindow?, to target: NSWindow, change: () -> Void) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion, let source, source.isVisible else { change(); return }
        let start = source.frame
        target.alphaValue = 0 // not seen at its final place before it's moved to the start
        change()
        // Not shown after all (Swiss is locked and asks for Touch ID first): nothing to animate to.
        guard target.isVisible else { target.alphaValue = 1; return }
        let end = target.frame
        target.setFrame(start, display: true)
        target.alphaValue = 1
        guard start != end else { return }
        target.setFrame(end, display: true, animate: true) // the Mac's own window resize
    }
}
