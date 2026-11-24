"""Rewrite Perch no_dft ONNX (opset 18) to opset 13 so onnx2torch can convert it.
Only ReduceL2/ReduceMax differ (axes input -> attribute); other ops are identical across 13..18 here."""
import sys, onnx
from onnx import numpy_helper, helper
src,dst=sys.argv[1],sys.argv[2]
m=onnx.load(src)
init={i.name:i for i in m.graph.initializer}
n_fix=0
for n in m.graph.node:
    if n.op_type in ('ReduceL2','ReduceMax') and len(n.input)>1:
        axes=numpy_helper.to_array(init[n.input[1]]).tolist()
        del n.input[1]
        keep=[a for a in n.attribute if a.name=='keepdims']
        del n.attribute[:]; n.attribute.extend(keep); n.attribute.append(helper.make_attribute('axes',axes)); n_fix+=1
for i,n in enumerate(m.graph.node): n.name=f'n{i}_{n.op_type}'
for o in m.opset_import:
    if o.domain in ('','ai.onnx'): o.version=13
onnx.checker.check_model(m, full_check=False)
onnx.save(m,dst)
print('rewrote',n_fix,'reduce nodes ->',dst)
