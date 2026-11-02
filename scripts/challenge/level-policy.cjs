'use strict';
// Explicitly compatible roster: only opponent level/stat policy changes. Existing
// in-flight checkpoints keep their original opponent set for deterministic replay.
const previousCatalog='challenge-bw-v2-red-sun-max-ivs/3b953196790944aba015f8c2c585ee1c2d5dce6c500cf3ad4f1856f715453956';
function applyOpponentLevels(catalog,dex){
 for(const encounter of catalog.encounters){
  const level=encounter.index<12?75:encounter.index<16?90:100;
  for(const pokemon of encounter.team){
   const species=dex.species.get(pokemon.species),nature=dex.natures.get(pokemon.nature);
   pokemon.level=level;
   pokemon.stats=Object.fromEntries(Object.entries(species.baseStats).map(([stat,base])=>{
    const raw=Math.floor((2*base+pokemon.ivs[stat])*level/100);
    return [stat,stat==='hp'?(base===1?1:raw+level+10):Math.floor((raw+5)*(nature.plus===stat?1.1:nature.minus===stat?.9:1))];
   }));
  }
 }
 delete catalog.level;
 catalog.version='challenge-bw-v3-tiered-opponent-levels';
 catalog.levelPolicy={rounds1To12:75,rounds13To16:90,eliteFourAndBeyond:100};
 catalog.compatiblePreviousVersions=[previousCatalog];
 return catalog;
}
module.exports={applyOpponentLevels};
if(require.main===module){
 const fs=require('node:fs'),{Dex}=require('../../BattleEngine/node_modules/pokemon-showdown');
 const file='BattleEngine/challenge-opponents.json';
 fs.writeFileSync(file,JSON.stringify(applyOpponentLevels(JSON.parse(fs.readFileSync(file)),Dex.mod('gen5')),null,2)+'\n');
}
