import AVKit
import Carbon.HIToolbox
import SwiftUI
import WebKit

/// The Frame: the canvas, and one quiet row on top — the window buttons, zoom, Clear. No projects, no toolbars.
struct CanvasView: View {
    @ObservedObject private var canvas = CanvasStore.shared
    /// The library down the side (Recent, All Items, projects), to drag things in from.
    @AppStorage("canvas.library") private var showLibrary = false
    @State private var panStart: CGSize?
    @State private var zoomStart: Double?
    /// The selection box while you draw one (press, hold a moment, then drag — or ⇧-drag). Its own object, so only the
    /// box redraws as the mouse moves.
    @State private var box = MarqueeBox()
    @State private var marqueeBase: Set<UUID> = []
    @State private var dragMode: DragMode?
    private enum DragMode { case pan, select }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            HStack(spacing: 0) {
            if showLibrary {
                CanvasLibrary().frame(width: 220)
                Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 1)
            }
            GeometryReader { geo in
                ZStack(alignment: .topLeading) {
                    DotGrid(zoom: canvas.zoom, pan: canvas.pan)
                        .contentShape(Rectangle())
                        .gesture(panGesture)
                        .onTapGesture(count: 2, coordinateSpace: .local) { location in
                            // Double-click empty space: a new note right there.
                            let p = canvas.canvasPoint(location)
                            let id = canvas.add(.text, at: p, size: CGSize(width: 200, height: 90), text: "")
                            canvas.editingID = id
                        }
                        .onTapGesture {
                            CanvasLibraryPick.shared.id = nil
                            canvas.selection = []
                            canvas.editingID = nil
                            canvas.clearArmed = false
                        }
                    ForEach(canvas.items.sorted { $0.z < $1.z }) { item in
                        let frame = canvas.viewFrame(item)
                        // Only what's on screen (and a little around it) is made into a view.
                        if frame.intersects(CGRect(origin: .zero, size: geo.size).insetBy(dx: -200, dy: -200)) {
                            CanvasItemView(item: item, frame: frame)
                                .frame(width: frame.width, height: frame.height, alignment: .topLeading)
                                .offset(x: frame.minX, y: frame.minY)
                        }
                    }
                    if canvas.items.isEmpty { emptyHint.frame(width: geo.size.width, height: geo.size.height) }
                    MarqueeOverlay(box: box)
                    if let id = canvas.bigPageID, let item = canvas.items.first(where: { $0.id == id && $0.showsPage }) {
                        BigPage(item: item)
                            .frame(width: geo.size.width, height: geo.size.height)
                            .transition(.scale(scale: 0.9).combined(with: .opacity))
                            .zIndex(1)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .topLeading)
                .clipped()
                .simultaneousGesture(zoomGesture)
                .background(GeometryReader { inner in
                    Color.clear.onAppear { report(inner) }.onChange(of: inner.frame(in: .global)) { report(inner) }
                })
            }
            }
        }
        .frame(minWidth: 260, minHeight: 300)
        .stashChrome()
        .ignoresSafeArea() // the buttons sit in the window's top row, like any Mac window
    }

    private func report(_ geo: GeometryProxy) {
        canvas.viewSize = geo.size
        let f = geo.frame(in: .global)
        canvas.viewOrigin = f.origin
    }

    private var topBar: some View {
        HStack(spacing: 6) {
            WindowLights(mode: .floating)
            // Reframe: draw on the screen where the Frame should be; it takes that size and place (and locks there).
            Button { AppDelegate.shared.drawFrame(for: .floating) } label: {
                Image(systemName: "rectangle.dashed").font(.system(size: 11)).frame(width: 20, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Reframe — draw where the Frame should be on the screen")
            .accessibilityLabel("Reframe: draw the Frame's size and place")
            Button { AppDelegate.shared.openCompanion() } label: {
                Image(systemName: "macwindow.badge.plus").font(.system(size: 11)).frame(width: 20, height: 18).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open Swiss beside the canvas — a pop-up you can make a window or full screen")
            .accessibilityLabel("Open Swiss beside the canvas")
            Button { showLibrary.toggle() } label: {
                Image(systemName: "sidebar.left").font(.system(size: 11)).frame(width: 20, height: 18).contentShape(Rectangle())
                    .foregroundStyle(showLibrary ? Color.accentColor : Color.secondary)
            }
            .buttonStyle(.plain)
            .help(showLibrary ? "Hide the library" : "Show Recent, All Items and your projects — drag things onto the canvas")
            .accessibilityLabel(showLibrary ? "Hide the library" : "Show the library")
            Spacer(minLength: 4)
            // Select or Hand: what dragging on empty space does.
            HStack(spacing: 1) {
                toolButton(.select, symbol: "cursorarrow", help: "Select (V) — drag on empty space to draw a box")
                toolButton(.hand, symbol: "hand.raised", help: "Hand (H) — drag to move around (or hold Space)")
            }
            .padding(2)
            .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.05)))
            if canvas.cleared != nil {
                Button("Undo Clear") { canvas.undoClear() }
                    .buttonStyle(QuietButtonStyle()).font(.system(size: 11, weight: .medium)).foregroundStyle(Color.accentColor)
            }
            Button { canvas.zoom(by: 1 / 1.25) } label: { Image(systemName: "minus").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 22) }
                .buttonStyle(QuietButtonStyle()).help("Zoom out (⌘−, or pinch)").accessibilityLabel("Zoom out")
            Button { canvas.fitAll() } label: {
                Text("\(Int((canvas.zoom * 100).rounded()))%").font(.system(size: 10, weight: .medium)).monospacedDigit().frame(width: 36, height: 22)
            }
            .buttonStyle(QuietButtonStyle()).help("Show everything (⌘0)").accessibilityLabel("Zoom \(Int(canvas.zoom * 100)) percent. Show everything")
            Button { canvas.zoom(by: 1.25) } label: { Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).frame(width: 20, height: 22) }
                .buttonStyle(QuietButtonStyle()).help("Zoom in (⌘+, or pinch)").accessibilityLabel("Zoom in")
            Button {
                if canvas.clearArmed { canvas.clear() } else {
                    canvas.clearArmed = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { canvas.clearArmed = false }
                }
            } label: {
                HStack(spacing: 3) {
                    Image(systemName: "trash").font(.system(size: 10.5))
                    if canvas.clearArmed { Text("Clear all?").font(.system(size: 11, weight: .medium)) }
                }
                .frame(minWidth: 22, minHeight: 22).padding(.horizontal, canvas.clearArmed ? 6 : 0)
                .foregroundStyle(canvas.clearArmed ? Color.white : Color.secondary)
                .background(Capsule().fill(canvas.clearArmed ? Color.red.opacity(0.85) : .clear))
            }
            .buttonStyle(.plain)
            .disabled(canvas.items.isEmpty)
            .help(canvas.clearArmed ? "Click again to clear the whole frame (you can undo)" : "Clear the frame")
            .accessibilityLabel(canvas.clearArmed ? "Confirm: clear everything" : "Clear the frame")
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 10)
        .padding(.top, 8).padding(.bottom, 6)
        .background(WindowDragArea(locked: { UserDefaults.standard.bool(forKey: AppDelegate.floatingLockedKey) }))
        .overlay(alignment: .bottom) { Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1) }
    }

    private func toolButton(_ tool: CanvasStore.Tool, symbol: String, help: String) -> some View {
        let on = canvas.tool == tool
        return Button { canvas.tool = tool } label: {
            Image(systemName: symbol).font(.system(size: 11, weight: on ? .semibold : .regular))
                .frame(width: 24, height: 20)
                .foregroundStyle(on ? Color.accentColor : Color.secondary)
                .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(on ? Color.primary.opacity(0.1) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var emptyHint: some View {
        VStack(spacing: 8) {
            Image(systemName: "square.on.square.dashed").font(.system(size: 28, weight: .light)).foregroundStyle(.tertiary)
            Text("Drop anything here").font(.system(size: 13, weight: .semibold))
            Text("Photos, videos, links (YouTube plays here), text, files.\n⌘V pastes · double-click for a note · pinch or ⌘± to zoom · drag on empty space to select (Hand or Space-drag moves around)")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 260)
        }
        .allowsHitTesting(false)
    }

    /// Drag on empty space: with Select (V) it draws a box that selects everything it touches (⇧ / ⌘ add to what's
    /// selected); with Hand (H) — or holding Space — it moves around the canvas. Two-finger scrolling always moves around.
    private var panGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if dragMode == nil {
                    let spaceHeld = CGEventSource.keyState(.combinedSessionState, key: CGKeyCode(kVK_Space))
                    let flags = NSEvent.modifierFlags
                    dragMode = canvas.tool == .hand || spaceHeld ? (flags.contains(.shift) ? .select : .pan) : .select
                    marqueeBase = flags.contains(.command) || flags.contains(.shift) ? canvas.selection : []
                    panStart = canvas.pan
                }
                switch dragMode {
                case .select?:
                    let rect = CGRect(x: min(value.startLocation.x, value.location.x), y: min(value.startLocation.y, value.location.y),
                                      width: abs(value.location.x - value.startLocation.x), height: abs(value.location.y - value.startLocation.y))
                    box.rect = rect
                    let touched = canvas.items.filter { canvas.viewFrame($0).intersects(rect) }
                    let picked = Set(touched.map(\.id))
                    if picked != box.canvasPicked { // the box shows what it touches; selected once you let go
                        box.canvasPicked = picked
                        box.hits = touched.map { canvas.viewFrame($0) }
                    }
                default:
                    guard let start = panStart else { return }
                    canvas.pan = CGSize(width: start.width + value.translation.width, height: start.height + value.translation.height)
                }
            }
            .onEnded { _ in
                if dragMode == .pan { canvas.save() }
                if dragMode == .select { canvas.selection = marqueeBase.union(box.canvasPicked) } // once, when you let go
                dragMode = nil
                panStart = nil
                box.rect = nil
                box.hits = []
                box.canvasPicked = []
            }
    }

    private var zoomGesture: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                if zoomStart == nil { zoomStart = canvas.zoom }
                guard let start = zoomStart else { return }
                canvas.setZoom(start * value.magnification, around: value.startLocation)
            }
            .onEnded { _ in zoomStart = nil }
    }
}

