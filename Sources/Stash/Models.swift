import Foundation

enum ItemKind: String, Codable {
    case link, image, text, file
}

struct Project: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var createdAt = Date()
    /// When you last opened it — the tabs show the ones you're working on.
    var lastOpened: Date?
    /// Pinned projects always have a tab.
    var pinned: Bool?
    /// Its tab was closed (×) — the project is still there (sidebar, ⌄, Go menu); opening it brings the tab back.
    var tabClosed: Bool?
}

/// A folder on the board. Lives inside a project (or Not Selected when `projectID` is nil).
struct Folder: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var style: FolderStyle
    var projectID: UUID?
    /// The folder this one sits in (nil = on the project's board).
    var parentID: UUID?
    /// True once you've given it a name yourself; until then only the icon shows.
    var isNamed: Bool?
    /// Color tags, like Finder's.
    var colorTags: [TagColor]?
    /// Where you put it on the board, per window (Arrange By: None).
    var spots: [String: BoardSpot]?
    var createdAt = Date()
}

enum FolderStyle: String, Codable, CaseIterable, Identifiable {
    // Styles you can pick for any folder
    case classic, kraft, pastel, midnight
    // Styles the organize button uses, one per kind of item.
    // (`photos` is PhotoBook and `noteHanger` is Notepad; the raw names stay for older libraries.)
    case linker, photos, noteHanger, files

    var id: String { rawValue }

    /// Linker, PhotoBook, Notepad and Files hold one kind of thing each.
    var isKind: Bool { [.linker, .photos, .noteHanger, .files].contains(self) }

    var name: String {
        switch self {
        case .classic: "Classic"
        case .kraft: "Kraft"
        case .pastel: "Pastel"
        case .midnight: "Midnight"
        case .linker: "Linker"
        case .photos: "PhotoBook"
        case .noteHanger: "Notepad"
        case .files: "Files"
        }
    }

    /// Where the organize button puts each kind of item.
    static func forKind(_ kind: ItemKind) -> FolderStyle {
        switch kind {
        case .link: .linker
        case .image: .photos
        case .text: .noteHanger
        case .file: .files
        }
    }
}

struct Item: Codable, Identifiable, Hashable {
    var id = UUID()
    var kind: ItemKind
    var projectID: UUID?
    var folderID: UUID?
    var createdAt = Date()
    /// The note itself for `.text`, or an optional note attached to other kinds.
    var text: String?
    /// The note with its formatting (RTF), when it has any.
    var richText: Data?
    /// Web URL for `.link`, file URL for `.file`.
    var url: String?
    var title: String?
    /// File name inside the library's images folder (the image itself, or a link/file thumbnail).
    var imageFile: String?
    /// Page an image was dragged from.
    var sourceURL: String?
    /// Where its file is in ~/Documents/.Stash (relative), kept up to date by the mirror.
    var storedPath: String?
    /// Text recognized inside images, used for search.
    var ocrText: String?
    var tags: [String] = []
    /// Color tags, like Finder's.
    var colorTags: [TagColor]?
    /// Where you put it on the board, per window (Arrange By: None).
    var spots: [String: BoardSpot]?
    /// Linked files: finds the original again if it's moved or renamed.
    var bookmark: Data?
}

/// Where something sits on the board after you've dragged it there.
struct BoardSpot: Codable, Hashable {
    var x: Double
    var y: Double
    /// The board it was placed on ("f:<folder>" or "p:<project>"), so the spot is forgotten once it moves elsewhere.
    var board: String
}

/// A lined notebook page. Each project has its own pages.
struct NotebookPage: Codable, Identifiable, Hashable {
    var id = UUID()
    var projectID: UUID?
    var createdAt = Date()
    var title: String?
    var notes: [PageNote] = []
}

/// Text written somewhere on a notebook page.
struct PageNote: Codable, Identifiable, Hashable {
    var id = UUID()
    /// Top-left corner on the page, in points.
    var x: Double
    var y: Double
    var width: Double
    var text = ""
    var isQuote = false
}

