import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Organizer options, kept in UserDefaults and changed in the Settings window (⌘,).
enum OrganizerSettings {
    enum Existing: String, CaseIterable, Identifiable {
        case ask, add, new
        var id: String { rawValue }
        var label: String {
            switch self {
            case .ask: "Ask me"
            case .add: "Add to the existing folder"
            case .new: "Always make a new folder"
            }
        }
    }

    static let wandScopeKey = "organizer.wandInOpenFolder"
    static let existingKey = "organizer.existingFolders"
    static let deepAllProjectsKey = "organizer.deepAllProjects"
    static let deepOwnFoldersKey = "organizer.deepOwnFolders"
    static let deepFixKey = "organizer.deepFixWrongKind"
    static let copyFilesKey = "files.copyIntoStash"
    static let quickSaveKey = "quickSave.shortcut"
    static let pasteMakesFolderKey = "paste.makesFolder"

    static func register() {
        UserDefaults.standard.register(defaults: [
            wandScopeKey: true,
            existingKey: Existing.ask.rawValue,
            deepAllProjectsKey: false,
            deepOwnFoldersKey: true,
            deepFixKey: true,
            copyFilesKey: true,
            pasteMakesFolderKey: false,
            quickSaveKey: QuickSaveShortcut.optionCommandV.rawValue,
        ])
    }

    static var copyFiles: Bool { UserDefaults.standard.bool(forKey: copyFilesKey) }
    /// ⌥Space + paste when there's no Linker/PhotoBook/Notepad/Files here: make one (on) or save on the page (off, default).
    static var pasteMakesFolder: Bool { UserDefaults.standard.bool(forKey: pasteMakesFolderKey) }
    static var quickSave: QuickSaveShortcut {
        QuickSaveShortcut(rawValue: UserDefaults.standard.string(forKey: quickSaveKey) ?? "") ?? .optionCommandV
    }

    static var wandWorksInOpenFolder: Bool { UserDefaults.standard.bool(forKey: wandScopeKey) }
    static var existingFolders: Existing {
        Existing(rawValue: UserDefaults.standard.string(forKey: existingKey) ?? "") ?? .ask
    }
}

/// The global shortcut that saves what you copied without opening Stash.
enum QuickSaveShortcut: String, CaseIterable, Identifiable {
    case optionCommandV, controlOptionV, controlOptionS, off
    var id: String { rawValue }
    var label: String {
        switch self {
        case .optionCommandV: "⌥⌘V"
        case .controlOptionV: "⌃⌥V"
        case .controlOptionS: "⌃⌥S"
        case .off: "Off"
        }
    }
    /// Carbon key code and modifiers.
    var key: (code: Int, modifiers: Int)? {
        switch self {
        case .optionCommandV: (kVK_ANSI_V, optionKey | cmdKey)
        case .controlOptionV: (kVK_ANSI_V, controlKey | optionKey)
        case .controlOptionS: (kVK_ANSI_S, controlKey | optionKey)
        case .off: nil
        }
    }
}

/// Settings (⌘, or right-click the menu bar icon). Holds the organizer options and Deep Organize.
struct SettingsView: View {
    @EnvironmentObject var store: Store
    @AppStorage(OrganizerSettings.wandScopeKey) private var wandInOpenFolder = true
    @AppStorage(OrganizerSettings.existingKey) private var existing = OrganizerSettings.Existing.ask.rawValue
    @AppStorage(OrganizerSettings.deepAllProjectsKey) private var deepAllProjects = false
    @AppStorage(OrganizerSettings.deepOwnFoldersKey) private var deepOwnFolders = true
    @AppStorage(OrganizerSettings.deepFixKey) private var deepFix = true
    @AppStorage(OrganizerSettings.copyFilesKey) private var copyFiles = true
    @AppStorage(OrganizerSettings.pasteMakesFolderKey) private var pasteMakesFolder = false
    @AppStorage(OrganizerSettings.quickSaveKey) private var quickSave = QuickSaveShortcut.optionCommandV.rawValue
    @State private var confirming = false
    @State private var result: String?

