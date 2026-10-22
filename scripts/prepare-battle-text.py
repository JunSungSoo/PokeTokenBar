#!/usr/bin/env python3
"""Build the checked-in, offline battle catalog from PokeAPI CSV + pinned Gen-V dex.
Optional missing-language translations use local Argos/CTranslate2 models, never a live service.
See Sources/PokeTokenBar/Resources/BattleText/README.md for provenance and regeneration.
"""
import argparse, csv, hashlib, json, pathlib, re
parser=argparse.ArgumentParser()
parser.add_argument('--source',type=pathlib.Path,required=True)
parser.add_argument('--models',type=pathlib.Path,required=True)
parser.add_argument('--output',type=pathlib.Path,default=pathlib.Path('Sources/PokeTokenBar/Resources/BattleText/catalog.json'))
a=parser.parse_args(); root=a.source
langs={'ja':1,'ko':3,'fr':5,'de':6,'es':7,'en':9,'pt':13}
all_langs=['ko','en','ja','es','fr','pt','de','ru']
def rows(file):return list(csv.DictReader(open(root/(file+'.csv'))))
def key(text):return re.sub('[^a-z0-9]','',text.lower())
def names(file,id_key):
 result={}
 for row in rows(file):
  for lang,ident in langs.items():
   if int(row['local_language_id'])==ident and row['name'].strip():result.setdefault(row[id_key],{})[lang]=row['name'].strip()
 return result
engine=json.loads((root/'engine-text.json').read_text())
move_names=names('move_names','move_id'); species_names=names('pokemon_species_names','pokemon_species_id')
ability_names=names('ability_names','ability_id');type_names=names('type_names','type_id')
orders={r['id']:int(r['order']) for r in rows('version_groups')}
def descriptions(file,id_key,maximum):
 flavors={};rank={}
 for row in rows(file):
  ident=row[id_key]
  if int(ident)>maximum:continue
  for lang,language_id in langs.items():
   if int(row['language_id'])!=language_id:continue
   order=orders[row['version_group_id']];priority=(abs(order-16),order>16)
   slot=(ident,lang)
   if slot not in rank or priority<rank[slot]:
    rank[slot]=priority;flavors.setdefault(ident,{})[lang]=' '.join(row['flavor_text'].replace('\u00ad','').split())
 return flavors
flavors=descriptions('move_flavor_text','move_id',559)
ability_flavors=descriptions('ability_flavor_text','ability_id',164)
result={'moves':{},'species':{},'aliases':{},'abilities':{},'abilityDescriptions':{},'types':{}}
for m in engine['moves']:
 if m['key'] in result['moves']:continue
 ident=str(m['id']);record={'names':dict(move_names[ident]),'descriptions':dict(flavors[ident])}
 # English is the engine's Gen-V explanation, including past-generation overrides.
 record['descriptions']['en']=m['desc'] or record['descriptions']['en'];result['moves'][m['key']]=record
 record.update({k:m[k] for k in ['power','pp','accuracy','category','type']})
for r in rows('moves'):
 if int(r['id'])<=559:
  match=next((m for m in engine['moves'] if m['id']==int(r['id'])),None)
  if match:result['moves'][key(r['identifier'])]=result['moves'][match['key']]
for s in engine['species']:
 ident=str(s['id']);result['species'][ident]=dict(species_names[ident]);result['aliases'][s['key']]=ident
for ability in engine['abilities']:
 ident=str(ability['id'])
 if ident in ability_names:
  result['abilities'][ability['key']]=dict(ability_names[ident])
  record=dict(ability_flavors[ident]);record['en']=ability['desc'] or record['en']
  result['abilityDescriptions'][ability['key']]=record
english_types=['normal','fighting','flying','poison','ground','rock','bug','ghost','steel','fire','water','grass','electric','psychic','ice','dragon','dark']
pt_types=['Normal','Lutador','Voador','Venenoso','Terrestre','Pedra','Inseto','Fantasma','Aço','Fogo','Água','Planta','Elétrico','Psíquico','Gelo','Dragão','Sombrio']
ru_types=['Нормальный','Боевой','Летающий','Ядовитый','Земляной','Каменный','Насекомый','Призрачный','Стальной','Огненный','Водный','Травяной','Электрический','Психический','Ледяной','Драконий','Тёмный']
for i,name in enumerate(english_types):
 result['types'][name]=dict(type_names[str(i+1)]);result['types'][name].update(pt=pt_types[i],ru=ru_types[i])
