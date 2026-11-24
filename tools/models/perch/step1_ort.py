import numpy as np, onnxruntime as ort, time
from parity import G, report
s=ort.InferenceSession('onnx/full/perch_v2_no_dft_fp32.onnx',providers=['CPUExecutionProvider'])
X=G['x']; L=[];E=[]
t=time.time()
for i in range(0,len(X),16):
    o=s.run(['label','embedding'],{'inputs':X[i:i+16]}); L.append(o[0]);E.append(o[1])
print('ort time/window',(time.time()-t)/len(X))
report('ONNX no_dft fp32 (ORT CPU) vs TF',np.concatenate(L),np.concatenate(E))
