const {test}=require('node:test'),assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown');
const {OwnedBattle,validateTeam}=require('../engine.cjs');
const {allowedFairyMoves,battleDex}=require('../held-items.cjs');
function member(id,species,moves=['splash']) {
 return {id,species,moves,ability:Dex.mod('gen5').species.get(species).abilities[0],level:50,nature:'Hardy',
  ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100}};
}
function team(prefix,lead='Smeargle',moves=['splash']) {
 const species=[lead,'Blissey','Raichu','Vaporeon','Slowbro','Scizor'];
 if(lead==='Scizor')species[5]='Ditto';
 return species.map((s,i)=>member(prefix+i,s,i===0?moves:['splash']));
}
function turn(e) {
 for(const p of [0,1]) {
  const f=e.frame(p);
  e.choose(p,f.decisionID,f.slots.map(s=>{
   if(s.canPass)return {kind:'pass'};
   const m=s.moves[0];return {kind:'move',index:m.index,target:m.targetRequired ? (m.targets[0]?.location ?? 0):0};
  }));
 }
}
test('only the fourteen generation-VI Fairy moves extend the existing move boundary',()=>{
 assert.equal(allowedFairyMoves.size,14);
 const dex=Dex.mod('gen6');
 for(const id of allowedFairyMoves) {
  assert.equal(dex.moves.get(id).gen,6);assert.equal(dex.moves.get(id).type,'Fairy');
  assert.doesNotThrow(()=>validateTeam(team('a','Smeargle',[id]),6),id);
 }
 for(const id of ['mysticalfire','flowertrick','fleurcannon','floralhealing','naturesmadness','spiritbreak','mistyexplosion','springtidestorm','alluringvoice','not-a-move']) {
  assert.throws(()=>validateTeam(team('a','Smeargle',[id]),6),/Unsupported move/,id);
 }
});
test('all fourteen allowed Fairy moves reach actual single and double battle actions',()=>{
 for(const mode of ['singles','doubles'])for(const id of allowedFairyMoves) {
  const e=new OwnedBattle(mode,[team('a','Smeargle',[id]),team('b','Mew')],[1,2,3,4]);
  turn(e);
  const name=battleDex().moves.get(id).name;
  assert.ok(e.frame(0).log.some(l=>l.startsWith('|move|')&&l.includes('|'+name+'|')),mode+' '+id);
  assert.ok(!e.frame(0).log.some(l=>l.startsWith('|error|')),mode+' '+id);
 }
});
test('Fairy matchups are added without replacing BW2 Steel resistances or base species types',()=>{
 const d=battleDex(),old=Dex.mod('gen5'),six=Dex.mod('gen6');
 for(const type of old.types.all()) {
  for(const [attack,value]of Object.entries(type.damageTaken)) {
   if(attack==='Fairy')continue;
   assert.equal(d.types.get(type.name).damageTaken[attack],value,type.name+' vs '+attack);
  }
  if(type.name!=='Stellar')assert.equal(d.types.get(type.name).damageTaken.Fairy,six.types.get(type.name).damageTaken.Fairy??0,type.name);
 }
 assert.equal(d.types.get('Steel').damageTaken.Dark,2);
 assert.equal(d.types.get('Steel').damageTaken.Ghost,2);
 assert.deepEqual(d.species.get('Gardevoir').types,['Psychic']);
 function damage(species) {
  const e=new OwnedBattle('singles',[team('a','Smeargle',['moonblast']),team('b',species)],[1,2,3,4]);
  turn(e);return 500-e.battle.sides[1].pokemon[0].hp;
 }
 const neutral=damage('Mew');assert.ok(damage('Haxorus')>neutral*1.8);assert.ok(damage('Scizor')<neutral*.6);
});
test('Fairy drain, charging and terrain effects execute under the extended BW2 rules',()=>{
 const drain=new OwnedBattle('singles',[team('a','Smeargle',['drainingkiss']),team('b','Mew')],[1,2,3,4]);
 drain.battle.sides[0].active[0].hp=200;turn(drain);assert.ok(drain.battle.sides[0].active[0].hp>200);
 const charge=new OwnedBattle('singles',[team('a','Smeargle',['geomancy']),team('b','Mew')],[1,2,3,4]);
 turn(charge);assert.equal(charge.battle.sides[0].active[0].boosts.spa,0);
 turn(charge);for(const stat of ['spa','spd','spe'])assert.equal(charge.battle.sides[0].active[0].boosts[stat],2);
 const terrain=new OwnedBattle('singles',[team('a','Smeargle',['mistyterrain']),team('b','Mew')],[1,2,3,4]);
 turn(terrain);assert.equal(terrain.battle.field.terrain,'mistyterrain');
});
test('Fairy translations and inspector metadata agree with the permitted generation-VI moves',()=>{
 const supplement=require('../../Sources/PokeTokenBar/Resources/BattleText/gen6-fairy.json');
 assert.deepEqual(Object.keys(supplement.moves).sort(),[...allowedFairyMoves].sort());
 for(const [id,row]of Object.entries(supplement.moves)){
  const move=battleDex().moves.get(id);
  for(const [key,value]of Object.entries({power:move.basePower,pp:move.pp,accuracy:move.accuracy,type:move.type,category:move.category}))assert.deepEqual(row[key],value,id+' '+key);
  for(const language of ['ko','en','ja','es','fr','pt','de','ru']){
   assert.ok(row.names[language]);assert.ok(row.descriptions[language]);
  }
 }
 assert.equal(battleDex().moves.get('moonblast').secondaries[0].chance,30);
 assert.ok(supplement.moves.moonblast.descriptions.en.includes('30%'));
});
