import AppKit
import AVFoundation
import CoreVideo

// MARK: - The Swiss commercial: scenes, camera moves, transitions and encoding.

let root = CommandLine.arguments[1]
let mode = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "render"
let W = 1920.0, H = 1080.0, FPS = 30

// MARK: Basics

func col(_ r: Double, _ g: Double, _ b: Double, _ a: Double = 1) -> CGColor { CGColor(red: r, green: g, blue: b, alpha: a) }
let ink = col(0.082, 0.071, 0.063)
let paper = col(0.965, 0.953, 0.933)
let red = col(0.878, 0.267, 0.227)
let white = col(1, 1, 1)
let gray = col(0.62, 0.60, 0.58)

func clamp(_ x: Double, _ a: Double = 0, _ b: Double = 1) -> Double { min(max(x, a), b) }
func ease(_ x: Double) -> Double { let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2 }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }
func easeOutBack(_ x: Double) -> Double { let t = clamp(x), c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * pow(t - 1, 3) + c1 * pow(t - 1, 2) }
func prog(_ s: Double, _ a: Double, _ d: Double) -> Double { clamp((s - a) / d) }
func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

func loadCG(_ path: String) -> CGImage {
    guard let img = NSImage(contentsOfFile: path), let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("missing \(path)") }
    return cg
}

struct Seeded {
    var s: UInt64
    mutating func next() -> Double {
        s = s &* 6364136223846793005 &+ 1442695040888963407
        return Double((s >> 33) & 0xFFFFFF) / Double(0xFFFFFF)
    }
}

// MARK: Pictures

struct Shot {
    let img: CGImage
    let w: Double, h: Double
    let base: Double
    init(_ file: String, base: Double) {
        img = loadCG("\(root)/shots/\(file).png")
        w = Double(img.width); h = Double(img.height); self.base = base
    }
}

let board = Shot("board", base: 0.5)
let messB = Shot("mess_before", base: 0.5)
let messA = Shot("mess_after", base: 0.5)
let recent = Shot("recent", base: 0.5)
let connected = Shot("connected", base: 0.5)
let popup = Shot("popup", base: 0.95)
let canvasShot = Shot("canvas", base: 0.6)
let iconImg = loadCG("\(root)/icon-preview.png")           // 1024, the tile is 824 of it
let posters: [CGImage] = ["Orange poster", "Blue poster", "Color study", "Green mood", "Soft study"].map { loadCG("\(root)/demo/\($0).jpg") }

// MARK: Drawing helpers (top-left origin)

enum Al { case left, center, right }

@discardableResult
func text(_ c: CGContext, _ s: String, _ x: Double, _ y: Double, size: Double, font: String = "HelveticaNeue-Bold",
          color: CGColor = white, al: Al = .left, kern: Double = 0, alpha: Double = 1) -> Double {
    let f = NSFont(name: font, size: size) ?? NSFont.systemFont(ofSize: size, weight: .bold)
    let ns = NSColor(cgColor: color) ?? .white
    let a = NSAttributedString(string: s, attributes: [.font: f, .foregroundColor: ns.withAlphaComponent(CGFloat(alpha) * ns.alphaComponent), .kern: kern])
    let w = Double(a.size().width)
    let ox = al == .left ? x : al == .center ? x - w / 2 : x - w
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: c, flipped: true)
    a.draw(at: NSPoint(x: ox, y: y))
    NSGraphicsContext.restoreGraphicsState()
    return w
}

func rrect(_ r: CGRect, _ rad: Double) -> CGPath { CGPath(roundedRect: r, cornerWidth: min(rad, r.width / 2), cornerHeight: min(rad, r.height / 2), transform: nil) }

func drawImg(_ c: CGContext, _ img: CGImage, _ r: CGRect, radius: Double = 0, alpha: Double = 1, shadow: Double = 0) {
    guard r.width > 1, r.height > 1 else { return }
    c.saveGState()
    c.setAlpha(CGFloat(alpha))
    if shadow > 0 {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -shadow * 0.45), blur: CGFloat(shadow), color: col(0, 0, 0, 0.5))
        c.setFillColor(col(0, 0, 0))
        c.addPath(rrect(r, radius)); c.fillPath()
        c.restoreGState()
    }
    c.addPath(rrect(r, radius)); c.clip()
    c.translateBy(x: r.minX, y: r.maxY)
    c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    c.restoreGState()
}

/// A picture filling a rounded frame (cropped from the bottom, like a window made taller or wider).
func drawCover(_ c: CGContext, _ img: CGImage, _ r: CGRect, radius: Double = 0, alpha: Double = 1, shadow: Double = 0) {
    guard r.width > 1, r.height > 1 else { return }
    let iw = Double(img.width), ih = Double(img.height)
    let scale = max(r.width / iw, r.height / ih)
    let full = CGRect(x: r.minX + (r.width - iw * scale) / 2, y: r.minY, width: iw * scale, height: ih * scale)
    c.saveGState()
    c.setAlpha(CGFloat(alpha))
    if shadow > 0 {
        c.saveGState()
        c.setShadow(offset: CGSize(width: 0, height: -shadow * 0.45), blur: CGFloat(shadow), color: col(0, 0, 0, 0.5))
        c.setFillColor(col(0, 0, 0)); c.addPath(rrect(r, radius)); c.fillPath()
        c.restoreGState()
    }
    c.addPath(rrect(r, radius)); c.clip()
    c.translateBy(x: full.minX, y: full.maxY); c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: full.width, height: full.height))
    c.restoreGState()
}

func fillRR(_ c: CGContext, _ r: CGRect, _ rad: Double, _ color: CGColor, shadow: Double = 0) {
    c.saveGState()
    if shadow > 0 { c.setShadow(offset: CGSize(width: 0, height: -shadow * 0.4), blur: CGFloat(shadow), color: col(0, 0, 0, 0.35)) }
    c.setFillColor(color)
    c.addPath(rrect(r, rad)); c.fillPath()
    c.restoreGState()
}

func radial(_ c: CGContext, _ center: CGPoint, _ radius: Double, _ inner: CGColor, _ outer: CGColor) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [inner, outer] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(radius), options: [])
}

func linear(_ c: CGContext, _ a: CGPoint, _ b: CGPoint, _ c1: CGColor, _ c2: CGColor) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [c1, c2] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(g, start: a, end: b, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func star(_ c: CGContext, _ p: CGPoint, _ r: Double, _ color: CGColor, alpha: Double, rot: Double = 0) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y); c.rotate(by: CGFloat(rot))
    c.setFillColor(color); c.setAlpha(CGFloat(alpha))
    let path = CGMutablePath()
    for i in 0..<8 {
        let a = Double(i) * Double.pi / 4
        let rr = i % 2 == 0 ? r : r * 0.22
        let pt = CGPoint(x: cos(a) * rr, y: sin(a) * rr)
        if i == 0 { path.move(to: pt) } else { path.addLine(to: pt) }
    }
    path.closeSubpath()
    c.addPath(path); c.fillPath()
    c.restoreGState()
}

