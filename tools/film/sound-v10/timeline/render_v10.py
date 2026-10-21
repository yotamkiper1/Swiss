"""Swiss v10: v9 with a plain pop on the wand and the v10 picture + voice-over + music, mixed to one track.

    python3 render_v10.py <silent-16x9.mp4> <vertical.mp4 (any audio; only its picture is used)>

Uses the v5 functions in render_sfx.py for every SFX cue in timeline.json (v5 cues unchanged, plus the
v7 and v8 cues from make_v7_cues.py and make_v8_cues.py). Writes ../clips/, ../stems/, placement.json and ../swiss-film-v10-*.mp4.
Needs Python 3 with numpy and scipy, and ffmpeg.
"""
import json, os, subprocess, sys
from fractions import Fraction
import numpy as np
from scipy.signal import butter, sosfilt, resample_poly, iirpeak
import render_sfx as R

HERE, ROOT, SR, DUR = R.HERE, R.ROOT, R.SR, R.DUR
N = int(DUR * SR)
V5_MASTER_DB = 2.87      # v5's master gain, so the v5 cues keep their balance
SFX_DB = 3.0             # SFX bus up against voice and music
VOICE_DB = 0.0           # voice-only-heart.wav is already levelled (−18.5 LUFS mono) and peak-controlled
MUSIC = dict(file='music/06 HoliznaCC0 - Happy Dance.ogg',
             speed=Fraction(170, 169),  # +0.59 % (10 cents) so the bar lines land on 4.0 s and 36.5 s
             film0=4.034,               # track time at film 0 s; the track's first full section (8.06 s) starts at film 4.0 s
             level_lufs=-23.0,          # integrated, before ducking
             fade_in=0.4, fade_out_from=36.72, fade_out_to=37.5)  # ends on the 36.5 s downbeat (A), then out
DUCK = dict(voice_music_db=-7.0, voice_sfx_db=-3.0, attack=0.15, release=0.5, pre=0.12, post=0.25)

def envelope(active, depth_db, attack, release):
    g = np.empty(N); cur = 1.0; lo = 10 ** (depth_db / 20)
    ka, kr = np.exp(-1 / (attack * SR)), np.exp(-1 / (release * SR))
    for n in range(N):
        tgt = lo if active[n] else 1.0; k = ka if tgt < cur else kr
        cur = tgt + (cur - tgt) * k; g[n] = cur
    return g

def limit(x, ceil_db, look=0.002, release=0.08):
    """Look-ahead peak limiter (4x-oversampled detection). Only the SFX bus goes through it: a few short
    transients (the logo note, the first pop, the wand settle) would otherwise set the level of the whole mix."""
    ceil = 10 ** (ceil_db / 20)
    from scipy.ndimage import maximum_filter1d, uniform_filter1d
    det = np.abs(resample_poly(x, 4, 1, axis=0)).max(axis=1).reshape(-1, 4).max(axis=1)[:len(x)]
    la = int(look * SR); pk = maximum_filter1d(det, 2 * la + 1)
    want = np.minimum(1, ceil / np.maximum(pk, 1e-12)); g = np.empty_like(want); c = 1.0; kr = np.exp(-1 / (release * SR))
    for n in range(len(want)):
        c = want[n] if want[n] < c else want[n] + (c - want[n]) * kr; g[n] = c
    g = np.minimum(uniform_filter1d(g, la), want)
    return g

def music():
    x = R.decode(os.path.join(ROOT, MUSIC['file']))
    s = MUSIC['speed']; x = resample_poly(x, s.denominator, s.numerator, axis=0)   # plays faster by `speed`
    i = int(round(MUSIC['film0'] / float(s) * SR)); x = x[i:i + N]
    x = np.vstack([x, np.zeros((N - len(x), 2))])
    x = sosfilt(butter(2, 45, 'high', fs=SR, output='sos'), x, axis=0)
    # a gentle 3 dB dip around 2.5 kHz leaves room for the voice's consonants
    b, a = iirpeak(2500, 1.2, fs=SR)
    from scipy.signal import lfilter
    x = x - (1 - 10 ** (-3 / 20)) * lfilter(b, a, x, axis=0)
    t = np.arange(N) / SR; env = np.clip(t / MUSIC['fade_in'], 0, 1)
    u = np.clip((t - MUSIC['fade_out_from']) / (MUSIC['fade_out_to'] - MUSIC['fade_out_from']), 0, 1)
    env *= np.cos(u * np.pi / 2) ** 2
    x *= env[:, None]
    return x * 10 ** ((MUSIC['level_lufs'] - R.integrated_lufs(x)) / 20)

