import SwiftUI

/// The big, movable window.
struct RootView: View {
    @EnvironmentObject var store: Store
    @FocusState private var searchFocused: Bool
    @AppStorage("window.sidebar") private var sidebar = true

    var body: some View {
        HStack(spacing: 0) {
            if sidebar {
                // Like Finder: Recent, All Items, projects and tags down the side.
                VStack(alignment: .leading, spacing: 0) {
                    WindowLights(mode: .window, extras: false) // top-left, like Finder
                        .padding(.leading, 14).padding(.top, 12).padding(.bottom, 2)
                    LibrarySidebar()
                }
                .frame(width: 200)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            }
            main
        }
        .frame(minWidth: sidebar ? 600 : 460, minHeight: 380)
        .stashChrome()
        .ignoresSafeArea() // the window buttons sit in the top row, like any Mac window
        .background(shortcuts)
    }

    private var main: some View {
        VStack(spacing: 0) {
            if !sidebar {
                // Two rows, like a browser: the project tabs get their own strip, the tools sit under them.
                HStack(spacing: 10) {
                    WindowLights(mode: .window, extras: false) // top-left, like any Mac window
                    ProjectBar(limit: 6)
                }
                    .padding(.horizontal, 12)
                    .padding(.top, 8)
                    .padding(.bottom, 5)
                    .background(Color.primary.opacity(0.035))
                    .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
            }
            HStack(spacing: 2) {
                LockButton(mode: .window)
                FrameModeButton(mode: .window).padding(.trailing, 6)
                SidebarToggle()
                Tool(.search) { searchField }
                SaveTarget()
                    .fixedSize()
                Spacer(minLength: 8)
                // View tools stay on the window; the magic wand is only here, in full screen. The rest: menu bar.
                // Recent is a list of what you copied: the board's view options and the wand don't apply there (gray).
                Group {
                    Tool(.arrange) { ArrangeMenu() }
                    Tool(.layout) { LayoutToggle() }
                    Tool(.organize) { OrganizeButton() }
                }
                .disabled(store.showingRecent)
                .opacity(store.showingRecent ? 0.35 : 1)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .padding(.top, sidebar ? 18 : 0)
            BoardView(compact: false)
            QuickBar(compact: false)
        }
    }

    private var searchField: some View {
        HStack(spacing: 5) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            SearchBox(placeholder: "Search \(store.tabTitle)") // searches this tab only
                .focused($searchFocused)
            if !store.search.isEmpty {
                Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(minWidth: 120, maxWidth: 240)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color.primary.opacity(0.05)))
    }

    /// Invisible buttons that carry keyboard shortcuts.
    private var shortcuts: some View {
        ZStack {
            Button("Search") { searchFocused = true }.keyboardShortcut("f")

        }
        .opacity(0)
        .frame(width: 0, height: 0)
        .allowsHitTesting(false)
    }
}

extension View {
    /// What both windows share: background, drop highlight, toasts, the note composer and shortcuts.
    func stashChrome() -> some View { modifier(StashChrome()) }
}

private struct StashChrome: ViewModifier {
    @EnvironmentObject var store: Store
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            // System Settings → Accessibility → Reduce motion: no sliding or springing anywhere.
            .transaction { if reduceMotion { $0.animation = nil; $0.disablesAnimations = true } }
            .background(VisualEffect().ignoresSafeArea())
            .overlay {
                if store.isDropTargeted { DropOverlay(name: store.dropTargetName) }
            }
            .overlay {
                if store.composingNote { NoteComposer().transition(.opacity) }
            }
            .overlay {
                if let names = store.organizePrompt { OrganizePrompt(names: names).transition(.opacity) }
            }
            .overlay {
                if let targets = store.pendingDelete {
                    DeletePrompt(targets: targets).transition(.opacity)
                }
                if let project = store.pendingProjectDelete {
                    DeleteProjectPrompt(projectID: project).transition(.opacity)
                }
                if store.showingRecentlyDeleted { RecentlyDeletedSheet().transition(.opacity) }
                if let targets = store.pendingBatchRename {
                    BatchRenamePrompt(targets: targets).transition(.opacity)
                }
                if let cleanup = store.linkCleanup {
                    LinkCleanupPrompt(cleanup: cleanup).transition(.opacity)
                }
            }
            .overlay(alignment: .bottom) { ToastView() }
            .background(
                ZStack {
                    Button("New Note") { store.perform(.newNote) }.keyboardShortcut("n")
                    Button("New Folder") { store.perform(.newFolder) }.keyboardShortcut("n", modifiers: [.command, .shift])
                }
                .opacity(0)
                .frame(width: 0, height: 0)
                .allowsHitTesting(false)
            )
    }
}

struct DropOverlay: View {
    let name: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, dash: [8, 6]))
            VStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill")
                    .font(.system(size: 34))
                Text("Drop to save to \(name)")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Color.accentColor)
        }
        .padding(6)
        .allowsHitTesting(false)
    }
}

struct VisualEffect: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

struct ToastView: View {
    @EnvironmentObject var store: Store

    var body: some View {
        if let message = store.toast {
            HStack(spacing: 10) {
                Text(message)
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(.secondary)
                if store.toastUndo {
                    Button("Undo") {
                        store.toast = nil
                        store.toastUndo = false
                        store.undo()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                    .accessibilityHint("Undoes the last change")
                }
            }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.regularMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(Color.primary.opacity(0.06)))
                .padding(.bottom, 44) // above the bottom bar
                .transition(.opacity)
        }
    }
}


/// The search field. What you type is searched once you pause for a moment (0.15 s), not on every key,
/// so typing stays smooth in a big library; clearing it (or a #tag) still shows at once.
struct SearchBox: View {
    @EnvironmentObject var store: Store
    let placeholder: String
    @State private var draft = ""
    @State private var pending: DispatchWorkItem?

    var body: some View {
        TextField(placeholder, text: $draft)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .onAppear { draft = store.search }
            .onChange(of: draft) {
                pending?.cancel()
                guard draft != store.search else { return }
                if draft.trimmingCharacters(in: .whitespaces).isEmpty { store.search = draft; return }
                let work = DispatchWorkItem { [draft] in MainActor.assumeIsolated { if store.search != draft { store.search = draft } } }
                pending = work
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
            }
            .onChange(of: store.search) { if store.search != draft { pending?.cancel(); draft = store.search } }
            .onSubmit { pending?.cancel(); store.search = draft }
    }
}
