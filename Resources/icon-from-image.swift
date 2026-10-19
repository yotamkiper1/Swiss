// Makes AppIcon.icns from a square picture (Resources/AppIcon-source.png): sized and rounded like a macOS icon
// (824 of 1024 points, with a soft shadow), its corners cut clean.
// Run: swift Resources/icon-from-image.swift Resources/AppIcon-source.png Resources/AppIcon.icns
import AppKit

let args = CommandLine.arguments
guard args.count == 3, let source = NSImage(contentsOfFile: args[1]) else { print("usage: source.png out.icns"); exit(1) }
let fm = FileManager.default
let set = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("Swiss-\(UUID().uuidString).iconset")
try fm.createDirectory(at: set, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let s = CGFloat(px) / 1024
    let tile = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 18 * s
    shadow.shadowOffset = NSSize(width: 0, height: -8 * s)
    shadow.set()
    NSColor(red: 0.953, green: 0.949, blue: 0.937, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    shape.addClip()
    // The picture's own tile runs to its edges; a hair bigger so no light rim shows at the corners.
    source.draw(in: tile.insetBy(dx: -6 * s, dy: -6 * s), from: .zero, operation: .sourceOver, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

for size in [16, 32, 128, 256, 512] {
    try render(size).write(to: set.appendingPathComponent("icon_\(size)x\(size).png"))
    try render(size * 2).write(to: set.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let task = Process()
task.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
task.arguments = ["-c", "icns", set.path, "-o", args[2]]
try task.run(); task.waitUntilExit()
try? fm.removeItem(at: set)
try render(1024).write(to: URL(fileURLWithPath: args[2]).deletingPathExtension().appendingPathExtension("png"))
print(task.terminationStatus == 0 ? "made \(args[2])" : "iconutil failed")
