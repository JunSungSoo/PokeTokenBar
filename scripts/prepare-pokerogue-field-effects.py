#!/usr/bin/env python3
"""Import pinned, unmodified common weather/status timelines without changing move entries."""
import hashlib,json,pathlib,sys,urllib.request,urllib.parse
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
CACHE=pathlib.Path('/private/tmp/ptb-pokerogue-assets-review')
PIN='009cac30c39d3615c7b2c320c3984af368871031'
STATUS='--status' in sys.argv
NAMES=['sleep','poison','toxic','paralysis','confusion','burn','frozen','attract'] if STATUS else (['rain'] if '--pilot' in sys.argv else ['sunny','rain','sandstorm','hail'])
m=json.loads((OUT/'manifest.json').read_text())
assert m['assetRevision']==PIN
entries={}
def copy(name,dest=None):
 target=OUT/(dest or name);cached=CACHE/name
 if cached.is_file():data=cached.read_bytes()
 elif target.is_file():data=target.read_bytes()
 else:data=urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/'+PIN+'/'+urllib.parse.quote(name),timeout=30).read()
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 key=str(target.relative_to(OUT));m['sha256'][key]=hashlib.sha256(data).hexdigest();m['originalPaths'][key]=name
 return data
for name in NAMES:
 key='common'+name;dest='animations/common-'+name+'.json'
 raw=copy('battle-anims/common-'+name+'.json',dest);definition=json.loads(raw)
 variants=definition if isinstance(definition,list) else [definition]
 graphics={v['graphic'] for v in variants if v.get('graphic')};backgrounds=set();sounds=set()
 for v in variants:
  for events in v.get('frameTimedEvents',{}).values():
   for event in events:
    resource=event.get('resourceName')
    if resource:(sounds if event['eventType']=='AnimTimedSoundEvent' else backgrounds).add(resource)
 for resource in graphics|backgrounds:copy('images/battle_anims/'+resource+'.png')
 for resource in sounds:copy('audio/battle_anims/'+resource)
 entries[key]={'file':dest,'graphics':sorted(graphics),'backgrounds':sorted(backgrounds),'sounds':sorted(sounds),'frames':[len(v['frames']) for v in variants]}
m['statusEntries' if STATUS else 'fieldEntries']=entries
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported common '+('status' if STATUS else 'weather')+' effects:',', '.join(entries))
