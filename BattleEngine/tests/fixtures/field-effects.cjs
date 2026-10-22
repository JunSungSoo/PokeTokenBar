const {OwnedBattle}=require('../../engine.cjs');
const base=[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']];
function team(prefix,moves){return base.map(([species,ability],i)=>({id:prefix+i,species,ability,moves,level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:300,spa:100,spd:300,spe:prefix==='a'?200:50}}));}
const e=new OwnedBattle('singles',[team('a',['raindance','trickroom']),team('b',['splash'])],[1,2,3,4]);
const frames=[];
for(const index of [1,2]){
 for(const p of [0,1]){const f=e.frame(p);e.choose(p,f.decisionID,[{kind:'move',index:p===0?index:1,target:0}]);}
 frames.push(e.frame(0));
}
for(const move of ['sunnyday','sandstorm','hail','gravity','magicroom','wonderroom','mudsport','watersport','reflect','lightscreen','safeguard','mist','tailwind','luckychant','spikes','stealthrock','toxicspikes']){
 const battle=new OwnedBattle('singles',[team('a',[move]),team('b',['splash'])],[1,2,3,4]);
 for(const p of [0,1]){const f=battle.frame(p);battle.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]);}
 frames.push(battle.frame(0));
}
for(const [species,ability]of [['Politoed','Drizzle'],['Ninetales','Drought'],['Tyranitar','Sand Stream'],['Abomasnow','Snow Warning']]){
 const own=team('a',['splash']);own[0].species=species;own[0].ability=ability;
 frames.push(new OwnedBattle('singles',[own,team('b',['splash'])],[1,2,3,4]).frame(0));
}
process.stdout.write(JSON.stringify(frames));
