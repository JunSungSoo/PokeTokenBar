#!/usr/bin/env python3
"""Bundle pinned original cries for every BW2 species and its distinct cry forms."""
import concurrent.futures,hashlib,json,pathlib,urllib.request,time
ROOT=pathlib.Path(__file__).resolve().parents[1]
OUT=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
m=json.loads((OUT/'manifest.json').read_text())
keys=[str(i) for i in range(1,650)]+['492-sky','641-therian','642-therian','645-therian','646-black','646-white']
def fetch(key):
 name='audio/cry/'+key+'.m4a';target=OUT/name
 if target.is_file():data=target.read_bytes()
 else:
  for attempt in range(3):
   try:
    data=urllib.request.urlopen('https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/'+m['assetRevision']+'/'+name,timeout=30).read();break
   except Exception:
    if attempt==2:raise
    time.sleep(attempt+1)
  target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes(data)
 return key,name,hashlib.sha256(data).hexdigest()
with concurrent.futures.ThreadPoolExecutor(max_workers=12) as pool:results=list(pool.map(fetch,keys))
m['cries']={key:name for key,name,_ in results}
for _,name,digest in results:m['sha256'][name]=digest;m['originalPaths'][name]=name
(OUT/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported',len(results),'original BW2 species/form cries')

notice=OUT/'NOTICE.md'
if 'Entry cries use original pinned' not in notice.read_text():
 notice.write_text(notice.read_text()+"\nEntry cries use original pinned"+" audio/cry/*.m4a for all 649 BW2 species and six\nforms with distinct cries (Sky Shaymin, Therian trio, Black/White Kyurem).\nPokemonSpecies.getCryKey selects these form suffixes; other supported forms use\nthe species cry. SummonPhase starts the cry after the 250ms growth animation,\nslowing it to 0.85x at HP <=25%. The host's existing 1.25x appearance clock is\npreserved; cry audio retains its original rate, subject only to the low-HP rule.\nCries share the user's effects volume, play only on the foreground audio owner,\nand extend the serialized entry lifetime if their decoded duration requires it.\nAll original asset hashes, audio REUSE notices and licenses remain applicable.\n")
