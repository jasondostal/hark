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
cls={}; tax={}; inat={}
with gzip.open('data/metadata.jsonl.gz','rt') as f:
    for line in f:
        d=json.loads(line); s=d['scientific_name']
        if s in want:
            tax[s]=d.get('taxonomy') or {}
            cls[s]=tax[s].get('class','')
            i=((d.get('links') or {}).get('inaturalist') or {}).get('id')
            if i and str(i).isdigit(): inat[s]=int(i)
import collections
ebird=[l.strip() for l in open(sys.argv[1].replace('labels.csv','perch_v2_ebird_classes.csv'))][1:]
gen=collections.defaultdict(collections.Counter)
for k,v in cls.items():
    if v: gen[k.split()[0]][v]+=1
ANIMAL={'Aves','Amphibia','Mammalia','Insecta','Reptilia','Actinopterygii','Arachnida','Malacostraca','Gastropoda','Bivalvia','Cephalopoda'}
for i,s_ in enumerate(labels):
    # An eBird code always means bird: OpenFauna puts some bird genera under plant homonyms (Antigone = cranes).
    if ebird[i]!='no_ebird_code': cls[s_]='Aves'; continue
    if cls.get(s_) not in ANIMAL:
        if gen.get(s_.split()[0]): cls[s_]=gen[s_.split()[0]].most_common(1)[0][0]
# Hand-filled genera that OpenFauna leaves without a class (checked 2026-11-21).
G_OVR={}
for g,ks in {'Mammalia':'Sciurus Mustela Panthera Colobus Hystrix Kobus Oryx Axis Capreolus Choloepus Erinaceus Lama Macropus Pan Pusa Aotus Apodemus Choeropsis Crocuta Diceros Elephas Enhydra Galea Herpestes Lemur Lycaon Mungos Mus Octodon Otaria Pelea Perameles Rangifer',
  'Amphibia':'Boana Trachycephalus Hylodes Rhacophorus Atelopus Aquarana Buergeria Eupsophus Pelodytes Ansonia Dendrobates Leptomantis Pipa Amolops Assa Boreorana Chiromantis Cochranella Hildebrandtia Ichthyophis Kassina Latonia Rhinoderma Sphaerotheca',
  'Insecta':'Conocephalus Tettigonia Lipotactes Odontura Platypleura Microcentrum Saga Pterolepis Anthophora Decticus Ewartia Osmia Polysarcus Ruspolia Aromia Cystosoma Hamadryas Prionotropis Prionus Pseudorhynchus Vanessa Pterophylla Locusta Gastrimargus Pamphagus Empusa Acanthosoma Anoplophora Atta Buprestis Chalcophora Euphoria Lasius Leiopus Leptoglossus Lucilia Malacosoma Orthosoma Perkinsiella Strategus Brachypremna Eumaeus Anartia Lamia Phoberus Broughtonia Galanga',
  'Aves':'Anarhynchus Pachyglossa Antigone Driophlox Hypsipetes Diomedea Otus Troglodytes Automolus Brachypteryx Campylorhynchus Contopus Emblema Hesperoburhinus Neophilydor Oenanthe Bubo Centropus Chloropsis Corvinella Cyanoderma Iole Lalage Lepidothrix Macronyx Monticola Psilopogon Quechuavis Rhynchocyclus Satizabalus Tanychlamys Xenops Goodfellowia Corypha Veles'}.items():
    for k in ks.split(): G_OVR[k]=g
for s_ in labels:
    if cls.get(s_) not in ANIMAL and s_.split()[0] in G_OVR: cls[s_]=G_OVR[s_.split()[0]]
GROUP={'Aves':'bird','Amphibia':'amphibian','Mammalia':'mammal','Insecta':'insect','Reptilia':'reptile','Actinopterygii':'fish'}
# Species without OpenFauna taxonomy borrow their genus's most common order/family; a few have no congeners.
GEN_TAX=collections.defaultdict(collections.Counter)
for sp,t in tax.items():
    if t.get('order'): GEN_TAX[sp.split()[0]][(t['order'],t.get('family',''))]+=1
