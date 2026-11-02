#!/usr/bin/env python3
"""Reconstruct Charizard's original pinned PokéRogue front/back/shiny animations."""
import hashlib,json,pathlib,subprocess,tempfile,urllib.request
root=pathlib.Path(__file__).resolve().parents[1]
player=root/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
pin=json.loads((player/'manifest.json').read_text())['assetRevision']
out=player/'base-sprites';out.mkdir(exist_ok=True)
records={};jobs=[]
for back in [False,True]:
 for shiny in [False,True]:
  stem=('back/' if back else '')+('shiny/' if shiny else '')+'6'
  paths=['images/pokemon/'+stem+ext for ext in ['.json','.png']]
  files=[];sources={}
  for path in paths:
   target=out/'source'/path;target.parent.mkdir(parents=True,exist_ok=True)
   url=f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{pin}/{path}'
   if not target.exists():target.write_bytes(urllib.request.urlopen(url,timeout=40).read())
   files.append(target);sources[path]={'url':url,'sha256':hashlib.sha256(target.read_bytes()).hexdigest()}
  frames=json.loads(files[0].read_bytes())['textures'][0]['frames']
  key=('back-' if back else '')+'6'+('-sh' if shiny else '')
  filename=key+('.gif' if len(frames)>1 else '.png')
  records[key]={'file':filename,'animated':len(frames)>1,'frames':len(frames),'fps':10,'assetRevision':pin,'sources':sources}
  jobs.append({'atlas':str(files[0]),'image':str(files[1]),'destination':str(out/filename)})
jobfile=pathlib.Path(tempfile.gettempdir())/'ptb-charizard-export.json';jobfile.write_text(json.dumps(jobs))
subprocess.run(['swift',str(root/'scripts/export-pokerogue-sprites.swift'),str(jobfile)],check=True)
for r in records.values():r['sha256']=hashlib.sha256((out/r['file']).read_bytes()).hexdigest()
(out/'manifest.json').write_text(json.dumps(records,separators=(',',':'))+'\n')
(out/'NOTICE.md').write_text(f'Original PokéRogue Charizard atlases at {pin}. Source bytes and hashes are retained in source/. Frames reconstruct the original canvas at 10 FPS. Preserve parent REUSE/license notices.\n')
print('Exported',len(records),'original Charizard variants')
