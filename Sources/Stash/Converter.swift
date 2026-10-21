import AppKit
import AVFoundation
import SwiftUI

/// Convert to MP3 / MP4 and Download as MP3 / MP4 — all built into Stash, nothing to install.
/// MP4s and sound decoding use the Mac's own media frameworks; MP3s are written by a tiny
/// bundled LAME encoder; links are fetched by the bundled yt-dlp.
enum ConvertTarget: String, Identifiable {
    case mp3, mp4
    var id: String { rawValue }
    var title: String { self == .mp3 ? "Convert to MP3" : "Convert to MP4" }
}

enum ConvertError: LocalizedError {
    case unreadable(String), noSound, failed(String)
    var errorDescription: String? {
        switch self {
        case .unreadable(let ext): "The Mac can't read .\(ext) files"
        case .noSound: "There's no sound in it"
        case .failed(let what): what
        }
    }
}

enum Converter {
    /// Formats the Mac's media frameworks can read.
    static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "3gp"]
    static let audioExtensions: Set<String> = ["mp3", "wav", "aiff", "aif", "m4a", "aac", "flac", "caf"]

    /// Sites with video or music to download (and direct links to media files).
    /// Ordinary web links don't get MP3 / MP4 buttons.
    static let mediaHosts = ["youtube.com", "youtu.be", "vimeo.com", "soundcloud.com", "tiktok.com", "instagram.com",
                             "x.com", "twitter.com", "facebook.com", "fb.watch", "dailymotion.com", "twitch.tv",
                             "bandcamp.com", "mixcloud.com"]

    static func isMediaLink(_ url: URL?) -> Bool {
        guard let url, !url.isFileURL else { return false }
        if videoExtensions.union(audioExtensions).union(["webm", "ogg", "opus"]).contains(url.pathExtension.lowercased()) { return true }
        guard let host = url.host?.lowercased() else { return false }
        return mediaHosts.contains { host == $0 || host.hasSuffix("." + $0) }
    }

    /// What a file can be turned into.
    static func targets(for url: URL?) -> [ConvertTarget] {
        guard let ext = url?.pathExtension.lowercased() else { return [] }
        if videoExtensions.contains(ext) { return ext == "mp4" ? [.mp3] : [.mp3, .mp4] }
        if audioExtensions.contains(ext) { return ext == "mp3" ? [.mp4] : [.mp3, .mp4] }
        return []
    }

    // MARK: Bundled tools

    static var bundledTools: URL? { Bundle.main.resourceURL?.appendingPathComponent("tools", isDirectory: true) }

    /// The MP3 encoder inside Stash. (STASH_LAME points a test run elsewhere.)
    static var lame: URL? {
        let path = testOverride("STASH_LAME") ?? bundledTools?.appendingPathComponent("lame").path
        return path.flatMap { FileManager.default.isExecutableFile(atPath: $0) ? URL(fileURLWithPath: $0) : nil }
    }

    /// A tool from somewhere else, for test runs only: in the real Swiss nothing outside it can choose what it runs.
    private static func testOverride(_ name: String) -> String? {
        TestMode.isOn ? ProcessInfo.processInfo.environment[name] : nil
    }

    /// yt-dlp: the copy inside Stash, or an updated one in Application Support once you've updated it
    /// (Stash can't change its own insides, so updating makes that one copy).
    static var updatedYtdlp: URL { TestMode.supportDir.appendingPathComponent("tools/yt-dlp") }

    static var ytdlp: URL? {
        if let override = testOverride("STASH_YTDLP") { return URL(fileURLWithPath: override) }
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: updatedYtdlp.path) { return updatedYtdlp }
        let bundled = bundledTools?.appendingPathComponent("yt-dlp")
        return bundled.flatMap { fm.isExecutableFile(atPath: $0.path) ? $0 : nil }
    }

    /// Makes the updatable copy (only when you ask to update the downloader).
    static func prepareYtdlpForUpdate() -> URL? {
        let fm = FileManager.default
        if fm.isExecutableFile(atPath: updatedYtdlp.path) { return updatedYtdlp }
        guard let bundled = bundledTools?.appendingPathComponent("yt-dlp") else { return nil }
        try? fm.createDirectory(at: updatedYtdlp.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? fm.copyItem(at: bundled, to: updatedYtdlp)
        return fm.isExecutableFile(atPath: updatedYtdlp.path) ? updatedYtdlp : nil
    }

    /// Runs a tool and waits. Each line it prints goes to `onLine`.
    @discardableResult
    static func run(_ tool: URL, _ arguments: [String], started: ((Process) -> Void)? = nil,
                    onLine: ((String) -> Void)? = nil) -> (ok: Bool, output: String) {
        let process = Process()
        process.executableURL = tool
        process.arguments = arguments
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        var collected = ""
        let lock = NSLock()
        pipe.fileHandleForReading.readabilityHandler = { handle in
            guard let text = String(data: handle.availableData, encoding: .utf8), !text.isEmpty else { return }
            lock.lock(); collected += text; lock.unlock()
            text.split(whereSeparator: \.isNewline).forEach { onLine?(String($0)) }
        }
        do {
            try process.run()
            started?(process) // so a download can be cancelled
            process.waitUntilExit()
        } catch {
            return (false, error.localizedDescription)
        }
        pipe.fileHandleForReading.readabilityHandler = nil
        lock.lock(); defer { lock.unlock() }
        return (process.terminationStatus == 0, collected)
    }

    // MARK: Converting with the Mac's own frameworks

    /// Any file with sound → MP3 (the Mac decodes it, LAME encodes it). The sound is streamed straight into the
    /// encoder — no big temporary WAV file, however long the video.
    static func toMP3(_ input: URL, _ output: URL) async throws {
        guard let lame else { throw ConvertError.failed("The MP3 encoder is missing from Swiss") }
        let asset = AVURLAsset(url: input)
        guard (try? await asset.load(.isReadable)) == true else { throw ConvertError.unreadable(input.pathExtension) }
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ConvertError.noSound }
        let (rate, sourceChannels) = try await format(of: track)
        let channels = min(sourceChannels, 2)
        // About 1 MB per minute at this quality: make sure there's room.
        let minutes = (try? await asset.load(.duration)).map { $0.seconds / 60 } ?? 0
        if let free = BigFiles.freeSpace(at: output), Double(free) < minutes * 2_500_000 + 200_000_000 {
            throw ConvertError.failed("Not enough disk space for the MP3")
        }
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
        ]
        let reader = try AVAssetReader(asset: asset)
        let pcm = AVAssetReaderTrackOutput(track: track, outputSettings: settings)
        reader.add(pcm)
        guard reader.startReading() else { throw ConvertError.failed("Couldn't read the sound") }

        let process = Process()
        process.executableURL = lame
        let khz = rate / 1000
        process.arguments = ["--quiet", "-r", "-s", khz == khz.rounded() ? String(Int(khz)) : String(khz),
                             "--bitwidth", "16", "--signed", "--little-endian", "-m", channels == 1 ? "m" : "j",
                             "-V", "2", "-", output.path]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        let writer = stdin.fileHandleForWriting
        var failed = false
        while let buffer = pcm.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            var length = 0
            var pointer: UnsafeMutablePointer<CChar>?
            guard CMBlockBufferGetDataPointer(block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length, dataPointerOut: &pointer) == noErr,
                  let pointer else { continue }
            // Blocks while the encoder catches up, so memory stays flat.
            do { try writer.write(contentsOf: Data(bytesNoCopy: pointer, count: length, deallocator: .none)) } catch { failed = true; break }
        }
        try? writer.close()
        process.waitUntilExit()
        if reader.status == .failed { failed = true }
        guard !failed, process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            try? FileManager.default.removeItem(at: output)
            throw ConvertError.failed("Couldn't write the MP3")
        }
    }

    /// Video → MP4, using Apple's exporter (on the Mac's video hardware). When the picture and sound are already
    /// in formats an MP4 holds (H.264 / HEVC with AAC, as from most cameras and phones), they're just rewrapped —
    /// seconds instead of minutes, and no quality lost. Otherwise it's re-encoded.
    static func videoToMP4(_ input: URL, _ output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard (try? await asset.load(.isReadable)) == true else { throw ConvertError.unreadable(input.pathExtension) }
        if let free = BigFiles.freeSpace(at: output), free < BigFiles.size(of: input) + 500_000_000 {
            throw ConvertError.failed("Not enough disk space for the MP4")
        }
        if await canRewrap(asset), (try? await export(asset, preset: AVAssetExportPresetPassthrough, to: output)) != nil { return }
        try? FileManager.default.removeItem(at: output) // the rewrap didn't work: make it properly
        try await export(asset, preset: AVAssetExportPresetHighestQuality, to: output)
    }

    private static func export(_ asset: AVURLAsset, preset: String, to output: URL) async throws {
        guard let export = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw ConvertError.unreadable(asset.url.pathExtension)
        }
        export.outputURL = output
        export.outputFileType = .mp4
        export.shouldOptimizeForNetworkUse = true
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            export.exportAsynchronously { done.resume() }
        }
        guard export.status == .completed else { throw ConvertError.failed(export.error?.localizedDescription ?? "Couldn't make the MP4") }
    }

    /// True when every track can go into an MP4 as it is.
    private static func canRewrap(_ asset: AVURLAsset) async -> Bool {
        guard let tracks = try? await asset.load(.tracks), !tracks.isEmpty else { return false }
        let fine: Set<FourCharCode> = [kCMVideoCodecType_H264, kCMVideoCodecType_HEVC, kAudioFormatMPEG4AAC,
                                       FourCharCode(0x6876_6331) /* hvc1 */, FourCharCode(0x6865_7631) /* hev1 */]
        for track in tracks {
            guard track.mediaType == .video || track.mediaType == .audio else { continue } // timecode etc. are left out
            let descriptions = (try? await track.load(.formatDescriptions)) ?? []
            guard let d = descriptions.first, fine.contains(CMFormatDescriptionGetMediaSubType(d)) else { return false }
        }
        return true
    }

    /// Waits for a writer input to take more, but never forever: 30 seconds without progress means it's stuck.
    private static func waitUntilReady(_ input: AVAssetWriterInput) async throws {
        var waited = 0
        while !input.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(5))
            waited += 5
            if waited > 30_000 { throw ConvertError.failed("The conversion got stuck") }
        }
    }

    /// Sound → MP4 with a still black picture.
    static func audioToMP4(_ input: URL, _ output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw ConvertError.noSound }
        let duration = try await asset.load(.duration)
        let reader = try AVAssetReader(asset: asset)
        let pcm = AVAssetReaderTrackOutput(track: track, outputSettings: [AVFormatIDKey: kAudioFormatLinearPCM])
        reader.add(pcm)
        let (rate, channels) = try await format(of: track)

        let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
        let size = (width: 1280, height: 720)
        let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: size.width, AVVideoHeightKey: size.height,
        ])
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: size.width, kCVPixelBufferHeightKey as String: size.height,
        ])
        // AAC at 44.1 kHz with a bit rate that suits mono or stereo (any source is resampled to it).
        _ = rate
        let outChannels = min(channels, 2)
        let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
            AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: outChannels,
            AVEncoderBitRateKey: outChannels == 1 ? 96_000 : 160_000,
        ])
        writer.add(video)
        writer.add(audio)
        guard reader.startReading(), writer.startWriting() else { throw ConvertError.failed("Couldn't start the MP4") }
        writer.startSession(atSourceTime: .zero)

        // The picture first — a black frame at the start and one at the end, so it lasts as long as the sound —
        // and finished, so the writer doesn't hold the sound back waiting for more picture.
        if let black = blackFrame(width: size.width, height: size.height) {
            try await waitUntilReady(video)
            adaptor.append(black, withPresentationTime: .zero)
            try await waitUntilReady(video)
            adaptor.append(black, withPresentationTime: CMTimeSubtract(duration, CMTime(value: 1, timescale: 30)))
        }
        video.markAsFinished()
        while let buffer = pcm.copyNextSampleBuffer() {
            try await waitUntilReady(audio)
            audio.append(buffer)
        }
        audio.markAsFinished()
        writer.endSession(atSourceTime: duration) // exactly as long as the sound (the last frame would otherwise run on)
        await writer.finishWriting()
        guard writer.status == .completed else { throw ConvertError.failed(writer.error?.localizedDescription ?? "Couldn't make the MP4") }
    }

    private static func format(of track: AVAssetTrack) async throws -> (rate: Double, channels: Int) {
        let descriptions = try await track.load(.formatDescriptions)
        guard let description = descriptions.first,
              let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(description)?.pointee else { return (44_100, 2) }
        return (asbd.mSampleRate > 0 ? asbd.mSampleRate : 44_100, max(1, Int(asbd.mChannelsPerFrame)))
    }

    private static func blackFrame(width: Int, height: Int) -> CVPixelBuffer? {
        var buffer: CVPixelBuffer?
        CVPixelBufferCreate(kCFAllocatorDefault, width, height, kCVPixelFormatType_32BGRA, nil, &buffer)
        guard let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        if let base = CVPixelBufferGetBaseAddress(buffer) {
            memset(base, 0, CVPixelBufferGetDataSize(buffer)) // all zeros = black
        }
        CVPixelBufferUnlockBaseAddress(buffer, [])
        return buffer
    }

    /// Picks the conversion for a file.
    /// One conversion at a time (they use every core and lots of disk); the rest wait their turn.
    static func convert(_ input: URL, to target: ConvertTarget, output: URL) async throws {
        try await HeavyJobs.conversions.run { try await convertNow(input, to: target, output: output) }
    }

    private static func convertNow(_ input: URL, to target: ConvertTarget, output: URL) async throws {
        let ext = input.pathExtension.lowercased()
        switch target {
        case .mp3: try await toMP3(input, output)
        case .mp4 where audioExtensions.contains(ext): try await audioToMP4(input, output)
        case .mp4: try await videoToMP4(input, output)
        }
    }
}

