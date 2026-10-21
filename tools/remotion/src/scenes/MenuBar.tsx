import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { Icon, Keycap, Kicker, Wallpaper, Words } from "../components";
import { fontFamily, pop, shadow, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "It lives in your menu bar." ⌥Space, and the pop-up drops from the icon.

const ICON_X = 1530;

export const MenuBar: React.FC = () => {
  const frame = useCurrentFrame();
  const keysAt = cue("menubar", "Press", -6);
  const press = cue("menubar", "Space", 2);
  const drop = pop(frame, press + 2, 14, 0.8);
  const zoom = interpolate(frame, [0, 200], [1.06, 1]);
  const lit = frame >= press && frame < press + 200;

  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `scale(${zoom})`, transformOrigin: "80% 0%" }}>
        <Wallpaper />
        {/* The pop-up */}
        <div
          style={{
            position: "absolute",
            left: ICON_X - 330,
            top: 58,
            width: 528,
            height: 704,
            borderRadius: 22,
            overflow: "hidden",
            boxShadow: shadow,
            opacity: Math.min(1, drop * 2),
            transform: `translateY(${(1 - drop) * -60}px) scale(${0.85 + drop * 0.15})`,
            transformOrigin: "62% 0%",
          }}
        >
          <Img src={staticFile("shots/01-popup.png")} style={{ width: "100%", height: "100%" }} />
        </div>
      </AbsoluteFill>

      {/* The menu bar stays put while the camera moves */}
      <div
        style={{
          position: "absolute",
          left: 0,
          right: 0,
          top: 0,
          height: 46,
          background: "rgba(255,255,255,0.32)",
          backdropFilter: "blur(20px)",
          display: "flex",
          alignItems: "center",
          padding: "0 28px",
          fontFamily,
          fontSize: 21,
          color: "#151210",
          gap: 30,
        }}
      >
        <b>Finder</b>
        <span>File</span>
        <span>Edit</span>
        <span>View</span>
        <span>Go</span>
        <span>Window</span>
        <span>Help</span>
        <div style={{ flex: 1 }} />
        <div
          style={{
            position: "absolute",
            left: ICON_X - 24,
            top: 5,
            width: 48,
            height: 36,
            borderRadius: 8,
            background: lit ? "rgba(255,255,255,0.55)" : "transparent",
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
          }}
        >
          <Icon size={34} tile={false} />
        </div>
        <span style={{ marginLeft: 0 }}>
          <Battery />
        </span>
        <span>Wed 21 Oct 9:41</span>
      </div>


      {/* Words, left */}
      <div style={{ position: "absolute", left: 130, top: 330, textShadow: "0 4px 30px rgba(0,0,0,0.25)" }}>
        <Kicker text="Lives in your menu bar" at={4} color="#fff" />
        <Words text="One key." at={10} size={150} color="#fff" style={{ marginTop: 20 }} />
        <Words text="There it is." at={press} size={150} color="#fff" />
      </div>

      {/* Keys */}
      <div style={{ position: "absolute", left: 130, top: 780, display: "flex", gap: 22, opacity: 1 - soft(frame, press + 40) * 0.0 }}>
        <Keycap label="⌥" sub="option" at={keysAt} press={press} />
        <Keycap label="space" at={keysAt + 4} press={press} width={380} />
      </div>

      <Sfx name="click" at={press} volume={0.8} />
      <Sfx name="swish" at={press + 2} volume={0.4} />
    </AbsoluteFill>
  );
};

const Battery: React.FC = () => (
  <svg width="34" height="18" viewBox="0 0 34 18" style={{ verticalAlign: "middle" }}>
    <rect x="1" y="1" width="28" height="16" rx="4" fill="none" stroke="#151210" strokeWidth="1.6" opacity="0.6" />
    <rect x="4" y="4" width="20" height="10" rx="2" fill="#151210" />
    <rect x="30.5" y="6" width="2.5" height="6" rx="1" fill="#151210" opacity="0.6" />
  </svg>
);
