// Real BW2 activation logs/scenes; deterministic statuses avoid probabilistic move misses.
const {OwnedBattle}=require('../../engine.cjs');
const frames=[];
function team(prefix){return ['Smeargle','Blissey','Raichu','Vaporeon','Slowbro','Scizor'].map((species,i)=>({id:prefix+i,species,ability:['Technician','Serene Grace','Static','Water Absorb','Oblivious','Technician'][i],moves:['splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:1000,atk:50,def:300,spa:50,spd:300,spe:100}}));}
for(const mode of ['singles','doubles'])for(const status of ['slp','par','frz','psn','tox','brn','confusion','attract']){
 const e=new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4]);
 const a=e.battle.sides[0].active,b=e.battle.sides[1].active;
 // All conditions are reachable in BW2; invoke their actual simulator handlers.
 for(const [side,mons] of [a,b].entries()) for(const p of mons){
  if(status==='confusion')p.addVolatile('confusion',side===0?b[0]:a[0]);
  else if(status==='attract') {p.gender=side===0?'M':'F';}
  else p.setStatus(status);
 }
 if(status==='attract')for(const [side,mons]of [a,b].entries())for(const p of mons)p.addVolatile('attract',side===0?b[0]:a[0]);
 for(let turn=0;turn<4;turn++){
  for(const player of [0,1]){const f=e.frame(player);e.choose(player,f.decisionID,Array.from({length:mode==='doubles'?2:1},()=>({kind:'move',index:1,target:0})));}
  for(const player of [0,1])frames.push({mode,status,player,frame:e.frame(player)});
 }
}
process.stdout.write(JSON.stringify(frames));
