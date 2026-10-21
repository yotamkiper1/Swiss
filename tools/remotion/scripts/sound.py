"""Music and sound effects, synthesized from scratch with numpy.

Writes public/audio/music.wav (fitted to the film's timeline) and public/audio/sfx/*.wav.
Run after scripts/voice.py, since scene lengths follow the voice-over.
"""
import json, os, wave

import numpy as np

SR = 44100
here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
rng = np.random.default_rng(7)


def save(path, x):
    x = np.asarray(x, dtype=np.float64)
    if x.ndim == 1:
        x = np.stack([x, x], axis=1)
    peak = np.max(np.abs(x))
    if peak > 0.98:
        x = x * (0.98 / peak)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes((x * 32767).astype("<i2").tobytes())


def t_(dur):
    return np.arange(int(dur * SR)) / SR


def band(x, lo, hi):
    """Band-pass by FFT, with soft edges."""
    f = np.fft.rfftfreq(len(x), 1 / SR)
    resp = 1 / (1 + (lo / np.maximum(f, 1)) ** 4) / (1 + (f / hi) ** 4)
    return np.fft.irfft(np.fft.rfft(x) * resp, len(x))


def noise(dur):
    return rng.standard_normal(int(dur * SR))


def reverb(x, seconds=1.4, mix=0.22):
    ir_t = t_(seconds)
    ir = rng.standard_normal(len(ir_t)) * np.exp(-ir_t * 5.0)
    ir = band(ir, 200, 7000)
    ir /= np.sqrt(np.sum(ir**2))
    n = len(x) + len(ir)
    wet = np.fft.irfft(np.fft.rfft(x, n) * np.fft.rfft(ir, n), n)[: len(x)]
    return x * (1 - mix) + wet * mix * 3


def midi(n):
    return 440 * 2 ** ((n - 69) / 12)


# MARK: Instruments


def pluck(freq, dur=0.9, bright=1.0):
    t = t_(dur)
    y = np.zeros_like(t)
    for k in range(1, 8):
        y += (1 / k**1.3) * np.sin(2 * np.pi * freq * k * t) * np.exp(-t * (3.5 + k * 2.2 / bright))
    return y * np.minimum(1, t / 0.003)


def pad(freqs, dur):
    t = t_(dur)
    y = np.zeros_like(t)
    for f in freqs:
        for d in (-0.12, 0.12):
            for k in range(1, 6):
                y += (1 / k**1.8) * np.sin(2 * np.pi * (f * (1 + d / 100)) * k * t + k)
    env = np.minimum(1, t / 0.35) * np.minimum(1, (dur - t) / 0.4)
    return y * env / len(freqs)


def bass(freq, dur):
    t = t_(dur)
    y = np.sin(2 * np.pi * freq * t) + 0.35 * np.sin(2 * np.pi * 2 * freq * t)
    env = np.minimum(1, t / 0.01) * np.exp(-t * 2.2) * np.minimum(1, (dur - t) / 0.03)
    return np.tanh(1.6 * y * env)


def kick():
    t = t_(0.45)
    f = 45 + 110 * np.exp(-t * 28)
    ph = 2 * np.pi * np.cumsum(f) / SR
    return np.sin(ph) * np.exp(-t * 7) + 0.3 * band(noise(0.45), 1500, 6000) * np.exp(-t * 120)


def clap():
    t = t_(0.3)
    env = sum(np.exp(-np.maximum(t - d, 0) * 40) * (t >= d) for d in (0, 0.012, 0.024)) / 3
    return band(noise(0.3), 900, 5000) * env * 0.7


def hat(open_=False):
    t = t_(0.25)
    return band(noise(0.25), 7000, 16000) * np.exp(-t * (18 if open_ else 70)) * 0.5


# MARK: Sound effects


def sfx():
    d = os.path.join(root, "public", "audio", "sfx")
    t = t_(0.12)
    save(f"{d}/pop.wav", np.sin(2 * np.pi * np.cumsum(500 + 700 * np.exp(-t * 40)) / SR) * np.exp(-t * 30) * 0.8)

    t = t_(0.05)
    save(f"{d}/click.wav", (np.sin(2 * np.pi * 2200 * t) * 0.5 + band(noise(0.05), 2000, 9000) * 0.4) * np.exp(-t * 160))

    for name, dur, lo, hi, gain in (("whoosh", 0.7, 300, 3000, 0.7), ("swish", 0.35, 1200, 8000, 0.6)):
        t = t_(dur)
        env = np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 2
        n = band(noise(dur), lo, hi) * env
        pan = np.clip(t / dur, 0, 1)
        save(f"{d}/{name}.wav", np.stack([n * (1 - pan * 0.7), n * (0.3 + pan * 0.7)], axis=1) * gain)

    t = t_(0.5)
    thud = np.sin(2 * np.pi * np.cumsum(40 + 60 * np.exp(-t * 18)) / SR) * np.exp(-t * 9)
    save(f"{d}/thud.wav", thud + band(noise(0.5), 100, 900) * np.exp(-t * 40) * 0.4)

    out = np.zeros(int(1.0 * SR))
    for i in range(14):
        at = int((i * 0.055 + rng.uniform(0, 0.03)) * SR)
        tt = t_(0.08)
        f = rng.uniform(500, 1100)
        blip = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 50) * rng.uniform(0.3, 0.7)
        out[at : at + len(blip)] += blip[: len(out) - at]
    save(f"{d}/rattle.wav", out)

    out = np.zeros(int(1.4 * SR))
    for i in range(22):
        at = int(rng.uniform(0, 0.8) * SR)
        tt = t_(0.5)
        f = rng.uniform(2000, 6000)
        ping = np.sin(2 * np.pi * f * tt) * np.exp(-tt * 12) * rng.uniform(0.15, 0.35)
        out[at : at + len(ping)] += ping[: len(out) - at]
    save(f"{d}/sparkle.wav", reverb(out, 1.0, 0.35))

    t = t_(0.9)
    poof = band(noise(0.9), 150, 2500) * np.exp(-t * 6) + np.sin(2 * np.pi * 80 * t) * np.exp(-t * 10) * 0.6
    save(f"{d}/poof.wav", reverb(poof * 0.8, 0.8, 0.3))

    def bell(f, dur=1.6):
        t = t_(dur)
        return sum(a * np.sin(2 * np.pi * f * r * t) * np.exp(-t * dcy) for r, a, dcy in ((1, 1, 3), (2.76, 0.4, 6), (5.4, 0.2, 10)))

    save(f"{d}/ding.wav", reverb(bell(1320) * 0.5, 1.2, 0.3))
    chime = np.zeros(int(2.6 * SR))
    for i, n in enumerate((72, 76, 79, 84)):
        b = bell(midi(n), 2.2) * 0.35
        at = int(i * 0.07 * SR)
        chime[at : at + len(b)] += b
    save(f"{d}/chime.wav", reverb(chime, 1.6, 0.3))