extension Store {
    /// Converts a file card. The result is saved next to it, in the same folder.
    func convert(_ itemID: UUID, to target: ConvertTarget) {
        guard let item = items.first(where: { $0.id == itemID }), let input = contentURL(item) else { return }
        let resultID = UUID()
        let folder = filesDir.appendingPathComponent(resultID.uuidString, isDirectory: true)
        let output = folder.appendingPathComponent(input.deletingPathExtension().lastPathComponent + "." + target.rawValue)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        converting.insert(itemID)
        jobFailures[itemID] = nil
        cancelledJobs.remove(itemID)
        let place = Place(project: item.projectID, folder: item.folderID)
        pending.append(PendingResult(id: resultID, sourceID: itemID, name: output.lastPathComponent, target: target,
                                     place: place, stage: .converting))
        Task.detached {
            do {
                try await Converter.convert(input, to: target, output: output)
                await MainActor.run { Store.shared.finishConversion(itemID, resultID: resultID, file: output, place: place, source: nil) }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                await MainActor.run {
                    Store.shared.jobFailed(itemID, resultID: resultID, target: target, download: false, reason: error.localizedDescription)
                }
            }
        }
    }

    /// Downloads what a link points to (a video page, a sound…) as an MP3 or MP4, saved next to the link.
    func download(_ itemID: UUID, as target: ConvertTarget) {
        // Only real web addresses: a "link" starting with "-" would otherwise be read by the downloader as an option.
        guard let item = items.first(where: { $0.id == itemID }), let link = item.linkURL, Safety.isWebURL(link) else { return }
        guard let ytdlp = Converter.ytdlp else {
            flash("The downloader is missing from Swiss")
            return
        }
        let resultID = UUID()
        let folder = filesDir.appendingPathComponent(resultID.uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        converting.insert(itemID)
        jobFailures[itemID] = nil
        cancelledJobs.remove(itemID)
        let place = Place(project: item.projectID, folder: item.folderID)
        pending.append(PendingResult(id: resultID, sourceID: itemID, name: (item.title ?? item.host) + "." + target.rawValue,
                                     target: target, place: place, stage: .downloading(0)))
        // Formats that come as one file, so no FFmpeg is needed: the sound alone (M4A) for MP3,
        // a ready-made MP4 for video.
        let format = target == .mp3 ? "ba[ext=m4a]/ba[acodec^=mp4a]/b[ext=mp4]" : "b[ext=mp4]/b"
        // --ignore-config: settings files on the Mac can't add options (like ones that run commands).
        // "--": everything after it is a link, never an option.
        let arguments = ["--ignore-config", "--no-playlist", "--newline", "--no-mtime", "-f", format,
                         "-o", folder.path + "/%(title).120B.%(ext)s", "--", link.absoluteString]
        Task.detached {
            let result = Converter.run(ytdlp, arguments, started: { process in
                Task { @MainActor in Store.shared.jobProcesses[itemID] = process }
            }) { line in
                // "[download]  42.3% of …" → the card's progress bar.
                guard line.contains("[download]"), let range = line.range(of: #"(\d+(\.\d+)?)%"#, options: .regularExpression),
                      let percent = Double(line[range].dropLast()) else { return }
                Task { @MainActor in Store.shared.setPending(resultID, stage: .downloading(percent / 100)) }
            }
            let fetched = ((try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)) ?? [])
                .first { !$0.lastPathComponent.hasPrefix(".") && $0.pathExtension != "part" }
            do {
                guard result.ok, let fetched else {
                    let reason = result.output.split(whereSeparator: \.isNewline).last { $0.contains("ERROR") }.map(String.init)
                    throw ConvertError.failed(reason?.replacingOccurrences(of: "ERROR: ", with: "") ?? "The download didn't work")
                }
                var final = fetched
                if fetched.pathExtension.lowercased() != target.rawValue {
                    // e.g. the M4A sound → MP3, made right here.
                    await MainActor.run { Store.shared.setPending(resultID, stage: .converting) }
                    final = fetched.deletingPathExtension().appendingPathExtension(target.rawValue)
                    try await Converter.convert(fetched, to: target, output: final)
                    try? FileManager.default.removeItem(at: fetched)
                }
                let file = final
                Safety.quarantine(file, from: link) // downloaded: macOS checks it like a Safari download
                await MainActor.run { Store.shared.finishConversion(itemID, resultID: resultID, file: file, place: place, source: link) }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                await MainActor.run {
                    Store.shared.jobFailed(itemID, resultID: resultID, target: target, download: true, reason: error.localizedDescription)
                }
            }
        }
    }

    fileprivate func finishConversion(_ itemID: UUID, resultID: UUID, file: URL, place: Place, source: URL?) {
        converting.remove(itemID)
        pending.removeAll { $0.id == resultID }
        jobProcesses[itemID] = nil
        if cancelledJobs.remove(itemID) != nil { // cancelled while it was finishing: throw the result away
            try? FileManager.default.removeItem(at: file.deletingLastPathComponent())
            return
        }
        var result = Item(id: resultID, kind: .file, projectID: place.project, folderID: place.folder)
        result.url = file.absoluteString
        result.title = file.lastPathComponent
        result.sourceURL = source?.absoluteString
        // A downloaded link turns into the MP3/MP4 right where it was — no extra copy on the board.
        // The link lives on inside it (the small link badge), to open, copy, bring back or remove.
        if source != nil, let index = items.firstIndex(where: { $0.id == itemID }) {
            checkpoint("Download")
            let link = items[index]
            result.projectID = link.projectID
            result.folderID = link.folderID
            result.spots = link.spots
            result.colorTags = link.colorTags
            result.createdAt = link.createdAt
            if link.imageFile != nil, file.pathExtension.lowercased() == "mp3" { result.imageFile = link.imageFile } // keeps the video's picture
            items[index] = result
            selection.remove(.item(itemID))
            save()
            if result.imageFile == nil { makeThumbnail(for: resultID, from: file) }
            flash("Made \(file.lastPathComponent)", undo: true)
            return
        }
        add(result)
        makeThumbnail(for: resultID, from: file)
    }

    /// A download or conversion stopped: say why on the thing itself (a red ! with Try Again), unless you cancelled it.
    func jobFailed(_ itemID: UUID, resultID: UUID, target: ConvertTarget, download: Bool, reason: String) {
        converting.remove(itemID)
        pending.removeAll { $0.id == resultID }
        jobProcesses[itemID] = nil
        if cancelledJobs.remove(itemID) != nil { flash("Cancelled"); return }
        jobFailures[itemID] = JobFailure(target: target, download: download, reason: reason)
        flash(download ? "Couldn't download — see the red ! on it" : "Couldn't convert — see the red ! on it")
    }

    /// Stops a download or conversion that's running.
    func cancelJob(_ itemID: UUID) {
        guard converting.contains(itemID) else { return }
        cancelledJobs.insert(itemID)
        jobProcesses[itemID]?.terminate()
        // Conversions can't be stopped halfway; their result is simply thrown away when they finish.
        converting.remove(itemID)
        pending.removeAll { $0.sourceID == itemID }
        flash("Cancelled")
    }

    func retryJob(_ itemID: UUID) {
        guard let failure = jobFailures[itemID] else { return }
        jobFailures[itemID] = nil
        if failure.download { download(itemID, as: failure.target) } else { convert(itemID, to: failure.target) }
    }

    /// The link a downloaded file came from, back on the board as its own link.
    func restoreSourceLink(of itemID: UUID) {
        guard let item = items.first(where: { $0.id == itemID }), let source = item.sourceURL else { return }
        addText(source, place: Place(project: item.projectID, folder: item.folderID))
    }

    func removeSourceLink(of itemID: UUID) {
        guard let index = items.firstIndex(where: { $0.id == itemID }) else { return }
        checkpoint("Remove Link")
        items[index].sourceURL = nil
        save()
    }

    func setPending(_ id: UUID, stage: PendingResult.Stage) {
        guard let index = pending.firstIndex(where: { $0.id == id }) else { return }
        pending[index].stage = stage
    }

    /// The loading placeholders to show where you are.
    /// Progress is shown on the link or file being turned into the MP3/MP4 itself, so no extra cards.
    var visiblePending: [PendingResult] { [] }

    func progress(for itemID: UUID) -> PendingResult? { pending.first { $0.sourceID == itemID } }
}

/// Why a download or conversion didn't work, kept on the thing until you try again or dismiss it.
struct JobFailure: Equatable {
    let target: ConvertTarget
    let download: Bool
    let reason: String
}

/// An MP3/MP4 that's still being made: shown as a see-through card until it's ready.
struct PendingResult: Identifiable, Equatable {
    enum Stage: Equatable {
        case downloading(Double), converting
    }
    let id: UUID
    let sourceID: UUID
    var name: String
    let target: ConvertTarget
    let place: Place
    var stage: Stage

