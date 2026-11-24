"""Write Hark's parity fixtures from golden.npz (made by ref.py from YOUR audio):
  HarkCore/Tests/HarkCoreTests/Fixtures/golden_windows.f32 + golden.json   (swift test: GoldenParityTests)
  Hark/Resources/selftest.f32 + selftest.json                             (the app's -selftest launch argument)
Picks the most confident windows, one per top-1 species. All four files are git-ignored: they are your recordings.
Usage: python make_fixtures.py [n_golden=12] [n_selftest=3]"""
import json, os, sys, numpy as np
from common import LABELS
G=np.load('golden.npz',allow_pickle=True)
n_golden=int(sys.argv[1]) if len(sys.argv)>1 else 12; n_self=int(sys.argv[2]) if len(sys.argv)>2 else 3
ROOT=os.path.join(os.path.dirname(os.path.abspath(__file__)),'..','..','..')
L=G['label']; top1=L.argmax(1); conf=L.max(1)
pick=[];seen=set()
for i in np.argsort(-conf):
    if top1[i] in seen: continue
    seen.add(top1[i]); pick.append(int(i))
    if len(pick)==n_golden: break
def refs(ix): return [{'species':LABELS[top1[i]],'top1':int(top1[i]),'top5':[int(j) for j in np.argsort(-L[i])[:5]],'top1_logit':float(conf[i])} for i in ix]
def write(dirpath,stem,ix):
    os.makedirs(dirpath,exist_ok=True)
    G['x'][ix].astype(np.float32).tofile(os.path.join(dirpath,stem+'.f32'))
    json.dump(refs(ix),open(os.path.join(dirpath,stem+'.json'),'w'),indent=1)
    print(f'wrote {os.path.normpath(os.path.join(dirpath,stem))}.f32/.json: {len(ix)} windows')
write(os.path.join(ROOT,'HarkCore','Tests','HarkCoreTests','Fixtures'),'golden_windows',pick)
os.replace(os.path.join(ROOT,'HarkCore','Tests','HarkCoreTests','Fixtures','golden_windows.json'),
           os.path.join(ROOT,'HarkCore','Tests','HarkCoreTests','Fixtures','golden.json'))
write(os.path.join(ROOT,'Hark','Resources'),'selftest',pick[:n_self])
print('then: run tools/convert_birdnet3.py again to write birdnet3_selftest.json for the same windows')
