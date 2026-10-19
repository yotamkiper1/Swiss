import AppKit
func poster(_ name: String, _ top: NSColor, _ bottom: NSColor, _ word: String, _ shape: Int) {
    let w = 1200, h = 1600
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGradient(starting: top, ending: bottom)!.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
    NSColor.white.withAlphaComponent(0.92).setFill()
    switch shape {
    case 0: NSBezierPath(ovalIn: NSRect(x: 220, y: 560, width: 760, height: 760)).fill()
    case 1: NSBezierPath(rect: NSRect(x: 160, y: 420, width: 880, height: 880)).fill(); NSColor.black.withAlphaComponent(0.85).setFill(); NSBezierPath(ovalIn: NSRect(x: 560, y: 820, width: 400, height: 400)).fill()
    case 2: let p = NSBezierPath(); p.move(to: NSPoint(x: 600, y: 1340)); p.line(to: NSPoint(x: 1040, y: 480)); p.line(to: NSPoint(x: 160, y: 480)); p.close(); p.fill()
    default: for i in 0..<5 { NSBezierPath(rect: NSRect(x: 160 + i*190, y: 460, width: 130, height: 300 + i*140)).fill() }
    }
    let para = NSMutableParagraphStyle(); para.alignment = .left
    (word as NSString).draw(in: NSRect(x: 90, y: 90, width: 1020, height: 260), withAttributes: [.font: NSFont.systemFont(ofSize: 150, weight: .heavy), .foregroundColor: NSColor.white, .paragraphStyle: para, .kern: -4])
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .jpeg, properties: [.compressionFactor: 0.9])!.write(to: URL(fileURLWithPath: "demo/\(name).jpg"))
}
poster("Poster draft — orange", NSColor(red: 0.98, green: 0.55, blue: 0.20, alpha: 1), NSColor(red: 0.86, green: 0.22, blue: 0.20, alpha: 1), "Grid", 0)
poster("Poster draft — blue", NSColor(red: 0.20, green: 0.45, blue: 0.95, alpha: 1), NSColor(red: 0.08, green: 0.14, blue: 0.45, alpha: 1), "Form", 1)
poster("Color study", NSColor(red: 0.95, green: 0.80, blue: 0.30, alpha: 1), NSColor(red: 0.90, green: 0.45, blue: 0.30, alpha: 1), "Tone", 2)
poster("Green mood", NSColor(red: 0.45, green: 0.80, blue: 0.55, alpha: 1), NSColor(red: 0.10, green: 0.35, blue: 0.30, alpha: 1), "Calm", 3)
poster("Sonoma reference", NSColor(red: 0.55, green: 0.40, blue: 0.85, alpha: 1), NSColor(red: 0.95, green: 0.50, blue: 0.65, alpha: 1), "Soft", 0)
