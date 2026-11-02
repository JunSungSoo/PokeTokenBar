// Explicit user-authored exception to the BW usage sets; not a claim of BW usage evidence.
exports.applyRedOverrides=function(catalog,dex){
 const red=catalog.encounters.find(e=>e.id==='red');if(!red)throw Error('Missing Red encounter');
 for(const p of red.team){
  p.ivs=Object.fromEntries(['hp','atk','def','spa','spd','spe'].map(k=>[k,31]));
  const species=dex.species.get(p.species),nature=dex.natures.get(p.nature);
  p.stats=Object.fromEntries(Object.entries(species.baseStats).map(([k,base])=>{
   const v=Math.floor((2*base+31)*p.level/100);
   return [k,k==='hp'?v+p.level+10:Math.floor((v+5)*(nature.plus===k?1.1:nature.minus===k?.9:1))];
  }));
  if(p.speciesID===6){
   p.item='charizarditey';p.moves=['weatherball','solarbeam','fireblast','airslash'];
   p.evidence={...p.evidence,manual:true,set:'User-requested Mega Charizard Y sun set',source:'User instruction 2026-10-30',itemAdapted:true,exception:'Charizardite Y and post-BW Weather Ball compatibility'};
  }
 }
 catalog.version='challenge-bw-v2-red-sun-max-ivs';return catalog;
};
