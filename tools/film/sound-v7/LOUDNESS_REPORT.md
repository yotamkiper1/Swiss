# Loudness report — Swiss v7

Measured with ffmpeg's `ebur128` filter (ITU-R BS.1770-4, true peak by 4× oversampling).

| File | Integrated | Loudness range | True peak |
|---|---|---|---|
| `swiss-film-v7-1920x1080.mp4` (AAC 256 kb/s) | **−16.6 LUFS** | 2.6 LU | **−1.5 dBTP** |
| `swiss-film-v7-1080x1920-vertical.mp4` (AAC 256 kb/s) | −16.6 LUFS | 2.6 LU | −1.5 dBTP |
| `stems/swiss-v7-mix.wav` (48 kHz / 24-bit) | −16.6 LUFS | 2.6 LU | −1.5 dBTP |
| `stems/swiss-v7-music-sfx-no-voice.wav` | −21.6 LUFS | 6.1 LU | −2.9 dBTP |

Stems as they sit in the mix (each gated on its own): voice −16.7 LUFS / −6.8 dBTP; music −27.2 LUFS / −9.5 dBTP (mostly ducked); keys & mouse −31.0 LUFS / −6.6 dBTP (v6: −28.4 LUFS); accents (wand, logo chord) −18.9 LUFS / −3.7 dBTP.

The final gain aimed for −16 LUFS with a −1.5 dBTP ceiling; the ceiling won by 0.6 dB, so the mix lands at −16.6 LUFS (v6: −16.9). Fine for web and social delivery; YouTube, Instagram and TikTok normalise to about −14 LUFS. Nothing clips.

Not done: a listening pass. These are measurements only.
