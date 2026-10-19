import SwiftUI

/// Icons (cards in columns) or List (one row each), switched in the header.
enum BoardLayout: String {
    case icons, list
    static let key = "board.layout"
}

/// One saved thing: a quiet card on the board, or a row in List view.
struct CardView: View {
    @EnvironmentObject var store: Store
    let item: Item
    var asRow = false
    /// Big window with Quotes on: a note shows its whole text, ready to copy.
    var asQuote = false
    /// The small pop-up: everything is a small icon tile with its name, like the folders.
    var asTile = false
    /// Far off-screen on a big board: just its shape and name (same size), none of the clicking, dragging,
    /// menus or pictures. It becomes the full card as it scrolls near.
    var lite = false
    @State private var justCopied = false
    /// Position in the list, for the alternating stripes.
    var rowIndex: Int? = nil
    @State private var hovering = false
    @State private var editing = false
    @State private var draft = NSAttributedString()
    @State private var draftName = ""
    @FocusState private var nameFocused: Bool

    /// Its picture, at about the size it's shown. Made in the background (ThumbnailService redraws the card when ready).
    private var thumb: NSImage? { store.displayImage(item, maxPixels: asTile || asRow ? 256 : 900) }
    @ObservedObject private var thumbs = ThumbnailService.shared
    @ObservedObject private var mark: SelectFlag
    private var selected: Bool { mark.on }

    init(item: Item, asRow: Bool = false, asQuote: Bool = false, asTile: Bool = false, lite: Bool = false, rowIndex: Int? = nil) {
        self.item = item
        self.asRow = asRow
        self.asQuote = asQuote
        self.asTile = asTile
        self.lite = lite
        self.rowIndex = rowIndex
        _mark = ObservedObject(wrappedValue: SelectionCenter.shared.flag(.item(item.id)))
    }

    var body: some View {
        if TestMode.isOn { Perf.cardBodies += 1 }
        return Group {
            if lite { card } else { fullBody }
        }
    }