func cursor(_ c: CGContext, _ p: CGPoint, scale: Double = 1.6, alpha: Double = 1) {
    c.saveGState()
    c.translateBy(x: p.x, y: p.y); c.scaleBy(x: CGFloat(scale), y: CGFloat(scale)); c.setAlpha(CGFloat(alpha))
    let path = CGMutablePath()
    for (i, pt) in [(0.0, 0.0), (0, 17), (4.2, 13.2), (7, 19.5), (9.8, 18.3), (7.2, 12), (12.5, 12)].enumerated() {
        if i == 0 { path.move(to: CGPoint(x: pt.0, y: pt.1)) } else { path.addLine(to: CGPoint(x: pt.0, y: pt.1)) }
    }
    path.closeSubpath()
    c.setShadow(offset: CGSize(width: 0, height: -2), blur: 4, color: col(0, 0, 0, 0.4))
    c.setFillColor(white); c.addPath(path); c.fillPath()
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.setStrokeColor(col(0, 0, 0)); c.setLineWidth(1.1); c.addPath(path); c.strokePath()
    c.restoreGState()
}

func ripple(_ c: CGContext, _ p: CGPoint, _ t: Double, color: CGColor = white) {
    guard t > 0, t < 1 else { return }
    let r = 10 + 60 * easeOut(t)
    c.saveGState()
    c.setStrokeColor(color); c.setAlpha(CGFloat(1 - t)); c.setLineWidth(CGFloat(5 * (1 - t) + 1))
    c.strokeEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
    c.restoreGState()
}

func chip(_ c: CGContext, _ label: String, _ x: Double, _ y: Double, color: CGColor, t: Double, size: Double = 26, dot: Bool = true) {
    guard t > 0 else { return }
    let k = easeOutBack(t)
    let f = NSFont(name: "HelveticaNeue-Medium", size: size) ?? NSFont.systemFont(ofSize: size)
    let w = Double((label as NSString).size(withAttributes: [.font: f]).width) + size * (dot ? 2.4 : 1.6)
    let h = size * 1.9
    c.saveGState()
    c.translateBy(x: x + w / 2, y: y + h / 2); c.scaleBy(x: CGFloat(k), y: CGFloat(k)); c.translateBy(x: -(x + w / 2), y: -(y + h / 2))
    c.setAlpha(CGFloat(clamp(t * 3)))
    fillRR(c, CGRect(x: x, y: y, width: w, height: h), h / 2, col(1, 1, 1, 0.1), shadow: 12)
    c.setStrokeColor(col(1, 1, 1, 0.22)); c.setLineWidth(1.5); c.addPath(rrect(CGRect(x: x, y: y, width: w, height: h), h / 2)); c.strokePath()
    if dot {
        c.setFillColor(color); c.fillEllipse(in: CGRect(x: x + size * 0.7, y: y + h / 2 - size * 0.23, width: size * 0.46, height: size * 0.46))
    }
    text(c, label, x + size * (dot ? 1.5 : 0.8), y + h / 2 - size * 0.6, size: size, font: "HelveticaNeue-Medium", color: white)
    c.restoreGState()
}

func keycap(_ c: CGContext, _ label: String, _ x: Double, _ y: Double, t: Double, size: Double = 40) {
    guard t > 0 else { return }
    let k = easeOutBack(t)
    let w = max(size * 1.5, Double(label.count) * size * 0.8), h = size * 1.5
    c.saveGState()
    c.translateBy(x: x + w / 2, y: y + h / 2); c.scaleBy(x: CGFloat(k), y: CGFloat(k)); c.translateBy(x: -(x + w / 2), y: -(y + h / 2))
    fillRR(c, CGRect(x: x, y: y + 6, width: w, height: h), 14, col(0.55, 0.53, 0.5))
    fillRR(c, CGRect(x: x, y: y, width: w, height: h), 14, col(0.97, 0.96, 0.94), shadow: 10)
    text(c, label, x + w / 2, y + h / 2 - size * 0.55, size: size, font: "HelveticaNeue-Medium", color: ink, al: .center)
    c.restoreGState()
}

// MARK: Backgrounds

func darkBG(_ c: CGContext, _ s: Double) {
    linear(c, CGPoint(x: 0, y: 0), CGPoint(x: W, y: H), col(0.075, 0.066, 0.06), col(0.16, 0.13, 0.115))
    let drift = sin(s * 0.5) * 80
    radial(c, CGPoint(x: 1500 + drift, y: 150), 900, col(0.88, 0.27, 0.23, 0.2), col(0.88, 0.27, 0.23, 0))
    radial(c, CGPoint(x: 200, y: 950 - drift), 700, col(0.3, 0.45, 0.85, 0.09), col(0.3, 0.45, 0.85, 0))
    c.setStrokeColor(col(1, 1, 1, 0.035)); c.setLineWidth(1)
    for i in 0...12 { let x = 160.0 * Double(i); c.move(to: CGPoint(x: x, y: 0)); c.addLine(to: CGPoint(x: x, y: H)); c.strokePath() }
}

func paperBG(_ c: CGContext) {
    c.setFillColor(paper); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
}

// MARK: Camera

struct Cam { var z: Double; var fx: Double; var fy: Double; var cx: Double; var cy: Double }

func cam(_ keys: [(Double, Cam)], _ s: Double) -> Cam {
    if s <= keys[0].0 { return keys[0].1 }
    for i in 1..<keys.count where s <= keys[i].0 {
        let a = keys[i - 1], b = keys[i]
        let t = ease((s - a.0) / (b.0 - a.0))
        return Cam(z: lerp(a.1.z, b.1.z, t), fx: lerp(a.1.fx, b.1.fx, t), fy: lerp(a.1.fy, b.1.fy, t), cx: lerp(a.1.cx, b.1.cx, t), cy: lerp(a.1.cy, b.1.cy, t))
    }
    return keys.last!.1
}

func place(_ shot: Shot, _ cm: Cam) -> CGRect {
    let sc = shot.base * cm.z
    return CGRect(x: cm.cx - cm.fx * sc, y: cm.cy - cm.fy * sc, width: shot.w * sc, height: shot.h * sc)
}

func toScreen(_ shot: Shot, _ cm: Cam, _ p: CGPoint) -> CGPoint {
    let sc = shot.base * cm.z
    return CGPoint(x: cm.cx + (p.x - cm.fx) * sc, y: cm.cy + (p.y - cm.fy) * sc)
}

func screenRect(_ shot: Shot, _ cm: Cam, _ r: CGRect) -> CGRect {
    let a = toScreen(shot, cm, r.origin), b = toScreen(shot, cm, CGPoint(x: r.maxX, y: r.maxY))
    return CGRect(x: a.x, y: a.y, width: b.x - a.x, height: b.y - a.y)
}

func drawShot(_ c: CGContext, _ shot: Shot, _ cm: Cam, alpha: Double = 1, radius: Double = 22) {
    let r = place(shot, cm)
    drawImg(c, shot.img, r, radius: radius * shot.base * cm.z, alpha: alpha, shadow: 70 * cm.z)
}

