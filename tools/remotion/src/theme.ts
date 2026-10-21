import interUrl from "@fontsource-variable/inter/files/inter-latin-wght-normal.woff2";
import { loadFont } from "@remotion/fonts";
import { spring } from "remotion";
import { FPS } from "./timeline";

// Inter ships with the project, so rendering needs no network.
loadFont({ family: "Inter", url: interUrl, weight: "100 900" });
export const fontFamily = "Inter, sans-serif";

export const ink = "#151210";
export const paper = "#F6F3EE";
export const red = "#E0443A";
export const blade = "#3B2219";
export const gray = "#8E8A85";
export const yellow = "#FCEBA5";

/** A spring that starts at `delay` frames. */
export const pop = (frame: number, delay = 0, damping = 13, mass = 0.7) =>
  spring({ frame: frame - delay, fps: FPS, config: { damping, mass, stiffness: 120 } });

export const soft = (frame: number, delay = 0) => spring({ frame: frame - delay, fps: FPS, config: { damping: 200 } });

export const shadow = "0 30px 80px rgba(20, 14, 10, 0.28), 0 8px 24px rgba(20, 14, 10, 0.16)";
