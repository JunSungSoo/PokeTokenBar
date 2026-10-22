// Real simulator frames consumed by the mounted SwiftUI presentation regressions.
const {OwnedBattle}=require('../../engine.cjs');
function team(prefix,speed){return [['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']].map(([species,ability],i)=>({id:prefix+i,species,ability,moves:['dragonrage'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:40,atk:100,def:100,spa:100,spd:100,spe:speed}}));}
function run(mode){
 const own=team('a',200);own[0].species='Gyarados';own[0].ability='Moxie';
 const e=new OwnedBattle(mode,[own,team('b',50)],[1,2,3,4]);
 const both=()=>[e.frame(0),e.frame(1)];const initial=both();
 const turn=()=>{for(const p of [0,1]){const f=e.frame(p);if(!f.waiting)e.choose(p,f.decisionID,f.slots.map((s,i)=>({kind:'move',index:1,target:mode==='singles'?0:i+1})));}};
 turn();const resolved=both();
 const f=e.frame(1);let used=new Set();
 e.choose(1,f.decisionID,f.slots.map(s=>{if(s.canPass)return {kind:'pass'};const i=f.own.findIndex((p,j)=>!p.active&&!p.fainted&&!used.has(j));used.add(i);return {kind:'switch',index:i+1};}));
 const replaced=both();
 let guard=0;
 while(!e.frame(0).ended&&guard++<8){
  for(const p of [0,1]){const f=e.frame(p);if(f.waiting)continue;const used=new Set();e.choose(p,f.decisionID,f.slots.map((s,i)=>{if(s.canPass)return {kind:'pass'};if(s.mustSwitch){const j=f.own.findIndex((m,k)=>!m.active&&!m.fainted&&!used.has(k));used.add(j);return {kind:'switch',index:j+1};}return {kind:'move',index:1,target:mode==='singles'?0:f.foe.findIndex(m=>!m.fainted)+1};}));}
 }
 return {initial,resolved,replaced,ended:both()};
}
process.stdout.write(JSON.stringify({singles:run('singles'),doubles:run('doubles')}));
