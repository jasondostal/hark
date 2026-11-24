"""Shared helpers. Parity audio lives in ./audio (git-ignored): bring your own recordings.
audio/manifest.json is optional: [{"file": "audio/x.wav", "species": "Genus species", "common": "Name"}, ...].
Without it, every audio file in ./audio is used and the species is read from a "Genus_species_*" filename, if any."""
import glob, json, os, numpy as np, pandas as pd, librosa
SR=32000; WIN=160000
AUDIO=os.environ.get('HARK_AUDIO','audio')
LABELS=pd.read_csv('model_cpu/assets/labels.csv')['inat2024_fsd50k'].tolist()
def load_windows(fn):
    y,_=librosa.load(fn,sr=SR,mono=True)
    n=max(1,int(np.ceil(len(y)/WIN)))
    y=np.pad(y,(0,n*WIN-len(y)))
    return y.reshape(n,WIN).astype(np.float32)
def manifest():
    mf=os.path.join(AUDIO,'manifest.json')
    if os.path.exists(mf): return json.load(open(mf))
    files=sorted(f for e in ('wav','flac','mp3','ogg','m4a') for f in glob.glob(os.path.join(AUDIO,f'*.{e}')))
    if not files: raise SystemExit(f'no audio in {AUDIO}/: add your own recordings (see README.md)')
    def sp(f):
        p=os.path.basename(f).split('_')
        return f'{p[0]} {p[1]}' if len(p)>=2 and p[0][:1].isupper() and p[1].islower() else None
    return [{'file':f,'species':sp(f),'common':os.path.basename(f)} for f in files]
