// BW2 terminal species; later-generation evolutions must not disqualify Gen V final forms.
const fs=require('node:fs');
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const dex=Dex.mod('gen5'), species=dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5);
const nonfinal=new Set(species.filter(s=>s.evos.some(name=>dex.species.get(name).gen<=5)).map(s=>s.num));
const finals=[...new Set(species.map(s=>s.num))].filter(id=>!nonfinal.has(id)).sort((a,b)=>a-b);
fs.writeFileSync('Sources/PokeTokenBar/Resources/BattleText/final-species.json',JSON.stringify(finals)+'\n');