/// A glowing outline around part of a picture, with a label.
func ring(_ c: CGContext, _ r: CGRect, t: Double, time: Double, label: String? = nil, labelBelow: Bool = false) {
    guard t > 0 else { return }
    let pulse = 0.5 + 0.5 * sin(time * 5)
    let grow = 10 + 5 * pulse
    let rr = r.insetBy(dx: -grow, dy: -grow)
    c.saveGState()
    c.setAlpha(CGFloat(clamp(t * 2)))
    c.setStrokeColor(red); c.setLineWidth(5)
    c.setShadow(offset: .zero, blur: 24, color: red)
    let reveal = easeOut(t)
    c.addPath(rrect(rr.insetBy(dx: (1 - reveal) * 30, dy: (1 - reveal) * 30), 16)); c.strokePath()
    c.restoreGState()
    if let label {
        let y = labelBelow ? rr.maxY + 14 : rr.minY - 56
        chip(c, label, rr.minX, y, color: red, t: prog(t, 0.2, 0.8), size: 24)
    }
}

// MARK: Captions (left column)

func caption(_ c: CGContext, _ s: Double, label: String, lines: [String], sub: String, fade: Double = 1, x: Double = 120, y: Double = 300) {
    let a = prog(s, 0.2, 0.5)
    if fade <= 0 { return }
    text(c, label, x - (1 - easeOut(a)) * 40, y, size: 24, font: "HelveticaNeue-Bold", color: red, kern: 5, alpha: easeOut(a) * fade)
    for (i, line) in lines.enumerated() {
        let t = prog(s, 0.35 + Double(i) * 0.14, 0.6)
        let yy = y + 50 + Double(i) * 104
        c.saveGState()
        c.clip(to: CGRect(x: 0, y: yy - 6, width: 800, height: 112))
        text(c, line, x, yy + (1 - easeOut(t)) * 110, size: 94, color: white, kern: -2, alpha: fade)
        c.restoreGState()
    }
    let st = prog(s, 0.9 + Double(lines.count) * 0.1, 0.6)
    let ySub = y + 50 + Double(lines.count) * 104 + 20
    var yy = ySub
    for part in sub.components(separatedBy: "\n") {
        text(c, part, x, yy + (1 - easeOut(st)) * 20, size: 32, font: "HelveticaNeue-Light", color: col(0.82, 0.80, 0.78), alpha: easeOut(st) * fade)
        yy += 44
    }
}

// MARK: Scenes

let iconTile = 824.0 / 1024.0
/// CGContext.draw in a flipped context would mirror it: this draws upright.
func drawIconUpright(_ c: CGContext, center: CGPoint, tile: Double, alpha: Double = 1) {
    let size = tile / iconTile
    drawImg(c, iconImg, CGRect(x: center.x - size / 2, y: center.y - size / 2, width: size, height: size), alpha: alpha)
}

func sceneIntro(_ c: CGContext, _ s: Double) {
    paperBG(c)
    radial(c, CGPoint(x: 960, y: 540), 900, col(0.878, 0.267, 0.227, 0.08), col(0.878, 0.267, 0.227, 0))
    let pop = easeOutBack(prog(s, 0.25, 0.8))
    let slide = ease(prog(s, 1.7, 0.9))
    let iconX = lerp(960, 640, slide)
    // Pulse ring when it lands.
    let ringT = prog(s, 0.95, 0.9)
    if ringT > 0 && ringT < 1 {
        c.saveGState(); c.setStrokeColor(red); c.setAlpha(CGFloat(0.5 * (1 - ringT))); c.setLineWidth(6)
        let r = 150 + 380 * easeOut(ringT)
        c.strokeEllipse(in: CGRect(x: 960 - r, y: 540 - r, width: r * 2, height: r * 2)); c.restoreGState()
    }
    if s > 0.25 {
        let tile = 330 * pop
        c.saveGState()
        drawIconUpright(c, center: CGPoint(x: iconX, y: 540 + (1 - pop) * -30), tile: tile, alpha: clamp(pop * 2))
        c.restoreGState()
    }
    // Wordmark, revealed from behind the icon.
    let reveal = easeOut(prog(s, 2.0, 0.9))
    if reveal > 0 {
        c.saveGState()
        c.clip(to: CGRect(x: 820, y: 300, width: 1100 * reveal + 1, height: 420))
        text(c, "Swiss", 820 + (1 - reveal) * -120, 395, size: 230, color: ink, kern: -6)
        c.restoreGState()
    }
    let tag = prog(s, 3.1, 0.7)
    if tag > 0 {
        text(c, "A pocket knife for your ideas.", 832, 650 + (1 - easeOut(tag)) * 20, size: 44, font: "HelveticaNeue-Light", color: col(0.35, 0.33, 0.31), alpha: easeOut(tag))
        c.setFillColor(red); c.fill(CGRect(x: 832, y: 628, width: 160 * easeOut(tag), height: 5))
    }
}

struct Card { var kind: Int; var x, y, w, h, rot, spin, ax, ay, fx, fy, ph: Double; var poster: Int }

func makeCards() -> [Card] {
    var r = Seeded(s: 42)
    return (0..<34).map { i in
        let w = 150 + r.next() * 120
        return Card(kind: i % 4, x: r.next() * W, y: r.next() * H, w: w, h: w * (i % 4 == 0 ? 1.3 : 0.8), rot: (r.next() - 0.5) * 0.9, spin: (r.next() - 0.5) * 0.25,
                    ax: 40 + r.next() * 90, ay: 30 + r.next() * 70, fx: 0.3 + r.next() * 0.5, fy: 0.3 + r.next() * 0.5, ph: r.next() * 6, poster: i % posters.count)
    }
}
let cards = makeCards()

func drawCard(_ c: CGContext, _ k: Card) {
    let r = CGRect(x: -k.w / 2, y: -k.h / 2, width: k.w, height: k.h)
    switch k.kind {
    case 0:
        drawImg(c, posters[k.poster], r, radius: 10, shadow: 24)
    case 1:
        fillRR(c, r, 14, col(0.96, 0.96, 0.97), shadow: 24)
        fillRR(c, CGRect(x: r.minX + 18, y: r.minY + 18, width: 34, height: 34), 17, col(0.2, 0.62, 0.45))
        fillRR(c, CGRect(x: r.minX + 62, y: r.minY + 20, width: r.width - 90, height: 12), 6, col(0.3, 0.3, 0.32))
        fillRR(c, CGRect(x: r.minX + 62, y: r.minY + 40, width: r.width * 0.4, height: 10), 5, col(0.7, 0.7, 0.72))
    case 2:
        fillRR(c, r, 6, col(0.99, 0.91, 0.55), shadow: 24)
        for i in 0..<3 { fillRR(c, CGRect(x: r.minX + 16, y: r.minY + 22 + Double(i) * 22, width: r.width - 32 - Double(i) * 18, height: 8), 4, col(0.55, 0.45, 0.2, 0.7)) }
    default:
        fillRR(c, r, 10, col(0.88, 0.89, 0.92), shadow: 24)
        let exts = ["PDF", "MOV", "ZIP", "AIFF"]
        text(c, exts[k.poster % 4], 0, -14, size: 30, color: col(0.35, 0.38, 0.5), al: .center)
    }
}