    private var fullBody: some View {
        Group {
            if asRow { row } else { card }
        }
        // VoiceOver: "Note: Shopping list, selected", with its buttons inside.
        .accessibilityElement(children: .contain)
        .accessibilityLabel(spokenName)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityAction(named: "Open") { primaryAction() }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            // One tap gesture reads the click count, so single clicks select instantly.
            let event = NSApp.currentEvent
            if (event?.clickCount ?? 1) >= 2 {
                primaryAction()
            } else {
                store.click(.item(item.id), modifiers: event?.modifierFlags ?? [])
            }
        }
        .onDrag {
            store.draggingItemID = item.id
            store.draggingFolderID = nil
            return store.itemProvider(for: item)
        }
        // Icons view handles press-and-hold itself (BoardDrag), so a held press can still turn into a drag.
        .simultaneousGesture(LongPressGesture(minimumDuration: asRow ? 0.6 : 100_000).onEnded { _ in
            if item.kind == .text { startEditing() } else { store.renamingItemID = item.id }
        })
        .contextMenu { menu }
        .popover(isPresented: $editing, arrowEdge: .trailing) { editor }
        .popover(isPresented: Binding(get: { !asRow && store.renamingItemID == item.id },
                                      set: { if !$0, store.renamingItemID == item.id { store.renamingItemID = nil } })) {
            renameField.frame(width: 240).padding(10)
        }
        .onChange(of: store.renamingItemID) {
            if store.renamingItemID == item.id, item.kind == .text {
                store.renamingItemID = nil
                startEditing() // notes are named by their text: Return edits them
            }
        }
        .help(item.kind == .text ? "Double-click to edit · drag onto a folder or out to another app"
              : item.kind == .image ? "Double-click or Space to preview · drag onto a folder or out to another app"
              : "Double-click to open · drag onto a folder or out to another app")
    }

    // MARK: Card

    /// Selected cards sit on a soft gray box, like folders — no blue outline.
    private var card: some View {
        Group {
            if asTile {
                tile
            } else if item.kind == .text && asQuote {
                quoteCard
            } else if item.kind == .text {
                noteTile
            } else {
                cardBody
                    .padding(5)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.primary.opacity(selected ? 0.1 : 0))
                    )
            }
        }
    }

    /// A note looks like a folder: a big note pad, and a short name under it —
    /// its title if the first line is short, otherwise a glimpse of what's written.
    private var noteTile: some View {
        VStack(spacing: 5) {
            NotePadIcon(size: 58)
                .padding(8)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.1 : (hovering ? 0.045 : 0)))
                )
            HStack(spacing: 4) {
            TagDots(tags: item.colorTags ?? [])
            Text(noteName)
                .font(.system(size: 11, weight: .medium))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .foregroundStyle(selected ? Color.white : Color.primary)
                .padding(.horizontal, 6)
                .padding(.vertical, 1.5)
                .background(
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(selected ? Color.accentColor.opacity(0.72) : .clear)
                )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 4)
        .overlay(alignment: .topTrailing) {
            if hovering { hoverActions }
        }
    }

    /// While it's being downloaded or converted: a see-through ring with the percent, on the thing itself.
    @ViewBuilder private var progressOverlay: some View {
        if let job = store.progress(for: item.id) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.black.opacity(0.35))
                VStack(spacing: 3) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.3), lineWidth: 3)
                        if let fraction = job.fraction {
                            Circle().trim(from: 0, to: fraction)
                                .stroke(Color.white, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                        } else {
                            ProgressView().controlSize(.small).tint(.white)
                        }
                    }
                    .frame(width: 24, height: 24)
                    Text(job.fraction.map { "\(Int($0 * 100))%" } ?? (job.stage == .converting ? job.target.rawValue.uppercased() : "…"))
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }
            .overlay(alignment: .topTrailing) {
                Button { store.cancelJob(item.id) } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 15, height: 15).background(Circle().fill(.black.opacity(0.5)))
                }
                .buttonStyle(.plain)
                .padding(3)
                .help("Cancel")
                .accessibilityLabel("Cancel \(job.target.rawValue.uppercased())")
            }
            .help(job.label)
            .accessibilityElement(children: .contain)
            .accessibilityLabel(job.label)
        }
    }

    /// A download or conversion that didn't work: a red ! — click for why, Try Again or Dismiss.
    @ViewBuilder private var failureBadge: some View {
        if let failure = store.jobFailures[item.id] {
            Button {
                PopMenu.show([
                    MenuEntry(title: (failure.download ? "Couldn't download " : "Couldn't make the ") + failure.target.rawValue.uppercased(),
                              symbol: "exclamationmark.triangle", enabled: false) {},
                    MenuEntry(title: String(failure.reason.prefix(90)), enabled: false) {},
                    MenuEntry(title: "Try Again", symbol: "arrow.clockwise", lineBefore: true) { store.retryJob(item.id) },
                    MenuEntry(title: "Dismiss", symbol: "xmark") { store.jobFailures[item.id] = nil },
                ])
            } label: {
                Image(systemName: "exclamationmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(Circle().fill(Color.red))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("\(failure.download ? "Download" : "Conversion") didn't work: \(failure.reason) — click to try again")
            .accessibilityLabel("\(failure.target.rawValue.uppercased()) failed. \(failure.reason). Try again")
        }
    }

    /// A file that's linked, not copied: a small arrow on its corner. Its original gone missing: an orange ?, with Find Original.
    @ViewBuilder private var linkedBadge: some View {
        switch store.fileState(item) {
        case .linked?:
            Image(systemName: "arrow.up.forward")
                .font(.system(size: 7, weight: .heavy)).foregroundStyle(.white)
                .frame(width: 14, height: 14)
                .background(Circle().fill(Color.gray))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                .help("Linked: Swiss shows the original where it is (it isn't copied)")
                .accessibilityLabel("Linked to the original")
        case .missing(let url)?:
            Button {
                PopMenu.show([
                    MenuEntry(title: "Original not found", symbol: "questionmark.folder", enabled: false) {},
                    MenuEntry(title: String(url.deletingLastPathComponent().path.prefix(70)), enabled: false) {},
                    MenuEntry(title: "Find Original…", symbol: "magnifyingglass", lineBefore: true) { store.findOriginal(item.id) },
                ])
            } label: {
                Image(systemName: "questionmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color.orange))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.9), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("The original isn't where it was — moved, renamed, deleted, or on a drive that isn't connected. Click to find it.")
            .accessibilityLabel("Original not found. Find original")
        default:
            EmptyView()
        }
    }

    /// A downloaded MP3/MP4 keeps the link it came from: a small badge on its left — click for the link.
    @ViewBuilder private var sourceBadge: some View {
        if item.kind == .file, let source = item.sourceURL, let url = URL(string: source), !url.isFileURL {
            Button {
                PopMenu.show([
                    MenuEntry(title: url.host.map { $0.replacingOccurrences(of: "www.", with: "") } ?? source, symbol: "link", enabled: false) {},
                    MenuEntry(title: "Open Link", symbol: "arrow.up.right", lineBefore: true) { Safety.openLink(url) },
                    MenuEntry(title: "Copy Link", symbol: "doc.on.doc") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(source, forType: .string)
                        store.flash("Link copied")
                    },
                    MenuEntry(title: "Put Link Back on the Board", symbol: "arrow.uturn.backward") { store.restoreSourceLink(of: item.id) },
                    MenuEntry(title: "Remove Link", symbol: "trash", lineBefore: true) { store.removeSourceLink(of: item.id) },
                ])
            } label: {
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color(red: 0.36, green: 0.72, blue: 0.52)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.85), lineWidth: 1))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help("Made from \(source) — click to open, copy or remove the link")
        }
    }

    /// Pop-up tile: an icon (the picture itself, a file's own icon, a link's thumbnail) and the name under it.
    private var tile: some View {
        VStack(spacing: 5) {
            Group { if lite { Color.clear } else { tileIcon } }
                .frame(width: 50, height: 50)
                .overlay { progressOverlay }
                .overlay { CopyProgressBadge(id: item.id) }
                .overlay(alignment: .topLeading) { sourceBadge.offset(x: -5, y: -5) }
                .overlay(alignment: .bottomLeading) { failureBadge.offset(x: -5, y: 5) }
                .overlay(alignment: .bottomTrailing) { if !lite { linkedBadge.offset(x: 5, y: 5) } }
                .overlay(alignment: .bottom) { tileChips }
                .padding(7)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.primary.opacity(selected ? 0.1 : (hovering ? 0.045 : 0)))
                )
            HStack(spacing: 3) {
                TagDots(tags: item.colorTags ?? [])
                Text(tileName)
                    .font(.system(size: 11, weight: .medium))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .truncationMode(.middle)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(selected ? Color.accentColor.opacity(0.72) : .clear)
                    )
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    /// Small tiles: MP3 / MP4 show over the bottom of the picture while you point at it (or it's selected), so every
    /// tile is the same size and the board stays calm.
    @ViewBuilder private var tileChips: some View {
        if !lite, (hovering || selected), !mediaTargets.isEmpty {
            mediaChips
                .padding(3)
                .background(Capsule().fill(.regularMaterial))
                .offset(y: 10)
                .transition(.opacity)
        }
    }

    @ViewBuilder private var tileIcon: some View {
        switch item.kind {
        case .text:
            NotePadIcon(size: 44)
        case .image:
            if let thumb {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.1)))
            } else {
                Image(systemName: "photo").font(.system(size: 26, weight: .light)).foregroundStyle(.secondary)
            }
        case .file:
            if let thumb { // a video's frame, or the picture an MP3 was downloaded with
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                    .frame(width: 50, height: 50)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    .overlay(alignment: .bottomTrailing) {
                        Text((store.contentURL(item)?.pathExtension ?? "").uppercased())
                            .font(.system(size: 7.5, weight: .heavy, design: .rounded))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .background(.black.opacity(0.55), in: RoundedRectangle(cornerRadius: 3))
                            .padding(3)
                    }
            } else {
                Image(nsImage: store.contentURL(item).map { NSWorkspace.shared.icon(forFile: $0.path) }
                      ?? NSWorkspace.shared.icon(for: .data))
                    .resizable().aspectRatio(contentMode: .fit)
            }
        case .link:
            ZStack(alignment: .bottomTrailing) {
                if let thumb {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: 50, height: 50)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                } else if let doc = OnlineDocument(item.linkURL) {
                    // Google Docs / Sheets / Slides (and Office on the web): a document, in its color.
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: doc.color.0, green: doc.color.1, blue: doc.color.2))
                        .frame(width: 40, height: 48)
                        .overlay(Image(systemName: doc.symbol).font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                        .frame(width: 50, height: 50)
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.36, green: 0.72, blue: 0.52))
                        .frame(width: 44, height: 44)
                        .overlay(Image(systemName: "link").font(.system(size: 18, weight: .semibold)).foregroundStyle(.white))
                        .frame(width: 50, height: 50)
                }
                // A small link badge, so links read as links even with a picture.
                Image(systemName: "link")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 16, height: 16)
                    .background(Circle().fill(Color(red: 0.36, green: 0.72, blue: 0.52)))
                    .overlay(Circle().strokeBorder(Color.white.opacity(0.8), lineWidth: 1))
                    .offset(x: 4, y: 4)
                    .opacity(thumb == nil ? 0 : 1)
            }
        }
    }

    private var tileName: String {
        switch item.kind {
        case .text: return noteName
        case .link: return item.displayTitle.isEmpty ? item.host : item.displayTitle
        default: return item.displayTitle.isEmpty ? "Untitled" : item.displayTitle
        }
    }

    /// Quotes view: the note as a quote — its words, when you saved it, and a one-click Copy.
    private var quoteCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "quote.opening")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.tertiary)
            Text(item.text ?? "")
                .font(.system(size: 13.5, design: .serif))
                .lineSpacing(2)
                .lineLimit(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .naturalDirection(item.text)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                TagDots(tags: item.colorTags ?? [])
                Text(item.createdAt.formatted(.relative(presentation: .named)))
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                Spacer()
                Button {
                    store.copy(item)
                    justCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { justCopied = false }
                } label: {
                    Label(justCopied ? "Copied" : "Copy", systemImage: justCopied ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .background(Color.primary.opacity(0.07), in: Capsule())
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .foregroundStyle(justCopied ? Color.accentColor : .secondary)
                .help("Copy the text")
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.primary.opacity(selected ? 0.11 : (hovering ? 0.065 : 0.045)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.06))
        )
    }

    private var spokenName: String {
        switch item.kind {
        case .text: return "Note: " + noteName
        case .link: return "Link: " + (item.displayTitle.isEmpty ? item.host : item.displayTitle)
        case .image: return "Picture: " + (item.displayTitle.isEmpty ? "untitled" : item.displayTitle)
        case .file: return "File: " + (item.displayTitle.isEmpty ? "untitled" : item.displayTitle)
        }
    }

    private var noteName: String {
        let first = (item.text ?? "").split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? "Note"
        let trimmed = first.trimmingCharacters(in: .whitespaces)
        return trimmed.count <= 34 ? trimmed : String(trimmed.prefix(30)).trimmingCharacters(in: .whitespaces) + "…"
    }

    private var cardBody: some View {
        VStack(alignment: .leading, spacing: 0) {
            cardContent
            if item.kind != .text, let note = item.text, !note.isEmpty {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .padding(.horizontal, 9)
                    .padding(.vertical, 6)
            }
            if !item.tags.isEmpty { tagRow }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay { progressOverlay }
        .overlay { CopyProgressBadge(id: item.id) }
        .overlay(alignment: .topLeading) { sourceBadge.padding(5) }
        .overlay(alignment: .bottomLeading) { failureBadge.padding(5) }
        .overlay(alignment: .bottomTrailing) { linkedBadge.padding(5) }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(hovering ? 0.14 : (item.kind == .image ? 0 : 0.06)), lineWidth: 1)
        )
        .overlay(alignment: .topTrailing) {
            if hovering { hoverActions }
        }
        .overlay(alignment: .topLeading) { TagDots(tags: item.colorTags ?? [], size: 9).padding(6) }
    }

    private var cardBackground: Color {
        switch item.kind {
        case .text: Color.primary.opacity(0.03)
        case .image: .clear
        default: Color.primary.opacity(0.045)
        }
    }

    @ViewBuilder private var cardContent: some View {
        switch item.kind {
        case .image: imageCard
        case .link: linkCard
        case .file: fileCard
        case .text: noteCard
        }
    }

    /// Just the picture.
    @ViewBuilder private var imageCard: some View {
        if let image = thumb {
            let ratio = max(0.4, image.size.width / max(image.size.height, 1))
            Color.clear
                .aspectRatio(ratio, contentMode: .fit)
                .overlay(Image(nsImage: image).resizable().scaledToFill())
                .clipped()
                .overlay(alignment: .bottomLeading) {
                    if hovering, let host = item.sourceHost {
                        Text(host)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.ultraThinMaterial, in: Capsule())
                            .padding(5)
                    }
                }
        } else {
            Image(systemName: "photo")
                .font(.system(size: 20))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity)
                .frame(height: 80)
                .background(Color.primary.opacity(0.045))
        }
    }

    /// A slim preview strip, the title, and the site.
    private var linkCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let image = thumb {
                Color.clear
                    .frame(height: 64)
                    .overlay(Image(nsImage: image).resizable().scaledToFill())
                    .clipped()
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? item.host)
                    .font(.system(size: 12.5, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 4) {
                    Image(systemName: "link").font(.system(size: 9, weight: .semibold))
                    Text(item.host).lineLimit(1)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                if !mediaTargets.isEmpty { mediaChips.padding(.top, 3) }
            }
            .padding(.horizontal, 9)
            .padding(.vertical, 8)
        }
    }

    /// The quick MP3 / MP4 buttons: only on YouTube links. Other video sites and video / sound files have them in
    /// the right-click menu instead.
    private var mediaTargets: [ConvertTarget] { Self.mediaTargets(for: item, store: store) }

    static func mediaTargets(for item: Item, store: Store) -> [ConvertTarget] {
        guard item.kind == .link, let host = item.linkURL?.host?.lowercased() else { return [] }
        let youTube = ["youtube.com", "youtu.be"].contains { host == $0 || host.hasSuffix("." + $0) }
        return youTube ? [.mp3, .mp4] : []
    }

    /// Small MP3 / MP4 buttons: one click downloads (links) or converts (files).
    @ViewBuilder private var mediaChips: some View {
        let busy = store.converting.contains(item.id)
        HStack(spacing: 3) {
            ForEach(mediaTargets) { target in
                Button {
                    if item.kind == .link { store.download(item.id, as: target) } else { store.convert(item.id, to: target) }
                } label: {
                    Text(target.rawValue.uppercased())
                        .font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .foregroundStyle(selected && asRow ? Color.white : Color.secondary)
                        .background(
                            Capsule().strokeBorder(selected && asRow ? Color.white.opacity(0.6) : Color.primary.opacity(0.2))
                        )
                        .contentShape(Capsule())
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .disabled(busy)
                .opacity(busy ? 0.4 : 1)
                .help(item.kind == .link ? "Download as \(target.rawValue.uppercased())" : "Convert to \(target.rawValue.uppercased())")
            }
        }
    }

    /// Small thumbnail, the name, and its type and size.
    private var fileCard: some View {
        HStack(spacing: 9) {
            fileIcon(size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(item.title ?? "File")
                    .font(.system(size: 12, weight: .medium))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                fileBadge
                if !mediaTargets.isEmpty { mediaChips.padding(.top, 2) }
            }
            Spacer(minLength: 0)
        }
        .padding(9)
    }

    /// A note: a bigger note-pad icon, its first line as the title under it, then a glimpse of the rest.
    private var noteCard: some View {
        let lines = (item.text ?? "").split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
        let first = lines.first ?? "Note"
        let rest = lines.dropFirst().joined(separator: " ")
        return VStack(alignment: .leading, spacing: 6) {
            NotePadIcon(size: 30)
            Text(first)
                .font(.system(size: 12.5, weight: .medium))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if !rest.isEmpty {
                Text(rest)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
                    .lineSpacing(1)
                    .fixedSize(horizontal: false, vertical: true)
                    .mask(LinearGradient(colors: [.black, .black, .black.opacity(0.2)], startPoint: .top, endPoint: .bottom))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
    }

    private var tagRow: some View {
        HStack(spacing: 4) {
            ForEach(item.tags.prefix(4), id: \.self) { tag in
                Button { store.search = "#" + tag } label: {
                    Text("#" + tag)
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .padding(.bottom, 7)
    }

    /// The note with its fonts, sizes, colors and lists.
    private var noteText: Text {
        if item.richText != nil, let styled = try? AttributedString(item.attributedText, including: \.appKit) {
            return Text(styled)
        }
        return Text(item.text ?? "")
    }

    // MARK: Row (List view)

    /// Like Finder's list: a tiny thumbnail and the name on one line, soft stripes, a solid highlight when selected.
    private var row: some View {
        HStack(spacing: 7) {
            rowIcon
            if store.renamingItemID == item.id {
                renameField.frame(maxWidth: 260)
            } else {
                Text(title)
                    .font(.system(size: 12.5))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(selected ? Color.white : Color.primary)
            }
            TagDots(tags: item.colorTags ?? [])
            Spacer(minLength: 0)
            if !mediaTargets.isEmpty { mediaChips }
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .background(
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(rowFill)
        )
    }

    private var rowFill: Color {
        if selected { return .accentColor }
        if hovering { return Color.primary.opacity(0.06) }
        return (rowIndex ?? 0) % 2 == 1 ? Color.primary.opacity(0.035) : .clear
    }

    @ViewBuilder private var rowIcon: some View {
        let size: CGFloat = 17
        switch item.kind {
        case .image, .link:
            if let image = thumb {
                Image(nsImage: image).resizable().scaledToFill()
                    .frame(width: size, height: size * 0.78)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 2).strokeBorder(Color.black.opacity(0.12), lineWidth: 0.5))
                    .frame(width: size, height: size)
            } else {
                glyph(item.kind == .link ? "link" : "photo", tint: FolderStyle.forKind(item.kind).color, size: size)
            }
        case .text: NotePadIcon(size: size)
        case .file: fileIcon(size: size)
        }
    }

    private func glyph(_ symbol: String, tint: Color, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.16), in: RoundedRectangle(cornerRadius: size * 0.2, style: .continuous))
    }

    private var title: String {
        switch item.kind {
        case .link: item.title ?? item.host
        case .image: item.title ?? item.sourceHost ?? "Image"
        case .text: item.text?.split(separator: "\n").first.map(String.init) ?? "Note"
        case .file: item.title ?? "File"
        }
    }

    private var subtitle: String {
        switch item.kind {
        case .link: item.host
        case .image: [item.sourceHost, item.ocrText.map { _ in "has text" }].compactMap { $0 }.joined(separator: " · ").ifEmpty("Image")
        case .text:
            item.text.flatMap { text -> String? in
                let lines = text.split(separator: "\n")
                return lines.count > 1 ? lines.dropFirst().joined(separator: " ") : nil
            } ?? (item.tags.isEmpty ? "Note" : item.tags.map { "#" + $0 }.joined(separator: " "))
        case .file: fileDetails
        }
    }

    /// The name field for renaming (in the list row, or a small popover over the card).
    private var renameField: some View {
        RenameField(initial: item.kind == .link ? (item.title ?? item.host) : title, onDark: selected && asRow,
                    commit: { store.renameItem(item.id, to: $0) },
                    cancel: { store.renamingItemID = nil })
            .frame(height: 22)
    }

    // MARK: Files

    @ViewBuilder private func fileIcon(size: CGFloat) -> some View {
        Group {
            if let image = thumb {
                Image(nsImage: image).resizable().scaledToFill()
            } else if let url = item.linkURL {
                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(2)
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var fileBadge: some View {
        HStack(spacing: 5) {
            if let ext = fileExtension {
                Text(ext)
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1.5)
                    .background(FolderStyle.files.color.opacity(0.22), in: Capsule())
            }
            if let size = fileSize {
                Text(size).font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    private var fileExtension: String? {
        let ext = item.linkURL?.pathExtension.uppercased() ?? ""
        return ext.isEmpty ? nil : ext
    }

    private var fileSize: String? {
        guard let url = item.linkURL,
              let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return nil }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }

    private var fileDetails: String {
        [fileExtension, fileSize].compactMap { $0 }.joined(separator: " · ").ifEmpty("File")
    }

    // MARK: Actions

    private var hoverActions: some View {
        HStack(spacing: 3) {
            if item.kind != .text {
                iconButton("arrow.up.right", help: "Open") { store.open(item) }
            }
            iconButton("doc.on.doc", help: "Copy") { store.copy(item) }
            iconButton("trash", help: "Delete") { store.requestDelete(store.targets(for: .item(item.id))) }
        }
        .padding(asRow ? 0 : 5)
    }

    private func iconButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .semibold))
                .frame(width: 22, height: 22)
                .background(.regularMaterial, in: Circle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    @ViewBuilder private var menu: some View {
        let targets = store.targets(for: .item(item.id))
        if targets.count > 1 {
            SelectionMenu(targets: targets)
        } else {
            singleMenu
        }
    }

    @ViewBuilder private var singleMenu: some View {
        if item.kind == .image { Button("Preview") { AppDelegate.shared.preview(item.id) } }
        if item.kind != .text { Button("Open") { store.open(item) } }
        Button("Copy") { store.copy(item) }
        Button("Get Info") { AppDelegate.shared.showInfo(for: [.item(item.id)]) }
        if item.kind != .text { Button("Rename") { store.renamingItemID = item.id } }
        Button(item.kind == .text ? "Edit…" : (item.text == nil ? "Add Note…" : "Edit Note…")) { startEditing() }
        if let source = item.sourceURL.flatMap(URL.init(string:)) {
            Button("Open Source Page") { Safety.openLink(source) }
        }
        if item.kind == .image || item.kind == .file {
            Button("Show in Finder") { store.reveal(item) }
        }
        switch store.fileState(item) {
        case .linked?:
            Button("Keep a Copy in Swiss") { store.keepCopy(item.id) }
                .disabled(FileCopies.shared.isCopying(item.id))
        case .missing?:
            Button("Find Original…") { store.findOriginal(item.id) }
        default:
            EmptyView()
        }
        if item.kind == .link, Converter.isMediaLink(item.linkURL) {
            Divider()
            Button("Download as MP3") { store.download(item.id, as: .mp3) }
                .disabled(store.converting.contains(item.id))
            Button("Download as MP4") { store.download(item.id, as: .mp4) }
                .disabled(store.converting.contains(item.id))
        }
        let conversions = item.kind == .file ? Converter.targets(for: store.contentURL(item) ?? item.linkURL) : []
        if !conversions.isEmpty {
            Divider()
            ForEach(conversions) { target in
                Button(target.title) { store.convert(item.id, to: target) }
                    .disabled(store.converting.contains(item.id))
            }
            Divider()
        }
        if item.kind == .image || item.kind == .file, let file = store.contentURL(item) {
            let options = FormatConverter.conversions(for: file)
            if !options.isEmpty {
                Menu("Convert") {
                    ForEach(options) { option in Button(option.title) { store.convert(item.id, using: option) } }
                }
                .disabled(store.converting.contains(item.id))
            }
        }
        TagMenu(targets: [.item(item.id)])
        PutInFolderMenu(targets: [.item(item.id)])
        Menu("Move to Project") {
            ProjectChoices(current: item.projectID) { store.moveToProject([.item(item.id)], project: $0) }
        }
        Divider()
        Button("Delete", role: .destructive) { store.requestDelete([.item(item.id)]) }
    }

    private func primaryAction() {
        switch item.kind {
        case .text: startEditing()
        case .image: AppDelegate.shared.preview(item.id)
        default: store.open(item)
        }
    }

    private func startEditing() {
        draft = item.attributedText
        DispatchQueue.main.async { editing = true }
    }

    private func saveEdit() {
        store.checkpoint("Edit")
        store.setNote(item.id, draft)
        editing = false
    }

    private var editor: some View {
        VStack(alignment: .trailing, spacing: 10) {
            RichNoteEditor(text: $draft, placeholder: item.kind == .text ? "Write a note…" : "Add a note to this…", onSubmit: saveEdit)
                .frame(width: 360, height: 220)
            HStack {
                Button { editing = false } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(QuietButtonStyle())
                .help("Cancel (esc)")
                Button(action: saveEdit) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .frame(width: 26, height: 26)
                        .contentShape(Rectangle())
                }
                .keyboardShortcut(.return, modifiers: .command)
                .buttonStyle(QuietButtonStyle())
                .help("Save (↩)")
            }
            .font(.system(size: 12))
        }
        .padding(12)
    }
}

/// Icons | List, side by side like Finder's view switch — the one you're in is highlighted.
struct LayoutToggle: View {
    @AppStorage(BoardLayout.key) private var layout = BoardLayout.icons.rawValue

    var body: some View {
        HStack(spacing: 0) {
            segment(.icons, symbol: "square.grid.2x2", help: "View as icons")
            segment(.list, symbol: "list.bullet", help: "View as a list")
        }
        .padding(1.5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(Color.primary.opacity(0.06)))
    }

    private func segment(_ option: BoardLayout, symbol: String, help: String) -> some View {
        let on = layout == option.rawValue
        return Button { layout = option.rawValue } label: {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: on ? .semibold : .regular))
                .frame(width: 24, height: 21)
                .background(RoundedRectangle(cornerRadius: 5.5, style: .continuous)
                    .fill(on ? Color.primary.opacity(0.13) : .clear))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? .primary : .secondary)
        .help(help)
        .accessibilityLabel(help)
        .accessibilityAddTraits(on ? .isSelected : [])
    }
}

private extension String {
    func ifEmpty(_ fallback: String) -> String { isEmpty ? fallback : self }
}
