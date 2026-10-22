#!/usr/bin/env python3
"""Import pinned original ball atlases, release sound and entry source references."""
import hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((OUT/'manifest.json').read_text())
assets=['images/pb.png','images/pb.json','images/effects/pb_particles.png','images/effects/pb_particles.json','audio/se/pb_rel.wav','images/effects/shiny.png','images/effects/shiny.json','audio/se/sparkle.wav']
sources=['src/phases/summon-phase.ts','src/phases/switch-summon-phase.ts','src/animations.ts','src/data/pokeball.ts','src/phases/shiny-sparkle-phase.ts']
for repo,pin,files in [('pokerogue-assets',m['assetRevision'],assets),('pokerogue',m['runtimeRevision'],sources)]:
 for name in files:
  dest=name if repo=='pokerogue-assets' else 'original/entry/'+name.removeprefix('src/')
  target=OUT/dest
  data=target.read_bytes() if target.is_file() else urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/'+repo+'/'+pin+'/'+name,timeout=30).read()
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
  m['sha256'][dest]=hashlib.sha256(data).hexdigest();m['originalPaths'][dest]=name
m['entryAssets']={'ball':'images/pb.json','particles':'images/effects/pb_particles.json','release':'audio/se/pb_rel.wav','ballType':'pb','shiny':'images/effects/shiny.json','sparkle':'audio/se/sparkle.wav'}
notice=OUT/'NOTICE.md'
if 'Standard shiny entries append' not in notice.read_text():
 notice.write_text(notice.read_text()+'\nStandard shiny entries append the original shiny atlas (35 frames at 32fps) and\n'
  'se/sparkle.wav after ball appearance/settle. This preserves the authored animation\n'
  'through its final frame (1093.75ms), exceeding ShinySparklePhase\'s 1000ms wait slightly\n'
  'so the next native action cannot cut the sparkle short. Both assets retain pinned bytes.\n')
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported original entry assets and source references')
