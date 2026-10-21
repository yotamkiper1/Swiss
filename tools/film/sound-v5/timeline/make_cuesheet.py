"""Writes ../CUE_SHEET.md and ../cue_sheet.csv from timeline.json, sources.json and placement.json."""
import csv, json, os

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
tl = json.load(open(os.path.join(HERE, 'timeline.json')))
src = json.load(open(os.path.join(HERE, 'sources.json')))
pl = {p['id']: p for p in json.load(open(os.path.join(HERE, 'placement.json')))['placed']}
master = json.load(open(os.path.join(HERE, 'placement.json')))['master_gain_db']
TRACK = {1: 'Clicks & pops', 2: 'Movement', 3: 'Accents'}

def tc(s):
    f = int(round(s * 30)); return f'00:00:{f // 30:02d}:{f % 30:02d}'

def processing(c):
    p = [f"trim {c['in']:.3f}–{c['out']:.3f} s"]
    if c.get('pitch'): p.append(f"pitch {c['pitch']:+d} st (varispeed)")
    p.append(f"HP {c['hp']} Hz / LP {c['lp']} Hz (12 dB/oct)")
    p.append(f"fade in {c.get('fade_in', 0.002) * 1000:.0f} ms, out {c.get('fade_out', 0.02) * 1000:.0f} ms")
    if c.get('reverb'): p.append(f"soft room tail {int(c['reverb'] * 100)} % wet")
    if c.get('pan'): p.append(f"pan {c['pan']:+.2f}")
    p.append(f"level {c['level']} LUFS (loudest 100 ms), master {master:+.2f} dB")
    return '; '.join(p)

rows = []
for c in tl['cues']:
    s = src[c['src']]; p = pl[c['id']]
    url = s['url_downloaded'] + (f" (zip member: {s['zip_member']})" if s['url_downloaded'].endswith('.zip') else '')
    rows.append({'#': c['id'], 'Sync (s)': f"{c['at']:.2f}", 'Timecode @30fps': tc(c['at']), 'Clip start (s)': f"{p['start']:.3f}",
                 'Track': TRACK[c['track']], 'Clip file': 'clips/' + p['clip'], 'Visual beat': c['beat'],
                 'Source file (exact title)': s['title'], 'Library / pack': s['pack'], 'Creator': s['creator'],
                 'Bundle': s['bundle'], 'Source URL': url, 'Licence': s['licence'], 'Processing': processing(c)})

with open(os.path.join(ROOT, 'cue_sheet.csv'), 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)

md = ['# Swiss v5 — SFX cue sheet', '',
      f"{len(rows)} cues on 3 tracks, 48 kHz / 24-bit. *Sync* is the film time where the sound's impact lands "
      "(its transient, or the peak of a swell); *clip start* is where the clip file begins on the timeline. "
      'All sources are from the Sonniss #GameAudioGDC bundles, licence: royalty-free, commercial use, **no attribution required** '
      '(full text: `sources/Sonniss-GameAudioGDC-License.pdf`).', '',
      '| # | Sync | TC | Track | Clip | Visual beat | Source file | Creator / pack | Processing |', '|---|---|---|---|---|---|---|---|---|']
for r in rows:
    md.append(f"| {r['#']} | {r['Sync (s)']} | {r['Timecode @30fps']} | {r['Track']} | `{r['Clip file'][6:]}` | {r['Visual beat']} | "
              f"{r['Source file (exact title)']} | {r['Creator']} — *{r['Library / pack']}* ({r['Bundle'].split(' (')[0].replace('Sonniss #GameAudioGDC ', 'GDC ')}) | {r['Processing']} |")
md += ['', '## Sources', '', '| Source file | Creator | Pack | Bundle | Downloaded from |', '|---|---|---|---|---|']
for k, s in src.items():
    md.append(f"| {s['title']} | {s['creator']} | {s['pack']} | {s['bundle']} | {s['url_downloaded']}" +
              (f" → `{s['zip_member']}`" if s['url_downloaded'].endswith('.zip') else '') + ' |')
open(os.path.join(ROOT, 'CUE_SHEET.md'), 'w').write('\n'.join(md) + '\n')
print('wrote CUE_SHEET.md and cue_sheet.csv')
