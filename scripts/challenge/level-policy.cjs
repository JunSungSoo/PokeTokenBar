'use strict';
// Explicitly compatible roster updates. Existing
// in-flight checkpoints keep their original opponent set for deterministic replay.
const previousCatalog='challenge-bw-v2-red-sun-max-ivs/3b953196790944aba015f8c2c585ee1c2d5dce6c500cf3ad4f1856f715453956';
function applyOpponentLevels(catalog,dex){
 for(const encounter of catalog.encounters){
  const level=encounter.index<24?95:100;
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
 catalog.version='challenge-bw-v8-gym-elite-95';
 catalog.levelPolicy={gymLeaders:95,eliteFour:95,championsAndRed:100};
 catalog.compatiblePreviousVersions=[previousCatalog,'challenge-bw-v3-tiered-opponent-levels/cba4ebcf4e2884f290606d8585fa84be1da23531fab95c0faf5ff32f9c00cd06','challenge-bw-v4-role-opponent-levels/6c25210dee2c3830259f1cf22730619d60e56fd65802971f134b8fb7f65afaea','challenge-bw-v5-red-mewtwo/bb4209190f979fdcd7995827e00629030c261579f7ef2483e7033c1ae1d8d7fb','challenge-bw-v6-red-mewtwo-recovery/60ccc86942e79cc8ef71d79f73d2e41da3cdfeff2d26a6d82b82f54676696089','challenge-bw-v7-role-items/906e0a5cec66ffa5ea9ac03262447019dc7feb2cf5fb91cc0cbc5b29e64d8779'];
 return catalog;
}
module.exports={applyOpponentLevels};
if(require.main===module){
 const fs=require('node:fs'),{Dex}=require('../../BattleEngine/node_modules/pokemon-showdown');
 const file='BattleEngine/challenge-opponents.json';
 fs.writeFileSync(file,JSON.stringify(applyOpponentLevels(JSON.parse(fs.readFileSync(file)),Dex.mod('gen5')),null,2)+'\n');
}
