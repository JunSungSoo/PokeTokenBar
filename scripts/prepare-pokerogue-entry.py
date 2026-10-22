#!/usr/bin/env python3
"""Import pinned original ball atlases, release sound and entry source references."""
import hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((OUT/'manifest.json').read_text())
assets=['images/pb.png','images/pb.json','images/effects/pb_particles.png','images/effects/pb_particles.json','audio/se/pb_rel.wav']
sources=['src/phases/summon-phase.ts','src/phases/switch-summon-phase.ts','src/animations.ts','src/data/pokeball.ts']
for repo,pin,files in [('pokerogue-assets',m['assetRevision'],assets),('pokerogue',m['runtimeRevision'],sources)]:
 for name in files:
  dest=name if repo=='pokerogue-assets' else 'original/entry/'+name.removeprefix('src/')
  target=OUT/dest
  data=target.read_bytes() if target.is_file() else urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/'+repo+'/'+pin+'/'+name,timeout=30).read()
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  m['sha256'][dest]=hashlib.sha256(data).hexdigest();m['originalPaths'][dest]=name
m['entryAssets']={'ball':'images/pb.json','particles':'images/effects/pb_particles.json','release':'audio/se/pb_rel.wav','ballType':'pb'}
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported original entry assets and source references')
