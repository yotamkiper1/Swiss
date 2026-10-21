import numpy as np, soundfile as sf, parselmouth, os, json
from kokoro import KPipeline
p = KPipeline(lang_code='a', repo_id='hexgrad/Kokoro-82M')
os.makedirs('last', exist_ok=True)
V = {'a': "Swiss. Keep your ideas moving.", 'c': "Swiss! Keep your ideas moving.", 'd': "Swiss... Keep your ideas moving.",
     'g': "Swiss. Keep your ideas, moving.", 'h': "Swiss. Keep your ideas moving. That's it.", 'k': "Keep your ideas moving.", 's': "Swiss."}
res = {}
for key, txt in V.items():
    for sp in (0.85, 0.9, 0.95):
        a = np.concatenate([c.numpy() for _, _, c in p(txt, voice='af_heart', speed=sp)])
        fn = f'last/{key}_{sp}.wav'; sf.write(fn, a, 24000)
        snd = parselmouth.Sound(fn); pi = snd.to_pitch(time_step=0.01, pitch_floor=120, pitch_ceiling=450)
        f = pi.selected_array['frequency']; t = pi.xs(); v = f > 0
        res[f'{key}_{sp}'] = dict(dur=len(a) / 24000, t=t[v].round(2).tolist(), f=f[v].round(0).tolist())
json.dump(res, open('last/pitch.json', 'w'))
