import React from "react";
import { AbsoluteFill, Img, interpolate, staticFile, useCurrentFrame } from "remotion";
import { blade, fontFamily, gray, ink, paper, pop, red, shadow, yellow } from "./theme";

// MARK: The Swiss icon, drawn as vectors so it stays sharp at any size. `open` swings the blade from closed (0) to open (1).

export const Icon: React.FC<{ size: number; open?: number; tile?: boolean }> = ({ size, open = 1, tile = true }) => (
  <svg width={size} height={size} viewBox="0 0 100 100" style={{ overflow: "visible" }}>
    {tile && (
      <>
        <defs>
          <linearGradient id="tile" x1="0" y1="0" x2="0" y2="1">
            <stop offset="0" stopColor="#FBFAF8" />
            <stop offset="1" stopColor="#ECE9E5" />
          </linearGradient>
        </defs>
        <rect x="2" y="2" width="96" height="96" rx="22" fill="url(#tile)" />
      </>
    )}
    <g transform={`rotate(${(1 - open) * 32} 33 55)`}>
      <path d="M31 56 C 44 44, 62 27, 84 15 C 77 31, 62 48, 45 60 Z" fill={blade} />
    </g>
    <g transform={`rotate(${(1 - open) * -40} 31 50)`}>
      <rect x="22" y="31" width="9" height="21" rx="3" transform="rotate(-38 26 42)" fill={red} />
    </g>
    <rect x="16" y="52" width="66" height="23" rx="11.5" fill={red} />
    <circle cx="69" cy="63.5" r="5.3" fill="#FFF8F2" />
  </svg>
);

// MARK: Type

/** A line of words that rise into place one after another. */
export const Words: React.FC<{
  text: string;
  at: number;
  size: number;
  color?: string;
  weight?: number;
  stagger?: number;
  style?: React.CSSProperties;
  highlight?: string[];
  highlightColor?: string;
}> = ({ text, at, size, color = ink, weight = 800, stagger = 3, style, highlight = [], highlightColor = red }) => {
  const frame = useCurrentFrame();
  return (
    <div style={{ fontFamily, fontSize: size, fontWeight: weight, color, letterSpacing: -size * 0.035, lineHeight: 1.08, ...style }}>
      {text.split(" ").map((w, i) => {
        const p = pop(frame, at + i * stagger, 15, 0.6);
        return (
          <span key={i} style={{ display: "inline-block", overflow: "hidden", verticalAlign: "top", paddingBottom: size * 0.12, marginBottom: -size * 0.12 }}>
            <span
              style={{
                display: "inline-block",
                transform: `translateY(${(1 - p) * 110}%) rotate(${(1 - p) * 6}deg)`,
                opacity: Math.min(1, p * 2),
                color: highlight.includes(w) ? highlightColor : undefined,
              }}
            >
              {w}
              {i < text.split(" ").length - 1 ? " " : ""}
            </span>
          </span>
        );
      })}
    </div>
  );
};

export const Kicker: React.FC<{ text: string; at: number; color?: string; style?: React.CSSProperties }> = ({ text, at, color = red, style }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at, 20);
  return (
    <div
      style={{
        fontFamily,
        fontSize: 26,
        fontWeight: 700,
        letterSpacing: 6,
        textTransform: "uppercase",
        color,
        opacity: p,
        transform: `translateX(${(1 - p) * -30}px)`,
        display: "flex",
        alignItems: "center",
        gap: 16,
        ...style,
      }}
    >
      <span style={{ width: 44 * p, height: 4, borderRadius: 2, background: color }} />
      {text}
    </div>
  );
};

// MARK: Keys

export const Keycap: React.FC<{ label: string; sub?: string; at: number; press?: number; width?: number; dark?: boolean }> = ({
  label,
  sub,
  at,
  press = -1,
  width = 130,
  dark = false,
}) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at, 11);
  const down = press >= 0 ? interpolate(frame - press, [0, 3, 10], [0, 1, 0], { extrapolateLeft: "clamp", extrapolateRight: "clamp" }) : 0;
  const face = dark ? "#2A2522" : "#FFFFFF";
  const edge = dark ? "#0B0908" : "#CFC9C2";
  return (
    <div
      style={{
        width,
        height: 120,
        borderRadius: 22,
        background: face,
        boxShadow: `0 ${10 - down * 8}px 0 ${edge}, 0 ${24 - down * 14}px 40px rgba(0,0,0,0.25)`,
        transform: `translateY(${down * 8}px) scale(${p})`,
        opacity: Math.min(1, p * 2),
        display: "flex",
        flexDirection: "column",
        alignItems: "center",
        justifyContent: "center",
        fontFamily,
        color: dark ? "#fff" : ink,
      }}
    >
      <div style={{ fontSize: sub ? 46 : 40, fontWeight: 600, lineHeight: 1 }}>{label}</div>
      {sub && <div style={{ fontSize: 20, fontWeight: 500, color: gray, marginTop: 8 }}>{sub}</div>}
    </div>
  );
};

// MARK: Windows and wallpaper

