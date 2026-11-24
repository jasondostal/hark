import sys, time, collections, numpy as np, coremltools as ct
from parity import G, report
path=sys.argv[1]; idx=np.loadtxt(sys.argv[2],dtype=int) if len(sys.argv)>2 else None
X=G['x']
for cu in ['CPU_ONLY','CPU_AND_GPU','CPU_AND_NE','ALL']:
    t=time.time(); m=ct.models.MLModel(path,compute_units=getattr(ct.ComputeUnit,cu)); load=time.time()-t
    m.predict({'audio':X[:1]})
    L=[];E=[]; t=time.time()
    for i in range(len(X)):
        o=m.predict({'audio':X[i:i+1]}); L.append(o['logits'][0]);E.append(o['embedding'][0])
    ms=(time.time()-t)/len(X)*1000
    if 'spectrogram' in o:
        sp=np.array([m.predict({'audio':X[i:i+1]})['spectrogram'][0] for i in range(0,len(X),12)]); ref=G['spec'][::12]
        print('   spec max|diff|',float(np.abs(sp-ref).max()),'nonfinite',int((~np.isfinite(sp)).sum()),'ref range',float(ref.min()),float(ref.max()))
    print(f'{cu:12} load {load:5.1f}s  {ms:6.1f} ms/window')
    report(f'CoreML {cu}',np.array(L),np.array(E),idx=idx)
# per-op device plan
from coremltools.models.compute_plan import MLComputePlan
from coremltools.models.compute_device import MLNeuralEngineComputeDevice, MLGPUComputeDevice, MLCPUComputeDevice
cp=MLComputePlan.load_from_path(path=m.get_compiled_model_path(),compute_units=ct.ComputeUnit.ALL)
prog=cp.model_structure.program; c=collections.Counter(); cost=collections.Counter()
for fn in prog.functions.values():
    for op in fn.block.operations:
        u=cp.get_compute_device_usage_for_mlprogram_operation(op)
        if u is None: continue
        d=type(u.preferred_compute_device).__name__.replace('ML','').replace('ComputeDevice','')
        c[d]+=1
        e=cp.get_estimated_cost_for_mlprogram_operation(op); cost[d]+= e.weight if e else 0
print('ops by preferred device:',dict(c)); print('est. cost share:',{k:round(v,3) for k,v in cost.items()})
