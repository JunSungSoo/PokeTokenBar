#!/usr/bin/env python3
"""Generate offline display heights from PokéAPI CSV (the collection's height source)."""
import csv, hashlib, json, pathlib, sys
ROOT=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(sys.argv[1]);out=ROOT/'Sources/PokeTokenBar/Resources/PokeRoguePlayer'
rows=list(csv.DictReader((source/'pokemon.csv').open()))
species={int(r['id']):r['identifier'] for r in csv.DictReader((source/'pokemon_species.csv').open())}
records={}
for r in rows:
 sid=int(r['species_id']);height=int(r['height'])
 if sid>649 or height<=0:continue
 key=str(sid) if r['is_default']=='1' else str(sid)+'-'+r['identifier'].removeprefix(species[sid]+'-')
 records[key]={'decimetres':height,'pokemonID':int(r['id'])}
by_id={int(r['id']):r for r in rows}
for item in json.loads((ROOT/'BattleEngine/held-items.json').read_text())['items']:
 if 'mega' not in item:continue
 m=item['mega'];r=by_id[m['pokemonID']]
 assert int(r['height'])>0
 records[str(m['baseID'])+'-'+m['form']]={'decimetres':int(r['height']),'pokemonID':m['pokemonID']}
assert all(str(i) in records for i in range(1,650))
data={'source':'https://github.com/PokeAPI/pokeapi/tree/master/data/v2/csv','sha256':{n:hashlib.sha256((source/n).read_bytes()).hexdigest() for n in ['pokemon.csv','pokemon_species.csv']},'records':records}
p=out/'pokemon-heights.json';p.write_text(json.dumps(data,separators=(',',':')))
m=json.loads((out/'manifest.json').read_text());m['sha256'][p.name]=hashlib.sha256(p.read_bytes()).hexdigest()
for name in ['pokemon.csv','pokemon_species.csv']:
 dest='original/physical/'+name;target=out/dest;target.parent.mkdir(parents=True,exist_ok=True);target.write_bytes((source/name).read_bytes())
 m['sha256'][dest]=hashlib.sha256(target.read_bytes()).hexdigest();m['originalPaths'][dest]=data['source']+'/'+name
(out/'manifest.json').write_text(json.dumps(m,separators=(',',':')))
print('Imported physical heights:',len(records))
