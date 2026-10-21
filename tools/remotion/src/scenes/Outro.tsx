import React from "react";
import { AbsoluteFill, useCurrentFrame } from "remotion";
import { Icon, Keycap } from "../components";
import { fontFamily, gray, ink, paper, pop, red, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "Swiss. Now go save something."

export const Outro: React.FC = () => {
  const frame = useCurrentFrame();
  const icon = pop(frame, 2, 12, 0.8);
  const open = pop(frame, 10, 8, 0.6);
  const name = soft(frame, 8);
  const tag = soft(frame, cue("outro", "Now go", -4));
  const keys = cue("outro", "save", 4);

  return (
    <AbsoluteFill style={{ background: paper, alignItems: "center" }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 40%, #FFFFFF 0%, rgba(255,255,255,0) 60%)" }} />
      <div style={{ marginTop: 130, transform: `scale(${icon})`, filter: "drop-shadow(0 30px 40px rgba(60,30,20,0.25))" }}>
        <Icon size={250} open={open} />
      </div>
      <div
        style={{
          fontFamily,
          fontWeight: 900,
          fontSize: 190,
          letterSpacing: -9,
          color: ink,
          lineHeight: 1,
          marginTop: 20,
          opacity: name,
          transform: `translateY(${(1 - name) * 40}px)`,
        }}
      >
        Swiss
      </div>
      <div style={{ fontFamily, fontWeight: 500, fontSize: 48, color: gray, marginTop: 22, opacity: tag, transform: `translateY(${(1 - tag) * 20}px)` }}>
        Now go save <span style={{ color: red, fontWeight: 700 }}>something</span>.
      </div>
      <div style={{ display: "flex", alignItems: "center", gap: 18, marginTop: 50, transform: "scale(0.62)", transformOrigin: "center top" }}>
        <Keycap label="⌥" sub="option" at={keys} />
        <div style={{ fontFamily, fontSize: 60, fontWeight: 300, color: gray }}>+</div>
        <Keycap label="space" at={keys + 3} width={360} />
        <div style={{ fontFamily, fontSize: 52, fontWeight: 600, color: ink, marginLeft: 30, opacity: soft(frame, keys + 8) }}>· for macOS</div>
      </div>
      <Sfx name="chime" at={6} volume={0.5} />
    </AbsoluteFill>
  );
};