    enum Tab: String, CaseIterable {
        case general = "General", capture = "Capture", files = "Files", shortcuts = "Shortcuts", organize = "Organize", tools = "Tools", privacy = "Privacy"
        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .capture: "camera.viewfinder"
            case .files: "internaldrive"
            case .shortcuts: "command"
            case .organize: "wand.and.stars"
            case .tools: "wrench.and.screwdriver"
            case .privacy: "lock.shield"
            }
        }
    }
    @AppStorage("settings.tab") private var tab = Tab.general.rawValue

    var body: some View {
        VStack(spacing: 0) {
            // Like any Mac app's Settings: a row of icons on top.
            HStack(spacing: 2) {
                ForEach(Tab.allCases, id: \.self) { item in
                    let on = tab == item.rawValue
                    Button { tab = item.rawValue } label: {
                        VStack(spacing: 3) {
                            Image(systemName: item.symbol).font(.system(size: 17)).frame(height: 20)
                            Text(item.rawValue).font(.system(size: 10.5))
                        }
                        .frame(width: 68, height: 46)
                        .foregroundStyle(on ? Color.accentColor : Color.secondary)
                        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(on ? Color.primary.opacity(0.08) : .clear))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(on ? .isSelected : [])
                }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity)
            .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.08)).frame(height: 1) }
            Group {
                switch Tab(rawValue: tab) ?? .general {
                case .general: pane { generalSections }
                case .capture: pane { CaptureSettingsView() }
                case .files: pane { BigFileSettings(); StorageSettings() }
                case .shortcuts: pane { ShortcutsSettings() }
                case .organize: pane { organizeSections }
                case .tools: pane { ToolsSettings() }
                case .privacy: pane { PrivacySettings() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: 520, height: 620)
        .confirmationDialog("Deep Organize \(deepAllProjects ? "every project" : store.name(for: store.currentPlace.project))?",
                            isPresented: $confirming) {
            Button("Deep Organize") {
                let (moved, made) = store.deepOrganize(allProjects: deepAllProjects, includeOwnFolders: deepOwnFolders, fixWrongKind: deepFix)
                result = moved == 0 ? "Already tidy" : "Moved \(store.plural(moved, "thing")), made \(store.plural(made, "folder"))"
            }
        } message: {
            Text("You can undo it with ⌘Z.")
        }
    }
    private func pane<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        Form { content() }.formStyle(.grouped)
    }

    @ViewBuilder private var generalSections: some View {
            Section {
                Toggle("When pasting, make a Linker / PhotoBook / Notepad / Files folder if there isn't one", isOn: $pasteMakesFolder)
            } header: {
                Label("Quick save", systemImage: "square.and.arrow.down")
            } footer: {
                Text("Copy something anywhere, press the shortcut, and Swiss saves it without opening: into the project you last had open, inside its Files, PhotoBook, Linker or Notepad folder if there is one. ⌥⌘V is also Finder's \"move here\" — pick another shortcut if you use that.")
                    .foregroundStyle(.secondary)
                .settingsFooter()
            }

        ToolbarSettings()
    }

    @ViewBuilder private var organizeSections: some View {
            Section {
                Picker("Organizes", selection: $wandInOpenFolder) {
                    Text("The folder I'm in").tag(true)
                    Text("Only the project's board").tag(false)
                }
                Picker("If a matching folder exists", selection: $existing) {
                    ForEach(OrganizerSettings.Existing.allCases) { Text($0.label).tag($0.rawValue) }
                }
            } header: {
                Label("Organize button", systemImage: "wand.and.stars")
            } footer: {
                Text("Links go to Linker, images to PhotoBook, notes to Notepad, other files to Files.")
                    .foregroundStyle(.secondary)
                .settingsFooter()
            }

            Section {
                Picker("Works on", selection: $deepAllProjects) {
                    Text("The project that's open (\(store.name(for: store.currentPlace.project)))").tag(false)
                    Text("Every project").tag(true)
                }
                Toggle("Also sort things inside my own folders", isOn: $deepOwnFolders)
                Toggle("Fix things in the wrong kind of folder", isOn: $deepFix)
                HStack {
                    if let result {
                        Text(result).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Deep Organize…") { confirming = true }
                        .controlSize(.large)
                }
            } header: {
                Label("Deep Organize", systemImage: "sparkles")
            } footer: {
                Text("Goes through every folder, even folders inside folders, and puts each thing into the right kind of folder at its level. A PhotoBook inside a Linker moves out next to it, an image inside a Linker moves to the PhotoBook beside it. ⌘Z undoes it.")
                    .foregroundStyle(.secondary)
                .settingsFooter()
            }
    }

}


extension View {
    /// A Settings section's explanation: left-aligned, wrapping, gray.
    func settingsFooter() -> some View {
        self.font(.system(size: 11))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}
