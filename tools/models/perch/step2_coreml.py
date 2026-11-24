"""ONNX -> PyTorch (onnx2torch) -> Core ML mlprogram. Parity-gate each hop."""
import sys, time, numpy as np, torch, onnx, coremltools as ct
from onnx2torch import convert
from onnx2torch.node_converters.min_max import OnnxMinMax
from functools import reduce
def _mm(self,*t):  # elementwise chain instead of broadcast_to+stack+amax (Core ML-friendly)
    f=torch.maximum if self._operator is torch.amax else torch.minimum
    return reduce(f,t)
OnnxMinMax.apply_reduction=_mm
from parity import G, report
src=sys.argv[1]; out=sys.argv[2]; prec=sys.argv[3] if len(sys.argv)>3 else 'fp16'  # fp16 | fp32 | mixed
idx=None
if len(sys.argv)>4: idx=np.loadtxt(sys.argv[4],dtype=int)
tm=convert(onnx.load(src)).eval()
class Wrap(torch.nn.Module):
    def __init__(s,m): super().__init__(); s.m=m
    def forward(s,x):
        o=s.m(x)  # order: embedding, spatial_embedding, spectrogram, label
        return o[3], o[0], o[2]
w=Wrap(tm).eval()
X=torch.from_numpy(G['x'])
with torch.no_grad():
    L=[];E=[]
    for i in range(0,len(X),16):
        l,e,_=w(X[i:i+16]); L.append(l.numpy());E.append(e.numpy())
report('PyTorch (onnx2torch) vs TF',np.concatenate(L),np.concatenate(E),idx=idx)
with torch.no_grad(): tr=torch.jit.trace(w,X[:1])
import re
FRONTEND_MAX=12  # ONNX nodes 0..12 = framing, window, DFT, |X|, mel, max(1e-5), log, *0.1
seen=[]
def keep_fp16(op):
    mm=re.search(r'n(\d+)_[A-Za-z]',op.name)
    fp32 = mm is not None and int(mm.group(1))<=FRONTEND_MAX
    if fp32: seen.append(op.name)
    return not fp32
PREC={'fp16':ct.precision.FLOAT16,'fp32':ct.precision.FLOAT32}.get(prec) or ct.transform.FP16ComputePrecision(op_selector=keep_fp16)
t=time.time()
ml=ct.convert(tr,inputs=[ct.TensorType(name='audio',shape=(1,160000),dtype=np.float32)],
    outputs=[ct.TensorType(name='logits'),ct.TensorType(name='embedding'),ct.TensorType(name='spectrogram')],
    convert_to='mlprogram',minimum_deployment_target=ct.target.iOS17,
    compute_precision=PREC)
print('fp32-kept ops',len(seen),seen[:6]); print('convert secs',round(time.time()-t,1))
ml.save(out)
