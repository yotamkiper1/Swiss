# Loudness report — Swiss v9

Measured with ffmpeg's `ebur128` filter (ITU-R BS.1770-4, true peak by 4× oversampling).

| File | Integrated | Loudness range | True peak |
|---|---|---|---|
| `swiss-film-v9-1920x1080.mp4` (AAC 256 kb/s) | **−16.0 LUFS** | 3.0 LU | **−2.0 dBTP** |
| `swiss-film-v9-1080x1920-vertical.mp4` (AAC 256 kb/s) | −16.0 LUFS | 3.0 LU | −2.0 dBTP |
| `stems/swiss-v9-mix.wav` (48 kHz / 24-bit) | −16.0 LUFS | 3.1 LU | −1.9 dBTP |
| `stems/swiss-v9-music-sfx-no-voice.wav` | −21.3 LUFS | 6.3 LU | −2.6 dBTP |

Final gain hit the −16 LUFS target (+2.44 dB); the −1.5 dBTP ceiling was not reached. Wand chimes, 14.9–15.6 s: about −34 dBFS RMS, roughly 3 dB under the music there. Nothing clips. Not done: a listening pass.