func sceneProblem(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let collapse = ease(prog(s, 6.35, 1.0))
    for k in cards {
        let t = s + k.ph
        let x = k.x + sin(t * k.fx) * k.ax, y = k.y + cos(t * k.fy) * k.ay
        let appear = easeOut(prog(s, -0.4 + (k.ph / 6) * 0.5, 0.6))
        let px = lerp(x, 960, collapse), py = lerp(y, 540, collapse)
        let sc = (0.5 + 0.5 * appear) * (1 - collapse * 0.95)
        c.saveGState()
        c.setAlpha(CGFloat(0.55 * appear * (1 - collapse)))
        c.translateBy(x: px, y: py); c.rotate(by: CGFloat(k.rot + s * k.spin + collapse * 2)); c.scaleBy(x: CGFloat(sc), y: CGFloat(sc))
        drawCard(c, k)
        c.restoreGState()
    }
    // A dark veil behind the words.
    radial(c, CGPoint(x: 760, y: 560), 900, col(0.05, 0.04, 0.04, 0.9), col(0.05, 0.04, 0.04, 0))
    let a = easeOut(prog(s, 0.3, 0.6)) * (1 - collapse)
    text(c, "YOUR IDEAS ARE", 140, 330, size: 26, color: gray, kern: 6, alpha: a)
    let words: [(String, Double, Double, CGColor)] = [("scattered.", 0.5, 2.35, red), ("links.", 2.35, 3.6, white), ("screenshots.", 3.6, 4.9, white), ("files.", 4.9, 7.0, white)]
    for (w, s0, s1, color) in words {
        let tin = easeOut(prog(s, s0, 0.45)), tout = prog(s, s1 - 0.25, 0.25)
        if tin <= 0 || tout >= 1 { continue }
        c.saveGState()
        c.clip(to: CGRect(x: 100, y: 370, width: 1500, height: 300))
        text(c, w, 140, 390 + (1 - tin) * 160 - tout * 160, size: 168, color: color, kern: -4, alpha: (1 - collapse))
        c.restoreGState()
    }
}

func menuBar(_ c: CGContext, iconHighlight: Double) {
    c.saveGState()
    c.setFillColor(col(0.08, 0.07, 0.1, 0.62)); c.fill(CGRect(x: 0, y: 0, width: W, height: 46))
    let items = ["\u{F8FF}", "Finder", "File", "Edit", "View", "Go", "Window", "Help"]
    var x = 26.0
    for (i, it) in items.enumerated() {
        x += text(c, it, x, 9, size: 22, font: i == 1 ? "HelveticaNeue-Bold" : "HelveticaNeue-Medium", color: white) + 34
    }
    // Right side: Swiss, battery, wifi, clock.
    let iconX = 1560.0
    if iconHighlight > 0 { fillRR(c, CGRect(x: iconX - 24, y: 4, width: 48, height: 38), 9, col(1, 1, 1, 0.2 * iconHighlight)) }
    drawImg(c, iconImg, CGRect(x: iconX - 20 * 1.243, y: 23 - 20 * 1.243, width: 40 * 1.243, height: 40 * 1.243))
    text(c, "Mon 19 Oct  9:41", W - 28, 9, size: 22, font: "HelveticaNeue-Medium", color: white, al: .right)
    fillRR(c, CGRect(x: 1668, y: 15, width: 38, height: 18), 5, col(1, 1, 1, 0.85))
    for i in 0..<3 {
        c.setStrokeColor(col(1, 1, 1, 0.9)); c.setLineWidth(3)
        c.addArc(center: CGPoint(x: 1640, y: 33), radius: CGFloat(9 + i * 6), startAngle: -.pi * 0.75, endAngle: -.pi * 0.25, clockwise: false); c.strokePath()
    }
    c.restoreGState()
}

let iconPoint = CGPoint(x: 1560, y: 23)

func sceneMenu(_ c: CGContext, _ s: Double) {
    // A soft wallpaper.
    linear(c, CGPoint(x: 0, y: 0), CGPoint(x: W, y: H), col(0.16, 0.2, 0.42), col(0.75, 0.35, 0.4))
    radial(c, CGPoint(x: 400, y: 900), 800, col(0.95, 0.55, 0.3, 0.55), col(0.95, 0.55, 0.3, 0))
    radial(c, CGPoint(x: 1500, y: 250), 700, col(0.4, 0.5, 0.95, 0.5), col(0.4, 0.5, 0.95, 0))
    let click = 1.7
    menuBar(c, iconHighlight: s > click ? 1 : 0)
    // The pop-up drops from the icon.
    let pt = prog(s, click + 0.25, 0.7)
    let spring = easeOutBack(pt)
    let cm = cam([(0, Cam(z: 1, fx: 300, fy: 400, cx: 1500, cy: 470)), (3.7, Cam(z: 1, fx: 300, fy: 400, cx: 1500, cy: 470)),
                  (5.6, Cam(z: 1.42, fx: 300, fy: 260, cx: 1180, cy: 560))], s)
    if pt > 0 {
        c.saveGState()
        let anchor = CGPoint(x: 1480, y: 60)
        let sc = 0.7 + 0.3 * spring
        c.translateBy(x: anchor.x, y: anchor.y); c.scaleBy(x: CGFloat(sc), y: CGFloat(sc)); c.translateBy(x: -anchor.x, y: -anchor.y)
        c.setAlpha(CGFloat(clamp(pt * 2.5)))
        let r = place(popup, cm)
        drawImg(c, popup.img, r, radius: 16 * cm.z, shadow: 60)
        c.restoreGState()
        if s > 3.8 {
            // Close-up: the tabs and the tools.
            ring(c, screenRect(popup, cm, CGRect(x: 8, y: 12, width: 584, height: 70)), t: prog(s, 3.9, 0.6), time: s, label: "Projects as tabs", labelBelow: true)
        }
    }
    // Cursor travels to the icon and clicks.
    if s < click + 1.2 {
        let m = ease(prog(s, 0.4, 1.2))
        let p = CGPoint(x: lerp(1050, iconPoint.x + 6, m), y: lerp(620, iconPoint.y + 8, m))
        let fade = 1 - prog(s, click + 0.6, 0.5)
        cursor(c, p, alpha: fade)
        ripple(c, iconPoint, prog(s, click, 0.6))
    }
    let fade = 1 - prog(s, 3.8, 0.6)
    caption(c, s - 1.9, label: "01   MENU BAR", lines: ["One click", "away."], sub: "Lives in your menu bar.\nAlways ready.", fade: fade, y: 270)
}