def main():
    tl = json.load(open(os.path.join(HERE, 'timeline.json'))); sources = json.load(open(os.path.join(HERE, 'sources.json')))
    tracks = {t: np.zeros((N, 2)) for t in (1, 2, 3, 4)}; placed = []
    for c in tl['cues']:
        x, sync = R.process(c, sources[c['src']]); start = c['at'] - sync
        name = f"SFX{c['id']}_{c['name']}_{c['at']:05.2f}s.wav"
        R.write_wav(os.path.join(ROOT, 'clips', name), x)
        i = int(round(start * SR)); j = min(N, i + len(x)); tracks[c['track']][max(0, i):j] += x[max(0, -i): j - i]
        placed.append(dict(id=c['id'], clip=name, track=c['track'], start=round(start, 4), sync_at=c['at'], length=round(len(x) / SR, 4)))
    g_sfx = 10 ** ((V5_MASTER_DB + SFX_DB) / 20)
    v = R.decode(os.path.join(ROOT, 'voice', 'voice-only-heart.wav')) * 10 ** (VOICE_DB / 20)
    v = np.vstack([v, np.zeros((N - len(v), 2))])[:N]
    regions = json.load(open(os.path.join(ROOT, 'voice', 'regions.json')))
    act = np.zeros(N, bool)
    for t0, t1, _ in regions: act[int((t0 - DUCK['pre']) * SR): int((t1 + DUCK['post']) * SR)] = True
    m = music()
    gm = envelope(act, DUCK['voice_music_db'], DUCK['attack'], DUCK['release'])
    gs = envelope(act, DUCK['voice_sfx_db'], DUCK['attack'], DUCK['release'])
    sfx = {t: x * g_sfx * gs[:, None] for t, x in tracks.items()}
    md = m * gm[:, None]
    mix = sum(sfx.values()) + md + v
    gdb = -16.0 - R.integrated_lufs(mix)                      # aim for -16 LUFS integrated
    gl = limit(sum(sfx.values()), -3.0 - gdb)                 # SFX bus peaks at most -3 dBTP after the final gain
    sfx = {t: x * gl[:, None] for t, x in sfx.items()}        # the same gain curve on every SFX stem
    gr = 20 * np.log10(gl.min()); busy = (gl < 10 ** (-0.5 / 20)).sum() / SR
    mix = sum(sfx.values()) + md + v
    li, tp = R.integrated_lufs(mix), R.true_peak_db(mix)
    gdb = min(-16.0 - li, -1.5 - tp); g = 10 ** (gdb / 20)
    print(f'SFX bus limiter: max {gr:.1f} dB, more than 0.5 dB for {busy:.2f} s in total')
    names = {1: '1_clicks-pops', 2: '2_movement', 3: '3_accents', 4: '4_keys-mouse'}
    for t, x in sfx.items(): R.write_wav(os.path.join(ROOT, 'stems', names[t] + '.wav'), x * g)
    R.write_wav(os.path.join(ROOT, 'stems', '5_voice.wav'), v * g); R.write_wav(os.path.join(ROOT, 'stems', '6_music.wav'), md * g)
    R.write_wav(os.path.join(ROOT, 'stems', 'swiss-v10-music-sfx-no-voice.wav'), (sum(sfx.values()) + m * 10 ** (-2 / 20)) * g)
    mixpath = os.path.join(ROOT, 'stems', 'swiss-v10-mix.wav'); R.write_wav(mixpath, mix * g)
    json.dump(dict(final_gain_db=round(gdb, 2), sfx_limiter_max_gr_db=round(gr, 1), sfx_limiter_active_s=round(busy, 2), sfx_gain_db=V5_MASTER_DB + SFX_DB, placed=placed), open(os.path.join(HERE, 'placement.json'), 'w'), indent=1)
    for video, tag in zip(sys.argv[1:3], ['1920x1080', '1080x1920-vertical']):
        out = os.path.join(ROOT, f'swiss-film-v10-{tag}.mp4')
        subprocess.run(['ffmpeg', '-nostdin', '-v', 'error', '-y', '-i', video, '-i', mixpath, '-map', '0:v:0', '-map', '1:a:0', '-c:v', 'copy',
                        '-c:a', 'aac', '-b:a', '256k', '-ar', '48000', '-movflags', '+faststart', '-t', str(DUR), out], check=True)
        print('wrote', out)
    print(f'final gain {gdb:+.2f} dB (pre {li:.1f} LUFS, {tp:.1f} dBTP)')

if __name__ == '__main__':
    main()
