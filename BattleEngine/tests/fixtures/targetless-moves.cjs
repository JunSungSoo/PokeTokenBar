'use strict';
const assert=require('node:assert/strict'),{OwnedBattle}=require('../../engine.cjs');
function mon(species,ability,moves,spe){return {species,ability,moves,level:100,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:80,def:300,spa:80,spd:300,spe}};}
function team(prefix,lead){return [lead,...[['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']].map(([s,a])=>mon(s,a,['splash'],50))].map((p,i)=>({...p,id:prefix+i}));}
function resolve(mode,move,{ghost=false,recover=false,lastFoe=false,knockout=false}={}){
 const own=team('a',mon(ghost?'Gengar':'Smeargle',ghost?'Levitate':'Own Tempo',[recover?'recover':'thunderbolt'],100));
 const foe=team('b',mon('Electrode','Static',[move],200));
 if(lastFoe)foe[1]={...mon('Golem','Sturdy',[move],150),id:'b1'};
 const e=new OwnedBattle(mode,[own,foe],[1,2,3,4]);
 if(recover)e.battle.sides[0].active[0].hp=100;
 if(knockout)e.battle.sides[0].active[0].hp=1;
 const before=e.frame(0),ppBefore=e.battle.sides[0].pokemon[0].moveSlots[0].pp;
 for(const player of [0,1]){
  const f=e.frame(player);
  e.choose(player,f.decisionID,f.slots.map((slot,i)=>slot.canPass?{kind:'pass'}:{kind:'move',index:1,target:player===0&&i===0&&mode==='doubles'&&!recover?1:0}));
 }
 return {before,frames:[e.frame(0),e.frame(1)],pp:{before:ppBefore,after:e.battle.sides[0].pokemon[0].moveSlots[0].pp}};
}
function fixtures(){
 const result={};
 for(const move of ['explosion','selfdestruct']){
  for(const ghost of [false,true])result['single-'+move+(ghost?'-immune':'')]=resolve('singles',move,{ghost});
  result['double-'+move+'-last']=resolve('doubles',move,{lastFoe:true});
  result['double-'+move+'-retarget']=resolve('doubles',move);
  result['single-'+move+'-ko']=resolve('singles',move,{knockout:true});
  result['single-'+move+'-recover']=resolve('singles',move,{recover:true});
 }
 return result;
}
module.exports={fixtures};
if(require.main===module)process.stdout.write(JSON.stringify(fixtures()));
