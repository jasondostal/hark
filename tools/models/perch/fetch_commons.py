"""Optional: fetch Creative Commons recordings from Wikimedia Commons as parity audio.
Usage: python fetch_commons.py audio "Bubo virginianus" "Poecile atricapillus" ...
Writes audio/<species>.<ext> + audio/manifest.json (with each file's license). Check the licenses before you redistribute anything."""
import time, urllib.error, json, sys, urllib.request, urllib.parse, os
UA={'User-Agent':'hark-tools/0.1 (model parity audio)'}
def api(params):
    q='https://commons.wikimedia.org/w/api.php?'+urllib.parse.urlencode({**params,'format':'json'})
    return json.load(urllib.request.urlopen(urllib.request.Request(q,headers=UA)))
out=sys.argv[1]
species=sys.argv[2:]
manifest=[]
for sp in species:
    r=api({'action':'query','list':'search','srsearch':f'"{sp}" filetype:audio','srnamespace':6,'srlimit':5})
    hits=[h['title'] for h in r['query']['search']]
    got=None
    for t in hits:
        ii=api({'action':'query','titles':t,'prop':'imageinfo','iiprop':'url|size|extmetadata|mime'})
        p=next(iter(ii['query']['pages'].values()))['imageinfo'][0]
        if p['size']>8_000_000: continue
        fn=os.path.join(out, sp.replace(' ','_')+os.path.splitext(p['url'])[1].lower())
        if not os.path.exists(fn):
            for att in range(4):
                try:
                    time.sleep(3+att*10)
                    open(fn,'wb').write(urllib.request.urlopen(urllib.request.Request(p['url'],headers=UA)).read()); break
                except urllib.error.HTTPError as e:
                    if e.code!=429: raise
        lic=p.get('extmetadata',{}).get('LicenseShortName',{}).get('value')
        got={'species':sp,'file':fn,'title':t,'url':p['url'],'license':lic}
        break
    print(got or {'species':sp,'file':None,'hits':hits}); 
    if got: manifest.append(got)
json.dump(manifest,open(os.path.join(out,'manifest.json'),'w'),indent=1)
