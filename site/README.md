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

Source: the v10 film, `swiss-film-v10-1920x1080.mp4` (40 s). Everything is cropped to the app windows only, so no film
backdrop shows on the white page.

- `media/swiss-film.mp4`: the hero, a 20 s silent montage of five window crops (collect, recent, wand, connected folder,
  the Frame), each fitted onto a white 1600×1000 canvas and joined with 0.5 s crossfades.
- `media/clip-*.mp4`: one short muted loop per feature, cropped just inside the window edges (collect 5.6–9.0 s,
  recent 10.4–14.0, wand 14.8–19.0, connected 20.0–24.0, frame 25.0–31.8, sizes 33.4–36.0), H.264 CRF 25, each with a
  poster `.jpg`. They load only when scrolled to, and one plays at a time.

## Selling (off for now)

Sales go through Lemon Squeezy's hosted checkout, linked from this site (not the Mac App Store). To switch it on:
1. Create a Lemon Squeezy store and a product "Swiss" at $2, upload the zipped Swiss.app as its file.
2. Paste the product's checkout link into `CHECKOUT_URL` in `js/purchase.js` (only `https://*.lemonsqueezy.com/buy/…`
   links are accepted), then deploy. Empty link = no Buy button.
No card data or keys ever touch this site; Lemon Squeezy emails the receipt and the download.

## Deploy (Vercel)

Live at https://swiss-kohl.vercel.app (Vercel project "swiss"). From `site/`: `npx vercel deploy` (preview, behind
Vercel login) or `npx vercel deploy --prod`. The canonical URL and `og:image` in `index.html` and `privacy.html` use that
address; change them if a custom domain is added.
