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

Source: the v8 film, `~/Downloads/swiss-film-v8-1920x1080.mp4` (40 s, with sound).

- `media/swiss-film.mp4`: the only video on the page, 3.3–36.0 s of v8 (the logo intro and the end card are cut),
  1600 px, H.264 CRF 23, AAC 160 kb/s. Muted autoplay; Sound turns the sound on.
  `ffmpeg -ss 3.3 -i swiss-film-v8-1920x1080.mp4 -t 32.7 -vf scale=1600:-2 -c:v libx264 -crf 23 -preset slow -pix_fmt yuv420p -c:a aac -b:a 160k -movflags +faststart media/swiss-film.mp4`
- `img/shot-*.webp`: stills from v8 (frames at 8.8, 13.6, 14.9, 16.8, 23.8, 27.8, 32.6, 34.1, 35.6 s), cropped to the
  app windows. The film's dark backdrop is made transparent by a flood fill from the edges, so photos inside the windows
  keep their dark pixels. `shot-frame.webp` keeps its backdrop (it's the Frame over another app).

## Download

There's no notarized build yet, so the page shows "Build it on your Mac". As soon as a GitHub release with a
`.dmg` or `.zip` asset is published (not a draft or pre-release), the page shows its download, version and size by itself.

## Deploy (Vercel)

Live at https://swiss-kohl.vercel.app (Vercel project "swiss"). From `site/`: `npx vercel deploy` (preview, behind
Vercel login) or `npx vercel deploy --prod`. The canonical URL and `og:image` in `index.html` and `privacy.html` use that
address; change them if a custom domain is added.
