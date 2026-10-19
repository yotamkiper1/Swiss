import SwiftUI

// MARK: - Placing things on the board

/// Like Finder's icon view: with Arrange By "None" you can drag anything anywhere and it stays there.
/// Picking Name, Kind, Date Added or Tags lines everything up again in that order.
extension Store {
    /// Padding around the board's contents (spots are measured from inside it).
    static let boardPadding: CGFloat = 12

    /// The compact preview and the big window are different sizes, so each keeps its own arrangement.
    /// The big window keeps one arrangement for minimal tiles and one for the full view (❝), since they're different sizes.
    static func windowKey(_ compact: Bool) -> String {
        if compact { return "compact" }
        return "window-tiles"
    }

    func boardKey(of item: Item) -> String {
        item.folderID.map { "f:" + $0.uuidString } ?? "p:" + (item.projectID?.uuidString ?? "none")
    }

    func boardKey(of folder: Folder) -> String {
        folder.parentID.map { "f:" + $0.uuidString } ?? "p:" + (folder.projectID?.uuidString ?? "none")
    }

    func spot(of item: Item, compact: Bool) -> CGPoint? {
        guard let s = item.spots?[Self.windowKey(compact)], s.board == boardKey(of: item) else { return nil }
        return CGPoint(x: s.x, y: s.y)
    }

    func spot(of folder: Folder, compact: Bool) -> CGPoint? {
        guard let s = folder.spots?[Self.windowKey(compact)], s.board == boardKey(of: folder) else { return nil }
        return CGPoint(x: s.x, y: s.y)
    }

    /// Dragged on the board: these go where you let go, and everything else stays where it is now.
    func moveOnBoard(_ moving: Set<Selectable>, by delta: CGSize, compact: Bool, frames given: [Selectable: CGRect]? = nil) {
        let frames = given ?? boardFrames[compact] ?? [:]
        guard moving.contains(where: { frames[$0] != nil }) else { return }
        let key = Self.windowKey(compact)
        let pad = Self.boardPadding
        func point(_ target: Selectable) -> (Double, Double)? {
            guard let frame = frames[target] else { return nil }
            let shift = moving.contains(target) ? delta : .zero
            return (max(0, frame.minX - pad + shift.width), max(0, frame.minY - pad + shift.height))
        }
        checkpoint("Move")
        for index in items.indices {
            guard let (x, y) = point(.item(items[index].id)) else { continue }
            items[index].spots = (items[index].spots ?? [:]).merging([key: BoardSpot(x: x, y: y, board: boardKey(of: items[index]))]) { $1 }
        }
        for index in folders.indices {
            guard let (x, y) = point(.folder(folders[index].id)) else { continue }
            folders[index].spots = (folders[index].spots ?? [:]).merging([key: BoardSpot(x: x, y: y, board: boardKey(of: folders[index]))]) { $1 }
        }
        UserDefaults.standard.set(BoardSort.manual.rawValue, forKey: BoardSort.key)
        save(touchesFiles: false)
    }

    /// Pop-up cards became small tiles, so spots saved for the old, wider cards are dropped once
    /// (they'd leave things scattered). Folders keep theirs.
    func resetOldPopUpSpots() {
        let marker = dataDir.appendingPathComponent("popup-tiles-v1")
        guard !FileManager.default.fileExists(atPath: marker.path) else { return }
        for index in items.indices { items[index].spots?[Self.windowKey(true)] = nil }
        writeLibrary()
        FileManager.default.createFile(atPath: marker.path, contents: Data())
    }

    /// Arrange By: lines up everything on this board in that order (forgetting where you'd put things).
    /// "None" keeps things where they are.
    func arrange(by sort: BoardSort) {
        if connectedView != nil, !showingRecent {
            if sort != .manual { ConnectedEditor.shared.forgetSpots() }
            UserDefaults.standard.set(sort.rawValue, forKey: BoardSort.key)
            ConnectedEditor.shared.arrangeInFinder(sort) // the real folder, arranged the same way in Finder
            return
        }
        if sort != .manual {
            checkpoint("Arrange")
            let here = Set(visibleOrder)
            for index in items.indices where here.contains(.item(items[index].id)) { items[index].spots = nil }
            for index in folders.indices where here.contains(.folder(folders[index].id)) { folders[index].spots = nil }
        }
        UserDefaults.standard.set(sort.rawValue, forKey: BoardSort.key)
        objectWillChange.send()
        if sort != .manual { save(touchesFiles: false) }
    }
}

