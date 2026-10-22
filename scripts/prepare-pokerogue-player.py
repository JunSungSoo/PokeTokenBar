#!/usr/bin/env python3
"""Bundle complete unfiltered PokéRogue timelines for the production original player."""
import pathlib,json,re,hashlib,urllib.request,urllib.parse,concurrent.futures,struct,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
SOURCE=pathlib.Path('/private/tmp/ptb-pokerogue-assets-review')
PREVIEW=ROOT/'Tests/PokeTokenBarTests/Fixtures/PokeRogueFaithful'
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
PIN='009cac30c39d3615c7b2c320c3984af368871031'
key=lambda s:re.sub('[^a-z0-9]','',s.lower())
def main():
 OUT.mkdir(parents=True,exist_ok=True)
 old=json.loads((ROOT/'Sources/PokeTokenBar/Resources/PokeRogue/catalog.json').read_text())
 paths={key(p.stem):p for p in (SOURCE/'battle-anims').glob('*.json')}
 entries={};required=set();hashes={};origins={}
 for mid in sorted(old['entries']):
  sourceKey=mid.replace(':charge','charging');p=paths[sourceKey]
  data=p.read_bytes();variants=json.loads(data);variants=variants if isinstance(variants,list) else [variants]
  dest='animations/'+mid.replace(':','-')+'.json';(OUT/dest).parent.mkdir(parents=True,exist_ok=True);(OUT/dest).write_bytes(data)
  hashes[dest]=hashlib.sha256(data).hexdigest();origins[dest]=str(p.relative_to(SOURCE))
  backgrounds=set();sounds=set();graphics=set()
  for a in variants:
   if a.get('graphic'):graphics.add(a['graphic'])
   for events in a.get('frameTimedEvents',{}).values():
    for e in events:
     if e.get('resourceName'):
      if e['eventType']=='AnimTimedSoundEvent':sounds.add(e['resourceName'])
      else:backgrounds.add(e['resourceName'])
  required.update('images/battle_anims/'+n+'.png' for n in graphics|backgrounds)
  required.update('audio/battle_anims/'+n for n in sounds)
  entries[mid]={'file':dest,'graphics':sorted(graphics),'backgrounds':sorted(backgrounds),'sounds':sorted(sounds),'frames':[len(a['frames']) for a in variants]}
 required.update(['images/arenas/plains_bg.png','images/arenas/plains_a.png','images/arenas/plains_b.png','README.md','REUSE.toml','battle-anims/REUSE.toml','images/REUSE.toml','audio/REUSE.toml','LICENSES/AGPL-3.0-only.txt','LICENSES/CC-BY-NC-SA-4.0.txt','LICENSES/LicenseRef-POKEMON-REBORN.txt'])
 def copy(name):
  local=SOURCE/name;cached=PREVIEW/name;dest=OUT/name
  if local.exists():data=local.read_bytes()
  elif cached.exists():data=cached.read_bytes()
  elif dest.exists():data=dest.read_bytes()
  else:
   for attempt in range(6):
    try:
     data=urllib.request.urlopen(f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{PIN}/'+urllib.parse.quote(name),timeout=30).read();break
    except Exception:
     if attempt==5:raise
     time.sleep(attempt+1)
  dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  return name,hashlib.sha256(data).hexdigest()
 with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:
  for i,(path,digest) in enumerate(pool.map(copy,sorted(required))):
   hashes[path]=digest
   if i%100==0:print('Resources',i,'/',len(required),flush=True)
 for name in ['original-player.js','adapter.ts','phaser.min.js','original/battle-anims.ts','original/LICENSE','original/PHASER-LICENSE.txt','original/sprite-frag-shader.frag','server.cjs']:
  p=OUT/name;p.parent.mkdir(parents=True,exist_ok=True);data=(PREVIEW/name).read_bytes();p.write_bytes(data);hashes[name]=hashlib.sha256(data).hexdigest()
 m=json.loads((PREVIEW/'manifest.json').read_text())
 (OUT/'manifest.json').write_text(json.dumps({'assetRevision':PIN,'runtimeRevision':m['runtimeRevision'],'phaser':m['phaser'],'entries':entries,'aliases':old['aliases'],'sha256':hashes,'originalPaths':origins},separators=(',',':')))
 (OUT/'NOTICE.md').write_text('''# PokéRogue original production animation player

Complete source timelines, GRAPHIC/USER/TARGET commands, timed backgrounds and sounds are
bundled without filtering. Pinned assets: pagefaultgames/pokerogue-assets '''+PIN+'''.
The verbatim AnimConfig/timed-event and BattleAnim source ranges are transpiled mechanically
from runtime '''+m['runtimeRevision']+'''. Phaser version '''+m['phaser']+'''.
Host adapters supply current native GIF frames, actual battle anchors, guarded lifecycle and
serialized frame stepping. Showdown remains the authoritative BW2 battle rules engine.
Original and derived runtime code: AGPL-3.0-only. Phaser: MIT. Mixed asset licenses/credits:
see root/directory REUSE.toml, README, original/LICENSE and LICENSES. Preserve all notices and
manifest hashes on redistribution. No claim of a blanket MIT or CC0 asset license.
''')
 print('Complete:',len(entries),'unfiltered timelines,',len(hashes),'hashed resources',flush=True)
if __name__=='__main__':main()