/// The dotted background, moving and scaling with the canvas.
private struct DotGrid: View {
    let zoom: Double
    let pan: CGSize

    var body: some View {
        Canvas { context, size in
            var step = 24 * zoom
            while step < 12 { step *= 2 } // never denser than this
            let ox = pan.width.truncatingRemainder(dividingBy: step), oy = pan.height.truncatingRemainder(dividingBy: step)
            let dot = max(1, min(2, 1.4 * zoom))
            var path = Path()
            var y = oy
            while y < size.height {
                var x = ox
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x - dot / 2, y: y - dot / 2, width: dot, height: dot))
                    x += step
                }
                y += step
            }
            context.fill(path, with: .color(.primary.opacity(0.12)))
        }
    }
}

/// One thing on the canvas: drag it to move, drag its corner to resize, double-click to open or edit,
/// right-click for more. Videos and web players have a bar on top for moving them (the player takes clicks).
private struct CanvasItemView: View {
    @ObservedObject private var canvas = CanvasStore.shared
    @ObservedObject private var thumbs = ThumbnailService.shared
    let item: CanvasItem
    let frame: CGRect
    @State private var hovering = false
    @State private var draft = ""
    @State private var naming = false
    @State private var nameDraft = ""

    @ObservedObject private var live = CanvasLive.shared
    @Environment(\.colorScheme) private var colorScheme
    /// While a handle is dragged: where it would be (view points, from its own top left; a top or left handle moves
    /// that side). The canvas itself changes once, when you let go.
    @State private var liveRect: CGRect?

