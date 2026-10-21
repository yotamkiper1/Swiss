import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Doc, Keycap, Kicker, LinkChip, Note, Picture, Window, Words } from "../components";
import { fontFamily, ink, paper, pop, red, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "Drop in links, pictures, files and notes." They fly onto the board; then ⌘C, and Swiss offers to keep it.

const WIN = { x: 800, y: 150, w: 1040 };

export const Capture: React.FC = () => {
  const frame = useCurrentFrame();
  const enter = soft(frame, 0);
  const cues = [cue("capture", "links"), cue("capture", "pictures"), cue("capture", "files"), cue("capture", "notes")];
  const copyAt = cue("capture", "Copy something");
  const keepAt = cue("capture", "keep it", -4);

  const flyers: { node: React.ReactNode; to: [number, number]; rot: number }[] = [
    { node: <LinkChip url="are.na/swiss-refs" size={26} />, to: [1060, 770], rot: -4 },
    { node: <Picture w={230} h={170} g={1} />, to: [1330, 760], rot: 5 },
    { node: <Doc name="Brief.pdf" size={110} light={false} />, to: [1560, 740], rot: -3 },
    { node: <Note text="Push in slow on the blue poster." w={250} size={22} />, to: [1700, 560], rot: 4 },
  ];

  const toast = pop(frame, copyAt + 6, 14);
  const kept = frame >= keepAt + 4;

  return (
    <AbsoluteFill style={{ background: paper, overflow: "hidden" }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 70% 50%, #FFFFFF 0%, rgba(255,255,255,0) 60%)" }} />

      <div style={{ position: "absolute", inset: 0, perspective: 2400 }}>
        <div
          style={{
            position: "absolute",
            left: WIN.x,
            top: WIN.y,
            transform: `translateX(${(1 - enter) * 900}px) rotateY(${-16 + enter * 6}deg) rotateX(3deg)`,
            transformOrigin: "0% 50%",
          }}
        >
          <Window src="13-big-full.png" width={WIN.w} style={{ position: "relative" }} />
        </div>
      </div>

      {flyers.map((f, i) => {
        const t = soft(frame, cues[i] - 4);
        if (frame < cues[i] - 4) return null;
        const x = interpolate(t, [0, 1], [-300, f.to[0]]);
        const y = interpolate(t, [0, 1], [f.to[1] + 200, f.to[1]]) - Math.sin(t * Math.PI) * 220;
        const land = interpolate(frame - cues[i] - 10, [0, 4, 10], [1, 0.92, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
        return (
          <div key={i} style={{ position: "absolute", left: x, top: y, transform: `translate(-50%, -50%) rotate(${f.rot + (1 - t) * -30}deg) scale(${land})` }}>
            {f.node}
          </div>
        );
      })}

      {/* Left column */}
      <div style={{ position: "absolute", left: 120, top: 250 }}>
        <Kicker text="Drop it in" at={2} />
        <div style={{ marginTop: 24 }}>
          {["Links.", "Pictures.", "Files.", "Notes."].map((w, i) => (
            <Words key={w} text={w} at={cues[i] - 3} size={112} color={ink} />
          ))}
        </div>
        <div style={{ display: "flex", gap: 18, marginTop: 40 }}>
          <Keycap label="⌘" sub="command" at={copyAt - 4} press={copyAt + 4} width={120} />
          <Keycap label="C" at={copyAt} press={copyAt + 4} width={120} />
        </div>
      </div>

      {/* The "you copied" banner */}
      <div
        style={{
          position: "absolute",
          left: WIN.x + 150,
          top: 70,
          transform: `translateY(${(1 - toast) * -120}px)`,
          opacity: Math.min(1, toast * 2),
          display: "flex",
          alignItems: "center",
          gap: 22,
          padding: "18px 18px 18px 30px",
          borderRadius: 22,
          background: ink,
          color: "#fff",
          fontFamily,
          fontSize: 30,
          fontWeight: 600,
          boxShadow: "0 20px 50px rgba(0,0,0,0.3)",
        }}
      >
        <span style={{ opacity: 0.6 }}>You copied</span>
        <span>vimeo.com/reel-2026</span>
        <div
          style={{
            padding: "12px 26px",
            borderRadius: 14,
            background: kept ? "#2FA36B" : red,
            transform: `scale(${1 - interpolate(frame - keepAt, [0, 3, 8], [0, 0.1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" })})`,
          }}
        >
          {kept ? "Kept ✓" : "Keep"}
        </div>
      </div>

      {cues.map((c, i) => (
        <Sfx key={i} name="pop" at={c + 8} volume={0.45} />
      ))}
      <Sfx name="click" at={copyAt + 4} volume={0.6} />
      <Sfx name="swish" at={copyAt + 6} volume={0.3} />
      <Sfx name="ding" at={keepAt + 4} volume={0.5} />
    </AbsoluteFill>
  );
};
