import AppKit
import SwiftUI

/// A real macOS menu popped up from one of the header buttons. (SwiftUI's own menu buttons draw only a bare
/// icon, which hid the ▾ and the lock — these buttons draw themselves and open this.)
struct MenuEntry {
    var title: String
    var symbol: String? = nil
    var checked = false
    var enabled = true
    var lineBefore = false
    /// A submenu (the action is then ignored).
    var children: [MenuEntry] = []
    var action: () -> Void = {}
}

@MainActor
enum PopMenu {
    static func show(_ entries: [MenuEntry]) {
        build(entries).popUp(positioning: nil, at: NSEvent.mouseLocation, in: nil)
    }

    private static func build(_ entries: [MenuEntry]) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in entries {
            if entry.lineBefore { menu.addItem(.separator()) }
            let target = Target(entry.action)
            let item = NSMenuItem(title: entry.title, action: #selector(Target.fire(_:)), keyEquivalent: "")
            item.target = target
            item.representedObject = target // keeps it alive while the menu is open
            item.image = entry.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
            item.state = entry.checked ? .on : .off
            item.isEnabled = entry.enabled
            if !entry.children.isEmpty { item.submenu = build(entry.children); item.action = nil }
            menu.addItem(item)
        }
        return menu
    }

    private final class Target: NSObject {
        let action: () -> Void
        init(_ action: @escaping () -> Void) { self.action = action }
        @objc func fire(_ sender: Any?) { action() }
    }
}

/// An icon with a small ▾, so it reads as "click for options". Click or right-click opens the menu.
struct MenuIconButton<Label: View>: View {
    let entries: () -> [MenuEntry]
    let help: String
    @ViewBuilder let label: () -> Label

    var body: some View {
        Button { PopMenu.show(entries()) } label: {
            HStack(spacing: 3) {
                label()
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold)).opacity(0.7)
            }
            .padding(.horizontal, 5)
            .frame(height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(QuietButtonStyle())
        .contextMenu {
            ForEach(Array(entries().enumerated()), id: \.offset) { _, entry in
                if entry.lineBefore { Divider() }
                Button {
                    entry.action()
                } label: {
                    if let symbol = entry.symbol {
                        SwiftUI.Label(entry.title, systemImage: entry.checked ? "checkmark" : symbol)
                    } else {
                        Text(entry.checked ? "✓ " + entry.title : entry.title)
                    }
                }
                .disabled(!entry.enabled)
            }
        }
        .help(help)
        .accessibilityLabel(help.components(separatedBy: " — ").first ?? help)
        .accessibilityHint("Opens a menu")
    }
}
