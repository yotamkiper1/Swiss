# Swiss v9: only the first, quiet part of the wind chimes on the wand

v8 with one change: the wand keeps only the opening of your wind chimes, very quiet. Everything else (fewer early clicks, the real screenshot) is as in v8, described below. v8 is kept in `../sound-v8/` for comparison.

*In git:* code, timeline, cue sheet and docs only; no audio or video, and not the user-supplied wand file. The picture source is `../html-film/` (unchanged since v8).

## v9: the wand

Only the first part of the file is used: file 0.06–0.80 s, the soft opening strike and shimmer. The swell that builds from 0.7 s (loudest at 1.2–2.2 s) and the tail are cut. It starts on the wand click at 14.90 s and fades out over 0.35 s, so it is gone by about 15.6 s, as the folders appear. Level −31 LUFS (loudest 100 ms; v8 was −21), high-passed at 400 Hz. Measured in the mix, it sits about 3 dB under the music at that moment, so it should read as a light touch rather than an effect. Same licence note as below: the file's source is unknown.

---

*v8 notes (section 1 on the wand is replaced by the v9 cut above; the rest still applies):*

| File | What it is |
|---|---|
| `swiss-film-v9-1920x1080.mp4` | **The finished commercial** (16:9, AAC 256 kb/s, 48 kHz stereo) |
| `swiss-film-v9-1080x1920-vertical.mp4` | The vertical cut with the same mix |
| `stems/`, `clips/` | Stems as they sit in the mix, `swiss-v9-mix.wav`, `swiss-v9-music-sfx-no-voice.wav`; every cue as its own file |
| `CUE_SHEET.md` / `cue_sheet.csv` | All 66 cues with source, licence and processing, plus the voice lines and the music |
| `LOUDNESS_REPORT.md` | −16.0 LUFS, −2.0 dBTP |
| `timeline/` | `make_v8_cues.py` and `make_v9_cues.py`, `render_v9.py`, `make_cuesheet.py`, `timeline.json`, `sources.json` |
| `../v8/` | The picture source (`film.html`, `render.mjs`, `assets/`) and the silent v8 renders |

Rebuild: `cd timeline && python3 make_v8_cues.py && python3 make_v9_cues.py && python3 render_v9.py ../../v8/out/swiss-film-v9-1920x1080-SILENT.mp4 ../../v8/out/swiss-film-v9-1080x1920-vertical-SILENT.mp4 && python3 make_cuesheet.py`

## 1. The wand: your "Magic Wind Chimes"

v7's two-layer sparkle is gone; the wand plays only your file (`sources/User-supplied/magic-wind-chimes.mp3`, 5.04 s). Measured, it starts with a soft strike at 0.11 s, swells to its loudest at about 1.3–2.2 s and then decays. Cut: file 0.06–3.00 s, placed so the first strike lands on the wand click at 14.90 s and the swell crests as the folders fill and the last card lands (about 16.2–16.5 s). It then fades out over 1.2 s and is gone by about 17.9 s, around the PhotoBook page turn. Light filtering only (HP 250 Hz), level −21 LUFS (loudest 100 ms), about the same as v7's sparkle.

**Licence:** this file's original source and licence are unknown. It is listed as user-provided in the cue sheet. Please confirm you have the rights before a commercial release. It is not in the repo.

## 2. Fewer clicks at the start

The first 14 s had 9 sounds; v8 has 6, one per real event. Removed: the link card's plop (6.48 s), the ⌘C copy tick (7.30 s) and the plop as the link slides into Recent (9.72 s). The drops that stay (photo 5.38 s, note 7.92 s, screenshot landing 11.52 s) are 2 dB softer. Kept: the opening pop, the window whoosh, the screenshot shutter and the Keep click.

## 3. A real screenshot

In v7 the "screenshot" was a crop of a photo (`lyuba.jpg`). In v8, ⇧⌘4 is taken over a browser window showing a real, unedited capture of Wikipedia's search results for "woolly mammoth calf Lyuba" (`assets/wiki-search.jpg`, captured in headless Chromium at 2×; the top results are the Lyuba and Woolly mammoth articles). The selection covers the whole page, and that capture is what flies into Recent and becomes its thumbnail. I used Wikipedia's own search rather than Google: Wikipedia's content is openly licensed (credited in `CREDITS.md`), while showing Google's results page and logo in an ad would need Google's permission. The vertical cut follows the browser window so it stays in frame.

## Honestly

I can't listen here. The chime cut is placed by measured onset and envelope, not by ear. Please check that the swell lands where you want it and that the opening feels calm enough.
