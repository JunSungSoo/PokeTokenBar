#!/usr/bin/env node
// Inventory reflects the pinned gen5 runtime, not a claim of exhaustive interaction testing.
const fs=require('node:fs'),path=require('node:path');
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const dex=Dex.mod('gen5');
const finals=new Set(require('../Sources/PokeTokenBar/Resources/BattleText/final-species.json'));
const species=dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5);
const abilities=dex.abilities.all().filter(a=>a.exists&&a.num>0&&a.gen<=5).sort((a,b)=>a.num-b.num);
const rows=abilities.map(a=>{
 const witnesses=species.filter(s=>Object.values(s.abilities).includes(a.name));
 const final=witnesses.find(s=>s.num!==493&&finals.has(s.num));
 const hooks=Object.entries(a).filter(([k,v])=>k.startsWith('on')&&typeof v==='function').map(([k])=>k).sort();
 const scope=a.id==='multitype'?'excluded: item-dependent-type rule':!final?'excluded: final-evolution-only selection':!hooks.length?'available: no in-battle effect in BW2':'available: gen5 engine event hooks';
 return [a.id,a.name,witnesses[0]?.name||'',final?.name||'',scope,hooks.join(' ')];
});
const out=path.join(__dirname,'../docs/reference/battle-ability-support.csv');
fs.writeFileSync(out,[['id','ability','engine_witness','selectable_final_witness','scope','gen5_event_hooks'],...rows].map(row=>row.map(x=>JSON.stringify(x)).join(',')).join('\n')+'\n');
console.log(`${abilities.length} gen5 abilities inventoried; ${rows.filter(r=>r[3]).length} selectable with current final-species/item rules: ${out}`);
