# Loudness report — Swiss v6

Measured with ffmpeg's `ebur128` filter (ITU-R BS.1770-4, true peak by 4× oversampling).

| File | Integrated | Loudness range | True peak |
|---|---|---|---|
| `swiss-film-v6-1920x1080.mp4` (AAC 256 kb/s) | **−16.9 LUFS** | 2.5 LU | **−2.0 dBTP** |
| `swiss-film-v6-1080x1920-vertical.mp4` (AAC 256 kb/s) | −16.9 LUFS | 2.5 LU | −2.0 dBTP |
| `stems/swiss-v6-mix.wav` (48 kHz / 24-bit) | −16.9 LUFS | 2.5 LU | −1.5 dBTP |
| `stems/swiss-v6-music-sfx-no-voice.wav` | −21.7 LUFS | 5.7 LU | −1.8 dBTP |

Stems as they sit in the mix (each gated on its own): voice −17.2 LUFS / −7.0 dBTP; music −27.7 LUFS / −10.0 dBTP (mostly ducked); keys & mouse −28.4 LUFS / −4.5 dBTP.

The final gain aimed for −16 LUFS with a −1.5 dBTP ceiling on the WAV; the ceiling won by 0.9 dB (the music's beat at 16.4 s coinciding with the wand's marimba note), so the mix lands at −16.9 LUFS. That suits web and social delivery; YouTube, Instagram and TikTok normalise to about −14 LUFS and will turn it up slightly. Nothing clips.

Not done: a listening pass. These are measurements only.
