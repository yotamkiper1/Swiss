import Foundation

// MARK: - Audio: voice-over, music and sound effects, mixed to one stereo track.

let SR = 44100.0
let TOTAL = 80.0

/// Where each scene starts (seconds) — the video uses the same numbers.
let sceneStarts: [Double] = [0, 5.5, 13.2, 20.0, 26.8, 35.0, 42.2, 50.4, 60.2, 66.2, 70.9]
let voiceStarts: [Double] = [2.0, 5.9, 13.5, 20.3, 27.1, 35.3, 42.5, 50.6, 60.5, 66.4, 72.0]

struct Bus {
    var l: [Float]
    var r: [Float]
    init(_ n: Int) { l = [Float](repeating: 0, count: n); r = l }

    mutating func add(_ x: [Float], at t: Double, gain: Float = 1, pan: Float = 0) {
        let start = Int(t * SR)
        let gl = gain * min(1, 1 - pan), gr = gain * min(1, 1 + pan)
        for i in 0..<x.count {
            let j = start + i
            if j < 0 || j >= l.count { continue }
            l[j] += x[i] * gl
            r[j] += x[i] * gr
        }
    }

    /// With the pan moving from `from` to `to` across the sound.
    mutating func addSweep(_ x: [Float], at t: Double, gain: Float, from: Float, to: Float) {
        let start = Int(t * SR)
        for i in 0..<x.count {
            let j = start + i
            if j < 0 || j >= l.count { continue }
            let p = from + (to - from) * Float(i) / Float(max(1, x.count))
            l[j] += x[i] * gain * min(1, 1 - p)
            r[j] += x[i] * gain * min(1, 1 + p)
        }
    }
}

func noise() -> Float { Float.random(in: -1...1) }
func midi(_ m: Double) -> Double { 440 * pow(2, (m - 69) / 12) }

// MARK: Sound effects (all made from scratch)

func whoosh(_ dur: Double, up: Bool, f0: Double = 250, f1: Double = 5000) -> [Float] {
    let n = Int(dur * SR)
    var out = [Float](repeating: 0, count: n)
    var low = 0.0, band = 0.0
    for i in 0..<n {
        let p = Double(i) / Double(n)
        let fc = up ? f0 * pow(f1 / f0, p) : f1 * pow(f0 / f1, p)
        let f = 2 * sin(Double.pi * min(fc, 9000) / SR)
        let x = Double(noise())
        low += f * band
        let high = x - low - 0.35 * band
        band += f * high
        let env = pow(sin(Double.pi * min(1, p * 1.0)), 1.4) * (up ? (0.4 + 0.6 * p) : (1.0 - 0.4 * p))
        out[i] = Float(band * env * 0.55)
    }
    return out
}

func impact() -> [Float] {
    // A soft bubbly bloom: two quick pops and a light shimmer (no sub-bass boom).
    let n = Int(1.2 * SR)
    var out = [Float](repeating: 0, count: n)
    var p1 = 0.0, p2 = 0.0
    for i in 0..<n {
        let t = Double(i) / SR
        p1 += 2 * Double.pi * (300 + 700 * exp(-t * 34)) / SR
        var v = sin(p1) * exp(-t * 16) * 0.55
        if t > 0.09 { let u = t - 0.09; p2 += 2 * Double.pi * (480 + 900 * exp(-u * 36)) / SR; v += sin(p2) * exp(-u * 18) * 0.4 }
        v += (sin(2 * Double.pi * 1568 * t) + 0.5 * sin(2 * Double.pi * 2093 * t)) * exp(-t * 5) * 0.05
        out[i] = Float(v)
    }
    return out
}

func clickSound() -> [Float] {
    let n = Int(0.14 * SR)
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
        let t = Double(i) / SR
        var v = sin(2 * Double.pi * 1900 * t) * exp(-t * 380) * 0.45 + Double(noise()) * exp(-t * 900) * 0.08
        if t > 0.055 { let u = t - 0.055; v += sin(2 * Double.pi * 1500 * u) * exp(-u * 600) * 0.35 }
        out[i] = Float(v)
    }
    return out
}