GEN_TAX_OVR={'Bubo':('Strigiformes','Strigidae'),'Otus':('Strigiformes','Strigidae'),'Sciurus':('Rodentia','Sciuridae'),
             'Mustela':('Carnivora','Mustelidae'),'Panthera':('Carnivora','Felidae'),'Lycaon':('Carnivora','Canidae'),
             'Herpestes':('Carnivora','Herpestidae'),'Mungos':('Carnivora','Herpestidae'),'Crocuta':('Carnivora','Hyaenidae'),
             'Erinaceus':('Eulipotyphla','Erinaceidae'),'Macropus':('Diprotodontia','Macropodidae'),'Elephas':('Proboscidea','Elephantidae'),
             'Diceros':('Perissodactyla','Rhinocerotidae'),'Choeropsis':('Artiodactyla','Hippopotamidae'),'Enhydra':('Carnivora','Mustelidae'),
             'Otaria':('Carnivora','Otariidae'),'Pusa':('Carnivora','Phocidae'),'Rangifer':('Artiodactyla','Cervidae'),
             'Capreolus':('Artiodactyla','Cervidae'),'Axis':('Artiodactyla','Cervidae'),'Choloepus':('Pilosa','Choloepodidae'),
             'Pan':('Primates','Hominidae'),'Mus':('Rodentia','Muridae'),'Apodemus':('Rodentia','Muridae'),'Diomedea':('Procellariiformes','Diomedeidae')}

