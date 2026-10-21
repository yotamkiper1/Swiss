import sys, json, numpy as np, soundfile as sf, pyloudnorm as pyln
from scipy.signal import resample_poly, butter, sosfilt
take, sfxpath, out = sys.argv[1], sys.argv[2], sys.argv[3]
SR=48000; N=40*SR
lines=json.load(open('lines.json'))
sfx,sr=sf.read(sfxpath); assert sr==SR and len(sfx)==N
meter=pyln.Meter(SR)
hp=butter(2,75,'hp',fs=SR,output='sos')
vo=np.zeros(N); act=np.zeros(N); regions=[]
for i,(t,txt) in enumerate(lines):
    a,_=sf.read(f'{take}/{i:02d}.wav'); a=resample_poly(a,2,1)
    e=np.abs(a)>0.01; s=np.argmax(e); en=len(a)-np.argmax(e[::-1])
    pad=int(0.04*SR); a=a[max(0,s-pad):en+int(0.12*SR)]
    f=np.minimum(1,np.arange(len(a))/(0.01*SR)); a=a*f*f[::-1]   # 10 ms fades
    a=sosfilt(hp,a)
    st=int(t*SR)-pad
    vo[st:st+len(a)]+=a; regions.append((t, t+(en-s)/SR, txt))
    act[int((t-0.12)*SR):int((t+(en-s)/SR+0.2)*SR)]=1
# voice chain: gentle 2.5:1 compression (10 ms attack, 120 ms release on a 10 ms RMS),
# then a 3 ms look-ahead peak limiter, so plosives don't set the level
from scipy.ndimage import maximum_filter1d, uniform_filter1d
def comp(x, thr_db, ratio):
    rms=np.sqrt(uniform_filter1d(x*x, int(0.01*SR))+1e-12); lvl=20*np.log10(rms)
    gr=np.minimum(0,(thr_db-lvl)*(1-1/ratio)); out=np.empty_like(gr); c=0.0
    ka,kr=np.exp(-1/(0.01*SR)),np.exp(-1/(0.12*SR))
    for n in range(len(gr)):
        k=ka if gr[n]<c else kr; c=gr[n]+(c-gr[n])*k; out[n]=c
    return x*10**(out/20)
def limit(x, ceil):
    la=int(0.003*SR); pk=maximum_filter1d(np.abs(x),2*la+1)
    g=np.minimum(1,ceil/np.maximum(pk,1e-9)); out=np.empty_like(g); c=1.0; kr=np.exp(-1/(0.06*SR))
    for n in range(len(g)):
        c=g[n] if g[n]<c else g[n]+(c-g[n])*kr; out[n]=c
    out=uniform_filter1d(out,la)  # smooth the gain so it never clicks
    return x*np.minimum(out,g)
rms_all=20*np.log10(np.sqrt(np.mean(vo[act>0]**2)))
vo=comp(vo, rms_all+4, 2.5)
vo=limit(vo, 10**((20*np.log10(np.sqrt(np.mean(vo[act>0]**2)))+10)/20))
# level the voice to target
VO_TARGET=float(sys.argv[4]) if len(sys.argv)>4 else -17.0
vo*=10**((VO_TARGET-meter.integrated_loudness(vo))/20)
# ducking envelope: -DUCK dB while speaking, 120 ms attack, 400 ms release
DUCK=4.5
g=np.ones(N); cur=1.0; lo=10**(-DUCK/20)
aa=np.exp(-1/(0.12*SR)); ar=np.exp(-1/(0.40*SR))
for n in range(N):
    tgt=lo if act[n] else 1.0
    c=aa if tgt<cur else ar
    cur=tgt+(cur-tgt)*c; g[n]=cur
SFX_GAIN=float(sys.argv[5]) if len(sys.argv)>5 else 3.0
sfxd=sfx*10**(SFX_GAIN/20)*g[:,None]
mix=sfxd+vo[:,None]
sf.write(f'{out}/voice-only.wav', np.stack([vo,vo],1), SR, subtype='FLOAT')
sf.write(f'{out}/sfx-ducked.wav', sfxd, SR, subtype='FLOAT')
sf.write(f'{out}/mix.wav', mix, SR, subtype='FLOAT')
json.dump(regions,open(f'{out}/regions.json','w'),indent=1)
print('mix LUFS',round(meter.integrated_loudness(mix),1),'peak',round(20*np.log10(np.abs(mix).max()),2))
for t0,t1,txt in regions: print(f'{t0:5.2f}-{t1:5.2f}  {txt}')