func sceneRecent(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let cm = cam([(0, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)), (2.5, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)),
                  (4.0, Cam(z: 1.85, fx: 1650, fy: 330, cx: 1050, cy: 560))], s)
    let enter = easeOut(prog(s, -0.35, 0.7))
    var cm2 = cm; cm2.cy += (1 - enter) * 60
    drawShot(c, recent, cm2, alpha: enter)
    // Chips: what was just copied.
    let chipsOut = 1 - prog(s, 3.0, 0.4)
    chip(c, "Link copied", 120, 720, color: col(0.36, 0.62, 0.95), t: prog(s, 0.7, 0.4) * chipsOut)
    chip(c, "Screenshot captured", 120, 796, color: col(0.7, 0.5, 0.95), t: prog(s, 1.5, 0.4) * chipsOut)
    chip(c, "Text copied", 120, 872, color: col(0.4, 0.78, 0.5), t: prog(s, 2.3, 0.4) * chipsOut)
    // The row under the pointer shows its Keep button (drawn here, as the app shows it on hover).
    let keep = CGRect(x: 2150, y: 380, width: 195, height: 48)
    let kr = screenRect(recent, cm, keep)
    let rowHi = screenRect(recent, cm, CGRect(x: 360, y: 360, width: 1992, height: 88))
    fillRR(c, rowHi, 14 * recent.base * cm.z, col(0, 0, 0, 0.07 * prog(s, 3.4, 0.4)))
    let kept = prog(s, 4.8, 0.2)
    fillRR(c, kr, 10 * cm.z, kept > 0.5 ? col(0.2, 0.48, 0.96) : col(0.21, 0.46, 0.96, 0.14 * prog(s, 3.4, 0.4)))
    text(c, kept > 0.5 ? "\u{2713} Kept" : "Keep", kr.midX, kr.midY - kr.height * 0.33, size: kr.height * 0.55, font: "HelveticaNeue-Medium",
         color: kept > 0.5 ? white : col(0.2, 0.45, 0.95), al: .center, alpha: prog(s, 3.4, 0.4))
    ring(c, kr, t: prog(s, 4.2, 0.5), time: s, label: "Keep it", labelBelow: true)
    if s > 4.3 && s < 5.3 {
        let m = ease(prog(s, 4.3, 0.5))
        cursor(c, CGPoint(x: lerp(kr.minX - 300, kr.midX, m), y: lerp(kr.midY + 240, kr.midY, m)), alpha: 1 - prog(s, 5.1, 0.2))
    }
    ripple(c, CGPoint(x: kr.midX, y: kr.midY), prog(s, 4.8, 0.6))
    chip(c, "Kept in Poster Series", kr.minX - 520, kr.maxY + 70, color: col(0.4, 0.78, 0.5), t: prog(s, 5.0, 0.4), size: 28)
    caption(c, s, label: "02   RECENT", lines: ["Copy.", "Capture.", "Keep."], sub: "Everything you copy or screenshot\nlands here, ready to keep.", fade: 1 - prog(s, 2.9, 0.5), y: 170)
}

func sceneProjects(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let cm = cam([(0, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)), (1.0, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)),
                  (2.4, Cam(z: 1.7, fx: 230, fy: 330, cx: 760, cy: 540)), (4.2, Cam(z: 1.7, fx: 230, fy: 330, cx: 760, cy: 540)),
                  (5.8, Cam(z: 1.5, fx: 1150, fy: 450, cx: 1000, cy: 540)), (7.2, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570))], s)
    let enter = easeOut(prog(s, -0.35, 0.7))
    var cm2 = cm; cm2.cy += (1 - enter) * 60
    let swap = ease(prog(s, 3.1, 0.35))
    drawShot(c, board, cm2, alpha: enter)
    if swap > 0 { drawShot(c, messB, cm2, alpha: swap) }
    ring(c, screenRect(board, cm, CGRect(x: 30, y: 205, width: 360, height: 260)), t: prog(s, 1.9, 0.5) * (1 - prog(s, 4.0, 0.3)), time: s, label: "Projects", labelBelow: false)
    let target = screenRect(board, cm, CGRect(x: 30, y: 420, width: 360, height: 48))
    if s > 2.4 && s < 3.6 {
        let m = ease(prog(s, 2.4, 0.7))
        cursor(c, CGPoint(x: lerp(target.midX + 260, target.midX, m), y: lerp(target.midY - 160, target.midY, m)), alpha: 1 - prog(s, 3.4, 0.2))
    }
    ripple(c, CGPoint(x: target.midX, y: target.midY), prog(s, 3.1, 0.6))
    caption(c, s, label: "03   PROJECTS", lines: ["Tabs for", "every idea."], sub: "Folders, notes, pictures and links.\nOne calm place.", fade: 1 - prog(s, 1.5, 0.5), y: 250)
}

func sceneWand(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let wand = CGRect(x: 2255, y: 30, width: 105, height: 80)
    let cm = cam([(0, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)), (0.9, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570)),
                  (2.1, Cam(z: 2.3, fx: 2150, fy: 190, cx: 1250, cy: 480)), (3.4, Cam(z: 2.3, fx: 2150, fy: 190, cx: 1250, cy: 480)),
                  (4.6, Cam(z: 1, fx: 1180, fy: 760, cx: 1330, cy: 570))], s)
    let enter = easeOut(prog(s, -0.35, 0.7))
    var cm2 = cm; cm2.cy += (1 - enter) * 60
    drawShot(c, messB, cm2, alpha: enter)
    let swap = ease(prog(s, 2.55, 0.45))
    if swap > 0 { drawShot(c, messA, cm2, alpha: swap) }
    let wr = screenRect(messB, cm, wand)
    ring(c, wr, t: prog(s, 1.5, 0.5) * (1 - prog(s, 2.9, 0.3)), time: s, label: "The magic wand", labelBelow: true)
    if s > 1.6 && s < 3.0 {
        let m = ease(prog(s, 1.6, 0.8))
        cursor(c, CGPoint(x: lerp(wr.midX - 320, wr.midX, m), y: lerp(wr.midY + 220, wr.midY, m)), alpha: 1 - prog(s, 2.7, 0.2))
    }
    ripple(c, CGPoint(x: wr.midX, y: wr.midY), prog(s, 2.4, 0.6))
    // Sparkles.
    if s > 2.4 && s < 4.2 {
        var r = Seeded(s: 7)
        let t = s - 2.4
        for _ in 0..<46 {
            let ang = r.next() * 6.28, spd = 120 + r.next() * 520, life = 0.7 + r.next() * 0.9, sz = 10 + r.next() * 22
            let age = t / life
            if age >= 1 { _ = r.next(); continue }
            let p = CGPoint(x: wr.midX + cos(ang) * spd * t * 0.9, y: wr.midY + sin(ang) * spd * t * 0.9 + 140 * t * t)
            star(c, p, sz * (1 - age * 0.6), r.next() > 0.5 ? white : col(1, 0.8, 0.4), alpha: (1 - age), rot: ang + t * 3)
        }
    }
    let names: [(String, CGColor)] = [("Linker", col(0.35, 0.78, 0.5)), ("PhotoBook", col(0.9, 0.35, 0.3)), ("Notepad", col(0.95, 0.65, 0.25)), ("Files", col(0.6, 0.6, 0.65))]
    for (i, n) in names.enumerated() { chip(c, n.0, 120, 690 + Double(i) * 78, color: n.1, t: prog(s, 4.4 + Double(i) * 0.25, 0.4)) }
    caption(c, s, label: "04   THE WAND", lines: ["One tap.", "No mess."], sub: "Links, pictures, notes and files\nsort themselves into folders.", fade: clamp(1 - prog(s, 0.9, 0.4) + prog(s, 4.4, 0.5)), y: 150)
}

