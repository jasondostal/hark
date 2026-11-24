"""BirdNET+ Geomodel V3.0.4 (Apache 2.0, github.com/birdnet-team/geomodel) -> Core ML, plus the label map.

  tools/models/perch/.venv/bin/python convert_geomodel.py      # needs torch + coremltools

Writes ../Models/Geo.mlpackage (input "input" [1,3] = lat, lon, week 1-48; output "logits" [1,14082], sigmoid
= probability the species occurs there that week) and ../Hark/Resources/geo_map.bin: one little-endian u16 per
Perch label, the geomodel output index for that species or 0xFFFF. Matched by scientific name, then by
eBird code, then the GBIF taxon key gbif_ranges.py looked up (the geomodel's first label column
is an eBird code for birds, a GBIF key otherwise).
"""
import json, os, struct, sys, urllib.request
import numpy as np, torch, coremltools as ct

HERE = os.path.dirname(os.path.abspath(__file__))
REL = "https://github.com/birdnet-team/geomodel/releases/download/v3.0.4/"
TS, LABELS = "BirdNET+_Geomodel_V3.0.4_Global_14K_TorchScript.pt", "BirdNET+_Geomodel_V3.0.4_Global_14K_Labels.txt"
CACHE = os.path.join(HERE, "data", "geomodel")
os.makedirs(CACHE, exist_ok=True)
for f in (TS, LABELS):
    if not os.path.exists(os.path.join(CACHE, f)):
        print("downloading", f); urllib.request.urlretrieve(REL + f, os.path.join(CACHE, f))

geo = [l.rstrip("\n").split("\t") for l in open(os.path.join(CACHE, LABELS), encoding="utf-8")]
by_sci = {g[1]: i for i, g in enumerate(geo)}
by_key = {g[0]: i for i, g in enumerate(geo)}
labels = json.load(open(os.path.join(HERE, "..", "Hark", "Resources", "labels.json")))
out, n_sci, n_key = [], 0, 0
for i, l in enumerate(labels):
    j = by_sci.get(l["s"]) if l["g"] != "sound" else None
    if j is not None: n_sci += 1
    elif l.get("b") in by_key: j = by_key[l["b"]]; n_key += 1      # birds: the geomodel's key is the eBird code
    elif l["g"] != "sound":
        f = os.path.join(HERE, "data", "gbif", f"{i}.json")
        if os.path.exists(f):
            k = json.load(open(f)).get("key")
            j = by_key.get(str(k)) if k else None
            if j is not None: n_key += 1
    out.append(0xFFFF if j is None else j)
with open(os.path.join(HERE, "..", "Hark", "Resources", "geo_map.bin"), "wb") as f:
    f.write(struct.pack(f"<{len(out)}H", *out))
print(f"geo_map.bin: {n_sci} by name + {n_key} by eBird code/GBIF key = {n_sci + n_key} of {len(labels)} labels")

m = torch.jit.load(os.path.join(CACHE, TS), map_location="cpu").eval()
ex = torch.tensor([[44.45, -89.55, 20.0]])
ml = ct.convert(torch.jit.trace(m, ex), inputs=[ct.TensorType(name="input", shape=(1, 3))],
                outputs=[ct.TensorType(name="logits")], minimum_deployment_target=ct.target.iOS17,
                compute_precision=ct.precision.FLOAT32, convert_to="mlprogram")
dst = os.path.join(HERE, "..", "Models", "Geo.mlpackage")
ml.save(dst)
a = ml.predict({"input": ex.numpy()})["logits"][0]
with torch.no_grad(): b = m(ex)[0].numpy()
print("saved", dst, "max|diff| vs torch", float(np.abs(a - b).max()))