for lang in ['pt','ru']:
 import ctranslate2,sentencepiece
 p=a.models/('translate-en_'+lang+'-1_9');sp=sentencepiece.SentencePieceProcessor(model_file=str(p/'sentencepiece.model'))
 translator=ctranslate2.Translator(str(p/'model'),device='cpu',compute_type='int8',intra_threads=4)
 records=[]
 for record in result['moves'].values():records.extend([record['names'],record['descriptions']])
 records.extend(result['abilities'].values())
 records.extend(result['abilityDescriptions'].values())
 for record in result['species'].values():
  # Portuguese uses the international species names, not literal word translations.
  if lang=='pt':record[lang]=record['en']
  else:records.append(record)
 missing={r['en'] for r in records if not r.get(lang)}
 cache_file=root/('translated-'+lang+'.json')
 cache=json.loads(cache_file.read_text()) if cache_file.exists() else {}
 texts=sorted(missing-set(cache))
 for start in range(0,len(texts),32):
  batch=texts[start:start+32]
  translated=translator.translate_batch([sp.encode(t,out_type=str) for t in batch],beam_size=3,max_batch_size=32,max_decoding_length=256)
  for text,t in zip(batch,translated):cache[text]=' '.join(sp.decode(t.hypotheses[0]).replace('▁',' ').split())
  cache_file.write_text(json.dumps(cache,ensure_ascii=False));print(lang,min(start+32,len(texts)),len(texts),flush=True)
 for record in records:
  if not record.get(lang):record[lang]=cache[record['en']]
 # Review the demonstration move and standard battle terminology rather than trust raw MT.
 result['moves']['thunderbolt']['descriptions'][lang]={'pt':'Tem 10% de chance de paralisar o alvo.','ru':'С вероятностью 10% парализует цель.'}[lang]
# Explicitly reviewed translations used by UI fixtures and common gameplay.
for ident,name in {'25':'Пикачу','1':'Бульбазавр','4':'Чармандер','7':'Сквиртл','133':'Иви','448':'Лукарио'}.items():result['species'][ident]['ru']=name
for move,pt,ru in [('thunderbolt','Raio do Trovão','Удар молнии'),('protect','Proteção','Защита'),('quickattack','Ataque Rápido','Быстрая атака'),('voltswitch','Troca Elétrica','Вольт-свитч')]:
 result['moves'][move]['names'].update(pt=pt,ru=ru)
# Fallback proper-name transliteration when the general model retained a rare Latin species name.
latin={'a':'а','b':'б','c':'к','d':'д','e':'е','f':'ф','g':'г','h':'х','i':'и','j':'дж','k':'к','l':'л','m':'м','n':'н','o':'о','p':'п','q':'к','r':'р','s':'с','t':'т','u':'у','v':'в','w':'в','x':'кс','y':'и','z':'з'}
for record in result['species'].values():
 text=record['ru']
 if re.search('[A-Za-z]',text):
  text=''.join(latin.get(c.lower(),c).upper() if c.isupper() else latin.get(c,c) for c in text)
  record['ru']=text
for group in ['species','abilities','abilityDescriptions','types']:
 for ident,record in result[group].items():
  assert all(record.get(lang) for lang in all_langs),(group,ident,record)
for ident,record in result['moves'].items():
 assert all(record['names'].get(lang) and record['descriptions'].get(lang) for lang in all_langs),ident
assert len(result['species'])==649
sources={p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in root.glob('*.csv')}
a.output.parent.mkdir(parents=True,exist_ok=True)
a.output.write_text(json.dumps(result,ensure_ascii=False,separators=(',',':'),sort_keys=True)+'\n')
(a.output.parent/'source-sha256.json').write_text(json.dumps(sources,indent=2)+'\n')
print('Written',a.output,a.output.stat().st_size,flush=True)
