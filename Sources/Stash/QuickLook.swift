import AppKit
import Quartz

/// Space: the real macOS Quick Look, like Finder — pictures, videos, music, PDFs and other files
/// (a link shows as its little note). Arrow keys step through everything selected; Space or Esc closes it.
@MainActor
final class QuickLook: NSObject, QLPreviewPanelDataSource, QLPreviewPanelDelegate {
    static let shared = QuickLook()
    private var urls: [URL] = []

    /// The files for what's selected — on the board (in its order) or in All Items / a tag list (anywhere in the library).
    private func selectedFiles() -> [URL] {
        let store = Store.shared
        let onBoard = store.visibleItems.filter { store.selection.contains(.item($0.id)) }
        let shownIDs = Set(onBoard.map(\.id))
        let elsewhere = store.items.filter { store.selection.contains(.item($0.id)) && !shownIDs.contains($0.id) }
        return (onBoard + elsewhere).compactMap { store.dragFile(for: $0) }
            + store.folders
            .filter { store.selection.contains(.folder($0.id)) }
            .compactMap { store.mirrorDirs["f:" + $0.id.uuidString].map(store.absolute) }
    }

    /// Quick Look for these files.
    func show(_ files: [URL]) {
        guard let panel = QLPreviewPanel.shared(), !files.isEmpty else { NSSound.beep(); return }
        urls = files
        panel.makeKeyAndOrderFront(nil)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
        panel.reloadData()
    }

    /// Opens Quick Look for the selection, or closes it if it's already open.
    func toggle() {
        guard let panel = QLPreviewPanel.shared() else { return }
        if QLPreviewPanel.sharedPreviewPanelExists(), panel.isVisible {
            panel.orderOut(nil)
            return
        }
        urls = selectedFiles()
        guard !urls.isEmpty else { NSSound.beep(); return }
        panel.makeKeyAndOrderFront(nil)
        panel.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1) // above Stash's windows
        panel.reloadData()
    }

    func begin(_ panel: QLPreviewPanel) {
        panel.dataSource = self
        panel.delegate = self
        if urls.isEmpty { urls = selectedFiles() }
    }

    func end(_ panel: QLPreviewPanel) {
        panel.dataSource = nil
        panel.delegate = nil
        urls = []
    }

    // MARK: QLPreviewPanelDataSource

    nonisolated func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        MainActor.assumeIsolated { urls.count }
    }

    nonisolated func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> QLPreviewItem! {
        MainActor.assumeIsolated { urls[index] as NSURL }
    }

    // Space and Esc close it, like in Finder.
    nonisolated func previewPanel(_ panel: QLPreviewPanel!, handle event: NSEvent!) -> Bool {
        guard event.type == .keyDown, event.keyCode == 49 || event.keyCode == 53 else { return false }
        MainActor.assumeIsolated { panel.orderOut(nil) }
        return true
    }
}
