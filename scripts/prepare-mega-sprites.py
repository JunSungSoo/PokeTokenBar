#!/usr/bin/env python3
"""Bundle only pinned PokéRogue Mega atlases; reconstruct frames without replacing art."""
import concurrent.futures,hashlib,json,pathlib,subprocess,tempfile,time,urllib.request,urllib.error,uuid
root=pathlib.Path(__file__).resolve().parents[1]
player=root/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
out=player/'mega-sprites';out.mkdir(exist_ok=True)
pin=json.loads((player/'manifest.json').read_text())['assetRevision']
records=json.loads((root/'BattleEngine/held-items.json').read_text())['items']
cache=pathlib.Path(tempfile.gettempdir())/'ptb-pokerogue-mega-atlases'/pin
base=f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{pin}/'
def download(path,optional=False):
 target=cache/path
 if target.exists():return target
 for attempt in range(4):
  try:data=urllib.request.urlopen(base+path,timeout=40).read();break
  except urllib.error.HTTPError as e:
   if optional and e.code==404:return None
   if attempt==3:raise
  except Exception:
   if attempt==3:raise
  time.sleep(attempt+1)
 target.parent.mkdir(parents=True,exist_ok=True)
 staging=target.with_name(target.name+"."+uuid.uuid4().hex);staging.write_bytes(data);staging.replace(target);return target

def fetch(args):
 item,back,shiny=args;m=item['mega'];stem=str(m['baseID'])+'-'+m['form']
 key=('back-' if back else '')+stem+('-sh' if shiny else '')
 facing='back/' if back else ''
 color='shiny/' if shiny else ''
 atlas_path='images/pokemon/'+facing+color+stem+'.json'
 image_path='images/pokemon/'+facing+color+stem+'.png'
 atlas=download(atlas_path,optional=shiny);image=download(image_path,optional=shiny)
 fallback=False
 if atlas is None or image is None:
  atlas_path='images/pokemon/'+facing+stem+'.json';image_path='images/pokemon/'+facing+stem+'.png'
  atlas=download(atlas_path);image=download(image_path);fallback=True
 metadata=json.loads(atlas.read_bytes());textures=metadata.get('textures',[metadata]);assert len(textures)==1
 frames=textures[0]['frames']
 assert frames and all(not f['rotated'] for f in frames),key
 animated=len(frames)>1;filename=key+('.gif' if animated else '.png')
 sources={p:{'url':base+p,'sha256':hashlib.sha256(file.read_bytes()).hexdigest()} for p,file in [(atlas_path,atlas),(image_path,image)]}
 # Keep the exact source bytes so provenance and frame extraction can be verified offline.
 for p,file in [(atlas_path,atlas),(image_path,image)]:
  target=out/'source'/p;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(file.read_bytes())
 result={'file':filename,'url':base+image_path,'animated':animated,'frames':len(frames),'fps':10,'assetRevision':pin,'atlas':'source/'+atlas_path,'image':'source/'+image_path,'sources':sources}
 if fallback:result['fallback']='normal-color-same-facing'
 job={'atlas':str(atlas),'image':str(image),'destination':str(out/filename)}
 return key,result,job
jobs=[(i,b,s) for i in records if i.get('mega') for b in [False,True] for s in [False,True]]
with concurrent.futures.ThreadPoolExecutor(max_workers=8) as pool:results=list(pool.map(fetch,jobs))
jobfile=cache/'export-jobs.json';jobfile.write_text(json.dumps([r[2] for r in results]))
subprocess.run(['swift',str(root/'scripts/export-pokerogue-sprites.swift'),str(jobfile)],check=True)
manifest={}
for key,record,_ in results:
 record['sha256']=hashlib.sha256((out/record['file']).read_bytes()).hexdigest();manifest[key]=record
(out/'manifest.json').write_text(json.dumps(manifest,separators=(',',':'))+'\n')
# Remove obsolete generated Showdown/PokéAPI files only after every original export succeeds.
keep={r['file'] for r in manifest.values()}
for p in out.iterdir():
 if p.suffix in ['.gif','.png'] and p.name not in keep:p.unlink()
(out/'NOTICE.md').write_text(f'''# PokéRogue Mega-form sprites

Original front/rear/standard shiny atlases from pagefaultgames/pokerogue-assets at
{pin}. Source PNG and JSON bytes, paths and SHA-256 hashes are preserved in source/.
Native images reconstruct each TexturePacker frame on its original transparent canvas;
multi-frame atlases keep the runtime's 10 FPS and loop. Single-frame originals remain
static. No Showdown, PokeAPI, base-form or front-for-rear substitutions are used.
Any unavailable standard shiny variant is explicitly recorded as a same-facing normal
color fallback in manifest.json. Preserve the parent PokéRogue REUSE/license notices.
''')
print('Bundled',len(manifest),'PokéRogue Mega variants;',sum(r['animated'] for r in manifest.values()),'animated;',sum(bool(r.get('fallback')) for r in manifest.values()),'explicit color fallbacks')