    /// The size to draw at: the live one while resizing. A video or page stays as it is until you let go (only its
    /// outline follows the mouse) — a playing player re-laid out on every mouse move stutters.
    private var size: CGSize {
        guard let liveRect, !playsInside else { return frame.size }
        return liveRect.size
    }
    /// Pages, links and files can take any shape; pictures, videos, notes and quotes keep theirs.
    private var freeShape: Bool { item.kind == .link || item.kind == .file }

    private var selected: Bool { canvas.selection.contains(item.id) }
    /// Videos and live pages take their own clicks; they're moved by the bar on top.
    private var playsInside: Bool { item.kind == .video || item.showsPage }

    var body: some View {
        ZStack(alignment: .topLeading) {
            content
                .frame(width: size.width, height: size.height)
                .clipShape(RoundedRectangle(cornerRadius: 8 * min(1, canvas.zoom), style: .continuous))
            if playsInside {
                // A grip to move a player by (the player itself takes the clicks).
                HStack(spacing: 4) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 9, weight: .bold))
                    Text(item.text ?? item.link?.host ?? "Video").font(.system(size: 10, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if item.showsPage { PageButtons(item: item) }
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 7)
                .frame(width: size.width, height: 20)
                .background(Color.black.opacity(0.55))
                .contentShape(Rectangle())
                .opacity(hovering || selected ? 1 : 0)
                .gesture(moveGesture)
                .onTapGesture(count: 2) { open() }
                .onTapGesture { select() }
                .contextMenu { menu }
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8 * min(1, canvas.zoom), style: .continuous)
                // A quote shows it's chosen with a quiet grey ring, not the coloured one.
                .strokeBorder(item.quote == true ? Color.primary.opacity(0.3) : Color.accentColor, lineWidth: selected ? (item.quote == true ? 1 : 2) : 0)
        )
        .overlay(alignment: .topLeading) { resizeHandles }
        .overlay(alignment: .bottom) {
            // Its name, if you gave it one.
            if let name = item.name, !name.isEmpty {
                Text(name)
                    .font(.system(size: max(9, 11 * canvas.zoom), weight: .medium))
                    .lineLimit(1)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(.regularMaterial))
                    .fixedSize()
                    .offset(y: max(9, 11 * canvas.zoom) + 8)
                    .allowsHitTesting(false)
            }
        }
        .popover(isPresented: $naming, arrowEdge: .bottom) {
            HStack(spacing: 6) {
                TextField("Name", text: $nameDraft)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 180)
                    .onSubmit { commitName() }
                Button("Done") { commitName() }.keyboardShortcut(.defaultAction)
            }
            .padding(10)
        }
        .shadow(color: .black.opacity(item.kind == .text ? 0.08 : 0.12), radius: 3, y: 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .modifier(CardClicks(on: !playsInside, open: open, select: select, move: moveGesture) { menu })
        .offset(playsInside ? .zero : CGSize(width: liveRect?.minX ?? 0, height: liveRect?.minY ?? 0)) // a top or left side moving
        .offset(live.ids.contains(item.id) ? live.offset : .zero) // moving: drawn shifted, saved when you let go
        .accessibilityElement(children: .contain)
        .accessibilityLabel(label)
    }

    private var label: String {
        switch item.kind {
        case .text: "\(item.quote == true ? "Quote" : "Note"): \(item.name ?? item.text ?? "")"
        case .image: "Picture"
        case .link: "Link: \(item.text ?? item.url ?? "")"
        case .video: "Video: \(item.text ?? item.url ?? "")"
        case .file: "File: \(item.text ?? "")"
        }
    }

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .image:
            if let url = canvas.fileURL(item), let image = ThumbnailService.shared.image(at: url, maxPixels: Self.pixels(frame)) {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else {
                Rectangle().fill(Color.primary.opacity(0.06))
                    .overlay(Image(systemName: "photo").foregroundStyle(.tertiary))
            }
        case .text:
            noteView
        case .link where item.showsPage:
            if canvas.bigPageID == item.id {
                // Open big: the same page is up there (one page can't be in two places).
                Color.primary.opacity(0.06).overlay(Image(systemName: "macwindow").foregroundStyle(.tertiary))
            } else if let url = item.link {
                WebPageView(page: WebPages.shared.page(for: item.id, url: url), zoom: canvas.zoom)
                    .background(Color(nsColor: .textBackgroundColor))
            }
        case .link:
            HStack(spacing: 8 * canvas.zoom) {
                Image(systemName: "link").font(.system(size: 13 * canvas.zoom, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30 * canvas.zoom, height: 30 * canvas.zoom)
                    .background(RoundedRectangle(cornerRadius: 7 * canvas.zoom).fill(FolderStyle.linker.color))
                VStack(alignment: .leading, spacing: 1) {
                    Text(item.text ?? item.link?.host ?? "Link").font(.system(size: 12 * canvas.zoom, weight: .medium)).lineLimit(2)
                    Text(item.link?.host ?? "").font(.system(size: 10 * canvas.zoom)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10 * canvas.zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topTrailing) {
                // Show the page itself, right here.
                if hovering, item.link.map(Safety.isWebURL) == true {
                    Button { canvas.togglePage(item.id) } label: {
                        Image(systemName: "macwindow").font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(.regularMaterial))
                    }
                    .buttonStyle(.plain)
                    .padding(4)
                    .help("Show the page here, on the canvas")
                    .accessibilityLabel("Show page here")
                }
            }
        case .video:
            if let link = item.link, let id = CanvasStore.youTubeID(link) {
                YouTubePlayer(videoID: id)
            } else if let file = canvas.fileURL(item) {
                VideoFilePlayer(url: file)
            } else {
                Color.black
            }
        case .file:
            VStack(spacing: 4 * canvas.zoom) {
                if let url = canvas.fileURL(item) {
                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().aspectRatio(contentMode: .fit)
                        .frame(width: 56 * canvas.zoom, height: 56 * canvas.zoom)
                }
                Text(item.text ?? "File").font(.system(size: 11 * canvas.zoom, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
            }
            .padding(6 * canvas.zoom)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .textBackgroundColor).opacity(0.7))
        }
    }

    /// A note's text grows and shrinks with the note: its size is part of the note (made bigger, it reads bigger).
    /// It's laid out once, at 13 pt, and drawn scaled — so while the sizer is dragged nothing re-wraps (no words jumping
    /// between lines), and the lines break in the same places at any size or zoom.
    private var scale: CGFloat { canvas.zoom * item.textSize / 13 * (frame.width > 0 ? size.width / frame.width : 1) }

    private func noteFont(_ size: CGFloat) -> Font { .system(size: size, design: item.quote == true ? .serif : .default) }

    private var dark: Bool { colorScheme == .dark }
    /// White text in dark mode (on a dark note or quote), black in light mode.
    private var ink: Color { dark ? Color.white.opacity(0.92) : Color.black.opacity(0.85) }

    /// A typed note is a yellow sticky; copied text is a quote: a white, see-through card, readable over anything.
    /// In dark mode they go dark (a deep amber note, a dark glass quote) with white text.
    @ViewBuilder private var noteFill: some View {
        if item.quote == true {
            ZStack {
                Rectangle().fill(.ultraThinMaterial).environment(\.colorScheme, dark ? .dark : .light)
                (dark ? Color.black.opacity(0.35) : Color.white.opacity(0.6))
            }
        } else {
            dark ? Color(red: 0.42, green: 0.34, blue: 0.1) : Color(red: 1.0, green: 0.93, blue: 0.62)
        }
    }

    @ViewBuilder private func quoteMark(_ textSize: CGFloat) -> some View {
        if item.quote == true {
            Text("\u{201C}")
                .font(.system(size: textSize * 1.6, weight: .bold, design: .serif))
                .foregroundStyle(dark ? Color.white.opacity(0.45) : Color.black.opacity(0.32))
                .frame(height: textSize * 0.9, alignment: .top)
                .frame(maxWidth: .infinity, alignment: item.text?.isRightToLeft == true ? .trailing : .leading)
        }
    }

    @ViewBuilder private var noteView: some View {
        if canvas.editingID == item.id {
            VStack(spacing: 0) {
                quoteMark(13 * scale).padding([.horizontal, .top], 9 * scale)
                TextEditor(text: $draft)
                    .font(noteFont(13 * scale))
                    .environment(\.layoutDirection, draft.isRightToLeft ? .rightToLeft : .leftToRight) // Hebrew from the right
                    .scrollContentBackground(.hidden)
                    .padding(6 * scale)
            }
            .background(noteFill)
            .foregroundStyle(ink)
            .onAppear { draft = item.text ?? "" }
            .onChange(of: draft) { canvas.update(item.id) { $0.text = draft } }
            .onDisappear { if draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { canvas.delete([item.id]) } }
        } else {
            let s = max(0.01, scale)
            VStack(spacing: 0) {
                quoteMark(13)
                Text(item.text ?? "")
                    .font(noteFont(13))
                    .foregroundStyle(ink)
                    .multilineTextAlignment(item.text?.isRightToLeft == true ? .trailing : .leading)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: item.text?.isRightToLeft == true ? .topTrailing : .topLeading)
            }
            .padding(9)
            .frame(width: size.width / s, height: size.height / s)
            .scaleEffect(s, anchor: .topLeading)
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            .background(noteFill)
        }
    }

    @ViewBuilder private var menu: some View {
        Button(item.kind == .text ? "Edit" : item.kind == .link ? "Open in Browser" : "Open") { open() }
        if item.kind == .link, item.link.map(Safety.isWebURL) == true {
            Button(item.showsPage ? "Show as Link" : "Show Page Here") { canvas.togglePage(item.id) }
        }
        Button("Copy") { canvas.selection = [item.id]; canvas.copySelection() }
        if let file = canvas.fileURL(item) {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        Button(item.name?.isEmpty == false ? "Rename…" : "Name…") { nameDraft = item.name ?? ""; naming = true }
        Button("Bigger") { canvas.scale(canvas.selection.contains(item.id) ? canvas.selection : [item.id], by: 1.25) }
        Button("Smaller") { canvas.scale(canvas.selection.contains(item.id) ? canvas.selection : [item.id], by: 1 / 1.25) }
        Button("Bring to Front") { canvas.bringToFront(item.id) }
        Divider()
        Button("Delete", role: .destructive) { canvas.delete(canvas.selection.contains(item.id) ? canvas.selection : [item.id]) }
    }

    private func commitName() {
        let name = nameDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        canvas.update(item.id) { $0.name = name.isEmpty ? nil : name }
        naming = false
    }

    private func select() {
        canvas.clearArmed = false
        let flags = NSEvent.modifierFlags
        if flags.contains(.shift) || flags.contains(.command) || flags.contains(.control) {
            if selected { canvas.selection.remove(item.id) } else { canvas.selection.insert(item.id) }
        } else {
            canvas.selection = [item.id]
        }
        if canvas.editingID != item.id { canvas.editingID = nil }
    }

    private func open() {
        switch item.kind {
        case .text: canvas.editingID = item.id
        case .link: if let url = WebPages.shared.existing(item.id)?.currentURL ?? item.link { Safety.openLink(url) } // where the page is now
        case .image: if let url = canvas.fileURL(item) { QuickLook.shared.show([url]) }
        case .file, .video:
            if let url = canvas.fileURL(item) { Safety.open(url) } else if let url = item.link { Safety.openLink(url) }
        }
    }

    /// Moving: the dragged things are drawn shifted while you drag (nothing is saved or redrawn per mouse move);
    /// the canvas gets their new place once, when you let go.
    private var moveGesture: some Gesture {
        DragGesture(minimumDistance: 2)
            .onChanged { value in
                if live.ids.isEmpty {
                    if !selected { canvas.selection = [item.id] }
                    canvas.bringToFront(item.id)
                    live.ids = canvas.selection.isEmpty ? [item.id] : canvas.selection
                }
                live.offset = value.translation
            }
            .onEnded { value in
                let ids = live.ids
                live.ids = []
                live.offset = .zero
                canvas.move(ids, by: CGSize(width: value.translation.width / canvas.zoom, height: value.translation.height / canvas.zoom))
            }
    }

    /// Resizing: shown at the new size while you drag; the canvas gets it once, when you let go.
    // MARK: Resizing

    /// Where a handle sits: a corner, or the middle of a side (sides only for things that can take any shape).
    private enum Handle: CaseIterable {
        case topLeft, top, topRight, right, bottomRight, bottom, bottomLeft, left
        var x: CGFloat { [.topLeft, .left, .bottomLeft].contains(self) ? 0 : [.top, .bottom].contains(self) ? 0.5 : 1 }
        var y: CGFloat { [.topLeft, .top, .topRight].contains(self) ? 0 : [.left, .right].contains(self) ? 0.5 : 1 }
        var isCorner: Bool { x != 0.5 && y != 0.5 }
        var movesLeft: Bool { x == 0 }
        var movesTop: Bool { y == 0 }
        var cursor: NSCursor {
            if !isCorner { return x == 0.5 ? .resizeUpDown : .resizeLeftRight }
            if #available(macOS 15.0, *) {
                let position: NSCursor.FrameResizePosition = switch self {
                case .topLeft: .topLeft
                case .topRight: .topRight
                case .bottomLeft: .bottomLeft
                default: .bottomRight
                }
                return .frameResize(position: position, directions: .all)
            }
            return .crosshair
        }
    }

    /// Handles on the corners (and, for pages, links and files, the sides): shown while it's chosen or under the mouse,
    /// with a generous grab area. While dragging, an outline and the new size follow the mouse.
    @ViewBuilder private var resizeHandles: some View {
        let rect = liveRect ?? CGRect(origin: .zero, size: frame.size)
        ZStack(alignment: .topLeading) {
            if let liveRect {
                RoundedRectangle(cornerRadius: 8 * min(1, canvas.zoom), style: .continuous)
                    .strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1.5, dash: [5, 3]))
                    .frame(width: liveRect.width, height: liveRect.height)
                    .offset(x: playsInside ? liveRect.minX : 0, y: playsInside ? liveRect.minY : 0)
                    .allowsHitTesting(false)
                Text("\(Int((liveRect.width / canvas.zoom).rounded())) × \(Int((liveRect.height / canvas.zoom).rounded()))")
                    .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Capsule().fill(Color.accentColor))
                    .foregroundStyle(.white)
                    .fixedSize()
                    .offset(x: (playsInside ? liveRect.minX : 0) + liveRect.width / 2 - 30,
                            y: (playsInside ? liveRect.minY : 0) + liveRect.height + 6)
                    .allowsHitTesting(false)
            }
            if selected || hovering || liveRect != nil {
                let origin = playsInside ? rect.origin : .zero
                ForEach(Handle.allCases.filter { $0.isCorner || freeShape }, id: \.self) { handle in
                    handleDot(handle)
                        .position(x: origin.x + rect.width * handle.x, y: origin.y + rect.height * handle.y)
                }
            }
        }
        .frame(width: rect.width, height: rect.height, alignment: .topLeading)
    }

    private func handleDot(_ handle: Handle) -> some View {
        Group {
            if handle.isCorner {
                Circle().fill(Color.white).frame(width: 10, height: 10)
                    .overlay(Circle().strokeBorder(Color.accentColor, lineWidth: 2))
            } else {
                Capsule().fill(Color.white)
                    .frame(width: handle.x == 0.5 ? 18 : 6, height: handle.x == 0.5 ? 6 : 18)
                    .overlay(Capsule().strokeBorder(Color.accentColor, lineWidth: 1.5))
            }
        }
        .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
        .opacity(selected || liveRect != nil ? 1 : 0.75)
        .frame(width: 24, height: 24) // the grab area, bigger than the dot
        .contentShape(Rectangle())
        .highPriorityGesture(resizeGesture(handle)) // wins over moving
        .onHover { inside in if inside { handle.cursor.push() } else { NSCursor.pop() } }
        .help(freeShape ? "Drag to resize (⇧ keeps its shape)" : "Drag to make it bigger or smaller")
        .accessibilityLabel("Resize")
    }

    private func resizeGesture(_ handle: Handle) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global) // global: the view moves while you drag
            .onChanged { value in
                let minW = 40 * canvas.zoom, minH = 30 * canvas.zoom
                let dx = value.translation.width, dy = value.translation.height
                var w = frame.width, h = frame.height
                if handle.x == 1 { w += dx } else if handle.x == 0 { w -= dx }
                if handle.y == 1 { h += dy } else if handle.y == 0 { h -= dy }
                w = max(minW, w)
                h = max(minH, h)
                // Its shape stays: always for pictures, videos and notes; with ⇧ for the rest.
                let keep = !freeShape || NSEvent.modifierFlags.contains(.shift)
                if keep, handle.isCorner, frame.width > 0, frame.height > 0 {
                    let ratio = frame.height / frame.width
                    if abs(w - frame.width) * ratio >= abs(h - frame.height) { h = w * ratio } else { w = h / ratio }
                    if h < minH { h = minH; w = h / ratio }
                }
                liveRect = CGRect(x: handle.movesLeft ? frame.width - w : 0, y: handle.movesTop ? frame.height - h : 0, width: w, height: h)
            }
            .onEnded { _ in
                if let r = liveRect {
                    let z = canvas.zoom
                    canvas.setFrame(item.id, CGRect(x: item.x + r.minX / z, y: item.y + r.minY / z, width: r.width / z, height: r.height / z))
                }
                liveRect = nil
            }
    }

    /// Pictures are made at about the size they're shown (in steps, so zooming doesn't remake them all the time).
    private static func pixels(_ frame: CGRect) -> Int {
        let needed = max(frame.width, frame.height) * 2
        return [256, 512, 1024, 2048].first { Double($0) >= needed } ?? 2048
    }
}

