# Swiss v7: calmer middle, magic wand, a final last line, a polished picture

The 40-second film with a new, more polished picture (same timing, same script) and a thinner v7 mix. v6 is kept unchanged in `../sound-v6/` for comparison.

*In git:* only code, timeline, cue sheet and docs. The audio, the MP4s and the original sound files are not stored here (Sonniss licence: no redistribution of raw sounds). The picture source is in `../html-film/`.

| File | What it is |
|---|---|
| `swiss-film-v7-1920x1080.mp4` | **The finished commercial** (16:9, AAC 256 kb/s, 48 kHz stereo) |
| `swiss-film-v7-1080x1920-vertical.mp4` | The vertical cut with the same mix |
| `stems/` | `1_clicks-pops`, `2_movement`, `3_accents`, `4_keys-mouse`, `5_voice`, `6_music` (each as it sits in the mix), `swiss-v7-mix.wav`, `swiss-v7-music-sfx-no-voice.wav` |
| `clips/` | Every sound-effect cue as its own processed file |
| `CUE_SHEET.md` / `cue_sheet.csv` | All 70 cues with timing, source, creator, pack, bundle, URL, licence and processing; plus the voice lines and the music |
| `LOUDNESS_REPORT.md` | −16.6 LUFS, −1.5 dBTP |
| `timeline/` | `make_v7_cues.py` (applies the v7 changes to the v6 timeline), `render_v7.py`, `make_cuesheet.py`, `timeline.json`, `sources.json` |
| `voice/` | The v7 voice track, `LAST_LINE.md`, and the scripts for the new last line |
| `../v7/` | The picture source (`film.html`, `render.mjs`) and the silent v7 renders |

Rebuild: `cd timeline && python3 make_v7_cues.py && python3 render_v7.py ../../v7/out/swiss-film-v7-1920x1080-SILENT.mp4 ../../v7/out/swiss-film-v7-1080x1920-vertical-SILENT.mp4 && python3 make_cuesheet.py`

## 1. The magic wand

v6 played three sounds on the wand: a mechanical click (14.90), a rising glissando (15.08) and a marimba note (16.40). v7 replaces all three with one magic sparkle:

- **Magic Effect-000** (Alexander Ahura, *Groats Part1*, Sonniss GDC 2017), lands on the click at 14.92. Bright (about 7 kHz centre) and sustained, so it carries the seven items into their folders and fades out as the last card lands around 16.4 s (0.9 s fade, light room tail).
- **Ice Spell Buff Positive 02** (Sound Spark LLC, *Magic Spells, Buffs and Attacks*, Sonniss GDC 2019), a short bright shimmer layered on the attack at 14.90, 5 dB under it, so the click itself reads.

## 2. The last line

The generated "moving" rose at the end (to about 267 Hz, then restarted at 224 Hz on "-ving"), which sounds like she is about to add something. I re-shaped only the pitch of that word (Praat resynthesis, same timing and voice). It now peaks at about 203 Hz and falls to about 151 Hz: a full stop. Speech-to-text reads it back as "Swiss, keep your ideas moving." The line still starts at 36.9 s and ends at 38.63 s. The A-major ukulele chord still lands on the logo at 36.5 s, and a second, softer strum of the same chord now answers her last word at 38.66 s and rings out to the end of the film. Details: `voice/LAST_LINE.md`.

## 3. The middle, thinned out

v6 had 114 SFX cues; v7 has 70. Keys and mouse went from 81 to 43 (70 key strokes to 41, 11 mouse clicks to 2), and no key or click is stacked on a pop any more. Removed:

| Removed | Where | Why |
|---|---|---|
| All modifier combos: ⌘V (7.80/7.85), ⌘C (9.50/9.55), ⇧⌘4 (10.13–10.25), ⌘N (26.00/26.05), ⌘V (26.90/26.95) | Collect, Recent, Frame | Each was stacked on the pop of the item it creates, 50–150 ms later |
| The second ↩ (21.47) | Rename | Sat under the tonal rename click |
| 9 of 11 mouse clicks (4.60, 5.75, 6.75, 7.65, 10.40, 12.10, 17.50, 17.68, 25.05) | Throughout | Grabs and selects already have the drop pop or page-turn; kept only "select the file" (20.30) and "click back into the editor" (29.10), which have no other sound |
| All 5 wipe whooshes (4.25, 9.25, 14.25, 19.25, 32.25) | Every scene change | Each one fell right on a voice entry |
| Copy tick on the Recent link (9.55) | Recent | The link's own pop follows 170 ms later |
| Mech click, gliss and marimba (14.90, 15.08, 16.40) | Wand | Replaced by the magic sparkle |
| Editor typing: 11 → 7 strokes (24.12–24.98) and 29 → 16 (29.28–31.90), 3 dB quieter | Frame | Still starts and stops with the text, at a relaxed 6–7 strokes a second |

Kept: the rename (↩ and 9 strokes, now 2 dB quieter) and the 8-stroke Frame note.

## 4. The picture

Every transition was checked frame by frame and fixed without moving any event, so the sound stays in sync:

- **Opening:** the icon no longer shows through the window as it grows (no double exposure); a calmer pop with a small overshoot and no spin; a softer pulse.
- **Wipes:** a wider red band with a soft gradient edge. The new scene settles in from the right while the old one drifts left and dims slightly, so each cut reads as one move. Fixed a strip of bare background that appeared at the frame edge during wipes.
- **Connected (Finder) and the Frame:** the windows no longer appear see-through as they open; they ease up and scale in.
- **Three sizes:** the grid now resizes smoothly instead of jumping between layouts, and full screen pushes in gently so the screen isn't empty.
- **Ending:** the "Swiss" wordmark slides out from behind the icon instead of being cut off, the drifting crosses are gone, and the lockup settles with a slow scale.
- **High-end pass:** layered window shadows, a warm key light and vignette on the dark stage, lighter and tighter headline type (weight 700, tighter tracking), softer chips, thinner highlight rings with a soft glow, warmer greys.

## Mix

Unchanged from v6: voice on top, music "Happy Dance" by Holizna (CC0) dipping 7 dB under the voice, SFX dipping 3 dB, a look-ahead limiter on the SFX bus only (at most 3.8 dB, for under half a second in total).

## Honestly

I can't listen to audio here. All of the above was chosen and checked by measurement: pitch tracking for the last line, speech-to-text, onset timing, levels and true peak. The picture was checked on frame grabs. Please listen on headphones and on laptop speakers, especially to the wand sparkle, the last line, and whether the middle now feels calm enough.
