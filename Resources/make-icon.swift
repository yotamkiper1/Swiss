import AppKit
import CoreGraphics

// Swiss's app icon: a half-open pocket knife — red handle with a cream rivet, a dark blade just coming out — on a white
// tile (the macOS icon shape). Usage: swift make-icon.swift <out.iconset> <preview.png>
func draw(_ size: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    let s = CGFloat(size)
    ctx.translateBy(x: 0, y: s); ctx.scaleBy(x: 1, y: -1) // y down, like the design
    // The white tile: the macOS icon grid (824 of 1024), a soft edge so it shows on white too.
    let tile = CGPath(roundedRect: CGRect(x: s * 100 / 1024, y: s * 100 / 1024, width: s * 824 / 1024, height: s * 824 / 1024),
                      cornerWidth: s * 185 / 1024, cornerHeight: s * 185 / 1024, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: s * 6 / 1024), blur: s * 18 / 1024, color: CGColor(gray: 0, alpha: 0.18))
    ctx.addPath(tile); ctx.setFillColor(CGColor(red: 0.965, green: 0.953, blue: 0.933, alpha: 1)); ctx.fillPath() // warm off-white
    ctx.restoreGState()
    ctx.addPath(tile); ctx.setStrokeColor(CGColor(gray: 0, alpha: 0.06)); ctx.setLineWidth(max(1, s / 512)); ctx.strokePath()
    // The design is drawn on a 100-unit grid (knife spans x 20…82, y 30…74); scaled to sit inside the tile.
    let scale = s * 0.60 / 62
    ctx.translateBy(x: (s - 62 * scale) / 2 - 20 * scale, y: (s - 44 * scale) / 2 - 30 * scale)
    ctx.scaleBy(x: scale, y: scale)
    let blade = CGMutablePath()
    blade.move(to: CGPoint(x: 36, y: 54))
    blade.addLine(to: CGPoint(x: 68, y: 34))
    blade.addQuadCurve(to: CGPoint(x: 82, y: 30), control: CGPoint(x: 80, y: 30))
    blade.addQuadCurve(to: CGPoint(x: 70, y: 46), control: CGPoint(x: 78, y: 40))
    blade.addLine(to: CGPoint(x: 56, y: 56))
    blade.closeSubpath()
    ctx.addPath(blade); ctx.setFillColor(CGColor(red: 0.15, green: 0.137, blue: 0.122, alpha: 1)); ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: CGRect(x: 20, y: 54, width: 62, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil))
    ctx.setFillColor(CGColor(red: 0.62, green: 0.09, blue: 0.08, alpha: 1)); ctx.fillPath()
    ctx.addEllipse(in: CGRect(x: 72 - 3.2, y: 64 - 3.2, width: 6.4, height: 6.4))
    ctx.setFillColor(CGColor(red: 0.957, green: 0.94, blue: 0.918, alpha: 1)); ctx.fillPath()
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let out = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
for (name, px) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128),
                   ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    try! draw(px).write(to: out.appendingPathComponent(name + ".png"))
}
try! draw(1024).write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
