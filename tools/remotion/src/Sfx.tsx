import { Audio, Sequence, staticFile } from "remotion";

export type SfxName = "pop" | "rattle" | "thud" | "whoosh" | "click" | "sparkle" | "poof" | "chime" | "swish" | "ding";

/** A sound effect from public/audio/sfx, starting at frame `at` of the current scene. */
export const Sfx: React.FC<{ name: SfxName; at: number; volume?: number }> = ({ name, at, volume = 0.6 }) => (
  <Sequence from={Math.max(0, Math.round(at))} durationInFrames={90} layout="none">
    <Audio src={staticFile(`audio/sfx/${name}.wav`)} volume={volume} />
  </Sequence>
);
