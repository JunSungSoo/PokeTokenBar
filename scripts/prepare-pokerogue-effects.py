#!/usr/bin/env python3
"""Build an offline, effect-only catalog from the pinned PokéRogue asset checkout."""
import hashlib,json,pathlib,re,subprocess,sys
root=pathlib.Path(__file__).resolve().parent.parent
source=pathlib.Path(sys.argv[1]);pin='009cac30c39d3615c7b2c320c3984af368871031'
assert subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()==pin
base=json.loads((root/'Sources/PokeTokenBar/Resources/BattleEffects/catalog.json').read_text())
text=json.loads((root/'Sources/PokeTokenBar/Resources/BattleText/catalog.json').read_text())
dex=json.loads(subprocess.check_output(['node','-e',"const{Dex}=require('pokemon-showdown');console.log(JSON.stringify(Object.fromEntries(Dex.mod('gen5').moves.all().map(m=>[m.id,{desc:m.desc||m.shortDesc,type:m.type,category:m.category,target:m.target,boosts:m.boosts,self:m.self,heal:m.heal,weather:m.weather,sideCondition:m.sideCondition,status:m.status,volatileStatus:m.volatileStatus,flags:m.flags}]))));"],cwd=root/'BattleEngine',text=True))
out=root/'Sources/PokeTokenBar/Resources/PokeRogue';(out/'animations').mkdir(parents=True,exist_ok=True);(out/'images/battle_anims').mkdir(parents=True,exist_ok=True)
key=lambda s:re.sub('[^a-z0-9]','',s.lower())
paths={key(p.stem):p for p in (source/'battle-anims').glob('*.json')}
entries={};hashes={};originals={};sheets=set();bad=[]
def kind(mid,m):
 desc=m.get('desc','').lower()
 if mid=='rest' or m.get('heal') or 'regains' in desc or 'restores its' in desc:return 'heal'
 if mid=='flash':return 'flash'
 if mid in ['surf','muddywater','sludgewave','heatwave','ominouswind'] or 'gust of' in desc:return 'wave'
 if m.get('weather'):return 'weather'
 if mid in ['protect','detect','endure','wideguard','quickguard','reflect','lightscreen','safeguard','mist','magiccoat','substitute']:return 'shield'
 if mid in ['trick','switcheroo','skillswap','powerswap','guardswap','heartswap','allyswitch','powersplit','guardsplit','powertrick','speedswap']:return 'exchange'
 if mid in ['mimic','copycat','mirrormove','roleplay','transform','camouflage','conversion','conversion2','reflecttype']:return 'copy'
 if mid in ['minimize','doubleteam','snatch','quash','afteryou','teleport']:return 'vanish'
 if m.get('sideCondition'):return 'field'
 if m.get('boosts') or (m.get('self') or {}).get('boosts'):
  boosts=m.get('boosts') or m['self']['boosts']
  return 'debuff' if all(v<0 for v in boosts.values()) else 'boost'
 if m.get('flags',{}).get('sound'):return 'sound'
 if m.get('status') or m.get('volatileStatus'):return 'status'
 if m.get('category')=='Physical':return 'impact'
 if m.get('category')=='Special':return 'energy'
 return 'aura'
