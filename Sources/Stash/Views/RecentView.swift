import AppKit
import SwiftUI

/// The Recent tab: everything captured lately, newest first. Click to select (⌘/⇧ for more), Keep (⌘K or Return)
/// puts it in the project you came from, Space looks at it, ⌘C copies it again, ⌘⌫ removes it.
struct RecentView: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var recent = RecentStore.shared
    @AppStorage(CaptureSettings.clipboardKey) private var clipboardOn = false
    @AppStorage(CaptureSettings.screenshotsKey) private var screenshotsOn = false
    @AppStorage(CaptureSettings.retentionKey) private var retention = 7
    let compact: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if recent.items.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "clock.arrow.circlepath").font(.system(size: 30, weight: .light)).foregroundStyle(.tertiary)
                    Text("Nothing here yet").font(.system(size: 13, weight: .semibold))
                    Text(clipboardOn || screenshotsOn ? "Copy anything, or take a screenshot — it shows up here."
                         : "Turn on Copies or Screenshots above to catch them here.")
                        .font(.system(size: 11.5)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                .padding()
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        let shown = recent.items.filter { entry in entry.itemID.map { store.index.itemIDs.contains($0) } ?? true }
                        let _ = recent.shownIDs = shown.map(\.id)
                        LazyVStack(spacing: 1) {
                            ForEach(shown) {
                                RecentRow(item: $0).id($0.id)
                            }
                        }
                        .padding(.horizontal, 8).padding(.vertical, 6)
                    }
                    .onChange(of: recent.cursor) { if let id = recent.cursor { proxy.scrollTo(id) } } // instant, follows the arrow keys
                }
                .contentShape(Rectangle())
                .onTapGesture { recent.selection = [] }
            }
            if !recent.selection.isEmpty { keepBar }
        }
        .onPreferenceChange(RecentFramesKey.self) { frames in MainActor.assumeIsolated { RecentDrag.shared.frames = frames } }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text("Recent").font(.system(size: 12, weight: .semibold))
            Text("\(recent.items.count)").font(.system(size: 11)).foregroundStyle(.tertiary).monospacedDigit()
            Text(retention == 0 ? "kept until you clear" : "kept \(retention) day\(retention == 1 ? "" : "s")")
                .font(.system(size: 10.5)).foregroundStyle(.tertiary)
            Spacer()
            // What's being captured, always in sight: flip either one right here.
            captureChip("Copies", symbol: "doc.on.clipboard", on: $clipboardOn)
            captureChip("Screenshots", symbol: "camera.viewfinder", on: $screenshotsOn)
            if clipboardOn || screenshotsOn {
                Button { recent.setPaused(!recent.paused) } label: {
                    Image(systemName: recent.paused ? "play.circle.fill" : "pause.circle")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(recent.paused ? Color.orange : Color.secondary)
                        .frame(width: 24, height: 22)
                        .background(Capsule().fill(recent.paused ? Color.orange.opacity(0.15) : Color.primary.opacity(0.05)))
                }
                .buttonStyle(.plain)
                .help(recent.paused ? "Capture is paused — click to resume" : "Pause capture")
                .accessibilityLabel(recent.paused ? "Resume capture" : "Pause capture")
            }
            if !recent.items.isEmpty {
                Button("Clear") { recent.clear() }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                    .help("Remove everything from Recent (things you kept stay in their projects)")
            }
        }
        .padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 2)
    }

    /// A small on/off switch for one kind of capture. The pop-up shows just the icon (the tooltip names it).
    private func captureChip(_ title: String, symbol: String, on: Binding<Bool>) -> some View {
        let isOn = on.wrappedValue
        return Button { on.wrappedValue.toggle() } label: {
            // Like a light switch: lit when it's catching, crossed out and dim when it isn't.
            HStack(spacing: 3) {
                Image(systemName: symbol).font(.system(size: 10.5, weight: .semibold))
                    .overlay {
                        if !isOn {
                            Rectangle().frame(width: 1.5, height: 17).rotationEffect(.degrees(-45))
                        }
                    }
                if !compact { Text(isOn ? title : title + " off").font(.system(size: 10.5, weight: .medium)) }
            }
            .padding(.horizontal, 7).frame(height: 22)
            .foregroundStyle(isOn ? Color.accentColor : Color.secondary.opacity(0.7))
            .background(Capsule().fill(isOn ? Color.accentColor.opacity(0.16) : .clear))
            .overlay(Capsule().strokeBorder(isOn ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1))
            .opacity(recent.paused && isOn ? 0.5 : 1)
        }
        .buttonStyle(.plain)
        .help("\(title): \(isOn ? "on" : "off") — click to turn \(isOn ? "off" : "on")"
              + (title == "Screenshots" ? " (watching \((CaptureSettings.screenshotFolder.path as NSString).abbreviatingWithTildeInPath))" : ""))
        .accessibilityLabel("Capture \(title.lowercased())")
        .accessibilityValue(isOn ? "on" : "off")
    }

    /// Selected things: Keep them in the project you were in, or pick another.
    private var keepBar: some View {
        HStack(spacing: 8) {
            Text("\(recent.selection.count) selected").font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer()
            Button { recent.remove(recent.selection) } label: { Label("Remove", systemImage: "trash") }
                .buttonStyle(QuietButtonStyle()).font(.system(size: 11))
            KeepButton(ids: recent.selection, prominent: true)
        }
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Color.primary.opacity(0.04))
        .overlay(alignment: .top) { Rectangle().fill(Color.primary.opacity(0.07)).frame(height: 1) }
    }
}

