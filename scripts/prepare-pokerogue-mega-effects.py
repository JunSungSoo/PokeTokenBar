#!/usr/bin/env python3
"""Import the original Electric Terrain animation used by Mega Raichu X's ability."""
import hashlib,json,pathlib,urllib.request,urllib.parse
root=pathlib.Path(__file__).resolve().parents[1];out=root/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((out/'manifest.json').read_text());pin=m['assetRevision']
def copy(path,target=None):
 p=out/(target or path)
 data=p.read_bytes() if p.exists() else urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/'+pin+'/'+urllib.parse.quote(path),timeout=30).read()
 p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data)
 key=str(p.relative_to(out));m['sha256'][key]=hashlib.sha256(data).hexdigest();m['originalPaths'][key]=path
 return data
raw=copy('battle-anims/electric-terrain.json','animations/electric-terrain.json');definition=json.loads(raw)
variants=definition if isinstance(definition,list) else [definition]
graphics={v['graphic'] for v in variants if v.get('graphic')};backgrounds=set();sounds=set()
for variant in variants:
 for events in variant.get('frameTimedEvents',{}).values():
  for event in events:
   resource=event.get('resourceName')
   if resource:(sounds if event['eventType']=='AnimTimedSoundEvent' else backgrounds).add(resource)
for resource in graphics|backgrounds:copy('images/battle_anims/'+resource+'.png')
for resource in sounds:copy('audio/battle_anims/'+resource)
m['fieldEntries']['electricterrain']={'file':'animations/electric-terrain.json','graphics':sorted(graphics),'backgrounds':sorted(backgrounds),'sounds':sorted(sounds),'frames':[len(v['frames']) for v in variants]}
(out/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported original Electric Terrain assets')