def add(mid,path,charge=False):
 data=json.loads(path.read_text());variants=data if isinstance(data,list) else [data];compiled=[];gcount=0;removed=0;hasbg=False;length=0
 m=dex.get(mid,{})
 for a in variants:
  graphic=a.get('graphic') or '';cells=0
  if graphic:
   import struct
   png=source/'images/battle_anims'/str(graphic+'.png')
   w,h=struct.unpack('>II',png.read_bytes()[16:24]);cells=w//96*(h//96)
  frames=[]
  for fs in a.get('frames',[]):
   effects=[]
   for f in fs:
    if not f or f.get('target')!=2:continue
    if not 0<=f.get('graphicFrame',0)<cells:
     removed+=1;continue
    effects.append(f)
   gcount+=sum(f.get('visible',True) and f.get('opacity',255)>0 for f in effects)
   frames.append(effects)
  events={k:[e for e in es if e.get('eventType') in ['AnimTimedAddBgEvent','AnimTimedUpdateBgEvent']] for k,es in a.get('frameTimedEvents',{}).items()}
  for es in events.values():
   for e in es:
    if e.get('eventType')=='AnimTimedAddBgEvent':
     hasbg=True
     if e.get('resourceName'):sheets.add(e['resourceName'])
  if graphic and any(frames):sheets.add(graphic)
  compiled.append({'graphic':graphic,'hue':a.get('hue',0),'frames':frames,'frameTimedEvents':events})
  length=max(length,len(frames),max([float(k)+float(e.get('duration',0)) for k,es in events.items() for e in es]+[0]))
 scope=base['recipes'].get(mid,{}).get('scope','target')
 classification='graphics' if gcount else 'background' if hasbg else 'empty' if not length else 'motion'
 semantic=kind(mid,m)
 if charge:semantic='charge'
 duration=min(3.6,max(0.85,length*0.05))
 if not gcount and not hasbg:duration=1.45
 if removed:bad.append({'move':mid,'phase':'charge' if charge else 'move','discarded':removed})
 k=mid+(':charge' if charge else '');file='animations/'+k.replace(':','-')+'.json'
 encoded=json.dumps(compiled,separators=(',',':'),ensure_ascii=False).encode();(out/file).write_bytes(encoded);hashes[file]=hashlib.sha256(encoded).hexdigest()
 original=str(path.relative_to(source));originals[original]=hashlib.sha256(path.read_bytes()).hexdigest()
 entries[k]={'file':file,'duration':duration,'length':length,'scope':scope,'kind':semantic,'supplement':gcount<8 or removed>0,'classification':classification,'discarded':removed,'description':text['moves'].get(mid,{}).get('descriptions',{}).get('ko','')}
for mid in sorted(set(base['aliases'].values())):
 assert mid in paths,mid
 add(mid,paths[mid])
for name,path in paths.items():
 if name.endswith('charging'):
  mid=name[:-8]
  if mid in entries:add(mid,path,True)
for name in sorted(sheets):
 p='images/battle_anims/'+name+'.png';data=(source/p).read_bytes();(out/p).write_bytes(data);hashes[p]=hashlib.sha256(data).hexdigest();originals[p]=hashes[p]
for p in ['README.md','REUSE.toml','battle-anims/REUSE.toml','images/REUSE.toml','LICENSES/AGPL-3.0-only.txt','LICENSES/CC-BY-NC-SA-4.0.txt','LICENSES/LicenseRef-POKEMON-REBORN.txt']:
 data=(source/p).read_bytes();dest=out/'notices'/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);hashes['notices/'+p]=hashlib.sha256(data).hexdigest()
(out/'catalog.json').write_text(json.dumps({'revision':pin,'aliases':base['aliases'],'entries':entries,'discarded':bad},separators=(',',':'),ensure_ascii=False))
(out/'source-sha256.json').write_text(json.dumps({'source':originals,'bundled':hashes},indent=2))
(out/'NOTICE.md').write_text('''# PokéRogue effect-only presentation data

Source: https://github.com/pagefaultgames/pokerogue-assets
Pinned revision: 009cac30c39d3615c7b2c320c3984af368871031.
Original PNG bytes are retained. Animation JSON is a derived effect-only representation:
USER/TARGET Pokémon transforms and all sound events are excluded. Only GRAPHIC entries and
timed background commands are imported. Out-of-bounds graphic indices are discarded and
listed in catalog.json; those moves require authored supplements. Generation tags are unknown.
No Pokémon sprite, stats, rules, moveset or audio/BGM is replaced by this catalog.

Original root/directory REUSE declarations and relevant full license/credit texts are in notices/.
JSON metadata includes AGPL-3.0-only and Pokémon Reborn / Gen8 Animation Project provenance.
Graphics retain the associated notices and default CC-BY-NC-SA-4.0 terms where applicable.
This collection is not a blanket MIT/CC0 asset pack. Preserve original authors/credits, source
links, license texts and source-sha256.json on redistribution. Source and derived file hashes
are recorded separately. Rebuild using scripts/prepare-pokerogue-effects.py with the pinned
external checkout. Source assets and original notices remain unmodified.
''')
print('Imported',len(entries),'timelines;',len(sheets),'PNG files;',len(bad),'frame-index exception records;',sum(e['supplement'] for e in entries.values()),'supplemented profiles')
