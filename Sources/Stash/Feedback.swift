import AppKit
import SwiftUI

// MARK: - Report a Problem / Send Feedback

/// Help ▸ Report a Problem… and Send Feedback…: a new email to the developer, filled in, which you read and send
/// yourself. Swiss has no mail password inside it (anyone could take one out of the app), so it never sends on
/// its own. Diagnostics are a plain text file you can open before sending: versions, settings switches and
/// counts — never what's in your library, never file or folder names.
@MainActor
enum Feedback {
    static let address = "kipery20@gmail.com"

    static var version: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "?") (\(info?["CFBundleVersion"] as? String ?? "?"))"
    }

    static var macOS: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    static func reportProblem() {
        let alert = NSAlert()
        alert.messageText = "Report a Problem"
        alert.informativeText = """
        Swiss opens a new email to the developer. Say what happened and what you expected; you can read everything before you press Send.

        Diagnostics (optional) add Swiss's and macOS's versions, which settings are on, how many projects and things you have, and the latest crash report if Swiss crashed. Never what's in your library and never file names.
        """
        alert.addButton(withTitle: "Write Email with Diagnostics")
        alert.addButton(withTitle: "Write Email Without")
        alert.addButton(withTitle: "Show Diagnostics…")
        alert.addButton(withTitle: "Cancel")
        NSApp.activate()
        switch alert.runModal() {
        case .alertFirstButtonReturn:
            compose(subject: "Swiss problem report — \(version)", body: problemBody, attachment: writeDiagnostics())
        case .alertSecondButtonReturn:
            compose(subject: "Swiss problem report — \(version)", body: problemBody, attachment: nil)
        case .alertThirdButtonReturn:
            if let file = writeDiagnostics() { NSWorkspace.shared.open(file) } // in TextEdit: read it, then come back
        default: break
        }
    }

    static func sendFeedback() {
        let body = """
        How many stars would you give Swiss (1–5)?


        What do you like?


        What would make it better?



        —
        Swiss \(version), macOS \(macOS)
        """
        compose(subject: "Swiss feedback — \(version)", body: body, attachment: nil)
    }

    private static var problemBody: String {
        """
        What happened?


        What did you expect?


        Can you make it happen again? How?



        —
        Swiss \(version), macOS \(macOS)
        """
    }

    /// A new email with everything filled in. In Mail the diagnostics are attached; with another mail app they're
    /// shown in Finder to drag into the email.
    private static func compose(subject: String, body: String, attachment: URL?) {
        // Mail takes everything at once. Another mail app (Gmail in a browser, Outlook…) gets a mailto: link.
        let mailApp = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "mailto:x@example.com")!)
        let usesMail = mailApp.flatMap { Bundle(url: $0)?.bundleIdentifier } == "com.apple.mail"
        if TestMode.isOn { FileHandle.standardError.write("feedback via \(usesMail ? "Mail" : "mailto: \(mailApp?.lastPathComponent ?? "-")")\n".data(using: .utf8)!) }
        if usesMail, let service = NSSharingService(named: .composeEmail) {
            service.recipients = [address]
            service.subject = subject
            let items: [Any] = [body] + (attachment.map { [$0] } ?? [])
            if service.canPerform(withItems: items) {
                service.perform(withItems: items)
                return
            }
        }
        var parts = URLComponents()
        parts.scheme = "mailto"
        parts.path = address
        parts.queryItems = [URLQueryItem(name: "subject", value: subject), URLQueryItem(name: "body", value: body)]
        if let url = parts.url { NSWorkspace.shared.open(url) }
        if let attachment { NSWorkspace.shared.activateFileViewerSelecting([attachment]) }
    }

    /// Writes the diagnostics file (in Swiss's temporary folder) and returns it.
    static func writeDiagnostics() -> URL? {
        let store = Store.shared
        var lines = [
            "Swiss diagnostics — \(Date().formatted(date: .abbreviated, time: .shortened))",
            "",
            "Swiss \(version)\(TestMode.isOn ? " (Test)" : "")",
            "macOS \(macOS), \(machine)",
            "Projects: \(store.projects.count), folders: \(store.folders.count), things: \(store.items.count)",
            "Connected folders: \(ConnectedRegistry.shared.folders.count)",
            "Recent: \(RecentStore.shared.items.count) things",
            "Library readable: \(store.libraryReadable ? "yes" : "no")\(store.recoveryNote == nil ? "" : ", restored from a backup")",
            "Capture — clipboard: \(onOff(CaptureSettings.clipboardOn)), screenshots: \(onOff(CaptureSettings.screenshotsOn)), downloads: \(onOff(CaptureSettings.downloadsOn)), paused: \(onOff(CaptureSettings.paused))",
            "Lock: \(onOff(AppLock.enabled)), window mode: \(WindowMode.current.rawValue)",
            "Downloader: \(Converter.ytdlp == nil ? "missing" : (Converter.ytdlp == Converter.updatedYtdlp ? "updated copy" : "built in"))",
            "Free disk space: \(BigFiles.freeSpace(at: store.dataDir).map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "?")",
        ]
        if let crash = latestCrashReport() {
            lines += ["", "Latest crash report (\(crash.date.formatted(date: .abbreviated, time: .shortened))):", crash.text]
        } else {
            lines += ["", "No crash reports from Swiss in the last 30 days."]
        }
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("Swiss Diagnostics.txt")
        do {
            try lines.joined(separator: "\n").write(to: file, atomically: true, encoding: .utf8)
            return file
        } catch {
            return nil
        }
    }

    private static func onOff(_ on: Bool) -> String { on ? "on" : "off" }

    private static var machine: String {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [UInt8](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        #if arch(arm64)
        let chip = "Apple silicon"
        #else
        let chip = "Intel"
        #endif
        return "\(String(decoding: model.prefix { $0 != 0 }, as: UTF8.self)), \(chip)"
    }

    /// The newest Swiss crash report from the last 30 days, with your home folder's name taken out.
    private static func latestCrashReport() -> (date: Date, text: String)? {
        let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/DiagnosticReports")
        let keys: [URLResourceKey] = [.contentModificationDateKey]
        let files = (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys)) ?? []
        // Only this Swiss's own crashes (not Swiss Test's, or the other way round).
        let mine = "\"bundleID\":\"\(Bundle.main.bundleIdentifier ?? "")\""
        let newest = files
            .filter { $0.lastPathComponent.hasPrefix("Swiss") && ["ips", "crash"].contains($0.pathExtension) }
            .compactMap { url in (try? url.resourceValues(forKeys: Set(keys)).contentModificationDate).flatMap { $0 }.map { (url, $0) } }
            .filter { Date().timeIntervalSince($0.1) < 30 * 86_400 }
            .sorted { $0.1 > $1.1 }
            .lazy.compactMap { url, date in (try? Data(contentsOf: url)).map { (date, $0) } }
            .first { String(decoding: $0.1.prefix(600), as: UTF8.self).contains(mine) }
        guard let (date, data) = newest else { return nil }
        let text = String(decoding: data.prefix(60_000), as: UTF8.self)
            .replacingOccurrences(of: NSHomeDirectory(), with: "~")
            .replacingOccurrences(of: NSUserName(), with: "user")
        return (date, text)
    }
}

/// Settings ▸ Privacy ▸ Help and feedback.
struct FeedbackSettings: View {
    var body: some View {
        Section {
            HStack {
                Button("Report a Problem…") { Feedback.reportProblem() }
                Button("Send Feedback or a Review…") { Feedback.sendFeedback() }
            }
        } header: {
            Label("Help and feedback", systemImage: "envelope")
        } footer: {
            Text("Opens an email to the developer (\(Feedback.address)) that you send yourself.")
                .foregroundStyle(.secondary)
                .settingsFooter()
        }
    }
}
