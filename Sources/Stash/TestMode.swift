import Foundation

/// "Stash Test" (built with `./build.sh test`) is a separate app: its own bundle id — so its own settings —
/// its own library, its own URL scheme (stashtest://) and no global shortcuts. Tests can never touch the real
/// Stash, its library or its settings.
enum TestMode {
    static let isOn = Bundle.main.bundleIdentifier?.hasSuffix(".test") == true

    /// Stash's own folder in Application Support (tools, the old library) — a separate one for Stash Test.
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(isOn ? "Stash Test" : "Stash", isDirectory: true)
    }

    /// Temporary folders (drag copies, link notes) — separate for Stash Test, so it never clears the real app's.
    static func temp(_ name: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(isOn ? "Test-" + name : name, isDirectory: true)
    }

    /// Where the test app keeps its library unless STASH_LIBRARY says otherwise. Never the real one.
    static var defaultLibrary: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Stash Test/Library", isDirectory: true)
    }
}
