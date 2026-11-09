// Public-frame counterfactuals inspect whether model choices respond to each input.
const fs=require('fs'),{OwnedBattle}=require('../../BattleEngine/engine.cjs'),{chooseCPU,candidates,features,observation,loadPolicy}=require('../../BattleEngine/challenge-policy.cjs');
const {encounters}=require('../../BattleEngine/challenge-opponents.json');
const allowed=new Set(require('../../BattleEngine/held-items.json').items.map(item=>item.id));
const human=structuredClone(encounters[0].team).map((p,i)=>({...p,id:'human-'+i,item:allowed.has(p.item)?p.item:''}));
const counts={speed:0,status:0,survivors:0},scoreChanges={speed:0,status:0,survivors:0},examples={},model=loadPolicy();let comparisons=0;
for(const encounter of encounters)for(let lead=0;lead<6;lead++){
 const team=encounter.team.slice();team.unshift(...team.splice(lead,1));
 const e=new OwnedBattle('singles',[human,team],[1,2,3,4],{profile:'challenge'}),f=e.frame(1);
 for(const fraction of [.1,.25,.5,.75,1])for(const foeFraction of [.1,.5,1]){
  const base=structuredClone(f),own=base.own.find(p=>p.active);own.hp=Math.max(1,Math.floor(own.maxHP*fraction));base.foe[0].hp=Math.max(1,Math.floor(base.foe[0].maxHP*foeFraction));
  for(const kind of Object.keys(counts)){
   comparisons++;
   const left=structuredClone(base),right=structuredClone(base),a=left.own.find(p=>p.active),b=right.own.find(p=>p.active);
   if(kind==='speed'){a.effectiveSpeed=20;b.effectiveSpeed=800;}
   if(kind==='status'){a.status='';b.status='brn';}
   if(kind==='survivors'){left.foeTeamStatus={selected:6,fainted:0};right.foeTeamStatus={selected:6,fainted:5};}
   const scores=frame=>candidates(frame).map(c=>features(e.battle.dex,observation(frame),c).reduce((sum,x,i)=>sum+x*model.weights[i],0));
   const ls=scores(left),rs=scores(right);
   if(ls.some((score,i)=>Math.abs((score-ls[0])-(rs[i]-rs[0]))>1e-9))scoreChanges[kind]++;
   const x=chooseCPU(e.battle.dex,left),y=chooseCPU(e.battle.dex,right);
   if(JSON.stringify(x)!==JSON.stringify(y)){counts[kind]++;examples[kind]??={trainer:encounter.id,species:own.name,hpFraction:fraction,before:x,after:y};}
  }
 }
}
const result={comparisons,counts,scoreChanges,examples,note:'Legal-candidate counterfactual sensitivity checks, not independent match wins.'};
fs.writeFileSync('build/challenge-training/ai-input-sensitivity.json',JSON.stringify(result,null,2)+'\n');console.log(JSON.stringify(result));
