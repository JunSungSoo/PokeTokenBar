const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const keys=['hp','atk','def','spa','spd','spe'];
function mon(id, species='Pikachu', ability='Static', moves=['thunderbolt','protect']) {
 return {id,species,level:37,ability,moves,nature:'Hardy',gender:'M',ivs:Object.fromEntries(keys.map(k=>[k,17])),stats:{hp:143,atk:91,def:87,spa:96,spd:89,spe:107}};
}
const species = ['Pikachu','Raichu','Pichu','Electabuzz','Mareep','Flaaffy'];
function member(id, i) { return mon(id,species[i]); }
function setup(mode='singles', foeMoves=null, seed=undefined, ownMoves=null) {
 const count=6;
 const foe=Array.from({length:count},(_,i)=>member('b'+i,i));
 if(foeMoves) foe[0].moves=foeMoves;
 const own=Array.from({length:count},(_,i)=>member('a'+i,i));
 if(ownMoves)own[0].moves=ownMoves;
 return new OwnedBattle(mode,[own,foe],seed);
}
function lead(e) {if(!e.frame(0).preview)return;for (let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,null,e.frame(p).own.map((_,i)=>i+1));}
test('imports current six stats and level without EVs or PP Ups in both modes',()=>{
 for(const mode of ['singles','doubles']) {
 const e=setup(mode);
 assert.equal(e.battle.gen,5);
 for(const p of [0,1]) for(const poke of e.frame(p).own) {assert.deepEqual(poke.stats,mon('x').stats);assert.equal(poke.level,37);}
 lead(e);
 assert.equal(e.frame(0).own.filter(p=>p.active).length,mode==='singles'?1:2);
 assert.equal(e.frame(0).slots[0].moves[0].maxPP,15);
 }
});
test('opponent view never includes private stats or exact HP',()=>{
 const e=setup();lead(e);assert.equal(e.frame(0).foe[0].maxHP,100);assert.equal(e.frame(0).foe[0].stats,undefined);
});
test('singles resolves both commands, immunity and switching using BW2 rules',()=>{
 // Thunderbolt from the defender could paralyze and stop the attack before immunity resolves.
 // Growl still resolves the opposing command without adding an unrelated random paralysis gate.
 const e=setup('singles',['growl','protect']);lead(e);
 e.battle.sides[1].pokemon[0].setType(['Ground']);
 e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 e.choose(1,e.frame(1).decisionID,[{kind:'move',index:1,target:0}]);
 assert.match(e.frame(0).log.join('\n'),/immune/);
 e.choose(0,e.frame(0).decisionID,[{kind:'switch',index:2}]);
 e.choose(1,e.frame(1).decisionID,[{kind:'move',index:2,target:0}]);
 assert.equal(e.battle.sides[0].active[0].set.ptbID,'a1');
 assert.deepEqual(e.frame(0).own[0].stats,mon('x').stats);
});
test('doubles requires both commands and explicit legal targets',()=>{
 const e=setup('doubles');lead(e);
 assert.equal(e.frame(0).slots.length,2);
 assert.ok(e.frame(0).slots[0].moves[0].targets.length>=2);
 assert.throws(()=>e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:1}]),/every active/);
 for(let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:1},{kind:'move',index:1,target:2}]);
 assert.equal(e.battle.turn,2);
});
test('surrender ends both perspectives once and opponent wins',()=>{
 const e=setup();lead(e);e.surrender(0);e.surrender(0);
 for(let p=0;p<2;p++){assert.equal(e.frame(p).ended,true);assert.equal(e.frame(p).winner,1);}
});
test('rejects unsupported abilities, invalid stats, roster sizes and stale commands',()=>{
 assert.throws(()=>new OwnedBattle('singles',[[mon('x')],[mon('y')]]),/exactly/);
 const e=setup();lead(e);assert.throws(()=>e.choose(0,'old',[]),/Stale/);
 const team=Array.from({length:6},(_,i)=>member('invalid'+i,i));team[0].ability='Cursed Body';
 assert.throws(()=>new OwnedBattle('singles',[team,team]),/incompatible/);
});
test('real form ability mapping preserves existing numeric stats',()=>{
 const team=Array.from({length:6},(_,i)=>member('s'+i,i));
 team[0]={...mon('s0','Shaymin-Sky','Natural Cure',['air-slash']),form:'sky',abilitySlot:1};
 const e=new OwnedBattle('singles',[team,team.map(p=>({...p,id:'b'+p.id}))]);
 assert.equal(e.battle.sides[0].pokemon[0].ability,'serenegrace');
 assert.deepEqual(e.frame(0).own[0].stats,team[0].stats);
});
test('doubles supports a forced replacement with only one bench Pokémon remaining',()=>{
 const e=setup('doubles');lead(e);
 const side=e.battle.sides[0];
 for(const index of [0,1,3]) {side.pokemon[index].hp=0;side.pokemon[index].fainted=true;}
 side.pokemonLeft=1;
 e.battle.checkFainted();
 e.battle.makeRequest('switch');
 const slots=e.frame(0).slots;
 assert.equal(slots.filter(s=>s.mustSwitch).length,1);
 assert.equal(slots.filter(s=>s.canPass).length,1);
 e.choose(0,e.frame(0).decisionID,[{kind:'switch',index:3},{kind:'pass'}]);
 assert.equal(side.active[0].set.ptbID,'a2');
});
test('a complete singles match reaches a winner through moves and forced replacements',()=>{
 const team=Array.from({length:6},(_,i)=>({...member('a'+i,i),stats:{hp:20,atk:91,def:87,spa:196,spd:89,spe:107}}));
 const e=new OwnedBattle('singles',[team,team.map(p=>({...p,id:'b'+p.id}))],[1,2,3,4]);lead(e);
 for(let n=0;n<60&&!e.battle.ended;n++) for(let p=0;p<2&&!e.battle.ended;p++){
   const f=e.frame(p);if(f.waiting)continue;
   if(f.slots[0].mustSwitch){const index=f.own.findIndex(m=>!m.active&&!m.fainted)+1;e.choose(p,f.decisionID,[{kind:'switch',index}]);}
   else e.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]);
 }
 assert.equal(e.battle.ended,true);
 assert.ok([0,1].includes(e.frame(0).winner));
});
test('a complete doubles match supports knockouts and forced replacements until victory',()=>{
 const team=Array.from({length:6},(_,i)=>({...member('a'+i,i),stats:{hp:20,atk:91,def:87,spa:196,spd:89,spe:107}}));
 const e=new OwnedBattle('doubles',[team,team.map(p=>({...p,id:'b'+p.id}))],[7,8,9,10]);lead(e);
 for(let n=0;n<40&&!e.battle.ended;n++)for(let p=0;p<2&&!e.battle.ended;p++){
   const f=e.frame(p);if(f.waiting)continue;
   const used=new Set();
   const actions=f.slots.map(s=>{
     if(s.canPass)return {kind:'pass'};
     if(s.mustSwitch){const index=f.own.findIndex((m,i)=>!m.active&&!m.fainted&&!used.has(i))+1;used.add(index-1);return{kind:'switch',index};}
     const move=s.moves.find(m=>!m.disabled&&m.pp>0);
     return {kind:'move',index:move.index,target:move.targetRequired?move.targets[0].location:0};
   });
   e.choose(p,f.decisionID,actions);
 }
 assert.equal(e.battle.ended,true);
 assert.ok([0,1].includes(e.frame(0).winner));
});
test('all item-dependent Arceus forms are rejected in singles and doubles',()=>{
 const {Dex}=require('pokemon-showdown');
 const forms=Dex.mod('gen5').species.all().filter(s=>s.num===493 && s.gen<=5);
 assert.ok(forms.length>1);
 for(const mode of ['singles','doubles']) for(const species of forms) {
   const count=6;
   const team=Array.from({length:count},(_,i)=>member('a'+i,i));
   team[1]=mon('blocked',species.name,'Multitype',['judgment']);
   assert.throws(()=>new OwnedBattle(mode,[team,Array.from({length:count},(_,i)=>member('b'+i,i))]),/type depends on a held item/);
 }
});
test('battle sprite follows Forecast weather changes rather than the saved cosmetic form',()=>{
 const template={...mon('x','Castform','Forecast',['sunny-day','rain-dance','protect']),form:'normal'};
 const team=Array.from({length:6},(_,i)=>member('a'+i,i));
 team[0]={...template,id:'a0'};
 const foe=Array.from({length:6},(_,i)=>member('b'+i,i));
 const e=new OwnedBattle('singles',[team,foe]);lead(e);
 for(const [index,form] of [[1,'sunny'],[2,'rainy']]){
   e.choose(0,e.frame(0).decisionID,[{kind:'move',index,target:0}]);
   e.choose(1,e.frame(1).decisionID,[{kind:'move',index:2,target:0}]);
   assert.equal(e.frame(0).own[0].form,form);
   assert.equal(e.frame(1).foe[0].form,form);
 }
});
test('move inspector uses BW2 power and current type chart without consuming battle state',()=>{
 for (const mode of ['singles','doubles']) {
  const e=setup(mode);lead(e);
  const target=e.battle.sides[1].active[0];
  if(mode==='doubles') {
   const names=e.frame(0).slots[0].moves[0].targets.map(t=>t.name);
   assert.equal(new Set(names).size,names.length,'duplicate species still need distinct target labels');
  }
  const before=e.battle.log.length;
  for(const [types,multiplier] of [[['Water','Flying'],4],[['Water'],2],[['Ground'],0],[['Grass'],0.5],[['Grass','Dragon'],0.25],[['Normal'],1]]) {
   target.setType(types);
   const move=e.frame(0).slots[0].moves[0];
   assert.equal(move.power,95); // Generation VI changed Thunderbolt to 90.
   assert.equal(move.category,'Special');assert.ok(move.description.length>0);
   assert.equal(move.matchups[0].multiplier,multiplier);
   assert.equal(e.frame(0).slots[0].moves[1].matchups[0].multiplier,null);
   assert.equal(target.hp,143);assert.equal(e.battle.log.length,before);
  }
 }
});

