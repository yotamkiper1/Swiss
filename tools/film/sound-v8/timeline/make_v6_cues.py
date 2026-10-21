"""Adds the v6 cues to timeline.json: keyboard strokes synced to the film's typing, key combos,
mouse clicks and soft wipe whooshes. Strokes are cut from one real recording (Hear and Now Sound,
"Laptop Keyboard 5.wav"); each stroke is a separate cue with its own trim, level and pan, so the
typing keeps natural variation. Run once after editing; needs numpy and soundfile.

    python3 make_v6_cues.py
"""
import json, os
import numpy as np, soundfile as sf

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
KB = 'sources/Hear and Now Sound - Office Equipment and Supplies/Laptop Keyboard 5.wav'
rng = np.random.default_rng(6)

# Clean, separated strokes picked from the recording (onset in s; next onset ≥ 85 ms later).
# Letters are the brighter keys; spaces the lower, longer ones (spectral centroid under 7 kHz).
LETTERS = [0.365, 0.571, 0.736, 2.061, 2.264, 2.491, 2.659, 2.853, 3.032, 3.328, 4.243, 4.547, 4.680, 4.907, 5.115,
           5.347, 5.947, 6.219, 6.493, 6.736, 7.491, 8.464, 8.653, 9.144, 9.437, 9.805, 12.325, 12.664, 12.787,
           13.453, 13.736, 15.160, 15.813]
SPACES = [1.053, 5.624, 12.499]
a, sr = sf.read(os.path.join(ROOT, KB)); mono = np.abs(a.mean(axis=1))

def stroke(onset, length):
    i, j = int(onset * sr), int((onset + 0.03) * sr)
    peak = onset + np.argmax(mono[i:j]) / sr
    return round(onset - 0.003, 4), round(onset + length, 4), round(peak, 4)

def typing(name, t0, t1, text, n, beat, pan, level=-31):
    """n strokes from t0 to t1, uneven like real typing; spaces where the text has them."""
    gaps = rng.uniform(0.7, 1.3, n - 1); times = t0 + np.concatenate([[0], np.cumsum(gaps)]) / gaps.sum() * (t1 - t0)
    out = []
    for k, t in enumerate(times):
        ch = text[min(len(text) - 1, round(k * (len(text) - 1) / max(1, n - 1)))]
        space = ch == ' '
        on = rng.choice(SPACES) if space else rng.choice(LETTERS)
        i, o, s = stroke(on, 0.10 if space else 0.075)
        out.append(dict(track=4, name=f'{name}-{"space" if space else "key"}', src='laptopkeys', **{'in': i, 'out': o, 'sync': s},
                        at=round(float(t), 3), pitch=-1, hp=140, lp=9000, fade_out=0.025, pan=pan + float(rng.uniform(-0.05, 0.05)),
                        level=round(level + (1.5 if space else 0) + float(rng.uniform(-2.5, 2.0)), 1), beat=beat))
    return out

def keys(name, times, beat, pan, level=-30):
    out = []
    for t in times:
        i, o, s = stroke(rng.choice(LETTERS), 0.075)
        out.append(dict(track=4, name=name, src='laptopkeys', **{'in': i, 'out': o, 'sync': s}, at=t, pitch=-2, hp=140, lp=8000,
                        fade_out=0.025, pan=pan, level=level + float(round(rng.uniform(-1.5, 1.0), 1)), beat=beat))
    return out

def click(t, beat, pan, level=-31):
    return dict(track=4, name='mouse-click', src='mouse', **{'in': 0.0, 'out': 0.12, 'sync': MOUSE_SYNC}, at=t, pitch=-1, hp=250,
                lp=9000, fade_out=0.03, pan=pan, level=level, beat=beat)

m, msr = sf.read(os.path.join(ROOT, 'sources/SoundFxwizard - Textrobot/Mouse_press and release.wav'))
m = np.abs(m if m.ndim == 1 else m.mean(axis=1)); MOUSE_SYNC = round(float(np.argmax(m > 0.3 * m.max()) / msr), 4)

