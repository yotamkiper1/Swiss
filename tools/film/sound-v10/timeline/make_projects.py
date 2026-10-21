"""Writes editable timelines from placement.json (made by render_sfx.py):

- ../swiss-v5-sfx.RPP       REAPER project: the silent film on a video track, three SFX tracks, sample-accurate.
- ../swiss-v5-sfx-fcp7.xml  Final Cut Pro 7 XML for Premiere Pro or DaVinci Resolve (File > Import; relink to
                            the clips/ folder if it lives somewhere else). Frame-based, so positions round to 1/30 s.
"""
import json, os, subprocess
from urllib.parse import quote
from xml.sax.saxutils import escape

HERE = os.path.dirname(os.path.abspath(__file__)); ROOT = os.path.dirname(HERE)
FPS, DUR, SR = 30, 40.0, 48000
VIDEO = 'swiss-film-v5-1920x1080-SILENT.mp4'
TRACKS = {1: '1 Clicks & pops', 2: '2 Movement', 3: '3 Accents'}

pl = json.load(open(os.path.join(HERE, 'placement.json')))['placed']
cues = {c['id']: c for c in json.load(open(os.path.join(HERE, 'timeline.json')))['cues']}

def rpp():
    L = ['<REAPER_PROJECT 0.1 "7.0" 0', '  SAMPLERATE 48000 0 0', '  TEMPO 120 4 4',
         '  <TRACK', '    NAME "Picture (silent v5)"',
         f'    <ITEM', '      POSITION 0', f'      LENGTH {DUR}', f'      NAME "{VIDEO}"',
         f'      <SOURCE VIDEO', f'        FILE "{VIDEO}"', '      >', '    >', '  >']
    for t, name in TRACKS.items():
        L += ['  <TRACK', f'    NAME "{name}"']
        for p in pl:
            if p['track'] != t: continue
            L += ['    <ITEM', f"      POSITION {p['start']:.6f}", f"      LENGTH {p['length']:.6f}",
                  f"      NAME \"{p['clip'][:-4]}\"", '      <SOURCE WAVE', f"        FILE \"clips/{p['clip']}\"", '      >', '    >']
        L += ['  >']
    # Markers at every sync point, named after the visual beat.
    L[3:3] = [f"  MARKER {i} {p['sync_at']:.4f} \"{p['id']} {cues[p['id']]['name']}\" 0" for i, p in enumerate(pl, 1)]
    L.append('>')
    open(os.path.join(ROOT, 'swiss-v5-sfx.RPP'), 'w').write('\n'.join(L) + '\n')

# Where the delivery folder sits on the owner's Mac; Premiere/Resolve offer to relink if it has moved.
MAC_DIR = '/Users/yotamkiper/Downloads/Swiss sound design v5'

def url(rel):
    return 'file://localhost' + quote(os.path.join(MAC_DIR, rel))

def xml():
    fr = lambda s: int(round(s * FPS))
    rate = '<rate><timebase>30</timebase><ntsc>FALSE</ntsc></rate>'
    X = ['<?xml version="1.0" encoding="UTF-8"?>', '<!DOCTYPE xmeml>', '<xmeml version="4">',
         '<sequence id="swiss-v5-sfx">', '<name>Swiss v5 SFX</name>', f'<duration>{fr(DUR)}</duration>', rate,
         '<media><video><format><samplecharacteristics>' + rate + '<width>1920</width><height>1080</height>'
         '<pixelaspectratio>square</pixelaspectratio></samplecharacteristics></format>',
         '<track><clipitem id="picture"><name>' + VIDEO + f'</name><duration>{fr(DUR)}</duration>{rate}'
         f'<start>0</start><end>{fr(DUR)}</end><in>0</in><out>{fr(DUR)}</out>'
         f'<file id="file-picture"><name>{VIDEO}</name><pathurl>{url(VIDEO)}</pathurl>{rate}<duration>{fr(DUR)}</duration>'
         '<media><video><samplecharacteristics><width>1920</width><height>1080</height></samplecharacteristics></video></media></file>'
         '</clipitem></track></video>', '<audio>']
    for t, name in TRACKS.items():
        X.append('<track>')
        for p in pl:
            if p['track'] != t: continue
            s, n = fr(p['start']), max(1, fr(p['length']))
            X.append(f"<clipitem id=\"c{p['id']}\"><name>{escape(p['clip'])}</name><duration>{n}</duration>{rate}"
                     f"<start>{s}</start><end>{s + n}</end><in>0</in><out>{n}</out>"
                     f"<file id=\"f{p['id']}\"><name>{escape(p['clip'])}</name><pathurl>{url('clips/' + p['clip'])}</pathurl>{rate}"
                     f"<duration>{n}</duration><media><audio><samplecharacteristics><depth>24</depth><samplerate>{SR}</samplerate>"
                     f"</samplecharacteristics><channelcount>2</channelcount></audio></media></file>"
                     f"<sourcetrack><mediatype>audio</mediatype><trackindex>1</trackindex></sourcetrack>"
                     f"<comments><mastercomment1>{escape(cues[p['id']]['beat'])}</mastercomment1></comments></clipitem>")
        X.append(f'<enabled>TRUE</enabled><locked>FALSE</locked></track>')
    X += ['</audio></media>']
    for p in pl:
        X.append(f"<marker><name>{p['id']} {escape(cues[p['id']]['name'])}</name><in>{fr(p['sync_at'])}</in><out>-1</out></marker>")
    X += ['</sequence>', '</xmeml>']
    open(os.path.join(ROOT, 'swiss-v5-sfx-fcp7.xml'), 'w').write('\n'.join(X) + '\n')

rpp(); xml(); print('wrote swiss-v5-sfx.RPP and swiss-v5-sfx-fcp7.xml')
