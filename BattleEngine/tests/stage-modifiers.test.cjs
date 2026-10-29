const {test}=require('node:test'),assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const stats={hp:1000,atk:91,def:300,spa:96,spd:300,spe:107};
function mon(species,ability,moves=['splash'],item){return {species,ability,moves,item,level:50,nature:'Hardy',ivs:{hp:17,atk:17,def:17,spa:17,spd:17,spe:17},stats:{...stats}};}
function team(prefix,lead){
 const all=[lead];for(const [s,a]of [['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Scizor','Technician'],['Slowbro','Own Tempo']])all.push(mon(s,a));
 return all.map((p,i)=>({...p,id:prefix+i}));
}
function setup(mode,lead,foe=mon('Smeargle','Own Tempo')){return new OwnedBattle(mode,[team('a',lead),team('b',foe)],[1,2,3,4]);}
function turn(e,mega=false){for(const p of [0,1]){const f=e.frame(p);e.choose(p,f.decisionID,f.slots.map((s,i)=>({kind:'move',index:1,target:s.moves[0].targetRequired?(s.moves[0].targets[0]?.location||1):0,mega:mega&&p===0&&i===0})));}}
test('actual Mega Staraptor Close Combat reverses both drops and applies stage ratios until its PP runs out',()=>{
 for(const mode of ['singles','doubles']){
  const e=setup(mode,mon('Staraptor','Intimidate',['closecombat'],'staraptite'));
  for(let i=1;i<=5;i++){
   turn(e,i===1);const p=e.battle.sides[0].active[0],stage=i;
   assert.equal(p.ability,'contrary');assert.equal(p.boosts.def,stage);assert.equal(p.boosts.spd,stage);
   assert.equal(p.getStat('def',false,true),Math.floor(p.storedStats.def*(2+stage)/2));
   assert.equal(e.frame(0).own[0].boosts.def,stage);
   assert.equal(e.frame(1).foe[0].boosts,undefined);
  }
  assert.ok(e.frame(0).log.some(l=>l.includes('[from] ability: Contrary')),mode+' public Contrary attribution');
  const f=e.frame(0);e.choose(0,f.decisionID,[{kind:'switch',index:mode==='singles'?2:3},...(mode==='doubles'?[{kind:'move',index:1,target:0}]:[])]);
  const b=e.frame(1);e.choose(1,b.decisionID,b.slots.map(()=>({kind:'move',index:1,target:0})));
  assert.equal(e.frame(0).own.find(p=>p.id==='a0').boosts.def,0,'Switching resets the modified stages');
 }
});
test('Contrary also reverses increases and opponent drops; Simple doubles both directions',()=>{
 for(const mode of ['singles','doubles'])for(const [species,ability,move,enemyMove,stat,expected]of [
  ['Serperior','Contrary','swordsdance','splash','atk',-2],
  ['Serperior','Contrary','splash','growl','atk',1],
  ['Swoobat','Simple','calmmind','splash','spa',2],
  ['Swoobat','Simple','splash','growl','atk',-2]
 ]){
  const e=setup(mode,mon(species,ability,[move]),mon('Smeargle','Own Tempo',[enemyMove]));turn(e);
  assert.equal(e.frame(0).own[0].boosts[stat],expected,mode+' '+ability+' '+move);
  assert.ok(e.frame(0).log.some(l=>l.includes('[from] ability: '+ability)),mode+' '+ability+' public notice');
  for(let i=0;i<6;i++)turn(e);
  assert.equal(e.frame(0).own[0].boosts[stat],expected>0?6:-6,'Normal repeated uses obey the stage cap');
  const perUse=move==='calmmind'?2:1;
  assert.equal(e.frame(0).log.filter(l=>l.includes('|p1a:')&&l.includes('[from] ability: '+ability)).length,perUse*Math.ceil(6/Math.abs(expected)),'Do not announce a modifier when every affected stage is already capped');
 }
});
test('Gastro Acid suppression leaves original move stages and does not claim a modifier activation',()=>{
 for(const [species,ability,move,stat,expected]of [['Serperior','Contrary','swordsdance','atk',2],['Swoobat','Simple','calmmind','spa',1]]){
  const foe=mon('Smeargle','Own Tempo',['gastroacid']);foe.stats.spe=999;
  const e=setup('singles',mon(species,ability,[move]),foe);turn(e);
  assert.equal(e.frame(0).own[0].boosts[stat],expected);
  assert.ok(!e.frame(0).log.some(l=>l.includes('[from] ability: '+ability)));
 }
});
test('Mist blocks a Simple-amplified opposing drop without a false stat-change notice',()=>{
 const e=setup('singles',mon('Swoobat','Simple',['mist','splash']),mon('Smeargle','Own Tempo',['growl']));
 e.battle.sides[0].active[0].storedStats.spe=999;
 turn(e);
 assert.equal(e.frame(0).own[0].boosts.atk,0);
 assert.ok(e.frame(0).log.some(l=>l.includes('Mist')));
 assert.ok(!e.frame(0).log.some(l=>l.includes('[from] ability: Simple')));
});
