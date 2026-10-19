import AppKit
import SwiftUI

/// Stash's three ways to be on screen. One at a time; it reopens in the one you used last.
enum WindowMode: String {
    case popup, window, floating
    static let key = "window.mode"
    @MainActor static var current: WindowMode { WindowMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .popup }
    @MainActor static func set(_ mode: WindowMode) { UserDefaults.standard.set(mode.rawValue, forKey: key) }
}

