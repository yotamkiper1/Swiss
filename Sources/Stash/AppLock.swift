import AppKit
import LocalAuthentication
import SwiftUI

// MARK: - Lock

/// Settings → Privacy → Require Touch ID: Swiss's windows open only after Touch ID (or the Mac's password, through
/// macOS's own prompt — Swiss never sees it). It locks again when the Mac locks or sleeps, and after Swiss has been
/// in the background for the time you chose. Quick save and capture keep working while it's locked: they add,
/// they don't show anything.
@MainActor
enum AppLock {
    static let enabledKey = "lock.enabled"
    static let graceKey = "lock.graceMinutes" // 0 = every time Swiss opens
    /// "Ask again after Swiss has been in the background for", in minutes.
    static let graceChoices: [(minutes: Int, label: String)] = [(0, "Every time"), (60, "1 hour"), (180, "3 hours"),
                                                                (1440, "1 day"), (4320, "3 days")]

    static var enabled: Bool { UserDefaults.standard.bool(forKey: enabledKey) }
    private static var grace: TimeInterval { TimeInterval(UserDefaults.standard.integer(forKey: graceKey)) * 60 }

    private static var unlocked = false
    static var isUnlocked: Bool { unlocked } // for test runs
    private static var awaySince = Date()
    private static var asking = false
    private static var waiting: (() -> Void)?

    static func start() {
        UserDefaults.standard.register(defaults: [enabledKey: false, graceKey: 60])
        // An earlier choice that's no longer on the list (1, 5 or 15 minutes) becomes 1 hour.
        if !graceChoices.contains(where: { $0.minutes == UserDefaults.standard.integer(forKey: graceKey) }) {
            UserDefaults.standard.set(60, forKey: graceKey)
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { awaySince = Date() }
        }
        let workspace = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.willSleepNotification, NSWorkspace.screensDidSleepNotification, NSWorkspace.sessionDidResignActiveNotification] {
            workspace.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { lock() } }
        }
        DistributedNotificationCenter.default().addObserver(forName: .init("com.apple.screenIsLocked"), object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { lock() }
        }
    }

    /// True when Swiss may show the library now. Otherwise asks for Touch ID and runs `then` once it's given.
    static func allow(_ then: @escaping () -> Void) -> Bool {
        guard enabled else { return true }
        if unlocked && (NSApp.isActive || Date().timeIntervalSince(awaySince) < max(grace, 3)) { return true }
        unlocked = false
        waiting = then // only the latest thing you asked for opens
        guard !asking else { return false }
        asking = true
        authenticate(reason: "open Swiss") { ok in
            asking = false
            let next = waiting
            waiting = nil
            guard ok else { return }
            unlocked = true
            awaySince = Date()
            next?()
        }
        return false
    }

    /// Locks now and puts away every window that shows the library.
    static func lock() {
        guard enabled else { return }
        unlocked = false
        let app = AppDelegate.shared
        app?.closeCompact()
        if app?.floating.isVisible == true { app?.hideFloating() }
        if app?.panel.isVisible == true { app?.hidePanel() }
        for window in NSApp.windows where window.isVisible && !window.className.contains("StatusBar") { window.orderOut(nil) }
    }

    /// Turning the lock on or off needs Touch ID too, so someone at your Mac can't simply switch it off.
    static func set(_ on: Bool, done: @escaping (Bool) -> Void) {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            let alert = NSAlert()
            alert.messageText = "This Mac has no password or Touch ID"
            alert.informativeText = "Set a login password in System Settings ▸ Users & Groups first, then turn the lock on."
            alert.runModal()
            done(false)
            return
        }
        authenticate(reason: on ? "require Touch ID to open Swiss" : "stop requiring Touch ID to open Swiss") { ok in
            if ok {
                UserDefaults.standard.set(on, forKey: enabledKey)
                unlocked = true
                awaySince = Date()
            }
            done(ok)
        }
    }

    /// macOS's own Touch ID / password prompt.
    private static func authenticate(reason: String, done: @escaping @MainActor (Bool) -> Void) {
        let context = LAContext()
        context.localizedFallbackTitle = "Use Password…"
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else {
            if TestMode.isOn { FileHandle.standardError.write("auth skipped: \(error?.localizedDescription ?? "-")\n".data(using: .utf8)!) }
            done(true) // no password on this Mac at all: nothing to check against
            return
        }
        NSApp.activate()
        context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason) { ok, error in
            if TestMode.isOn { FileHandle.standardError.write("auth ok=\(ok) \(error?.localizedDescription ?? "")\n".data(using: .utf8)!) }
            DispatchQueue.main.async { MainActor.assumeIsolated { done(ok) } }
        }
    }
}

/// Settings → Privacy.
struct PrivacySettings: View {
    @AppStorage(AppLock.enabledKey) private var enabled = false
    @AppStorage(AppLock.graceKey) private var grace = 60

    var body: some View {
        Section {
            Toggle("Require Touch ID or your password to open Swiss", isOn: Binding(get: { enabled }, set: { on in
                AppLock.set(on) { _ in } // @AppStorage follows the setting once macOS says yes
            }))
            Picker("Ask again after Swiss has been in the background for", selection: $grace) {
                ForEach(AppLock.graceChoices, id: \.minutes) { Text($0.label).tag($0.minutes) }
            }
            .disabled(!enabled)
        } header: {
            Label("Lock", systemImage: "lock")
        } footer: {
            Text("Swiss locks again when your Mac locks or sleeps. Quick save and capture still work while it's locked.")
                .foregroundStyle(.secondary)
                .settingsFooter()
        }

        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("Everything you save stays on this Mac, in your Documents ▸ Swiss folder and Swiss's own Library folder. Swiss has no account and no servers, and it sends nothing anywhere: no analytics, no tracking, no ads.")
                Text("Capturing what you copy, screenshots and downloads is off until you turn it on. Even then, passwords and anything apps mark as private are never kept.")
                Text("Swiss goes online only for things you do yourself: getting the title and picture of a link you save, a picture you drag in from a web page, a YouTube video you play on a canvas, downloading a video or sound from a link, and updating the downloader.")
                Text("Report a Problem and Send Feedback open an email that you can read before you press Send.")
            }
            .font(.system(size: 12))
            .fixedSize(horizontal: false, vertical: true)
        } header: {
            Label("Your privacy", systemImage: "hand.raised")
        }

        FeedbackSettings()
    }
}
