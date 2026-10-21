import React from "react";
import { AbsoluteFill, interpolate, random, useCurrentFrame } from "remotion";
import { Doc, LinkChip, Window } from "../components";
import { fontFamily, ink, pop, red } from "../theme";
import { cue } from "../timeline";
import { Sfx } from "../Sfx";

// Cold open: everything you ever saved, piling up on a dark desk.

const clutterNames = [
  "IMG_4471.HEIC",
  "untitled folder 3",
  "Notes (copy).txt",
  "moodboard-v3-REAL.png",
  "export (2).zip",
  "draft_old_NEW.key",
  "Screenshot 2026-10-02.png",
  "invoice-final-v2.pdf",
  "ref.webloc",
  "thesis_FINAL_ok.docx",
  "logo-alt-alt.svg",
  "Untitled 14.txt",
  "IMG_0007 (1).jpg",
  "brief (1) (1).pdf",
  "ideas.rtf",
  "Archive.zip",
  "poster-blue-v9.png",
  "meeting notes?.txt",
];

const exts = ["JPG", "DIR", "TXT", "PNG", "ZIP", "KEY", "PNG", "PDF", "URL", "DOC", "SVG", "TXT", "JPG", "PDF", "RTF", "ZIP", "PNG", "TXT"];
const tints = ["#6E7BF0", "#8E8A85", "#8E8A85", "#2FA36B", "#B08A5A", "#3D6BF0", "#2FA36B", "#E0443A", "#2FA36B", "#3D6BF0", "#F0A23A", "#8E8A85"];

export const Mess: React.FC = () => {
  const frame = useCurrentFrame();
  const tLink = cue("mess", "That link");
  const tShot = cue("mess", "That screenshot");
  const tFile = cue("mess", "final, final");
  const tSaved = cue("mess", "You saved");
  const tWhere = cue("mess", "Somewhere");

  const phrases = [
    { text: "That link.", at: tLink },
    { text: "That screenshot.", at: tShot },
    { text: "final_final_2.pdf", at: tFile },
    { text: "You saved them.", at: tSaved },
    { text: "Somewhere.", at: tWhere },
  ];
  const current = [...phrases].reverse().find((p) => frame >= p.at - 2);

  // The camera drifts in, and shakes a little when it all piles up.
  const zoom = interpolate(frame, [0, 260], [1.0, 1.12]);
  const shake = frame > tWhere ? Math.sin(frame * 2.1) * interpolate(frame, [tWhere, tWhere + 20], [10, 0], { extrapolateRight: "clamp" }) : 0;

  const item = (at: number, x: number, y: number, rot: number, node: React.ReactNode, key: string, scale = 1) => {
    const p = pop(frame, at, 10, 0.6);
    if (frame < at) return null;
    const drift = Math.sin((frame + x) / 30) * 8;
    return (
      <div
        key={key}
        style={{
          position: "absolute",
          left: x,
          top: y + drift,
          transform: `translate(-50%, -50%) rotate(${rot * p}deg) scale(${p * scale})`,
        }}
      >
        {node}
      </div>
    );
  };

  const clutter = clutterNames.map((name, i) => {
    const at = tSaved - 8 + i * 2.2;
    const x = 140 + random(`x${i}`) * 1640;
    const y = 120 + random(`y${i}`) * 700;
    const rot = (random(`r${i}`) - 0.5) * 40;
    return item(at, x, y, rot, <Doc name={name} ext={exts[i]} tint={tints[i % tints.length]} size={84} />, `c${i}`, 0.9);
  });

  return (
    <AbsoluteFill style={{ background: ink, overflow: "hidden" }}>
      <AbsoluteFill style={{ background: "radial-gradient(circle at 50% 40%, #2C2522 0%, #151210 70%)" }} />
      <AbsoluteFill style={{ transform: `scale(${zoom}) translateX(${shake}px)` }}>
        {clutter}
        {item(tLink, 560, 280, -6, <LinkChip url="dribbble.com/shots/2291…" size={34} />, "link")}
        {item(
          tShot,
          1400,
          330,
          7,
          <div style={{ position: "relative", width: 520, height: 397 }}>
            <Window src="16-big-dark.png" width={520} />
          </div>,
          "shot",
        )}
        {item(tFile, 700, 640, -10, <Doc name="final.pdf" size={130} />, "f1")}
        {item(tFile + 8, 960, 610, 4, <Doc name="final_final.pdf" size={130} />, "f2")}
        {item(tFile + 16, 1220, 650, 12, <Doc name="final_final_2.pdf" size={130} />, "f3")}
      </AbsoluteFill>

      {/* The words, low and left */}
      <AbsoluteFill style={{ background: "linear-gradient(0deg, rgba(10,8,7,0.92) 0%, rgba(10,8,7,0) 38%)" }} />
      {current && (
        <div style={{ position: "absolute", left: 120, bottom: 110 }}>
          <Phrase key={current.text} text={current.text} at={current.at} color={current.text === "Somewhere." ? red : "#fff"} />
        </div>
      )}

      <Sfx name="pop" at={tLink} volume={0.5} />
      <Sfx name="pop" at={tShot} volume={0.5} />
      <Sfx name="pop" at={tFile} volume={0.4} />
      <Sfx name="pop" at={tFile + 8} volume={0.4} />
      <Sfx name="pop" at={tFile + 16} volume={0.4} />
      <Sfx name="rattle" at={tSaved - 8} volume={0.45} />
      <Sfx name="thud" at={tWhere} volume={0.6} />
    </AbsoluteFill>
  );
};

const Phrase: React.FC<{ text: string; at: number; color: string }> = ({ text, at, color }) => {
  const frame = useCurrentFrame();
  const p = pop(frame, at - 2, 14, 0.5);
  return (
    <div
      style={{
        fontFamily,
        fontSize: 132,
        fontWeight: 900,
        letterSpacing: -5,
        color,
        transform: `translateY(${(1 - p) * 60}px) scale(${0.9 + p * 0.1})`,
        opacity: Math.min(1, p * 1.5),
        transformOrigin: "left bottom",
      }}
    >
      {text}
    </div>
  );
};
