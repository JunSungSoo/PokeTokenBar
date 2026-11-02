'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const kinds=[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Scizor','Technician'],['Slowbro','Own Tempo']];
function team(prefix){return kinds.map(([species,ability],i)=>({id:prefix+i,species,ability,moves:['tackle','splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100}}));}
function setup(boosts,edit=()=>{}){const teams=[team('a'),team('b')];edit(teams);return new OwnedBattle('singles',teams,[1,2,3,4],{profile:'challenge',challengeBoosts:boosts});}
function turn(e,a={kind:'move',index:2,target:0},b={kind:'move',index:2,target:0}){e.choose(0,e.frame(0).decisionID,[a]);e.choose(1,e.frame(1).decisionID,[b]);}
function damage(e,crit=false){const p=e.battle.sides[0].active[0],q=e.battle.sides[1].active[0],move={...e.battle.dex.moves.get('tackle'),willCrit:crit};e.battle.setActiveMove(move,p,q);return e.battle.actions.getDamage(p,q,move);}
test('team rewards add stages, retain owned stats, and survive Haze/clear and switches for all six',()=>{
 const e=setup({atk:2,spa:2});let p=e.battle.sides[0].active[0];
 assert.equal(p.getStat('atk'),240);assert.equal(p.getStat('spa'),240);assert.equal(p.storedStats.atk,120);
 assert.ok(e.frame(0).own.every(p=>p.boosts.atk===2&&p.boosts.spa===2&&p.stats.atk===120));
 p.boosts.atk=-1;assert.equal(p.getStat('atk'),180);p.clearBoosts();assert.equal(p.getStat('atk'),240);
 turn(e,{kind:'switch',index:2,target:0});p=e.battle.sides[0].active[0];assert.equal(p.set.ptbID,'a1');assert.equal(p.getStat('atk'),240);
 assert.equal(e.battle.sides[1].active[0].getStat('atk'),120);
 p.boosts.atk=4;assert.equal(p.boostBy({atk:1}),0);assert.equal(p.getStat('atk'),480);
});
test('damage and critical-hit checks use combined stages before the standard calculation',()=>{
 for(const crit of [false,true]){
  const reward=setup({atk:2}),ordinary=setup({});ordinary.battle.sides[0].active[0].boosts.atk=2;
  assert.equal(damage(reward,crit),damage(ordinary,crit));
  assert.equal(reward.battle.sides[0].active[0].boosts.atk,0,'Calculation must restore ordinary engine stages');
 }
 const reward=setup({atk:1}),ordinary=setup({});reward.battle.sides[0].active[0].boosts.atk=-1;
 assert.equal(damage(reward,true),damage(ordinary,true),'A crit must inspect the combined zero stage');
});
test('Contrary and Simple affect move boosts, not the external team reward; Unaware remains effective',()=>{
 for(const [species,ability,expected]of [['Shuckle','Contrary',2],['Bibarel','Simple',-1]]){
  const e=setup({atk:1},t=>Object.assign(t[0][0],{species,ability})),p=e.battle.sides[0].active[0];
  e.battle.boost({atk:-1},p,p,e.battle.dex.moves.get('growl'));
  assert.equal(e.frame(0).own.find(m=>m.active).boosts.atk,expected);
 }
 const edit=t=>Object.assign(t[1][0],{species:'Quagsire',ability:'Unaware'});
 assert.equal(damage(setup({atk:2},edit)),damage(setup({},edit)));
});
test('reward speed participates in real turn order and Trick Room reversal',()=>{
 const e=setup({spe:1},t=>t[1].forEach(p=>p.stats.spe=120));
 turn(e);let moves=e.battle.log.filter(l=>l.startsWith('|move|'));assert.match(moves[0],/p1a/);
 e.battle.field.addPseudoWeather('trickroom',e.battle.sides[0].active[0],e.battle.dex.moves.get('trickroom'));const start=e.battle.log.length;turn(e);
 moves=e.battle.log.slice(start).filter(l=>l.startsWith('|move|'));assert.match(moves[0],/p2a/);
});
test('Mega form stats retain the same reward and never overwrite the owned baseline',()=>{
 const red=require('../challenge-opponents.json').encounters.at(-1).team;
 const own=structuredClone(red).map(p=>({...p,item:p.speciesID===6?'charizarditey':''}));[own[0],own[4]]=[own[4],own[0]];
 const e=new OwnedBattle('singles',[own,team('b')],[1,2,3,4],{profile:'challenge',challengeBoosts:{atk:1,spa:1,spe:1}}),p=e.battle.sides[0].active[0];
 const hp=p.maxhp;e.battle.actions.runMegaEvo(p);assert.equal(p.species.id,'charizardmegay');assert.equal(p.maxhp,hp);
 assert.equal(p.getStat('spa'),Math.floor(p.storedStats.spa*1.5));assert.equal(p.set.ptbStats.spa,own[0].stats.spa);
});
test('invalid or peer reward payloads cannot alter battles',()=>{
 for(const boost of [{atk:-1},{hp:1},{atk:7},{spe:1.5},[],{spa:'1'}])assert.throws(()=>setup(boost));
 assert.throws(()=>new OwnedBattle('singles',[team('a'),team('b')],[1,2,3,4],{challengeBoosts:{atk:1}}),/Challenge-only/);
});

test('Defense and Sp. Def rewards reduce the corresponding damage without raising offense or HP',()=>{
 function received(e,moveID){const source=e.battle.sides[1].active[0],target=e.battle.sides[0].active[0],move={...e.battle.dex.moves.get(moveID),willCrit:false};e.battle.setActiveMove(move,source,target);return e.battle.actions.getDamage(source,target,move);}
 for(const [key,move]of [['def','tackle'],['spd','surf']]){
  const reward=setup({[key]:1}),ordinary=setup({}),plain=setup({});ordinary.battle.sides[0].active[0].boosts[key]=1;
  assert.equal(received(reward,move),received(ordinary,move));assert.ok(received(setup({[key]:1}),move)<received(plain,move));
  const own=reward.frame(0).own.find(p=>p.active);assert.equal(own.boosts[key],1);assert.equal(own.boosts.atk,0);assert.equal(own.boosts.spa,0);assert.equal(own.maxHP,500);
 }
});
