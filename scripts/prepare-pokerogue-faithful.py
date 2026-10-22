#!/usr/bin/env python3
"""Prepare an offline, pinned original-player comparison; never rewrite original timelines."""
import hashlib,json,pathlib,subprocess,urllib.request,concurrent.futures,os,tarfile,io,base64
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Tests/PokeTokenBarTests/Fixtures/PokeRogueFaithful'
ASSETS=pathlib.Path('/private/tmp/ptb-pokerogue-assets-review')
ASSET_REV='009cac30c39d3615c7b2c320c3984af368871031'
RUNTIME_REV='13f1139f0aef39fa75b8b57268832d6c1d9aa742'
MOVES=['thunderbolt','protect','quick-attack','volt-switch']
def fetch(url):return urllib.request.urlopen(url).read()
def main():
 assert subprocess.check_output(['git','-C',str(ASSETS),'rev-parse','HEAD'],text=True).strip()==ASSET_REV
 files={};paths=set()
 for move in MOVES:
  path='battle-anims/'+move+'.json';paths.add(path)
  data=json.loads((ASSETS/path).read_text())
  for a in data if isinstance(data,list) else [data]:
   if a.get('graphic'):paths.add('images/battle_anims/'+a['graphic']+'.png')
   for es in a.get('frameTimedEvents',{}).values():
    for e in es:
     if e.get('resourceName'):
      paths.add(('audio/battle_anims/'+e['resourceName']) if e['eventType']=='AnimTimedSoundEvent' else 'images/battle_anims/'+e['resourceName']+'.png')
 paths.update(['images/arenas/plains_bg.png','images/arenas/plains_a.png','images/arenas/plains_b.png','README.md','REUSE.toml','battle-anims/REUSE.toml','images/REUSE.toml','audio/REUSE.toml','LICENSES/AGPL-3.0-only.txt','LICENSES/CC-BY-NC-SA-4.0.txt','LICENSES/LicenseRef-POKEMON-REBORN.txt'])
 def asset(path):
  p=ASSETS/path
  data=p.read_bytes() if p.exists() else fetch(f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{ASSET_REV}/'+urllib.parse.quote(path))
  dest=OUT/path;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data)
  return path,hashlib.sha256(data).hexdigest()
 with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:files.update(pool.map(asset,sorted(paths)))
 for source,dest in [('src/data/battle-anims.ts','original/battle-anims.ts'),('src/pipelines/glsl/sprite-frag-shader.frag','original/sprite-frag-shader.frag'),('LICENSE','original/LICENSE')]:
  data=fetch(f'https://raw.githubusercontent.com/pagefaultgames/pokerogue/{RUNTIME_REV}/'+source)
  p=OUT/dest;p.parent.mkdir(parents=True,exist_ok=True);p.write_bytes(data);files[dest]=hashlib.sha256(data).hexdigest()
 for url,dest in [('https://cdn.jsdelivr.net/npm/phaser@3.90.0/dist/phaser.min.js','phaser.min.js'),('https://cdn.jsdelivr.net/npm/phaser@3.90.0/LICENSE.md','original/PHASER-LICENSE.txt')]:
  data=fetch(url);(OUT/dest).write_bytes(data);files[dest]=hashlib.sha256(data).hexdigest()
 source=(OUT/'original/battle-anims.ts').read_text()
 ranges=[source[source.index('export class AnimConfig'):source.index('export const moveAnims')],source[source.index('interface GraphicFrameData'):source.index('export class CommonBattleAnim')]]
 shim='''const Phaser=window.Phaser;
export let globalScene;
export function bindScene(scene){globalScene=scene;}
const settings={display:{enableMoveAnimations:true}};
const getFrameMs=(frames)=>frames*1000/60;
const getEnumValues=(e)=>Object.values(e).filter(v=>typeof v==='number');
const AnimFrameTarget={USER:0,TARGET:1,GRAPHIC:2};
const AnimFocus={TARGET:1,USER:2,USER_TARGET:3,SCREEN:4};
const AnimBlendType={NORMAL:0,ADD:1,SUBTRACT:2};
const BattlerTagType={SUBSTITUTE:'substitute'};
const audioManager={playSound:(key,config)=>globalScene.sound.play(key,{...config,volume:globalScene.audioEnabled?config.volume:0})};
'''
 (OUT/'adapter.ts').write_text(shim+'\n'.join(ranges))
 binary=ROOT/'build/tools/esbuild-0.25.0-arm64'
 if not binary.exists():
  package=json.loads(fetch('https://registry.npmjs.org/@esbuild/darwin-arm64/0.25.0'))
  archive=fetch(package['dist']['tarball'])
  assert 'sha512-'+base64.b64encode(hashlib.sha512(archive).digest()).decode()==package['dist']['integrity']
  data=tarfile.open(fileobj=io.BytesIO(archive)).extractfile('package/bin/esbuild').read()
  binary.parent.mkdir(parents=True,exist_ok=True);binary.write_bytes(data);binary.chmod(0o755)
 env=dict(os.environ,ESBUILD_BINARY_PATH=str(binary))
 subprocess.run([str(ROOT/'BattleEngine/runtime/node'),'-e',"const fs=require('fs'),e=require('./BattleEngine/node_modules/esbuild');const p=process.argv[1];fs.writeFileSync(p+'/original-player.js',e.transformSync(fs.readFileSync(p+'/adapter.ts','utf8'),{loader:'ts',format:'esm',target:'es2020'}).code)",str(OUT)],cwd=ROOT,check=True,env=env)
 (OUT/'manifest.json').write_text(json.dumps({'assetRevision':ASSET_REV,'runtimeRevision':RUNTIME_REV,'phaser':'3.90.0','moves':MOVES,'originalSHA256':files,'extractedRangesSHA256':[hashlib.sha256(r.encode()).hexdigest() for r in ranges]},indent=2)+'\n')
 (OUT/'NOTICE.md').write_text('''# PokéRogue original-player comparison prototype

Unmodified source timelines/assets: pagefaultgames/pokerogue-assets at '''+ASSET_REV+'''.
Unmodified runtime source: pagefaultgames/pokerogue at '''+RUNTIME_REV+'''.
`adapter.ts` extracts AnimConfig/timed events and BattleAnim verbatim, adding dependency shims.
`original-player.js` is its mechanically transpiled ES module. The host supplies Pokémon GIF
frames exported by the existing native SpriteLoader, scene anchors, a deterministic clock,
minimal tone shader and Phaser 3.90.0. Both comparison panels execute this same original player;
they are not independent implementations, and this is not a full running PokéRogue game.
Original code/derived adapter: AGPL-3.0-only. Phaser: MIT. Mixed asset licenses and credits:
retain REUSE metadata, README, LICENSES and this manifest on redistribution.
No animation commands, invalid frames or sound events are filtered from the four timelines.
''')
 print('Prepared original player:',len(files),'hashed source files')
if __name__=='__main__':main()