    var label: String {
        switch stage {
        case .downloading(let p): p > 0 ? "Downloading \(Int(p * 100))%" : "Starting download…"
        case .converting: "Making the \(target.rawValue.uppercased())…"
        }
    }

    var fraction: Double? {
        if case .downloading(let p) = stage, p > 0 { return p }
        return nil
    }
}

/// After a link is downloaded: "Delete the link?"
struct LinkCleanup: Equatable {
    let linkID: UUID
    let resultName: String
}

/// The loading placeholder: a faint card with a soft pulse and a thin progress bar.
struct PendingCard: View {
    let pending: PendingResult
    var asRow = false
    @State private var pulse = false

    var body: some View {
        Group {
            if asRow { row } else { card }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { pulse = true }
        }
        .help(pending.label)
    }

    private var symbol: String { pending.target == .mp3 ? "music.note" : "film" }

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack {
                RoundedRectangle(cornerRadius: 0)
                    .fill(Color.primary.opacity(pulse ? 0.07 : 0.035))
                Image(systemName: symbol)
                    .font(.system(size: 22, weight: .light))
                    .foregroundStyle(.tertiary)
            }
            .frame(height: 72)
            VStack(alignment: .leading, spacing: 5) {
                Text(pending.name)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                bar
                Text(pending.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
            .padding(9)
        }
        .background(Color.primary.opacity(0.02))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
        )
        .opacity(0.85)
    }

