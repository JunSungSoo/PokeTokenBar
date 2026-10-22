// Run from the repository root after scripts/prepare-battle-engine.sh.
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const d=Dex.mod('gen5'), seen=new Set();
const moves=d.moves.all().filter(m=>{
  if(m.num<1||m.num>559||seen.has(m.id))return false;
  seen.add(m.id);return true;
}).map(m=>({id:m.num,key:m.id,name:m.name,desc:m.desc||m.shortDesc,
 power:m.basePower,pp:m.pp,accuracy:m.accuracy,category:m.category,type:m.type}));
process.stdout.write(JSON.stringify({moves,
 species:d.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5).map(s=>({id:s.num,key:s.id,name:s.name})),
 abilities:d.abilities.all().filter(a=>a.gen<=5).map(a=>({id:a.num,key:a.id,name:a.name,desc:a.desc||a.shortDesc}))})+'\n');
