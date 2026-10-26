#!/usr/bin/env python3
"""Generate the shared offline whitelist/localizations from PokéAPI CSV and pinned rules.
Usage: BattleEngine/runtime/node scripts/export-held-items.cjs > SOURCE/rules.json
       python3 scripts/prepare-held-items.py SOURCE
"""
import csv,json,re,sys,hashlib,pathlib
root=pathlib.Path(__file__).resolve().parents[1];source=pathlib.Path(sys.argv[1])
langs=['ko','en','ja','es','fr','pt','de','ru'];language_ids={'ko':3,'en':9,'ja':1,'es':7,'fr':5,'de':6}
def key(s):return re.sub('[^a-z0-9]','',s.lower())
def rows(n):return list(csv.DictReader((source/(n+'.csv')).open()))
api_items={key(r['identifier']):r['id'] for r in rows('items')}
names={}
for r in rows('item_names'):
 for lang,n in language_ids.items():
  if r['local_language_id']==str(n):names.setdefault(r['item_id'],{})[lang]=r['name']
base=json.loads((root/'Sources/PokeTokenBar/Resources/BattleText/catalog.json').read_text())
records=json.loads((source/'rules.json').read_text())
pt=['Lenço de Seda','Carvão','Água Mística','Ímã','Semente Milagrosa','Gelo Eterno','Faixa Preta','Espinho Venenoso','Areia Macia','Bico Afiado','Colher Torta','Pó Prateado','Pedra Dura','Amuleto Maldito','Presa de Dragão','Óculos Escuros','Revestimento Metálico','Orbe da Vida','Cinto Especialista','Faixa Muscular','Óculos Sábios','Metrônomo','Joia Normal','Restos','Sino de Concha','Raiz Grande','Faixa de Foco','Banda de Foco','Capacete Rochoso','Balão de Ar','Lenço da Escolha','Garra Rápida','Bola de Ferro','Fruta Sitrus','Fruta Lum']
ru=['Шёлковый шарф','Древесный уголь','Мистическая вода','Магнит','Чудесное семя','Нетающий лёд','Чёрный пояс','Ядовитый шип','Мягкий песок','Острый клюв','Изогнутая ложка','Серебряный порошок','Твёрдый камень','Проклятый амулет','Клык дракона','Чёрные очки','Металлическое покрытие','Сфера жизни','Пояс эксперта','Мускульная лента','Очки мудреца','Метроном','Самоцвет нормального типа','Объедки','Ракушечный колокольчик','Большой корень','Лента фокуса','Повязка фокуса','Каменный шлем','Воздушный шар','Шарф выбора','Быстрый коготь','Железный шар','Ягода Ситрус','Ягода Лум']
# Authored descriptions describe this project's BW2 rules, not modern Champions changes.
desc={}
def d(id,text):desc[id]=dict(zip(langs,text.split('|')))
d('lifeorb','공격 기술의 위력 1.3배. 명중 시 최대 HP의 1/10을 잃습니다.|Damaging moves deal 1.3× damage; a successful attack costs 1/10 max HP.|攻撃技の威力1.3倍。命中時に最大HPの1/10を失う。|Potencia los ataques ×1,3; al acertar pierde 1/10 de PS máximos.|Attaques ×1,3 ; perd 1/10 des PV max après une attaque réussie.|Ataques ×1,3; ao acertar perde 1/10 dos PS máximos.|Angriffe ×1,3; nach einem Treffer verliert der Träger 1/10 der maximalen KP.|Урон атак ×1,3; успешная атака отнимает 1/10 максимальных ОЗ.')
d('expertbelt','효과가 굉장한 공격의 위력 1.2배.|Supereffective attacks deal 1.2× damage.|効果抜群の攻撃の威力1.2倍。|Ataques supereficaces ×1,2.|Attaques super efficaces ×1,2.|Ataques superefetivos ×1,2.|Sehr effektive Angriffe ×1,2.|Сверхэффективные атаки наносят урон ×1,2.')
d('muscleband','물리 기술의 위력 1.1배.|Physical move power ×1.1.|物理技の威力1.1倍。|Potencia física ×1,1.|Puissance physique ×1,1.|Poder físico ×1,1.|Physische Stärke ×1,1.|Сила физических атак ×1,1.')
d('wiseglasses','특수 기술의 위력 1.1배.|Special move power ×1.1.|特殊技の威力1.1倍。|Potencia especial ×1,1.|Puissance spéciale ×1,1.|Poder especial ×1,1.|Spezielle Stärke ×1,1.|Сила специальных атак ×1,1.')
d('metronome','같은 기술을 연속 사용하면 위력이 20%씩 증가합니다. 최대 2배.|Consecutive uses of one move gain 20% power each, up to 2×; another move resets it.|同じ技を連続使用すると威力が20%ずつ上がる。最大2倍。|Repetir un movimiento suma 20% de potencia, hasta ×2; cambiar reinicia.|Même capacité répétée : +20% à chaque fois, jusqu’à ×2 ; changer annule.|Repetir o golpe soma 20% de poder, até ×2; trocar o golpe reinicia.|Gleiche Attacke in Folge: je +20% Stärke, maximal ×2; andere Attacke setzt zurück.|Повтор одного приёма добавляет 20% силы, до ×2; другой приём сбрасывает бонус.')
d('normalgem','노말 공격의 위력 1.5배. 한 번 사용하면 배틀 중 소모됩니다.|First successful Normal-type attack has 1.5× power. Consumed in battle.|ノーマル技の威力1.5倍。一度使うと消費。|Primer ataque Normal ×1,5. Se consume.|Première attaque Normal ×1,5. Consommé.|Primeiro ataque Normal ×1,5. Consumida.|Erster erfolgreicher Normal-Angriff ×1,5. Wird verbraucht.|Первая успешная нормальная атака ×1,5. Расходуется.')
d('leftovers','매 턴 종료 시 최대 HP의 1/16 회복.|Restores 1/16 max HP at each turn end.|毎ターン終了時に最大HPの1/16回復。|Recupera 1/16 de PS máximos al final del turno.|Restaure 1/16 des PV max en fin de tour.|Recupera 1/16 dos PS máximos no fim do turno.|Regeneriert am Rundenende 1/16 der maximalen KP.|В конце хода восстанавливает 1/16 максимальных ОЗ.')
d('shellbell','공격으로 준 피해의 1/8만큼 HP를 회복합니다.|Restores HP equal to 1/8 of damage dealt by an attack.|与えたダメージの1/8だけHP回復。|Recupera PS iguales a 1/8 del daño causado.|Restaure des PV égaux à 1/8 des dégâts infligés.|Recupera PS iguais a 1/8 do dano causado.|Heilt KP in Höhe von 1/8 des verursachten Schadens.|Восстанавливает ОЗ в размере 1/8 нанесённого урона.')
d('bigroot','흡수 기술 등으로 회복하는 HP가 1.3배가 됩니다.|HP drained from opponents and effects such as Ingrain restore 1.3× HP.|吸収技やねをはる等の回復量1.3倍。|La curación por drenaje y efectos como Arraigo aumenta ×1,3.|Soins par drainage et effets comme Racines ×1,3.|Cura por drenagem e efeitos como Enraizar ×1,3.|Heilung durch Absaugen und Effekte wie Verwurzler ×1,3.|Исцеление от поглощения и эффектов вроде Укоренения ×1,3.')
d('focussash','HP가 가득 찼을 때 일격으로 쓰러질 공격을 HP 1로 버팁니다. 소모형.|At full HP, survives an otherwise fatal attack with 1 HP. Consumed.|満タン時に一撃で倒される攻撃をHP1で耐える。消費。|Con PS completos resiste un golpe mortal con 1 PS. Se consume.|PV pleins : résiste à une attaque fatale avec 1 PV. Consommé.|Com PS cheios, sobrevive a um ataque fatal com 1 PS. Consumida.|Bei vollen KP überlebt der Träger einen tödlichen Angriff mit 1 KP. Verbraucht.|При полных ОЗ переживает смертельную атаку с 1 ОЗ. Расходуется.')
d('focusband','10% 확률로 쓰러질 공격을 HP 1로 버팁니다.|10% chance to survive an otherwise fatal attack with 1 HP.|10%の確率で倒される攻撃をHP1で耐える。|10% de resistir un ataque mortal con 1 PS.|10% de chances de survivre à une attaque fatale avec 1 PV.|10% de sobreviver a um ataque fatal com 1 PS.|Überlebt einen tödlichen Angriff mit 10% Chance bei 1 KP.|10% шанс пережить смертельную атаку с 1 ОЗ.')
d('rockyhelmet','접촉 공격을 받으면 공격자에게 최대 HP의 1/6 피해를 줍니다.|Contact attackers lose 1/6 of their max HP.|接触した相手に最大HPの1/6のダメージ。|El atacante por contacto pierde 1/6 de PS máximos.|Un attaquant au contact perd 1/6 de ses PV max.|Atacantes de contato perdem 1/6 dos PS máximos.|Angreifer mit Kontakt verlieren 1/6 ihrer maximalen KP.|Атакующий при контакте теряет 1/6 максимальных ОЗ.')
d('airballoon','공중에 떠 땅 기술을 피합니다. 공격에 맞으면 터집니다.|Floats above Ground attacks and grounded hazards; pops when hit by an attack.|浮いて地面技等を回避。攻撃を受けると割れる。|Flota y evita ataques Tierra y trampas del suelo; un ataque lo rompe.|Évite les attaques Sol et les pièges au sol ; éclate sous une attaque.|Flutua e evita ataques Terrestres e armadilhas do chão; estoura ao ser atingido.|Schwebt über Boden-Angriffen und Bodenfallen; platzt bei einem Treffer.|Защищает от земляных атак и наземных ловушек; лопается при попадании атаки.')
d('choicescarf','스피드 1.5배. 교체 전까지 처음 사용한 기술만 사용할 수 있습니다.|Speed ×1.5, but locks the first move used until switching out.|素早さ1.5倍。交代まで最初に使った技しか使えない。|Velocidad ×1,5; solo permite el primer movimiento hasta retirarse.|Vitesse ×1,5 ; bloque sur la première capacité jusqu’au changement.|Velocidade ×1,5; prende ao primeiro golpe até sair de campo.|Initiative ×1,5; bis zum Wechsel nur die zuerst genutzte Attacke.|Скорость ×1,5; до замены доступен только первый использованный приём.')
d('quickclaw','같은 우선도 안에서 20% 확률로 먼저 행동합니다.|20% chance to move first within the same priority bracket.|同じ優先度内で20%の確率で先に行動。|20% de actuar primero dentro de la misma prioridad.|20% de chances d’agir en premier à priorité égale.|20% de agir primeiro na mesma faixa de prioridade.|20% Chance, bei gleicher Priorität zuerst zu handeln.|20% шанс действовать первым при одинаковом приоритете.')
d('ironball','스피드가 절반이 되고 땅에 닿아 땅 기술을 받습니다.|Halves Speed and grounds the holder, exposing it to Ground attacks.|素早さ半分。地面に降りて地面技が当たる。|Reduce Velocidad a la mitad y lo expone a ataques Tierra.|Divise la Vitesse par deux et rend sensible aux attaques Sol.|Reduz Velocidade à metade e expõe a ataques Terrestres.|Halbiert die Initiative und macht den Träger für Boden-Angriffe erreichbar.|Вдвое снижает скорость и приземляет, делая уязвимым к земляным атакам.')
d('sitrusberry','HP가 절반 이하가 되면 최대 HP의 1/4을 회복합니다. 소모형.|At half HP or less, restores 1/4 max HP. Consumed.|HP半分以下で最大HPの1/4回復。消費。|Con la mitad de PS o menos recupera 1/4 de PS máximos. Se consume.|À la moitié des PV ou moins, restaure 1/4 des PV max. Consommée.|Com metade dos PS ou menos, recupera 1/4 dos PS máximos. Consumida.|Bei halben KP oder weniger: heilt 1/4 der maximalen KP. Verbraucht.|При половине ОЗ или меньше восстанавливает 1/4 максимальных ОЗ. Расходуется.')
d('lumberry','상태이상 또는 혼란을 치료합니다. 소모형.|Cures a status condition or confusion. Consumed.|状態異常か混乱を回復。消費。|Cura un problema de estado o confusión. Se consume.|Soigne un statut ou la confusion. Consommée.|Cura um problema de estado ou confusão. Consumida.|Heilt ein Statusproblem oder Verwirrung. Verbraucht.|Снимает статусное состояние или замешательство. Расходуется.')
d('toxicorb','매 턴 종료 시 상태이상이 없고 독에 걸릴 수 있으면 맹독 상태가 됩니다. 소모되지 않습니다.|At turn end, badly poisons the holder if it has no status and can be poisoned. Not consumed.|ターン終了時、状態異常がなく毒が有効なら猛毒になる。消費しない。|Al final del turno envenena gravemente al portador si no tiene otro estado y puede ser envenenado. No se consume.|En fin de tour, empoisonne gravement le porteur sans statut s’il peut être empoisonné. Non consommé.|No fim do turno, envenena gravemente o portador se ele não tiver outro estado e puder ser envenenado. Não é consumido.|Vergiftet den Träger am Rundenende schwer, wenn er keinen Status hat und vergiftet werden kann. Wird nicht verbraucht.|В конце хода сильно отравляет владельца, если у него нет другого статуса и он может быть отравлен. Не расходуется.')
authored_names=dict(zip([r['id'] for r in records if not r.get('mega') and r['id']!='toxicorb'],zip(pt,ru)))
authored_names['toxicorb']=('Orbe Tóxico','Токсичная сфера')
type_ids=['normal','fire','water','electric','grass','ice','fighting','poison','ground','flying','psychic','bug','rock','ghost','dragon','dark','steel']
pokemon={key(r['identifier']):int(r['id']) for r in rows('pokemon')}
for index,record in enumerate(records):
 n=names.get(api_items.get(record['id']),{}).copy();n['en']=record.pop('name')
 if not record.get('mega'):
  p_name,r_name=authored_names[record['id']];n.update(pt=p_name,ru=r_name)
 else:
  m=record['mega'];base_names=base['species'][str(m['baseID'])]
  n.setdefault('pt',base_names['en']+' — Megapedra'+(' '+m['form'][5:].upper() if m['form'].startswith('mega-') else ''))
  n.setdefault('ru','Мегакамень '+base_names['ru']+(' '+m['form'][5:].upper() if m['form'].startswith('mega-') else ''))
  m['pokemonID']=pokemon[key(m['species'])]
  n={lang:n.get(lang) or base_names[lang]+' '+{'ko':'메가스톤','ja':'メガストーン','es':'megapiedra','fr':'méga-gemme','de':'Mega-Stein'}.get(lang,'Mega Stone') for lang in langs}
  record['descriptions']={lang:dict(zip(langs,['해당 포켓몬을 메가진화시킵니다. 한 배틀에 트레이너당 한 번.','Enables its Pokémon to Mega Evolve. Once per trainer per battle.','対応するポケモンをメガシンカ。1バトルで各トレーナー1回。','Permite megaevolucionar a su Pokémon. Una vez por entrenador y combate.','Permet la Méga-Évolution du Pokémon associé. Une fois par Dresseur et combat.','Permite a Mega Evolução do Pokémon correspondente. Uma vez por treinador e batalha.','Erlaubt die Mega-Entwicklung des passenden Pokémon. Einmal pro Trainer und Kampf.','Позволяет соответствующему покемону мегаэволюционировать. Один раз за бой на тренера.']))[lang] for lang in langs}
 record['names']=n
 if index<17:
  typ=base['types'][type_ids[index]]
  texts=['{t} 기술의 위력 1.2배.','{t} move power ×1.2.','{t}技の威力1.2倍。','Potencia de movimientos {t} ×1,2.','Puissance des capacités {t} ×1,2.','Poder dos golpes {t} ×1,2.','Stärke von {t}-Attacken ×1,2.','Сила приёмов типа «{t}» ×1,2.']
  record['descriptions']={lang:text.format(t=typ[lang]) for lang,text in zip(langs,texts)}
 elif not record.get('mega'):record['descriptions']=desc[record['id']]
 assert set(record['names'])>=set(langs),record['id']
 assert set(record['descriptions'])==set(langs)
result={'items':records,'source':{'rules':'pokemon-showdown 0.11.11; BW2 + isolated Gen6/Gen9 Mega forms','champions':'https://www.serebii.net/pokemonchampions/items.shtml','csvSHA256':{p.name:hashlib.sha256(p.read_bytes()).hexdigest() for p in source.glob('*.csv')}}}
text=json.dumps(result,ensure_ascii=False,separators=(',',':'))+'\n'
for p in [root/'BattleEngine/held-items.json',root/'Sources/PokeTokenBar/Resources/BattleText/held-items.json']:p.write_text(text)
print('Generated',len(records),'held items')
