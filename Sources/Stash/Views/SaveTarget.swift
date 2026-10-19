import SwiftUI

/// "↓ Mammoth ▸ PhotoBook": where pasted, dropped and quick-saved things go right now. Always visible in the tool row.
struct SaveTarget: View {
    @EnvironmentObject var store: Store

    private var path: [String] {
        let place = store.showingRecent ? store.keepPlace : store.currentPlace
        var parts = [place.project.flatMap { id in store.projects.first { $0.id == id }?.name } ?? "Not Selected"]
        if let folderID = place.folder {
            parts += store.ancestors(of: folderID).map(\.name)
            if let folder = store.folder(folderID) { parts.append(folder.name) }
        }
        return parts
    }

    private func label(_ parts: [String]) -> String {
        if store.showingRecent { return "Recent" }
        if let location = store.connectedView { return ConnectedRegistry.shared.folder(location.folderID)?.name ?? "Folder" }
        return parts.count > 3 ? [parts[0], "…", parts[parts.count - 1]].joined(separator: " ▸ ") : parts.joined(separator: " ▸ ")
    }

    var body: some View {
        let parts = path
        HStack(spacing: 4) {
            Image(systemName: store.showingRecent ? "clock.arrow.circlepath" : store.connectedView != nil ? "externaldrive.connected.to.line.below" : "tray.and.arrow.down")
                .font(.system(size: 10, weight: .semibold))
            // In Recent it says so; in a connected folder, its name; elsewhere, where things go (project ▸ folder).
            Text(label(parts))
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(Capsule().fill(Color.primary.opacity(0.05)))
        .help(store.showingRecent ? "Keep puts things here: \(parts.joined(separator: " ▸ "))"
              : "New things you paste, drop or quick-save go here: \(parts.joined(separator: " ▸ "))")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Saving to \(parts.joined(separator: ", "))")
    }
}
