'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown'),{OwnedBattle}=require('../engine.cjs');
const catalog=require('../challenge-opponents.json'),dex=Dex.mod('gen5');
test('all 162 opponents use their round level and matching Gen V zero-EV stats in the real engine',()=>{
 assert.equal(catalog.evPolicy,'zero');
 for(const encounter of catalog.encounters){
  const level=encounter.index<=11?75:encounter.index<=15?90:100;
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
   const shown=actual.find(a=>a.id===p.id);assert.equal(shown.level,level);assert.deepEqual(shown.stats,p.stats);assert.equal(shown.maxHP,p.stats.hp);
  }
 }
});
test('level-policy compiler is reproducible and preserves fixed moves, abilities and perfect-IV Red',()=>{
 const {applyOpponentLevels}=require('../../scripts/challenge/level-policy.cjs');
 assert.deepEqual(applyOpponentLevels(structuredClone(catalog),dex),catalog);
 for(const p of catalog.encounters.at(-1).team){assert.equal(p.level,100);assert.ok(Object.values(p.ivs).every(v=>v===31));}
 assert.ok(catalog.compatiblePreviousVersions.length===1);
});