// MARK: - Layout


/// Where everything on a board goes, from just the sizes: used by the layout above, and by the board grid,
/// which works out every place first and then only makes views for what's near the screen.
struct BoardPlacement {
    struct Tile {
        var size: CGSize
        /// Folder-sized (folders, and cards shown as small tiles): placed in folder slots.
        var tileSized: Bool
        /// Where you put it by hand, if you did.
        var spot: CGPoint?
    }

    var folderWidth: CGFloat
    var cardWidth: CGFloat
    var columns: Int
    var spacing: CGFloat

    func frames(width: CGFloat, tiles: [Tile]) -> [CGRect] {
        let sizes = tiles.map(\.size)
        var result = Array(repeating: CGRect.zero, count: tiles.count)
        var placed = PlacedIndex()

        // Things you've put somewhere stay there (pulled back in if the window got narrower).
        for (index, tile) in tiles.enumerated() {
            guard let spot = tile.spot else { continue }
            let x = max(0, min(spot.x, width - sizes[index].width))
            result[index] = CGRect(origin: CGPoint(x: x, y: max(0, spot.y)), size: sizes[index])
            placed.insert(result[index])
        }

        let folderColumns = max(1, Int((width + 6) / (folderWidth + 6)))
        let unplaced = tiles.indices.filter { tiles[$0].spot == nil }

        if placed.isEmpty {
            // Nothing moved yet: the tidy layout — folder rows, then cards in the shortest column.
            var y: CGFloat = 0, rowHeight: CGFloat = 0, column = 0
            for index in unplaced where tiles[index].tileSized {
                if column == folderColumns { column = 0; y += rowHeight + 8; rowHeight = 0 }
                result[index] = CGRect(origin: CGPoint(x: CGFloat(column) * (folderWidth + 6), y: y), size: sizes[index])
                rowHeight = max(rowHeight, sizes[index].height)
                column += 1
            }
            let top = column > 0 ? y + rowHeight + 14 : 0
            var heights = Array(repeating: top, count: columns)
            for index in unplaced where !tiles[index].tileSized {
                let shortest = heights.indices.min { heights[$0] < heights[$1] } ?? 0
                result[index] = CGRect(origin: CGPoint(x: CGFloat(shortest) * (cardWidth + spacing), y: heights[shortest]), size: sizes[index])
                heights[shortest] += sizes[index].height + spacing
            }
            return result
        }

        // Some things have been moved: the rest take the first free place, reading left to right, top down.
        let freeStart = TestMode.isOn ? Perf.now : 0
        defer { if TestMode.isOn { Perf.freeSpotNanos += Perf.now - freeStart } }
        // Same-sized things fill in reading order, so each one's search picks up where the last one's ended:
        // every place before that is still taken (nothing gets removed while placing).
        struct SizeKey: Hashable { let folder: Bool; let width: CGFloat; let height: CGFloat }
        var resume: [SizeKey: (row: Int, slot: Int)] = [:]
        for index in unplaced {
            let isFolder = tiles[index].tileSized
            let step = isFolder ? folderWidth + 6 : cardWidth + spacing
            let slots = isFolder ? folderColumns : columns
            let key = SizeKey(folder: isFolder, width: sizes[index].width, height: sizes[index].height)
            var (row, firstSlot) = resume[key] ?? (0, 0)
            search: while CGFloat(row) * 8 < 50_000 {
                for slot in firstSlot..<slots {
                    let rect = CGRect(origin: CGPoint(x: CGFloat(slot) * step, y: CGFloat(row) * 8), size: sizes[index])
                    if !placed.overlaps(rect) {
                        result[index] = rect
                        resume[key] = (row, slot)
                        break search
                    }
                }
                firstSlot = 0
                row += 1
            }
            placed.insert(result[index])
        }
        return result
    }
}

