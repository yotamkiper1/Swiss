"""v9: the wand keeps only the first part of Yotam's wind chimes (the opening strike and shimmer, file 0.06-0.80 s),
very quiet. The swell that builds from 0.7 s and peaks at 1.2-2.2 s, and the tail, are cut. Everything else is v8.
Run on the v8 timeline.json (re-running is safe).

    python3 make_v9_cues.py
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
tl = json.load(open(os.path.join(HERE, 'timeline.json')))
for c in tl['cues']:
    if c['name'] == 'wand-chimes':
        c.update(**{'in': 0.06, 'out': 0.80}, fade_in=0.01, fade_out=0.35, hp=400, level=-31,
                 beat='Click the wand (14.90): a quiet first shimmer as the folders appear (15.05)')
json.dump(tl, open(os.path.join(HERE, 'timeline.json'), 'w'), indent=1, ensure_ascii=False)
print([(c['id'], c['in'], c['out'], c['level']) for c in tl['cues'] if c['name'] == 'wand-chimes'])
