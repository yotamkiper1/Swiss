# The Swiss commercial

Everything for the 80-second commercial is made in code: no video editor.

- `posters.swift` — the demo pictures used on screen.
- Swiss Test (`./build.sh test`, `STASH_LIBRARY=… "build/Swiss Test.app/…"`) with the `stashtest://debug…` hooks
  stages and captures each screen (`debugshot`).
- Voice-over: macOS `say -v Samantha` (one WAV per scene, named `vo/v1.wav` … `v11.wav`).
- `audio.swift` — the music, sound effects and the mix (ducked under the voice).
- `main.swift` — scenes, camera moves, transitions, encoding. `film <dir> preview 12.5 40` writes stills,
  `film <dir> audio` mixes the sound, `film <dir> render` makes `out/video.mp4`.
- `mux.swift` — joins picture and sound into the final MP4 (`afconvert -f m4af -d aac out/audio.wav out/audio.m4a` first).

Build: `swiftc -O -wmo main.swift audio.swift -o film`. The finished video isn't stored in git (it's ~70 MB).