test('species clause rejects distinct individuals and forms per team in both modes',()=>{
 for(const mode of ['singles','doubles']) {
  const count=6;
  for(const [base,form,ability] of [['Pikachu','Pikachu','Static'],['Rotom','Rotom-Wash','Levitate'],['Deoxys','Deoxys-Attack','Pressure'],['Shaymin','Shaymin-Sky','Natural Cure']]) {
   const team=Array.from({length:count},(_,i)=>member('a'+i,i));
   team[0]=mon('distinct-a',base,ability);team[1]=mon('distinct-b',form,ability);
   // Peer-supplied IDs cannot bypass canonical species validation.
   team[0].speciesID=25;team[1].speciesID=26;
   assert.throws(()=>new OwnedBattle(mode,[team,Array.from({length:count},(_,i)=>member('b'+i,i))]),/Duplicate species/);
  }
  assert.doesNotThrow(()=>setup(mode),'opposing teams may share species');
 }
});

test('visual events preserve every resolved move, recipient-relative targets and immunity',()=>{
 const e=setup('singles',['growl','protect']);lead(e);
 e.battle.sides[1].active[0].setType(['Ground']);
 e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 e.choose(1,e.frame(1).decisionID,[{kind:'move',index:1,target:0}]);
 const a=e.frame(0),b=e.frame(1);
 assert.equal(a.effects.length,2);
 assert.equal(new Set(a.effects.map(v=>v.id)).size,2);
 const bolt=a.effects.find(v=>v.move==='Thunderbolt');
 assert.equal(bolt.moveID,'thunderbolt');
 assert.equal(bolt.type,'Electric');assert.equal(bolt.category,'Special');
 assert.deepEqual(bolt.source,{own:true,slot:0});
 assert.deepEqual(bolt.targets,[{position:{own:false,slot:0},hit:false}]);
 const enemyView=b.effects.find(v=>v.move==='Thunderbolt');
 assert.deepEqual(enemyView.source,{own:false,slot:0});
 assert.deepEqual(enemyView.targets,[{position:{own:true,slot:0},hit:false}]);
 assert.equal(a.effects.find(v=>v.move==='Growl').category,'Status');
 assert.deepEqual(e.frame(0).effects,a.effects,'an unchanged frame must preserve event IDs');
});
test('visual events distinguish charge turns and suppress failed status effects',()=>{
 const e=setup('singles',['growl'],[1,2,3,4],['solarbeam']);lead(e);
 for(let turn=0;turn<2;turn++)for(let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 assert.deepEqual(e.frame(0).effects.filter(v=>v.moveID==='solarbeam').map(v=>v.phase),['charge','move']);
 // Gen V logs a capped stat increase as |-boost|...|0, not |-fail|. Full-HP Rest reaches -fail.
 const fail=setup('singles',['splash'],[1,2,3,4],['rest']);lead(fail);
 for(let p=0;p<2;p++)fail.choose(p,fail.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 assert.equal(fail.frame(0).effects.find(v=>v.moveID==='rest').targets[0].hit,false);
});
test('spread visual effects include the actual doubles ally and both foes',()=>{
 const teams=[0,1].map(p=>Array.from({length:6},(_,i)=>({...member(`${p}-${i}`,i),moves:['growl','protect']})));
 teams[0][0].moves=['surf','protect'];
 const e=new OwnedBattle('doubles',teams);lead(e);
 for(let p=0;p<2;p++) e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0},{kind:'move',index:1,target:0}]);
 const effects=e.frame(0).effects;
 assert.equal(effects.length,4);
 const surf=effects.find(v=>v.move==='Surf');
 assert.equal(surf.type,'Water');
 assert.deepEqual(surf.targets.map(t=>t.position).sort((a,b)=>Number(b.own)-Number(a.own)||a.slot-b.slot),
  [{own:true,slot:1},{own:false,slot:0},{own:false,slot:1}]);
 assert.ok(surf.targets.every(t=>t.hit));
});
test('visual metadata does not disclose private IV-derived Hidden Power types',()=>{
 const teams=[0,1].map(p=>Array.from({length:6},(_,i)=>({...member(`${p}-${i}`,i),moves:p===0&&i===0?['hiddenpower','protect']:['growl','protect']})));
 const e=new OwnedBattle('singles',teams);lead(e);
 assert.equal(e.frame(0).slots[0].moves[0].type,'Dark','the owner still sees the true move type');
 for(let p=0;p<2;p++) e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 for(let p=0;p<2;p++) assert.equal(e.frame(p).effects.find(v=>v.move==='Hidden Power').type,'Normal');
});
test('blocked and missed moves never produce a successful hit burst',()=>{
 for(const scenario of ['protect','miss']) {
  const e=setup('singles',['growl','protect'],[1,2,3,0]);lead(e);
  if(scenario==='miss') e.battle.sides[0].active[0].boosts.accuracy=-6;
  e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
  e.choose(1,e.frame(1).decisionID,[{kind:'move',index:scenario==='protect'?2:1,target:0}]);
  assert.ok(e.frame(0).log.some(line=>scenario==='protect'?line.includes('move: Protect'):line.startsWith('|-miss|')));
  assert.equal(e.frame(0).effects.find(v=>v.move==='Thunderbolt').targets[0].hit,false,scenario);
 }
});
test('registered six enter as ordered three/four without revealing opposing benches',()=>{
 for(const mode of ['singles','doubles']) {
  const own=Array.from({length:6},(_,i)=>member('own'+i,i)).reverse();
  const foe=Array.from({length:6},(_,i)=>member('foe'+i,i));
  const e=new OwnedBattle(mode,[own,foe],[1,2,3,4]);
  const active=mode==='singles'?1:2;
  for(const p of [0,1]) {
   const f=e.frame(p), submitted=p===0?own:foe;
   assert.equal(f.preview,false);assert.equal(f.own.length,mode==='singles'?3:4);
   assert.deepEqual(f.own.map(m=>m.id), submitted.slice(0,mode==='singles'?3:4).map(m=>m.id));
   assert.deepEqual(f.own.filter(m=>m.active).map(m=>m.id),submitted.slice(0,active).map(m=>m.id));
   assert.equal(f.foe.length,active);
   assert.ok(f.foe.every(m=>m.active));
   assert.ok(!f.log.some(l=>l.startsWith('|poke|')),'No team preview roster in public log');
  }
  for(const size of [3,4,5])assert.throws(()=>new OwnedBattle(mode,[own.slice(0,size),foe]),/exactly 6/);
 }
});

