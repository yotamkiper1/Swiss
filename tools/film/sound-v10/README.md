# Swiss v10: type and design pass, plain pop on the wand

Same 40 s, same script, same voice and music as v9. v9 is kept in `../sound-v9/` for comparison.

*In git:* code, timeline, cue sheet and docs only; no audio or video. The picture source is `../html-film/`.

| File | What it is |
|---|---|
| `swiss-film-v10-1920x1080.mp4` | **The finished commercial** (16:9, AAC 256 kb/s, 48 kHz stereo) |
| `swiss-film-v10-1080x1920-vertical.mp4` | The vertical cut with the same mix |
| `stems/`, `clips/`, `CUE_SHEET.md`, `cue_sheet.csv` | Stems, every cue as its own file, and the full cue sheet (66 cues) |
| `LOUDNESS_REPORT.md` | −16.0 LUFS, −1.8 dBTP |
| `timeline/` | `make_v10_cues.py` (on top of v6–v9), `render_v10.py`, `make_cuesheet.py` |
| `../v10/` | The picture source (`film.html`, `render.mjs`, `assets/`, `assets/fonts/`) and the silent v10 renders |

## Sound

The wand now has one plain, soft pop on the click (14.90 s): Membrans "Pop 31" (Sonniss GDC 2015), at its own pitch, a little lower and rounder than the screenshot's landing pop, level −23 LUFS (loudest 100 ms). The user-supplied wind chimes are no longer used anywhere, so every sound in the film is again a Sonniss GDC sound (no credit required).

## Design and type

Checked against the taste-skill rules (Leonxlnx/taste-skill, read as guidance; its tooling is built for web pages, so the rules were applied by eye on frame grabs, not with its inspector).

- **Typeface.** Everything was set in Inter, the most common default on generated work. The titles, the opening line and the closing lockup are now set in **Schibsted Grotesk** (a grotesk in the Swiss tradition; semibold, tracking −0.035em, leading 1.0). Inter stays only inside the app's screens, as a stand-in for the macOS system font. Two families in all.
- **No eyebrow labels.** The tiny, letter-spaced red capitals above every headline ("RECENT", "THE FRAME", "MAGIC WAND", "SWISS" …) are gone. The feature name moved into a readable supporting line under each headline, in sentence case, e.g. "Recent: optional clipboard and screenshot capture." Every line is from the voice-over script, so nothing new is claimed.
- **No pill chips.** The outlined pills with coloured dots are now plain lines of text. The "Pop-up / Window / Full screen" capsules are now words: the active one in full white (or ink, once the screen turns light), the others dimmed.
- **Colour from the icon only.** Ground #F3F4F1 and red #DF4637 are sampled from the app icon; the dark scenes are one flat near-black (#191614) instead of a brown radial gradient with a vignette; the Frame scene's violet-to-pink wallpaper gradient (the most recognisable "AI" palette) is now a full field of the knife's red. The wipe band is flat red.
- **No glow, one shadow.** Highlight rings are a solid 3 px red line with no glow. Windows keep one honest shadow, because they float; the four-layer stack is gone.
- **Smaller details.** The tracked caps line in the editor document is now sentence case; the opening and closing type is in the icon's dark brown, no grey.

## Fonts (both free for commercial use)

| Font | Where | Licence |
|---|---|---|
| Schibsted Grotesk (Schibsted, via Google Fonts) | Titles, opening, closing | SIL Open Font License 1.1 (`../v10/assets/fonts/OFL-SchibstedGrotesk.txt`) |
| Inter (Rasmus Andersson) | Inside the app screens | SIL Open Font License 1.1 |

The note card in the Frame uses DejaVu Serif (free licence, Bitstream Vera derivative) as the app's note style.

## Honestly

I can't listen here, and the design was judged on frame grabs, not in motion on a big screen. Please watch it once full screen.