func pop(_ base: Double = 220) -> [Float] {
    // A bubble pop: a quick blip with a little harmonic sparkle.
    let n = Int(0.16 * SR)
    var out = [Float](repeating: 0, count: n)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / SR
        phase += 2 * Double.pi * (base * 1.6 + base * 3.2 * exp(-t * 55)) / SR
        out[i] = Float((sin(phase) + 0.25 * sin(phase * 2)) * exp(-t * 30) * 0.7)
    }
    return out
}

func tick(_ f: Double = 3200) -> [Float] {
    let n = Int(0.05 * SR)
    return (0..<n).map { i in
        let t = Double(i) / SR
        return Float(sin(2 * Double.pi * f * t) * exp(-t * 300) * 0.32)
    }
}

func shutter() -> [Float] {
    let n = Int(0.3 * SR)
    var out = [Float](repeating: 0, count: n)
    var prev = 0.0
    for i in 0..<n {
        let t = Double(i) / SR
        let x = Double(noise())
        let hp = x - prev; prev = x
        var v = 0.0
        if t < 0.03 { v += hp * exp(-t * 130) }
        if t > 0.07 && t < 0.13 { v += hp * exp(-(t - 0.07) * 70) * 0.8 }
        v += sin(2 * Double.pi * 900 * t) * exp(-t * 90) * 0.18
        out[i] = Float(v * 0.4)
    }
    return out
}

func sparkle(notes: Int = 7, base: Double = 0) -> [Float] {
    let scale: [Double] = [1318.5, 1568.0, 1760.0, 2093.0, 2637.0, 3136.0, 3520.0, 4186.0]
    let n = Int(1.6 * SR)
    var out = [Float](repeating: 0, count: n)
    for k in 0..<notes {
        let f = scale[(k + Int(base)) % scale.count]
        let start = Int(Double(k) * 0.065 * SR)
        for i in 0..<(n - start) {
            let t = Double(i) / SR
            let v = (sin(2 * Double.pi * f * t) + 0.35 * sin(2 * Double.pi * f * 2.01 * t)) * exp(-t * 6.5) * 0.12
            out[start + i] += Float(v)
        }
    }
    return out
}

func ding(_ f: Double = 1318.5) -> [Float] {
    let n = Int(1.8 * SR)
    return (0..<n).map { i in
        let t = Double(i) / SR
        let a = sin(2 * Double.pi * f * t) * exp(-t * 2.8)
        let b = 0.4 * sin(2 * Double.pi * f * 2.76 * t) * exp(-t * 6)
        let c = 0.2 * sin(2 * Double.pi * f * 5.4 * t) * exp(-t * 11)
        return Float((a + b + c) * 0.45)
    }
}

func typeTick() -> [Float] {
    let n = Int(0.04 * SR)
    var lp = 0.0
    let pitch = Double.random(in: 0.25...0.5)
    return (0..<n).map { i in
        let t = Double(i) / SR
        lp += pitch * (Double(noise()) - lp)
        return Float(lp * exp(-t * 160) * 1.6)
    }
}

func thud() -> [Float] {
    let n = Int(0.14 * SR)
    var phase = 0.0
    return (0..<n).map { i in
        let t = Double(i) / SR
        phase += 2 * Double.pi * (170 + 260 * exp(-t * 45)) / SR
        return Float(sin(phase) * exp(-t * 28) * 0.6)
    }
}

// MARK: Reverb (a small Freeverb)

func reverb(_ x: [Float], wet: Float = 1, room: Float = 0.84) -> [Float] {
    let combs = [1557, 1617, 1491, 1422, 1277, 1356, 1188, 1116]
    let aps = [225, 556, 441, 341]
    var out = [Float](repeating: 0, count: x.count)
    for d in combs {
        var buf = [Float](repeating: 0, count: d)
        var idx = 0, store: Float = 0
        for i in 0..<x.count {
            let y = buf[idx]
            store = y * 0.8 + store * 0.2
            buf[idx] = x[i] * 0.015 + store * room
            idx = (idx + 1) % d
            out[i] += y
        }
    }
    for d in aps {
        var buf = [Float](repeating: 0, count: d)
        var idx = 0
        for i in 0..<out.count {
            let b = buf[idx]
            let y = -out[i] + b
            buf[idx] = out[i] + b * 0.5
            idx = (idx + 1) % d
            out[i] = y
        }
    }
    return out.map { $0 * wet }
}

// MARK: Music

