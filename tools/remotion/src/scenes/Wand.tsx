import React from "react";
import { AbsoluteFill, interpolate, random, useCurrentFrame } from "remotion";
import { Folder, LinkIcon, Sparkle, Words, gradients } from "../components";
import { fontFamily, ink, pop, red, soft, yellow } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "Total mess? Wave the wand. Poof. Sorted."

const folders = [
  { label: "PhotoBook", badge: "#E0443A", x: 540 },
  { label: "Linker", badge: "#2FA36B", x: 820 },
  { label: "Notepad", badge: "#F0A23A", x: 1100 },
  { label: "Files", badge: "#6E6A65", x: 1380 },
];
const FOLDER_Y = 800;
const N = 24;

export const Wand: React.FC = () => {
  const frame = useCurrentFrame();
  const wave = cue("wand", "Wave", -2);
  const poof = cue("wand", "Poof", -2);
  const sorted = cue("wand", "Sorted", -2);

  const swing = interpolate(frame, [wave, wave + 16], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const wandIn = pop(frame, wave - 8, 12);
  const wandOut = soft(frame, poof + 8);
  const flash = interpolate(frame - poof, [0, 2, 12], [0, 0.7, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  const foldersIn = pop(frame, poof - 4, 12);

  const counts = [0, 0, 0, 0];
  const cards = Array.from({ length: N }, (_, i) => {
    const kind = i % 4;
    const appear = pop(frame, 2 + i * 0.8, 12);
    const sx = 160 + random(`wx${i}`) * 1560;
    const sy = 230 + random(`wy${i}`) * 420;
    const rot = (random(`wr${i}`) - 0.5) * 60;
    const jitter = frame < poof ? Math.sin(frame * 0.9 + i) * 3 : 0;
    const go = soft(frame, poof + i * 0.7);
    if (go > 0.92) counts[kind]++;
    const tx = folders[kind].x;
    const ty = FOLDER_Y - 40;
    const x = interpolate(go, [0, 1], [sx, tx]);
    const y = interpolate(go, [0, 1], [sy, ty]) - Math.sin(go * Math.PI) * 140;
    const s = interpolate(go, [0, 0.8, 1], [1, 0.6, 0.2]) * appear;
    const o = go > 0.97 ? 0 : 1;
    return (
      <div
        key={i}
        style={{ position: "absolute", left: x + jitter, top: y, opacity: o, transform: `translate(-50%, -50%) rotate(${rot * (1 - go)}deg) scale(${s})` }}
      >
        <Card kind={kind} i={i} />
      </div>
    );
  });

  // Sparkles trail the tip of the wand.
  const sparkles = Array.from({ length: 14 }, (_, i) => {
    const born = wave + i * 1.4;
    const age = frame - born;
    if (age < 0 || age > 22) return null;
    const a = interpolate((born - wave) / 16, [0, 1], [-50, 50]);
    const tipX = 960 + Math.sin((a * Math.PI) / 180) * 420;
    const tipY = 640 - Math.cos((a * Math.PI) / 180) * 420;
    const life = age / 22;
    return (
      <div
        key={i}
        style={{
          position: "absolute",
          left: tipX + (random(`sx${i}`) - 0.5) * 80 * life,
          top: tipY + life * 60,
          opacity: 1 - life,
          transform: `translate(-50%, -50%) scale(${1 - life * 0.6})`,
        }}
      >
        <Sparkle size={30 + random(`ss${i}`) * 30} color={i % 3 === 0 ? yellow : "#fff"} rotate={age * 8} />
      </div>
    );
  });

  const wandAngle = interpolate(swing, [0, 1], [-50, 50], {}) ;

  return (
    <AbsoluteFill style={{ background: red, overflow: "hidden" }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 40%, #EC5A4F 0%, #C9352C 80%)" }} />
      {cards}

      {/* Folders */}
      <div style={{ position: "absolute", left: 0, top: FOLDER_Y - 100, width: "100%" }}>
        {folders.map((f, i) => {
          const bump = counts[i] > 0 ? 1 + 0.06 * Math.sin(frame * 0.8) * Math.max(0, 1 - (frame - poof - 20) / 20) : 1;
          return (
            <div key={f.label} style={{ position: "absolute", left: f.x, transform: `translateX(-50%) scale(${foldersIn * bump})`, opacity: foldersIn }}>
              <Folder label={f.label} badge={f.badge} size={180} count={counts[i] || undefined} />
            </div>
          );
        })}
      </div>

      {/* The wand */}
      {frame >= wave - 8 && wandOut < 0.99 && (
        <div
          style={{
            position: "absolute",
            left: 960,
            top: 640,
            width: 0,
            height: 0,
            transform: `rotate(${wandAngle}deg) scale(${wandIn * (1 - wandOut)})`,
          }}
        >
          <div style={{ position: "absolute", left: -9, top: -420, width: 18, height: 420, borderRadius: 9, background: `linear-gradient(0deg, ${ink} 0 22%, #fff 22% 78%, ${ink} 78%)` }} />
          <div style={{ position: "absolute", left: -40, top: -470 }}>
            <Sparkle size={80} color={yellow} rotate={frame * 6} />
          </div>
        </div>
      )}
      {sparkles}

      <AbsoluteFill style={{ background: "#fff", opacity: flash }} />

      {/* Headline */}
      <div style={{ position: "absolute", top: 80, width: "100%", display: "flex", justifyContent: "center", textAlign: "center" }}>
        {frame < sorted ? (
          <Words text={frame < poof ? "Total mess?" : "Poof."} at={frame < poof ? 4 : poof} size={140} color="#fff" />
        ) : (
          <Words text="Sorted." at={sorted} size={140} color="#fff" />
        )}
      </div>

      <Sfx name="rattle" at={2} volume={0.35} />
      <Sfx name="sparkle" at={wave} volume={0.55} />
      <Sfx name="poof" at={poof} volume={0.6} />
      <Sfx name="ding" at={sorted} volume={0.5} />
    </AbsoluteFill>
  );
};

const Card: React.FC<{ kind: number; i: number }> = ({ kind, i }) => {
  const base: React.CSSProperties = { boxShadow: "0 14px 30px rgba(60,10,5,0.35)", borderRadius: 14 };
  if (kind === 0) return <div style={{ ...base, width: 150, height: 112, background: gradients[i % gradients.length] }} />;
  if (kind === 1)
    return (
      <div style={{ ...base, display: "flex", alignItems: "center", gap: 12, padding: "12px 20px 12px 12px", borderRadius: 40, background: "#fff", fontFamily, fontWeight: 600, fontSize: 22, color: ink }}>
        <div style={{ width: 38, height: 38, borderRadius: 20, background: "#2FA36B", display: "flex", alignItems: "center", justifyContent: "center" }}>
          <LinkIcon size={22} />
        </div>
        {["figma.com", "are.na", "vimeo.com", "dribbble.com", "youtube.com", "fonts.adobe.com"][i % 6]}
      </div>
    );
  if (kind === 2)
    return (
      <div style={{ ...base, width: 150, height: 120, background: yellow, padding: 16, fontFamily, fontSize: 18, fontWeight: 600, color: "#4A3A10" }}>
        {["Call print shop", "Typeface: GT America?", "Opening: slow push", "Deadline Thu", "Ask about A2", "Blue or orange?"][i % 6]}
      </div>
    );
  return (
    <div style={{ ...base, width: 100, height: 128, background: "#fff", position: "relative" }}>
      <div style={{ position: "absolute", left: 14, right: 14, bottom: 16, height: 26, borderRadius: 6, background: ["#3D6BF0", "#E0443A", "#6E6A65"][i % 3] }} />
    </div>
  );
};
