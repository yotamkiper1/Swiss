import AppKit
import SwiftUI

/// "You just copied something" — when Stash opens, it jumps into the folder that fits
/// (link → Linker, image → PhotoBook, text → Notepad, file → Files) and offers to paste it there.
struct ClipboardHint: Equatable {
    var kind: ItemKind
    var preview: String
    /// The folder it will go into — nil when that folder doesn't exist yet and pasting will create it.
    var folderID: UUID?
    var style: FolderStyle { .forKind(kind) }
}

extension Store {
    /// What kind of thing is on the clipboard, without saving it. Same order as `ingest`.
    static func clipboardKind(_ pb: NSPasteboard) -> (ItemKind, String)? {
        if let urls = pb.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
           let first = urls.first {
            let isImage = imageExtensions.contains(first.pathExtension.lowercased())
            let name = urls.count == 1 ? first.lastPathComponent : "\(urls.count) files"
            return (isImage ? .image : .file, name)
        }
        if imageData(in: pb) != nil { return (.image, "Image") }
        let webURL = (pb.readObjects(forClasses: [NSURL.self], options: nil) as? [URL])?
            .first { ["http", "https"].contains($0.scheme?.lowercased() ?? "") }
        if let webURL { return (.link, webURL.host ?? webURL.absoluteString) }
        guard let text = pb.string(forType: .string)?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
            return nil
        }
        if let url = Store.webURL(from: text) { return (.link, url.host ?? text) }
        return (.text, text)
    }

    /// Called when Stash opens: if you copied something new since last time and there's a
    /// folder for that kind of thing here, opens that folder and shows the paste banner.
    func prepareForClipboard() {
        let pb = NSPasteboard.general
        guard pb.changeCount != clipboardSeenCount else { return }
        clipboardSeenCount = pb.changeCount
        guard let (kind, preview) = Self.clipboardKind(pb) else { return }
        let style = FolderStyle.forKind(kind)
        let project = currentPlace.project
        // The folder you're in if it fits, else a fitting folder inside it, else one on the board.
        let here = openFolder.flatMap { $0.style == style ? $0 : nil }
        let inside = folders.first { $0.style == style && $0.projectID == project && $0.parentID == openFolderID }
        let onBoard = folders.first { $0.style == style && $0.projectID == project && $0.parentID == nil }
        let match = here ?? inside ?? onBoard
        search = ""
        if let match { openFolderID = match.id } // no folder yet: stay where you are, pasting will make one
        clipboardHint = ClipboardHint(kind: kind, preview: preview, folderID: match?.id)
    }

    /// The paste banner's Save button (⌘V does the same).
    func saveClipboardHint() {
        guard let hint = clipboardHint else { return }
        undoGroup("Paste") { pasteHint(hint) }
    }

    private func pasteHint(_ hint: ClipboardHint) {
        let target: Folder
        if let id = hint.folderID, let existing = folder(id) {
            target = existing
        } else if !OrganizerSettings.pasteMakesFolder {
            // No folder of that kind here: it goes onto the page you're on (unless Settings says make one).
            if !ingest(.general, into: currentPlace) { NSSound.beep() }
            return
        } else {
            let project = currentPlace.project
            target = Folder(name: uniqueFolderName(hint.style.name, in: project), style: hint.style, projectID: project, parentID: openFolderID)
            withAnimation(.spring(duration: 0.3)) { addFolder(target) }
            clipboardHint?.folderID = target.id
            openFolderID = target.id
        }
        if !ingest(.general, into: Place(project: target.projectID, folder: target.id)) { NSSound.beep() }
    }
}

/// Shown at the top of a folder Stash opened for you because of what you copied.
struct ClipboardBanner: View {
    @EnvironmentObject var store: Store
    let hint: ClipboardHint

    private var label: String {
        switch hint.kind {
        case .link: "Link copied"
        case .image: "Image copied"
        case .text: "Text copied"
        case .file: "File copied"
        }
    }

    private var symbol: String {
        switch hint.kind {
        case .link: "link"
        case .image: "photo"
        case .text: "text.quote"
        case .file: "doc"
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28, height: 28)
                .background(Color.accentColor.opacity(0.15), in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(hint.preview)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                if hint.folderID == nil, OrganizerSettings.pasteMakesFolder {
                    Label("New \(hint.style.name) folder", systemImage: hint.style.symbol)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(Color.accentColor)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 4)
            Button { store.saveClipboardHint() } label: {
                Text("Paste  ⌘V")
                    .font(.system(size: 12, weight: .semibold))
            }
            .help(hint.folderID == nil
                  ? (OrganizerSettings.pasteMakesFolder ? "Makes a \(hint.style.name) folder and saves it there" : "Saves it here")
                  : "Save it into this folder")
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            Button { withAnimation { store.clipboardHint = nil } } label: {
                Image(systemName: "xmark").font(.system(size: 10, weight: .bold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .help("Dismiss")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.accentColor.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.accentColor.opacity(0.35)))
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 4)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}
