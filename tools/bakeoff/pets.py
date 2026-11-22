"""Pets: does Perch hear a dog or cat as the species, or as AudioSet sound classes? Scores ESC-50 animal clips like the
live app (2 s quiet, the clip, 3 s quiet; a 5 s window every second) into pet_windows.json (_pets_score.py), then
compares logging Domestic Dog / Domestic Cat with and without moving the "Dog"/"Bark"/"Meow"... scores onto the species
(Fusion.soundSynonyms), with false IDs on the other ESC-50 animals and live_windows.json.

  ~/working/perch-spike/.venv/bin/python pets.py
"""
import json, os
HERE = os.path.dirname(os.path.abspath(__file__))
if not os.path.exists(os.path.join(HERE, "pet_windows.json")):
    exec(open(os.path.join(HERE, "_pets_score.py")).read(), {"__file__": os.path.join(HERE, "_pets_score.py")})
HARK = os.path.join(HERE, "..", "..")
L = json.load(open(f"{HARK}/Hark/Resources/labels.json")); ix = {l["s"]: i for i, l in enumerate(L)}
POOL = {"Canis familiaris": ["Dog", "Bark", "Growling"], "Felis catus": ["Cat", "Meow", "Purr"]}
pool = {ix[k]: [ix[s] for s in v] for k, v in POOL.items()}
t = 0.41  # Balanced, mammals
def score(w, sp, pooled):
    p, g = w.get(str(sp), [0, 0])
    if pooled: p += sum(w.get(str(j), [0, 0])[0] for j in pool[sp])
    return p, g
def hit(p, g, model):
    if model == "perch": return p >= t
    return (p >= .83 * t and g >= .47 * t) or p >= max(.7, t) or g >= max(.41, 1.03 * t)
def logged(r, sp, model, pooled, k):
    run = 0; last = -99
    for n, w in enumerate(r["windows"]):
        if hit(*score(w, sp, pooled), model):
            run = run + 1 if n - last <= 5 else 1; last = n
            if run >= k: return True
    return False
A = json.load(open(os.path.join(HERE, "pet_windows.json")))
LW = json.load(open(os.path.join(HERE, "live_windows.json")))
for name, sp, cat in [("Domestic Dog", ix["Canis familiaris"], "dog"), ("Domestic Cat", ix["Felis catus"], "cat")]:
    print(f"\n{name}")
    for model in ("perch", "both"):
        for pooled in (False, True):
            for k in (1, 2):
                tp = [logged(r, sp, model, pooled, k) for r in A if r["cat"] == cat]
                fp = [r["cat"] for r in A if r["cat"] != cat and logged(r, sp, model, pooled, k)]
                fw = [r["species"] for r in LW if logged(r, sp, model, pooled, k)]
                print(f"  {model:5} pooled={pooled!s:5} k={k}: found {sum(tp)}/{len(tp)}  false on other ESC animals {len(fp)} {sorted(set(fp))}  false on {len(LW)} wildlife clips {len(fw)} {fw[:6]}")
