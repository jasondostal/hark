# Perch 2.0 → Core ML (Apple Neural Engine)

How Hark's `Models/Perch.mlpackage` is made: Google DeepMind's Perch 2.0 (Apache 2.0), converted to a Core ML
mlprogram that runs on the iPhone's Neural Engine in fp16 with the same answers as Google's own TensorFlow model.
On an M5 MacBook: 196 MB, 4.8 ms per 5-second window, 143/144 top-1 agreement with TF (the one flip is a dead tie).

## Bring your own audio

The parity gates compare the Core ML model with Google's TF model on real recordings. **No audio ships in this repo.**
Put a dozen or more recordings in `audio/` (git-ignored), any of wav/flac/mp3/ogg/m4a. Field recordings are best:
quiet, distant calls are what break fp16. Optional: `audio/manifest.json` with species labels, or name files
`Genus_species_anything.wav`, and `ref.py` also reports agreement with your labels.

No recordings handy? `python fetch_commons.py audio "Bubo virginianus" "Poecile atricapillus" ...` pulls Creative
Commons clips from Wikimedia Commons and records each license in the manifest.

## Setup

```
uv venv -p 3.12 .venv
uv pip install -p .venv tensorflow coremltools==9.0 torch==2.7.0 torchvision==0.22.0 onnx onnxruntime onnx2torch librosa pandas
```
coremltools 9.0 wants torch 2.7.0 (+ torchvision 0.22.0). TensorFlow is only for the reference run.

Downloads (all git-ignored here):
- `model_cpu/`: the official TF SavedModel, Kaggle `google/bird-vocalization-classifier/tensorFlow2/perch_v2_cpu`.
- `onnx/full/perch_v2_no_dft_fp32.onnx`: the ONNX `no_dft` export, from Hugging Face `tphakala/Perch-v2-Models`
  (which also has regional slices).

## Run

```
.venv/bin/python ref.py              # TF reference on your audio -> golden.npz
.venv/bin/python step1_ort.py        # optional: the ONNX export matches TF
./build.sh                           # -> models/perch_v2_full_fp16.mlpackage, parity-gated per compute unit
cp -R models/perch_v2_full_fp16.mlpackage ../../../Models/Perch.mlpackage
.venv/bin/python make_fixtures.py    # optional: swift test + on-device -selftest fixtures from your audio
```

## Why it isn't a one-line conversion

1. The official Kaggle SavedModel is a jax2tf export: the whole net is two `XlaCallModule` (StableHLO) ops, so the
   coremltools TF frontend can't read it. The ONNX `no_dft` export matches TF exactly (144/144, max logit diff 0.003).
2. `to_opset13.py`: opset 18 → 13 (ReduceL2/ReduceMax axes input → attribute) and sanitized node names, so onnx2torch
   converts it.
3. `fp16_safe_frontend.py` rewrites the spectrogram frontend. It is exact in fp32 and required for the ANE:
   - **Framing Conv** (identity 640×640 kernel, stride 320, pad 160): the ANE and CPU fp16 kernels compute it wrong
     (relative error 1.2; the GPU is fine). Replaced with pad + reshape(501, 320) + concat(row i, row i+1).
   - **|X| via ReduceL2** squares values. Quiet field audio puts mel at 1e-5..4e-3, so the squares underflow fp16.
     Replaced with hypot `hi*sqrt(1+(lo/hi)^2)`.
   - **Gain S=1024** folded into the window multiply, and the floor `max(mel, 1e-5)` → `max(mel, S*1e-5)`: 1e-5 is
     subnormal in fp16, the ANE flushes it to zero, and log(0) follows. `- log(S)` after the log undoes the gain.
4. `step2_coreml.py`: onnx2torch (Min/Max patched to an elementwise chain) → `torch.jit.trace` → Core ML mlprogram,
   iOS 17, fp16.
5. `step3_eval.py`: the parity gate on every compute unit, plus the per-op device plan. `parity.py` holds the gate.

The GPU hides all three frontend bugs, so it's a misleading place to check: test on the Neural Engine.

BirdNET+ 3.0 uses the BirdNET team's own converter (`../../convert_birdnet3.py`), and the BirdNET+ geomodel
`../../convert_geomodel.py`. Both use this venv.