func renderMusic(_ n: Int) -> (dry: Bus, send: Bus) {
    var drums = Bus(n)   // no reverb
    var tonal = Bus(n)   // pad / pluck / bass (to the reverb)
    let beat = 0.6, bar = 2.4
    // D – A – Bm – G, a bar each.
    let pads: [[Double]] = [[50, 54, 57, 62, 66], [45, 52, 57, 61, 64], [47, 54, 59, 62, 66], [43, 50, 55, 59, 62]]
    let roots: [Double] = [38, 45, 47, 43]
    let bars = Int(TOTAL / bar) + 2

    func energy(_ t: Double) -> (pad: Float, pluck: Float, bass: Float, kick: Bool, hat: Bool, clap: Bool) {
        if t < 5.5 { return (0.55, 0.45, 0, false, false, false) }
        if t < 13.2 { return (0.6, 0.75, 0.7, false, false, false) }
        if t < 20.0 { return (0.6, 0.8, 0.8, true, false, false) }
        if t < 26.8 { return (0.62, 0.85, 0.85, true, true, false) }
        if t < 60.2 { return (0.65, 0.9, 0.9, true, true, true) }
        if t < 66.2 { return (0.7, 0.95, 0.95, true, true, true) }
        if t < 70.9 { return (0.55, 0.55, 0.5, false, false, false) }
        if t < 76.0 { return (0.85, 0.9, 0.9, true, true, true) }
        return (0.8, 0.5, 0.4, false, false, false)
    }

    // Pad: soft detuned saws, a chord a bar, each swelling in and out.
    for b in 0..<bars {
        let t0 = Double(b) * bar
        if t0 >= TOTAL { break }
        let notes = pads[b % 4]
        let len = Int((bar + 0.9) * SR)
        var chunk = [Float](repeating: 0, count: len)
        for (ni, m) in notes.enumerated() {
            for detune in [-7.0, 0.0, 7.0] {
                let f = midi(m) * pow(2, detune / 1200)
                var phase = Double(ni) * 0.37, lp = 0.0
                let inc = f / SR
                for i in 0..<len {
                    phase += inc; if phase >= 1 { phase -= 1 }
                    let saw = phase * 2 - 1
                    lp += 0.06 * (saw - lp)
                    let tt = Double(i) / SR
                    let env = min(1, tt / 0.5) * min(1, max(0, (bar + 0.9 - tt) / 0.9))
                    chunk[i] += Float(lp * env * 0.07)
                }
            }
        }
        tonal.add(chunk, at: t0, gain: energy(t0).pad * 0.9)
    }

    // Pluck arpeggio.
    let pattern = [0, 2, 1, 3, 2, 4, 3, 1]
    var t = 0.0
    var step = 0
    while t < TOTAL {
        let e = energy(t)
        let eighths = t >= 5.5 && !(t >= 66.2 && t < 70.9)
        let play = eighths || (step % 2 == 0 && t > 0.4)
        if play && e.pluck > 0 {
            let b = Int(t / bar)
            let chord = pads[b % 4]
            let m = chord[pattern[step % 8] % chord.count] + (step % 8 >= 4 ? 24 : 12)
            let f = midi(m)
            let n2 = Int(0.9 * SR)
            var pl = [Float](repeating: 0, count: n2)
            for i in 0..<n2 {
                let tt = Double(i) / SR
                let tri = 2 * abs(2 * (f * tt - floor(f * tt + 0.5))) - 1
                let v = (0.55 * sin(2 * Double.pi * f * tt) + 0.3 * tri + 0.15 * sin(4 * Double.pi * f * tt)) * exp(-tt * 7.5)
                pl[i] = Float(v * 0.22)
            }
            let accent: Float = step % 2 == 0 ? 1 : 0.7
            tonal.add(pl, at: t, gain: e.pluck * accent, pan: Float(sin(Double(step) * 0.9) * 0.35))
        }
        t += 0.3
        step += 1
    }

    // Bass: root on the one and the "and" of two.
    for b in 0..<bars {
        let t0 = Double(b) * bar
        for (off, len) in [(0.0, 0.9), (1.5 * beat, 0.5), (2.0 * beat, 0.9), (3.5 * beat, 0.4)] {
            let tt0 = t0 + off
            if tt0 >= TOTAL { continue }
            let e = energy(tt0)
            if e.bass == 0 { continue }
            let f = midi(roots[b % 4])
            let n2 = Int(len * SR)
            var bs = [Float](repeating: 0, count: n2)
            var lp = 0.0
            for i in 0..<n2 {
                let ti = Double(i) / SR
                let saw = 2 * (f * ti - floor(f * ti + 0.5))
                lp += 0.05 * (saw - lp)
                let env = min(1, ti / 0.01) * exp(-ti * 3.5)
                bs[i] = Float((sin(2 * Double.pi * f * ti) * 0.7 + lp * 0.5) * env * 0.5)
            }
            tonal.add(bs, at: tt0, gain: e.bass)
        }
    }

    // Drums.
    let kick: [Float] = {
        let n2 = Int(0.35 * SR)
        var phase = 0.0
        return (0..<n2).map { i in
            let ti = Double(i) / SR
            phase += 2 * Double.pi * (46 + 110 * exp(-ti * 28)) / SR
            return Float(sin(phase) * exp(-ti * 9) * 0.95)
        }
    }()
    let hat: [Float] = {
        let n2 = Int(0.06 * SR)
        var prev: Float = 0
        return (0..<n2).map { i in
            let x = noise(); let hp = x - prev; prev = x
            return hp * Float(exp(-Double(i) / SR * 90)) * 0.3
        }
    }()
    let clap: [Float] = {
        let n2 = Int(0.22 * SR)
        var lp: Float = 0, prev: Float = 0
        return (0..<n2).map { i in
            let ti = Double(i) / SR
            let x = noise(); lp += 0.5 * (x - lp); let hp = lp - prev; prev = lp
            var env = exp(-ti * 22)
            for d in [0.0, 0.011, 0.022] where ti >= d { env += exp(-(ti - d) * 160) * 0.7 }
            return hp * Float(env) * 0.55
        }
    }()
    var tb = 0.0
    var bi = 0
    while tb < TOTAL {
        let e = energy(tb)
        if e.kick && bi % 1 == 0 { drums.add(kick, at: tb, gain: 0.72) }
        if e.clap && (bi % 4 == 1 || bi % 4 == 3) { drums.add(clap, at: tb, gain: 0.5) }
        if e.hat { drums.add(hat, at: tb + beat / 2, gain: 0.55, pan: 0.2) }
        tb += beat
        bi += 1
    }
    return (drums, tonal)
}

