'use strict';
const assert=require('node:assert/strict'),{OwnedBattle}=require('../../engine.cjs');
function team(prefix){return [['Pikachu','Static'],['Raichu','Static'],['Ampharos','Static'],['Electabuzz','Static'],['Jolteon','Volt Absorb'],['Electrode','Static']].map(([species,ability],i)=>({id:prefix+i,species,ability,moves:['splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:200,spa:100,spd:200,spe:200-i*10}}));}
const result={};
for(const mode of ['singles','doubles']){
 for(let seed=0;seed<64;seed++){
  const own=team('a'),foe=team('b');own[0].moves=['thunderbolt'];
  const e=new OwnedBattle(mode,[own,foe],[1,2,3,seed]);
  e.battle.sides[0].active[0].boosts.accuracy=-6;
  for(const player of [0,1]){
   const frame=e.frame(player),actions=frame.slots.map((slot,i)=>({kind:'move',index:1,target:player===0&&i===0&&mode==='doubles'?1:0}));
   e.choose(player,frame.decisionID,actions);
  }
  if(e.frame(0).log.some(l=>l.startsWith('|-miss|p1a: Pikachu|'))){result[mode]=[e.frame(0),e.frame(1)];break;}
 }
 assert(result[mode],mode+' must include a real accuracy miss');
}
process.stdout.write(JSON.stringify(result));
