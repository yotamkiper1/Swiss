import AppKit
import SwiftUI

/// Day or night: Auto (by the clock — night from 7 pm to 7 am, the default), Light, Dark, or Match Mac.
enum StashAppearance: String {
    case auto, system, light, dark
    static let key = "appearance"

    /// Always by the clock now (no manual switch).
    static var current: StashAppearance { .auto }

    /// Night between 19:00 and 07:00.
    static var isNightTime: Bool {
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 19 || hour < 7
    }

    private static var timer: Timer?

    /// Every Stash window follows it. In Auto, it checks the time every minute.
    static func apply() {
        switch current {
        case .auto: NSApp.appearance = NSAppearance(named: isNightTime ? .darkAqua : .aqua)
        case .system: NSApp.appearance = nil
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        }
        if timer == nil {
            timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
                MainActor.assumeIsolated {
                    guard current == .auto else { return }
                    let wanted = NSAppearance(named: isNightTime ? .darkAqua : .aqua)
                    if NSApp.appearance?.name != wanted?.name { NSApp.appearance = wanted }
                }
            }
        }
    }

    static func set(_ value: StashAppearance) {
        UserDefaults.standard.set(value.rawValue, forKey: key)
        apply()
    }

    static var isDarkNow: Bool { NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua }
}

