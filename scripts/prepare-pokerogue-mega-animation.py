#!/usr/bin/env python3
"""Bundle pinned FormChangePhase particles/audio and source references for the battle adapter."""
import concurrent.futures,hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1];OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((OUT/'manifest.json').read_text());items=[]
for name in ['audio/se/charge.wav','audio/se/beam.wav','audio/se/sparkle.wav','audio/se/shine.wav','images/effects/evo_sparkle.png']:
 items.append(('pokerogue-assets',m['assetRevision'],name,name))
for name in ['phases/form-change-phase.ts','phases/evolution-phase.ts','animations.ts']:
 items.append(('pokerogue',m['runtimeRevision'],'src/'+name,'original/mega/'+name))
def fetch(item):
 repo,pin,name,dest=item;data=urllib.request.urlopen(f'https://raw.githubusercontent.com/pagefaultgames/{repo}/{pin}/{name}',timeout=30).read();return name,dest,data
with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:results=list(pool.map(fetch,items))
for name,dest,data in results:
 p=OUT/dest;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);m['sha256'][dest]=hashlib.sha256(data).hexdigest();m['originalPaths'][dest]=name
m['megaAssets']={'particle':'images/effects/evo_sparkle.png','sounds':{name:'audio/se/'+name+'.wav' for name in ['charge','beam','sparkle','shine']}}
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported original Mega transformation resources')
