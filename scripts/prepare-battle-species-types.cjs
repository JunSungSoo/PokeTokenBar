// Offline BW2 roster types, including form overrides, from the pinned battle engine.
const fs=require('node:fs');
const path=require('node:path');
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const dex=Dex.mod('gen5'),types={};
for(const s of dex.species.all()) {
 if(!s.exists||s.num<1||s.num>649||s.gen>5)continue;
 const form=(s.forme||'').toLowerCase().replace(/ /g,'-');
 types[String(s.num)+(form?':'+form:'')]=s.types.map(t=>t.toLowerCase());
}
for(let id=1;id<=649;id++)if(!types[id])throw Error('Missing species '+id);
fs.writeFileSync(path.join(__dirname,'../Sources/PokeTokenBar/Resources/BattleText/species-types.json'),JSON.stringify(types)+'\n');
console.log('Generated BW2 roster types: '+Object.keys(types).length+' species/forms');

const chart={};
for(const attack of dex.types.names()) {
 chart[attack.toLowerCase()]={};
 for(const defense of dex.types.names()) {
  chart[attack.toLowerCase()][defense.toLowerCase()]=dex.getImmunity(attack,[defense])?2**dex.getEffectiveness(attack,[defense]):0;
 }
}
fs.writeFileSync(path.join(__dirname,'../Sources/PokeTokenBar/Resources/BattleText/type-chart.json'),JSON.stringify(chart)+'\n');