// MARK: Mix

func buildAudio(root: String) -> Bus {
    let n = Int(TOTAL * SR)

    // Voice.
    var voice = Bus(n)
    for (i, start) in voiceStarts.enumerated() {
        var samples = readWav("\(root)/vo3/v\(i + 1).wav")
        let count = samples.count
        // High-pass and a little warmth.
        var lp: Float = 0
        for k in 0..<count {
            lp += 0.012 * (samples[k] - lp)
            let hp = samples[k] - lp
            samples[k] = tanhf(hp * 1.5) / 1.5
        }
        let peak = samples.map { abs($0) }.max() ?? 1
        let norm = 0.85 / max(peak, 0.01)
        voice.add(samples.map { $0 * norm }, at: start, gain: 1, pan: 0)
    }
    let voiceMono = voice.l
    let voiceVerb = reverb(voiceMono, wet: 0.45, room: 0.78)

    // Music.
    let (drums, tonal) = renderMusic(n)
    let tonalVerb = reverb(zip(tonal.l, tonal.r).map { ($0 + $1) * 0.5 }, wet: 1.4, room: 0.88)

    // Ducking: the music steps back while she speaks.
    var duck = [Float](repeating: 1, count: n)
    var env: Float = 0
    for i in 0..<n {
        let a = abs(voiceMono[i])
        env += (a > env ? 0.002 : 0.00008) * (a - env)
        duck[i] = 1 - 0.45 * min(1, env * 7)
    }

    // Sound effects.
    var sfx = Bus(n)
    func at(_ t: Double, _ x: [Float], _ g: Float = 1, pan: Float = 0) { sfx.add(x, at: t, gain: g, pan: pan) }
    func sweep(_ t: Double, _ x: [Float], _ g: Float, _ a: Float, _ b: Float) { sfx.addSweep(x, at: t, gain: g, from: a, to: b) }

    // Intro.
    sweep(0.2, whoosh(1.2, up: true, f0: 200, f1: 4000), 0.6, -0.5, 0.2)
    at(1.0, impact(), 0.9)
    sweep(1.85, whoosh(0.6, up: true), 0.45, -0.6, 0.6)
    at(2.9, sparkle(), 0.5)
    // Scene changes.
    for b in sceneStarts.dropFirst() {
        sweep(b - 0.34, whoosh(0.62, up: Int(b) % 2 == 0, f0: 500, f1: 4200), 0.4, -0.7, 0.7)
        at(b - 0.02, thud(), 0.3)
    }
    // 1 — scattered.
    for (k, t) in [6.1, 8.2, 9.4, 10.6].enumerated() { at(t, pop(200 + Double(k) * 40), 0.55, pan: Float(k % 2 == 0 ? -0.3 : 0.3)) }
    sweep(11.7, whoosh(1.0, up: false, f0: 200, f1: 3500), 0.5, 0.7, -0.7)
    // 2 — menu bar.
    at(14.9, clickSound(), 0.8)
    at(15.15, pop(160), 0.6)
    at(15.2, sparkle(notes: 4, base: 2), 0.25)
    at(17.3, tick(), 0.5)
    // 3 — Recent.
    at(20.8, pop(260), 0.6, pan: -0.3)
    at(21.55, shutter(), 0.7, pan: -0.2)
    at(22.3, pop(300), 0.6, pan: -0.3)
    at(24.9, clickSound(), 0.8)
    at(25.0, ding(1568), 0.55)
    // 4 — projects.
    at(27.9, tick(), 0.5)
    at(30.1, clickSound(), 0.8)
    sweep(30.15, whoosh(0.35, up: true, f0: 800, f1: 5000), 0.3, -0.4, 0.4)
    at(32.6, tick(3600), 0.4)
    // 5 — wand.
    at(36.0, tick(), 0.5)
    at(37.4, clickSound(), 0.8)
    at(37.45, sparkle(notes: 8), 0.7)
    sweep(37.5, whoosh(0.8, up: true, f0: 400, f1: 7000), 0.4, -0.7, 0.7)
    for (k, t) in [39.3, 39.55, 39.8, 40.05].enumerated() { at(t, pop(330 + Double(k) * 70), 0.55, pan: Float(Double(k) * 0.3 - 0.45)) }
    // 6 — connected.
    at(43.4, tick(), 0.5)
    for k in 0..<7 { at(47.6 + Double(k) * 0.09, typeTick(), 0.5) }
    at(48.4, ding(1760), 0.45)
    at(48.4, pop(280), 0.4)
    // 7 — Frame.
    at(52.0, tick(), 0.5)
    sweep(53.7, whoosh(0.9, up: true, f0: 300, f1: 3500), 0.45, -0.7, 0.4)
    at(54.6, pop(190), 0.65)
    at(56.6, clickSound(), 0.7)
    sweep(56.75, whoosh(0.5, up: false, f0: 300, f1: 3000), 0.4, 0.2, -0.5)
    at(57.5, tick(2600), 0.3)
    // 8 — sizes.
    at(60.7, pop(230), 0.6)
    sweep(61.7, whoosh(0.6, up: true), 0.45, -0.3, 0.3)
    at(61.95, pop(170), 0.55)
    at(63.4, clickSound(), 0.8)
    sweep(63.5, whoosh(0.7, up: true, f0: 250, f1: 5500), 0.5, -0.8, 0.8)
    at(64.0, thud(), 0.4)
    // 9 — private.
    at(66.8, tick(), 0.5)
    at(67.6, tick(), 0.5)
    at(68.4, clickSound(), 0.8)
    at(68.5, ding(1046.5), 0.6)
    // 10 — outro.
    at(70.9, impact(), 0.9)
    at(71.7, sparkle(notes: 8, base: 1), 0.55)
    at(74.7, ding(1318.5), 0.5)
    at(74.75, ding(1975.5), 0.3)
    let sfxVerb = reverb(zip(sfx.l, sfx.r).map { ($0 + $1) * 0.5 }, wet: 0.45, room: 0.8)

    do {
        func rms(_ x: [Float], _ a: Int, _ b: Int) -> Double { var t = 0.0; for i in a..<b { t += Double(x[i] * x[i]) }; return 20 * log10(sqrt(t / Double(b - a)) + 1e-9) }
        // During the first spoken line of scene 3 (13.5–19 s): voice vs music vs effects.
        let a = Int(14.0 * SR), b = Int(18.5 * SR)
        var mus = [Float](repeating: 0, count: n)
        for i in 0..<n {
            let body: Float = tonal.l[i] * 0.85 + drums.l[i] * 0.95
            mus[i] = (body + tonalVerb[i] * 0.4) * 0.62 * duck[i]
        }
        print("balance 14–18.5s  voice \(Int(rms(voiceMono, a, b))) dB, music \(Int(rms(mus, a, b))) dB, sfx \(Int(rms(sfx.l, a, b))) dB")
        let a2 = Int(28.0 * SR), b2 = Int(34.0 * SR)
        print("balance 28–34s    voice \(Int(rms(voiceMono, a2, b2))) dB, music \(Int(rms(mus, a2, b2))) dB, sfx \(Int(rms(sfx.l, a2, b2))) dB")
    }

    // Mix everything.
    var out = Bus(n)
    let fadeStart = Int(77.5 * SR)
    for i in 0..<n {
        var fade: Float = 1
        if i > fadeStart { fade = max(0, 1 - Float(i - fadeStart) / Float(n - fadeStart)) }
        let musicGain: Float = 0.85 * duck[i] * fade
        let v = voiceMono[i] * 1.0 + voiceVerb[i] * 0.22
        let m = tonalVerb[i] * 0.4
        out.l[i] = v + (tonal.l[i] * 0.85 + drums.l[i] * 0.95 + m) * musicGain + sfx.l[i] * 0.95 + sfxVerb[i] * 0.22
        out.r[i] = v + (tonal.r[i] * 0.85 + drums.r[i] * 0.95 + m) * musicGain + sfx.r[i] * 0.95 + sfxVerb[i] * 0.22
    }
    // Gentle limiter, then normalise to -1 dB.
    var peak: Float = 0
    for i in 0..<n {
        out.l[i] = tanhf(out.l[i] * 0.95)
        out.r[i] = tanhf(out.r[i] * 0.95)
        peak = max(peak, abs(out.l[i]), abs(out.r[i]))
    }
    let g = 0.89 / max(peak, 0.01)
    for i in 0..<n { out.l[i] *= g; out.r[i] *= g }
    return out
}

