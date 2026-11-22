import json, os, numpy as np, soundfile as sf, coremltools as ct, onnxruntime as ort
from scipy.signal import resample_poly; from math import gcd
HERE = os.path.dirname(os.path.abspath(__file__)); HARK = os.path.join(HERE, "..", ".."); SR, W, B = 32000, 160_000, 96_000
labels = json.load(open(f"{HARK}/Hark/Resources/labels.json")); U = len(labels)
perch = ct.models.MLModel(f"{HARK}/Models/Perch.mlpackage", compute_units=ct.ComputeUnit.CPU_AND_NE)
sess = ort.InferenceSession(f"{HARK}/tools/data/birdnet3/model_fp32.onnx", providers=["CPUExecutionProvider"])
bmap = np.frombuffer(open(f"{HARK}/Hark/Resources/birdnet3_map.bin", "rb").read(), dtype="<u2")
def pe(b): b = np.clip(b, 1e-6, 1 - 1e-6); return np.minimum(0.99, 0.30 * np.exp((np.log(b / (1 - b)) - np.log(3.0)) / 2))
meta = [l.split(",") for l in open(f"{HARK}/tools/data/esc50/ESC-50-master/meta/esc50.csv").read().splitlines()[1:]]
out = []
for cat in ["dog", "cat", "rooster", "hen", "cow", "crow", "frog", "insects", "chirping_birds", "pig", "sheep"]:
    for m in [m for m in meta if m[3] == cat]:
        a, sr = sf.read(f"{HARK}/tools/data/esc50/ESC-50-master/audio/{m[0]}", dtype="float32")
        g_ = gcd(sr, SR); a = resample_poly(a, SR // g_, sr // g_).astype(np.float32)
        a = np.concatenate([np.zeros(2 * SR, np.float32), a, np.zeros(3 * SR, np.float32)])
        wins = []
        for end in range(2 * SR, len(a) + 1, SR):
            w = a[max(0, end - W):end]; w = np.pad(w, (W - len(w), 0))
            lo = perch.predict({"audio": w[None]})["logits"][0]; e = np.exp(lo - lo.max()); p = e / e.sum()
            bs = np.maximum(sess.run(None, {"input": w[None, :B]})[0][0], sess.run(None, {"input": w[None, W - B:]})[0][0])
            g = np.zeros(U, np.float32); ok = bmap != 0xFFFF; np.maximum.at(g, bmap[ok].astype(int), pe(bs[ok]).astype(np.float32))
            pp = np.zeros(U, np.float32); pp[:len(p)] = p
            keep = np.flatnonzero((pp >= 0.01) | (g >= 0.03))
            wins.append({int(i): [round(float(pp[i]), 4), round(float(g[i]), 4)] for i in keep})
        out.append({"cat": cat, "file": m[0], "windows": wins})
    print(cat, flush=True)
json.dump(out, open(os.path.join(HERE, "pet_windows.json"), "w"))
