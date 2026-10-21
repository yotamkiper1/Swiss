"""v7: a thinner version of the v6 keys/mouse layer, plus the magic wand.

v6 had 101 key strokes and 11 mouse clicks under the voice, and a whoosh on every wipe (each one on a voice
entry). v7 keeps a click only where the picture shows a real action that has no other sound, and keeps typing
short and quiet. Removed: every modifier combo (⌘V, ⌘C, ⇧⌘4, ⌘N; the item that lands already has its pop),
the second ↩ (under the tonal rename click), 9 of 11 mouse clicks, all 5 wipe whooshes, the copy tick on the
Recent link (the link's pop follows 170 ms later), and the wand's mech click, gliss and marimba. The wand is now
one magic sparkle. Run on the v6 timeline.json (it replaces track 4, so re-running is safe).

Original v6 note: adds the v6 cues to timeline.json: keyboard strokes synced to the film's typing, key combos,
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
new += keys('key-return', [20.55], 'Connected: ↩ starts the rename (20.55)', -0.1, -29)
new += typing('rename', 20.70, 21.33, 'Lyuba – hero print.jpg', 9, 'Connected: typing the new name (20.70–21.35)', -0.1, -33)
new += typing('editor', 24.12, 24.98, 'Lyuba is the best-preserved ', 7, 'Frame: typing in the editor (24.0–25.0)', -0.25, -35)
new += typing('note', 26.30, 26.88, 'Under 60 words. Big type.', 8, 'Frame: typing the note (26.30–26.90)', 0.25, -34)
new += typing('editor', 29.28, 31.90, 'mammoth calf ever found. She was about a month old. Hang her photo', 16, 'Frame: back in the editor, typing (29.25–32.0)', -0.25, -35)
for t, b, p in [(20.30, 'Connected: select the file', -0.1), (29.10, 'Frame: click back into the editor', -0.25)]:
    new.append(click(t, b, p, -32))
# The wand: one magic sparkle on the click (14.90), carrying the seven items into their folders and fading as
# the last card lands (16.4). A short bright ice-buff shimmer sits on the attack so the click itself reads.
new.append(dict(track=3, name='wand-magic', src='magic', **{'in': 0.0, 'out': 2.3, 'sync': 0.057}, at=14.92, pitch=0, hp=300, lp=15000,
                fade_in=0.004, fade_out=0.9, pan=0, level=-21, reverb=0.15, beat='Click the wand (14.90): folders appear, seven things fly in (15.05–16.4)'))
new.append(dict(track=3, name='wand-sparkle', src='sparkle', **{'in': 0.0, 'out': 1.2, 'sync': 0.006}, at=14.90, pitch=0, hp=1200, lp=15000,
                fade_in=0.002, fade_out=0.5, pan=0.1, level=-26, beat='Sparkle on the wand click (14.90)'))
# The ending: the A-major chord lands on the logo (36.5) and has decayed by the time she finishes (38.63), so a
# second, softer strum of the same chord answers her last word and rings out to the end of the film.
new.append(dict(track=3, name='logo-chord-answer', src='uke', **{'in': 0.0, 'out': 1.36, 'sync': 0.06}, at=38.66, pitch=-5, hp=150,
                lp=10000, fade_in=0.002, fade_out=0.9, reverb=0.3, pan=-0.1, level=-24,
                beat='After "…ideas moving." (38.63): the chord again, softer, ringing to the end'))

tl = json.load(open(os.path.join(HERE, 'timeline.json')))
tl['cues'] = [c for c in tl['cues'] if c['track'] != 4 and c['name'] not in ('wipe-whoosh', 'wand-magic', 'wand-sparkle', 'logo-chord-answer')
             and c['id'] not in ('07', '12', '13', '14')]
new.sort(key=lambda c: c['at'])
ks = [c for c in new if c['track'] == 4]; ws = [c for c in new if c['track'] != 4]
for k, c in enumerate(ks, 1): c['id'] = f'K{k:02d}'
for k, c in enumerate(ws, 1): c['id'] = f'M{k}'
tl['cues'] += new
tl['tracks'] = ['1 Clicks & pops', '2 Movement', '3 Accents', '4 Keys & mouse']
json.dump(tl, open(os.path.join(HERE, 'timeline.json'), 'w'), indent=1, ensure_ascii=False)
print(len(new), 'v7 cues added;', len(tl['cues']), 'cues in all')
