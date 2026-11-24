"""Replay recordings the way the live app hears them: a 5 s window every 1 s, Perch on the window, BirdNET+ on its two
3 s halves (max), both mapped to Hark's labels on Hark's scale. Saves per-window scores (>= 0.03) to live_windows.json
for tune.py.

  tools/models/perch/.venv/bin/python live_sim.py ../data/yard/manifest.json ../data/inat_wi/manifest.json
"""
import json, os, sys, struct
import numpy as np, soundfile as sf, coremltools as ct, onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
HARK = os.path.join(HERE, "..", "..")
SR, W, B = 32000, 160_000, 96_000
labels = json.load(open(os.path.join(HARK, "Hark", "Resources", "labels.json")))
U = len(labels)
perch = ct.models.MLModel(os.path.join(HARK, "Models", "Perch.mlpackage"), compute_units=ct.ComputeUnit.CPU_AND_NE)
sess = ort.InferenceSession(os.path.join(HARK, "tools", "data", "birdnet3", "model_fp32.onnx"), providers=["CPUExecutionProvider"])
bmap = np.frombuffer(open(os.path.join(HARK, "Hark", "Resources", "birdnet3_map.bin"), "rb").read(), dtype="<u2")

def perch_equiv(b):
    b = np.clip(b, 1e-6, 1 - 1e-6)
    return np.minimum(0.99, 0.30 * np.exp((np.log(b / (1 - b)) - np.log(3.0)) / 2))

def load(f):
    a, sr = sf.read(f, dtype="float32")
    if a.ndim > 1: a = a.mean(1)
    if sr != SR:
        from scipy.signal import resample_poly; from math import gcd
        g = gcd(sr, SR); a = resample_poly(a, SR // g, sr // g).astype(np.float32)
    return a

out = []
for man in sys.argv[1:]:
    for it in json.load(open(man)):
        f = it["file"]
        if not os.path.exists(f): continue
        try: a = load(f)
        except Exception as e: print("skip", f, e); continue
        if len(a) < 2 * SR: continue
        a = np.pad(a, (0, max(0, W - len(a))))
        wins = []
        for end in range(2 * SR, len(a) + 1, SR):          # live: score the newest 5 s every second, from 2 s in
            w = a[max(0, end - W):end]
            if len(w) < W: w = np.pad(w, (W - len(w), 0))
            lo = perch.predict({"audio": w[None]})["logits"][0]
            e = np.exp(lo - lo.max()); p = e / e.sum()
            bs = np.maximum(sess.run(None, {"input": w[None, :B]})[0][0], sess.run(None, {"input": w[None, W - B:]})[0][0])
            g = np.zeros(U, np.float32)
            ok = bmap != 0xFFFF
            np.maximum.at(g, bmap[ok].astype(int), perch_equiv(bs[ok]).astype(np.float32))
            pp = np.zeros(U, np.float32); pp[:len(p)] = p
            keep = np.flatnonzero((pp >= 0.03) | (g >= 0.03))
            wins.append({int(i): [round(float(pp[i]), 4), round(float(g[i]), 4)] for i in keep})
        out.append({"set": os.path.basename(os.path.dirname(man)), "species": it["species"], "windows": wins})
        print(f"{it['species']:30} {len(wins)} windows", flush=True)
json.dump(out, open(os.path.join(HERE, os.environ.get("OUT", "live_windows.json")), "w"))
print("saved", len(out))
