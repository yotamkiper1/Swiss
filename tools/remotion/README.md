# The Swiss commercial, in Remotion

A 50-second spot made with [Remotion](https://www.remotion.dev) (React → video). Nine scenes, each as long as its voice-over line:

| Scene | Line |
|---|---|
| Mess | That link. That screenshot. That file called final, final, two. You saved them. Somewhere. |
| Intro | Meet Swiss. A pocket knife for your ideas. |
| Menu bar | It lives in your menu bar. Press Option Space, and it's right there. |
| Capture | Drop in links, pictures, files and notes. Copy something anywhere, and Swiss can keep it. |
| Tabs | Every project gets its own tab. Folders, notes and links, living together like a very tidy family. |
| Wand | Total mess? Wave the wand. Poof. Sorted. |
| Frame | Need room to think? The Frame is a free canvas, floating above every app. |
| Private | No account. No cloud. Everything stays on your Mac. |
| Outro | Swiss. Now go save something. |

## Make it

```bash
npm install
./scripts/shots.sh                                   # app screenshots from docs/ → public/shots
python3 scripts/voice.py en_US-lessac-high.onnx      # Piper voice-over → public/audio/vo, src/timing.json
python3 scripts/sound.py                             # music and sound effects (numpy) → public/audio
npm run studio                                       # preview and scrub in the browser
npm run render                                       # → out/swiss-commercial.mp4
node scripts/stills.mjs 3 12.5 40                    # quick stills → out/still-<seconds>.png
```

- The voice is [Piper](https://github.com/rhasspy/piper) (`pip install piper-tts`), voice `en_US-lessac-high` from
  [rhasspy/piper-voices](https://huggingface.co/rhasspy/piper-voices). Any Piper voice works; scene lengths follow the new timings.
- To change a line, edit `src/scenes.json` and run `voice.py` then `sound.py` again (the music is fitted to the timeline).
- On-screen moments are cued to words in the line (`cue("wand", "Poof")` in `src/timeline.ts`).
- Without a downloaded Chrome, point Remotion at one: `--browser-executable=…` for the CLI, `REMOTION_BROWSER=…` for `stills.mjs`.

| Path | Contents |
|---|---|
| `src/scenes/` | One file per scene |
| `src/components.tsx` | The icon (vector), animated type, keycaps, windows, folders, cards |
| `src/Commercial.tsx` | Scene order, transitions, voice-over and music with ducking |
| `src/timeline.ts` | Scene lengths and word cues from the voice-over timings |
| `scripts/` | Screenshots, voice, sound, stills |

Generated audio, screenshots and renders aren't stored in git.
