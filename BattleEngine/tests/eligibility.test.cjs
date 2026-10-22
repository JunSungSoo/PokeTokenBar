const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path');
const {Dex}=require('pokemon-showdown');
test('offline terminal-species catalog matches every Gen V species and ignores future evolutions',()=>{
 const dex=Dex.mod('gen5');
 const ids=new Set(JSON.parse(fs.readFileSync(path.join(__dirname,'../../Sources/PokeTokenBar/Resources/BattleText/final-species.json'))));
 const all=dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5);
 for(const s of all)assert.equal(ids.has(s.num),!all.filter(v=>v.num===s.num).some(v=>v.evos.some(name=>dex.species.get(name).gen<=5)),s.name);
 for(const id of [57,83,206,26,134,143])assert.ok(ids.has(id));
 for(const id of [25,133,233,82,299])assert.ok(!ids.has(id));
});
