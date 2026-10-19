import AVFoundation
import AppKit
let a = AVURLAsset(url: URL(fileURLWithPath: CommandLine.arguments[1]))
let g = AVAssetImageGenerator(asset: a); g.requestedTimeToleranceBefore = .zero; g.requestedTimeToleranceAfter = .zero
for (i, t) in CommandLine.arguments.dropFirst(3).enumerated() {
    let img = try g.copyCGImage(at: CMTime(seconds: Double(t)!, preferredTimescale: 600), actualTime: nil)
    try NSBitmapImageRep(cgImage: img).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(CommandLine.arguments[2])\(i).png"))
}
