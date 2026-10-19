import AppKit
import AVFoundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers

// MARK: - Changing a file's format

/// "Convert" in the right-click menu: pictures to JPG / PNG / HEIC / TIFF / PDF (iPhone HEIC photos included) or
/// smaller; videos to MP4 / MOV / M4V, smaller (1080p, 720p) or as HEVC (same look, smaller file); sound to M4A (and
/// MP3); documents (Word, RTF, text, web pages) to PDF. The original is never changed — the result is a new file
/// next to it. Uses only the Mac's own frameworks (video on its hardware encoders), one heavy job at a time.
struct Conversion: Identifiable, Hashable {
    enum Kind: Hashable {
        case image(UTType, maxPixels: Int?)
        case imageToPDF
        case video(preset: String, type: AVFileType)
        case audio(preset: String, type: AVFileType)
        case documentToPDF
    }
    let id: String
    let title: String
    let ext: String
    let kind: Kind
    /// Added to the name ("photo smaller.jpg") when the format stays the same.
    var suffix: String = ""
}

enum FormatConverter {
    static let imageTypes: [(String, UTType)] = [("jpg", .jpeg), ("png", .png), ("heic", .heic), ("tiff", .tiff)]
    static let documentExtensions: Set<String> = ["doc", "docx", "rtf", "rtfd", "txt", "md", "odt", "html", "htm", "webarchive"]

    /// What this file can become.
    static func conversions(for url: URL) -> [Conversion] {
        let ext = url.pathExtension.lowercased()
        let type = UTType(filenameExtension: ext)
        var list: [Conversion] = []
        if type?.conforms(to: .image) == true, ext != "svg", ext != "pdf" {
            for (target, uti) in imageTypes where !(target == ext || (target == "jpg" && ext == "jpeg") || (target == "tiff" && ext == "tif")) {
                list.append(Conversion(id: "img-" + target, title: target.uppercased(), ext: target, kind: .image(uti, maxPixels: nil)))
            }
            list.append(Conversion(id: "img-pdf", title: "PDF", ext: "pdf", kind: .imageToPDF))
            let same = imageTypes.first { $0.0 == ext || ($0.0 == "jpg" && ext == "jpeg") }
            let (sameExt, sameType) = same ?? ("jpg", .jpeg)
            list.append(Conversion(id: "img-2048", title: "Smaller (2048 px)", ext: sameExt, kind: .image(sameType, maxPixels: 2048), suffix: " 2048"))
            list.append(Conversion(id: "img-1024", title: "Smaller (1024 px)", ext: sameExt, kind: .image(sameType, maxPixels: 1024), suffix: " 1024"))
        } else if type?.conforms(to: .movie) == true || Converter.videoExtensions.contains(ext) {
            if ext != "mp4" { list.append(Conversion(id: "vid-mp4", title: "MP4", ext: "mp4", kind: .video(preset: AVAssetExportPresetHighestQuality, type: .mp4))) }
            if ext != "mov" { list.append(Conversion(id: "vid-mov", title: "MOV", ext: "mov", kind: .video(preset: AVAssetExportPresetHighestQuality, type: .mov))) }
            if ext != "m4v" { list.append(Conversion(id: "vid-m4v", title: "M4V", ext: "m4v", kind: .video(preset: AVAssetExportPresetHighestQuality, type: .m4v))) }
            list.append(Conversion(id: "vid-1080", title: "Smaller (1080p)", ext: "mp4", kind: .video(preset: AVAssetExportPreset1920x1080, type: .mp4), suffix: " 1080p"))
            list.append(Conversion(id: "vid-720", title: "Smaller (720p)", ext: "mp4", kind: .video(preset: AVAssetExportPreset1280x720, type: .mp4), suffix: " 720p"))
            list.append(Conversion(id: "vid-hevc", title: "Smaller file (HEVC)", ext: "mov", kind: .video(preset: AVAssetExportPresetHEVCHighestQuality, type: .mov), suffix: " HEVC"))
            list.append(Conversion(id: "aud-m4a", title: "Sound only (M4A)", ext: "m4a", kind: .audio(preset: AVAssetExportPresetAppleM4A, type: .m4a)))
        } else if type?.conforms(to: .audio) == true || Converter.audioExtensions.contains(ext) {
            if ext != "m4a" { list.append(Conversion(id: "aud-m4a", title: "M4A", ext: "m4a", kind: .audio(preset: AVAssetExportPresetAppleM4A, type: .m4a))) }
        } else if documentExtensions.contains(ext) {
            list.append(Conversion(id: "doc-pdf", title: "PDF", ext: "pdf", kind: .documentToPDF))
        }
        return list
    }

