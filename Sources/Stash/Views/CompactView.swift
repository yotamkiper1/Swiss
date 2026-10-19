import SwiftUI

/// The small preview that drops down from the menu bar icon.
struct CompactView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        VStack(spacing: 0) {
            header
            BoardView(compact: true)
            QuickBar(compact: true)
        }
        .frame(width: 300, height: 400)
        .stashChrome()
    }

    /// Two rows: the project tabs on their own strip, the quiet tool buttons under them.
    private var header: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                WindowLights(mode: .popup, extras: false) // top-left, like any Mac window
                ProjectBar(limit: 2)
            }
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 5)
                .background(Color.primary.opacity(0.035))
                .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
            tools
        }
        .background(WindowDragArea()) // drag the pop-up by its top bar (until it's locked)
    }

    /// The window buttons (red, orange, green, lock), where things go, and the view tools (Icons / List, Arrange By).
    /// Everything else is in the Mac's menu bar.
    private var tools: some View {
        HStack(spacing: 6) {
            LockButton(mode: .popup)
            FrameModeButton(mode: .popup)
            // (Where things go is the selected tab — no room to say it twice in the small pop-up.)
            Spacer(minLength: 4)
            Group {
                Tool(.arrange) { ArrangeMenu() }
                Tool(.layout) { LayoutToggle() }
            }
            .disabled(store.showingRecent) // nothing to arrange in Recent
            .opacity(store.showingRecent ? 0.35 : 1)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 3)
    }
}

/// Empty space you can drag to move the pop-up by. Once it's locked, it stays put until you unlock it.
struct WindowDragArea: NSViewRepresentable {
    /// Locked windows don't move.
    var locked: () -> Bool = { AppDelegate.shared.isPinned }

    final class DragView: NSView {
        var locked: () -> Bool = { false }
        override func mouseDown(with event: NSEvent) {
            guard !locked(), let window else { return super.mouseDown(with: event) }
            window.performDrag(with: event)
        }
    }

    func makeNSView(context: Context) -> DragView {
        let view = DragView()
        view.locked = locked
        return view
    }

    func updateNSView(_ nsView: DragView, context: Context) { nsView.locked = locked }
}