/// "Keep" — into the project/folder you came from; its ▾ picks another project.
struct KeepButton: View {
    @EnvironmentObject var store: Store
    let ids: Set<UUID>
    var prominent = false

    var body: some View {
        HStack(spacing: 0) {
            Button { RecentStore.shared.keep(ids, in: store.keepPlace) } label: {
                Label("Keep", systemImage: "tray.and.arrow.down")
                    .font(.system(size: 11, weight: .semibold))
                    .padding(.horizontal, 8).frame(height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keep in \(store.describe(store.keepPlace)) (⌘K)")
            .accessibilityLabel("Keep in \(store.describe(store.keepPlace))")
            Button {
                PopMenu.show(store.projects.map { project in
                        MenuEntry(title: project.name, symbol: "folder") { RecentStore.shared.keep(ids, in: Place(project: project.id)) }
                    })
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                    .frame(width: 18, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Keep in another project")
            .accessibilityLabel("Keep in another project")
        }
        .foregroundStyle(prominent ? Color.white : Color.accentColor)
        .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(prominent ? Color.accentColor : Color.accentColor.opacity(0.12)))
    }
}

private struct RecentRow: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var recent = RecentStore.shared
    let item: RecentItem
    @State private var hovering = false

    private var selected: Bool { recent.selection.contains(item.id) }
    /// The project item this entry is, if it lives in a project.
    private var saved: Item? { item.itemID.flatMap { id in store.items.first { $0.id == id } } }

    private var title: String {
        guard let saved else { return item.title }
        if saved.kind == .text { return (saved.text ?? "").replacingOccurrences(of: "\n", with: " ") }
        return saved.displayTitle.isEmpty ? saved.host : saved.displayTitle
    }

    /// "Poster Series ▸ PhotoBook" for things in a project.
    private var whereItLives: String? {
        guard let saved else { return nil }
        var parts = [saved.projectID.flatMap { id in store.projects.first { $0.id == id }?.name } ?? "a project"]
        if let folder = saved.folderID.flatMap(store.folder) { parts.append(folder.name) }
        return parts.joined(separator: " ▸ ")
    }

    var body: some View {
        let missing = saved == nil && (item.kind == .files || item.kind == .screenshot) && !item.filesExist
        HStack(spacing: 9) {
            thumbnail.frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 12, weight: .medium)).lineLimit(2).truncationMode(.tail)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                HStack(spacing: 4) {
                    Text(item.lastSeen.formatted(.relative(presentation: .named)))
                    if let place = whereItLives { Label("In \(place)", systemImage: "folder").labelStyle(.titleAndIcon) }
                    else if let app = item.sourceApp { Text("· \(app)") }
                    if item.count > 1 { Text("· ×\(item.count)") }
                    if missing { Text("· moved or deleted").foregroundStyle(.orange) }
                    if let kept = item.keptIn, saved == nil { Label("Kept in \(kept)", systemImage: "checkmark").labelStyle(.titleAndIcon) }
                }
                .font(.system(size: 10)).foregroundStyle(selected ? Color.white.opacity(0.8) : Color.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            if hovering && !selected {
                HStack(spacing: 2) {
                    icon("doc.on.doc", "Copy again") { if let saved { store.copy(saved) } else { recent.copyAgain(item) } }
                    icon("xmark", "Remove from Recent" + (saved == nil ? "" : " (it stays in its project)")) { recent.remove([item.id]) }
                    if saved != nil { icon("arrow.right.circle", "Show it in its project") { reveal() } }
                }
                if saved == nil { KeepButton(ids: [item.id]) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(selected ? Color.accentColor.opacity(0.85) : Color.primary.opacity(hovering ? 0.05 : 0)))
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            let event = NSApp.currentEvent
            if (event?.clickCount ?? 1) >= 2 {
                if saved != nil { reveal() } else { RecentQuickLook.show([item]) }
                return
            }
            recent.click(item.id, flags: event?.modifierFlags ?? [])
        }
        // Dragging (out to other apps, or onto a project tab) is RecentDrag's: it needs to know where each row is.
        .background(GeometryReader { Color.clear.preference(key: RecentFramesKey.self, value: [item.id: $0.frame(in: .global)]) })
        .contextMenu {
            if saved != nil {
                Button("Show in Project") { reveal() }
            } else {
                Button("Keep in \(store.describe(store.keepPlace))") { recent.keep([item.id], in: store.keepPlace) }
            }
            RecentTools(item: item, saved: saved)
            Divider()
            Button("Copy Again") { recent.copyAgain(item) }
            Button("Share…") {
                let picked = recent.selection.contains(item.id) ? recent.items.filter { recent.selection.contains($0.id) } : [item]
                Sharing.share(recent: picked)
            }
            if let url = recent.fileURL(item), item.kind != .image {
                Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
            Divider()
            Button("Remove from Recent", role: .destructive) { recent.remove([item.id]) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(item.kind.rawValue): \(item.title), \(item.lastSeen.formatted(.relative(presentation: .named)))\(item.keptIn.map { ", kept in \($0)" } ?? "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .help(item.kind == .text ? (item.text ?? "") : "Double-click to look · drag it out · Keep to put it in a project")
    }

    /// Opens its project and folder, with it selected.
    private func reveal() {
        guard let saved else { return }
        store.openProject(saved.projectID)
        store.openFolderID = saved.folderID
        store.selection = [.item(saved.id)]
        store.scrollTarget = .item(saved.id)
    }

    @ViewBuilder private var thumbnail: some View {
        if let saved, let image = store.displayImage(saved) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        } else if let saved, saved.kind == .text {
            NotePadIcon(size: 28)
        } else if let saved, saved.kind == .file, let url = store.contentURL(saved) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable()
        } else if let image = recent.previewImage(item) {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: 34, height: 34).clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
        } else {
            switch item.kind {
            case .files:
                Image(nsImage: NSWorkspace.shared.icon(forFile: item.fileURLs.first?.path ?? "/")).resizable()
            case .link:
                Image(systemName: "link").font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(FolderStyle.linker.color))
            default:
                Image(systemName: item.kind == .screenshot ? "camera.viewfinder" : "text.quote")
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .frame(width: 30, height: 30).background(RoundedRectangle(cornerRadius: 7).fill(Color.primary.opacity(0.07)))
            }
        }
    }

    private func icon(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 22, height: 22).contentShape(Rectangle())
        }
        .buttonStyle(.plain).foregroundStyle(.secondary).help(help).accessibilityLabel(help)
    }
}

