'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown'),{OwnedBattle}=require('../engine.cjs');
const catalog=require('../challenge-opponents.json'),dex=Dex.mod('gen5');
test('all 162 opponents use their round level and matching Gen V zero-EV stats in the real engine',()=>{
 assert.equal(catalog.evPolicy,'zero');
 for(const encounter of catalog.encounters){
  const level=encounter.index<24?95:100;
  const battle=new OwnedBattle('singles',[catalog.encounters.at(-1).team.map(p=>({...p,item:''})),encounter.team],[1,2,3,4],{profile:'challenge'});
  const actual=battle.frame(1).own;
  for(const p of encounter.team){
   assert.equal(p.level,level,encounter.id);
   const base=dex.species.get(p.species).baseStats,nature=dex.natures.get(p.nature);
   for(const stat of ['hp','atk','def','spa','spd','spe']){
    const effortFree=Math.floor(((2*base[stat]+p.ivs[stat])*level)/100);
    const expected=stat==='hp'?effortFree+level+10:Math.floor((effortFree+5)*(nature.plus===stat?1.1:nature.minus===stat?.9:1));
    assert.equal(p.stats[stat],expected,`${encounter.id}/${p.species}/${stat}`);
    if(level<100){
     const old=stat==='hp'?2*base.hp+p.ivs.hp+110:Math.floor((2*base[stat]+p.ivs[stat]+5)*(nature.plus===stat?1.1:nature.minus===stat?.9:1));
     assert.ok(p.stats[stat]<old,`${p.species}/${stat} must decrease`);
    }
   }
   const shown=actual.find(a=>a.id===p.id);assert.equal(shown.level,level);assert.deepEqual(shown.stats,p.stats);assert.equal(shown.maxHP,p.stats.hp);assert.equal(shown.item,p.item);
  }
 }
});
test('level-policy compiler is reproducible and preserves fixed moves, abilities and perfect-IV Red',()=>{
 const {applyOpponentLevels}=require('../../scripts/challenge/level-policy.cjs');
 assert.deepEqual(applyOpponentLevels(structuredClone(catalog),dex),catalog);
 for(const p of catalog.encounters.at(-1).team){assert.equal(p.level,100);assert.ok(Object.values(p.ivs).every(v=>v===31));}
 assert.ok(catalog.compatiblePreviousVersions.length===6);
});

test('Red replaces Espeon with the approved level-100 Mewtwo and Recover works in a real turn',()=>{
 const red=catalog.encounters.find(e=>e.id==='red');
 assert.equal(red.team.length,6);assert.ok(!red.team.some(p=>p.speciesID===196));
 const m=red.team.find(p=>p.speciesID===150);
 assert.equal(m.ability,'Pressure');assert.equal(m.nature,'Timid');assert.equal(m.item,'lifeorb');
 assert.deepEqual(m.moves,['psystrike','shadowball','recover','flamethrower']);
 const {applyRedOverrides}=require('../../scripts/challenge/red-overrides.cjs');
 assert.deepEqual(require('../../scripts/challenge/optimize-items.cjs').applyRoleItems(applyOpponentLevelsForTest(applyRedOverrides(structuredClone(catalog),dex)),dex),catalog);
 const own=[m,...red.team.filter(p=>p.id!==m.id).map(p=>({...p,item:''}))];
 const enemy=catalog.encounters[0].team.map(p=>({...p,moves:['splash']}));
 const initial=new OwnedBattle('singles',[own,enemy],[1,2,3,4],{profile:'challenge'});
 assert.equal(initial.frame(0).own.find(p=>p.active).cpuRecoveryThreshold,undefined,'Player sets cannot enable the NPC tactic');
 const resources=initial.frame(0).resources;resources[0].hp=100;
 const battle=new OwnedBattle('singles',[own,enemy],[1,2,3,4],{profile:'challenge',resources:[resources,null]});
 const before=battle.frame(0);assert.equal(before.own.find(p=>p.active).id,m.id);
 battle.choose(0,before.decisionID,[{kind:'move',index:3,target:0}]);
 battle.choose(1,battle.frame(1).decisionID,[{kind:'move',index:1,target:0}]);
 const after=battle.frame(0).resources.find(p=>p.id===m.id);
 assert.ok(after.hp>100);assert.ok(after.hp<=m.stats.hp);
 assert.equal(after.moves[2].pp,resources[0].moves[2].pp-1);
});
function applyOpponentLevelsForTest(c){return require('../../scripts/challenge/level-policy.cjs').applyOpponentLevels(c,dex);}

test('Red Mewtwo prioritizes legal Recover at 65% HP and avoids full-HP or empty-PP recovery',()=>{
 const {chooseCPU,loadPolicy}=require('../challenge-policy.cjs');
 const red=catalog.encounters.find(e=>e.id==='red').team,m=red.find(p=>p.speciesID===150);
 assert.equal(m.cpuRecoveryThreshold,.65);
 assert.equal(red.find(p=>p.speciesID===3).item,'blacksludge');
 assert.equal(new Set(red.map(p=>p.item)).size,6);
 const npc=[m,...red.filter(p=>p!==m)];
 const own=catalog.encounters[0].team.map(p=>({...p,item:'',moves:['splash']}));
 const initial=new OwnedBattle('singles',[own,npc],[1,2,3,4],{profile:'challenge'});
 const make=(fraction,pp=10,legacy=false)=>{
  const resources=structuredClone(initial.frame(1).resources);
  resources[0].hp=Math.floor(m.stats.hp*fraction);resources[0].moves[2].pp=pp;
  const opponents=structuredClone(npc);if(legacy)delete opponents[0].cpuRecoveryThreshold;
  return new OwnedBattle('singles',[own,opponents],[1,2,3,4],{profile:'challenge',resources:[null,resources]});
 };
 const low=make(.65),before=low.frame(1),state=before.resources[0];
 assert.equal(before.own.find(p=>p.active).cpuRecoveryThreshold,.65);
 assert.equal(chooseCPU(dex,before).index,3);
 // A strongly attacking model proves the explicit tactic, rather than an incidental
 // recovery score, is responsible. Old checkpoints retain those learned scores.
 const offense={...loadPolicy(),weights:loadPolicy().weights.map(()=>0)};
 offense.weights[offense.features.indexOf('power')]=100;
 assert.equal(chooseCPU(dex,before,offense).index,3);
 assert.notEqual(chooseCPU(dex,make(.65,10,true).frame(1),offense).index,3);
 assert.equal(make(.65,10,true).frame(1).own.find(p=>p.active).cpuRecoveryThreshold,undefined);
 assert.notEqual(chooseCPU(dex,make(.66).frame(1),offense).index,3);
 assert.notEqual(chooseCPU(dex,make(1).frame(1)).index,3);
 assert.notEqual(chooseCPU(dex,make(.4,0).frame(1)).index,3);
 const blocked=structuredClone(before);blocked.slots[0].moves.find(p=>p.index===3).disabled=true;
 assert.notEqual(chooseCPU(dex,blocked).index,3);
 low.runCPU();low.choose(0,low.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 const after=low.frame(1).resources.find(p=>p.id===m.id);
 assert.ok(after.hp>state.hp);assert.equal(after.moves[2].pp,state.moves[2].pp-1);
 // Below the cutoff again after an attacking turn: the tactic remains available.
 const repeated=make(.35);assert.equal(chooseCPU(dex,repeated.frame(1)).index,3);
});
