// PokéRogue PokemonSpecies.getCryKey: BW2 forms with a distinct authored cry.
const distinctForms={492:['sky'],641:['therian'],642:['therian'],645:['therian'],646:['black','white']};
export function entryCry(speciesID,form,hpRatio,cries){
 const base=String(speciesID),suffix=distinctForms[speciesID]?.includes(form)?'-'+form:'';
 const id=base+suffix,path=cries?.[id];
 return path?{key:'cry/'+id,path,rate:hpRatio>.25?1:.85}:null;
}
