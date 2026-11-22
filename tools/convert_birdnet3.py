"""BirdNET+ V3.0 Global 12K (Apache 2.0) -> Hark: Core ML model, labels, self-test references.

1. Export Core ML with BirdNET's own converter (github.com/birdnet-team/model-converter, cloned to
   tools/data/model-converter, checkpoint via `git lfs pull`), Core ML only and without TensorFlow:
     cd tools/data/model-converter && .venv/bin/python run_coreml.py -f coreml -p fp16 -o export
2. ~/working/perch-spike/.venv/bin/python convert_birdnet3.py
   Copies the export to ../Models/BirdNET3.mlpackage (input "input" [1, 96000] = 3 s of 32 kHz mono; outputs
   "predictions" [1, 11725] sigmoid, "embeddings"), checks it against the FP32 ONNX model on the Perch self-test
   windows, and writes ../Hark/Resources/birdnet3_labels.json ([{s, c, g, b}], output order) and
   birdnet3_selftest.json (FP32 top-1 per window, which `-selftest` checks on the phone).
"""
import csv, json, os, shutil
import numpy as np, coremltools as ct, onnxruntime as ort

HERE = os.path.dirname(os.path.abspath(__file__))
D = os.path.join(HERE, "data", "birdnet3")
EXPORT = os.path.join(HERE, "data", "model-converter", "export", "02_BirdNET+_V3.0_Global_12K")
N = 96_000

dst = os.path.join(HERE, "..", "Models", "BirdNET3.mlpackage")
if os.path.exists(dst): shutil.rmtree(dst)
shutil.copytree(os.path.join(EXPORT, "coreml", "model_fp16.mlpackage"), dst)
ml = ct.models.MLModel(dst, compute_units=ct.ComputeUnit.CPU_ONLY)
onnx = ort.InferenceSession(os.path.join(D, "model_fp32.onnx"), providers=["CPUExecutionProvider"])

raw = np.fromfile(os.path.join(HERE, "..", "Hark", "Resources", "selftest.f32"), dtype=np.float32)
wins = raw.reshape(-1, 160_000)[:, :N]
diffs, agree, top1 = [], 0, []
for w in wins:
    ref = onnx.run(None, {"input": w[None]})[0][0]
    got = ml.predict({"input": w[None]})["predictions"][0]
    diffs.append(float(np.abs(ref - got).max())); agree += int(np.argmax(ref) == np.argmax(got)); top1.append(int(np.argmax(ref)))
print(f"Core ML fp16 vs ONNX fp32: max|diff| {max(diffs):.4f} (median {np.median(diffs):.4f}), top-1 agree {agree}/{len(wins)}")

labels_csv = os.path.join(EXPORT, "labels.csv") if os.path.exists(os.path.join(EXPORT, "labels.csv")) else os.path.join(D, "labels.csv")
rows = list(csv.DictReader(open(labels_csv, encoding="utf-8")))
GROUP = {"Aves": "bird", "Amphibia": "amphibian", "Insecta": "insect", "Mammalia": "mammal", "Reptilia": "reptile",
         "Actinopterygii": "fish", "Arachnida": "other"}
labels = [{"s": r["scientific_name"], "c": r.get("common_name_en") or r["common_name"], "g": GROUP.get(r["taxon_group"], "sound"),
           **({"b": r["ebird_code"]} if r.get("ebird_code") else {})} for r in rows]
json.dump(labels, open(os.path.join(HERE, "..", "Hark", "Resources", "birdnet3_labels.json"), "w"), separators=(",", ":"))
json.dump([{"top1": t} for t in top1], open(os.path.join(HERE, "..", "Hark", "Resources", "birdnet3_selftest.json"), "w"))
print("saved", dst, "and", len(labels), "labels")