def emoji(s, c, g):
    """A picture per kind of animal (by order/family/genus), or per kind of sound."""
    t=tax.get(s,{}); o=t.get('order',''); f=t.get('family',''); gn=s.split()[0]; k=cls.get(s,'')
    if not o:
        if gn in GEN_TAX_OVR: o,f=GEN_TAX_OVR[gn]
        elif GEN_TAX.get(gn): o,f=GEN_TAX[gn].most_common(1)[0][0]
    if g=='bird':
        if o=='Strigiformes': return '🦉'
        if gn in ('Cygnus','Coscoroba'): return '🦢'
        if o=='Anseriformes': return '🦆'
        if o in ('Accipitriformes','Falconiformes','Cathartiformes'): return '🦅'
        if gn=='Meleagris': return '🦃'
        if o=='Galliformes': return '🐓'
        if o=='Columbiformes': return '🕊️'
        if o=='Psittaciformes': return '🦜'
        if o=='Sphenisciformes': return '🐧'
        if o=='Phoenicopteriformes': return '🦩'
        if f=='Corvidae': return '🐦‍⬛'
        return '🐦'
    if g=='amphibian': return '🦎' if o=='Caudata' else '🪱' if o=='Gymnophiona' else '🐸'
    if g=='insect':
        if f=='Formicidae': return '🐜'
        if o=='Hymenoptera': return '🐝'
        if f=='Culicidae': return '🦟'
        if o=='Diptera': return '🪰'
        if f=='Coccinellidae': return '🐞'
        if o=='Coleoptera': return '🪲'
        if o=='Lepidoptera': return '🦋'
        return '🦗'   # crickets, katydids, grasshoppers, cicadas: the singers
    if g=='mammal':
        if o=='Chiroptera': return '🦇'
        if f=='Sciuridae': return '🐿️'
        if f=='Castoridae': return '🦫'
        if o=='Rodentia': return '🐭'
        if o=='Lagomorpha': return '🐰'
        if gn in ('Vulpes','Urocyon'): return '🦊'
        if f=='Canidae': return '🐺'
        if gn=='Panthera': return '🦁' if s=='Panthera leo' else '🐅'
        if f=='Felidae': return '🐆'
        if f=='Ursidae': return '🐻'
        if f=='Procyonidae': return '🦝'
        if f=='Mephitidae': return '🦨'
        if gn in ('Lutra','Lontra','Enhydra','Aonyx','Pteronura'): return '🦦'
        if f=='Mustelidae': return '🦡'
        if f in ('Otariidae','Phocidae','Odobenidae'): return '🦭'
        if f=='Cervidae': return '🦌'
        if f=='Suidae': return '🐗'
        if f=='Delphinidae': return '🐬'
        if f in ('Balaenopteridae','Balaenidae','Physeteridae','Monodontidae','Eschrichtiidae'): return '🐋'
        if f=='Hominidae': return '🦍'
        if o=='Primates': return '🐒'
        if o=='Proboscidea': return '🐘'
        if f=='Equidae': return '🐴'
        if f=='Rhinocerotidae': return '🦏'
        if f=='Hippopotamidae': return '🦛'
        if f=='Giraffidae': return '🦒'
        if f=='Camelidae': return '🐪'
        if f=='Bovidae': return '🐃'
        if f=='Macropodidae': return '🦘'
        if f=='Phascolarctidae': return '🐨'
        if f=='Erinaceidae': return '🦔'
        if o=='Pilosa': return '🦥'
        return '🐾'
    if g=='reptile':
        if o=='Crocodylia': return '🐊'
        if o=='Testudines': return '🐢'
        if f in ('Colubridae','Viperidae','Elapidae','Boidae','Pythonidae','Natricidae','Dipsadidae','Lamprophiidae'): return '🐍'
        return '🦎'
    if g=='fish': return '🐟'
    if g=='sound':
        n=c.lower()
        for keys,e in [(('dog','bark','growl'),'🐕'),(('cat','meow','purr'),'🐈'),(('chicken','rooster','fowl'),'🐓'),(('crow',),'🐦‍⬛'),
                       (('gull',),'🐦'),(('chirp','tweet'),'🐦'),(('frog',),'🐸'),(('cricket','insect','buzz'),'🦗'),(('livestock','wild animals','animal','pets'),'🐾'),
                       (('cough','sneeze','respiratory','breathing','gasp','sigh','burp','fart'),'😮‍💨'),(('laugh','giggle','chuckle'),'😆'),
                       (('cry','scream','shout','yell'),'😱'),(('singing',),'🎤'),(('speech','conversation','voice','whisper','chatter','crowd','child'),'🗣️'),
                       (('typing','keyboard','typewriter'),'⌨️'),(('aircraft','airplane'),'✈️'),(('train','rail','subway'),'🚆'),(('motorcycle',),'🏍️'),
                       (('truck','bus'),'🚚'),(('bicycle',),'🚲'),(('boat',),'🚤'),(('car','vehicle','traffic','engine','idling','revving','race'),'🚗'),
                       (('thunder',),'⛈️'),(('rain','raindrop'),'🌧️'),(('wind',),'💨'),(('ocean','waves','stream','water','drip','trickle','liquid','pour','splash','gurgl','sink','bathtub','toilet','faucet','boiling','fill'),'💧'),
                       (('fire','crackle'),'🔥'),(('gunshot','explosion','boom','fireworks'),'💥'),(('bell','chime','doorbell','gong'),'🔔'),
                       (('telephone','ringtone','alarm'),'📞'),(('clock','tick'),'⏰'),(('door','knock','drawer','cupboard','slam'),'🚪'),
                       (('walk','footsteps','run'),'👣'),(('clap','applause','cheer','hands','snapping'),'👏'),
                       (('drill','saw','hammer','tool','ratchet','mechanism','fan','printer','microwave'),'🔧'),
                       (('guitar','piano','drum','music','instrument','cymbal','organ','harp','trumpet','accordion','harmonica','marimba','glockenspiel','tabla','tambourine','percussion','strum','hi-hat','cowbell','rattle (instrument)','scratching'),'🎵'),
                       (('glass','dishes','cutlery','chink','shatter'),'🍽️'),(('chewing','frying'),'🍳')]:
            if any(k in n for k in keys): return e
        return '🔊'
    if k=='Arachnida': return '🕷️'
    if k=='Malacostraca': return '🦀'
    if k in ('Gastropoda',): return '🐌'
    if k in ('Bivalvia',): return '🐚'
    if k=='Cephalopoda': return '🐙'
    return '❔'

out=[]; miss=0
for s in labels:
    if ' ' not in s and ('_' in s or s[:1].isupper() and s not in cls):
        c=s.replace('_and_',' / ').replace('_',' ')
        out.append({'s':s,'c':c,'g':'sound','e':emoji(s,c,'sound')}); continue
    c=en_us.get(s) or en.get(s)
    if not c: miss+=1
    g=GROUP.get(cls.get(s,''),'other' if s in cls else 'unknown')
    o={'s':s,'c':c or s,'g':g,'e':emoji(s,c or s,g)}
    if s in inat: o['i']=inat[s]
    out.append(o)
json.dump(out,open(sys.argv[2],'w'),separators=(',',':'))
from collections import Counter
print('classes',len(out),'no common name',miss, Counter(o['g'] for o in out))
print('emoji', Counter(o['e'] for o in out).most_common(25))
for q in ['Antigone canadensis','Corvus brachyrhynchos','Strix varia','Anas platyrhynchos','Pseudacris crucifer','Tamias striatus','Typing','Cough','Respiratory_sounds','Canis latrans','Hyla versicolor','Sciurus carolinensis','Oecanthus fultoni','Bubo virginianus','Car_passing_by','Dog']:
    print([o for o in out if o['s']==q])
