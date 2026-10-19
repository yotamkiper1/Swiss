import Foundation
import os

/// Crash-safe saving.
///
/// - Every save becomes a numbered snapshot handed to one background writer, so typing and dragging never wait
///   for the disk, and bursts of saves collapse into one write (only the newest snapshot is written).
/// - The new file is written next to the library, checked by reading it back, then swapped in atomically.
///   The version it replaces is kept as library.prev.json.
/// - About once an hour a compressed copy goes to .stash/backups (the newest 24 are kept).
/// - At launch, if library.json can't be read, Stash falls back to library.prev.json, then the newest backup —
///   and keeps the damaged file aside instead of starting empty over it.
extension Store {
    static let schemaVersion = 2

    var previousLibraryURL: URL { dataDir.appendingPathComponent("library.prev.json") }
    var backupsDir: URL { dataDir.appendingPathComponent("backups", isDirectory: true) }

    static let persistQueue = DispatchQueue(label: "stash.persist", qos: .userInitiated)
    private static let newest = OSAllocatedUnfairLock(initialState: 0)

    nonisolated static func decodeLibrary(at url: URL) -> Library? {
        guard var data = try? Data(contentsOf: url), !data.isEmpty else { return nil }
        if url.pathExtension == "lzfse" { // hourly backups are stored compressed
            guard let plain = try? (data as NSData).decompressed(using: .lzfse) as Data else { return nil }
            data = plain
        }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Library.self, from: data)
    }

    nonisolated static func backupFiles(in dir: URL) -> [URL] {
        ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("library-") && ["json", "lzfse"].contains($0.pathExtension) }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } // names carry the time, newest first
    }

    nonisolated static func persist(_ lib: Library, to url: URL, previous: URL, backups: URL) {
        let revision = lib.revision ?? 0
        newest.withLock { $0 = max($0, revision) }
        persistQueue.async {
            // A newer snapshot is already waiting: skip this one.
            guard newest.withLock({ $0 }) == revision else { return }
            Perf.measure("library write (background)") { write(lib, to: url, previous: previous, backups: backups) }
        }
    }

    /// Waits until everything handed to the writer is on disk (used when Stash quits).
    nonisolated static func flushSaves() { persistQueue.sync {} }

    private nonisolated static func write(_ lib: Library, to url: URL, previous: URL, backups: URL) {
        let fm = FileManager.default
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(lib) else { return }
        let temp = url.deletingLastPathComponent().appendingPathComponent("library.writing.json")
        do {
            try data.write(to: temp)
            // Read it back before trusting it.
            guard decodeLibrary(at: temp)?.revision == lib.revision else { throw CocoaError(.fileWriteUnknown) }
            if fm.fileExists(atPath: url.path) {
                try? fm.removeItem(at: previous)
                _ = try fm.replaceItemAt(url, withItemAt: temp, backupItemName: previous.lastPathComponent,
                                         options: [.withoutDeletingBackupItem])
            } else {
                try fm.moveItem(at: temp, to: url)
            }
        } catch {
            try? fm.removeItem(at: temp) // the old library stays as it was
            return
        }
        hourlyBackup(of: url, into: backups)
    }

    private nonisolated static func hourlyBackup(of url: URL, into dir: URL) {
        let fm = FileManager.default
        let existing = backupFiles(in: dir)
        if let last = existing.first,
           let date = (try? last.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           Date().timeIntervalSince(date) < 3600 { return }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let stamp = Date().formatted(.iso8601.year().month().day().time(includingFractionalSeconds: false)
            .dateSeparator(.dash).timeSeparator(.omitted)).replacingOccurrences(of: ":", with: "")
        // Compressed: a backup takes about a tenth of the space.
        if let data = try? Data(contentsOf: url), let packed = try? (data as NSData).compressed(using: .lzfse) as Data {
            try? packed.write(to: dir.appendingPathComponent("library-\(stamp).json.lzfse"), options: .atomic)
        }
        for old in backupFiles(in: dir).dropFirst(24) { try? fm.removeItem(at: old) }
    }
}
