# Sound design for the v5 film

Code and cue sheet for the sound effects on the 40-second v5 film (`swiss-film-v5-*.mp4`). The audio itself is not in git: the Sonniss GDC licence allows using the sounds in the film but not redistributing them as sound files. The full delivery (finished MP4s, clips, stems, original sources, REAPER and Premiere/Resolve timelines, reports) lives in the project files under `swiss-commercial/sound-v5/`.

- `timeline/timeline.json` — every cue: source, trim, sync point, film time, pitch, EQ, fades, pan, level.
- `timeline/sources.json` — where each original file came from (bundle, zip member, URL, licence).
- `timeline/render_sfx.py` — rebuilds the clips, stems and MP4s from the originals in `sources/` (picture stream-copied).
- `timeline/check_mix.py` — loudness, true peak, sync and small-speaker checks.
- `timeline/make_projects.py`, `timeline/make_cuesheet.py` — the REAPER/FCP7 timelines and `CUE_SHEET.md` / `cue_sheet.csv`.

Result: 27 cues on 3 tracks, −25.0 LUFS integrated, −2.0 dBTP.
