import AppKit
import Carbon.HIToolbox
import SwiftUI

// MARK: - Shortcuts you can set yourself

/// A key with its modifiers, as you pressed it in the recorder.
struct KeyCombo: Codable, Equatable {
    var keyCode: Int
    /// Carbon modifier bits (cmdKey, optionKey, controlKey, shiftKey).
    var modifiers: Int

    var display: String {
        var s = ""
        if modifiers & controlKey != 0 { s += "⌃" }
        if modifiers & optionKey != 0 { s += "⌥" }
        if modifiers & shiftKey != 0 { s += "⇧" }
        if modifiers & cmdKey != 0 { s += "⌘" }
        return s + Self.keyName(keyCode)
    }

    init(keyCode: Int, modifiers: Int) {
        self.keyCode = keyCode
        self.modifiers = modifiers
    }

    init(event: NSEvent) {
        keyCode = Int(event.keyCode)
        let flags = event.modifierFlags
        modifiers = (flags.contains(.command) ? cmdKey : 0) | (flags.contains(.option) ? optionKey : 0)
            | (flags.contains(.control) ? controlKey : 0) | (flags.contains(.shift) ? shiftKey : 0)
    }

    /// Does this key event match (for shortcuts used inside Stash)?
    func matches(_ event: NSEvent) -> Bool { KeyCombo(event: event) == self }

    static func keyName(_ code: Int) -> String {
        let special: [Int: String] = [
            kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦", kVK_Escape: "⎋",
            kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
            kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5",
            kVK_F6: "F6", kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12",
        ]
        if let name = special[code] { return name }
        // The letter or symbol this key types on your keyboard layout.
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let raw = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return "?" }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        var dead: UInt32 = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var length = 0
        let status = data.withUnsafeBytes { buffer -> OSStatus in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                  OptionBits(kUCKeyTranslateNoDeadKeysBit), &dead, 4, &length, &chars)
        }
        guard status == noErr, length > 0 else { return "?" }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }
}

/// The shortcuts in Settings → Shortcuts.
@MainActor
enum Shortcut: String, CaseIterable, Identifiable {
    case open, quickSave, keep
    var id: String { rawValue }
    private var key: String { "shortcut." + rawValue }

    var title: String {
        switch self {
        case .open: "Open or close Swiss"
        case .quickSave: "Save the clipboard without opening Swiss"
        case .keep: "Keep (in Recent)"
        }
    }

    /// Works from any app (global) or only while Stash is in front.
    var isGlobal: Bool { self != .keep }

    var defaultCombo: KeyCombo? {
        switch self {
        case .open: KeyCombo(keyCode: kVK_Space, modifiers: optionKey)
        case .quickSave: OrganizerSettings.quickSave.key.map { KeyCombo(keyCode: $0.code, modifiers: $0.modifiers) } // the earlier choice
        case .keep: KeyCombo(keyCode: kVK_ANSI_K, modifiers: cmdKey)
        }
    }

    /// The combo in use; nil = off.
    var combo: KeyCombo? {
        let defaults = UserDefaults.standard
        if defaults.bool(forKey: key + ".off") { return nil }
        if let data = defaults.data(forKey: key), let combo = try? JSONDecoder().decode(KeyCombo.self, from: data) { return combo }
        return defaultCombo
    }

    func set(_ combo: KeyCombo?) {
        let defaults = UserDefaults.standard
        if let combo {
            defaults.set(try? JSONEncoder().encode(combo), forKey: key)
            defaults.set(false, forKey: key + ".off")
        } else {
            defaults.removeObject(forKey: key)
            defaults.set(true, forKey: key + ".off")
        }
        AppDelegate.shared?.registerHotKeys()
    }

    func reset() {
        UserDefaults.standard.removeObject(forKey: key)
        UserDefaults.standard.removeObject(forKey: key + ".off")
        AppDelegate.shared?.registerHotKeys()
    }

