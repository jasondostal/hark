"""Tune live logging on live_windows.json (from live_sim.py): which threshold and how many seconds of evidence.

For each recording, a species is LOGGED if its per-window rule passes in at least k windows (1 window = 1 second of
live listening). 'found' = the labeled species was logged; 'junk/clip' = other species logged (a false-positive
proxy: some are real background animals, but a setting that logs 2 extra species per clip is noisy).
"""
import json, os, collections
HERE = os.path.dirname(os.path.abspath(__file__))
labels = json.load(open(os.path.join(HERE, "..", "..", "Hark", "Resources", "labels.json")))
sci = [l["s"] for l in labels]
base = [0.40 if l["g"] in ("insect", "other") else 0.30 for l in labels]
animal = [l["g"] not in ("sound",) for l in labels]
R = json.load(open(os.path.join(HERE, "live_windows.json")))
idx = {s: i for i, s in enumerate(sci)}

def hit(p, g, t, model):
    if model == "perch": return p >= t
    if model == "birdnet": return g >= t
    return (p >= 0.83 * t and g >= 0.47 * t) or p >= 2.33 * t or g >= 1.37 * t

def sure(p, g, t): return p >= 2.33 * t or g >= 1.37 * t

def run(rs, model, mult, k, sure_fast):
    found = junk = 0
    for r in rs:
        counts, fast = collections.Counter(), set()
        for w in r["windows"]:
            for i, (p, g) in w.items():
                i = int(i)
                if not animal[i]: continue
                t = base[i] * mult
                if hit(p, g, t, model):
                    counts[i] += 1
                    if sure_fast and sure(p, g, t): fast.add(i)
        logged = {i for i, c in counts.items() if c >= k} | fast
        target = idx.get(r["species"])
        found += target in logged
        junk += len(logged - {target})
    return found / len(rs), junk / len(rs)

for st in sorted({r["set"] for r in R}):
    rs = [r for r in R if r["set"] == st and r["species"] in idx]
    print(f"\n## {st} ({len(rs)} recordings)")
    print(f"{'model':8} {'thresh':>6} {'secs':>4} {'sure=1s':>7} {'found':>6} {'junk/clip':>10}")
    for model in ("perch", "both"):
        for mult in (1.0, 1.33, 1.67):
            for k in (1, 2, 3, 4):
                for sf in ((False, True) if k > 1 else (False,)):
                    f, j = run(rs, model, mult, k, sf)
                    print(f"{model:8} {0.30 * mult:6.2f} {k:4} {('yes' if sf else ''):>7} {f:6.0%} {j:10.2f}")
