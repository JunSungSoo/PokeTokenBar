'use strict';

// Fit an offline conditional logit model to the first two switches in public
// BW VGC logs. Input is a directory of Showdown replay JSON files.
const fs=require('node:fs');
const path=require('node:path');
const crypto=require('node:crypto');
const {FEATURE_NAMES,leadFeatures}=require('../../BattleEngine/challenge-doubles-lineup.cjs');
const [directory,output]=process.argv.slice(2);
if(!directory||!output)throw Error('Usage: node train-doubles-lineup.cjs <replay-dir> <model.json>');

function replayExamples(log) {
  const teams={p1:[],p2:[]}, leads={p1:[],p2:[]};
  let vgc=false,doubles=false,bringFour=false,started=false;
  for(const line of log.split('\n')){
    const [,event,slot,details]=line.split('|');
    if(event==='tier')vgc=/^\[Gen 5\] VGC 201[23]$/.test(slot);
    if(event==='gametype')doubles=slot==='doubles';
    if(event==='teampreview')bringFour=slot==='4';
    if(event==='poke'&&teams[slot])teams[slot].push(details.split(',')[0]);
    if(event==='start')started=true;
    if(started&&event==='switch'&&/^p[12][ab]:/.test(slot))leads[slot.slice(0,2)].push(details.split(',')[0]);
    if(event==='turn')break;
  }
  if(!vgc||!doubles||!bringFour)return [];
  const sides=['p1','p2'];
  if(sides.some(side=>new Set(teams[side]).size!==6||new Set(leads[side]).size!==2||
    !leads[side].every(name=>teams[side].includes(name))))return [];
  const group=sides.map(side=>teams[side].slice().sort().join(',')).sort().join('|');
  const holdout=crypto.createHash('sha256').update(group).digest()[0]<51;
  return sides.map(side=>{
    const team=teams[side],foes=teams[side==='p1'?'p2':'p1'].slice().sort();
    const features=[];let chosen=-1;
    for(let i=0;i<6;i++)for(let j=i+1;j<6;j++){
      if(leads[side].includes(team[i])&&leads[side].includes(team[j]))chosen=features.length;
      features.push(leadFeatures(team[i],team[j],foes));
    }
    return {features,chosen,holdout};
  });
}

const train=[],test=[],files=[];
for(const file of fs.readdirSync(directory).filter(name=>name.endsWith('.json')).sort()){
  const {id,log}=JSON.parse(fs.readFileSync(path.join(directory,file),'utf8'));
  let examples;
  try {examples=replayExamples(log);} catch(error){
    if(error.message.startsWith('Unrecognized generation V species:'))continue;
    throw error;
  }
  if(!examples.length)continue;
  files.push(id);
  for(const example of examples)(example.holdout?test:train).push(example);
}
if(train.length<100||test.length<30)throw Error('Insufficient valid training or holdout replays');

const weights=FEATURE_NAMES.map(()=>0);
const dot=(features,weights)=>features.reduce((sum,x,i)=>sum+x*weights[i],0);
function probabilities(scores){
  const maximum=Math.max(...scores),values=scores.map(s=>Math.exp(s-maximum));
  const total=values.reduce((a,b)=>a+b,0);
  return values.map(v=>v/total);
}
for(let epoch=0;epoch<750;epoch++){
  const gradient=weights.map(w=>-.015*w);
  for(const {features,chosen} of train){
    const p=probabilities(features.map(f=>dot(f,weights)));
    for(const [i,f] of features.entries()){
      for(const [j,x] of f.entries())gradient[j]+=((i===chosen?1:0)-p[i])*x/train.length;
    }
  }
  for(const [i,delta] of gradient.entries())weights[i]+=.5*delta;
}
function evaluate(examples){
  let loss=0,reciprocalRank=0,top3=0;
  for(const {features,chosen} of examples){
    const scores=features.map(f=>dot(f,weights));
    const rank=scores.filter(s=>s>scores[chosen]).length+1;
    top3+=Number(rank<=3);reciprocalRank+=1/rank;
    loss-=Math.log(probabilities(scores)[chosen]);
  }
  return {examples:examples.length,logLoss:loss/examples.length,meanReciprocalRank:reciprocalRank/examples.length,top3:top3/examples.length};
}
const artifact={version:1,source:'Public Pokémon Showdown Gen 5 VGC 2012/2013 replays',
  featureNames:FEATURE_NAMES,weights,training:evaluate(train),holdout:evaluate(test),replayIDs:files};
fs.writeFileSync(output,JSON.stringify(artifact,null,2)+'\n');
console.log({replays:files.length,train:artifact.training,holdout:artifact.holdout,uniformLogLoss:Math.log(15)});