    /// Why this combo isn't a good idea, if it isn't.
    func problem(with combo: KeyCombo) -> String? {
        let mods = combo.modifiers
        if isGlobal, mods & (cmdKey | optionKey | controlKey) == 0 {
            return "Add ⌘, ⌥ or ⌃ — a key on its own would stop working in every other app."
        }
        let reserved: [(KeyCombo, String)] = [
            (KeyCombo(keyCode: kVK_Space, modifiers: cmdKey), "Spotlight"),
            (KeyCombo(keyCode: kVK_Space, modifiers: controlKey), "switching keyboard input"),
            (KeyCombo(keyCode: kVK_Tab, modifiers: cmdKey), "switching apps"),
            (KeyCombo(keyCode: kVK_ANSI_Q, modifiers: cmdKey), "quitting apps"),
            (KeyCombo(keyCode: kVK_ANSI_W, modifiers: cmdKey), "closing windows"),
            (KeyCombo(keyCode: kVK_ANSI_H, modifiers: cmdKey), "hiding apps"),
            (KeyCombo(keyCode: kVK_ANSI_M, modifiers: cmdKey), "minimising windows"),
            (KeyCombo(keyCode: kVK_ANSI_C, modifiers: cmdKey), "Copy"),
            (KeyCombo(keyCode: kVK_ANSI_V, modifiers: cmdKey), "Paste"),
            (KeyCombo(keyCode: kVK_ANSI_X, modifiers: cmdKey), "Cut"),
            (KeyCombo(keyCode: kVK_ANSI_Z, modifiers: cmdKey), "Undo"),
            (KeyCombo(keyCode: kVK_ANSI_3, modifiers: cmdKey | shiftKey), "screenshots"),
            (KeyCombo(keyCode: kVK_ANSI_4, modifiers: cmdKey | shiftKey), "screenshots"),
            (KeyCombo(keyCode: kVK_ANSI_5, modifiers: cmdKey | shiftKey), "screenshots"),
            (KeyCombo(keyCode: kVK_Escape, modifiers: cmdKey | optionKey), "Force Quit"),
            (KeyCombo(keyCode: kVK_ANSI_Q, modifiers: cmdKey | controlKey), "locking the screen"),
        ]
        if let hit = reserved.first(where: { $0.0 == combo }) { return "macOS uses \(combo.display) for \(hit.1)." }
        if let other = Shortcut.allCases.first(where: { $0 != self && $0.combo == combo }) { return "Already used for “\(other.title)”." }
        if !isGlobal, [KeyCombo(keyCode: kVK_ANSI_F, modifiers: cmdKey), KeyCombo(keyCode: kVK_ANSI_I, modifiers: cmdKey),
                       KeyCombo(keyCode: kVK_ANSI_A, modifiers: cmdKey), KeyCombo(keyCode: kVK_Space, modifiers: 0)].contains(combo) {
            return "Swiss already uses \(combo.display) (search, Get Info, select all or Quick Look)."
        }
        return nil
    }
}

// MARK: - Registering the global ones

extension AppDelegate {
    /// (Re)registers the global shortcuts from Settings. The test app never takes them (they belong to the real Stash).
    func registerHotKeys() {
        guard !TestMode.isOn else { return }
        if hotKeyCombo != Shortcut.open.combo {
            hotKeyCombo = Shortcut.open.combo
            hotKey = Shortcut.open.combo.map { combo in
                HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) {
                    MainActor.assumeIsolated { AppDelegate.shared.hotKeyPressed() }
                }
            }
        }
        if quickSaveCombo != Shortcut.quickSave.combo {
            quickSaveCombo = Shortcut.quickSave.combo
            quickSaveKey = Shortcut.quickSave.combo.map { combo in
                HotKey(keyCode: combo.keyCode, modifiers: combo.modifiers) {
                    MainActor.assumeIsolated { AppDelegate.shared.quickSavePressed() }
                }
            }
        }
    }

    /// False when another app already owns the shortcut.
    func isRegistered(_ shortcut: Shortcut) -> Bool? {
        switch shortcut {
        case .open: hotKey?.isRegistered
        case .quickSave: quickSaveKey?.isRegistered
        case .keep: nil
        }
    }

    /// While you're recording a new shortcut, the current ones step aside.
    func suspendHotKeys(_ suspended: Bool) {
        if suspended {
            hotKey = nil; quickSaveKey = nil
            hotKeyCombo = nil; quickSaveCombo = nil
        } else {
            registerHotKeys()
        }
    }
}

// MARK: - The recorder

/// Click, then press the shortcut you want. Esc cancels, ⌫ turns a global shortcut off.
struct ShortcutRecorder: NSViewRepresentable {
    let shortcut: Shortcut
    @Binding var message: String?
    let changed: () -> Void

    func makeNSView(context: Context) -> RecorderView {
        let view = RecorderView()
        view.shortcut = shortcut
        view.onMessage = { message = $0 }
        view.onChange = changed
        return view
    }

    func updateNSView(_ view: RecorderView, context: Context) { view.refresh() }