    private var row: some View {
        HStack(spacing: 7) {
            Image(systemName: symbol)
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .frame(width: 17, height: 17)
                .background(Color.primary.opacity(pulse ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 3))
            Text(pending.name)
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 8)
            bar.frame(width: 70)
            Text(pending.label)
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .frame(height: 22)
        .opacity(0.8)
    }

    /// Thin bar: fills with the download, or slides back and forth while converting.
    private var bar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.primary.opacity(0.08))
                if let fraction = pending.fraction {
                    Capsule().fill(Color.accentColor.opacity(0.7))
                        .frame(width: max(4, geo.size.width * fraction))
                        .animation(.easeOut(duration: 0.3), value: fraction)
                } else {
                    Capsule().fill(Color.accentColor.opacity(0.5))
                        .frame(width: geo.size.width * 0.3)
                        .offset(x: pulse ? geo.size.width * 0.7 : 0)
                }
            }
        }
        .frame(height: 3)
    }
}

/// "Saved X.mp3 — delete the link?"
struct LinkCleanupPrompt: View {
    @EnvironmentObject var store: Store
    let cleanup: LinkCleanup

    var body: some View {
        ZStack {
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .onTapGesture { store.linkCleanup = nil }
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle")
                    .font(.system(size: 24, weight: .light))
                    .foregroundStyle(.secondary)
                Text("Saved \(cleanup.resultName)")
                    .font(.system(size: 13, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text("Delete the link now that you have the file?")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Button("Keep Link") { store.linkCleanup = nil }
                        .keyboardShortcut(.cancelAction)
                    Button("Delete Link") {
                        store.linkCleanup = nil
                        store.performDelete([.item(cleanup.linkID)], keepFolderContents: true)
                    }
                    .keyboardShortcut(.defaultAction)
                }
                .controlSize(.large)
                .padding(.top, 4)
            }
            .padding(18)
            .frame(width: 280)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(.regularMaterial)
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
                    .shadow(color: .black.opacity(0.15), radius: 10, y: 4)
            )
        }
    }
}