export const Wallpaper: React.FC<{ dim?: number }> = ({ dim = 0 }) => (
  <AbsoluteFill
    style={{
      background: [
        "radial-gradient(ellipse 70% 60% at 15% 85%, #B8E04A 0%, rgba(184,224,74,0) 70%)",
        "radial-gradient(ellipse 60% 50% at 40% 60%, #3E9A5A 0%, rgba(62,154,90,0) 70%)",
        "radial-gradient(ellipse 70% 45% at 30% 30%, #F0645A 0%, rgba(240,100,90,0) 70%)",
        "radial-gradient(ellipse 80% 60% at 85% 20%, #7A86F0 0%, rgba(122,134,240,0) 70%)",
        "linear-gradient(160deg, #9AA6F5 0%, #E98572 45%, #3F8C4E 75%, #C4E852 100%)",
      ].join(","),
    }}
  >
    {dim > 0 && <AbsoluteFill style={{ background: `rgba(10,8,7,${dim})` }} />}
  </AbsoluteFill>
);

/** A screenshot in a macOS-style window frame. */
export const Window: React.FC<{ src: string; width: number; style?: React.CSSProperties; children?: React.ReactNode; aspect?: number }> = ({
  src,
  width,
  style,
  children,
  aspect = 1160 / 1520,
}) => (
  <div style={{ position: "absolute", width, height: width * aspect, borderRadius: width * 0.018, overflow: "hidden", boxShadow: shadow, background: "#C8C8C8", ...style }}>
    <Img src={staticFile(`shots/${src}`)} style={{ width: "100%", height: "100%", display: "block" }} />
    <TrafficLights size={width * 0.0105} style={{ position: "absolute", left: width * 0.018, top: width * 0.016 }} />
    {children}
  </div>
);

export const TrafficLights: React.FC<{ size: number; style?: React.CSSProperties }> = ({ size, style }) => (
  <div style={{ display: "flex", gap: size * 0.75, ...style }}>
    {["#FF5F57", "#FEBC2E", "#28C840"].map((c) => (
      <div key={c} style={{ width: size * 2, height: size * 2, borderRadius: size, background: c, boxShadow: "inset 0 0 0 0.5px rgba(0,0,0,0.2)" }} />
    ))}
  </div>
);

// MARK: Things people save

export const gradients = [
  "linear-gradient(150deg, #8F9BFF 0%, #F07C6A 45%, #3F9B57 72%, #D5F25A 100%)",
  "linear-gradient(135deg, #FFB46B 0%, #E0443A 55%, #6E1E3A 100%)",
  "linear-gradient(140deg, #6FD3FF 0%, #3D6BF0 55%, #1C1F6B 100%)",
  "linear-gradient(135deg, #C9F27A 0%, #3FA36B 60%, #0F4A3A 100%)",
  "linear-gradient(135deg, #FFD1E8 0%, #C58BF2 55%, #5A3FB0 100%)",
];

export const Picture: React.FC<{ w: number; h: number; g?: number; label?: string }> = ({ w, h, g = 0, label }) => (
  <div style={{ width: w, height: h, borderRadius: 18, background: gradients[g % gradients.length], boxShadow: shadow, position: "relative", overflow: "hidden" }}>
    <div style={{ position: "absolute", inset: 0, background: "radial-gradient(circle at 30% 25%, rgba(255,255,255,0.35), rgba(255,255,255,0) 50%)" }} />
    {label && (
      <div style={{ position: "absolute", left: 14, bottom: 12, fontFamily, fontSize: 18, fontWeight: 600, color: "rgba(255,255,255,0.92)" }}>{label}</div>
    )}
  </div>
);

export const LinkIcon: React.FC<{ size: number; color?: string }> = ({ size, color = "#fff" }) => (
  <svg width={size} height={size} viewBox="0 0 24 24" fill="none" stroke={color} strokeWidth={2.4} strokeLinecap="round">
    <path d="M10 14a4.5 4.5 0 0 0 6.4 0l3-3a4.5 4.5 0 0 0-6.4-6.4l-1.2 1.2" />
    <path d="M14 10a4.5 4.5 0 0 0-6.4 0l-3 3a4.5 4.5 0 0 0 6.4 6.4l1.2-1.2" />
  </svg>
);

