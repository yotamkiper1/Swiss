import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Kicker, LinkIcon, Note, Picture, TrafficLights, Wallpaper, Words } from "../components";
import { fontFamily, ink, pop, shadow, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "The Frame is a free canvas, floating above every app."

const P = { x: 640, y: 110, w: 1190, h: 740 };

export const Frame: React.FC = () => {
  const frame = useCurrentFrame();
  const panelAt = cue("frame", "The Frame", -6);
  const panel = pop(frame, panelAt, 15, 0.9);
  const drops = [cue("frame", "The Frame", 4), cue("frame", "free canvas"), cue("frame", "floating"), cue("frame", "every app")];
  const zoom = interpolate(frame, [0, 170], [1.04, 1]);

  const item = (i: number, x: number, y: number, rot: number, node: React.ReactNode) => {
    const p = pop(frame, drops[i], 12, 0.7);
    if (frame < drops[i]) return null;
    const float = Math.sin((frame + i * 20) / 22) * 5;
    return (
      <div
        key={i}
        style={{
          position: "absolute",
          left: x,
          top: y + float + (1 - p) * -80,
          transform: `rotate(${rot}deg) scale(${1.25 - p * 0.25})`,
          opacity: Math.min(1, p * 2),
        }}
      >
        {node}
      </div>
    );
  };

  return (
    <AbsoluteFill style={{ overflow: "hidden" }}>
      <AbsoluteFill style={{ transform: `scale(${zoom})` }}>
        <Wallpaper dim={0.25} />
        {/* Other apps, behind */}
        <AppWindow x={-60} y={160} w={760} h={560} title="Mail" />
        <AppWindow x={1240} y={520} w={760} h={520} title="Figma" />
        <AppWindow x={380} y={600} w={700} h={440} title="Safari" />
      </AbsoluteFill>
      <AbsoluteFill style={{ background: "linear-gradient(90deg, rgba(12,9,8,0.75) 0%, rgba(12,9,8,0.45) 30%, rgba(12,9,8,0) 45%)" }} />

      {/* The Frame */}
      <div
        style={{
          position: "absolute",
          left: P.x,
          top: P.y,
          width: P.w,
          height: P.h,
          borderRadius: 28,
          overflow: "hidden",
          background: "rgba(246,243,238,0.97)",
          backgroundImage: "radial-gradient(rgba(21,18,16,0.18) 1.6px, transparent 1.6px)",
          backgroundSize: "30px 30px",
          boxShadow: `${shadow}, 0 0 0 1.5px rgba(255,255,255,0.7)`,
          transform: `translateY(${(1 - panel) * 80}px) scale(${0.9 + panel * 0.1})`,
          opacity: Math.min(1, panel * 2),
        }}
      >
        <div style={{ height: 62, display: "flex", alignItems: "center", padding: "0 24px", gap: 24, background: "rgba(255,255,255,0.6)", borderBottom: "1px solid rgba(0,0,0,0.08)" }}>
          <TrafficLights size={8} />
          <div style={{ fontFamily, fontWeight: 700, fontSize: 22, color: ink }}>Frame</div>
          <div style={{ flex: 1 }} />
          <div style={{ fontFamily, fontWeight: 600, fontSize: 20, color: "#6E6A65" }}>100%</div>
        </div>
        {item(0, 70, 120, -3, <Picture w={420} h={300} g={0} label="Sonoma reference" />)}
        {item(1, 560, 150, 3, <Note text="Open on the blue poster. Slow push in, cut on the bass hit." w={330} size={25} />)}
        {item(2, 880, 120, -2, <LinkCard />)}
        {item(3, 560, 430, 4, <Picture w={300} h={220} g={2} label="Poster draft — blue" />)}
      </div>

      {/* Words, left */}
      <div style={{ position: "absolute", left: 90, top: 330, width: 540, textShadow: "0 4px 30px rgba(0,0,0,0.35)" }}>
        <Kicker text="The Frame" at={panelAt} color="#fff" />
        <Words text="A free canvas," at={drops[1] - 4} size={70} color="#fff" style={{ marginTop: 20 }} />
        <Words text="above every app." at={drops[2]} size={70} color="#fff" />
      </div>

      <Sfx name="swish" at={panelAt} volume={0.35} />
      {drops.map((d, i) => (
        <Sfx key={i} name="pop" at={d + 4} volume={0.4} />
      ))}
    </AbsoluteFill>
  );
};

const AppWindow: React.FC<{ x: number; y: number; w: number; h: number; title: string }> = ({ x, y, w, h, title }) => (
  <div
    style={{
      position: "absolute",
      left: x,
      top: y,
      width: w,
      height: h,
      borderRadius: 18,
      background: "rgba(250,250,250,0.85)",
      boxShadow: "0 30px 60px rgba(0,0,0,0.3)",
      overflow: "hidden",
      filter: "blur(1.5px)",
    }}
  >
    <div style={{ height: 50, display: "flex", alignItems: "center", gap: 18, padding: "0 18px", background: "#ECECEC" }}>
      <TrafficLights size={7} />
      <span style={{ fontFamily, fontSize: 18, fontWeight: 600, color: "#555" }}>{title}</span>
    </div>
    {Array.from({ length: 7 }, (_, i) => (
      <div key={i} style={{ margin: "22px 28px 0", height: 16, width: `${50 + ((i * 37) % 45)}%`, borderRadius: 8, background: "#DADADA" }} />
    ))}
  </div>
);

const LinkCard: React.FC = () => (
  <div style={{ width: 280, borderRadius: 18, overflow: "hidden", background: "#fff", boxShadow: shadow, fontFamily }}>
    <div style={{ height: 150, background: "linear-gradient(135deg, #1C1F6B, #3D6BF0 60%, #6FD3FF)", display: "flex", alignItems: "center", justifyContent: "center" }}>
      <div style={{ width: 64, height: 64, borderRadius: 32, background: "rgba(0,0,0,0.55)", display: "flex", alignItems: "center", justifyContent: "center" }}>
        <div style={{ width: 0, height: 0, borderLeft: "22px solid #fff", borderTop: "14px solid transparent", borderBottom: "14px solid transparent", marginLeft: 6 }} />
      </div>
    </div>
    <div style={{ padding: "14px 18px 18px" }}>
      <div style={{ fontSize: 22, fontWeight: 700, color: ink }}>Title sequence ideas</div>
      <div style={{ display: "flex", alignItems: "center", gap: 8, fontSize: 18, color: "#6E6A65", marginTop: 6 }}>
        <LinkIcon size={18} color="#6E6A65" /> vimeo.com
      </div>
    </div>
  </div>
);
