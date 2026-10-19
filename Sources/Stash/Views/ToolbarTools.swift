import SwiftUI

/// The header tools you can show or hide (Settings → Toolbar). All are on until you turn one off.
enum ToolbarTool: String, CaseIterable, Identifiable {
    case search, arrange, layout, organize
    var id: String { rawValue }
    var key: String { "tool." + rawValue }

    var title: String {
        switch self {
        case .search: "Search (big window)"
        case .arrange: "Arrange By"
        case .layout: "Icons | List"
        case .organize: "Organize wand (full screen)"
        }
    }

    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .arrange: "square.grid.3x1.below.line.grid.1x2"
        case .layout: "square.grid.2x2"
        case .organize: "wand.and.stars"
        }
    }

    var isShown: Bool { UserDefaults.standard.object(forKey: key) as? Bool ?? true }
}

/// Shows a header tool only if it's turned on in Settings (and redraws when that changes).
struct Tool<Content: View>: View {
    let tool: ToolbarTool
    @ViewBuilder let content: () -> Content
    @AppStorage private var shown: Bool

    init(_ tool: ToolbarTool, @ViewBuilder content: @escaping () -> Content) {
        self.tool = tool
        self.content = content
        _shown = AppStorage(wrappedValue: true, tool.key)
    }

    var body: some View {
        if shown { content() }
    }
}

/// Settings → Toolbar: tick the tools you want in the header.
struct ToolbarSettings: View {
    var body: some View {
        Section {
            ForEach(ToolbarTool.allCases) { tool in
                ToolToggle(tool: tool)
            }
        } header: {
            Label("Toolbar", systemImage: "slider.horizontal.3")
        } footer: {
            Text("Choose which buttons sit under the project tabs. Shortcuts keep working either way (⌘F search, ⌘1–⌘6, ⌥Space…).")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
    }
}

private struct ToolToggle: View {
    let tool: ToolbarTool
    @AppStorage private var shown: Bool

    init(tool: ToolbarTool) {
        self.tool = tool
        _shown = AppStorage(wrappedValue: true, tool.key)
    }

    var body: some View {
        Toggle(isOn: $shown) { Label(tool.title, systemImage: tool.symbol) }
    }
}
