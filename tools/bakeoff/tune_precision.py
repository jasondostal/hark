"""Precision tuning: false IDs per hour on audio with no animals (neg_windows.json: ESC-50 household/outdoor sounds +
synthetic speech) against real calls found on the wildlife sets (live_windows.json). Both from live_sim.py.

Rule per window, then a species is logged after k windows within 5 s (the tracker's confirmation):
  Both  = agree (P >= .83t and B >= .47t) or sure (P >= max(.70, t) or B >= max(.41, 1.03t))   [B on Perch's scale]
  gate  = if Perch's best non-animal sound (speech, typing, engine...) in that window >= G, only 'sure' hits count
"""
import json, os, collections, sys
HERE = os.path.dirname(os.path.abspath(__file__))
labels = json.load(open(os.path.join(HERE, "..", "..", "Hark", "Resources", "labels.json")))
sci = [l["s"] for l in labels]
base = [0.40 if l["g"] in ("insect", "other") else 0.30 for l in labels]
animal = [l["g"] != "sound" for l in labels]
idx = {s: i for i, s in enumerate(sci)}
POS = json.load(open(os.path.join(HERE, "live_windows.json")))
NEG = json.load(open(os.path.join(HERE, "neg_windows.json")))

def sure(p, g, t): return p >= max(0.70, t) or g >= max(0.41, 1.03 * t)
def hit(p, g, t, model):
    if model == "perch": return p >= t
    return (p >= 0.83 * t and g >= 0.47 * t) or sure(p, g, t)

def logged(r, model, mult, k, gate):
    seen = {}                      # index -> (count, last window number) for confirmation within 5 windows
    out = set()
    for n, w in enumerate(r["windows"]):
        noise = max((p for i, (p, g) in w.items() if not animal[int(i)]), default=0)
        for i, (p, g) in w.items():
            i = int(i)
            if not animal[i]: continue
            t = base[i] * mult
            if not hit(p, g, t, model): continue
            if gate and noise >= gate and not sure(p, g, t): continue
            c, last = seen.get(i, (0, -99))
            c = c + 1 if n - last <= 5 else 1
            seen[i] = (c, n)
            if c >= k: out.add(i)
    return out

def score(model, mult, k, gate):
    neg_ids = sum(len(logged(r, model, mult, k, gate)) for r in NEG)
    neg_hours = sum(len(r["windows"]) for r in NEG) / 3600
    res = {}
    for st in ("inat_wi", "yard"):
        rs = [r for r in POS if r["set"] == st and r["species"] in idx]
        f = j = 0
        for r in rs:
            lg = logged(r, model, mult, k, gate); t = idx[r["species"]]
            f += t in lg; j += len(lg - {t})
        res[st] = (f / len(rs), j / len(rs))
    return neg_ids / neg_hours, res

print(f"negatives: {len(NEG)} streams, {sum(len(r['windows']) for r in NEG) / 60:.0f} min")
print(f"{'model':6} {'thr':>4} {'sec':>3} {'gate':>4} | {'false IDs/hr':>12} | {'iNat found':>10} {'junk':>5} | {'yard found':>10} {'junk':>5}")
for model in ("perch", "both"):
    for mult in (1.0, 1.33, 1.67, 2.0):
        for k in (2, 3, 4):
            for gate in (0, 0.3, 0.15):
                fh, res = score(model, mult, k, gate)
                print(f"{model:6} {0.30 * mult:4.2f} {k:3} {gate:4.2f} | {fh:12.1f} | {res['inat_wi'][0]:10.0%} {res['inat_wi'][1]:5.2f} | {res['yard'][0]:10.0%} {res['yard'][1]:5.2f}")

# What fires on the negatives at today's Balanced setting
print("\nToday's Balanced (both, 0.30, 2 s, no gate) false IDs by source:")
for r in NEG:
    ids = logged(r, "both", 1.0, 2, 0)
    if ids: print(f"  {r.get('group', r['species']) if 'group' in r else ''}{os.path.basename(str(r.get('file', '')))}: " + ", ".join(labels[i]["c"] for i in ids))
