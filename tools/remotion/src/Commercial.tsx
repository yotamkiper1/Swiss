import React from "react";
import { AbsoluteFill, Audio, interpolate, Sequence, staticFile } from "remotion";
import { linearTiming, springTiming, TransitionPresentation, TransitionSeries } from "@remotion/transitions";
import { fade } from "@remotion/transitions/fade";
import { iris } from "@remotion/transitions/iris";
import { slide } from "@remotion/transitions/slide";
import { wipe } from "@remotion/transitions/wipe";
import { Capture } from "./scenes/Capture";
import { Frame } from "./scenes/Frame";
import { Intro } from "./scenes/Intro";
import { MenuBar } from "./scenes/MenuBar";
import { Mess } from "./scenes/Mess";
import { Outro } from "./scenes/Outro";
import { Private } from "./scenes/Private";
import { Tabs } from "./scenes/Tabs";
import { Wand } from "./scenes/Wand";
import { Sfx } from "./Sfx";
import { H, SCENES, SceneId, TOTAL, TRANSITION, W } from "./timeline";

const views: Record<SceneId, React.FC<{ dur: number }>> = {
  mess: Mess,
  intro: Intro,
  menubar: MenuBar,
  capture: Capture,
  tabs: Tabs,
  wand: Wand,
  frame: Frame,
  private: Private,
  outro: Outro,
};

// The transition into each scene after the first.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
const into: Record<SceneId, TransitionPresentation<any> | null> = {
  mess: null,
  intro: iris({ width: W, height: H }),
  menubar: slide({ direction: "from-bottom" }),
  capture: wipe({ direction: "from-right" }),
  tabs: slide({ direction: "from-right" }),
  wand: wipe({ direction: "from-bottom-left" }),
  frame: slide({ direction: "from-top" }),
  private: wipe({ direction: "from-left" }),
  outro: fade(),
};

/** Music sits back while someone is talking. */
const musicVolume = (f: number) => {
  let duck = 0;
  for (const s of SCENES) {
    const a = s.voStart - 6;
    const b = s.voStart + Math.round(s.vo * 30) + 4;
    duck = Math.max(duck, interpolate(f, [a, a + 6, b, b + 10], [0, 1, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }));
  }
  const fadeIn = interpolate(f, [0, 8], [0, 1], { extrapolateRight: "clamp" });
  return fadeIn * interpolate(duck, [0, 1], [0.55, 0.2]);
};

export const Commercial: React.FC = () => (
  <AbsoluteFill style={{ background: "#151210" }}>
    <TransitionSeries>
      {SCENES.map((s, i) => {
        const View = views[s.id];
        const t = into[s.id];
        return (
          <React.Fragment key={s.id}>
            {i > 0 && t && (
              <TransitionSeries.Transition
                presentation={t}
                timing={s.id === "intro" ? linearTiming({ durationInFrames: TRANSITION }) : springTiming({ config: { damping: 200 }, durationInFrames: TRANSITION })}
              />
            )}
            <TransitionSeries.Sequence durationInFrames={s.dur}>
              <View dur={s.dur} />
            </TransitionSeries.Sequence>
          </React.Fragment>
        );
      })}
    </TransitionSeries>

    <Audio src={staticFile("audio/music.wav")} volume={musicVolume} />
    {SCENES.map((s) => (
      <Sequence key={s.id} from={s.voStart} durationInFrames={Math.ceil(s.vo * 30) + 6} layout="none">
        <Audio src={staticFile(`audio/vo/${s.id}.wav`)} volume={1} />
      </Sequence>
    ))}
    {SCENES.slice(1).map((s) => (
      <Sfx key={s.id} name="whoosh" at={s.start - 2} volume={0.3} />
    ))}
  </AbsoluteFill>
);

export const totalSeconds = TOTAL / 30;
