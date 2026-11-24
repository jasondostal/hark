#!/bin/zsh
# Perch 2.0 no_dft ONNX -> fp16-safe frontend -> Core ML mlprogram, parity-gated against Google's TF model.
# See README.md for the downloads and the venv. Needs golden.npz (ref.py) from your own audio for the gates.
# Usage: ./build.sh [onnx=onnx/full/perch_v2_no_dft_fp32.onnx] [name=full] [slice_idx.txt]
set -e
cd "${0:A:h}"
PY=${PY:-.venv/bin/python}
SRC=${1:-onnx/full/perch_v2_no_dft_fp32.onnx}; NAME=${2:-full}; IDX=$3
$PY to_opset13.py $SRC onnx/${NAME}_op13.onnx
$PY fp16_safe_frontend.py onnx/${NAME}_op13.onnx onnx/${NAME}_op13_safe.onnx 1024
$PY step2_coreml.py onnx/${NAME}_op13_safe.onnx models/perch_v2_${NAME}_fp16.mlpackage fp16 $IDX
$PY step3_eval.py models/perch_v2_${NAME}_fp16.mlpackage $IDX
echo "done: cp -R models/perch_v2_${NAME}_fp16.mlpackage ../../../Models/Perch.mlpackage"
