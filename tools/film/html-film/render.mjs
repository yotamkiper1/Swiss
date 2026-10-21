// Renders film.html frame by frame in headless Chromium and pipes the frames to ffmpeg (no audio track).
//   node render.mjs stills 2 6.5 15     → stills/t2.png …
//   node render.mjs video out.mp4 [v]   → 30 fps H.264; "v" renders the vertical 1080×1920 version
import { createRequire } from 'module';
import { spawn } from 'child_process';
import { mkdirSync } from 'fs';
import path from 'path';
const require = createRequire(import.meta.url);
let pw; try { pw = require('playwright'); } catch { pw = require('/opt/node22/lib/node_modules/playwright'); }

const [mode, ...rest] = process.argv.slice(2);
const vertical = mode === 'video' ? rest[1] === 'v' : rest.includes('v');
const W = vertical ? 1080 : 1920, H = vertical ? 1920 : 1080, FPS = 30;
const here = path.dirname(new URL(import.meta.url).pathname);
const browser = await pw.chromium.launch();
const page = await browser.newPage({ viewport: { width: W, height: H }, deviceScaleFactor: 1 });
await page.goto('file://' + path.join(here, 'film.html') + (vertical ? '?v=1' : ''));
await page.evaluate(() => document.fonts.ready);
await page.waitForTimeout(300);

if (mode === 'stills') {
  mkdirSync(path.join(here, 'stills'), { recursive: true });
  for (const t of rest.filter(x => x !== 'v')) {
    await page.evaluate(t => window.seek(t), +t);
    await page.screenshot({ path: path.join(here, 'stills', `${vertical ? 'v' : ''}t${t}.png`) });
  }
} else {
  const out = rest[0];
  const duration = await page.evaluate(() => window.DURATION);
  const frames = Math.round(duration * FPS);
  const ff = spawn('ffmpeg', ['-y', '-loglevel', 'error', '-f', 'image2pipe', '-framerate', String(FPS), '-c:v', 'png', '-i', '-',
    '-an', '-c:v', 'libx264', '-preset', 'slow', '-crf', '15', '-pix_fmt', 'yuv420p', '-profile:v', 'high', '-tune', 'animation',
    '-r', String(FPS), '-movflags', '+faststart', out], { stdio: ['pipe', 'inherit', 'inherit'] });
  for (let f = 0; f < frames; f++) {
    await page.evaluate(t => window.seek(t), f / FPS);
    const buf = await page.screenshot({ type: 'png' });
    if (!ff.stdin.write(buf)) await new Promise(r => ff.stdin.once('drain', r));
    if (f % 150 === 0) console.log(`frame ${f}/${frames}`);
  }
  ff.stdin.end();
  await new Promise(r => ff.on('close', r));
}
await browser.close();
