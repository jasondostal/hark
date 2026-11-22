"""Summarize results.json from eval.py: recall and false-positive proxy for each model and tandem rule."""
import json, os, sys, collections

R = json.load(open(os.path.join(os.path.dirname(os.path.abspath(__file__)), "results.json")))

RULES = {
    "Perch ≥ 0.30 (Hark today)":          lambda p, b: p >= 0.30,
    "BirdNET+ ≥ 0.50":                     lambda p, b: b >= 0.50,
    "BirdNET+ ≥ 0.75":                     lambda p, b: b >= 0.75,
    "Either (P≥.30 or B≥.50)":             lambda p, b: p >= 0.30 or b >= 0.50,
    "Both agree (P≥.15 and B≥.25)":        lambda p, b: p >= 0.15 and b >= 0.25,
    "Agree, or one is sure":               lambda p, b: (p >= 0.15 and b >= 0.25) or p >= 0.60 or b >= 0.85,
}

def summarize(rs, title):
    if not rs: return
    print(f"\n## {title}  ({len(rs)} clips, {len({r['species'] for r in rs})} species)")
    print(f"   top-1 correct: Perch {sum(r['p_top'] == r['species'] for r in rs)}/{len(rs)}, "
          f"BirdNET+ {sum(r['b_top'] == r['species'] for r in rs)}/{len(rs)}")
    print(f"   {'rule':34} {'found':>8} {'others/clip':>12}")
    for name, rule in RULES.items():
        found = others = 0
        for r in rs:
            s = r["species"]
            found += rule(r["p"].get(s, 0), r["b"].get(s, 0))
            for x in set(r["p"]) | set(r["b"]):
                if x != s and rule(r["p"].get(x, 0), r["b"].get(x, 0)): others += 1
        print(f"   {name:34} {found:>4}/{len(rs):<3} {others / len(rs):>12.2f}")

for st in sorted({r["set"] for r in R}):
    rs = [r for r in R if r["set"] == st]
    summarize(rs, f"{st}: all")
    both = [r for r in rs if r["p_has"] and r["b_has"]]
    if len(both) != len(rs): summarize(both, f"{st}: species both models know")
    print("   missing from Perch:", sorted({r['species'] for r in rs if not r['p_has']}) or "none")
    print("   missing from BirdNET+:", sorted({r['species'] for r in rs if not r['b_has']}) or "none")
    for g in sorted({r["group"] for r in rs if r["group"]}):
        gs = [r for r in both if r["group"] == g]
        if gs and g != "Aves": summarize(gs, f"{st}: {g}")
