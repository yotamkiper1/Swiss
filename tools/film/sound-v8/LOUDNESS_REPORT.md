# Loudness report — Swiss v8

Measured with ffmpeg's `ebur128` filter (ITU-R BS.1770-4, true peak by 4× oversampling).

| File | Integrated | Loudness range | True peak |
|---|---|---|---|
| `swiss-film-v8-1920x1080.mp4` (AAC 256 kb/s) | **−16.0 LUFS** | 2.6 LU | **−2.1 dBTP** |
| `swiss-film-v8-1080x1920-vertical.mp4` (AAC 256 kb/s) | −16.0 LUFS | 2.6 LU | −2.1 dBTP |
| `stems/swiss-v8-mix.wav` (48 kHz / 24-bit) | −16.0 LUFS | 2.6 LU | −2.0 dBTP |
| `stems/swiss-v8-music-sfx-no-voice.wav` | −21.0 LUFS | 6.1 LU | −2.7 dBTP |

Stems in the mix: voice −16.2 LUFS / −6.2 dBTP; music −26.7 / −9.0; clicks & pops −26.1 / −3.0; keys & mouse −30.4 / −6.0; accents (wand chimes, logo chord) −18.1 / −3.1.

The final gain reached the −16 LUFS target this time (before gain, the v8 mix peaks 1.1 dB lower than v7, so the −1.5 dBTP ceiling no longer holds it back), so v8 is 0.6 dB louder overall than v7 at the same balance. Nothing clips. Not done: a listening pass.
