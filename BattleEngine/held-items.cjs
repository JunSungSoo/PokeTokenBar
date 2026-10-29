'use strict';
const {Dex}=require('pokemon-showdown');
const catalog=require('./held-items.json');
const allowed=new Map(catalog.items.map(i=>[i.id,i]));
// Only the requested generation-VI Fairy moves extend the BW2 move boundary.
const fairyDex=Dex.mod('gen6');
const allowedFairyMoves=new Set(fairyDex.moves.all().filter(m=>m.gen===6&&m.type==='Fairy').map(m=>m.id));
// Preserve BW2 species and existing type matchups; overlay only Fairy interactions.
function battleDex(){
 const id='ptbmegabw2';if(Dex.dexes[id])return Dex.dexes[id];
 const parent=Dex.mod('gen5'),d=new Dex.ModdedDex(id);
 d.gen=5;d.parentMod='gen5';
 d.dataCache={...parent.data,Pokedex:{...parent.data.Pokedex},Items:{...parent.data.Items},Abilities:{...parent.data.Abilities},Scripts:{...parent.data.Scripts},Moves:{...parent.data.Moves},TypeChart:{...parent.data.TypeChart}};
 for(const id of allowedFairyMoves)d.dataCache.Moves[id]=fairyDex.data.Moves[id];
 for(const [id,type]of Object.entries(parent.data.TypeChart)){
  const donor=fairyDex.data.TypeChart[id];
  if(donor)d.dataCache.TypeChart[id]={...type,damageTaken:{...type.damageTaken,Fairy:donor.damageTaken.Fairy??0}};
 }
 d.dataCache.TypeChart.fairy={...fairyDex.data.TypeChart.fairy};
 for(const item of catalog.items.filter(i=>i.mega)){
  const donor=Dex.mod(item.generation===6?'gen6':'gen9'),stone=donor.items.get(item.id),species=donor.species.get(item.mega.species);
  d.dataCache.Items[item.id]=donor.data.Items[item.id];
  d.dataCache.Pokedex[species.id]=donor.data.Pokedex[species.id];
  for(const ability of Object.values(species.abilities)){
   const a=donor.abilities.get(ability);
   if(!parent.abilities.get(ability).exists||a.gen>5)d.dataCache.Abilities[a.id]=donor.data.Abilities[a.id];
  }
 }
 // Preserve Showdown's arithmetic and annotate only the stage lines it actually emits.
 // AfterEachBoost excludes capped changes and changes blocked by Mist/TryBoost.
 for(const id of ['contrary','simple']){
  const ability=parent.abilities.get(id),change=ability.onChangeBoost;
  const changed=new WeakMap();
  d.dataCache.Abilities[id]={...parent.data.Abilities[id],
   onChangeBoost(boost,target,source,effect){
    const before={...boost},result=change.call(this,boost,target,source,effect);
    changed.set(target,new Set(Object.keys(boost).filter(stat=>boost[stat]!==before[stat])));
    return result;
   },
   onAfterEachBoost(boost,target){
    const index=this.log.length-1,line=this.log[index],parts=line?.split('|');
    if(parts&&['-boost','-unboost'].includes(parts[1])&&parts[2]===target.toString()
       &&Object.keys(boost).includes(parts[3])&&changed.get(target)?.has(parts[3])&&Number(parts[4])>0){
     this.log[index]=line+'|[from] ability: '+ability.name;
    }
   }
  };
 }
 Dex.dexes[id]=d;return d;
}
function heldItem(raw,species){
 if(raw==null||raw==='')return '';
 if(typeof raw!=='string')throw Error('Invalid held item');
 const id=Dex.toID(raw),item=allowed.get(id);
 if(!item)throw Error('Unsupported held item');
 if(item.mega && (item.mega.baseID!==species.num || species.forme))throw Error('Mega Stone does not match this Pokémon');
 return id;
}
module.exports={catalog,allowed,battleDex,heldItem,allowedFairyMoves};
