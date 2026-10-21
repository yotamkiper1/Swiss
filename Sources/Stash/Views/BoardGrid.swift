import AppKit
import SwiftUI

// MARK: - The board as small tiles, for any number of things

/// The sizes small tiles come in. A tile's height depends only on whether it's a folder or a card, the window,
/// and whether it has MP3 / MP4 buttons (names always get room for two lines, like Finder's icon grid) — so each
/// kind is measured once, from a real tile, and every place on the board can be worked out without making views.
@MainActor
enum TileMetrics {
    private static var cache: [String: CGSize] = [:]
    private static let longName = "Wwwwwwwwww Wwwwwwwwww Wwwwwwwwww Wwwwwwwwww"

    static func folder(compact: Bool, width: CGFloat) -> CGSize {
        measure("folder|\(compact)|\(width)", width: width) {
            FolderTile(folder: Folder(name: longName, style: .classic, projectID: nil), compact: compact, lite: true)
        }
    }

    static func card(chips: Bool, width: CGFloat) -> CGSize {
        measure("card|\(chips)|\(width)", width: width) {
            var item = Item(kind: chips ? .link : .text)
            item.text = longName
            item.title = longName
            if chips { item.url = "https://www.youtube.com/watch?v=measure" }
            return CardView(item: item, asTile: true, lite: true)
        }
    }

    private static func measure<V: View>(_ key: String, width: CGFloat, _ make: () -> V) -> CGSize {
        if let hit = cache[key] { return hit }
        let host = NSHostingView(rootView: make().environmentObject(Store.shared).frame(width: width))
        let size = CGSize(width: width, height: ceil(host.fittingSize.height))
        cache[key] = size
        return size
    }
}

/// Places each view at the frame it was given (BoardFrameKey); the board's size comes from those frames.
struct PlacedLayout: Layout {
    var size: CGSize

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize { size }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for view in subviews {
            let frame = view[BoardFrameKey.self]
            view.place(at: CGPoint(x: bounds.minX + frame.minX, y: bounds.minY + frame.minY),
                       proposal: ProposedViewSize(width: frame.width, height: frame.height))
        }
    }

    func explicitAlignment(of guide: HorizontalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
    func explicitAlignment(of guide: VerticalAlignment, in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGFloat? { nil }
}

struct BoardFrameKey: LayoutValueKey { static let defaultValue = CGRect.zero }

/// Every place on one board, worked out once per change (not per redraw).
@MainActor
final class BoardGridPlan {
    struct Key: Equatable {
        var visible: VisibleKey
        var width: CGFloat
        var free: Bool
    }

    private(set) var key: Key?
    private(set) var ids: [Selectable] = []
    private(set) var frames: [Selectable: CGRect] = [:]
    private(set) var height: CGFloat = 0

    func update(_ key: Key, folders: [Folder], items: [Item], compact: Bool, store: Store) {
        guard key != self.key else { return }
        let start = Perf.now
        let folderWidth: CGFloat = compact ? 72 : 84
        let folderSize = TileMetrics.folder(compact: compact, width: folderWidth)
        let plainCard = TileMetrics.card(chips: false, width: folderWidth)
        var tiles: [BoardPlacement.Tile] = []
        var ids: [Selectable] = []
        tiles.reserveCapacity(folders.count + items.count)
        ids.reserveCapacity(folders.count + items.count)
        for folder in folders {
            ids.append(.folder(folder.id))
            tiles.append(.init(size: folderSize, tileSized: true, spot: key.free ? store.spot(of: folder, compact: compact) : nil))
        }
        for item in items {
            ids.append(.item(item.id))
            tiles.append(.init(size: plainCard, tileSized: true, spot: key.free ? store.spot(of: item, compact: compact) : nil))
        }
        let placement = BoardPlacement(folderWidth: folderWidth, cardWidth: folderWidth, columns: 1, spacing: compact ? 10 : 12)
        let list = placement.frames(width: key.width, tiles: tiles)
        var byID: [Selectable: CGRect] = [:]
        byID.reserveCapacity(list.count)
        for (id, frame) in zip(ids, list) { byID[id] = frame }
        self.ids = ids
        self.frames = byID
        self.height = list.map(\.maxY).max() ?? 0
        self.key = key
        if TestMode.isOn { Perf.layoutPasses += 1; Perf.layoutNanos += Perf.now - start }
    }
}

/// Icons view with small tiles: everything gets its place up front, but only what's on screen (and a screenful
/// around it) is made into views. Scroll, and tiles come and go; a board of 10,000 costs about the same as 100.
struct BoardGrid: View {
    @EnvironmentObject var store: Store
    @ObservedObject private var nearby = BoardNearby.shared
    let folders: [Folder]
    let items: [Item]
    let compact: Bool
    let width: CGFloat
    let token: UUID
    let plan: BoardGridPlan
    /// An empty marker at this frame, for scrolling to a tile that has no view yet.
    var anchor: CGRect?
    static let anchorID = "board-scroll-anchor"

    var body: some View {
        let free = !store.isSearching
        let _ = plan.update(.init(visible: store.visibleKey, width: width, free: free), folders: folders, items: items, compact: compact, store: store)
        let _ = publishFrames()
        let near = nearby.near[token] ?? firstScreen()
        // Always made: what you're renaming, and where the arrow keys are taking you.
        let wanted = near.union([store.renamingItemID.map(Selectable.item), store.renamingFolderID.map(Selectable.folder), store.scrollTarget].compactMap { $0 })
        let numbers = Dictionary(uniqueKeysWithValues: folders.prefix(9).enumerated().map { ($0.element.id, $0.offset + 1) })
        PlacedLayout(size: CGSize(width: width, height: plan.height)) {
            if let anchor {
                Color.clear.allowsHitTesting(false).id(Self.anchorID).layoutValue(key: BoardFrameKey.self, value: anchor)
            }
            ForEach(folders.filter { wanted.contains(.folder($0.id)) }) { folder in
                FolderTile(folder: folder, compact: compact, number: numbers[folder.id] ?? 10)
                    .id(Selectable.folder(folder.id))
                    .followsBoardDrag(.folder(folder.id))
                    .layoutValue(key: BoardFrameKey.self, value: plan.frames[.folder(folder.id)] ?? .zero)
            }
            ForEach(items.filter { wanted.contains(.item($0.id)) }) { item in
                CardView(item: item, asTile: true, compact: compact)
                    .id(Selectable.item(item.id))
                    .followsBoardDrag(.item(item.id))
                    .layoutValue(key: BoardFrameKey.self, value: plan.frames[.item(item.id)] ?? .zero)
            }
        }
        .frame(width: width, height: plan.height, alignment: .topLeading)
    }

    /// Box selection, arrow keys and dragging read every tile's frame (in the board's coordinates) from here.
    private func publishFrames() {
        let pad = Store.boardPadding
        let shifted = plan.frames.mapValues { $0.offsetBy(dx: pad, dy: pad) }
        if store.boardFrames[compact] != shifted { store.boardFrames[compact] = shifted }
        BoardNearby.shared.laidOut(token, compact: compact, frames: shifted)
    }

    /// Before the first scroll position is known: the top of the board.
    private func firstScreen() -> Set<Selectable> {
        Set(plan.frames.lazy.filter { $0.value.minY < 900 }.map(\.key))
    }
}