/// Which tiles are close enough to the visible part of the board to be drawn in full. Everything else is drawn
/// lite (same size, nothing interactive), so a board of thousands only does real work for a screenful or so.
@MainActor
final class BoardNearby: ObservableObject {
    static let shared = BoardNearby()
    /// Per board: the tiles near the view. Only republished when that set changes.
    @Published private(set) var near: [UUID: Set<Selectable>] = [:]
    private var frames: [UUID: [Selectable: CGRect]] = [:]
    private var compactOf: [UUID: Bool] = [:]
    private var pending: Set<UUID> = []

    func laidOut(_ token: UUID, compact: Bool, frames: [Selectable: CGRect]) {
        self.frames[token] = frames
        compactOf[token] = compact
        update(token)
    }

    func scrolled(_ token: UUID, compact: Bool) {
        compactOf[token] = compact
        update(token)
    }

    /// The visible part of the board, a screen's worth above and below.
    private func window(_ compact: Bool) -> CGRect? {
        let store = Store.shared
        guard let viewport = store.boardViewports[compact], let origin = store.boardContentOrigins[compact] else { return nil }
        let zoom = compact ? store.boardZoom : 1
        let top = (viewport.minY - origin.y) / zoom, height = viewport.height / zoom
        // A margin above and below, in steps of 300 points, so scrolling only changes which tiles exist now
        // and then (not every frame) and they're ready before they come into view.
        let start = ((top - 250) / 300).rounded(.down) * 300
        return CGRect(x: -10_000, y: start, width: 20_000, height: height + 800)
    }

    private func update(_ token: UUID) {
        // Worked out after the current layout pass, never during it.
        guard !pending.contains(token) else { return }
        pending.insert(token)
        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                self.pending.remove(token)
                guard let frames = self.frames[token], let area = self.window(self.compactOf[token] ?? false) else { return }
                let set = Set(frames.lazy.filter { area.intersects($0.value) }.map(\.key))
                if self.near[token] != set { self.near[token] = set }
            }
        }
    }
}

/// The board's placed tiles, filed by band of height, so checking a spot only looks at its neighbours.
private struct PlacedIndex {
    private static let band: CGFloat = 64
    private var bands: [Int: [CGRect]] = [:]
    var isEmpty: Bool { bands.isEmpty }

    private static func range(_ rect: CGRect) -> ClosedRange<Int> {
        Int((rect.minY / band).rounded(.down))...Int((rect.maxY / band).rounded(.down))
    }

    /// Kept with a 3-point margin, like before: tiles never touch.
    mutating func insert(_ rect: CGRect) {
        let padded = rect.insetBy(dx: -3, dy: -3)
        for b in Self.range(padded) { bands[b, default: []].append(padded) }
    }

    func overlaps(_ rect: CGRect) -> Bool {
        for b in Self.range(rect) {
            if let list = bands[b], list.contains(where: { $0.intersects(rect) }) { return true }
        }
        return false
    }
}

// MARK: - Toolbar button

/// The Finder-style "Arrange By" button: ✓ None, then Name, Kind, Date Added, Tags.
struct ArrangeMenu: View {
    @EnvironmentObject var store: Store
    @AppStorage(BoardSort.key) private var sort = BoardSort.manual.rawValue

    var body: some View {
        MenuIconButton(entries: {
            BoardSort.allCases.map { option in
                MenuEntry(title: option.title, checked: sort == option.rawValue, lineBefore: option == .name) {
                    store.arrange(by: option)
                }
            }
        }, help: "Arrange By — None lets you drag things anywhere") {
            Image(systemName: "square.grid.3x1.below.line.grid.1x2").font(.system(size: 12))
        }
        .foregroundStyle(.secondary)
    }
}

/// The choices, shared by the toolbar button and the right-click menu.
struct ArrangeChoices: View {
    @EnvironmentObject var store: Store
    @AppStorage(BoardSort.key) private var sort = BoardSort.manual.rawValue

    var body: some View {
        choice(.manual)
        Divider()
        ForEach(BoardSort.allCases.filter { $0 != .manual }) { choice($0) }
    }

    private func choice(_ option: BoardSort) -> some View {
        Toggle(option.title, isOn: Binding(get: { sort == option.rawValue }, set: { _ in store.arrange(by: option) }))
    }
}