/// Moving, clicking and right-clicking a card. A player gets none of these on itself — they'd take the mouse from its
/// own controls (the volume slider, the timeline); it's moved and right-clicked by its grip, and selected by a click
/// (CanvasStore.selectPlayer, which lets the click through to the player).
private struct CardClicks<Menu: View, Move: Gesture>: ViewModifier {
    let on: Bool
    let open: () -> Void
    let select: () -> Void
    let move: Move
    @ViewBuilder let menu: () -> Menu

    func body(content: Content) -> some View {
        if on {
            content
                .gesture(move)
                .onTapGesture(count: 2) { open() }
                .onTapGesture { select() }
                .contextMenu { menu() }
        } else {
            content
        }
    }
}

// MARK: - Players

/// A live page opened big: it fills the canvas, the same page as in its card (where you were, what's playing).
private struct BigPage: View {
    let item: CanvasItem

    var body: some View {
        let page = WebPages.shared.page(for: item.id, url: item.link ?? URL(string: "about:blank")!)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(page.web.title.flatMap { $0.isEmpty ? nil : $0 } ?? item.text ?? item.link?.host ?? "Page")
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                PageButtons(item: item, big: true)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Color.black.opacity(0.75))
            WebPageView(page: page, zoom: 1)
        }
        .background(Color(nsColor: .textBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .padding(6)
    }
}

