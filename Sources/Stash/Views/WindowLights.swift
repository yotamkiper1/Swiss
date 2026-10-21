import AppKit
import SwiftUI

/// The Mac-style buttons in the top-left corner of every Swiss window — and how you move between the levels
/// (pop-up → the window → full screen; the Frame on the side): red closes the window, orange goes a level down,
/// green a level up (gray when there's no level further). The lock keeps the window where it is: one click locks, the next unlocks (right-click: draw its
/// frame). Quit is in the menu bar (⌘Q).
struct WindowLights: View {
    let mode: WindowMode
    /// The lock and Frame buttons next to the lights (off where they sit in the tools row instead).
    var extras = true
    @State private var hovering = false
    @AppStorage(AppDelegate.fullScreenKey) private var filled = false

    var body: some View {
        HStack(spacing: 8) {
            light(Color(red: 1.0, green: 0.37, blue: 0.34), symbol: "xmark", help: "Close the window (Swiss stays in the menu bar)") {
                switch mode {
                case .popup: AppDelegate.shared.closeCompact()
                case .window: AppDelegate.shared.hidePanel()
                case .floating: AppDelegate.shared.hideFloating()
                }
            }
            light(Color(red: 1.0, green: 0.74, blue: 0.18), symbol: "minus",
                  help: mode == .popup ? "Already the smallest" : (filled ? "Smaller: the window" : "Smaller: back to the pop-up"),
                  enabled: mode != .popup) {
                if mode == .window && filled { AppDelegate.shared.setFullScreen(false) } else { AppDelegate.shared.collapse() }
            }
            light(Color(red: 0.16, green: 0.78, blue: 0.25), symbol: "arrow.up.left.and.arrow.down.right",
                  help: mode == .window ? (filled ? "Already full screen" : "Bigger: full screen") : "Bigger: the window",
                  enabled: !(mode == .window && filled)) {
                if mode == .window { AppDelegate.shared.setFullScreen(true) } else { AppDelegate.shared.expand() }
            }
            if extras {
                LockButton(mode: mode).padding(.leading, 2)
                FrameModeButton(mode: mode)
            }
        }
        .onHover { hovering = $0 }
        .padding(.vertical, 2)
    }

