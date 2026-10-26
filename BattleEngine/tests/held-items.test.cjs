const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {Dex}=require('pokemon-showdown'),{OwnedBattle,validateTeam}=require('../engine.cjs'),{catalog,battleDex}=require('../held-items.cjs');
function member(id,species='Smeargle',item='',moves=['splash'],stats={}){return {id,species,ability:Dex.mod('gen5').species.get(species).abilities[0],item,moves,level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100,...stats}};}
function team(p,lead,second){const mons=[lead,second||member(p+'1','Blissey'),member(p+'2','Raichu'),member(p+'3','Vaporeon'),member(p+'4','Slowbro'),member(p+'5','Scizor')];return mons.map((m,i)=>({...((i>0&&m.species===lead.species)?member(p+i,'Ditto'):m),id:p+i}));}
function make(item='',moves=['tackle'],mode='singles'){return new OwnedBattle(mode,[team('a',member('a','Smeargle',item,moves)),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);}
function turn(e,a=[{kind:'move',index:1,target:0}],b=[{kind:'move',index:1,target:0}]){for(const [p,actions]of [[0,a],[1,b]])e.choose(p,e.frame(p).decisionID,actions);}
function firstDamage(e){const line=e.frame(0).log.find(l=>l.startsWith('|-damage|p2a:'));return 100-Number(line.split('|')[3].split('/')[0]);}
const types=['tackle','flamethrower','surf','thunderbolt','energyball','icebeam','brickbreak','sludgebomb','earthquake','aerialace','psychic','bugbuzz','rockslide','shadowball','dragonpulse','darkpulse','flashcannon'];
for(const [index,item]of catalog.items.filter(i=>i.group==='type').entries())test(item.id+' increases its matching attack in the real BW2 simulation',()=>{const base=make('',[types[index]]),boosted=make(item.id,[types[index]]);turn(base);turn(boosted);assert.ok(firstDamage(boosted)>firstDamage(base));});
for(const [item,move]of [['lifeorb','tackle'],['expertbelt','shadowball'],['muscleband','tackle'],['wiseglasses','psychic'],['normalgem','tackle']])test(item+' power and consumption/recoil',()=>{const base=make('',[move]),e=make(item,[move]);turn(base);turn(e);assert.ok(firstDamage(e)>firstDamage(base));const p=e.battle.sides[0].active[0];if(item==='lifeorb')assert.equal(p.hp,450);if(item==='normalgem'){assert.equal(p.item,'');assert.ok((500-e.battle.sides[1].pokemon[0].hp)/(500-base.battle.sides[1].pokemon[0].hp)>1.4);assert.match(battleDex().items.get(item).desc,/1\.5x/);}});
test('Metronome accumulates and resets when the chosen move changes',()=>{const e=make('metronome',['tackle','scratch']);turn(e);const p=e.battle.sides[0].active[0];assert.equal(p.volatiles.metronome.numConsecutive,0);turn(e);assert.equal(p.volatiles.metronome.numConsecutive,1);turn(e,[{kind:'move',index:2,target:0}]);assert.equal(p.volatiles.metronome.numConsecutive,0);});
test('Leftovers, Shell Bell and Big Root use actual recovery events',()=>{
 const e=make('leftovers');e.battle.sides[0].active[0].hp=300;turn(e);assert.equal(e.frame(0).own[0].hp,331);
 for(const [item,move]of [['shellbell','tackle'],['bigroot','gigadrain']]){const b=make('',[move]),s=make(item,[move]);b.battle.sides[0].active[0].hp=s.battle.sides[0].active[0].hp=200;turn(b);turn(s);assert.ok(s.frame(0).own[0].hp>b.frame(0).own[0].hp,item);}
});
test('Focus Sash protects full HP once; Focus Band triggers on an attainable RNG branch',()=>{
 let protectedBand=false;
 for(const item of ['focussash','focusband'])for(let seed=1;seed<=60;seed++){
  const e=new OwnedBattle('singles',[team('a',member('a','Smeargle',item,['splash'],{hp:10,def:1})),team('b',member('b','Mew','',['tackle'],{atk:1000,spe:200}))],[seed,2,3,4]);turn(e);const p=e.battle.sides[0].pokemon.find(p=>p.set.ptbID==='a0');
  if(item==='focussash'){assert.equal(p.hp,1);assert.equal(p.item,'');break;}
  if(p.hp===1){protectedBand=true;assert.equal(p.item,'focusband');break;}
 }
 assert.ok(protectedBand);
});
test('Rocky Helmet contact recoil and Air Balloon ground immunity/pop',()=>{
 const e=new OwnedBattle('singles',[team('a',member('a','Smeargle','rockyhelmet',['splash'])),team('b',member('b','Mew','',['tackle']))],[1,2,3,4]);turn(e);assert.equal(e.frame(0).foe[0].hp,84);
 const a=make('airballoon',['splash']);a.battle.sides[1].active[0].moveSlots[0].id='earthquake';a.battle.makeRequest('move');turn(a);assert.equal(a.frame(0).own[0].hp,500);
 a.battle.sides[1].active[0].moveSlots[0].id='tackle';a.battle.makeRequest('move');turn(a);assert.equal(a.frame(0).own[0].item,'');
});
test('Choice Scarf locks moves; Iron Ball halves speed and grounds',()=>{
 const e=make('choicescarf',['tackle','scratch']);assert.equal(e.battle.sides[0].active[0].getStat('spe'),150);turn(e);assert.equal(e.frame(0).slots[0].moves[1].disabled,true);
 const i=make('ironball');assert.equal(i.battle.sides[0].active[0].getStat('spe'),50);assert.equal(i.battle.sides[0].active[0].isGrounded(),true);
});
test('Quick Claw produces a real activation without outranking increased priority',()=>{
 let seen=false;
 for(let seed=1;seed<=60&&!seen;seed++){const e=make('quickclaw');e.battle.resetRNG([seed,2,3,4]);turn(e);seen=e.frame(0).log.some(l=>l.includes('Quick Claw'));}assert.ok(seen);
 let priority=false;for(let seed=1;seed<=60&&!priority;seed++){const e=new OwnedBattle('singles',[team('a',member('a','Smeargle','quickclaw',['tackle'],{spe:10})),team('b',member('b','Mew','',['quickattack'],{spe:200}))],[seed,2,3,4]);turn(e);if(e.frame(0).log.some(l=>l.includes('Quick Claw'))){priority=true;assert.match(e.frame(0).log.find(l=>l.startsWith('|move|')),/p2a: Mew/);}}assert.ok(priority);
});
test('Sitrus and Lum consume in battle and return in a fresh battle',()=>{
 const s=make('sitrusberry',['splash']);s.battle.sides[0].active[0].hp=200;turn(s);assert.equal(s.frame(0).own[0].hp,325);assert.equal(s.frame(0).own[0].item,'');assert.equal(make('sitrusberry').frame(0).own[0].item,'sitrusberry');
 const l=make('lumberry');l.battle.sides[0].active[0].setStatus('par');turn(l);assert.equal(l.frame(0).own[0].status,'');assert.equal(l.frame(0).own[0].item,'');
});
for(const mode of ['singles','doubles'])test('all 64 Mega Stones preserve custom HP/stats and activate once in '+mode,()=>{
 for(const item of catalog.items.filter(i=>i.mega)){
  const m=item.mega,own=team('a',member('a',m.base,item.id,['splash']));
  if(own.slice(1).some(p=>p.species===m.base)){const i=own.findIndex((p,i)=>i>0&&p.species===m.base);own[i]=member('a'+i,'Ditto');}
  const e=new OwnedBattle(mode,[own,team('b',member('b','Mew','',['splash']))],[1,2,3,4]);const p=e.battle.sides[0].active[0];p.hp=350;
  const before={...p.storedStats};assert.equal(e.frame(0).slots[0].canMegaEvo,true,item.id);
  const actions=Array.from({length:mode==='doubles'?2:1},(_,i)=>({kind:'move',index:1,target:0,mega:i===0}));turn(e,actions,actions.map(a=>({...a,mega:false})));
  const after=e.frame(0).own[0];assert.equal(after.mega,true,item.id);assert.equal(after.maxHP,500,item.id);assert.equal(after.form,m.form,item.id);
  // Weather may chip after Mega Evolution; every captured evolution scene must retain HP.
  const megaScene=e.frame(0).scenes.find(s=>s.own[0].form===m.form);assert.equal(megaScene.own[0].hp,350,item.id);
  const d=e.battle.dex,baseline=d.species.get(m.base),evolved=d.species.get(m.species);
  const b=e.battle.spreadModify(baseline.baseStats,{...p.set,ptbStats:undefined}),n=e.battle.spreadModify(evolved.baseStats,{...p.set,ptbStats:undefined,ptbMegaStats:undefined});
  for(const stat of ['atk','def','spa','spd','spe'])assert.equal(after.stats[stat],before[stat]+n[stat]-b[stat],item.id+' '+stat);
  assert.ok(e.battle.sides[0].pokemon.every(p=>!p.canMegaEvo));assert.equal(after.item,item.id);
  if(!['Trace','Intimidate'].includes(m.ability))assert.equal(after.ability,m.ability,item.id);
 }
});
test('whitelist, base form, stone-species binding, unsupported generations and private preview',()=>{
 assert.equal(catalog.items.length,100);assert.equal(catalog.items.filter(i=>i.mega).length,64);
 for(const item of ['fairyfeather','assaultvest','mewtwonitex','not-an-item'])assert.throws(()=>make(item),/held item/);
 const wrong=team('a',member('a','Smeargle','charizarditex'));assert.throws(()=>validateTeam(wrong,6),/does not match/);
 const mega=team('a',member('a','Charizard-Mega-X'));assert.throws(()=>validateTeam(mega,6),/base Pokémon/);
 const e=make('lifeorb');assert.equal(e.frame(1).foe[0].item,undefined);
 assert.equal(Dex.mod('gen5').currentMod,'gen5');assert.equal(Dex.mod('gen5').abilities.get('pixilate').gen,6);
});
test('shared catalog translations and bundled Mega art are complete and hash-verified',()=>{
 const root=path.resolve(__dirname,'../../Sources/PokeTokenBar/Resources');
 assert.deepEqual(JSON.parse(fs.readFileSync(path.join(root,'BattleText/held-items.json'))),catalog);
 for(const item of catalog.items)for(const lang of ['ko','en','ja','es','fr','pt','de','ru']){assert.ok(item.names[lang],item.id+lang);assert.ok(item.descriptions[lang],item.id+lang);}
 const dir=path.join(root,'PokeRoguePlayer/mega-sprites'),manifest=JSON.parse(fs.readFileSync(path.join(dir,'manifest.json')));
 assert.equal(Object.keys(manifest).length,256);
 for(const [key,r]of Object.entries(manifest)){
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,r.file))).digest('hex'),r.sha256);
  assert.equal(r.assetRevision,JSON.parse(fs.readFileSync(path.join(root,'PokeRoguePlayer/manifest.json'))).assetRevision);
  assert.equal(r.fps,10);assert.equal(r.animated,r.frames>1);assert.equal(r.fallback,undefined,key);
  assert.match(r.url,/githubusercontent.com\/pagefaultgames\/pokerogue-assets\//);
  assert.ok(r.image.includes(key.startsWith('back-')?'/back/':'/pokemon/'));
  assert.equal(r.image.includes('/shiny/'),key.endsWith('-sh'));
  for(const [source,metadata]of Object.entries(r.sources)){
   assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(dir,'source',source))).digest('hex'),metadata.sha256);
   assert.ok(metadata.url.endsWith(source));
  }
  const atlas=JSON.parse(fs.readFileSync(path.join(dir,r.atlas))),frames=(atlas.textures||[atlas])[0].frames;
  assert.equal(frames.length,r.frames);
 }
 assert.equal(Object.values(manifest).filter(r=>r.animated).length,8);
});

