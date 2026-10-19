import AppKit
import SwiftUI

/// The welcome tour: the first time Swiss opens, a small window walks through its tools, one page at a time.
/// It moves on by itself (Stay holds a page as long as you like), or step with the arrows; Help → Welcome Tour
/// shows it again.
enum WelcomeTour {
    static let seenKey = "welcome.seen"
    private static var window: NSPanel?

    /// On first launch only.
    @MainActor static func showIfFirstLaunch() {
        guard !UserDefaults.standard.bool(forKey: seenKey) else { return }
        show()
    }

    @MainActor static func show() {
        if let window { window.makeKeyAndOrderFront(nil); NSApp.activate(); return }
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 540, height: 420),
                            styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1) // over the pop-up
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.contentView = NSHostingView(rootView: WelcomeTourView { close() })
        panel.center()
        NotificationCenter.default.addObserver(forName: NSWindow.willCloseNotification, object: panel, queue: .main) { _ in
            MainActor.assumeIsolated {
                UserDefaults.standard.set(true, forKey: seenKey)
                WelcomeTour.window = nil
            }
        }
        window = panel
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    @MainActor static func close() { window?.close() }
}

/// One page of the tour.
private struct TourPage {
    let symbol: String
    let color: Color
    let title: String
    let text: String
    var keys: [String] = []
}

private let tourPages: [TourPage] = [
    TourPage(symbol: "sparkles", color: Color(red: 0.87, green: 0.28, blue: 0.22),
             title: "Welcome to Swiss",
             text: "A pocket knife for references: save links, pictures, files and notes from anywhere, and find them in a second.",
             keys: ["⌥Space opens Swiss"]),
    TourPage(symbol: "clock.arrow.circlepath", color: Color(red: 0.35, green: 0.55, blue: 0.85),
             title: "Recent",
             text: "What you copy and screenshot lands here (turn it on in Settings → Capture). Keep puts it into a project; the rest goes away by itself.",
             keys: ["Space looks", "↩ keeps", "⌘A all"]),
    TourPage(symbol: "rectangle.stack.fill", color: Color(red: 0.55, green: 0.66, blue: 0.80),
             title: "Projects are tabs",
             text: "Drop, paste or drag things into a project. × closes a tab — the project stays. Delete projects from All Projects.",
             keys: ["⌘V paste", "⌃Tab next tab", "⌘T new project"]),
    TourPage(symbol: "folder.fill", color: Color(red: 0.37, green: 0.65, blue: 0.93),
             title: "Notes and folders",
             text: "Make a note, a folder, or a Linker, PhotoBook, Notepad or Files folder. Copy and paste whole folders between projects.",
             keys: ["⌘1 note", "⌘2 folder", "⌘C ⌘V copies"]),
    TourPage(symbol: "wand.and.stars", color: Color(red: 0.62, green: 0.45, blue: 0.85),
             title: "The wand",
             text: "One click sorts a messy board: links into Linkers, pictures into PhotoBooks, notes into Notepads, everything else into Files.",
             keys: ["Big window only"]),
    TourPage(symbol: "externaldrive.connected.to.line.below", color: Color(red: 0.20, green: 0.62, blue: 0.66),
             title: "Connected folders",
             text: "Connect any Finder folder and work in it like a project — rename, move, tag and sort, and Finder follows along.",
             keys: ["Real files", "Nothing copied"]),
    TourPage(symbol: "square.on.square.dashed", color: Color(red: 0.93, green: 0.62, blue: 0.24),
             title: "The Frame",
             text: "A free canvas on top of every app: pictures, notes, links and a playing YouTube video, zoom and pan. Its library brings things in.",
             keys: ["⌘Z undo", "V select", "H hand"]),
    TourPage(symbol: "circle.grid.cross.fill", color: Color(red: 0.36, green: 0.72, blue: 0.40),
             title: "Three sizes",
             text: "Green grows Swiss: the pop-up, the window, then the whole screen. Orange steps back. Red closes. That's it — have fun.",
             keys: ["🔴 close", "🟠 smaller", "🟢 bigger"]),
]

