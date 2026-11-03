'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown'),{OwnedBattle}=require('../engine.cjs');
const catalog=require('../challenge-opponents.json'),dex=Dex.mod('gen5');
const {applyRoleItems,itemCandidates,suitability,assignTeam,RED_LOCKS}=require('../../scripts/challenge/optimize-items.cjs');
function member(encounter,species){return catalog.encounters.find(e=>e.id===encounter).team.find(p=>p.species===species);}
test('all fixed teams use unique, role-compatible items and preserve explicit Red equipment',()=>{
 for(const e of catalog.encounters){
  assert.equal(new Set(e.team.map(p=>p.item)).size,6,e.id);
  for(const p of e.team){
   assert.equal(suitability(p,p.item,dex),null,`${e.id}/${p.species}/${p.item}`);
   assert.ok(itemCandidates(p,dex).some(c=>c.item===p.item));
   assert.ok(p.evidence.itemOptimization.reason);
   if(p.item==='choiceband')assert.ok(p.moves.filter(m=>dex.moves.get(m).category==='Physical').length>=2);
   if(p.item==='choicespecs')assert.ok(p.moves.filter(m=>dex.moves.get(m).category==='Special').length>=2);
   if(p.item==='wiseglasses')assert.ok(p.moves.some(m=>dex.moves.get(m).category==='Special'));
   if(p.item.startsWith('choice'))assert.ok(p.moves.every(m=>dex.moves.get(m).category!=='Status'||['trick','switcheroo','sleeptalk'].includes(m)));
  }
 }
 for(const [id,item]of Object.entries(RED_LOCKS))assert.equal(catalog.encounters.at(-1).team.find(p=>p.id===id).item,item);
 assert.equal(member('red','Pikachu').item,'lightball');
 assert.deepEqual(member('red','Mewtwo').moves,['psystrike','shadowball','recover','flamethrower']);
 assert.equal(member('red','Mewtwo').cpuRecoveryThreshold,.65);
});
test('reviewed regressions assign defensive, setup and utility items instead of blind damage boosters',()=>{
 assert.equal(member('giovanni','Donphan').item,'custapberry');
 assert.equal(member('morty','Dusclops').item,'eviolite');
 assert.equal(member('whitney','Clefable').item,'sitrusberry');
 assert.equal(member('jasmine','Forretress').item,'leftovers');
 assert.equal(member('red','Blastoise').item,'leftovers');
 assert.equal(member('brock','Omastar').item,'whiteherb');
 assert.equal(member('bugsy','Heracross').item,'flameorb');
 assert.equal(member('giovanni','Dugtrio').item,'focussash');
 assert.equal(suitability(member('giovanni','Donphan'),'wiseglasses',dex),'no-special');
 assert.equal(suitability(member('misty','Lapras'),'choicespecs',dex),'locks-support-moves');
 assert.ok(!itemCandidates(member('whitney','Clefable'),dex).some(c=>c.item==='lifeorb'),'A weak Knock Off plus fixed damage does not justify Life Orb');
 assert.equal(suitability(member('morty','Dusclops'),'lifeorb',dex),'no-boostable-attack');
 assert.equal(suitability(member('whitney','Clefable'),'eviolite',dex),'fully-evolved');
 assert.equal(suitability(member('morty','Dusclops'),'blacksludge',dex),'not-poison');
 assert.equal(suitability(member('red','Blastoise'),'lightclay',dex),'no-screens');
 assert.equal(suitability(member('giovanni','Donphan'),'flameorb',dex),'no-status-benefit');
});
test('team optimization solves shared-item contention globally, including reserved late slots',()=>{
 const chosen=assignTeam([
  [{item:'leftovers',score:100},{item:'sitrusberry',score:90}],
  [{item:'leftovers',score:99},{item:'sitrusberry',score:1}],
 ]);
 assert.deepEqual(chosen.map(c=>c.item),['sitrusberry','leftovers']);
 const locked=assignTeam([
  [{item:'lifeorb',score:100},{item:'blacksludge',score:90}],
  [{item:'lifeorb',score:1000}],
 ]);
 assert.deepEqual(locked.map(c=>c.item),['blacksludge','lifeorb']);
 assert.throws(()=>assignTeam([[]]),/No role-compatible/);
 assert.throws(()=>assignTeam([[{item:'leftovers',score:10}],[{item:'leftovers',score:10}]]),/No unique/);
});
test('offline item compilation is deterministic and changes neither roster nor battle builds',()=>{
 const next=applyRoleItems(structuredClone(catalog),dex);
 assert.deepEqual(next,catalog);
 for(const e of catalog.encounters){
  const shuffled=structuredClone(e);shuffled.team.reverse();
  // Every resulting member is still eligible even if another order breaks a score tie.
  const c={encounters:[shuffled]};applyRoleItems(c,dex);
  assert.equal(new Set(shuffled.team.map(p=>p.item)).size,6);
  for(const p of shuffled.team){
   const before=e.team.find(b=>b.id===p.id),copy={...p,item:before.item,evidence:before.evidence};
   assert.deepEqual(copy,before,'Order, moves, stats, abilities, tactics and nature stay frozen');
  }
 }
});
function battleWith(npc){
 const first=npc[0],own=catalog.encounters[0].team.map(p=>({...p,item:'',moves:['splash']}));
 const battle=new OwnedBattle('singles',[own,npc],[1,2,3,4],{profile:'challenge'});
 assert.equal(battle.frame(1).own.find(p=>p.active).id,first.id);return battle;
}
function turn(battle,index){
 battle.choose(0,battle.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 battle.choose(1,battle.frame(1).decisionID,[{kind:'move',index,target:0}]);
}
test('assigned White Herb and Flame Orb activate in actual NPC battle turns',()=>{
 const brock=catalog.encounters[0].team,omastar=member('brock','Omastar');
 const smash=battleWith([omastar,...brock.filter(p=>p.id!==omastar.id)]);
 turn(smash,3);
 const mon=smash.battle.sides[1].active[0];
 assert.equal(mon.boosts.spa,2);assert.equal(mon.boosts.spe,2);
 assert.equal(mon.boosts.def,0);assert.equal(mon.boosts.spd,0);assert.equal(mon.item,'');
 const bugsy=catalog.encounters.find(e=>e.id==='bugsy').team,heracross=member('bugsy','Heracross');
 const guts=battleWith([heracross,...bugsy.filter(p=>p.id!==heracross.id)]);
 turn(guts,1);
 const fighter=guts.battle.sides[1].active[0];
 assert.equal(fighter.status,'brn');assert.equal(fighter.getAbility().id,'guts');
 assert.ok(fighter.getStat('atk')>heracross.stats.atk);
});