test('move details expose base accuracy and distinguish always-hit moves in singles and doubles',()=>{
 for(const mode of ['singles','doubles']) {
  const e=setup(mode,null,undefined,['thunderbolt','thunder','swift','fissure']);lead(e);
  const slots=e.frame(0).slots;
  assert.deepEqual(slots[0].moves.map(m=>m.accuracy),[100,70,true,30]);
  const attacker=e.battle.sides[0].active[0];attacker.boosts.accuracy=-2;
  e.battle.field.setWeather('raindance',attacker);
  assert.deepEqual(e.frame(0).slots[0].moves.map(m=>m.accuracy),[100,70,true,30],'Inspector shows base accuracy; actual weather and stage mechanics remain in the engine');
 }
});

test('unselected reserves cannot switch in or keep a defeated lineup alive',()=>{
 for(const mode of ['singles','doubles']) {
  const e=setup(mode);lead(e);
  const n=mode==='singles'?3:4, side=e.battle.sides[0];
  assert.equal(side.pokemonLeft,n);
  const before=side.active.map(p=>p.set.ptbID);
  assert.throws(()=>e.choose(0,e.frame(0).decisionID,e.frame(0).slots.map((s,i)=>i===0?{kind:'switch',index:n+1}:{kind:'move',index:2,target:0})),/Invalid action/);
  assert.deepEqual(side.active.map(p=>p.set.ptbID),before);
  for(const p of side.pokemon)p.faint();
  e.battle.faintMessages();
  assert.equal(e.battle.ended,true);
  assert.equal(e.frame(0).winner,1,'Healthy unselected registered Pokémon cannot prevent defeat');
 }
});
