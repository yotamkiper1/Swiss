import AppKit
import Carbon.HIToolbox
import SwiftUI

/// A big window for looking at an image. Space or Esc closes it, ← → step through the images.
final class PreviewPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 680),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1) // above the menu bar preview
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        backgroundColor = NSColor(white: 0.08, alpha: 1)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        minSize = NSSize(width: 360, height: 280)
        [.miniaturizeButton, .zoomButton].forEach { standardWindowButton($0)?.isHidden = true }
        contentView = NSHostingView(rootView: ImagePreview().environmentObject(Store.shared))
    }

    override var canBecomeKey: Bool { true }

    override func cancelOperation(_ sender: Any?) {
        AppDelegate.shared.closePreview()
    }

    override func performClose(_ sender: Any?) {
        AppDelegate.shared.closePreview()
    }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.modifierFlags.intersection([.command, .option, .control]).isEmpty {
            switch Int(event.keyCode) {
            case kVK_Space: AppDelegate.shared.closePreview(); return
            case kVK_LeftArrow, kVK_UpArrow: Store.shared.stepPreview(-1); return
            case kVK_RightArrow, kVK_DownArrow: Store.shared.stepPreview(1); return
            case kVK_Return: Store.shared.previewItem.map(Store.shared.open); return
            default: break
            }
        }
        super.sendEvent(event)
    }
}

struct ImagePreview: View {
    @EnvironmentObject var store: Store
    @State private var image: NSImage?

    var body: some View {
        let item = store.previewItem
        let images = store.previewableItems
        let position = item.flatMap { current in images.firstIndex { $0.id == current.id } }
        ZStack {
            Color(white: 0.08).ignoresSafeArea()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .padding(.top, 44)
                    .padding([.horizontal, .bottom], 16)
            } else {
                ProgressView().controlSize(.small)
            }
        }
        .overlay(alignment: .top) {
            if let item {
                toolbar(item, position: position, total: images.count)
            }
        }
        .overlay {
            if images.count > 1 {
                HStack {
                    arrow("chevron.left") { store.stepPreview(-1) }
                    Spacer()
                    arrow("chevron.right") { store.stepPreview(1) }
                }
                .padding(.horizontal, 10)
            }
        }
        .task(id: item.flatMap(store.contentURL)) {
            image = item.flatMap(store.contentURL).flatMap { NSImage(contentsOf: $0) }
        }
        .environment(\.colorScheme, .dark)
    }

    private func toolbar(_ item: Item, position: Int?, total: Int) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title ?? item.sourceHost ?? "Image")
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                if let position, total > 1 {
                    Text("\(position + 1) of \(total)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.leading, 70) // clear of the close button
            Spacer()
            if let source = item.sourceURL.flatMap(URL.init(string:)) {
                Button { Safety.openLink(source) } label: { Label("Source", systemImage: "link") }
                    .help(source.absoluteString)
            }
            Button { store.reveal(item) } label: { Label("Show in Finder", systemImage: "folder") }
            Button { Sharing.share(targets: [.item(item.id)]) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                .help("Share — AirDrop, Mail, Messages, WhatsApp…")
            Button { store.open(item) } label: { Label("Open", systemImage: "arrow.up.forward.app") }
                .buttonStyle(.borderedProminent)
                .help("Open in your default image app (↩)")
        }
        .controlSize(.regular)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
    }

    private func arrow(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 34, height: 34)
                .background(.ultraThinMaterial, in: Circle())
        }
        .buttonStyle(.plain)
    }
}