func readWav(_ path: String) -> [Float] {
    guard let d = try? Data(contentsOf: URL(fileURLWithPath: path)) else { fatalError("missing \(path)") }
    var pos = 12
    while pos + 8 <= d.count {
        let id = String(data: d[pos..<pos + 4], encoding: .ascii) ?? ""
        let size = Int(d[pos + 4]) | Int(d[pos + 5]) << 8 | Int(d[pos + 6]) << 16 | Int(d[pos + 7]) << 24
        if id == "data" {
            let end = min(d.count, pos + 8 + size)
            let count = (end - pos - 8) / 2
            var out = [Float](repeating: 0, count: count)
            d.withUnsafeBytes { raw in
                for k in 0..<count {
                    let v = Int16(truncatingIfNeeded: Int(raw[pos + 8 + 2 * k]) | Int(raw[pos + 9 + 2 * k]) << 8)
                    out[k] = Float(v) / 32768
                }
            }
            return out
        }
        pos += 8 + size + (size & 1)
    }
    fatalError("no data chunk in \(path)")
}

func writeWav(_ bus: Bus, to path: String) {
    let n = bus.l.count
    var data = Data()
    func u32(_ v: UInt32) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 4)) }
    func u16(_ v: UInt16) { var x = v.littleEndian; data.append(Data(bytes: &x, count: 2)) }
    data.append("RIFF".data(using: .ascii)!); u32(UInt32(36 + n * 4))
    data.append("WAVEfmt ".data(using: .ascii)!); u32(16); u16(1); u16(2); u32(UInt32(SR)); u32(UInt32(SR) * 4); u16(4); u16(16)
    data.append("data".data(using: .ascii)!); u32(UInt32(n * 4))
    var pcm = [Int16](repeating: 0, count: n * 2)
    for i in 0..<n {
        pcm[2 * i] = Int16(max(-1, min(1, bus.l[i])) * 32767)
        pcm[2 * i + 1] = Int16(max(-1, min(1, bus.r[i])) * 32767)
    }
    pcm.withUnsafeBytes { data.append(contentsOf: $0) }
    try? data.write(to: URL(fileURLWithPath: path))
}