    final class RecorderView: NSView {
        var shortcut: Shortcut = .open
        var onMessage: ((String?) -> Void)?
        var onChange: (() -> Void)?
        private var recording = false { didSet { refresh(); AppDelegate.shared.suspendHotKeys(recording) } }
        private let label = NSTextField(labelWithString: "")

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            layer?.cornerRadius = 6
            label.font = .systemFont(ofSize: 12, weight: .medium)
            label.alignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: centerXAnchor), label.centerYAnchor.constraint(equalTo: centerYAnchor),
                widthAnchor.constraint(equalToConstant: 150), heightAnchor.constraint(equalToConstant: 24),
            ])
            setAccessibilityRole(.button)
        }

        required init?(coder: NSCoder) { fatalError() }

        override var acceptsFirstResponder: Bool { true }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        func refresh() {
            label.stringValue = recording ? "Press a shortcut…" : (shortcut.combo?.display ?? "Off")
            label.textColor = recording ? .controlAccentColor : (shortcut.combo == nil ? .secondaryLabelColor : .labelColor)
            layer?.backgroundColor = (recording ? NSColor.controlAccentColor.withAlphaComponent(0.15) : NSColor.labelColor.withAlphaComponent(0.07)).cgColor
            layer?.borderWidth = recording ? 1.5 : 0
            layer?.borderColor = NSColor.controlAccentColor.cgColor
            setAccessibilityLabel("\(shortcut.title): \(shortcut.combo?.display ?? "off"). Click to change.")
        }

        override func mouseDown(with event: NSEvent) {
            recording.toggle()
            if recording { window?.makeFirstResponder(self); onMessage?(nil) }
        }

        override func resignFirstResponder() -> Bool {
            if recording { recording = false }
            return super.resignFirstResponder()
        }

        override func performKeyEquivalent(with event: NSEvent) -> Bool {
            guard recording else { return super.performKeyEquivalent(with: event) }
            keyDown(with: event) // ⌘-combos arrive here first
            return true
        }

        override func keyDown(with event: NSEvent) {
            guard recording else { return super.keyDown(with: event) }
            let plain = event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty
            if plain && event.keyCode == UInt16(kVK_Escape) { recording = false; return }
            if plain && (event.keyCode == UInt16(kVK_Delete) || event.keyCode == UInt16(kVK_ForwardDelete)) {
                shortcut.set(nil)
                recording = false
                onMessage?("Turned off.")
                onChange?()
                return
            }
            let combo = KeyCombo(event: event)
            if let problem = shortcut.problem(with: combo) {
                onMessage?(problem) // keep listening for another one
                NSSound.beep()
                return
            }
            shortcut.set(combo)
            recording = false
            if shortcut.isGlobal, AppDelegate.shared.isRegistered(shortcut) == false {
                onMessage?("Another app already uses \(combo.display) — pick another one.")
            } else {
                onMessage?(nil)
            }
            onChange?()
        }
    }
}

/// Settings → Shortcuts.
struct ShortcutsSettings: View {
    @State private var messages: [Shortcut: String] = [:]
    @State private var tick = 0

    var body: some View {
        Section {
            ForEach(Shortcut.allCases) { shortcut in
                VStack(alignment: .leading, spacing: 3) {
                    LabeledContent {
                        HStack(spacing: 6) {
                            ShortcutRecorder(shortcut: shortcut, message: Binding(get: { messages[shortcut] }, set: { messages[shortcut] = $0 })) { tick += 1 }
                                .frame(width: 150, height: 24)
                                .id("\(shortcut.rawValue)-\(tick)")
                            Button { shortcut.reset(); messages[shortcut] = nil; tick += 1 } label: { Image(systemName: "arrow.counterclockwise") }
                                .buttonStyle(.plain).foregroundStyle(.secondary)
                                .help("Back to \(shortcut.defaultCombo?.display ?? "off")")
                                .accessibilityLabel("Reset \(shortcut.title)")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 1) {
                            Text(shortcut.title)
                            Text(shortcut.isGlobal ? "Works from any app" : "While Swiss is in front")
                                .font(.system(size: 10.5)).foregroundStyle(.secondary)
                        }
                    }
                    if let message = messages[shortcut] {
                        Text(message).font(.system(size: 11)).foregroundStyle(.orange)
                    } else if shortcut.isGlobal, AppDelegate.shared.isRegistered(shortcut) == false, let combo = shortcut.combo {
                        Text("Another app already uses \(combo.display) — pick another one.").font(.system(size: 11)).foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Label("Shortcuts", systemImage: "command")
        } footer: {
            Text("Click a shortcut, then press the keys you want. Esc cancels; ⌫ turns it off. Swiss warns you about shortcuts macOS or another app already uses.")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
    }
}
