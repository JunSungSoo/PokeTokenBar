// Offline target scopes from the same pinned engine dex used by actual battles.
const fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'..');
const folder=path.join(root,'Sources/PokeTokenBar/Resources/BattleText');
const {battleDex}=require('../BattleEngine/held-items.cjs');
const dex=battleDex(),targets={};
for(const file of ['catalog.json','gen6-fairy.json']) {
 for(const id of Object.keys(JSON.parse(fs.readFileSync(path.join(folder,file))).moves)) {
  const move=dex.moves.get(id);
  if(!move.exists||!move.target)throw Error('Missing move target: '+id);
  targets[id]=move.target;
 }
}
fs.writeFileSync(path.join(folder,'move-targets.json'),JSON.stringify(Object.fromEntries(Object.entries(targets).sort()))+'\n');
console.log('Prepared target scopes for '+Object.keys(targets).length+' move entries');
