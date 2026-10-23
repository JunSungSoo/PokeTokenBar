const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../../Sources/PokeTokenBar/Resources/PokeRoguePlayer');
const load=name=>import('data:text/javascript;base64,'+fs.readFileSync(path.join(root,name)).toString('base64'));
test('all BW2 cries and distinct forms map like PokemonSpecies.getCryKey',async()=>{
 const {entryCry}=await load('entry-cries.js'),m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
 assert.equal(Object.keys(m.cries).length,655);
 for(let id=1;id<=649;id++)assert.equal(entryCry(id,'',1,m.cries).path,`audio/cry/${id}.m4a`);
 for(const [id,form]of [[492,'sky'],[641,'therian'],[642,'therian'],[645,'therian'],[646,'black'],[646,'white']])assert.equal(entryCry(id,form,.25,m.cries).key,`cry/${id}-${form}`);
 for(const [id,form]of [[386,'attack'],[479,'wash'],[487,'origin'],[647,'resolute'],[648,'pirouette'],[25,'unknown']])assert.equal(entryCry(id,form,.26,m.cries).key,`cry/${id}`);
 assert.equal(entryCry(25,'',.25,m.cries).rate,.85);assert.equal(entryCry(25,'',.251,m.cries).rate,1);
 assert.equal(entryCry(9999,'',1,m.cries),null);
});
test('entry cry fires once after growth, waits for audio and does not fire on recall',async()=>{
 const {EntryAnimation}=await load('entry-player.js');
 const shape=()=>{let proxy;proxy=new Proxy({x:0,y:0,shiny:false,base:{setTint(){},clearTint(){}},setVisible(v){this.visible=v;return this;}},{get(o,k){return k in o?o[k]:(()=>proxy);}});return proxy;};
 for(const own of [true,false])for(const recall of [false,true]){
  const incoming=shape();incoming.own=own;incoming.cryInfo={key:'cry/25',duration:2,rate:.85};
  const sounds=[],a=new EntryAnimation({incoming,outgoing:recall?shape():null,add:shape,playSound:(...v)=>sounds.push(v)});
  a.advance(a.delay+719);assert.equal(sounds.filter(s=>s[0]==='cry/25').length,0);
  a.advance(1);assert.equal(sounds.filter(s=>s[0]==='cry/25').length,1);
  assert.equal(sounds.find(s=>s[0]==='cry/25')[2].rate,.85);
  assert.equal(a.advance(1),false);assert.ok(a.duration>=a.cryStart+2000/.85);
  a.advance(10000);a.advance(10000);assert.equal(sounds.filter(s=>s[0]==='cry/25').length,1);
 }
});
