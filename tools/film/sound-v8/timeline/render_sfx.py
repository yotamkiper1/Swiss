"""Builds the Swiss v5 sound design from timeline.json and the original Sonniss files in ../sources.

    python3 render_sfx.py <silent-16x9.mp4> [silent-vertical.mp4]

Writes ../clips/ (each processed SFX, one file per cue), ../stems/ (one WAV per track, plus the mix)
and ../swiss-film-v5-sfx-*.mp4 (the picture is stream-copied, untouched). Needs Python 3 with
numpy and scipy, and ffmpeg.
"""
import json, os, subprocess, sys
from fractions import Fraction
import numpy as np
from scipy.signal import butter, sosfilt, resample_poly

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SR = 48000
DUR = 40.0

def decode(path):
    raw = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', path, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)

def write_wav(path, x):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-f', 'f64le', '-ar', str(SR), '-ac', '2', '-i', '-',
                    '-c:a', 'pcm_s24le', path], input=np.ascontiguousarray(x).tobytes(), check=True)

def pitch(x, semis):
    """Varispeed: shifts pitch and duration together, like a tape or sampler."""
    if not semis: return x
    r = Fraction(2 ** (-semis / 12)).limit_denominator(200)
    return resample_poly(x, r.numerator, r.denominator, axis=0)

def fades(x, fi, fo):
    n = len(x); env = np.ones(n)
    if fi: k = min(n, int(fi * SR)); env[:k] = np.sin(np.linspace(0, np.pi / 2, k)) ** 2
    if fo: k = min(n, int(fo * SR)); env[n - k:] *= np.cos(np.linspace(0, np.pi / 2, k)) ** 2
    return x * env[:, None]

def room(x, mix, seed=7):
    """A small, soft room tail: decaying filtered noise convolved with the dry sound."""
    rng = np.random.default_rng(seed); n = int(1.6 * SR)
    t = np.arange(n) / SR
    ir = rng.standard_normal((n, 2)) * np.exp(-t / 0.38)[:, None]
    ir = sosfilt(butter(2, 5000, 'low', fs=SR, output='sos'), ir, axis=0)
    ir[: int(0.012 * SR)] = 0  # pre-delay
    ir /= np.sqrt((ir ** 2).sum(axis=0))
    wet = np.stack([np.convolve(x[:, c], ir[:, c]) for c in range(2)], axis=1)
    y = np.zeros_like(wet); y[: len(x)] = x
    return y + mix * wet

# ITU-R BS.1770 K-weighting at 48 kHz (high shelf + RLB high-pass).
K_SOS = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1.0, -1.69065929318241, 0.73248077421585],
                  [1.0, -2.0, 1.0, 1.0, -1.99004745483398, 0.99007225036621]])

def loudest_100ms(x):
    k = sosfilt(K_SOS, x, axis=0)
    p = (k ** 2).sum(axis=1)
    w = int(0.1 * SR); m = np.convolve(p, np.ones(w) / w, 'full')
    return -0.691 + 10 * np.log10(m.max() + 1e-20)

def integrated_lufs(x):
    """BS.1770-4 gated integrated loudness (400 ms blocks, 75 % overlap)."""
    k = sosfilt(K_SOS, x, axis=0); p = (k ** 2).sum(axis=1)
    w, h = int(0.4 * SR), int(0.1 * SR)
    z = np.array([p[i:i + w].mean() for i in range(0, len(p) - w + 1, h)])
    l = -0.691 + 10 * np.log10(z + 1e-20)
    z = z[l > -70]; rel = -0.691 + 10 * np.log10(z.mean()) - 10
    z = z[-0.691 + 10 * np.log10(z) > rel]
    return -0.691 + 10 * np.log10(z.mean())

def pan(x, p):
    if not p: return x
    a = (p + 1) * np.pi / 4
    m = x.mean(axis=1)
    return np.stack([m * np.cos(a), m * np.sin(a)], axis=1) * np.sqrt(2)

def process(c, src):
    x = decode(os.path.join(ROOT, src['file']))
    x = x[int(c['in'] * SR): int(c['out'] * SR)]
    sync = c['sync'] - c['in']
    x = pitch(x, c.get('pitch', 0)); sync *= 2 ** (-c.get('pitch', 0) / 12)
    if c.get('hp'): x = sosfilt(butter(2, c['hp'], 'high', fs=SR, output='sos'), x, axis=0)
    if c.get('lp'): x = sosfilt(butter(2, c['lp'], 'low', fs=SR, output='sos'), x, axis=0)
    x = fades(x, c.get('fade_in', 0.002), c.get('fade_out', 0.02))
    if c.get('reverb'): x = room(x, c['reverb']); x = fades(x, 0, 0.6)
    x = pan(x, c.get('pan', 0))
    x *= 10 ** ((c['level'] - loudest_100ms(x)) / 20)
    return x, sync

def true_peak_db(x):
    up = resample_poly(x, 4, 1, axis=0)
    return 20 * np.log10(np.abs(up).max() + 1e-12)

def main():
    tl = json.load(open(os.path.join(HERE, 'timeline.json')))
    sources = json.load(open(os.path.join(HERE, 'sources.json')))
    n = int(DUR * SR); tracks = {t: np.zeros((n, 2)) for t in (1, 2, 3)}
    placed = []
    for c in tl['cues']:
        x, sync = process(c, sources[c['src']])
        start = c['at'] - sync
        name = f"SFX{c['id']}_{c['name']}_{c['at']:05.2f}s.wav"
        write_wav(os.path.join(ROOT, 'clips', name), x)
        i = int(round(start * SR)); j = min(n, i + len(x))
        tracks[c['track']][i:j] += x[: j - i]
        placed.append(dict(id=c['id'], clip=name, track=c['track'], start=round(start, 4), sync_at=c['at'], length=round(len(x) / SR, 4)))
    mix = sum(tracks.values())
    m = tl['master']; li = integrated_lufs(mix); tp = true_peak_db(mix)
    gdb = min(m['integrated_target_lufs'] - li, m['true_peak_ceiling_dbtp'] - tp); g = 10 ** (gdb / 20)
    names = {1: '1_clicks-pops', 2: '2_movement', 3: '3_accents'}
    for t, x in tracks.items(): write_wav(os.path.join(ROOT, 'stems', names[t] + '.wav'), x * g)
    mixpath = os.path.join(ROOT, 'stems', 'swiss-v5-sfx-mix.wav'); write_wav(mixpath, mix * g)
    json.dump(dict(master_gain_db=round(20 * np.log10(g), 2), placed=placed), open(os.path.join(HERE, 'placement.json'), 'w'), indent=1)
    for video, tag in zip(sys.argv[1:3], ['1920x1080', '1080x1920-vertical']):
        out = os.path.join(ROOT, f'swiss-film-v5-sfx-{tag}.mp4')
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', video, '-i', mixpath, '-map', '0:v:0', '-map', '1:a:0',
                        '-c:v', 'copy', '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', '-t', str(DUR), out], check=True)
        print('wrote', out)
    print(f'master gain {gdb:+.2f} dB (pre-master {li:.1f} LUFS, {tp:.1f} dBTP)')

if __name__ == '__main__':
    main()
