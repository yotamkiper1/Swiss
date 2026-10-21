import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { TrafficLights, Words } from "../components";
import { fontFamily, ink, red, shadow, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "Every project gets its own tab." Close on the tabs, then pull back to the board as it shows folders, notes and links.

const WW = 1240;
const K = WW / 1520; // screenshot pixels → window pixels
const WX = (1920 - WW) / 2;
const WY = 60;

const tabs = [
  { x: 217, w: 258 },
  { x: 490, w: 200 },
  { x: 725, w: 140 },
];

export const Tabs: React.FC = () => {
  const frame = useCurrentFrame();
  const tabCue = [cue("tabs", "Every project"), cue("tabs", "gets its", 2), cue("tabs", "own tab")];
  const pull = soft(frame, cue("tabs", "Folders", -10));
  const shots = [
    { src: "13-big-full.png", at: 0 },
    { src: "14-big-notepad-quotes.png", at: cue("tabs", "notes") },
    { src: "11-big-linker.png", at: cue("tabs", "links") },
    { src: "12-big-photobook.png", at: cue("tabs", "living") },
    { src: "13-big-full.png", at: cue("tabs", "tidy family") },
  ];
  const family = cue("tabs", "like a very");

  // Camera: from close on the tab bar to the whole window.
  const scale = interpolate(pull, [0, 1], [2.1, 1]);
  const focusX = interpolate(pull, [0, 1], [WX + 560 * K, 960]);
  const focusY = interpolate(pull, [0, 1], [WY + 110 * K, 540]);

  // The highlight steps from tab to tab.
  let hi = 0;
  tabCue.forEach((c, i) => {
    if (frame >= c) hi = i;
  });
  const prev = Math.max(0, hi - 1);
  const step = soft(frame, tabCue[hi]);
  const hx = interpolate(step, [0, 1], [tabs[prev].x, tabs[hi].x]);
  const hw = interpolate(step, [0, 1], [tabs[prev].w, tabs[hi].w]);

  return (
    <AbsoluteFill style={{ background: "linear-gradient(160deg, #EDEAE5 0%, #DCD7D0 100%)", overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `translate(${960 - focusX * scale}px, ${540 - focusY * scale}px) scale(${scale})`, transformOrigin: "0 0" }}>
        <div style={{ position: "absolute", left: WX, top: WY, width: WW, height: 1160 * K, borderRadius: 22, overflow: "hidden", boxShadow: shadow, background: "#C8C8C8" }}>
          {shots.map((s, i) => {
            const o = i === 0 ? 1 : interpolate(frame - s.at, [0, 6], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
            return <Img key={i} src={staticFile(`shots/${s.src}`)} style={{ position: "absolute", inset: 0, width: "100%", height: "100%", opacity: o }} />;
          })}
          <TrafficLights size={13} style={{ position: "absolute", left: 22, top: 20 }} />
          {/* Tab highlight */}
          <div
            style={{
              position: "absolute",
              left: hx * K - 6,
              top: 66 * K,
              width: hw * K + 12,
              height: 66 * K,
              borderRadius: 14,
              border: `4px solid ${red}`,
              opacity: 1 - pull,
            }}
          />
        </div>
      </AbsoluteFill>

      {/* Lower third */}
      <div
        style={{
          position: "absolute",
          left: 110,
          bottom: 80,
          padding: "26px 40px 30px",
          borderRadius: 26,
          background: "rgba(255,255,255,0.94)",
          boxShadow: shadow,
          opacity: soft(frame, 6),
        }}
      >
        {frame < family - 4 ? (
          <Words text="Every project, its own tab." at={6} size={64} color={ink} highlight={["tab."]} />
        ) : (
          <Words text="Like a very tidy family." at={family - 4} size={64} color={ink} highlight={["tidy"]} />
        )}
      </div>


      {tabCue.map((c, i) => (
        <Sfx key={i} name="click" at={c} volume={0.35} />
      ))}
      <Sfx name="whoosh" at={cue("tabs", "Folders", -10)} volume={0.3} />
    </AbsoluteFill>
  );
};
