import AVFoundation
let root = CommandLine.arguments[1], outPath = CommandLine.arguments[2]
let video = AVURLAsset(url: URL(fileURLWithPath: "\(root)/out/video.mp4"))
let audio = AVURLAsset(url: URL(fileURLWithPath: "\(root)/out/audio.m4a"))
let comp = AVMutableComposition()
let sem = DispatchSemaphore(value: 0)
Task {
    let vt = try await video.loadTracks(withMediaType: .video)[0]
    let at = try await audio.loadTracks(withMediaType: .audio)[0]
    let vd = try await video.load(.duration)
    let cv = comp.addMutableTrack(withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try cv.insertTimeRange(CMTimeRange(start: .zero, duration: vd), of: vt, at: .zero)
    let ca = comp.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid)!
    try ca.insertTimeRange(CMTimeRange(start: .zero, duration: vd), of: at, at: .zero)
    try? FileManager.default.removeItem(atPath: outPath)
    let ex = AVAssetExportSession(asset: comp, presetName: AVAssetExportPresetPassthrough)!
    ex.outputURL = URL(fileURLWithPath: outPath); ex.outputFileType = .mp4; ex.shouldOptimizeForNetworkUse = true
    await ex.export()
    print("export status \(ex.status.rawValue) \(ex.error?.localizedDescription ?? "")")
    sem.signal()
}
sem.wait()