func finderMock(_ c: CGContext, _ r: CGRect, _ s: Double) {
    c.saveGState()
    fillRR(c, r, 18, col(0.95, 0.95, 0.96), shadow: 50)
    for (i, k) in [col(1, 0.37, 0.34), col(1, 0.74, 0.18), col(0.16, 0.8, 0.25)].enumerated() {
        c.setFillColor(k); c.fillEllipse(in: CGRect(x: r.minX + 22 + Double(i) * 28, y: r.minY + 20, width: 16, height: 16))
    }
    text(c, "Client Files", r.midX, r.minY + 14, size: 22, font: "HelveticaNeue-Medium", color: col(0.25, 0.25, 0.28), al: .center)
    let renamed = prog(s, 5.4, 0.6)
    let names = ["Invoices", "Moodboards", renamed > 0.5 ? "Hero board.jpg" : "Brand board.jpg", "Kickoff notes.txt", "Voice memo.aiff"]
    for (i, n) in names.enumerated() {
        let y = r.minY + 62 + Double(i) * 52
        if i == 2 && renamed > 0 { fillRR(c, CGRect(x: r.minX + 14, y: y - 4, width: r.width - 28, height: 44), 8, col(0.25, 0.5, 0.95, 0.18 * (renamed > 0.5 ? 1 : 0.6))) }
        fillRR(c, CGRect(x: r.minX + 28, y: y + 4, width: 28, height: 26), i < 2 ? 6 : 4, i < 2 ? col(0.4, 0.65, 0.95) : col(0.82, 0.83, 0.86))
        text(c, n, r.minX + 72, y + 3, size: 24, font: "HelveticaNeue", color: col(0.15, 0.15, 0.18))
    }
    c.restoreGState()
}

func sceneConnected(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let cm = cam([(0, Cam(z: 1, fx: 1180, fy: 760, cx: 1230, cy: 520)), (1.2, Cam(z: 1, fx: 1180, fy: 760, cx: 1230, cy: 520)),
                  (2.6, Cam(z: 1.75, fx: 260, fy: 540, cx: 900, cy: 520)), (4.0, Cam(z: 1.75, fx: 260, fy: 540, cx: 900, cy: 520)),
                  (5.4, Cam(z: 1.0, fx: 1180, fy: 760, cx: 1000, cy: 500))], s)
    let enter = easeOut(prog(s, -0.35, 0.7))
    var cm2 = cm; cm2.cy += (1 - enter) * 60
    drawShot(c, connected, cm2, alpha: enter)
    ring(c, screenRect(connected, cm, CGRect(x: 30, y: 520, width: 360, height: 60)), t: prog(s, 2.0, 0.5) * (1 - prog(s, 4.2, 0.3)), time: s, label: "Any folder", labelBelow: false)
    // Finder, beside it, in step.
    let fin = easeOutBack(prog(s, 4.2, 0.7))
    if fin > 0 {
        let r = CGRect(x: 1180 + (1 - fin) * 400, y: 330, width: 640, height: 400)
        c.saveGState(); c.setAlpha(CGFloat(clamp(fin * 2)))
        finderMock(c, r, s)
        c.restoreGState()
        // Sync arrows.
        let pulse = 0.5 + 0.5 * sin(s * 6)
        text(c, "\u{21C4}", 1180, 440, size: 84, color: red, al: .center, alpha: fin * (0.6 + 0.4 * pulse))
        if s > 5.6 { chip(c, "Synced with Finder", 1300, 760, color: col(0.4, 0.78, 0.5), t: prog(s, 5.8, 0.4), size: 28) }
    }
    caption(c, s, label: "05   CONNECTED FOLDERS", lines: ["Finder,", "inside Swiss."], sub: "Rename, move, tag and sort.\nFinder follows along.", fade: 1 - prog(s, 1.2, 0.5) + prog(s, 5.6, 0.5) * 0, y: 250)
}

func sceneFrame(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let cm = cam([(0, Cam(z: 1, fx: 680, fy: 723, cx: 1300, cy: 540)), (1.2, Cam(z: 1, fx: 680, fy: 723, cx: 1300, cy: 540)),
                  (2.6, Cam(z: 1.55, fx: 300, fy: 700, cx: 1050, cy: 560)), (5.5, Cam(z: 1.55, fx: 300, fy: 700, cx: 1050, cy: 560)),
                  (7.2, Cam(z: 1.05, fx: 680, fy: 723, cx: 1300, cy: 540))], s)
    let enter = easeOut(prog(s, -0.35, 0.7))
    var cm2 = cm; cm2.cy += (1 - enter) * 60
    drawShot(c, canvasShot, cm2, alpha: enter, radius: 22)
    ring(c, screenRect(canvasShot, cm, CGRect(x: 15, y: 150, width: 420, height: 1100)), t: prog(s, 1.7, 0.5) * (1 - prog(s, 3.4, 0.3)), time: s, label: "Your library", labelBelow: false)
    // A picture dragged in.
    let drag = ease(prog(s, 3.5, 1.4))
    let undone = ease(prog(s, 6.3, 0.5))
    if s > 3.4 && undone < 1 {
        let a = toScreen(canvasShot, cm, CGPoint(x: 160, y: 626))
        let b = toScreen(canvasShot, cm, CGPoint(x: 1130, y: 1130))
        let mid = CGPoint(x: (a.x + b.x) / 2, y: min(a.y, b.y) - 150)
        let u = drag
        let p = CGPoint(x: (1 - u) * (1 - u) * a.x + 2 * (1 - u) * u * mid.x + u * u * b.x, y: (1 - u) * (1 - u) * a.y + 2 * (1 - u) * u * mid.y + u * u * b.y)
        let sc = canvasShot.base * cm.z
        let w = lerp(60, 235 * sc, u), h = lerp(60, 330 * sc, u)
        let land = easeOutBack(prog(s, 4.85, 0.35))
        c.saveGState()
        c.translateBy(x: p.x, y: p.y); c.rotate(by: CGFloat((1 - u) * -0.25))
        let k = (1 - undone * 0.5) * (u >= 1 ? lerp(1.12, 1, land) : 1)
        c.scaleBy(x: CGFloat(k), y: CGFloat(k)); c.setAlpha(CGFloat(1 - undone))
        drawImg(c, posters[3], CGRect(x: -w / 2, y: -h / 2, width: w, height: h), radius: 10, shadow: 40)
        c.restoreGState()
        if s < 4.7 { cursor(c, CGPoint(x: p.x + 16, y: p.y + 20), alpha: 1) }
    }
    if s > 6.1 { keycap(c, "\u{2318}", 120, 640, t: prog(s, 6.1, 0.35)); keycap(c, "Z", 238, 640, t: prog(s, 6.2, 0.35)); chip(c, "Undo anything", 120, 780, color: red, t: prog(s, 6.5, 0.4), size: 28) }
    if s > 1.2 && s < 6.0 {
        chip(c, "Drag it in", 120, 640, color: col(0.36, 0.62, 0.95), t: prog(s, 3.4, 0.4) * (1 - prog(s, 5.8, 0.2)), size: 28)
    }
    caption(c, s, label: "06   THE FRAME", lines: ["A canvas", "above it all."], sub: "Pull anything in from your library.\nMove it, zoom in, undo.", fade: 1 - prog(s, 1.2, 0.5) + prog(s, 6.9, 0.5), y: 190)
}

