import sys, json, soundfile as sf, numpy as np
from kokoro import KPipeline
voice, speed, out = sys.argv[1], float(sys.argv[2]), sys.argv[3]
lines = json.load(open('lines.json'))
p = KPipeline(lang_code='a', repo_id='hexgrad/Kokoro-82M')
import os; os.makedirs(out, exist_ok=True)
for i,(t,txt) in enumerate(lines):
    chunks=[a for _,_,a in p(txt, voice=voice, speed=speed)]
    a=np.concatenate([c.numpy() for c in chunks])
    sf.write(f'{out}/{i:02d}.wav', a, 24000, subtype='PCM_24')
    print(i, t, round(len(a)/24000,2), txt)