private struct WelcomeTourView: View {
    let close: () -> Void
    @State private var page = 0
    @State private var forward = true
    /// Moves on by itself unless you Stay.
    @State private var staying = false
    @State private var progress: CGFloat = 0
    @State private var floating = false
    private let pageSeconds: Double = 6
    private let tick = Timer.publish(every: 0.05, on: .main, in: .common).autoconnect()

    private var last: Bool { page == tourPages.count - 1 }

    var body: some View {
        let current = tourPages[page]
        VStack(spacing: 0) {
            ZStack {
                // The picture: the page's tool, floating gently on its color.
                Circle()
                    .fill(current.color.opacity(0.16))
                    .frame(width: 150, height: 150)
                    .scaleEffect(floating ? 1.06 : 0.96)
                Circle()
                    .strokeBorder(current.color.opacity(0.35), lineWidth: 1.5)
                    .frame(width: 186, height: 186)
                    .scaleEffect(floating ? 0.97 : 1.04)
                if page == 0, let icon = NSApp.applicationIconImage {
                    Image(nsImage: icon).resizable().frame(width: 104, height: 104)
                        .offset(y: floating ? -4 : 4)
                } else {
                    Image(systemName: current.symbol)
                        .font(.system(size: 54, weight: .medium))
                        .foregroundStyle(current.color)
                        .symbolEffect(.bounce, value: page)
                        .offset(y: floating ? -4 : 4)
                }
            }
            .frame(height: 200)
            .id("art\(page)")
            .transition(.asymmetric(insertion: .scale(scale: 0.7).combined(with: .opacity),
                                    removal: .opacity))
            VStack(spacing: 10) {
                Text(current.title).font(.system(size: 22, weight: .semibold))
                Text(current.text)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 400)
                HStack(spacing: 6) {
                    ForEach(current.keys, id: \.self) { key in
                        Text(key)
                            .font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Capsule().fill(Color.primary.opacity(0.07)))
                    }
                }
                .padding(.top, 2)
            }
            .id("text\(page)")
            .transition(.asymmetric(insertion: .move(edge: forward ? .trailing : .leading).combined(with: .opacity),
                                    removal: .move(edge: forward ? .leading : .trailing).combined(with: .opacity)))
            Spacer(minLength: 12)
            controls
        }
        .padding(.top, 28).padding(.horizontal, 24).padding(.bottom, 18)
        .frame(width: 540, height: 420)
        .background(.regularMaterial)
        .onAppear {
            withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) { floating = true }
        }
        .onReceive(tick) { _ in
            guard !staying, !last else { return }
            progress += 0.05 / pageSeconds
            if progress >= 1 { go(page + 1) }
        }
    }

    private var controls: some View {
        HStack(spacing: 12) {
            Button("Skip") { close() }
                .buttonStyle(.plain).foregroundStyle(.secondary).font(.system(size: 12))
                .opacity(last ? 0 : 1)
            Spacer()
            // Where you are; the page you're on fills up until it moves on.
            HStack(spacing: 5) {
                ForEach(tourPages.indices, id: \.self) { i in
                    Capsule()
                        .fill(Color.primary.opacity(0.15))
                        .overlay(alignment: .leading) {
                            Capsule().fill(Color.accentColor)
                                .frame(width: i < page ? 22 : i == page ? (last ? 22 : 22 * progress) : 0)
                        }
                        .frame(width: i == page ? 22 : 7, height: 7)
                        .clipShape(Capsule())
                        .onTapGesture { go(i) }
                }
            }
            Spacer()
            Button { go(page - 1) } label: { Image(systemName: "chevron.left") }
                .disabled(page == 0)
                .help("Back")
            if !last {
                Button(staying ? "Keep Going" : "Stay") { staying.toggle() }
                    .help(staying ? "Move on by itself again" : "Stay on this page as long as you like")
            }
            Button(last ? "Start Using Swiss" : "Next") { last ? close() : go(page + 1) }
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.regular)
    }

    private func go(_ next: Int) {
        guard tourPages.indices.contains(next), next != page else { return }
        forward = next > page
        withAnimation(.spring(duration: 0.45, bounce: 0.25)) { page = next }
        progress = 0
    }
}
