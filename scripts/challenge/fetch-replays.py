#!/usr/bin/env python3
"""Fetch a bounded public BW OU sample. Training logs omit chat and player identities."""
import argparse,concurrent.futures,hashlib,json,re,time,urllib.request
from pathlib import Path
p=argparse.ArgumentParser();p.add_argument('--manifest',type=Path);p.add_argument('--pages',type=int,default=6);p.add_argument('--output',type=Path,default=Path('build/challenge-training/raw'));a=p.parse_args();a.output.mkdir(parents=True,exist_ok=True)
if not 1<=a.pages<=20:raise ValueError('Use 1–20 pages per explicit training run')
def get(url):
 for attempt in range(3):
  try:return json.load(urllib.request.urlopen(urllib.request.Request(url,headers={'User-Agent':'PokeTokenBar offline training sample'}),timeout=25))
  except Exception:
   if attempt==2:raise
   time.sleep(1+attempt)
ids=[];expected={}
if a.manifest:
 manifest=json.loads(a.manifest.read_text());ids=[r['id'] for r in manifest['files']];expected={r['id']:r['sha256'] for r in manifest['files']}
else:
 for page in range(1,a.pages+1):
  for r in get(f'https://replay.pokemonshowdown.com/search.json?format=gen5ou&page={page}'):
   if r.get('private')==0 and not r.get('password'):ids.append(r['id'])
  time.sleep(.3)
ids=list(dict.fromkeys(id for id in ids if re.fullmatch(r'gen5ou-[0-9]+(?:-[a-z0-9]+)?',id)))
def fetch(id):
 path=a.output/(id+'.json')
 if path.exists():return id not in expected or hashlib.sha256(path.read_bytes()).hexdigest()==expected[id]
 try:
  r=get('https://replay.pokemonshowdown.com/'+id+'.json')
  # No usernames, chat, player declarations or results containing a player's name.
  allowed={'poke','switch','drag','replace','move','turn','faint','-damage','-heal','-status','-curestatus','-boost','-unboost','-weather','-fieldstart','-fieldend','-sidestart','-sideend','-enditem','-item','-ability','-start','-end','-setboost','-clearboost','-clearallboost','-activate'}
  log='\n'.join(l for l in r['log'].splitlines() if l.startswith('|') and l.split('|')[1] in allowed)
  data={'id':id,'format':'gen5ou','source':'https://replay.pokemonshowdown.com/'+id,'log':log}
  encoded=json.dumps(data,separators=(',',':')).encode()
  if id in expected and hashlib.sha256(encoded).hexdigest()!=expected[id]:return False
  path.write_bytes(encoded);return True
 except Exception:return False
with concurrent.futures.ThreadPoolExecutor(max_workers=3) as pool:success=sum(pool.map(fetch,ids))
if a.manifest and success!=len(ids):raise RuntimeError('Pinned replay data could not be reproduced')
print(json.dumps({'requested':len(ids),'available':success,'directory':str(a.output)}))
