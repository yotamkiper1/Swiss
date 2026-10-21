"""Voice-over: reads src/scenes.json with Piper and writes public/audio/vo/<id>.wav and src/timing.json.

Usage: python3 scripts/voice.py <voice.onnx> [piper executable]
"""
import json, os, subprocess, sys, wave

here = os.path.dirname(os.path.abspath(__file__))
root = os.path.dirname(here)
model = sys.argv[1]
piper = sys.argv[2] if len(sys.argv) > 2 else "piper"
out = os.path.join(root, "public", "audio", "vo")
os.makedirs(out, exist_ok=True)

timing = {}
for item in json.load(open(os.path.join(root, "src", "scenes.json")))["scenes"]:
    path = os.path.join(out, f"{item['id']}.wav")
    subprocess.run([piper, "-m", model, "-f", path, "--length-scale", "0.97", "--sentence-silence", "0.25"],
                   input=item["line"].encode(), check=True, capture_output=True)
    with wave.open(path) as w:
        timing[item["id"]] = round(w.getnframes() / w.getframerate(), 3)
    print(f"{item['id']:8} {timing[item['id']]:5.2f}s  {item['line']}")

json.dump(timing, open(os.path.join(root, "src", "timing.json"), "w"), indent=2)
