# The last line, v7

"Swiss. Keep your ideas moving." is Kokoro-82M `af_heart` at speed 0.9 (`lastline.py`, take `a_0.9`). As generated,
"moving" rose to about 267 Hz and restarted at 224 Hz on "-ving", which sounds like a list that continues.

`fixlast.py` replaces the pitch on "moving" with a falling contour (Praat overlap-add resynthesis; timing, voice
quality and level untouched):

    python fixlast.py a_0.9.wav final_C.wav "[(1.56,186),(1.71,204),(1.79,190),(1.96,168),(2.04,146),(2.10,140)]"

Measured after: "moving" peaks at about 203 Hz and falls to about 151 Hz at the end of the word. faster-whisper
(small.en) reads it back as "Swiss, keep your ideas moving." The line still starts at 36.9 s and now ends at 38.63 s.
`mix_v7.py` is the voice chain (HPF 75 Hz, 2.5:1 compression, look-ahead limiter, levelled to −18.5 LUFS) that
writes `voice-only-heart.wav` and `regions.json` from the nine takes.
