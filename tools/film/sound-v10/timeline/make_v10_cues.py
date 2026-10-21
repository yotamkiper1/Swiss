"""v10: the wand gets one plain, soft pop on the click instead of any chime. The user-supplied wind chimes
(unknown licence) are no longer used anywhere. Everything else is v9. Run on the v9 timeline.json (safe to re-run).

    python3 make_v10_cues.py
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
tl = json.load(open(os.path.join(HERE, 'timeline.json')))
tl['cues'] = [c for c in tl['cues'] if c['name'] not in ('wand-chimes', 'wand-pop')]
# Membrans "Pop 31", as used for the screenshot landing (+4 st) but at its own pitch, so it is rounder and a
# little lower: a click you can feel rather than a "magic" effect.
tl['cues'].append(dict(id='M1', track=1, name='wand-pop', src='pop31', **{'in': 0.0, 'out': 0.12, 'sync': 0.003}, at=14.90,
                       pitch=0, hp=160, lp=9000, fade_in=0.004, fade_out=0.05, pan=0, level=-23,
                       beat='Click the wand (14.90)'))
json.dump(tl, open(os.path.join(HERE, 'timeline.json'), 'w'), indent=1, ensure_ascii=False)
s = json.load(open(os.path.join(HERE, 'sources.json'))); s.pop('chimes', None)
json.dump(s, open(os.path.join(HERE, 'sources.json'), 'w'), indent=1, ensure_ascii=False)
print(len(tl['cues']), 'cues')