/// On a live page's bar: back, reload, open in your browser, and back to a plain link.
private struct PageButtons: View {
    let item: CanvasItem
    var big = false
    @ObservedObject private var page: WebPage

    init(item: CanvasItem, big: Bool = false) {
        self.item = item
        self.big = big
        page = WebPages.shared.page(for: item.id, url: item.link ?? URL(string: "about:blank")!)
    }

    var body: some View {
        HStack(spacing: 2) {
            button("chevron.left", "Back") { page.goBack() }.disabled(!page.canGoBack).opacity(page.canGoBack ? 1 : 0.4)
            button(page.loading ? "xmark" : "arrow.clockwise", page.loading ? "Stop" : "Reload") {
                if page.loading { page.web.stopLoading() } else { page.reload() }
            }
            button("safari", "Open in your browser") { if let url = page.currentURL ?? item.link { Safety.openLink(url) } }
            if big {
                button("arrow.down.right.and.arrow.up.left", "Back to the canvas (Esc)") { CanvasStore.shared.setBigPage(nil) }
            } else {
                button("arrow.up.left.and.arrow.down.right", "Open big — fill the canvas") { CanvasStore.shared.setBigPage(item.id) }
                button("rectangle.compress.vertical", "Show as a link again") { CanvasStore.shared.togglePage(item.id) }
            }
        }
    }

