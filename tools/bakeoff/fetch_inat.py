"""Independent test set for the model bake-off: research-grade iNaturalist sound observations from Wisconsin
(human-identified, so not biased toward either model). Top species by observation count, up to N recordings each,
first 30 s, converted to 32 kHz mono WAV with afconvert. Local evaluation only; nothing here ships.

  python3 fetch_inat.py [species=60] [per_species=3]
"""
import json, os, subprocess, sys, time, urllib.parse, urllib.request

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "..", "data", "inat_wi")
os.makedirs(OUT, exist_ok=True)
N_SPECIES = int(sys.argv[1]) if len(sys.argv) > 1 else 60
PER = int(sys.argv[2]) if len(sys.argv) > 2 else 3
BBOX = dict(swlat=42.49, swlng=-92.89, nelat=47.08, nelng=-86.25)    # Wisconsin
UA = {"User-Agent": "hark-model-bakeoff/0.1 (local evaluation)"}

def get(path, **q):
    url = f"https://api.inaturalist.org/v1/{path}?{urllib.parse.urlencode(q)}"
    for attempt in range(3):
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=30) as r:
                time.sleep(1.0)                 # iNat asks for ~1 request/second
                return json.load(r)
        except Exception as e:
            print("  retry", e); time.sleep(5)
    raise SystemExit(f"failed: {url}")

counts = get("observations/species_counts", sounds="true", quality_grade="research", per_page=200, **BBOX)
species = [r["taxon"] for r in counts["results"] if r["taxon"].get("iconic_taxon_name") in
           ("Aves", "Amphibia", "Insecta", "Mammalia", "Reptilia")][:N_SPECIES]
manifest = []
for t in species:
    sci = t["name"]
    obs = get("observations", taxon_id=t["id"], sounds="true", quality_grade="research", per_page=PER * 2,
              order_by="votes", **BBOX)["results"]
    got = 0
    for o in obs:
        if got >= PER: break
        snd = next((s for s in o.get("sounds", []) if s.get("file_url")), None)
        if not snd: continue
        base = f"{sci.replace(' ', '_')}_{o['id']}"
        wav = os.path.join(OUT, base + ".wav")
        if not os.path.exists(wav):
            raw = os.path.join(OUT, base + ".src")
            try:
                urllib.request.urlretrieve(snd["file_url"], raw)
                subprocess.run(["afconvert", "-f", "WAVE", "-d", "LEI16@32000", "-c", "1", raw, wav], check=True,
                               capture_output=True)
                # keep the first 30 s
                subprocess.run(["python3", "-c", f"""
import wave
w=wave.open({wav!r});p=w.getparams();n=min(p.nframes,30*32000);d=w.readframes(n);w.close()
o=wave.open({wav!r},'wb');o.setparams(p);o.writeframes(d);o.close()"""], check=True)
            except Exception as e:
                print("  skip", base, e); continue
            finally:
                if os.path.exists(raw): os.remove(raw)
        manifest.append({"file": wav, "species": sci, "common": t.get("preferred_common_name", ""),
                         "group": t.get("iconic_taxon_name"), "obs": o["id"]})
        got += 1
    print(f"{sci:32} {got}")
json.dump(manifest, open(os.path.join(OUT, "manifest.json"), "w"), indent=1)
print(len(manifest), "recordings,", len({m['species'] for m in manifest}), "species")
