import AppKit

/// Counts the board asks for on every redraw (how full each folder is, how much is in each project),
/// worked out in one pass over the library and kept until something in it changes.
struct LibraryIndex {
    fileprivate var itemsVersion = -1
    fileprivate var foldersVersion = -1
    var itemsInFolder: [UUID: Int] = [:]
    var itemsInProject: [UUID: Int] = [:]
    var foldersInFolder: [UUID: Int] = [:]
    /// Per project (nil = not in one): everything in it, and what's on its board (top-level folders + loose cards).
    var thingsInProject: [UUID?: Int] = [:]
    var onBoardInProject: [UUID?: Int] = [:]
    var tagged: [TagColor: Int] = [:]
    var itemIDs: Set<UUID> = []
}

/// What decides which folders and cards are on the board. The lists are only rebuilt when one of these changes.
struct VisibleKey: Equatable {
    var itemsVersion: Int
    var foldersVersion: Int
    var filter: Filter
    var openFolderID: UUID?
    var search: String
    var sort: BoardSort
    var compact: Bool
}

struct VisibleCache {
    var itemsKey: VisibleKey?
    var items: [Item]?
    var foldersKey: VisibleKey?
    var folders: [Folder]?
}

extension Store {
    var index: LibraryIndex {
        if libraryIndex.itemsVersion == itemsVersion && libraryIndex.foldersVersion == foldersVersion { return libraryIndex }
        var built = LibraryIndex(itemsVersion: itemsVersion, foldersVersion: foldersVersion)
        built.itemIDs.reserveCapacity(items.count)
        for item in items {
            built.itemIDs.insert(item.id)
            if let f = item.folderID { built.itemsInFolder[f, default: 0] += 1 } else { built.onBoardInProject[item.projectID, default: 0] += 1 }
            if let p = item.projectID { built.itemsInProject[p, default: 0] += 1 }
            built.thingsInProject[item.projectID, default: 0] += 1
            for tag in item.colorTags ?? [] { built.tagged[tag, default: 0] += 1 }
        }
        for folder in folders {
            if let parent = folder.parentID { built.foldersInFolder[parent, default: 0] += 1 } else { built.onBoardInProject[folder.projectID, default: 0] += 1 }
            built.thingsInProject[folder.projectID, default: 0] += 1
            for tag in folder.colorTags ?? [] { built.tagged[tag, default: 0] += 1 }
        }
        libraryIndex = built
        return built
    }

    /// Nothing on this tab's board (for Clear).
    var tabIsEmpty: Bool {
        switch filter {
        case .all: items.isEmpty && folders.isEmpty
        case .inbox: (index.onBoardInProject[nil] ?? 0) == 0
        case .project(let id): (index.onBoardInProject[id] ?? 0) == 0
        }
    }

    var visibleKey: VisibleKey {
        VisibleKey(itemsVersion: itemsVersion, foldersVersion: foldersVersion, filter: filter, openFolderID: openFolderID,
                   search: search, sort: BoardSort.current, compact: !(AppDelegate.shared?.panel?.isVisible ?? false))
    }
}

/// Each thing's searchable text (note, title, link, recognized text, #tags), lowercased — made once when you
/// start searching, and again only after the library changes, instead of for every thing on every key.
struct SearchIndex {
    fileprivate var itemsVersion = -1
    var text: [UUID: String] = [:]
}

extension Store {
    func searchableText(_ item: Item) -> String {
        if searchIndex.itemsVersion != itemsVersion {
            var built = SearchIndex(itemsVersion: itemsVersion)
            built.text.reserveCapacity(items.count)
            for i in items { built.text[i.id] = i.searchText }
            searchIndex = built
        }
        return searchIndex.text[item.id] ?? item.searchText
    }
}