export const LinkChip: React.FC<{ url: string; size?: number }> = ({ url, size = 30 }) => (
  <div
    style={{
      display: "flex",
      alignItems: "center",
      gap: size * 0.5,
      padding: `${size * 0.5}px ${size * 0.9}px ${size * 0.5}px ${size * 0.5}px`,
      borderRadius: size * 2,
      background: "#fff",
      boxShadow: shadow,
      fontFamily,
      fontSize: size,
      fontWeight: 600,
      color: ink,
      whiteSpace: "nowrap",
    }}
  >
    <div style={{ width: size * 1.6, height: size * 1.6, borderRadius: size, background: "#2FA36B", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <LinkIcon size={size} />
    </div>
    {url}
  </div>
);

export const Doc: React.FC<{ name: string; tint?: string; size?: number; light?: boolean; ext?: string }> = ({ name, tint = red, size = 120, light = true, ext = "PDF" }) => (
  <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: size * 0.1, width: size * 2.2 }}>
    <div style={{ width: size * 0.8, height: size, position: "relative", filter: "drop-shadow(0 12px 18px rgba(0,0,0,0.3))" }}>
      <svg width={size * 0.8} height={size} viewBox="0 0 80 100">
        <path d="M4 0 H56 L80 24 V96 a4 4 0 0 1 -4 4 H4 a4 4 0 0 1 -4 -4 V4 a4 4 0 0 1 4 -4Z" fill="#FFFFFF" />
        <path d="M56 0 V20 a4 4 0 0 0 4 4 H80 Z" fill="#DAD5CF" />
        <rect x="12" y="66" width="56" height="20" rx="4" fill={tint} />
        <text x="40" y="81" textAnchor="middle" fontFamily={fontFamily} fontWeight={800} fontSize="13" fill="#fff">
          {ext}
        </text>
      </svg>
    </div>
    <div
      style={{
        fontFamily,
        fontSize: size * 0.2,
        fontWeight: 600,
        color: light ? "#fff" : ink,
        textAlign: "center",
        padding: `${size * 0.03}px ${size * 0.1}px`,
        borderRadius: 8,
        whiteSpace: "nowrap",
      }}
    >
      {name}
    </div>
  </div>
);

export const Note: React.FC<{ text: string; w?: number; size?: number }> = ({ text, w = 300, size = 26 }) => (
  <div style={{ width: w, padding: size * 0.8, borderRadius: 16, background: yellow, boxShadow: shadow, fontFamily, fontSize: size, fontWeight: 600, color: "#4A3A10", lineHeight: 1.25 }}>
    {text}
  </div>
);

/** A Finder-style folder with a colored badge and a label. */
export const Folder: React.FC<{ label: string; badge: string; size?: number; count?: number; labelColor?: string }> = ({
  label,
  badge,
  size = 200,
  count,
  labelColor = "#fff",
}) => (
  <div style={{ display: "flex", flexDirection: "column", alignItems: "center", gap: size * 0.08 }}>
    <div style={{ position: "relative", width: size, height: size * 0.78 }}>
      <svg width={size} height={size * 0.78} viewBox="0 0 100 78" style={{ filter: "drop-shadow(0 10px 16px rgba(0,0,0,0.25))" }}>
        <path d="M4 6 a4 4 0 0 1 4 -4 H34 l8 8 H92 a4 4 0 0 1 4 4 V72 a4 4 0 0 1 -4 4 H8 a4 4 0 0 1 -4 -4Z" fill="#D9D4CD" />
        <path d="M4 18 a4 4 0 0 1 4 -4 H92 a4 4 0 0 1 4 4 V72 a4 4 0 0 1 -4 4 H8 a4 4 0 0 1 -4 -4Z" fill="#F3F0EB" />
      </svg>
      <div
        style={{
          position: "absolute",
          right: size * 0.02,
          bottom: size * 0.02,
          width: size * 0.26,
          height: size * 0.26,
          borderRadius: size,
          background: badge,
          border: `${size * 0.025}px solid #fff`,
        }}
      />
      {count !== undefined && (
        <div
          style={{
            position: "absolute",
            right: -size * 0.04,
            top: -size * 0.02,
            minWidth: size * 0.24,
            height: size * 0.24,
            borderRadius: size,
            background: ink,
            color: "#fff",
            fontFamily,
            fontWeight: 700,
            fontSize: size * 0.14,
            display: "flex",
            alignItems: "center",
            justifyContent: "center",
            padding: `0 ${size * 0.05}px`,
          }}
        >
          {count}
        </div>
      )}
    </div>
    <div style={{ fontFamily, fontWeight: 700, fontSize: size * 0.16, color: labelColor }}>{label}</div>
  </div>
);

export const Sparkle: React.FC<{ size: number; color?: string; rotate?: number }> = ({ size, color = "#fff", rotate = 0 }) => (
  <svg width={size} height={size} viewBox="-10 -10 20 20" style={{ transform: `rotate(${rotate}deg)` }}>
    <path d="M0 -10 L2 -2 L10 0 L2 2 L0 10 L-2 2 L-10 0 L-2 -2Z" fill={color} />
  </svg>
);

export const Cursor: React.FC<{ x: number; y: number; scale?: number; click?: number }> = ({ x, y, scale = 1.6, click = 0 }) => (
  <svg
    width={24 * scale}
    height={30 * scale}
    viewBox="0 0 24 30"
    style={{ position: "absolute", left: x, top: y, transform: `scale(${1 - click * 0.15})`, transformOrigin: "0 0", filter: "drop-shadow(0 3px 4px rgba(0,0,0,0.4))" }}
  >
    <path d="M1 1 L1 23 L7 17.5 L11 27 L15 25.3 L11 16 L19 16Z" fill="#fff" stroke="#000" strokeWidth={1.4} strokeLinejoin="round" />
  </svg>
);

export { paper, ink };
