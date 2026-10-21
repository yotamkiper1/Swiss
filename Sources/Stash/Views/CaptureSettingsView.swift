import AppKit
import SwiftUI

/// Settings → Capture: what goes into Recent, for how long, and what's never captured.
struct CaptureSettingsView: View {
    @ObservedObject private var recent = RecentStore.shared
    @AppStorage(CaptureSettings.clipboardKey) private var clipboardOn = false
    @AppStorage(CaptureSettings.screenshotsKey) private var screenshotsOn = false
    @AppStorage(CaptureSettings.downloadsKey) private var downloadsOn = false
    @AppStorage(CaptureSettings.retentionKey) private var retention = 72
    @AppStorage(CaptureSettings.maxMBKey) private var maxMB = 500
    @State private var folderPath = CaptureSettings.screenshotFolder.path
    @State private var excluded = CaptureSettings.excluded

    var body: some View {
        Section {
            Toggle("Capture what I copy (text, links, pictures, files)", isOn: $clipboardOn)
            Toggle("Capture screenshots", isOn: $screenshotsOn)
            Toggle("Capture downloads", isOn: $downloadsOn)
            if downloadsOn {
                LabeledContent("Save here to add to Recent") {
                    HStack {
                        Text("Downloads ▸ Swiss").foregroundStyle(.secondary)
                        Button("Show in Finder") { NSWorkspace.shared.open(RecentStore.prepareSwissFolder()) }
                    }
                }
                Text("New downloads land in Recent. In any Save dialog, pick Downloads ▸ Swiss (drag it into Finder's sidebar to have it in every dialog).")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            if screenshotsOn {
                LabeledContent("Screenshot folder") {
                    HStack {
                        Text((folderPath as NSString).abbreviatingWithTildeInPath).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        Button("Choose…", action: chooseFolder)
                    }
                }
            }
            Toggle("Pause capture", isOn: Binding(get: { recent.paused }, set: { recent.setPaused($0) }))
                .disabled(!clipboardOn && !screenshotsOn && !downloadsOn)
            Picker("Keep things in Recent for", selection: $retention) {
                ForEach(CaptureSettings.retentionChoices, id: \.hours) { Text($0.label).tag($0.hours) }
            }
            .onChange(of: retention) { recent.prune() }
            Picker("Recent can use up to", selection: $maxMB) {
                Text("100 MB").tag(100)
                Text("250 MB").tag(250)
                Text("500 MB").tag(500)
                Text("1 GB").tag(1000)
            }
            .onChange(of: maxMB) { recent.prune() }
            LabeledContent("Never capture from") {
                VStack(alignment: .trailing, spacing: 3) {
                    ForEach(excluded, id: \.self) { id in
                        HStack(spacing: 6) {
                            Text(Self.appName(id)).foregroundStyle(.secondary)
                            Button { setExcluded(excluded.filter { $0 != id }) } label: { Image(systemName: "minus.circle") }
                                .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Stop excluding \(Self.appName(id))")
                        }
                    }
                    Button("Add App…", action: addApp)
                }
            }
            HStack {
                Text("Recent uses \(StorageSettings.bytes(recent.diskBytes)) · \(recent.items.count) items").foregroundStyle(.secondary)
                Spacer()
                Button("Clear Recent") { recent.clear() }
            }
        } header: {
            Label("Capture", systemImage: "clock.arrow.circlepath")
        } footer: {
            Text("Off until you turn it on. What's captured stays on this Mac, in Recent, until it expires — copied files are only linked, and are copied into a project only when you Keep them. Password managers and anything apps mark as secret are skipped, but no filter is perfect: pause capture before copying something private.")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
    }

    private func setExcluded(_ list: [String]) {
        excluded = list
        UserDefaults.standard.set(list, forKey: CaptureSettings.excludedKey)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.directoryURL = CaptureSettings.screenshotFolder
        panel.prompt = "Watch This Folder"
        panel.message = "Swiss adds new screenshots saved in this folder to Recent (only screenshots, nothing else)."
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        UserDefaults.standard.set(url.path, forKey: CaptureSettings.screenshotFolderKey)
        folderPath = url.path
    }

    private func addApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.prompt = "Never Capture"
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 2)
        guard panel.runModal() == .OK, let url = panel.url, let id = Bundle(url: url)?.bundleIdentifier, !excluded.contains(id) else { return }
        setExcluded(excluded + [id])
    }

    static func appName(_ bundleID: String) -> String {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
            return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
        }
        return bundleID.split(separator: ".").last.map { String($0).capitalized } ?? bundleID
    }
}