    private func button(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9.5, weight: .semibold)).frame(width: 20, height: 18).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A YouTube video playing right on the canvas (YouTube's own player).
private struct YouTubePlayer: NSViewRepresentable {
    let videoID: String

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.mediaTypesRequiringUserActionForPlayback = []
        config.preferences.isElementFullscreenEnabled = true
        let web = WKWebView(frame: .zero, configuration: config)
        web.setValue(false, forKey: "drawsBackground")
        web.navigationDelegate = context.coordinator
        web.uiDelegate = context.coordinator
        load(web, context.coordinator)
        return web
    }

    /// Called on every redraw (hovering, selecting…): the player reloads only if it's a different video —
    /// reloading it here each time is what reset its volume bar and controls under the mouse.
    func updateNSView(_ web: WKWebView, context: Context) {
        if context.coordinator.loaded != videoID { load(web, context.coordinator) }
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    /// The player stays a player: a link clicked inside it (the title, "Watch on YouTube") opens in your browser
    /// instead of turning the canvas into a web page.
    final class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        var loaded: String?

        @MainActor func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                                decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            let leaving = action.targetFrame?.isMainFrame == true && action.navigationType == .linkActivated
            if leaving, let url = action.request.url {
                if Safety.isWebURL(url) { NSWorkspace.shared.open(url) }
                decisionHandler(.cancel)
            } else {
                decisionHandler(.allow)
            }
        }

        // Links that ask for a new window.
        @MainActor func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
                                for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
            if let url = action.request.url, Safety.isWebURL(url) { NSWorkspace.shared.open(url) }
            return nil
        }
    }

    private func load(_ web: WKWebView, _ coordinator: Coordinator) {
        coordinator.loaded = videoID
        if TestMode.isOn { FileHandle.standardError.write("youtube load \(videoID)\n".data(using: .utf8)!) }
        // The id has only letters, digits, - and _ (checked when the link came in), so it's safe in the address.
        let html = """
        <!doctype html><html><head><meta name="referrer" content="strict-origin-when-cross-origin">
        <style>html,body{margin:0;height:100%;background:#000;overflow:hidden}iframe{border:0;width:100%;height:100%}</style></head>
        <body><iframe src="https://www.youtube.com/embed/\(videoID)?playsinline=1&rel=0&modestbranding=1"
        allow="autoplay; encrypted-media; picture-in-picture; fullscreen" allowfullscreen
        referrerpolicy="strict-origin-when-cross-origin"></iframe></body></html>
        """
        web.loadHTMLString(html, baseURL: URL(string: "https://swiss.app/"))
    }
}

/// A video file on the canvas, with the Mac's own controls.
private struct VideoFilePlayer: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> AVPlayerView {
        let view = AVPlayerView()
        view.controlsStyle = .inline
        view.player = AVPlayer(url: url)
        view.allowsPictureInPicturePlayback = true
        return view
    }

    func updateNSView(_ view: AVPlayerView, context: Context) {
        if (view.player?.currentItem?.asset as? AVURLAsset)?.url != url { view.player = AVPlayer(url: url) }
    }

    static func dismantleNSView(_ view: AVPlayerView, coordinator: ()) {
        view.player?.pause() // nothing keeps playing after it's gone
        view.player = nil
    }
}

/// What's being moved on the canvas right now, and how far (view points) — only the moving items follow it.
@MainActor
final class CanvasLive: ObservableObject {
    static let shared = CanvasLive()
    @Published var offset: CGSize = .zero
    var ids: Set<UUID> = []
}
