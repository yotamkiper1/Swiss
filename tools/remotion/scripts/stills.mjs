// Renders stills for a quick look: node scripts/stills.mjs 12.5 30 41 (seconds) → out/still-<s>.png
import { bundle } from "@remotion/bundler";
import { renderStill, selectComposition } from "@remotion/renderer";
import path from "node:path";

const browserExecutable = process.env.REMOTION_BROWSER || null;
const serveUrl = await bundle({ entryPoint: path.resolve("src/index.ts") });
const composition = await selectComposition({ serveUrl, id: "Commercial", browserExecutable });
for (const s of process.argv.slice(2)) {
  const frame = Math.min(composition.durationInFrames - 1, Math.round(Number(s) * composition.fps));
  await renderStill({ serveUrl, composition, frame, output: `out/still-${s}.png`, browserExecutable });
  console.log(`out/still-${s}.png`);
}
