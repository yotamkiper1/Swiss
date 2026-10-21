# Swiss v6 — voice-over, music, typing and more sound

The 40-second v5 picture, untouched (video stream copied), with a new full mix: the v5 sound design, 87 new sound cues, the Heart voice-over and upbeat music.

| File | What it is |
|---|---|
| `swiss-film-v6-1920x1080.mp4` | **The finished commercial** (16:9, AAC 256 kb/s, 48 kHz stereo) |
| `swiss-film-v6-1080x1920-vertical.mp4` | The vertical cut with the same mix |
| `stems/` | `1_clicks-pops`, `2_movement`, `3_accents`, `4_keys-mouse`, `5_voice`, `6_music` (each as it sits in the mix), `swiss-v6-mix.wav`, and `swiss-v6-music-sfx-no-voice.wav` (music and SFX, no voice, music not ducked) |
| `clips/` | Every sound-effect cue as its own processed file |
| `CUE_SHEET.md` / `cue_sheet.csv` | Every cue with timing, source file, creator, pack, bundle, URL, licence and processing; plus the voice lines and the music |
| `ATTRIBUTION.md` | Licences (no credit required) |
| `LOUDNESS_REPORT.md` | −16.9 LUFS, −2.0 dBTP |
| `timeline/` | `timeline.json`, `sources.json`, `make_v6_cues.py` (adds the new cues), `render_v6.py` (renders everything), `make_cuesheet.py`, and v5's `render_sfx.py` |
| `voice/`, `music/`, `sources/` | The voice track and its scripts, the music file with its licence note, and the original SFX files |

**Earlier versions, unchanged for comparison:** `../sound-v5/` (SFX only), `../voiceover-v5/` (voice + SFX, no music).

Rebuild: `cd timeline && python3 make_v6_cues.py && python3 render_v6.py <silent 16:9 mp4> <v5 vertical mp4> && python3 make_cuesheet.py` (numpy, scipy, soundfile, ffmpeg).

## What's new

**Typing (81 cues on track 4).** Every visible keystroke moment now has key sounds, cut stroke by stroke from one real laptop-keyboard recording (Hear and Now Sound, *Laptop Keyboard 5*). Each stroke is chosen from 33 clean letter keys or 3 space-bar hits, with its own level (−2.5 to +2 dB), slight pan and uneven spacing, pitched down 1 semitone and softened above 9 kHz so it sounds rounder:

| Time | What's typed |
|---|---|
| 20.55 · 20.70–21.33 · 21.47 | ↩ to rename, "Lyuba – hero print.jpg" (9 strokes), ↩ to confirm |
| 24.12–24.98 | Typing in the editor (11) |
| 26.00/26.05 · 26.30–26.88 · 26.90/26.95 | ⌘N, the Frame note "Under 60 words. Big type." (8), ⌘V |
| 29.28–31.90 | Back in the editor (29) |
| 7.80/7.85 · 9.50/9.55 · 10.13–10.25 | ⌘V, ⌘C, ⇧⌘4 |

The film's text appears faster than anyone types (about 30 characters a second), so the strokes run at a natural 11–14 a second and start and stop with the text. Spaces fall where the text has them.

**More sound in the same calm, tactile style.** 11 soft mouse clicks (grabs, selects, the PhotoBook double-click, clicking back into the editor) and 5 quiet airy whooshes on the red slash wipes (4, 9, 14, 19 and 32 s), each at a slightly different pitch.

**Music.** "Happy Dance" by Holizna (CC0), 117.5 bpm, A major. Its full section starts on the first wipe (4.0 s), and it is sped up 0.6 % so its bar lines land exactly on the logo at 36.5 s, where the music resolves from E to A and stops. It sits at about −22 LUFS between lines and dips 7 dB under the voice, with a small cut at 2.5 kHz to keep the words clear.

**New ending.** v5's closing note was a damped metal-mallet note in E. Against the music it is the unresolved chord (E is the dominant of A), and it is short and muted. Alternatives auditioned by measurement (pitch, envelope, length): a synth confirm tone (F♯/G♯, clashes, 0.3 s), a musical UI notification (A/E but thin and "app-like", 0.6 s), an ascending harp glissando (leans C major, clashes, 5 s), a xylophone flourish (G major, clashes) and a ukulele chord. **Chosen:** the ukulele chord (Sound Ex Machina, D major in the source) pitched down 5 semitones to **A major**, with a soft room tail, on the music's last downbeat, and a quiet bell-tree shimmer rising into it from about 35.7 s. It rings under "Swiss. Keep your ideas moving." Measured: the mix from 36.5 s reads as A with E, as intended.

## Mix

Voice on top. SFX bus +3 dB against v5's balance (+5.87 dB in total); it dips 3 dB under the voice. A look-ahead peak limiter on the SFX bus only catches the sharpest transients (at most 3.6 dB, for 0.6 s in total across the film) so a handful of peaks don't hold the whole mix down. No limiter or compressor on the music or the full mix; the voice has its own gentle compression and peak control (see `../voiceover-v5/`).

## Honestly

I can't listen to audio here. Everything above was chosen and checked by measurement: onset and beat detection for sync, chroma for key, K-weighted levels, true peak. No one has heard v6 yet. Please listen on headphones and on laptop speakers; in particular whether the keyboard feels satisfying or too busy under the voice, whether the music is loud enough, and how the ukulele ending lands. Any level, time or sound is a one-line change in `timeline.json` or `render_v6.py`.

Not updated for v6: the REAPER/FCP7 project files and `check_mix.py` (they describe v5).