/// Settings → Tools: what's built in, and updating the downloader (websites change, yt-dlp keeps up).
struct ToolsSettings: View {
    @State private var version = "…"
    @State private var updating = false
    @State private var message: String?

    var body: some View {
        Section {
            LabeledContent("Downloader (yt-dlp)", value: version)
            HStack {
                if let message { Text(message).foregroundStyle(.secondary).lineLimit(2) }
                Spacer()
                Button(updating ? "Updating…" : "Update Downloader") { update() }
                    .disabled(updating)
            }
        } header: {
            Label("Tools", systemImage: "wrench.and.screwdriver")
        } footer: {
            Text("Built into Swiss: MP4 and sound conversion use the Mac's own media tools, MP3s are made by LAME (0.3 MB), links are fetched by yt-dlp. If a link stops downloading, update the downloader.")
                .foregroundStyle(.secondary)
            .settingsFooter()
        }
        .task { await loadVersion() }
    }

    private func loadVersion() async {
        guard let ytdlp = Converter.ytdlp else { version = "missing"; return }
        let result = await Task.detached { Converter.run(ytdlp, ["--version"]) }.value
        version = result.ok ? result.output.trimmingCharacters(in: .whitespacesAndNewlines) : "unknown"
    }

    private func update() {
        guard let ytdlp = Converter.prepareYtdlpForUpdate() else { return }
        updating = true
        message = nil
        Task {
            let result = await Task.detached { Converter.run(ytdlp, ["-U"]) }.value
            updating = false
            let last = result.output.split(whereSeparator: \.isNewline).last.map(String.init) ?? ""
            message = result.ok ? (last.isEmpty ? "Up to date" : last) : "Couldn't update: \(last)"
            await loadVersion()
        }
    }
}
