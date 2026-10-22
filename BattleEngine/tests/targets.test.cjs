const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const stats={hp:143,atk:91,def:87,spa:96,spd:89,spe:107};
function mon(id,species,ability,moves=['protect']) {return {id,species,ability,moves,level:37,nature:'Hardy',ivs:Object.fromEntries(Object.keys(stats).map(k=>[k,17])),stats:{...stats}};}
function setup(mode,species,ability,moves){
 const count=6;
 const bench=[['Slowpoke','Oblivious'],['Pikachu','Static'],['Eevee','Run Away'],['Raichu','Static'],['Emolga','Static'],['Stunfisk','Static'],['Electabuzz','Static']].filter(([s])=>s!==species).slice(0,count-1);
 const own=[mon('a',species,ability,moves),...bench.map(([s,a],i)=>mon('a'+i,s,a))];
 const foe=[['Magikarp','Swift Swim'],['Rattata','Run Away'],['Spearow','Keen Eye'],['Pichu','Static'],['Emolga','Static'],['Stunfisk','Static']].slice(0,count).map(([s,a],i)=>mon('b'+i,s,a));
 const e=new OwnedBattle(mode,[own,foe],[1,2,3,4]);
 for(let p=0;p<2;p++)if(e.frame(p).preview)e.choose(p,e.frame(p).decisionID,null,Array.from({length:count},(_,i)=>i+1));
 return e;
}
test('runtime move scopes cover all fourteen BW2 target rules in singles and doubles',()=>{
 const cases=[
 ['Vaporeon','Water Absorb','surf','allAdjacent'],['Vaporeon','Water Absorb','blizzard','allAdjacentFoes'],
 ['Pikachu','Static','protect','self'],['Eevee','Run Away','helping-hand','adjacentAlly'],
 ['Vaporeon','Water Absorb','heal-bell','allyTeam'],['Pikachu','Static','reflect','allySide'],
 ['Garchomp','Sand Veil','stealth-rock','foeSide'],['Garchomp','Sand Veil','dragon-claw','normal'],
 ['Charizard','Blaze','air-slash','any'],['Whismur','Soundproof','uproar','randomNormal'],
 ['Lucario','Steadfast','me-first','adjacentFoe'],['Lucario','Steadfast','counter','scripted'],
 ['Shuckle','Sturdy','acupressure','adjacentAllyOrSelf'],['Vaporeon','Water Absorb','hail','all']];
 for(const mode of ['singles','doubles'])for(const [species,ability,move,scope]of cases){
  const e=setup(mode,species,ability,[move]);
  const m=e.frame(0).slots[0].moves[0];assert.equal(m.targetScope,scope,`${mode} ${move}`);
  if(mode==='doubles'&&scope==='normal'){
   assert.ok(m.targets.some(t=>t.location<0));assert.ok(m.targets.some(t=>t.location>0));
  }
 }
});
test('Curse uses actual requested scope for Ghost and non-Ghost users, not just dex defaults',()=>{
 for(const mode of ['singles','doubles']) {
  assert.equal(setup(mode,'Gengar','Levitate',['curse']).frame(0).slots[0].moves[0].targetScope,'normal');
  assert.equal(setup(mode,'Slowpoke','Oblivious',['curse']).frame(0).slots[0].moves[0].targetScope,'self');
 }
});
