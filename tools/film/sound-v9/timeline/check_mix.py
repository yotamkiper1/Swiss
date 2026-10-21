"""Measures the finished mix: BS.1770 loudness and true peak (via ffmpeg ebur128), sync of every cue in the
exported MP4, spectral balance, and how much each cue loses on small speakers (simulated with filters).

    python3 check_mix.py ../swiss-film-v5-sfx-1920x1080.mp4 > ../reports/measurements.json
"""
import json, os, re, subprocess, sys
import numpy as np
from scipy.signal import butter, sosfilt, welch

HERE = os.path.dirname(os.path.abspath(__file__)); SR = 48000
K_SOS = np.array([[1.53512485958697, -2.69169618940638, 1.19839281085285, 1.0, -1.69065929318241, 0.73248077421585],
                  [1.0, -2.0, 1.0, 1.0, -1.99004745483398, 0.99007225036621]])

def decode(path):
    raw = subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-i', path, '-ac', '2', '-ar', str(SR), '-f', 'f32le', '-'],
                         capture_output=True, check=True).stdout
    return np.frombuffer(raw, np.float32).reshape(-1, 2).astype(np.float64)

def ebur128(path):
    err = subprocess.run(['ffmpeg', '-nostdin', '-nostats', '-i', path, '-af', 'ebur128=peak=true', '-f', 'null', '-'],
                         capture_output=True, text=True).stderr
    summ = err[err.rfind('Summary:'):]
    g = lambda k: float(re.search(k + r':\s+(-?[\d.]+)', summ).group(1))
    return dict(integrated_lufs=g('I'), lra_lu=g('LRA'), true_peak_dbtp=g('Peak'))

def main(path):
    tl = json.load(open(os.path.join(HERE, 'timeline.json')))
    X = decode(path); x = X.mean(axis=1)
    p = (sosfilt(K_SOS, X, axis=0) ** 2).sum(axis=1)
    out = dict(file=os.path.basename(path), **ebur128(path))
    for w, k in [(0.4, 'max_momentary_lufs'), (3.0, 'max_short_term_lufs')]:
        n = int(w * SR); m = np.convolve(p, np.ones(n) / n, 'valid')
        out[k] = round(-0.691 + 10 * np.log10(m.max()), 1); out[k + '_at_s'] = round((np.argmax(m) + n / 2) / SR, 2)
    out['sample_peak_dbfs'] = round(20 * np.log10(np.abs(X).max()), 2)
    out['clipped_samples'] = int((np.abs(X) >= 0.999).sum())
    f, s = welch(x, SR, nperseg=8192); tot = s.sum()
    out['spectrum_share_pct'] = {k: round(100 * s[m].sum() / tot, 2) for k, m in
                                 {'<80Hz': f < 80, '80-150Hz': (f >= 80) & (f < 150), '150Hz-2kHz': (f >= 150) & (f < 2000),
                                  '2-6kHz': (f >= 2000) & (f < 6000), '>6kHz': f >= 6000}.items()}
    sims = {'laptop_hp300_lp14k': [('high', 300), ('low', 14000)], 'phone_hp500_lp10k': [('high', 500), ('low', 10000)]}
    filt = {k: x.copy() for k in sims}
    for k, fl in sims.items():
        for t, fc in fl: filt[k] = sosfilt(butter(4, fc, t, fs=SR, output='sos'), filt[k])
    a = np.abs(x); cues = []
    for c in tl['cues']:
        i, j = max(0, int((c['at'] - 0.06) * SR)), int((c['at'] + 0.12) * SR); seg = a[i:j]
        onset = (i + np.argmax(seg > seg.max() * 0.3)) / SR
        i2, j2 = max(0, int((c['at'] - 0.2) * SR)), int((c['at'] + 0.5) * SR); e0 = np.sqrt((x[i2:j2] ** 2).mean())
        drops = {k: round(20 * np.log10(np.sqrt((v[i2:j2] ** 2).mean()) / e0), 1) for k, v in filt.items()}
        cues.append(dict(id=c['id'], name=c['name'], cue_s=c['at'], onset_in_export_s=round(onset, 3),
                         offset_ms=round((onset - c['at']) * 1000), small_speaker_drop_db=drops))
    out['cues'] = cues
    print(json.dumps(out, indent=1))

if __name__ == '__main__':
    main(sys.argv[1])
