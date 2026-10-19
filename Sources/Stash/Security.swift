import AppKit
import UniformTypeIdentifiers

// MARK: - Safety

/// Swiss stores and shows files — it never runs them by itself. These are the checks around the few places where
/// something could run: opening a file that's an app or a script, opening a link that isn't a web page, and the
/// downloader. Downloads are marked as downloaded (quarantined), so macOS checks them like anything from Safari.
enum Safety {
    /// Kinds of files that can run code when opened.
    private static let runnableExtensions: Set<String> = [
        "app", "command", "tool", "terminal", "sh", "zsh", "bash", "csh", "ksh", "fish", "py", "rb", "pl", "php", "js",
        "jar", "scpt", "scptd", "applescript", "workflow", "action", "pkg", "mpkg", "dmg", "prefpane", "saver", "qlgenerator",
        "kext", "plugin", "bundle", "dylib", "osax", "mobileconfig", "inetloc", "fileloc", "webloc", "url", "desktop",
    ]

    /// True when opening this file could run code (an app, a script, an installer, a shortcut to one).
    nonisolated static func canRunCode(_ url: URL) -> Bool {
        if runnableExtensions.contains(url.pathExtension.lowercased()) { return true }
        if let type = (try? url.resourceValues(forKeys: [.contentTypeKey]))?.contentType,
           [UTType.application, .applicationBundle, .executable, .script, .shellScript, .unixExecutable, .pythonScript]
               .contains(where: { type.conforms(to: $0) }) {
            return true
        }
        var isDir: ObjCBool = false
        // A plain file with the "executable" permission (no extension) is a program too.
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && !isDir.boolValue
            && FileManager.default.isExecutableFile(atPath: url.path) && url.pathExtension.isEmpty
    }

    /// Opens a file in its app — but asks first if it can run code. The safe choice (Show in Finder) is the default.
    @MainActor static func open(_ url: URL) {
        guard canRunCode(url) else { NSWorkspace.shared.open(url); return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "“\(url.lastPathComponent)” can run code on your Mac"
        alert.informativeText = "It's an app, a script or an installer. Only open it if you trust where it came from."
        alert.addButton(withTitle: "Show in Finder")
        alert.addButton(withTitle: "Open Anyway")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn: NSWorkspace.shared.activateFileViewerSelecting([url])
        case .alertSecondButtonReturn: NSWorkspace.shared.open(url) // macOS's own checks (Gatekeeper) still apply
        default: break
        }
    }

    /// Opens a saved link: web pages and email go straight to their app; anything else (a file:// path, another
    /// app's own link) is asked about first.
    @MainActor static func openLink(_ url: URL) {
        let scheme = url.scheme?.lowercased() ?? ""
        if ["http", "https", "mailto"].contains(scheme) { NSWorkspace.shared.open(url); return }
        if url.isFileURL { open(url); return }
        let alert = NSAlert()
        alert.messageText = "Open this link in another app?"
        alert.informativeText = "\(url.absoluteString.prefix(200))\n\nIt isn't a web page — it asks another app on your Mac to do something."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Open")
        NSApp.activate()
        if alert.runModal() == .alertSecondButtonReturn { NSWorkspace.shared.open(url) }
    }

    /// Marks a file Swiss downloaded as coming from the internet, so macOS checks it before anything runs it.
    nonisolated static func quarantine(_ url: URL, from source: URL? = nil) {
        let fields = ["0081", String(format: "%08x", Int(Date().timeIntervalSince1970)), "Swiss", UUID().uuidString]
        let value = fields.joined(separator: ";")
        _ = value.withCString { setxattr(url.path, "com.apple.quarantine", $0, strlen($0), 0, 0) }
        _ = source // where it came from isn't stored: the mark is enough for macOS's checks
    }

    /// Only real web addresses go to the downloader.
    nonisolated static func isWebURL(_ url: URL) -> Bool {
        ["http", "https"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false
    }
}


/// The Mac's own "move to Trash" sound — once per delete, however many things went.
@MainActor
enum DeleteSound {
    private static let sound = NSSound(contentsOfFile: "/System/Library/Components/CoreAudio.component/Contents/SharedSupport/SystemSounds/finder/move to trash.aif",
                                       byReference: true)
    private static var last = Date.distantPast

    static func play() {
        guard Date().timeIntervalSince(last) > 0.3 else { return } // a batch is one sound
        last = Date()
        sound?.stop()
        sound?.play()
    }
}
