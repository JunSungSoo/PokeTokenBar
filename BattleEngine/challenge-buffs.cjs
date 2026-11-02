'use strict';
const clamp=n=>Math.max(-6,Math.min(6,n));
function validateBoosts(boosts,profile){
 if(boosts==null)return {};
 if(profile!=='challenge'||typeof boosts!=='object'||Array.isArray(boosts))throw Error('Challenge-only team boosts');
 for(const [key,value] of Object.entries(boosts))if(!['atk','spa','spe','def','spd'].includes(key)||!Number.isInteger(value)||value<0||value>6)throw Error('Invalid challenge team boost');
 return {...boosts};
}
function combinedBoosts(p){
 if(p.ptbRewardContext)return {...p.boosts};
 const boosts={...p.boosts};
 for(const [key,value] of Object.entries(p.set.ptbRewardBoosts||{}))boosts[key]=clamp((boosts[key]||0)+value);
 return boosts;
}
// Stat/damage evaluation is synchronous. Present combined stages only during these
// calculations; all normal boost changes, Haze, Baton Pass and Transform retain their
// own engine state. This also lets critical hits and Unaware inspect the total stages.
function withBoosts(pokemon,calculate){
 const changed=[];
 for(const p of pokemon){
  if(p.ptbRewardContext||!Object.keys(p.set.ptbRewardBoosts||{}).length)continue;
  const boosts=p.boosts;p.boosts=combinedBoosts(p);p.ptbRewardContext=true;changed.push([p,boosts]);
 }
 try{return calculate();}finally{for(const [p,boosts]of changed){p.boosts=boosts;p.ptbRewardContext=false;}}
}
function install(battle){
 const damage=battle.actions.getDamage;
 battle.actions.getDamage=function(...args){return withBoosts(this.battle.sides.flatMap(s=>s?.pokemon||[]),()=>damage.apply(this,args));};
}
module.exports={validateBoosts,combinedBoosts,withBoosts,install};
