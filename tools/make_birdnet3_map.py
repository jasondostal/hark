"""Put BirdNET+ V3.0's species into Hark's label table (run after make_labels.py and convert_birdnet3.py, then
re-run convert_geomodel.py so the geomodel map covers the additions).

  python3 make_birdnet3_map.py

- labels.json: Perch's 14,795 labels (output order, untouched), then the BirdNET+ species Perch doesn't have.
  Idempotent: earlier additions are dropped and rebuilt.
- birdnet3_map.bin: one little-endian u16 per BirdNET+ output, the Hark label index for it, or 0xFFFF for
  BirdNET+'s 16 non-animal sound classes (Hark's non-animal sounds come from Perch).
Matched by scientific name, eBird code, then OpenFauna's alias map (data/openfauna_aliases.json, from
github.com/tphakala/openfauna build/aliases.json), in both directions.
"""
import csv, json, os, struct

HERE = os.path.dirname(os.path.abspath(__file__))
RES = os.path.join(HERE, "..", "Hark", "Resources")
PERCH_COUNT = 14_795

labels = json.load(open(os.path.join(RES, "labels.json")))[:PERCH_COUNT]
bn = json.load(open(os.path.join(RES, "birdnet3_labels.json")))
aliases = json.load(open(os.path.join(HERE, "data", "openfauna_aliases.json")))
aliases = aliases.get("aliases", aliases)
canon = lambda s: aliases.get(s, s)

inat = {}
with open(os.path.join(HERE, "data", "birdnet3", "labels.csv"), encoding="utf-8") as f:
    for r in csv.DictReader(f):
        if r.get("inat_id"): inat[r["scientific_name"]] = int(float(r["inat_id"]))

by_sci = {l["s"]: i for i, l in enumerate(labels)}
by_canon = {canon(l["s"]): i for i, l in enumerate(labels)}
by_ebird = {l["b"]: i for i, l in enumerate(labels) if "b" in l}
out, added, how = [], 0, {"name": 0, "ebird": 0, "alias": 0}
for l in bn:
    if l["g"] == "sound": out.append(0xFFFF); continue
    i = by_sci.get(l["s"])
    if i is not None: how["name"] += 1
    elif l.get("b") in by_ebird: i = by_ebird[l["b"]]; how["ebird"] += 1
    elif canon(l["s"]) in by_canon: i = by_canon[canon(l["s"])]; how["alias"] += 1
    else:
        i = len(labels)
        o = {"s": l["s"], "c": l["c"], "g": l["g"]}
        if l["s"] in inat: o["i"] = inat[l["s"]]
        if "b" in l: o["b"] = l["b"]
        labels.append(o); by_sci[l["s"]] = i; added += 1
    out.append(i)
json.dump(labels, open(os.path.join(RES, "labels.json"), "w"), separators=(",", ":"))
with open(os.path.join(RES, "birdnet3_map.bin"), "wb") as f:
    f.write(struct.pack(f"<{len(out)}H", *out))
print(f"BirdNET+ outputs: {len(out)}; matched {how}; added {added} species -> {len(labels)} labels")
