# The Swiss website

Plain HTML, CSS and JavaScript modules. No build step, no dependencies, no trackers.

```
index.html        the page
privacy.html      privacy for the app and the site
404.html          not found
css/tokens.css    colors (from the app icon), type, spacing, radii, motion
css/site.css      components and layout
js/main.js        header, mobile menu, Organize tabs, film dialog, reveal, download check
js/videos.js      feature clips: one plays at a time, pauses off screen / hidden tab / reduced motion
js/release.js     finds an installable build on GitHub Releases (none → "build from source")
media/            web encodes: 6 MB film + captions, 7 short muted clips with posters
tests/            node --test: release resolution and clip choice
vercel.json       security headers and caching
```

## Preview and test

```bash
cd site && python3 -m http.server 8765    # then open http://localhost:8765
cd site && npm test                       # Node 18+; no packages to install
```

## Media

Source quality lives outside the repo (`~/Desktop/Yotam Kiper/Video Projects/Swiss-Commercial.mp4`, 70 MB, 1920×1080).
The web copies are cut from it with ffmpeg. The scene times come from `tools/film/audio.swift` (`sceneStarts`):

| Clip | Film time | Shows |
|---|---|---|
| clip-hero | 14.9–34.6 s | menu bar pop-up, Recent, a project |
| clip-recent | 20.4–26.4 s | Recent, Keep |
| clip-projects | 27.2–34.6 s | a project board |
| clip-wand | 35.4–41.8 s | the magic wand |
| clip-connected | 42.6–50.0 s | a connected Finder folder |
| clip-frame | 50.8–59.8 s | the Frame and its library |
| clip-sizes | 60.6–65.8 s | pop-up → window → full screen |

```bash
ffmpeg -ss 20.4 -i Swiss-Commercial.mp4 -t 6 -an -vf scale=1280:-2 -c:v libx264 -crf 26 -preset slow \
  -pix_fmt yuv420p -movflags +faststart media/clip-recent.mp4
```

`media/swiss-commercial.en.vtt` is generated from `tools/film/script/voiceover.txt` and `voiceStarts`.

## Download

There's no notarized build yet, so the page shows "Build it on your Mac". As soon as a GitHub release with a
`.dmg` or `.zip` asset is published (not a draft or pre-release), the page shows its download, version and size by itself.

## Deploy (Vercel)

Live at https://swiss-kohl.vercel.app (Vercel project "swiss"). From `site/`: `npx vercel deploy` (preview, behind
Vercel login) or `npx vercel deploy --prod`. The canonical URL and `og:image` in `index.html` and `privacy.html` use that
address; change them if a custom domain is added.