test('Mega ability effects use the extension dex while normal BW2 behavior stays intact',()=>{
 for(const [species,item,move,expected]of [['Gardevoir','gardevoirite','tackle','Fairy'],['Pinsir','pinsirite','tackle','Flying'],['Glalie','glalitite','tackle','Ice'],['Feraligatr','feraligite','tackle','Dragon']]){
  const e=new OwnedBattle('singles',[team('a',member('a',species,item,[move])),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);turn(e,[{kind:'move',index:1,target:0,mega:true}]);assert.equal(e.frame(0).slots[0].moves[0].type,expected,item);
 }
 const bond=new OwnedBattle('singles',[team('a',member('a','Kangaskhan','kangaskhanite',['tackle'])),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);turn(bond,[{kind:'move',index:1,target:0,mega:true}]);assert.equal(bond.frame(0).log.filter(l=>l.startsWith('|-damage|p2a:')).length,2);
 const e=new OwnedBattle('singles',[team('a',member('a','Raichu','raichunitex',['thunderbolt'])),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);turn(e,[{kind:'move',index:1,target:0,mega:true}]);assert.equal(e.battle.field.terrain,'electricterrain');assert.ok(e.frame(0).field.conditions.includes('electricterrain'));assert.equal(e.frame(0).field.conditionTimings.electricterrain.maximum,5);
});
test('Mega stat delta keeps imported training and applies nature once',()=>{
 const own=team('a',{...member('a','Charizard','charizarditex',['splash'],{hp:143,atk:91,def:87,spa:96,spd:89,spe:107}),nature:'Adamant'});
 const e=new OwnedBattle('singles',[own,team('b',member('b','Mew','',['splash']))],[1,2,3,4]);
 e.battle.sides[0].active[0].hp=73;
 turn(e,[{kind:'move',index:1,target:0,mega:true}]);
 const p=e.frame(0).own[0];assert.equal(p.hp,73);assert.equal(p.maxHP,143);
 assert.deepEqual(p.stats,{hp:143,atk:142,def:120,spa:115,spd:89,spe:107});
});

test('item clause covers all six before singles/doubles lineup slicing and canonicalizes names',()=>{
 for(const mode of ['singles','doubles']){
  const own=team('a',member('a','Smeargle','Leftovers'));
  own[5].item='leftovers';
  assert.throws(()=>new OwnedBattle(mode,[own,team('b',member('b','Mew'))],[1,2,3,4]),/Duplicate held item/);
  own[5].item='lifeorb';
  assert.doesNotThrow(()=>new OwnedBattle(mode,[own,team('b',member('b','Mew','leftovers'))],[1,2,3,4]));
  own.forEach(p=>p.item='');assert.doesNotThrow(()=>validateTeam(own,6));
 }
});

for(const mode of ['singles','doubles'])test('Toxic Orb applies toxic at turn end, stays held and respects immunities in '+mode,()=>{
 const actions=Array.from({length:mode==='doubles'?2:1},()=>({kind:'move',index:1,target:0}));
 const e=make('toxicorb',['splash'],mode);
 turn(e,actions,actions);assert.equal(e.frame(0).own[0].status,'tox');assert.equal(e.frame(0).own[0].hp,500);
 assert.equal(e.frame(0).own[0].item,'toxicorb');
 assert.ok(e.frame(0).log.some(l=>l.startsWith('|-status|p1a:')&&l.includes('tox|[from] item: Toxic Orb')));
 turn(e,actions,actions);assert.equal(e.frame(0).own[0].hp,469);
 turn(e,actions,actions);assert.equal(e.frame(0).own[0].hp,407);
 for(const [species,ability]of [['Scizor','Swarm'],['Gengar','Levitate'],['Snorlax','Immunity']]){
  const immune=new OwnedBattle(mode,[team('a',{...member('a',species,'toxicorb',['splash']),ability}),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);
  turn(immune,actions,actions);assert.equal(immune.frame(0).own[0].status,'',species);
 }
 const existing=make('toxicorb',['splash'],mode);existing.battle.sides[0].active[0].setStatus('brn');
 turn(existing,actions,actions);assert.equal(existing.frame(0).own[0].status,'brn');
});
test('Toxic Orb interacts with Poison Heal and Guts through actual ability mechanics',()=>{
 const heal=new OwnedBattle('singles',[team('a',{...member('a','Gliscor','toxicorb',['splash']),ability:'Poison Heal'}),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);
 heal.battle.sides[0].active[0].hp=300;turn(heal);assert.equal(heal.frame(0).own[0].status,'tox');
 turn(heal);assert.equal(heal.frame(0).own[0].hp,362);assert.equal(heal.frame(0).own[0].item,'toxicorb');
 const makeGuts=item=>new OwnedBattle('singles',[team('a',member('a','Ursaring',item,['splash','tackle'])),team('b',member('b','Mew','',['splash']))],[1,2,3,4]);
 const normal=makeGuts(''),poisoned=makeGuts('toxicorb');turn(normal);turn(poisoned);
 turn(normal,[{kind:'move',index:2,target:0}]);turn(poisoned,[{kind:'move',index:2,target:0}]);
 assert.ok(firstDamage(poisoned)>firstDamage(normal));
});