/// Space / double-click in Recent: Quick Look for pictures and files; text opens a copy-ready preview via Quick Look too.
@MainActor
enum RecentQuickLook {
    static func show(_ items: [RecentItem]) {
        let urls = items.compactMap { item -> URL? in
            if let id = item.itemID, let saved = Store.shared.items.first(where: { $0.id == id }) { return Store.shared.dragFile(for: saved) }
            if let url = RecentStore.shared.fileURL(item) { return url }
            guard let text = item.text else { return nil }
            let file = TestMode.temp("StashOut").appendingPathComponent(UUID().uuidString).appendingPathComponent("Recent.txt")
            try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? text.write(to: file, atomically: true, encoding: .utf8)
            return file
        }
        QuickLook.shared.show(urls)
    }
}


/// Recent entries get the tools cards have: Open, Quick Look, Get Info, MP3 / MP4 and Convert.
private struct RecentTools: View {
    @EnvironmentObject var store: Store
    let item: RecentItem
    let saved: Item?

    private var file: URL? {
        if let saved { return store.contentURL(saved) }
        return RecentStore.shared.fileURL(item) ?? item.fileURLs.first
    }

    var body: some View {
        Button("Open") {
            if let saved { store.open(saved) }
            else if item.kind == .link, let link = item.text.flatMap(URL.init(string:)) { Safety.openLink(link) }
            else if let file { Safety.open(file) }
        }
        Button("Quick Look") { RecentQuickLook.show([item]) }
        if let saved {
            Button("Get Info") { AppDelegate.shared.showInfo(for: [.item(saved.id)]) }
        } else if let file {
            Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        // MP3 / MP4: links download (kept first, so the result has a home); files convert next to themselves.
        if let saved, saved.kind == .link, Converter.isMediaLink(saved.linkURL) {
            Button("Download as MP3") { store.download(saved.id, as: .mp3) }
            Button("Download as MP4") { store.download(saved.id, as: .mp4) }
        } else if saved == nil, item.kind == .link, let link = item.text.flatMap(URL.init(string:)), Converter.isMediaLink(link) {
            ForEach([ConvertTarget.mp3, .mp4]) { target in
                Button("Keep & Download as \(target.rawValue.uppercased())") {
                    RecentStore.shared.keep([item.id], in: store.keepPlace)
                    if let id = RecentStore.shared.items.first(where: { $0.id == item.id })?.itemID { store.download(id, as: target) }
                }
            }
        } else if let file, !Converter.targets(for: file).isEmpty {
            ForEach(Converter.targets(for: file)) { target in
                Button(target.title) {
                    if let saved { store.convert(saved.id, to: target) } else { ConnectedEditor.shared.convert([file], to: target) }
                }
            }
        }
        if let file {
            let options = FormatConverter.conversions(for: file)
            if !options.isEmpty {
                Menu("Convert") {
                    ForEach(options) { option in
                        Button(option.title) { if let saved { store.convert(saved.id, using: option) } else { store.convertFile(file, using: option) } }
                    }
                }
            }
        }
    }
}
