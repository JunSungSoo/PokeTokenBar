// Legal Gen V ability slots, including forms; no modern PokéAPI replacements.
const fs=require('node:fs');
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const dex=Dex.mod('gen5'), result={};
for(const species of dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5)) {
 result[species.id]=Object.entries(species.abilities).filter(([slot,name])=>['0','1','H'].includes(slot)&&dex.abilities.get(name).gen<=5).map(([slot,name])=>({name,slot:slot==='H'?3:Number(slot)+1,isHidden:slot==='H'}));
}
fs.writeFileSync('Sources/PokeTokenBar/Resources/BattleText/ability-options.json',JSON.stringify(result)+'\n');
