'use strict';
// Singles challenge guardrails over the learned scores: drop moves that cannot help, value data-power-0 attacks.
// Only policies with `cpuRules: RULES` use this — saved runs replay with their original scorer, so never change it in place.
const {Dex}=require('pokemon-showdown');
const RULES='meaningful-actions-v1';
const SETUP_CAP=2;
const protection=new Set(['protect','detect','endure']);
const healing=new Set(['recover','roost','softboiled','slackoff','milkdrink','moonlight','morningsun','synthesis','rest','wish','healorder']);
const residualStatus=new Set(['psn','tox','brn']);
const hazardLayers={stealthrock:1,spikes:3,toxicspikes:2};
const ownSideMoves=new Set(['reflect','lightscreen','safeguard','tailwind','mist','luckychant']);
const singleFoeTargets=new Set(['normal','adjacentFoe','any','randomNormal']);

function effectIDs(list){return new Set((list||[]).map(effect=>String(effect.id||effect).toLowerCase()));}
function sideLayers(entries,id){const found=(entries||[]).find(entry=>entry.id===id);return found?(found.layers||1):0;}

function statusBlocked(dex,move,foe){
 // Side, field and self moves are never stopped by the foe's status or Substitute.
 if(!singleFoeTargets.has(move.target))return false;
 const types=foe.types||dex.species.get(foe.name).types,effects=effectIDs(foe.effects);
 if(effects.has('substitute')&&!move.flags?.bypasssub)return true;
 if(move.status){
  if(foe.status)return true;
  if(['psn','tox'].includes(move.status)&&types.some(type=>['Poison','Steel'].includes(type)))return true;
  if(move.status==='brn'&&types.includes('Fire'))return true;
  if(move.id==='thunderwave'&&!dex.getImmunity('Electric',types))return true;
  if(move.status==='slp'&&effects.has('yawn'))return true;
 }
 if(move.id==='leechseed')return types.includes('Grass')||effects.has('leechseed');
 if(move.volatileStatus==='confusion')return effects.has('confusion');
 if(move.id==='yawn')return !!foe.status||effects.has('yawn');
 return false;
}

function raisedStats(move){
 const boosts=move.target==='self'?{...(move.boosts||{}),...(move.self?.boosts||{})}:move.self?.boosts||{};
 return Object.entries(boosts).filter(([,amount])=>amount>0).map(([stat])=>stat);
}

/** Why this move cannot help now, or null. `context` holds own-side facts the frame omits. */
function pointlessReason(dex,move,own,foe,field,context){
 const ownEffects=effectIDs(own.effects),hp=own.hp/own.maxHP;
 if(protection.has(move.id)){
  if(protection.has(context.lastMove))return 'consecutive protection';
  const purpose=context.wishPending||residualStatus.has(foe.status)||effectIDs(foe.effects).has('leechseed');
  return purpose?null:'protection without a reason to stall';
 }
 if(healing.has(move.id)){
  if(hp>=1)return 'healing at full HP';
  if(move.id==='wish'&&context.wishPending)return 'wish already pending';
 }
 if(move.id==='substitute'&&(ownEffects.has('substitute')||hp<=0.25))return 'substitute cannot be made';
 if(move.category==='Status'&&move.target!=='self'&&statusBlocked(dex,move,foe))return 'status has no effect';
 if(move.weather&&Dex.toID(field.weather||'')===Dex.toID(move.weather))return 'weather already active';
 if(hazardLayers[move.id]&&sideLayers(field.foeSide,move.id)>=hazardLayers[move.id])return 'hazard at maximum';
 if(ownSideMoves.has(move.id)&&sideLayers(field.ownSide,move.id)>0)return 'side condition already active';
 if(move.category==='Status'){
  const stats=raisedStats(move);
  if(stats.length&&stats.every(stat=>(own.boosts?.[stat]||0)>=SETUP_CAP))return 'stat boosts already high';
 }
 return null;
}

/** Moves that cannot help are removed; switches are kept, and if every move is pointless the original list stands. */
function meaningfulActions(dex,frame,actions,context={}){
 const own=frame.own.find(mon=>mon.active),visibleFoe=frame.foe?.[0];
 if(!own||!visibleFoe)return actions;
 // The frame omits the foe's volatile effects; runCPU passes the publicly visible ones.
 const foe={...visibleFoe,effects:context.foeEffects||[]};
 const field=frame.field||{};
 const kept=actions.filter(action=>action.kind!=='move'||!pointlessReason(dex,dex.moves.get(action.move),own,foe,field,context));
 return kept.some(action=>action.kind==='move')?kept:actions;
}

/** Base power that damaging moves with data power 0 actually reach, from public information. */
function effectivePower(dex,move,observation,candidate,estimatedSpeed){
 if(move.category==='Status'||move.basePower)return move.basePower||0;
 const level=observation.own.level||100,foe=dex.species.get(observation.foe.species);
 switch(move.id){
 case 'seismictoss': case 'nightshade': return Math.min(120,Math.round(1.3*level));
 case 'return': case 'frustration': return 102;
 case 'grassknot': case 'lowkick': {
  const weight=foe.weightkg||0;
  return weight<10?20:weight<25?40:weight<50?60:weight<100?80:weight<200?100:120;
 }
 case 'gyroball': {
  const own=estimatedSpeed(dex,observation.own),target=estimatedSpeed(dex,observation.foe);
  return Math.min(150,Math.floor(25*target/Math.max(1,own))+1);
 }
 case 'reversal': case 'flail': {
  const ratio=Math.floor(48*(observation.own.hp||0));
  return ratio<=1?200:ratio<=4?150:ratio<=9?100:ratio<=16?80:ratio<=32?40:20;
 }
 default: return candidate.power>0?candidate.power:60;
 }
}

/** Fixed-damage moves ignore type effectiveness except immunity. */
function ignoresEffectiveness(move){return ['seismictoss','nightshade'].includes(move.id);}

module.exports={RULES,SETUP_CAP,meaningfulActions,pointlessReason,effectivePower,ignoresEffectiveness};
