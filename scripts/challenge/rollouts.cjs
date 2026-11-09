// Offline engine adaptation/evaluation. It never contacts the public battle ladder.
const fs=require('fs'),{OwnedBattle}=require('../../BattleEngine/engine.cjs');
const {encounters}=require('../../BattleEngine/challenge-opponents.json'),allowed=new Set(require('../../BattleEngine/held-items.json').items.map(i=>i.id));
const args=process.argv.slice(2),arg=(k,d)=>{const i=args.indexOf(k);return i<0?d:args[i+1];};
const model=JSON.parse(fs.readFileSync(arg('--weights','BattleEngine/challenge-policy.json'))),episodes=Number(arg('--episodes','40')),pairShift=Number(arg('--pair-shift','13')),offset=Number(arg('--offset','0')),stochastic=args.includes('--stochastic'),output=arg('--output','build/challenge-training/rollouts.json');
const {features,observation,candidates,chooseCPU}=require('../../BattleEngine/'+(model.featureVersion==='bw-public-action-v1'?'challenge-policy-v1.cjs':'challenge-policy.cjs'));
let randomState=123456+offset;function random(){randomState=(Math.imul(randomState,1664525)+1013904223)>>>0;return randomState/4294967296;}
const trajectories=[];let wins=0,losses=0,draws=0,truncated=0,decisions=0;
for(let episode=0;episode<episodes;episode++){
 const index=episode+offset,enemy=structuredClone(encounters[index%27].team),opponent=structuredClone(encounters[(index*7+pairShift)%27].team).map((p,i)=>({...p,id:'human-'+i,item:allowed.has(p.item)?p.item:''}));
 const e=new OwnedBattle('singles',[opponent,enemy],[index%65536,19,41,73],{profile:'challenge',automaticOpponent:true}),steps=[];
 let iterations=0;
 while(!e.battle.ended&&iterations++<2400){
  let accepted=0;
  for(const side of [1,0]){
   const f=e.frame(side);if(f.waiting||f.ended)continue;
   const choices=candidates(f);if(!choices.length)throw Error('No rollout choices');
   const o=observation(f),x=choices.map(c=>features(e.battle.dex,o,c));
   let selected=0,runtimeAction;
   if(side===1){
    const scores=x.map(v=>v.reduce((s,a,i)=>s+a*model.weights[i],0));
    if(stochastic){const max=Math.max(...scores),p=scores.map(s=>Math.exp(s-max)),total=p.reduce((a,b)=>a+b,0);let pick=random()*total;for(let i=0;i<p.length;i++){pick-=p[i];if(pick<=0){selected=i;break;}}}
    else {runtimeAction=chooseCPU(e.battle.dex,f,model);selected=choices.findIndex(c=>c.kind===runtimeAction.kind&&c.index===runtimeAction.index);if(selected<0)throw Error('Policy returned an unavailable action');}
    if(stochastic&&choices.length>1)steps.push({x,y:selected});
   }else{
    const scores=x.map(v=>v[16]+.05*v[29]-.1*v[1]);selected=scores.indexOf(Math.max(...scores));
   }
   const c=choices[selected];e.choose(side,f.decisionID,[runtimeAction??{kind:c.kind,index:c.index,target:0,...(c.kind==='move'&&f.slots[0]?.canMegaEvo?{mega:true}:{})}]);accepted++;decisions++;
  }
  if(!accepted)throw Error('Rollout stalled');
 }
 const winner=e.frame(0).winner;let reward=0;
 if(!e.battle.ended){truncated++;reward=-.5;}else if(winner===1){wins++;reward=1;}else if(winner===0){losses++;reward=-1;}else{draws++;}
 trajectories.push({encounter:encounters[index%27].id,seed:[index%65536,19,41,73],reward,steps});
}
const metrics={episodes,wins,losses,draws,truncated,decisions,winRate:wins/episodes,opponent:'maximum public type-adjusted base power baseline',offset,pairShift,stochastic,note:'Fixed synthetic matchup evaluation, not human ladder strength.'};
fs.writeFileSync(output,JSON.stringify({metrics,trajectories}));console.log(JSON.stringify(metrics));
