# Swiss: silent product film (40 s)

A faithful HTML rebuild of Swiss's screens, rendered frame by frame. No audio, no video editor.

- `BRIEF.md`: verified feature table (with source references), on-screen copy, timed storyboard, assets and recording needs.
- `film.html`: every scene, caption and timing. Open it in a browser with `?t=12.3` to see a moment, `?v=1` for the vertical layout.
- `render.mjs`: `node render.mjs stills 2 6.5` writes stills; `node render.mjs video out/film.mp4 [v]` renders 30 fps H.264 without an audio track.
- `icon.png`: the app icon (from `Resources/AppIcon-source.png`).

The rendered MP4s aren't stored in git.