# MARK: Music


def music():
    cfg = json.load(open(os.path.join(root, "src", "scenes.json")))
    timing = json.load(open(os.path.join(root, "src", "timing.json")))
    fps, tr = cfg["fps"], cfg["transition"]
    durs = [round(max(s["min"], s["lead"] + timing[s["id"]] + s["tail"]) * fps) for s in cfg["scenes"]]
    starts = [sum(durs[:i]) - i * tr for i in range(len(durs))]
    ids = [s["id"] for s in cfg["scenes"]]
    total = (starts[-1] + durs[-1]) / fps
    at = {i: starts[k] / fps for k, i in enumerate(ids)}

    bpm = 110
    beat = 60 / bpm
    drop = at["intro"]
    end_chord = at["outro"] + 0.4
    n = int((total + 3) * SR)
    L = np.zeros(n)
    R = np.zeros(n)

    def put(x, time, gain=1.0, pan=0.0):
        i = int(time * SR)
        if i >= n or i + len(x) <= 0:
            return
        if i < 0:
            x, i = x[-i:], 0
        x = x[: n - i]
        L[i : i + len(x)] += x * gain * (1 - pan) ** 0.5
        R[i : i + len(x)] += x * gain * (1 + pan) ** 0.5

    chords = [[60, 64, 67], [55, 59, 62], [57, 60, 64], [53, 57, 60]]  # C G Am F
    roots = [36, 43, 45, 41]
    arp = [0, 1, 2, 1, 3, 2, 1, 2]

    def section(t):
        if t < drop:
            return "tense"
        if at["private"] <= t < at["outro"]:
            return "break"
        if t >= end_chord:
            return "end"
        return "full"

    first = -int(drop / beat) - 1
    last = int((end_chord - drop) / beat) + 1
    for b in range(first, last):
        t = drop + b * beat
        if t < -0.1:
            continue
        sec = section(t)
        bar = (b // 4) % 4
        ch = chords[bar]
        tones = ch + [ch[0] + 12]
        # Arpeggio in 8ths.
        for h in range(2):
            tt = t + h * beat / 2
            note = tones[arp[(b % 4) * 2 + h]] + 12
            g = {"tense": 0.16, "full": 0.22, "break": 0.12, "end": 0}[sec]
            if g:
                put(pluck(midi(note), 0.8, 0.6 if sec == "tense" else 1.0), tt, g, pan=0.3 if h else -0.3)
        if sec in ("full", "break") and b % 4 == 0:
            put(pad([midi(x) for x in ch], beat * 4 + 0.3), t, 0.06)
        if sec == "full":
            if b % 2 == 0:
                put(kick(), t, 0.5)
            if b % 4 in (1, 3):
                put(clap(), t, 0.35)
            put(hat(), t + beat / 2, 0.22, 0.4)
            put(hat(), t, 0.12, -0.4)
            if b % 4 in (0, 2):
                put(bass(midi(roots[bar]), beat * 1.4), t, 0.35)
            if b % 4 == 3:
                put(bass(midi(roots[bar]), beat * 0.45), t + beat / 2, 0.25)
        elif sec == "tense":
            put(hat(), t, 0.1, 0.3)
            if b % 4 == 0:
                put(bass(midi(36), beat * 3), t, 0.18)
        elif sec == "break":
            if b % 4 == 0:
                put(kick(), t, 0.45)
                put(bass(midi(roots[bar]), beat * 3.5), t, 0.3)

    # Riser into the drop.
    rdur = 1.6
    rt = t_(rdur)
    riser = band(noise(rdur), 1500, 9000) * (rt / rdur) ** 2.5 * 0.25
    put(riser, drop - rdur)
    put(kick(), drop, 0.6)

    # The last chord rings out under the logo.
    final = pad([midi(x) for x in (48, 60, 64, 67, 72)], total - end_chord + 2.5)
    put(final * 0.12, end_chord)
    for i, note in enumerate((72, 76, 79, 84)):
        put(pluck(midi(note), 2.5), end_chord + i * 0.09, 0.2)
    put(kick(), end_chord, 0.5)
    put(bass(midi(36), 2.5), end_chord, 0.35)

    mix = np.stack([reverb(L, 1.6, 0.18), reverb(R, 1.6, 0.18)], axis=1)
    fade = np.minimum(1, (total - t_(n / SR)) / 1.2).clip(0, 1)
    mix *= fade[:, None]
    save(os.path.join(root, "public", "audio", "music.wav"), mix[: int(total * SR)] * 0.9)
    print(f"music: {total:.2f}s, drop at {drop:.2f}s")


sfx()
music()
