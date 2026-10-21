# Final line: impose a falling, resolved contour on "moving" (Praat overlap-add pitch resynthesis).
import parselmouth, numpy as np, sys
from parselmouth.praat import call
src, out, pts = sys.argv[1], sys.argv[2], eval(sys.argv[3])   # pts: [(t, Hz), ...] over "moving"
snd = parselmouth.Sound(src)
man = call(snd, "To Manipulation", 0.01, 100, 500)
tier = call(man, "Extract pitch tier")
call(tier, "Remove points between", pts[0][0] - 0.005, pts[-1][0] + 0.2)
for t, f in pts: call(tier, "Add point", t, f)
call([tier, man], "Replace pitch tier")
res = call(man, "Get resynthesis (overlap-add)")
res.save(out, "WAV")
p = res.to_pitch(time_step=0.01, pitch_floor=120, pitch_ceiling=450); f = p.selected_array['frequency']; t = p.xs()
print(' '.join(f'{np.median(f[(t>=b)&(t<b+0.1)&(f>0)]):.0f}' if ((t>=b)&(t<b+0.1)&(f>0)).any() else '.' for b in np.arange(0, res.duration, 0.1)))
