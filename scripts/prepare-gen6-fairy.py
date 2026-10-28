#!/usr/bin/env python3
"""Import the reviewed Fairy-only supplement without replacing BW2 metadata or effects.
Requires cached PokéRogue locales and same-revision battle-anims in --source.
Network is used only for missing original effect dependencies during this explicit import.
"""
import argparse,csv,hashlib,json,pathlib,re,subprocess,urllib.request,urllib.parse,concurrent.futures
ROOT=pathlib.Path(__file__).resolve().parents[1]
PIN='009cac30c39d3615c7b2c320c3984af368871031'
RUNTIME='39fe0aa2c29a48fb57897c1b31b03e8039e59b15'
LOCALES='b24c6f3d1b3f4449440d0200487e614e69b5df3d'
LANGS={'ko':'ko','en':'en','ja':'ja','es':'es-ES','fr':'fr','pt':'pt-BR','de':'de','ru':'ru'}
SLUGS=['aromatic-mist','baby-doll-eyes','crafty-shield','dazzling-gleam','disarming-voice','draining-kiss','fairy-lock','fairy-wind','flower-shield','geomancy','light-of-ruin','misty-terrain','moonblast','play-rough']
key=lambda s:re.sub('[^a-z0-9]','',s.lower())
sha=lambda data:hashlib.sha256(data).hexdigest()
def write(path,data):path.write_text(json.dumps(data,ensure_ascii=False,separators=(',',':'))+'\n')
def main():
 parser=argparse.ArgumentParser();parser.add_argument('--source',type=pathlib.Path,required=True);args=parser.parse_args();source=args.source
 out=ROOT/'Sources/PokeTokenBar/Resources/BattleText';player=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
 engine=json.loads(subprocess.check_output([str(ROOT/'BattleEngine/runtime/node'),'-e',"const {Dex}=require('./BattleEngine/node_modules/pokemon-showdown');console.log(JSON.stringify(Object.fromEntries(Dex.mod('gen6').moves.all().filter(m=>m.gen===6&&m.type==='Fairy').map(m=>[m.id,{power:m.basePower,accuracy:m.accuracy,pp:m.pp,category:m.category,type:m.type}]))))"],cwd=ROOT,text=True))
 assert set(engine)=={key(s) for s in SLUGS}
 locales={lang:json.loads((source/'locales'/directory/'move.json').read_text()) for lang,directory in LANGS.items()}
 moves={};learnsets={}
 for slug in SLUGS:
  mid=key(slug);parts=slug.split('-');localeKey=parts[0]+''.join(p.title() for p in parts[1:])
  record={**engine[mid],'names':{},'descriptions':{}}
  for lang,data in locales.items():
   row=data[localeKey];description=' '.join(row['effect'].split())
   if mid=='moonblast':
    assert '10' in description or '１０' in description
    description=description.replace('10','30').replace('１０','３０')
   record['names'][lang]=row['name'];record['descriptions'][lang]=description
  moves[mid]=record
 with (ROOT/'docs/reference/gen6-fairy-move-learners.csv').open(encoding='utf-8-sig') as file:
  for row in csv.DictReader(file):
   mid=row['moveId'];assert mid in moves
   method=row['습득방식']
   if method=='특정 폼 레벨 기술':continue
   if method=='PokéRogue 고유 알 기술':name,level='pokerogue-egg',0
   elif '기술머신' in method:name,level='machine',0
   else:
    level=int(row['레벨']);name='level-up' if level>0 else 'evolution' if level==0 else 'relearn';level=max(0,level)
   slug=next(s for s in SLUGS if key(s)==mid)
   methods=learnsets.setdefault(row['전국도감번호'],{}).setdefault(slug,[])
   value={'method':name,'level':level}
   if value not in methods:methods.append(value)
 fairyNames=json.loads((out/'mega-text.json').read_text())['types']['fairy']
 write(out/'gen6-fairy.json',{'moves':moves,'types':{'fairy':fairyNames},'learnsets':learnsets})
 manifest=json.loads((player/'manifest.json').read_text());required=set();timelines={}
 for slug in SLUGS+['geomancy-charging']:
  mid='geomancy:charge' if slug=='geomancy-charging' else key(slug)
  raw=(source/'pinned'/(slug+'.json')).read_bytes();variants=json.loads(raw);variants=variants if isinstance(variants,list) else[variants]
  graphics=set();backgrounds=set();sounds=set()
  for v in variants:
   if v.get('graphic'):graphics.add(v['graphic'])
   for events in v.get('frameTimedEvents',{}).values():
    for event in events:
     if event.get('resourceName'):
      (sounds if event['eventType']=='AnimTimedSoundEvent' else backgrounds).add(event['resourceName'])
  required.update('images/battle_anims/'+p+'.png' for p in graphics|backgrounds)
  required.update('audio/battle_anims/'+p for p in sounds)
  file='animations/'+mid.replace(':','-')+'.json';(player/file).write_bytes(raw)
  manifest['entries'][mid]={'file':file,'graphics':sorted(graphics),'backgrounds':sorted(backgrounds),'sounds':sorted(sounds),'frames':[len(v['frames']) for v in variants]}
  manifest['sha256'][file]=sha(raw);manifest['originalPaths'][file]='battle-anims/'+slug+'.json'
  if ':' not in mid:manifest['aliases'][mid]=mid
  timelines[mid]={'file':file,'sha256':sha(raw),'sourcePath':'battle-anims/'+slug+'.json'}
 def fetch(name):
  path=player/name;cache=source/'effect-dependencies'/name
  if path.exists():return name,sha(path.read_bytes())
  if cache.exists():data=cache.read_bytes()
  else:
   url=f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{PIN}/'+urllib.parse.quote(name)
   data=urllib.request.urlopen(url,timeout=45).read();cache.parent.mkdir(parents=True,exist_ok=True);cache.write_bytes(data)
  path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data);return name,sha(data)
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
  for name,digest in pool.map(fetch,sorted(required)):manifest['sha256'][name]=digest
 manifest['fairyMoves']={'assetRevision':PIN,'moves':sorted(moves),'timelines':timelines}
 manifest['sha256']['server.cjs']=sha((player/'server.cjs').read_bytes())
 write(player/'manifest.json',manifest)
 fallbackPath=ROOT/'Sources/PokeTokenBar/Resources/BattleEffects/catalog.json';fallback=json.loads(fallbackPath.read_text())
 for mid in moves:assert mid in fallback['recipes'];fallback['aliases'][mid]=mid
 fallback['coverage']['catalogEntries']=len(fallback['aliases']);fallback['coverage']['canonicalMoves']=len(set(fallback['aliases'].values()))
 write(fallbackPath,fallback)
 provenance={'runtimeRevision':RUNTIME,'localeRevision':LOCALES,'assetRevision':PIN,'rules':'Showdown generation VI move definitions; Moonblast secondary chance 30%, including localized descriptions','learners':'Reviewed CSV; regular level/TM/pre-evolution routes and PokéRogue-specific egg moves; cosmetic/future forms excluded','sha256':{'learnersCSV':sha((ROOT/'docs/reference/gen6-fairy-move-learners.csv').read_bytes()),'gen6-fairy.json':sha((out/'gen6-fairy.json').read_bytes())},'locales':{lang:sha((source/'locales'/directory/'move.json').read_bytes()) for lang,directory in LANGS.items()},'timelines':timelines}
 write(out/'gen6-fairy-source.json',provenance)
 print('Imported',len(moves),'moves,',len(learnsets),'species,',len(timelines),'original timelines,',len(required),'referenced assets')
if __name__=='__main__':main()
