import config from "./scenes.json";
import timing from "./timing.json";

// Scene lengths follow the voice-over: lead-in + spoken line + tail, never under `min`.
// Neighbouring scenes overlap by TRANSITION frames.

export const FPS = config.fps;
export const W = 1920;
export const H = 1080;
export const TRANSITION = config.transition;

export type SceneId = "mess" | "intro" | "menubar" | "capture" | "tabs" | "wand" | "frame" | "private" | "outro";

export type Scene = { id: SceneId; line: string; lead: number; vo: number; dur: number; start: number; voStart: number };

const durations = config.scenes.map((s) => {
  const vo = (timing as Record<string, number>)[s.id];
  return Math.round(Math.max(s.min, s.lead + vo + s.tail) * FPS);
});

export const SCENES: Scene[] = config.scenes.map((s, i) => {
  const start = durations.slice(0, i).reduce((a, b) => a + b, 0) - i * TRANSITION;
  const vo = (timing as Record<string, number>)[s.id];
  return { id: s.id as SceneId, line: s.line, lead: s.lead, vo, dur: durations[i], start, voStart: start + Math.round(s.lead * FPS) };
});

export const TOTAL = SCENES[SCENES.length - 1].start + SCENES[SCENES.length - 1].dur;

export const scene = (id: SceneId) => SCENES.find((s) => s.id === id)!;

/** The frame (inside its scene) where `fragment` of the scene's line is spoken, estimated from its position in the line. */
export const cue = (id: SceneId, fragment: string, offset = 0) => {
  const s = scene(id);
  const i = s.line.indexOf(fragment);
  if (i < 0) throw new Error(`"${fragment}" is not in the ${id} line`);
  return Math.round((s.lead + 0.12 + (s.vo - 0.25) * (i / s.line.length)) * FPS) + offset;
};
