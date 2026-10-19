import Foundation

/// Timing for the slow paths (save, mirror, export, board drawing). Only Stash Test records it, so the
/// real Stash pays nothing.
enum Perf {
    nonisolated(unsafe) static var cardBodies = 0
    nonisolated(unsafe) static var layoutPasses = 0
    nonisolated(unsafe) static var followerBodies = 0
    /// Time spent working out where board tiles go (all passes), and in the free-spot search alone.
    nonisolated(unsafe) static var layoutNanos: UInt64 = 0
    nonisolated(unsafe) static var freeSpotNanos: UInt64 = 0
    static var now: UInt64 { DispatchTime.now().uptimeNanoseconds }

    @discardableResult
    static func measure<T>(_ name: String, _ work: () -> T) -> T {
        guard TestMode.isOn else { return work() }
        let start = DispatchTime.now().uptimeNanoseconds
        let result = work()
        let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
        FileHandle.standardError.write(String(format: "perf %@ %.1f ms\n", name, ms).data(using: .utf8)!)
        return result
    }

    nonisolated(unsafe) static var folderBodies = 0
    nonisolated(unsafe) static var boardBodies = 0

    /// Stash Test with STASH_COUNTERS set: every 2 seconds, how much got redrawn.
    @MainActor static func startCounterLog() {
        guard TestMode.isOn else { return }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { _ in
            FileHandle.standardError.write("counters board=\(boardBodies) folders=\(folderBodies) cards=\(cardBodies) layouts=\(layoutPasses)\n".data(using: .utf8)!)
        }
    }
}
