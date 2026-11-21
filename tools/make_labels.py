"""Build Hark's label table: Perch class index -> scientific name, English common name, group.
Sources: Perch labels.csv (iNat taxonomy + FSD50K events); OpenFauna (via birdnet-go) for names/class."""
import csv, gzip, json, sys
labels=[l.strip() for l in open(sys.argv[1])][1:]
want=set(labels)
en={}; en_us={}
with gzip.open('data/translations.csv.gz','rt') as f:
    for r in csv.reader(f):
        if r[0] in want:
            if r[1]=='en_us': en_us[r[0]]=r[2]
            elif r[1] in('en','en_uk') and r[0] not in en: en[r[0]]=r[2]
cls={}
with gzip.open('data/metadata.jsonl.gz','rt') as f:
    for line in f:
        d=json.loads(line); s=d['scientific_name']
        if s in want: cls[s]=(d.get('taxonomy') or {}).get('class','')
import collections
ebird=[l.strip() for l in open(sys.argv[1].replace('labels.csv','perch_v2_ebird_classes.csv'))][1:]
gen=collections.defaultdict(collections.Counter)
for k,v in cls.items():
    if v: gen[k.split()[0]][v]+=1
for i,s_ in enumerate(labels):
    if not cls.get(s_):
        if ebird[i]!='no_ebird_code': cls[s_]='Aves'
        elif gen.get(s_.split()[0]): cls[s_]=gen[s_.split()[0]].most_common(1)[0][0]
# Hand-filled genera that OpenFauna leaves without a class (checked 2026-11-21).
G_OVR={}
for g,ks in {'Mammalia':'Sciurus Mustela Panthera Colobus Hystrix Kobus Oryx Axis Capreolus Choloepus Erinaceus Lama Macropus Pan Pusa Aotus Apodemus Choeropsis Crocuta Diceros Elephas Enhydra Galea Herpestes Lemur Lycaon Mungos Mus Octodon Otaria Pelea Perameles Rangifer',
  'Amphibia':'Boana Trachycephalus Hylodes Rhacophorus Atelopus Aquarana Buergeria Eupsophus Pelodytes Ansonia Dendrobates Leptomantis Pipa Amolops Assa Boreorana Chiromantis Cochranella Hildebrandtia Ichthyophis Kassina Latonia Rhinoderma Sphaerotheca',
  'Insecta':'Conocephalus Tettigonia Lipotactes Odontura Platypleura Microcentrum Saga Pterolepis Anthophora Decticus Ewartia Osmia Polysarcus Ruspolia Aromia Cystosoma Hamadryas Prionotropis Prionus Pseudorhynchus Vanessa Pterophylla Locusta Gastrimargus Pamphagus Empusa Acanthosoma Anoplophora Atta Buprestis Chalcophora Euphoria Lasius Leiopus Leptoglossus Lucilia Malacosoma Orthosoma Perkinsiella Strategus Brachypremna Eumaeus Anartia Lamia Phoberus',
  'Aves':'Anarhynchus Pachyglossa Antigone Driophlox Hypsipetes Diomedea Otus Troglodytes Automolus Brachypteryx Campylorhynchus Contopus Emblema Hesperoburhinus Neophilydor Oenanthe Bubo Centropus Chloropsis Corvinella Cyanoderma Iole Lalage Lepidothrix Macronyx Monticola Psilopogon Quechuavis Rhynchocyclus Satizabalus Tanychlamys Xenops Goodfellowia'}.items():
    for k in ks.split(): G_OVR[k]=g
for s_ in labels:
    if not cls.get(s_) and s_.split()[0] in G_OVR: cls[s_]=G_OVR[s_.split()[0]]
GROUP={'Aves':'bird','Amphibia':'amphibian','Mammalia':'mammal','Insecta':'insect','Reptilia':'reptile','Actinopterygii':'fish'}
out=[]; miss=0
for s in labels:
    if ' ' not in s and ('_' in s or s[:1].isupper() and s not in cls):
        out.append({'s':s,'c':s.replace('_and_',' / ').replace('_',' '),'g':'sound'}); continue
    c=en_us.get(s) or en.get(s)
    if not c: miss+=1
    out.append({'s':s,'c':c or s,'g':GROUP.get(cls.get(s,''),'other' if s in cls else 'unknown')})
json.dump(out,open(sys.argv[2],'w'),separators=(',',':'))
from collections import Counter
print('classes',len(out),'no common name',miss, Counter(o['g'] for o in out))
for q in ['Canis latrans','Hyla versicolor','Sciurus carolinensis','Oecanthus fultoni','Bubo virginianus','Car_passing_by','Dog']:
    print([o for o in out if o['s']==q])