new = []
new += keys('key-cmd-v', [7.80, 7.85], 'Collect: ⌘V on the board (7.85)', 0.2)
new += keys('key-cmd-c', [9.50, 9.55], 'Recent: ⌘C on the link (9.55), under the glass tick', 0.0, -32)
new += keys('key-shift-cmd-4', [10.13, 10.19, 10.25], 'Recent: ⇧⌘4 (10.25)', 0.0)
new += keys('key-return', [20.55], 'Connected: ↩ starts the rename (20.55)', -0.1, -28)
new += typing('rename', 20.70, 21.33, 'Lyuba – hero print.jpg', 9, 'Connected: typing the new name (20.70–21.35)', -0.1)
new += keys('key-return', [21.47], 'Connected: ↩ confirms the rename, under the tonal click (21.50)', -0.1, -29)
new += typing('editor', 24.12, 24.98, 'Lyuba is the best-preserved ', 11, 'Frame: typing in the editor (24.0–25.0)', -0.25, -32)
new += keys('key-cmd-n', [26.00, 26.05], 'Frame: ⌘N for a note (26.05)', 0.25)
new += typing('note', 26.30, 26.88, 'Under 60 words. Big type.', 8, 'Frame: typing the note (26.30–26.90)', 0.25)
new += keys('key-cmd-v', [26.90, 26.95], 'Frame: ⌘V the tutorial link (26.95)', 0.25)
new += typing('editor', 29.28, 31.90, 'mammoth calf ever found. She was about a month old. Hang her photo', 29, 'Frame: back in the editor, typing (29.25–32.0)', -0.25, -32)
for t, b, p in [(4.60, 'Collect: grab the photo', 0.1), (5.75, 'Collect: grab the address', 0.1), (6.75, 'Collect: start selecting text', 0.1),
                (7.65, 'Collect: click the board', 0.3), (10.40, 'Recent: start the screenshot drag', 0.0), (12.10, 'Recent: select the screenshot', 0.2),
                (17.50, 'Wand: double-click PhotoBook (1)', 0.0), (17.68, 'Wand: double-click PhotoBook (2)', 0.0),
                (20.30, 'Connected: select the file', -0.1), (25.05, 'Frame: grab the hero print', 0.2), (29.10, 'Frame: click back into the editor', -0.25)]:
    new.append(click(t, b, p))
# The slash takes 0.5 s; the whoosh peaks as it crosses the middle. Each one a little different in pitch.
for t, st in ((4.25, 1), (9.25, -1), (14.25, 2), (19.25, 0), (32.25, -2)):
    new.append(dict(track=2, name='wipe-whoosh', src='airysoft', **{'in': 0.18, 'out': 0.7, 'sync': 0.306}, at=t, pitch=st, hp=450, lp=7000,
                    fade_in=0.06, fade_out=0.2, level=-34, beat=f'Red slash wipe into the next scene ({t - 0.25:.0f} s)'))

tl = json.load(open(os.path.join(HERE, 'timeline.json')))
# The closing sound. The music resolves from E (the dominant) to A at 36.5 s, so v5's damped metal note in E
# no longer fits. A ukulele chord (D major in the source) pitched down 5 semitones lands on A major with the music,
# with a short bell-tree shimmer rising into it; the music stops on that downbeat (render_v6.py).
for c in tl['cues']:
    if c['id'] == '27':
        c.update(name='logo-chord', src='uke', **{'in': 0.0, 'out': 4.0, 'sync': 0.06}, pitch=-5, hp=120, lp=12000,
                 fade_in=0.002, fade_out=0.6, reverb=0.18, pan=0, level=-17,
                 beat='Swiss logo (36.5): the music\'s last downbeat, resolving to A major')
new.append(dict(track=3, name='logo-shimmer', src='belltree', **{'in': 10.80, 'out': 11.90, 'sync': 11.626}, at=36.46, pitch=0,
                hp=1500, lp=14000, fade_in=0.15, fade_out=0.3, pan=0.15, level=-31, beat='Bell-tree shimmer rising into the logo (35.7–36.5)'))
tl['cues'] = [c for c in tl['cues'] if c['track'] != 4 and c['name'] not in ('wipe-whoosh', 'logo-shimmer')]
new.sort(key=lambda c: c['at'])
ks = [c for c in new if c['track'] == 4]; ws = [c for c in new if c['track'] != 4]
for k, c in enumerate(ks, 1): c['id'] = f'K{k:02d}'
for k, c in enumerate(ws, 1): c['id'] = f'W{k}'
tl['cues'] += new
tl['tracks'] = ['1 Clicks & pops', '2 Movement', '3 Accents', '4 Keys & mouse']
json.dump(tl, open(os.path.join(HERE, 'timeline.json'), 'w'), indent=1, ensure_ascii=False)
print(len(new), 'v6 cues added')
