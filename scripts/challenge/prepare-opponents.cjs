// Compile reviewed rosters and BW analyses into legal, fixed teams. Never run in the app.
const fs=require('fs'),path=require('path'),{Dex,TeamValidator}=require('../../BattleEngine/node_modules/pokemon-showdown');
const root=process.argv[2]||'/tmp/ptb-challenge-review',dex=Dex.mod('gen5');
const rosters=JSON.parse(fs.readFileSync('docs/reference/challenge/roster-proposal.json')).proposals;
const sets=JSON.parse(fs.readFileSync(path.join(root,'sets-gen5.json'))),usage=JSON.parse(fs.readFileSync(path.join(root,'parsed-usage.json')));
const validator=new TeamValidator({...Dex.formats.get('gen5customgame'),id:'ptbchallengelegality',name:'Challenge BW legality',ruleset:['Obtainable'],teamLength:{validate:[1,6],battle:6}});
const manual={
 Pidgey:{ability:'Keen Eye',moves:['Brave Bird','Return','Roost','U-turn'],nature:'Jolly',item:'Eviolite'},
 Rhyhorn:{ability:'Rock Head',moves:['Double-Edge','Earthquake','Rock Blast','Swords Dance'],nature:'Adamant',item:'Eviolite'},
 Ariados:{ability:'Insomnia',moves:['Toxic Spikes','Sucker Punch','Bug Bite','Baton Pass'],nature:'Adamant',item:'Focus Sash'},
 Bellossom:{ability:'Chlorophyll',moves:['Sunny Day','Solar Beam','Sleep Powder','Moonlight'],nature:'Modest',item:'Heat Rock'},
 Clefairy:{ability:'Magic Guard',moves:['Calm Mind','Moonlight','Ice Beam','Thunderbolt'],nature:'Bold',item:'Eviolite'},
 Dewgong:{ability:'Hydration',moves:['Rest','Rain Dance','Surf','Ice Beam'],nature:'Calm',item:'Leftovers'},
 Dodrio:{ability:'Early Bird',moves:['Brave Bird','Return','Quick Attack','Pursuit'],nature:'Jolly',item:'Choice Band'},
 Growlithe:{ability:'Intimidate',moves:['Flare Blitz','Morning Sun','Will-O-Wisp','Wild Charge'],nature:'Impish',item:'Eviolite'},
 Koffing:{ability:'Levitate',moves:['Will-O-Wisp','Pain Split','Sludge Bomb','Fire Blast'],nature:'Bold',item:'Eviolite'},
 Noctowl:{ability:'Insomnia',moves:['Roost','Whirlwind','Air Slash','Toxic'],nature:'Calm',item:'Leftovers'},
 Seel:{ability:'Thick Fat',moves:['Aqua Jet','Ice Shard','Waterfall','Fake Out'],nature:'Adamant',item:'Eviolite'},
 Sneasel:{ability:'Inner Focus',moves:['Ice Punch','Pursuit','Ice Shard','Low Kick'],nature:'Jolly',item:'Life Orb'},
 Voltorb:{ability:'Static',moves:['Thunderbolt','Volt Switch','Taunt','Hidden Power Ice'],nature:'Timid',item:'Life Orb'},
 Metapod:{ability:'Shed Skin',moves:['Bug Bite','Electroweb','Iron Defense','String Shot'],nature:'Impish',item:'Eviolite'},
 Kakuna:{ability:'Shed Skin',moves:['Bug Bite','Electroweb','Iron Defense','String Shot'],nature:'Impish',item:'Eviolite'},
 Pidgeotto:{ability:'Keen Eye',moves:['Brave Bird','Return','Roost','U-turn'],nature:'Jolly',item:'Life Orb'}
};
const permitted=new Set(['ou','uu','ru','nu','pu','zu','lc','ubers']);
const options=v=>Array.isArray(v)?v:[v];
function* combinations(slots,i=0,chosen=[]){if(i===slots.length){yield chosen;return;}for(const m of options(slots[i]))yield* combinations(slots,i+1,[...chosen,m]);}
function candidates(name){
 const species=dex.species.get(name),records=usage[name]||[],stat=records.find(e=>e.source==='2026-09-gen5ou-1630.txt'&&e.raw>=30)||records.sort((a,b)=>b.raw-a.raw)[0];
 const moves=new Map(stat?.moves||[]),abilities=new Map(stat?.abilities||[]);
 const all=[];
 if(manual[name])all.push({format:'manual',label:'Authored legal fallback',...manual[name]});
 if(!manual[name])for(const [format,entries]of Object.entries(sets[name]||{}))if(permitted.has(format))for(const [label,s]of Object.entries(entries))all.push({format,label,...s});
 const result=[];
 for(const base of all)for(const chosen of combinations(base.moves)){
  if(chosen.length!==4||new Set(chosen.map(Dex.toID)).size!==4||chosen.some(m=>!dex.moves.get(m).exists||dex.moves.get(m).gen>5))continue;
  const allowedAbility=base.ability?options(base.ability):Object.values(species.abilities);
  for(const ability of allowedAbility){
   const nature=options(base.nature||'Hardy')[0],ivs={hp:31,atk:31,def:31,spa:31,spd:31,spe:31};
   const hp=chosen.map(m=>dex.moves.get(m)).find(m=>m.id.startsWith('hiddenpower')&&m.type!=='Normal');
   if(hp)Object.assign(ivs,dex.types.get(hp.type).HPivs);
   const s={species:name,name,ability,nature,moves:chosen,level:100,ivs,evs:{hp:0,atk:0,def:0,spa:0,spd:0,spe:0},item:''};
   const errors=validator.validateSet(structuredClone(s));if(errors?.length)continue;
   const score=chosen.reduce((v,m)=>v+Math.log1p(moves.get(dex.moves.get(m).name)||0),0)+Math.log1p(abilities.get(ability)||0);
   const items=options(base.item||'Leftovers').filter(i=>dex.items.get(i).exists&&dex.items.get(i).gen<=5);
   result.push({set:s,items,format:base.format,label:base.label,score,source:stat?.source||null,manual:base.format==='manual'});
  }
 }
 return result.sort((a,b)=>b.score-a.score);
}
const selected=new Map(),catalog={version:'challenge-bw-v1',level:100,evPolicy:'zero',encounters:[]};
const itemFallback=['Leftovers','Life Orb','Expert Belt','Muscle Band','Wise Glasses','Focus Sash','Lum Berry','Sitrus Berry','Quick Claw','Shell Bell','Rocky Helmet'];
for(const r of rosters){
 const used=new Set(),team=[];
 for(const n of r.team){
  const name=n.species,choices=candidates(name);if(!choices.length)throw Error('No legal set: '+name);
  const occurrence=selected.get(name)||0;selected.set(name,occurrence+1);
  // Later encounters prefer another documented role where one is available.
  const roles=[...new Set(choices.map(c=>c.label))],label=roles[occurrence%roles.length];
  const c=choices.find(c=>c.label===label)||choices[0];
  const item=[...c.items,...itemFallback].find(i=>!used.has(Dex.toID(i)));used.add(Dex.toID(item));
  const s={...c.set,item};const errors=validator.validateSet(structuredClone(s));if(errors?.length)throw Error(errors.join(';'));
  const species=dex.species.get(name),stats={};
  for(const [stat,base]of Object.entries(species.baseStats)){
   const v=Math.floor((2*base+s.ivs[stat])*s.level/100);
   const nature=dex.natures.get(s.nature);stats[stat]=stat==='hp'?v+s.level+10:Math.floor((v+5)*(nature.plus===stat?1.1:nature.minus===stat?.9:1));
  }
  team.push({id:r.id+'-'+species.num,speciesID:species.num,species:name,displayName:name,level:100,ability:s.ability,nature:s.nature,gender:'',shiny:false,form:null,ivs:s.ivs,stats,moves:s.moves.map(m=>dex.moves.get(m).id),item:Dex.toID(item),evidence:{format:c.format,set:c.label,source:c.source,manual:c.manual,itemAdapted:!c.items.includes(item)}});
 }
 catalog.encounters.push({id:r.id,index:r.round-1,nameKo:r.name,phase:r.phase,team});
}
require('./red-overrides.cjs').applyRedOverrides(catalog,dex);
fs.writeFileSync('BattleEngine/challenge-opponents.json',JSON.stringify(catalog,null,2)+'\n');
console.log(JSON.stringify({encounters:catalog.encounters.length,members:catalog.encounters.flatMap(e=>e.team).length,manualSlots:catalog.encounters.flatMap(e=>e.team).filter(p=>p.evidence.manual).length}));
