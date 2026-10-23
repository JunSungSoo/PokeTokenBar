#!/usr/bin/env python3
"""Import pinned normal-hit audio and the original damage/weather source references."""
import hashlib,json,pathlib,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((OUT/'manifest.json').read_text())
for repo,pin,name,dest in [
 ('pokerogue-assets',m['assetRevision'],'audio/se/hit.wav','audio/se/hit.wav'),
 ('pokerogue',m['runtimeRevision'],'src/phases/damage-anim-phase.ts','original/weather/damage-anim-phase.ts'),
 ('pokerogue',m['runtimeRevision'],'src/phases/weather-effect-phase.ts','original/weather/weather-effect-phase.ts')]:
 target=OUT/dest
 data=target.read_bytes() if target.exists() else urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/'+repo+'/'+pin+'/'+name,timeout=30).read()
 target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 m['sha256'][dest]=hashlib.sha256(data).hexdigest();m['originalPaths'][dest]=name
m['weatherHitAssets']={'sound':'audio/se/hit.wav'}
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
notice=OUT/'NOTICE.md'
if 'Weather damage hit feedback' not in notice.read_text():
 notice.write_text(notice.read_text()+'\nWeather damage hit feedback adapts DamageAnimPhase\'s 100ms sprite blinking and\nse/hit.wav. Original weather INDIRECT damage intentionally omits this feedback;\nthe host explicitly enables normal-hit feedback for actual BW2 sandstorm/hail\ndamage at the user\'s request, with no damage numbers/notices. The authored hit\naudio is unchanged; the six visibility states end at 500ms before HP interpolation.\n')
print('Imported original normal-hit sound and weather/damage source references')