    /// The new file's place: next to `input` (or in `folder`), never over anything.
    static func output(for input: URL, _ conversion: Conversion, in folder: URL? = nil) -> URL {
        let dir = folder ?? input.deletingLastPathComponent()
        let stem = input.deletingPathExtension().lastPathComponent + conversion.suffix
        var url = dir.appendingPathComponent(stem + "." + conversion.ext)
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = dir.appendingPathComponent("\(stem) \(n).\(conversion.ext)")
            n += 1
        }
        return url
    }

    static func run(_ conversion: Conversion, input: URL, output: URL) async throws {
        try FileManager.default.createDirectory(at: output.deletingLastPathComponent(), withIntermediateDirectories: true)
        switch conversion.kind {
        case .image(let type, let maxPixels):
            try image(input, to: output, type: type, maxPixels: maxPixels)
        case .imageToPDF:
            try imagesToPDF([input], output: output)
        case .video(let preset, let type), .audio(let preset, let type):
            try await HeavyJobs.conversions.run { try await export(input, preset: preset, type: type, output: output) }
        case .documentToPDF:
            try await MainActor.run { try documentToPDF(input, output: output) }
        }
        guard FileManager.default.fileExists(atPath: output.path) else { throw ConvertError.failed("Nothing was made") }
    }

    // MARK: Pictures

    /// Decodes only as much as needed (big photos aren't read whole when made smaller), keeps the photo's
    /// orientation and colors, and its details (date, camera) where the format allows.
    static func image(_ input: URL, to output: URL, type: UTType, maxPixels: Int?) throws {
        guard let source = CGImageSourceCreateWithURL(input as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) else {
            throw ConvertError.unreadable(input.pathExtension)
        }
        guard let dest = CGImageDestinationCreateWithURL(output as CFURL, type.identifier as CFString, 1, nil) else {
            throw ConvertError.failed("This Mac can't write \(type.preferredFilenameExtension?.uppercased() ?? "that format")")
        }
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        var options: [CFString: Any] = [kCGImageDestinationLossyCompressionQuality: 0.88]
        if let maxPixels {
            let thumb: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true,
                                          kCGImageSourceThumbnailMaxPixelSize: maxPixels]
            guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, thumb as CFDictionary) else { throw ConvertError.unreadable(input.pathExtension) }
            var meta = properties
            meta[kCGImagePropertyOrientation] = 1 // already turned the right way
            options.merge(meta) { a, _ in a }
            CGImageDestinationAddImage(dest, cg, options as CFDictionary)
        } else {
            options.merge(properties) { a, _ in a }
            CGImageDestinationAddImageFromSource(dest, source, 0, options as CFDictionary)
        }
        guard CGImageDestinationFinalize(dest) else { throw ConvertError.failed("Couldn't write the picture") }
    }

    /// One PDF page per picture.
    static func imagesToPDF(_ inputs: [URL], output: URL) throws {
        let pdf = PDFDocument()
        for (i, url) in inputs.enumerated() {
            guard let image = NSImage(contentsOf: url), let page = PDFPage(image: image) else { continue }
            pdf.insert(page, at: i)
        }
        guard pdf.pageCount > 0, pdf.write(to: output) else { throw ConvertError.failed("Couldn't make the PDF") }
    }

    // MARK: Video and sound

    private static func export(_ input: URL, preset: String, type: AVFileType, output: URL) async throws {
        let asset = AVURLAsset(url: input)
        guard (try? await asset.load(.isReadable)) == true else { throw ConvertError.unreadable(input.pathExtension) }
        if let free = BigFiles.freeSpace(at: output), free < BigFiles.size(of: input) + 500_000_000 {
            throw ConvertError.failed("Not enough disk space")
        }
        guard let session = AVAssetExportSession(asset: asset, presetName: preset), session.supportedFileTypes.contains(type) else {
            throw ConvertError.failed("This video can't be made into that format")
        }
        session.outputURL = output
        session.outputFileType = type
        session.shouldOptimizeForNetworkUse = type == .mp4
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in session.exportAsynchronously { done.resume() } }
        guard session.status == .completed else {
            try? FileManager.default.removeItem(at: output)
            throw ConvertError.failed(session.error?.localizedDescription ?? "The conversion didn't finish")
        }
    }

    // MARK: Documents

    /// Word (.docx/.doc), RTF, text, OpenDocument text, web pages → a paged PDF (A4/Letter, as this Mac prints).
    @MainActor static func documentToPDF(_ input: URL, output: URL) throws {
        let text: NSAttributedString
        do {
            text = try NSAttributedString(url: input, options: [:], documentAttributes: nil)
        } catch {
            throw ConvertError.unreadable(input.pathExtension)
        }
        let info = NSPrintInfo.shared.copy() as! NSPrintInfo
        info.jobDisposition = .save
        info.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = output
        info.horizontalPagination = .fit
        info.verticalPagination = .automatic
        info.topMargin = 54; info.bottomMargin = 54; info.leftMargin = 54; info.rightMargin = 54
        let width = info.paperSize.width - info.leftMargin - info.rightMargin
        let view = NSTextView(frame: NSRect(x: 0, y: 0, width: width, height: 100))
        view.textStorage?.setAttributedString(text)
        view.sizeToFit()
        let op = NSPrintOperation(view: view, printInfo: info)
        op.showsPrintPanel = false
        op.showsProgressPanel = false
        guard op.run() else { throw ConvertError.failed("Couldn't make the PDF") }
    }
}