func sceneSizes(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    // Pop-up → window → full screen, one morphing frame.
    let t1 = ease(prog(s, 1.5, 0.8))      // pop-up → window
    let t2 = ease(prog(s, 3.35, 0.9))              // window → full
    let popRect = CGRect(x: 960 - 190, y: 540 - 253, width: 380, height: 506)
    let winRect = CGRect(x: 960 - 480, y: 290, width: 960, height: 618)
    let fullRect = CGRect(x: 0, y: 0, width: W, height: H)
    func mix(_ a: CGRect, _ b: CGRect, _ t: Double) -> CGRect {
        CGRect(x: lerp(a.minX, b.minX, t), y: lerp(a.minY, b.minY, t), width: lerp(a.width, b.width, t), height: lerp(a.height, b.height, t))
    }
    var r = mix(popRect, winRect, t1)
    r = mix(r, fullRect, t2)
    let enter = easeOut(prog(s, -0.3, 0.6))
    r = r.insetBy(dx: (1 - enter) * 40, dy: (1 - enter) * 40)
    let x = ease(prog(s, 1.5, 0.5))
    if x < 1 { drawCover(c, popup.img, r, radius: 18, alpha: enter * (1 - x), shadow: 60) }
    if x > 0 { drawCover(c, board.img, r, radius: lerp(22, 0, t2), alpha: x, shadow: 80 * (1 - t2)) }
    // Labels.
    let labels = [("Pop-up", 0.6, 1.9), ("Window", 2.0, 3.5), ("Full screen", 3.6, 6.0)]
    for (l, a, b) in labels {
        let t = prog(s, a, 0.4), out = prog(s, b - 0.3, 0.3)
        if t > 0 && out < 1 {
            let a = easeOut(t) * (1 - out)
            fillRR(c, CGRect(x: 960 - 190, y: 950 + (1 - easeOut(t)) * 30, width: 380, height: 78), 39, col(0, 0, 0, 0.55 * a))
            text(c, l.uppercased(), 960, 967 + (1 - easeOut(t)) * 30, size: 36, color: white, al: .center, kern: 8, alpha: a)
        }
    }
    // The green dot.
    let g = prog(s, 2.9, 0.4) * (1 - prog(s, 3.55, 0.25))
    if g > 0 {
        let p = CGPoint(x: winRect.minX + 120, y: winRect.minY + 22)
        ring(c, CGRect(x: p.x - 14, y: p.y - 14, width: 28, height: 28), t: g, time: s)
        if s < 3.5 { cursor(c, CGPoint(x: lerp(p.x + 220, p.x + 4, ease(prog(s, 2.9, 0.5))), y: lerp(p.y + 160, p.y + 6, ease(prog(s, 2.9, 0.5)))), alpha: 1) }
        ripple(c, p, prog(s, 3.35, 0.5))
    }
    let head = 1 - prog(s, 3.4, 0.4)
    if head > 0 {
        text(c, "07   ONE CLICK, THREE SIZES", 120, 70, size: 24, color: red, kern: 5, alpha: head * easeOut(prog(s, 0.2, 0.5)))
        text(c, "Make it yours.", 120, 108, size: 84, color: white, kern: -2, alpha: head * easeOut(prog(s, 0.3, 0.6)))
    }
}

func lockGlyph(_ c: CGContext, _ center: CGPoint, _ size: Double, closed: Double) {
    c.saveGState()
    c.translateBy(x: center.x, y: center.y)
    let w = size, h = size * 0.78
    // Shackle.
    c.setStrokeColor(white); c.setLineWidth(CGFloat(size * 0.13)); c.setLineCap(.round)
    let lift = (1 - closed) * size * 0.18
    c.addArc(center: CGPoint(x: 0, y: -h * 0.18 - lift), radius: CGFloat(size * 0.3), startAngle: .pi, endAngle: 0, clockwise: false)
    c.move(to: CGPoint(x: -size * 0.3, y: -h * 0.18 - lift)); c.addLine(to: CGPoint(x: -size * 0.3, y: -h * 0.02))
    c.move(to: CGPoint(x: size * 0.3, y: -h * 0.18 - lift)); c.addLine(to: CGPoint(x: size * 0.3, y: closed > 0.5 ? -h * 0.02 : -h * 0.18))
    c.strokePath()
    fillRR(c, CGRect(x: -w / 2, y: -h * 0.05, width: w, height: h), size * 0.14, red, shadow: 40)
    c.setFillColor(white); c.fillEllipse(in: CGRect(x: -size * 0.07, y: h * 0.28, width: size * 0.14, height: size * 0.14))
    c.restoreGState()
}

func scenePrivate(_ c: CGContext, _ s: Double) {
    darkBG(c, s)
    let enter = easeOutBack(prog(s, -0.25, 0.7))
    c.saveGState()
    c.translateBy(x: 0, y: (1 - enter) * 40)
    lockGlyph(c, CGPoint(x: 560, y: 540), 280 * enter, closed: prog(s, 2.2, 0.3))
    c.restoreGState()
    let lines: [(String, Double, Bool)] = [("No account.", 0.6, true), ("No cloud.", 1.4, true), ("Stays on your Mac.", 2.2, false)]
    for (i, l) in lines.enumerated() {
        let t = easeOut(prog(s, l.1, 0.5))
        let y = 380 + Double(i) * 130
        let w = text(c, l.0, 860, y + (1 - t) * 30, size: 100, color: l.2 ? col(0.78, 0.76, 0.74) : white, kern: -2, alpha: t)
        if l.2 {
            let st = easeOut(prog(s, l.1 + 0.5, 0.35))
            c.setFillColor(red); c.fill(CGRect(x: 850, y: y + 60, width: (w + 20) * st, height: 7))
        }
    }
}

func sceneOutro(_ c: CGContext, _ s: Double) {
    paperBG(c)
    radial(c, CGPoint(x: 960, y: 480), 1000, col(0.878, 0.267, 0.227, 0.14), col(0.878, 0.267, 0.227, 0))
    let pop = easeOutBack(prog(s, 0.3, 0.9))
    let float = sin(s * 1.6) * 6
    if pop > 0 { drawIconUpright(c, center: CGPoint(x: 960, y: 400 + float), tile: 300 * pop, alpha: clamp(pop * 2)) }
    let t = easeOut(prog(s, 1.3, 0.8))
    text(c, "Swiss", 960, 575 + (1 - t) * 30, size: 190, color: ink, al: .center, kern: -5, alpha: t)
    let t2 = easeOut(prog(s, 2.2, 0.8))
    text(c, "A pocket knife for your ideas.", 960, 800 + (1 - t2) * 20, size: 46, font: "HelveticaNeue-Light", color: col(0.35, 0.33, 0.31), al: .center, alpha: t2)
    let t3 = easeOut(prog(s, 3.4, 0.8))
    text(c, "FOR MACOS", 960, 890, size: 26, color: red, al: .center, kern: 10, alpha: t3)
    // Stars drifting.
    var r = Seeded(s: 11)
    for _ in 0..<14 {
        let x = r.next() * W, y0 = r.next() * H, ph = r.next() * 6, sz = 8 + r.next() * 14
        let a = easeOut(prog(s, 0.8, 1.0)) * (0.35 + 0.35 * sin(s * 2 + ph))
        star(c, CGPoint(x: x, y: y0 + sin(s + ph) * 14), sz, red, alpha: a, rot: s * 0.4 + ph)
    }
    let fade = prog(s, 8.0, 1.1)
    if fade > 0 { c.setFillColor(ink); c.setAlpha(CGFloat(fade)); c.fill(CGRect(x: 0, y: 0, width: W, height: H)); c.setAlpha(1) }
}

typealias SceneFn = (CGContext, Double) -> Void
let scenes: [SceneFn] = [sceneIntro, sceneProblem, sceneMenu, sceneRecent, sceneProjects, sceneWand, sceneConnected, sceneFrame, sceneSizes, scenePrivate, sceneOutro]
let transitions = ["", "wipe", "push", "zoom", "wipe", "zoom", "push", "wipe", "zoom", "flash", "fade"]

