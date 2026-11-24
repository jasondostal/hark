"""Parity gate: compare a candidate's outputs against the TF golden reference."""
import numpy as np
G=np.load('golden.npz',allow_pickle=True)
def softmax(z): z=z-z.max(-1,keepdims=True); e=np.exp(z); return e/e.sum(-1,keepdims=True)
def report(name,label,emb=None,idx=None, gate=dict(top1=0.99,prob=0.02,cos=0.999)):
    ref=G['label'] if idx is None else G['label'][:,idx]
    # softmax over FULL classes for both when full; for slices compare raw logits + top1 within slice
    t1=(ref.argmax(1)==label.argmax(1)).mean()
    top5=np.mean([len(set(np.argsort(-a)[:5])&set(np.argsort(-b)[:5]))/5 for a,b in zip(ref,label)])
    dlog=np.abs(ref-label).max()
    dprob=np.abs(softmax(ref)-softmax(label)).max()
    r=dict(windows=len(ref),top1=round(float(t1),4),top5_overlap=round(float(top5),4),max_logit_diff=float(dlog),max_prob_diff=float(dprob))
    if emb is not None:
        e=G['emb']; cos=(e*emb).sum(1)/np.linalg.norm(e,axis=1)/np.linalg.norm(emb,axis=1); r['min_emb_cos']=float(cos.min())
    ok=r['top1']>=gate['top1'] and r['max_prob_diff']<=gate['prob'] and r.get('min_emb_cos',1)>=gate['cos']
    print(f"[{'PASS' if ok else 'FAIL'}] {name}: {r}")
    return ok,r