/// The seven Finder tag colors.
enum TagColor: String, Codable, CaseIterable, Identifiable {
    case red, orange, yellow, green, blue, purple, gray
    var id: String { rawValue }
    /// The name Finder uses (so tags show up on the files in Documents too).
    var finderName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Something you can select on the board.
enum Selectable: Hashable {
    case item(UUID), folder(UUID)
}

extension Collection where Element == Selectable {
    var itemIDs: [UUID] { compactMap { if case .item(let id) = $0 { id } else { nil } } }
    var folderIDs: [UUID] { compactMap { if case .folder(let id) = $0 { id } else { nil } } }
}

/// Where new things get saved: a project (nil = Not Selected) and optionally a folder in it.
struct Place: Hashable {
    var project: UUID?
    var folder: UUID?
}

/// Which tab the board is showing. `.inbox` is the "Not Selected" tab.
/// `.all` is no longer shown; it's only kept so older libraries still load.
enum Filter: Codable, Hashable {
    case all, inbox, project(UUID)
}

extension Item {
    var linkURL: URL? { url.flatMap(URL.init(string:)) }

    var host: String {
        guard let host = linkURL?.host else { return "" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var sourceHost: String? {
        guard let host = sourceURL.flatMap(URL.init(string:))?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var searchText: String {
        ([text, title, url, ocrText, sourceURL].compactMap { $0 } + tags.map { "#" + $0 })
            .joined(separator: " ")
            .lowercased()
    }
}


/// Google Docs, Sheets, Slides and Forms links (and Office files on the web) are documents, not plain links.
enum OnlineDocument {
    case docs, sheets, slides, forms

    init?(_ url: URL?) {
        guard let url, let host = url.host?.lowercased() else { return nil }
        let path = url.path.lowercased()
        if host == "docs.google.com" {
            if path.hasPrefix("/document") { self = .docs }
            else if path.hasPrefix("/spreadsheets") { self = .sheets }
            else if path.hasPrefix("/presentation") { self = .slides }
            else if path.hasPrefix("/forms") { self = .forms }
            else { return nil }
        } else if host.hasSuffix("sheets.google.com") { self = .sheets }
        else if host.hasSuffix("slides.google.com") { self = .slides }
        else if host.hasSuffix(".sharepoint.com") || host == "onedrive.live.com" || host == "1drv.ms" {
            if path.contains(".xls") || path.contains("/x/") { self = .sheets }
            else if path.contains(".ppt") || path.contains("/p/") { self = .slides }
            else { self = .docs }
        } else { return nil }
    }

    var symbol: String {
        switch self {
        case .docs: "doc.text.fill"
        case .sheets: "tablecells.fill"
        case .slides: "rectangle.on.rectangle.angled.fill"
        case .forms: "list.bullet.rectangle.fill"
        }
    }

    var color: (Double, Double, Double) {
        switch self {
        case .docs: (0.26, 0.52, 0.96)
        case .sheets: (0.06, 0.62, 0.35)
        case .slides: (0.96, 0.71, 0.0)
        case .forms: (0.45, 0.33, 0.78)
        }
    }
}

extension Item {
    /// The folder the wand puts it in: documents (Office files, Google Docs / Sheets / Slides links) go with Files.
    var organizeStyle: FolderStyle {
        if kind == .link, OnlineDocument(linkURL) != nil { return .files }
        return .forKind(kind)
    }
}


extension FolderStyle {
    /// In Finder a folder's kind is its color tag: plain folders, with the color of Swiss's dot. So a Linker in a
    /// connected folder, or a Swiss folder dragged out to the Desktop, is a normal Finder folder tagged Green.
    var finderTag: TagColor? {
        switch self {
        case .classic: nil
        case .linker: .green
        case .photos: .red
        case .noteHanger: .orange
        case .files: .gray
        case .kraft: .yellow
        case .pastel: .purple
        case .midnight: .blue
        }
    }

    /// The other way: a Finder folder's color tags → the kind of folder it shows as in Swiss.
    static func fromFinderTags(_ names: [String]) -> FolderStyle {
        for style in [FolderStyle.linker, .photos, .noteHanger, .files]
        where style.finderTag.map({ names.contains($0.finderName) }) == true {
            return style
        }
        return .classic
    }

    /// A kind folder's name ("Linker", "PhotoBook"…) → its kind.
    static func named(_ name: String) -> FolderStyle? {
        choices.first { $0 != .classic && $0.name == name }
    }
}


extension FolderStyle {
    /// The folder kinds you can pick: Classic, Linker, PhotoBook, Notepad, Files. (Kraft, Pastel and Midnight are
    /// gone; folders that had them are Classic now.)
    static let choices: [FolderStyle] = [.classic, .linker, .photos, .noteHanger, .files]
}
