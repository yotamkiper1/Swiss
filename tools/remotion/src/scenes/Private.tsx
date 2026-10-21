import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { fontFamily, ink, pop, red } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "No account. No cloud. Everything stays on your Mac."

export const Private: React.FC = () => {
  const frame = useCurrentFrame();
  const lines = [
    { text: "No account.", at: cue("private", "No account", -3), strike: true },
    { text: "No cloud.", at: cue("private", "No cloud", -3), strike: true },
    { text: "Everything stays on your Mac.", at: cue("private", "Everything", -3), strike: false },
  ];

  return (
    <AbsoluteFill style={{ background: ink, justifyContent: "center", paddingLeft: 170 }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 20% 50%, #2C2522 0%, #151210 70%)" }} />
      <Lock at={lines[2].at + 6} />
      <div style={{ position: "relative", display: "flex", flexDirection: "column", gap: 30 }}>
        {lines.map((l, i) => {
          const p = pop(frame, l.at, 12, 0.6);
          const strike = l.strike ? interpolate(frame - l.at - 14, [0, 8], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 0;
          const dim = l.strike && i < lines.length && frame > lines[i + 1].at ? 0.35 : 1;
          return (
            <div
              key={l.text}
              style={{
                position: "relative",
                alignSelf: "flex-start",
                fontFamily,
                fontWeight: 900,
                fontSize: i === 2 ? 112 : 132,
                letterSpacing: -5,
                color: i === 2 ? "#fff" : "#fff",
                opacity: Math.min(1, p * 2) * dim,
                transform: `translateY(${(1 - p) * 80}px) scale(${1.3 - p * 0.3})`,
                transformOrigin: "left center",
              }}
            >
              {i === 2 ? (
                <>
                  Everything stays on <span style={{ color: red }}>your Mac.</span>
                </>
              ) : (
                l.text
              )}
              {l.strike && (
                <div style={{ position: "absolute", left: -10, top: "54%", height: 14, width: `calc(${strike * 100}% + 20px)`, background: red, borderRadius: 7 }} />
              )}
            </div>
          );
        })}
      </div>
      {lines.map((l, i) => (
        <Sfx key={i} name="thud" at={l.at + 2} volume={0.45} />
      ))}
      <Sfx name="swish" at={lines[0].at + 14} volume={0.25} />
      <Sfx name="swish" at={lines[1].at + 14} volume={0.25} />
    </AbsoluteFill>
  );
};

const Lock: React.FC<{ at: number }> = ({ at }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at, 10);
  const shut = interpolate(frame - at - 10, [0, 6], [26, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });
  return (
    <div style={{ position: "absolute", right: 170, top: 330, transform: `scale(${p})`, opacity: Math.min(1, p * 2) }}>
      <svg width="260" height="320" viewBox="0 0 26 32">
        <path d={`M6 ${14 - shut / 4} V9 a7 7 0 0 1 14 0 V${14 - shut / 4}`} fill="none" stroke="#fff" strokeWidth="3" strokeLinecap="round" transform={`translate(0 ${-shut / 4})`} />
        <rect x="2" y="13" width="22" height="18" rx="4" fill={red} />
        <circle cx="13" cy="21" r="2.4" fill="#fff" />
        <rect x="12" y="21" width="2" height="5" rx="1" fill="#fff" />
      </svg>
      <Sfx name="click" at={at + 16} volume={0.6} />
    </div>
  );
};