// MARK: Frame compositing

func makeContext(_ w: Int, _ h: Int) -> CGContext {
    let c = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    c.translateBy(x: 0, y: CGFloat(h)); c.scaleBy(x: 1, y: -1)
    c.interpolationQuality = .high
    c.setShouldAntialias(true)
    return c
}

func prepare(_ c: CGContext) {
    c.saveGState()
    c.setBlendMode(.copy); c.setFillColor(ink); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    c.restoreGState()
}

let ctxA = makeContext(Int(W), Int(H)), ctxB = makeContext(Int(W), Int(H))
let half = 0.36

func flipDraw(_ c: CGContext, _ img: CGImage) { drawImg(c, img, CGRect(x: 0, y: 0, width: W, height: H)) }

func renderFrame(_ t: Double, into c: CGContext) {
    var idx = 0
    for i in 0..<sceneStarts.count where t >= sceneStarts[i] { idx = i }
    // Near the next boundary: a transition.
    let next = idx + 1
    if next < scenes.count, t > sceneStarts[next] - half {
        let b = sceneStarts[next]
        let p = (t - (b - half)) / (2 * half)
        prepare(ctxA); scenes[idx](ctxA, t - sceneStarts[idx])
        prepare(ctxB); scenes[next](ctxB, t - b)
        let a = ctxA.makeImage()!, bi = ctxB.makeImage()!
        composite(c, a, bi, p, transitions[next])
        return
    }
    if idx > 0, t < sceneStarts[idx] + half {
        let b = sceneStarts[idx]
        let p = (t - (b - half)) / (2 * half)
        prepare(ctxA); scenes[idx - 1](ctxA, t - sceneStarts[idx - 1])
        prepare(ctxB); scenes[idx](ctxB, t - b)
        composite(c, ctxA.makeImage()!, ctxB.makeImage()!, p, transitions[idx])
        return
    }
    prepare(c)
    scenes[idx](c, t - sceneStarts[idx])
}

func composite(_ c: CGContext, _ a: CGImage, _ b: CGImage, _ p: Double, _ kind: String) {
    let e = ease(p)
    c.saveGState()
    switch kind {
    case "wipe":
        flipDraw(c, a)
        let edge = -240 + (W + 480) * e
        let clip = CGMutablePath()
        clip.move(to: CGPoint(x: 0, y: 0)); clip.addLine(to: CGPoint(x: edge + 160, y: 0)); clip.addLine(to: CGPoint(x: edge - 160, y: H)); clip.addLine(to: CGPoint(x: 0, y: H)); clip.closeSubpath()
        c.saveGState(); c.addPath(clip); c.clip(); flipDraw(c, b); c.restoreGState()
        let band = CGMutablePath()
        band.move(to: CGPoint(x: edge + 160, y: 0)); band.addLine(to: CGPoint(x: edge + 160 + 90, y: 0)); band.addLine(to: CGPoint(x: edge - 160 + 90, y: H)); band.addLine(to: CGPoint(x: edge - 160, y: H)); band.closeSubpath()
        c.setFillColor(red); c.addPath(band); c.fillPath()
    case "push":
        c.saveGState(); c.translateBy(x: CGFloat(-W * e), y: 0); flipDraw(c, a); c.restoreGState()
        c.saveGState(); c.translateBy(x: CGFloat(W * (1 - e)), y: 0); flipDraw(c, b); c.restoreGState()
    case "zoom":
        c.saveGState()
        let sa = 1 + 0.6 * e
        c.translateBy(x: CGFloat(W / 2), y: CGFloat(H / 2)); c.scaleBy(x: CGFloat(sa), y: CGFloat(sa)); c.translateBy(x: CGFloat(-W / 2), y: CGFloat(-H / 2))
        c.setAlpha(CGFloat(1 - e)); flipDraw(c, a); c.restoreGState()
        c.saveGState()
        let sb = 0.82 + 0.18 * e
        c.translateBy(x: CGFloat(W / 2), y: CGFloat(H / 2)); c.scaleBy(x: CGFloat(sb), y: CGFloat(sb)); c.translateBy(x: CGFloat(-W / 2), y: CGFloat(-H / 2))
        c.setAlpha(CGFloat(e)); flipDraw(c, b); c.restoreGState()
    case "flash":
        flipDraw(c, e < 0.5 ? a : b)
        c.setFillColor(white); c.setAlpha(CGFloat(sin(Double.pi * p))); c.fill(CGRect(x: 0, y: 0, width: W, height: H))
    default:
        flipDraw(c, a)
        c.setAlpha(CGFloat(e)); flipDraw(c, b)
    }
    c.restoreGState()
}

// MARK: Run

func savePNG(_ c: CGContext, to path: String) {
    guard let img = c.makeImage() else { return }
    // The context is flipped for drawing; the image itself is upright.
    let rep = NSBitmapImageRep(cgImage: img)
    try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
}

if mode == "preview" {
    try? FileManager.default.createDirectory(atPath: "\(root)/preview", withIntermediateDirectories: true)
    let main = makeContext(Int(W), Int(H))
    for a in CommandLine.arguments.dropFirst(3) {
        guard let t = Double(a) else { continue }
        renderFrame(t, into: main)
        savePNG(main, to: "\(root)/preview/t\(String(format: "%05.1f", t)).png")
    }
    exit(0)
}

if mode == "audio" {
    let bus = buildAudio(root: root)
    writeWav(bus, to: "\(root)/out/audio.wav")
    exit(0)
}

// Full render.
try? FileManager.default.createDirectory(atPath: "\(root)/out", withIntermediateDirectories: true)
let videoURL = URL(fileURLWithPath: "\(root)/out/video.mp4")
try? FileManager.default.removeItem(at: videoURL)
let writer = try AVAssetWriter(outputURL: videoURL, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: Int(W), AVVideoHeightKey: Int(H),
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 9_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel, AVVideoMaxKeyFrameIntervalKey: 60],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: Int(W), kCVPixelBufferHeightKey as String: Int(H),
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)
let frames = Int(TOTAL * Double(FPS))
let main = makeContext(Int(W), Int(H))
for f in 0..<frames {
    while !input.isReadyForMoreMediaData { usleep(1000) }
    renderFrame(Double(f) / Double(FPS), into: main)
    var pb: CVPixelBuffer?
    CVPixelBufferCreate(nil, Int(W), Int(H), kCVPixelFormatType_32BGRA, nil, &pb)
    guard let buffer = pb else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let dst = CVPixelBufferGetBaseAddress(buffer)!, rowBytes = CVPixelBufferGetBytesPerRow(buffer)
    let src = main.data!, srcRow = main.bytesPerRow
    for y in 0..<Int(H) { memcpy(dst + y * rowBytes, src + y * srcRow, min(rowBytes, srcRow)) }
    CVPixelBufferUnlockBaseAddress(buffer, [])
    adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
    if f % 150 == 0 { print("frame \(f)/\(frames)"); fflush(stdout) }
}
input.markAsFinished()
let sem = DispatchSemaphore(value: 0)
writer.finishWriting { sem.signal() }
sem.wait()
print("video done: \(writer.status.rawValue)")
