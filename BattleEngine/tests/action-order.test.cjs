const {test}=require('node:test');
const assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown');
const {OwnedBattle}=require('../engine.cjs');
const dex=Dex.mod('gen5');
function mon(species,ability,speed,moves=['amnesia']) {
 return {species,ability,moves,level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:80,def:100,spa:80,spd:100,spe:speed}};
}
function team(prefix,lead) {
 const result=[lead];
 for(const [s,a] of [['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician'],['Snorlax','Immunity']]) {
  if(result.length<6&&!result.some(p=>p.species===s))result.push(mon(s,a,70));
 }
 return result.map((p,i)=>({...p,id:prefix+i}));
}
function battle(a,b){return new OwnedBattle('singles',[team('a',a),team('b',b)],[1,2,3,4]);}
function turn(e,a=1,b=1){const last=Math.max(-1,...e.frame(0).effects.map(m=>m.id));for(const [p,index]of [[0,a],[1,b]]){const f=e.frame(p);e.choose(p,f.decisionID,[{kind:'move',index,target:0}]);}return e.frame(0).effects.filter(m=>m.id>last).map(m=>m.source.own?0:1);}
test('equal-priority moves use current speed, and priority precedes speed even in Trick Room',()=>{
 const e=battle(mon('Smeargle','Own Tempo',80,['quickattack','trickroom','amnesia']),mon('Snorlax','Immunity',200));
 assert.deepEqual(turn(e,3),[1,0]);
 assert.deepEqual(turn(e,1),[0,1]);
 turn(e,2);assert.ok(e.frame(0).field.conditions.includes('trickroom'));
 assert.deepEqual(turn(e,3),[0,1]);
 const fast=battle(mon('Smeargle','Own Tempo',200,['trickroom','quickattack']),mon('Snorlax','Immunity',80));
 turn(fast);assert.deepEqual(turn(fast,2),[0,1],'priority wins even though Trick Room favors the other Pokémon');
});
test('Tailwind and BW2 paralysis change the actual execution order',()=>{
 const wind=battle(mon('Smeargle','Own Tempo',80,['tailwind','amnesia']),mon('Snorlax','Immunity',120));
 turn(wind);assert.deepEqual(turn(wind,2),[0,1]);
 const par=battle(mon('Smeargle','Own Tempo',80,['thunderwave','amnesia']),mon('Snorlax','Immunity',200));
 turn(par);assert.equal(par.battle.sides[1].active[0].getStat('spe'),50);
 // Ignore possible full paralysis: the first actual action is still the now faster Pokémon.
 assert.equal(turn(par,2)[0],0);
});
test('rain Swift Swim changes execution order; Cloud Nine suppression restores normal speed',()=>{
 const rain=battle(mon('Ludicolo','Swift Swim',80),mon('Politoed','Drizzle',120));
 assert.deepEqual(turn(rain),[0,1]);
 const suppressed=battle(mon('Ludicolo','Swift Swim',80),mon('Golduck','Cloud Nine',120));
 suppressed.battle.field.setWeather('raindance',suppressed.battle.sides[0].active[0]);
 assert.equal(suppressed.frame(0).field.weatherSuppressed,true);
 assert.deepEqual(turn(suppressed),[1,0]);
});
test('long battles keep monotonic presentation event IDs after the bounded public log rolls over',()=>{
 const e=battle(mon('Smeargle','Own Tempo',80,['growl']),mon('Snorlax','Immunity',120,['growl']));
 let last=-1;
 for(let i=0;i<35;i++){
  turn(e);
  for(const side of [0,1]){
   const f=e.frame(side);const recent=f.effects.filter(m=>m.id>last);
   assert.equal(recent.length,2);assert.ok(f.log.length<=160);
   assert.ok(recent.every(m=>f.log[m.id-f.logOffset].startsWith('|move|')));
  }
  last=Math.max(...e.frame(0).effects.map(m=>m.id));
 }
 assert.ok(e.frame(0).logOffset>0);
 assert.equal(e.frame(0).own[0].ability,'Own Tempo');
 assert.equal(e.frame(1).own[0].ability,'Immunity');
 assert.equal(e.frame(0).foe[0].ability,undefined,'hidden opposing ability must not leak');
});
