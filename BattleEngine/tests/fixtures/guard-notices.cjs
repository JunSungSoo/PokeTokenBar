'use strict';
const assert=require('node:assert/strict'),{OwnedBattle}=require('../../engine.cjs');
const roster=prefix=>[['Pikachu','Static'],['Raichu','Static'],['Ampharos','Static'],['Electabuzz','Static'],['Jolteon','Volt Absorb'],['Electrode','Static']].map(([species,ability],i)=>({id:prefix+i,species,ability,moves:['splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:200,spa:100,spd:200,spe:200-i*10}}));
const result={};
for(const mode of ['singles','doubles'])for(const guard of ['protect','detect']){
 const own=roster('a'),foe=roster('b');own[0].moves=['thunderbolt'];foe[0].moves=[guard];if(mode==='doubles'){own[1].moves=['thunderbolt'];foe[1].moves=[guard];}
 const e=new OwnedBattle(mode,[own,foe],[1,2,3,4]);
 for(const player of [0,1]){
  const f=e.frame(player);e.choose(player,f.decisionID,f.slots.map((_,i)=>({kind:'move',index:1,target:player===0&&mode==='doubles'?i+1:0})));
 }
 const frames=[e.frame(0),e.frame(1)];assert(frames[0].log.some(l=>l==='|-activate|p2a: Pikachu|move: Protect'));
 result[mode+'-'+guard]=frames;
}
process.stdout.write(JSON.stringify(result));
