"""Perch 2.0 vs BirdNET+ V3.0 (and the two in tandem) on labeled recordings.

  tools/models/perch/.venv/bin/python eval.py manifest.json [manifest2.json ...]

Each clip is scored the way Hark scores a selection: overlapping windows (Perch 5 s, BirdNET+ 3 s, half-window hop),
best score per species across windows. Then per clip:
  - top-1: is the labeled species the highest-scoring animal?
  - recall at a threshold: is the labeled species at or above it?
  - "others": how many *other* animal species clear the threshold (a false-positive proxy: some will be real
    background birds, but a model that lights up five species on a one-species clip is noisy).
Tandem rules combine both models' per-species scores.
"""
import csv, json, os, sys, collections
import numpy as np, soundfile as sf, coremltools as ct, onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
HARK = os.path.join(HERE, "..", "..")
SR = 32000

# Perch: Core ML (CPU), softmax over 14,795 classes
perch = ct.models.MLModel(os.path.join(HARK, "Models", "Perch.mlpackage"), compute_units=ct.ComputeUnit.CPU_ONLY)
plab = json.load(open(os.path.join(HARK, "Hark", "Resources", "labels.json")))
p_sci = [l["s"] for l in plab]
p_animal = np.array([l["g"] not in ("sound",) for l in plab])

# BirdNET+ V3.0: ONNX, sigmoid scores
B = os.path.join(HARK, "tools", "data", "birdnet3")
sess = ort.InferenceSession(os.path.join(B, "model_fp32.onnx"), providers=["CPUExecutionProvider"])
b_in = sess.get_inputs()[0].name
rows = list(csv.DictReader(open(os.path.join(B, "labels.csv"), encoding="utf-8")))
sci_col = next(c for c in rows[0] if c.lower() in ("sci_name", "scientific_name", "sciname", "scientific"))
b_sci = [r[sci_col] for r in rows]
cls_col = next((c for c in rows[0] if c.lower() in ("taxon_group", "class", "taxon_class", "class_name")), None)
b_animal = np.array([(r.get(cls_col, "x") or "x").lower() not in ("", "sound", "non-animal", "none", "anthropogenic", "geophony", "music") for r in rows]) if cls_col else np.ones(len(rows), bool)

def windows(a, n):
    if len(a) <= n: return [np.pad(a, (0, n - len(a)))]
    hop = n // 2
    starts = list(range(0, len(a) - n + 1, hop))
    if starts[-1] != len(a) - n: starts.append(len(a) - n)
    return [a[s:s + n] for s in starts]

def perch_scores(a):
    best = None
    for w in windows(a, 5 * SR):
        o = perch.predict({"audio": w[None].astype(np.float32)})["logits"][0]
        e = np.exp(o - o.max()); p = e / e.sum()
        best = p if best is None else np.maximum(best, p)
    return best

def birdnet_scores(a):
    best = None
    for w in windows(a, 3 * SR):
        out = sess.run(None, {b_in: w[None].astype(np.float32)})
        p = out[0][0]
        if p.min() < 0 or p.max() > 1: p = 1 / (1 + np.exp(-p))
        best = p if best is None else np.maximum(best, p)
    return best

def load(f):
    a, sr = sf.read(f, dtype="float32")
    if a.ndim > 1: a = a.mean(1)
    if sr != SR:
        from scipy.signal import resample_poly; from math import gcd
        g = gcd(sr, SR); a = resample_poly(a, SR // g, sr // g).astype(np.float32)
    return a

def to_dict(scores, sci, animal):
    return {sci[i]: float(scores[i]) for i in np.flatnonzero(animal & (scores >= 0.05))}

results = []
for man in sys.argv[1:]:
    items = json.load(open(man))
    for it in items:
        f = it["file"] if os.path.isabs(it["file"]) else os.path.join(os.path.dirname(man), "..", it["file"])
        if not os.path.exists(f): f = os.path.join(os.path.dirname(man), os.path.basename(it["file"]))
        a = load(f)
        ps, bs = perch_scores(a), birdnet_scores(a)
        results.append(dict(set=os.path.basename(os.path.dirname(man)), species=it["species"], group=it.get("group", ""),
                            p=to_dict(ps, p_sci, p_animal), b=to_dict(bs, b_sci, b_animal),
                            p_top=p_sci[int(np.argmax(np.where(p_animal, ps, -1)))],
                            b_top=b_sci[int(np.argmax(np.where(b_animal, bs, -1)))],
                            p_has=it["species"] in p_sci, b_has=it["species"] in b_sci))
        print(f"{it['species']:30} perch {results[-1]['p'].get(it['species'], 0):.2f} ({results[-1]['p_top']})"
              f"  birdnet {results[-1]['b'].get(it['species'], 0):.2f} ({results[-1]['b_top']})", flush=True)
json.dump(results, open(os.path.join(HERE, "results.json"), "w"))
print(f"\nsaved {len(results)} clips -> results.json; run report.py")
