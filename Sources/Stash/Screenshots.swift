import AppKit

/// ⌥Space right after taking a screenshot saves it to the project that's open.
@MainActor
final class ScreenshotCatcher {
    /// How old a screenshot can be and still count as "just taken".
    private let recentWindow: TimeInterval = 90
    /// macOS writes the file only after its floating thumbnail goes away, so keep watching a little.
    private let waitForFile: TimeInterval = 8
    private var imported: Set<String> = []
    private var watch: Task<Void, Never>?

    /// Where macOS saves screenshots (Screenshot app → Options → Save to).
    private var folder: URL {
        let saved = UserDefaults(suiteName: "com.apple.screencapture")?.string(forKey: "location")
        let path = (saved.map { ($0 as NSString).expandingTildeInPath }) ?? (NSHomeDirectory() + "/Desktop")
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// Saves a screenshot taken in the last minute and a half into `place`. If the file
    /// isn't written yet, watches for it for a few seconds. Returns true if one was saved right away.
    @discardableResult
    func catchRecent(into place: Place) -> Bool {
        let pressed = Date()
        if let file = newestScreenshot(since: pressed.addingTimeInterval(-recentWindow)) {
            save(file, into: place)
            return true
        }
        watch?.cancel()
        watch = Task { [weak self] in
            let deadline = pressed.addingTimeInterval(self?.waitForFile ?? 0)
            while Date() < deadline, !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(400))
                guard let self else { return }
                if let file = self.newestScreenshot(since: pressed.addingTimeInterval(-self.recentWindow)) {
                    self.save(file, into: place)
                    return
                }
            }
        }
        return false
    }

    private func save(_ file: URL, into place: Place) {
        imported.insert(file.path)
        Store.shared.addFile(file, place: place)
    }

    private func newestScreenshot(since: Date) -> URL? {
        let keys: [URLResourceKey] = [.creationDateKey]
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else {
            return nil
        }
        return files
            .filter { Store.imageExtensions.contains($0.pathExtension.lowercased()) && !imported.contains($0.path) }
            .compactMap { url -> (URL, Date)? in
                guard let created = (try? url.resourceValues(forKeys: Set(keys)))?.creationDate, created >= since,
                      Self.isScreenshot(url) else { return nil }
                return (url, created)
            }
            .max { $0.1 < $1.1 }?
            .0
    }

    /// macOS tags its screenshots, whatever language their file name is in.
    private static func isScreenshot(_ url: URL) -> Bool {
        getxattr(url.path, "com.apple.metadata:kMDItemIsScreenCapture", nil, 0, 0, 0) > 0
    }
}
