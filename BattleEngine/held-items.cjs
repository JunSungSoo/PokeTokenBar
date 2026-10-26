'use strict';
const {Dex}=require('pokemon-showdown');
const catalog=require('./held-items.json');
const allowed=new Map(catalog.items.map(i=>[i.id,i]));
// Isolated dex: normal BW2 species, moves, items, abilities and type interactions stay intact.
function battleDex(){
 const id='ptbmegabw2';if(Dex.dexes[id])return Dex.dexes[id];
 const parent=Dex.mod('gen5'),d=new Dex.ModdedDex(id);
 d.gen=5;d.parentMod='gen5';
 d.dataCache={...parent.data,Pokedex:{...parent.data.Pokedex},Items:{...parent.data.Items},Abilities:{...parent.data.Abilities},Scripts:{...parent.data.Scripts}};
 for(const item of catalog.items.filter(i=>i.mega)){
  const donor=Dex.mod(item.generation===6?'gen6':'gen9'),stone=donor.items.get(item.id),species=donor.species.get(item.mega.species);
  d.dataCache.Items[item.id]=donor.data.Items[item.id];
  d.dataCache.Pokedex[species.id]=donor.data.Pokedex[species.id];
  for(const ability of Object.values(species.abilities)){
   const a=donor.abilities.get(ability);
   if(!parent.abilities.get(ability).exists||a.gen>5)d.dataCache.Abilities[a.id]=donor.data.Abilities[a.id];
  }
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
module.exports={catalog,allowed,battleDex,heldItem};