// MARK: - Running a conversion where the file lives

extension Store {
    /// A card's file converted: the result becomes a new card right next to it.
    func convert(_ itemID: UUID, using conversion: Conversion) {
        guard let item = items.first(where: { $0.id == itemID }), let input = contentURL(item) else { return }
        let place = Place(project: item.projectID, folder: item.folderID)
        let folder = filesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let output = FormatConverter.output(for: input, conversion, in: folder)
        flash("Making \(output.lastPathComponent)…")
        converting.insert(itemID)
        Task.detached {
            do {
                try await FormatConverter.run(conversion, input: input, output: output)
                await MainActor.run {
                    let store = Store.shared
                    store.converting.remove(itemID)
                    store.addFile(output, place: place)
                    store.flash("Made \(output.lastPathComponent)")
                }
            } catch {
                try? FileManager.default.removeItem(at: folder)
                await MainActor.run {
                    Store.shared.converting.remove(itemID)
                    Store.shared.flash("Couldn't convert: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Several pictures (cards) as one PDF, a page each.
    func combineIntoPDF(_ ids: [UUID]) {
        let chosen = ids.compactMap { id in items.first { $0.id == id } }.filter { $0.kind == .image }
        let files = chosen.compactMap(contentURL)
        guard files.count > 1, let first = chosen.first else { return }
        let folder = filesDir.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let output = folder.appendingPathComponent("Pictures (\(files.count) pages).pdf")
        do {
            try FormatConverter.imagesToPDF(files, output: output)
            addFile(output, place: Place(project: first.projectID, folder: first.folderID))
            flash("Made a PDF of \(files.count) pictures")
        } catch {
            flash("Couldn't make the PDF")
        }
    }

    /// A file anywhere (a connected folder, or a Recent file): the result goes next to it.
    func convertFile(_ input: URL, using conversion: Conversion) {
        let output = FormatConverter.output(for: input, conversion)
        flash("Making \(output.lastPathComponent)…")
        Task.detached {
            do {
                try await FormatConverter.run(conversion, input: input, output: output)
                await MainActor.run { Store.shared.flash("Made \(output.lastPathComponent)") }
            } catch {
                try? FileManager.default.removeItem(at: output)
                await MainActor.run { Store.shared.flash("Couldn't convert: \(error.localizedDescription)") }
            }
        }
    }
}
