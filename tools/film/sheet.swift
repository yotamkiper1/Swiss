import AppKit
let args = Array(CommandLine.arguments.dropFirst())
let out = args[0]; let files = Array(args.dropFirst())
let cols = 2, rows = (files.count + 1) / 2, tw = 960, th = 540
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: cols * tw, pixelsHigh: rows * th, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
for (i, f) in files.enumerated() {
    guard let img = NSImage(contentsOfFile: f) else { continue }
    img.draw(in: NSRect(x: (i % cols) * tw, y: (rows - 1 - i / cols) * th, width: tw, height: th))
}
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
