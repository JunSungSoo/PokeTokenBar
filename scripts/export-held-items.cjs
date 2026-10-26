// Export rules from the pinned simulator; translations are added by prepare-held-items.py.
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const stones=require('../BattleEngine/champions-mega-stones.json');
const groups={type:['silkscarf','charcoal','mysticwater','magnet','miracleseed','nevermeltice','blackbelt','poisonbarb','softsand','sharpbeak','twistedspoon','silverpowder','hardstone','spelltag','dragonfang','blackglasses','metalcoat'],power:['lifeorb','expertbelt','muscleband','wiseglasses','metronome','normalgem'],recovery:['leftovers','shellbell','bigroot'],defense:['focussash','focusband','rockyhelmet','airballoon','toxicorb'],order:['choicescarf','quickclaw','ironball'],berries:['sitrusberry','lumberry']};
const records=Object.entries(groups).flatMap(([group,ids])=>ids.map(id=>{const i=Dex.mod('gen5').items.get(id);return {id,name:i.name,generation:i.gen,group,description:i.desc||i.shortDesc};}));
for(const name of stones){
 const i=Dex.items.get(name);if(!i.exists||!i.megaStone)throw Error(name);
 const [base,mega]=Object.entries(i.megaStone)[0],s=Dex.species.get(base),m=Dex.mod(i.gen===6?'gen6':'gen9').species.get(mega);
 if(s.num<1||s.num>649)continue;
 records.push({id:i.id,name:i.name,generation:i.gen,group:'mega',description:i.desc,mega:{baseID:s.num,base,species:m.name,form:m.forme.toLowerCase().replaceAll(' ','-'),types:m.types,ability:m.abilities[0],stats:m.baseStats}});
}
console.log(JSON.stringify(records));
