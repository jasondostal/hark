"""Make Perch's spectrogram frontend fp16-safe (ANE) without changing its fp32 math.
  1. Fold gain S into the window multiply (frontend is linear up to the log).
  2. Replace ReduceL2 over (re,im) with hypot = hi*sqrt(1+(lo/hi)^2): no squaring of tiny/huge values.
  3. Floor max(mel, 1e-5) -> max(mel_S, S*1e-5); then log(.) - log(S).
Input: opset-13 Perch no_dft ONNX (from to_opset13.py). """
import sys, math, numpy as np, onnx
from onnx import numpy_helper as nh, helper as h
src,dst=sys.argv[1],sys.argv[2]; S=float(sys.argv[3]) if len(sys.argv)>3 else 1024.0
m=onnx.load(src); g=m.graph
init={i.name:i for i in g.initializer}
def const(name,arr): g.initializer.append(nh.from_array(np.asarray(arr,dtype=np.float32),name)); return name
nodes=list(g.node)
# 1. window constant (Mul feeding the Pad before DFT)
win=[n for n in nodes if n.op_type=='Mul' and 'frontend/mul2' in n.output[0]][0]
cname=[x for x in win.input if x in init][0]
arr=nh.to_array(init[cname])*S; init[cname].CopyFrom(nh.from_array(arr.astype(np.float32),cname))
# 2. ReduceL2 -> hypot
r=[n for n in nodes if n.op_type=='ReduceL2'][0]; x=r.input[0]; out=r.output[0]
i0=h.make_tensor('hyp_i0',onnx.TensorProto.INT64,[],[0]); i1=h.make_tensor('hyp_i1',onnx.TensorProto.INT64,[],[1]); g.initializer.extend([i0,i1])
eps=const('hyp_eps',S*1e-9); one=const('hyp_one',1.0)
new=[h.make_node('Gather',[x,'hyp_i0'],['hyp_a'],axis=-1,name='hyp_ga'),
     h.make_node('Gather',[x,'hyp_i1'],['hyp_b'],axis=-1,name='hyp_gb'),
     h.make_node('Abs',['hyp_a'],['hyp_aa'],name='hyp_absa'), h.make_node('Abs',['hyp_b'],['hyp_ab'],name='hyp_absb'),
     h.make_node('Max',['hyp_aa','hyp_ab'],['hyp_hi'],name='hyp_max'), h.make_node('Min',['hyp_aa','hyp_ab'],['hyp_lo'],name='hyp_min'),
     h.make_node('Add',['hyp_hi',eps],['hyp_hie'],name='hyp_add_eps'),
     h.make_node('Div',['hyp_lo','hyp_hie'],['hyp_r'],name='hyp_div'),
     h.make_node('Mul',['hyp_r','hyp_r'],['hyp_r2'],name='hyp_sq'),
     h.make_node('Add',['hyp_r2',one],['hyp_1r2'],name='hyp_add1'),
     h.make_node('Sqrt',['hyp_1r2'],['hyp_s'],name='hyp_sqrt'),
     h.make_node('Mul',['hyp_hi','hyp_s'],[out],name='hyp_out')]
pos=nodes.index(r); nodes[pos:pos+1]=new
# 3. floor + log offset
mx=[n for n in nodes if n.op_type=='Max' and 'magnitude_scaling/max2' in n.output[0]][0]
fl=[x for x in mx.input if x in init][0]; init[fl].CopyFrom(nh.from_array(np.asarray(nh.to_array(init[fl])*S,dtype=np.float32),fl))
lg=[n for n in nodes if n.op_type=='Log'][0]; lo=lg.output[0]; lg.output[0]='log_scaled'
off=const('log_offset',-math.log(S))
nodes.insert(nodes.index(lg)+1,h.make_node('Add',['log_scaled',off],[lo],name='log_unscale'))
# 4. framing Conv (identity 640-tap kernel, stride 320, pad 160) -> pad + reshape + concat (exact, ANE-safe)
conv=[n for n in nodes if n.op_type=='Conv'][0]; ci=nodes.index(conv)
assert nodes[ci+1].op_type=='Transpose' and nodes[ci+2].op_type=='Reshape'
frames_out=nodes[ci+2].output[0]
def I64(name,vals):
    g.initializer.append(nh.from_array(np.asarray(vals,dtype=np.int64),name)); return name
fr=[h.make_node('Pad',['inputs',I64('fr_pads',[0,160,0,160])],['fr_padded'],mode='constant',name='fr_pad'),
    h.make_node('Reshape',['fr_padded',I64('fr_shape',[-1,501,320])],['fr_rows'],name='fr_reshape'),
    h.make_node('Slice',['fr_rows',I64('fr_s0',[0]),I64('fr_e0',[500]),I64('fr_ax',[1])],['fr_a'],name='fr_slice_a'),
    h.make_node('Slice',['fr_rows',I64('fr_s1',[1]),I64('fr_e1',[501]),'fr_ax'],['fr_b'],name='fr_slice_b'),
    h.make_node('Concat',['fr_a','fr_b'],[frames_out],axis=-1,name='fr_concat')]
nodes[ci:ci+3]=fr
nodes=[n for n in nodes if not (n.op_type=='Reshape' and n.input[0]=='inputs')]  # old 4D reshape now unused
del g.node[:]; g.node.extend(nodes)
for i,n in enumerate(g.node): n.name=f'n{i}_{n.op_type}'
onnx.checker.check_model(m); onnx.save(m,dst); print('saved',dst,'S=',S)
