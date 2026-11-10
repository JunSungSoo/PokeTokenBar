'use strict';
// State carried between encounters, never the presentation's rounded foe HP.
function normalizeMove(id){return id.startsWith('hiddenpower')?'hiddenpower':id;}
function validateResources(resources,sets,dex){
 if(resources==null)return null;
 if(!Array.isArray(resources)||resources.length!==sets.length)throw Error('Challenge resources must match the battle team');
 const byID=new Map(resources.map(r=>[r.id,r]));
 if(byID.size!==sets.length)throw Error('Duplicate resource member');
 for(const set of sets){
  const r=byID.get(set.ptbID);
  if(!r||!Number.isInteger(r.hp)||r.hp<0||r.hp>set.ptbStats.hp)throw Error('Invalid challenge HP');
  if(!['','brn','par','psn','tox','slp','frz'].includes(r.status))throw Error('Invalid challenge status');
  if(r.status==='slp'&&(!Number.isInteger(r.sleepStart)||r.sleepStart<1||r.sleepStart>4))throw Error('Invalid sleep state');
  if(r.status==='slp'&&r.sleepRemaining!=null&&(!Number.isInteger(r.sleepRemaining)||r.sleepRemaining<0||r.sleepRemaining>r.sleepStart))throw Error('Invalid sleep remainder');
  if(!Array.isArray(r.moves)||r.moves.length!==set.moves.length)throw Error('Invalid challenge moves');
  r.moves.forEach((m,i)=>{
   const move=dex.moves.get(set.moves[i]);
   if(m.id!==normalizeMove(move.id)||m.maxPP!==move.pp||!Number.isInteger(m.pp)||m.pp<0||m.pp>m.maxPP)throw Error('Invalid challenge PP');
  });
  // Carried items may have been consumed, removed or obtained through Trick.
  if(typeof r.item!=='string'||(r.item&&(!dex.items.get(r.item).exists || dex.items.get(r.item).gen>5&&!require('./held-items.json').items.some(i=>i.id===r.item))))throw Error('Invalid carried item');
 }
 if(!resources.some(r=>r.hp>0))throw Error('Challenge team has no surviving Pokemon');
 return byID;
}
function initializeResources(battle,states){
 for(let i=0;i<2;i++){
  const side=battle.sides[i],byID=states[i];
  for(const p of side.pokemon){
   const r=byID?.get(p.set.ptbID);
   p.moveSlots.forEach((m,j)=>{m.maxpp=battle.dex.moves.get(m.id).pp;m.pp=r?r.moves[j].pp:m.maxpp;});
   p.baseMoveSlots=p.moveSlots.slice();
   if(!r)continue;
   p.hp=r.hp;p.fainted=r.hp===0;p.item=r.item;p.itemState={id:r.item,target:p};p.canMegaEvo=battle.actions.canMegaEvo(p);
   p.set.ptbMegaStats=require('./held-items.json').items.find(i=>i.id===r.item)?.mega?.stats;
   p.status=r.hp>0?r.status:'';p.statusState={id:p.status,target:p};
   if(p.status==='slp'){p.statusState.startTime=r.sleepStart;p.statusState.time=r.sleepRemaining??r.sleepStart;}
   if(p.status==='tox')p.statusState.stage=0;
  }
  // Skip dead leads without changing the identities/order persisted by the host.
  side.pokemon.sort((a,b)=>Number(a.fainted)-Number(b.fainted));
  side.pokemon.forEach((p,j)=>p.position=j);
  side.pokemonLeft=side.pokemon.filter(p=>!p.fainted).length;
 }
}
function resourcesFor(side){
 return side.pokemon.slice().sort((a,b)=>a.set.ptbOrder-b.set.ptbOrder).map(p=>({id:p.set.ptbID,hp:p.hp,status:p.hp>0?p.status:'',item:p.item,
  ...(p.status==='slp'?{sleepStart:p.statusState.startTime,sleepRemaining:p.statusState.time}:{}),
  moves:p.baseMoveSlots.map(m=>({id:m.id,pp:m.pp,maxPP:m.maxpp}))}));
}
module.exports={validateResources,initializeResources,resourcesFor};
