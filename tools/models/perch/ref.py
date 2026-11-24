"""Golden reference: run Google's official TF Perch v2 (CPU) on your parity audio, save inputs + outputs to golden.npz."""
import numpy as np, tensorflow as tf
from common import *
f=tf.saved_model.load('model_cpu').signatures['serving_default']
X=[];L=[];E=[];S=[];meta=[]
M=manifest()
for m in M:
    w=load_windows(m['file'])
    o=f(inputs=tf.constant(w))
    for i in range(len(w)):
        X.append(w[i]);L.append(o['label'][i].numpy());E.append(o['embedding'][i].numpy());S.append(o['spectrogram'][i].numpy())
        meta.append((m['file'],m.get('species') or '',i))
np.savez_compressed('golden.npz',x=np.stack(X),label=np.stack(L),emb=np.stack(E),spec=np.stack(S),
    meta=np.array(meta,dtype=object))
# sanity: clip-level max-over-windows top-3, and agreement with the manifest's species where it has one
meta=np.array(meta,dtype=object); L=np.stack(L)
hit=0;n=0
for m in M:
    idx=[i for i,t in enumerate(meta) if t[0]==m['file']]
    s=L[idx].max(0); top=np.argsort(-s)[:5]
    if m.get('species'): n+=1; hit+=LABELS[top[0]]==m['species']
    print(f"{str(m.get('common') or m['file'])[:28]:28}", '->', ', '.join(f"{LABELS[j]} {s[j]:.1f}" for j in top[:3]))
print(f'windows={len(L)}' + (f'; top-1 matches your labels on {hit}/{n} clips' if n else ''))
