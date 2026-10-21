"""v8: the magic wand plays Yotam's own "Magic Wind Chimes" file instead of v7's two-layer Sonniss sparkle.
Also fewer clicks in the opening scenes (Collect and Recent, 4-14 s): the link card's plop (04, 6.48), the copy tick
(05, 7.30) and the Recent link's plop (08, 9.72) are dropped, and the drops that stay (03, 06, 10) are 2 dB softer.
That leaves one sound per real event: the photo drop, the note paste, the screenshot shutter and its landing, Keep.
Run on the v7 timeline.json (re-running is safe).

The file swells from a soft first strike at 0.11 s to its loudest around 1.3-2.2 s, then decays. Trimmed so
the first strike lands on the wand click (14.90) and the swell crests as the last card lands (16.4), then
fades out over 1.2 s before the PhotoBook page turn (17.8). Its source and licence are unknown (see sources.json).

    python3 make_v8_cues.py
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
tl = json.load(open(os.path.join(HERE, 'timeline.json')))
tl['cues'] = [c for c in tl['cues'] if c['name'] not in ('wand-magic', 'wand-sparkle', 'wand-chimes') and c['id'] not in ('04', '05', '08')]
for c in tl['cues']:
    if c['id'] in ('03', '06', '10') and not c.get('v8_softer'):
        c['level'] -= 2; c['v8_softer'] = True
tl['cues'].append(dict(id='M1', track=3, name='wand-chimes', src='chimes', **{'in': 0.06, 'out': 3.0, 'sync': 0.107}, at=14.90,
                       pitch=0, hp=250, lp=15000, fade_in=0.01, fade_out=1.2, pan=0, level=-21,
                       beat='Click the wand (14.90): folders appear, seven things fly in, last card lands (16.4)'))
json.dump(tl, open(os.path.join(HERE, 'timeline.json'), 'w'), indent=1, ensure_ascii=False)
print(len(tl['cues']), 'cues')
