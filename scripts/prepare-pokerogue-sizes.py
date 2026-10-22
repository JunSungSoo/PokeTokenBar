#!/usr/bin/env python3
"""Extract original visible bounds from pinned PokéRogue atlas metadata (no sprite replacement)."""
import argparse,concurrent.futures,hashlib,json,pathlib,re,tempfile,urllib.request
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
a=argparse.ArgumentParser();a.add_argument('--tree',type=pathlib.Path);a.add_argument('--refresh',action='store_true');args=a.parse_args()
pin=json.loads((OUT/'manifest.json').read_text())['assetRevision']
target=OUT/'pokemon-sizes.json'
def ensure_notice():
 notice=OUT/'NOTICE.md'
 text=notice.read_text()
 if 'pokemon-sizes.json derives' not in text:
  notice.write_text(text+'\npokemon-sizes.json derives per-species/form/front/back visible animation bounds from\n'   'atlas JSON at the pinned asset revision. Each record preserves its source SHA-256;\n'   'prepare-pokerogue-sizes.py verifies source Git blob hashes before extraction. Existing\n'   'PokéAPI GIF artwork/cadence remains in use, fitted without distortion to those bounds.\n'   'All battlers share one camera scale. Native and original-player actors use the same\n'   'size/feet anchors; atlas cells retain natural dimensions instead of 64px normalization.\n')
ensure_notice()
if target.exists() and not args.refresh and json.loads(target.read_text())['assetRevision']==pin:
 print('Using pinned Pokémon size catalog',flush=True);raise SystemExit
cache=pathlib.Path(tempfile.gettempdir())/'ptb-pokerogue-size-atlases'/pin
if args.tree: tree=json.loads(args.tree.read_text())
else:
 request=urllib.request.Request(f'https://api.github.com/repos/pagefaultgames/pokerogue-assets/git/trees/{pin}?recursive=1',headers={'User-Agent':'PokeTokenBar-size-importer'})
 tree=json.load(urllib.request.urlopen(request,timeout=30))
assert not tree.get('truncated'),'Incomplete source tree'
entries=[t for t in tree['tree'] if re.fullmatch(r'images/pokemon/(?:back/)?\d+(?:-[^/]+)?\.json',t['path']) and 1<=int(re.search(r'/(\d+)',t['path']).group(1))<=649]
def extract(item):
 path=item['path'];file=cache/path
 if file.exists():data=file.read_bytes()
 else:
  data=urllib.request.urlopen(f'https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{pin}/{path}',timeout=40).read()
  file.parent.mkdir(parents=True,exist_ok=True);file.write_bytes(data)
 assert hashlib.sha1(b'blob '+str(len(data)).encode()+b'\0'+data).hexdigest()==item['sha'],path
 atlas=json.loads(data);textures=atlas.get('textures',[atlas]);frames=[f for t in textures for f in (t['frames'] if isinstance(t['frames'],list) else t['frames'].values())]
 left=min(f['spriteSourceSize']['x'] for f in frames);top=min(f['spriteSourceSize']['y'] for f in frames)
 right=max(f['spriteSourceSize']['x']+f['spriteSourceSize']['w'] for f in frames);bottom=max(f['spriteSourceSize']['y']+f['spriteSourceSize']['h'] for f in frames)
 key=path.removeprefix('images/pokemon/').removesuffix('.json')
 return key,dict(width=right-left,height=bottom-top,sha256=hashlib.sha256(data).hexdigest())
records={}
with concurrent.futures.ThreadPoolExecutor(max_workers=10) as pool:
 for i,(key,value) in enumerate(pool.map(extract,entries),1):
  records[key]=value
  if i%100==0:print(f'Original size metadata {i}/{len(entries)}',flush=True)
target.write_text(json.dumps(dict(assetRevision=pin,records=records),sort_keys=True,separators=(',',':'))+'\n')
print('Written',target,len(records),flush=True)