    private func light(_ color: Color, symbol: String, help: String, enabled: Bool = true, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Circle()
                .fill(enabled ? color : Color.primary.opacity(0.18)) // gray when it can't be used, like the Mac's
                .overlay(Circle().strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                .overlay {
                    // Like the Mac's: the symbols show when the pointer is over the buttons.
                    Image(systemName: symbol)
                        .font(.system(size: 6.5, weight: .black))
                        .foregroundStyle(Color.black.opacity(0.55))
                        .opacity(hovering && enabled ? 1 : 0)
                }
                .frame(width: 12, height: 12)
                .contentShape(Circle().inset(by: -3))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// Lock / unlock the window where it is — one click each way. Locked shows orange.
/// Right-click: Lock Where It Is, or Draw Frame… (draw on the screen where the window should be).
struct LockButton: View {
    let mode: WindowMode
    @AppStorage(AppDelegate.pinnedKey) private var popupLocked = false
    @AppStorage(FrameDrawer.lockedKey) private var windowFrame = ""
    @AppStorage(AppDelegate.floatingLockedKey) private var floatingLocked = false

    private var locked: Bool {
        switch mode {
        case .popup: popupLocked
        case .window: !windowFrame.isEmpty
        case .floating: floatingLocked
        }
    }

    var body: some View {
        Button(action: toggle) {
            Image(systemName: locked ? "lock.fill" : "lock.open")
                .font(.system(size: 10.5, weight: locked ? .semibold : .regular))
                .foregroundStyle(locked ? Color.orange : Color.secondary)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(locked ? Color.orange.opacity(0.16) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(locked ? "Unlock" : "Lock Where It Is") { toggle() }
            Button("Draw Frame…") { AppDelegate.shared.drawFrame(for: mode) }
        }
        .help(locked ? "Locked in place — click to unlock (right-click: draw a frame)"
                     : "Click to lock the window where it is (right-click: draw a frame on screen)")
        .accessibilityLabel(locked ? "Unlock the window" : "Lock the window where it is")
    }

    private func toggle() {
        let app = AppDelegate.shared!
        switch mode {
        case .popup: app.setPinned(!popupLocked)
        case .window: if locked { app.unlockPanel() } else { app.lockPanel(to: app.panel.frame) }
        case .floating: app.setFloatingLocked(!floatingLocked)
        }
    }
}

extension AppDelegate {
    static let floatingLockedKey = "floating.locked"

    /// The floating frame locked: it can't be moved or resized until it's unlocked.
    func setFloatingLocked(_ locked: Bool) {
        UserDefaults.standard.set(locked, forKey: Self.floatingLockedKey)
        applyFloatingLock()
        Store.shared.flash(locked ? "Locked here" : "Unlocked — move and resize it again")
    }

    func applyFloatingLock() {
        let locked = UserDefaults.standard.bool(forKey: Self.floatingLockedKey)
        floating.isMovable = !locked
        if locked { floating.styleMask.remove(.resizable) } else { floating.styleMask.insert(.resizable) }
    }

    /// Draw on the screen where this window should be; it snaps there and stays locked.
    func drawFrame(for mode: WindowMode) {
        switch mode {
        case .window: FrameDrawer.shared.start()
        case .popup, .floating: FrameDrawer.shared.start(target: mode)
        }
    }
}

/// Opens the Frame — the canvas that stays on top of every app. In the Frame it's lit, and takes you back to the pop-up.
struct FrameModeButton: View {
    let mode: WindowMode
    @ObservedObject private var companion = Companion.shared

    var body: some View {
        // A window opened from the canvas has no Frame button: the Frame is already open.
        if !companion.on || mode == .floating { button }
    }

    private var button: some View {
        let on = mode == .floating
        return Button { if on { AppDelegate.shared.collapse() } else { AppDelegate.shared.float() } } label: {
            Image(systemName: "square.on.square.dashed")
                .font(.system(size: 10.5, weight: on ? .semibold : .regular))
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .frame(width: 20, height: 18)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? Color.accentColor.opacity(0.16) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(on ? "Leave the Frame (back to the pop-up)" : "Open the Frame — a canvas on top of every app")
        .accessibilityLabel(on ? "Leave the Frame" : "Open the Frame")
    }
}


extension AppDelegate {
    static let fullScreenKey = "window.fullScreen"
    private static let frameBeforeFullKey = "window.frameBeforeFull"

    /// The window's last level: it fills the whole screen (the menu bar and Dock stay). Orange brings back its size.
    func setFullScreen(_ on: Bool) {
        guard let screen = panel.screen ?? NSScreen.main else { return }
        let defaults = UserDefaults.standard
        if on, isBigLocked { Store.shared.flash("Unlock the window first"); return }
        // Instant underneath (an animated resize redraws the board every step); the picture on top glides.
        WindowMorph.run(from: panel, to: panel) { fill(on, screen: screen, defaults: defaults) }
    }

    private func fill(_ on: Bool, screen: NSScreen, defaults: UserDefaults) {
        if on {
            defaults.set(NSStringFromRect(panel.frame), forKey: Self.frameBeforeFullKey)
            panel.setFrame(screen.visibleFrame, display: true, animate: false)
            defaults.set(true, forKey: Self.fullScreenKey)
        } else {
            let before = defaults.string(forKey: Self.frameBeforeFullKey).map(NSRectFromString)
            let fallback = NSRect(x: screen.visibleFrame.midX - 380, y: screen.visibleFrame.midY - 290, width: 760, height: 580)
            panel.setFrame(before.flatMap { $0.width > 100 ? $0 : nil } ?? fallback, display: true, animate: false)
            defaults.set(false, forKey: Self.fullScreenKey)
        }
    }
}
