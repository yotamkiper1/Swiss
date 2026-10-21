import React from "react";
import { AbsoluteFill, interpolate, useCurrentFrame } from "remotion";
import { Icon } from "../components";
import { fontFamily, gray, ink, paper, pop, red, soft } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// "Meet Swiss." The knife lands, flicks open, and makes room for its name.

export const Intro: React.FC = () => {
  const frame = useCurrentFrame();
  const land = pop(frame, 4, 11, 0.8);
  const open = pop(frame, 16, 8, 0.6);
  const slide = soft(frame, 30);
  const wordmark = soft(frame, 34);
  const tagAt = cue("intro", "A pocket");
  const ring = interpolate(frame, [18, 44], [0, 1], { extrapolateLeft: "clamp", extrapolateRight: "clamp" });

  const iconSize = 330;
  const iconX = interpolate(slide, [0, 1], [0, -390]);

  return (
    <AbsoluteFill style={{ background: paper, alignItems: "center", justifyContent: "center" }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 45%, #FFFFFF 0%, rgba(255,255,255,0) 60%)" }} />
      <div style={{ position: "absolute", transform: `translate(${iconX}px, -30px)` }}>
        {ring > 0 && ring < 1 && (
          <div
            style={{
              position: "absolute",
              left: iconSize / 2,
              top: iconSize / 2,
              width: iconSize * (1 + ring * 1.2),
              height: iconSize * (1 + ring * 1.2),
              borderRadius: "50%",
              border: `${8 * (1 - ring)}px solid ${red}`,
              opacity: 1 - ring,
              transform: "translate(-50%, -50%)",
            }}
          />
        )}
        <div
          style={{
            transform: `scale(${land}) rotate(${(1 - land) * -25}deg)`,
            filter: "drop-shadow(0 30px 40px rgba(60,30,20,0.25))",
          }}
        >
          <Icon size={iconSize} open={open} />
        </div>
      </div>

      <div style={{ position: "absolute", left: 960 - 390 + iconSize / 2 + 70, top: 540 - 30 - 150, width: 900 }}>
        <div
          style={{
            fontFamily,
            fontSize: 230,
            fontWeight: 900,
            color: ink,
            letterSpacing: -10,
            lineHeight: 1,
            clipPath: `inset(-20% ${(1 - wordmark) * 100}% -20% 0)`,
            transform: `translateX(${(1 - wordmark) * -40}px)`,
          }}
        >
          Swiss
        </div>
        <div
          style={{
            fontFamily,
            fontSize: 50,
            fontWeight: 500,
            color: gray,
            marginTop: 18,
            opacity: soft(frame, tagAt),
            transform: `translateY(${(1 - soft(frame, tagAt)) * 20}px)`,
          }}
        >
          A pocket knife for your <span style={{ color: red, fontWeight: 700 }}>ideas</span>.
        </div>
      </div>

      <Sfx name="thud" at={4} volume={0.35} />
      <Sfx name="click" at={16} volume={0.7} />
      <Sfx name="whoosh" at={30} volume={0.25} />
    </AbsoluteFill>
  );
};
