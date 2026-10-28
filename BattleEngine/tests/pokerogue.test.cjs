const{test}=require('node:test');const assert=require('node:assert/strict');const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const root=path.join(__dirname,'../../Sources/PokeTokenBar/Resources/PokeRogue');
const catalog=JSON.parse(fs.readFileSync(path.join(root,'catalog.json')));
test('all current canonical moves have effect-only offline timelines and resource hashes',()=>{
 const base=JSON.parse(fs.readFileSync(path.join(root,'../BattleEffects/catalog.json')));
 assert.equal(new Set(Object.values(catalog.aliases)).size,559);
 const original=JSON.parse(fs.readFileSync(path.join(root,'../PokeRoguePlayer/manifest.json')));
 for(const id of new Set(Object.values(base.aliases)))assert.ok(catalog.entries[id]||original.entries[id],id);
 const hashes=JSON.parse(fs.readFileSync(path.join(root,'source-sha256.json')));
 for(const[file,hash]of Object.entries(hashes.bundled))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,file))).digest('hex'),hash,file);
 for(const[id,entry]of Object.entries(catalog.entries)){
  assert.ok(entry.duration>0&&entry.duration<=3.6,id);
  const variants=JSON.parse(fs.readFileSync(path.join(root,entry.file)));
  for(const animation of variants){
   let cells=0;
   if(animation.graphic){const png=path.join(root,'images/battle_anims',animation.graphic+'.png');if(fs.existsSync(png)){const b=fs.readFileSync(png);cells=Math.floor(b.readUInt32BE(16)/96)*Math.floor(b.readUInt32BE(20)/96);}}
   for(const frame of animation.frames)for(const op of frame){
    assert.equal(op.target,2,'Pokémon transforms must never enter the production import');
    assert.ok(op.graphicFrame>=0&&op.graphicFrame<cells,id);
    for(const value of [op.x,op.y,op.zoomX??100,op.zoomY??100,op.opacity??255])assert.ok(Number.isFinite(value),id);
   }
   for(const events of Object.values(animation.frameTimedEvents))for(const event of events)assert.notEqual(event.eventType,'AnimTimedSoundEvent');
  }
  if(entry.classification==='motion'||entry.classification==='empty'||entry.discarded)assert.equal(entry.supplement,true,id);
 }
 for(const id of ['rest','naturepower','secretpower'])assert.equal(catalog.entries[id].classification,'empty');
 assert.ok(catalog.entries['solarbeam:charge']);
});
const {OwnedBattle}=require('../engine.cjs');
function team(prefix,count,moves){return Array.from({length:count},(_,i)=>({id:prefix+i,species:['Pikachu','Raichu','Pichu','Electabuzz','Mareep','Flaaffy'][i],level:37,ability:'Static',nature:'Hardy',gender:'M',ivs:{hp:17,atk:17,def:17,spa:17,spd:17,spe:17},stats:{hp:143,atk:91,def:87,spa:96,spd:89,spe:107},moves:i===0?moves:['protect','splash']}));}
function lead(e){if(!e.frame(0).preview)return;for(let p=0;p<2;p++)if(e.frame(p).preview)e.choose(p,e.frame(p).decisionID,null,e.frame(p).own.map((_,i)=>i+1));}
test('real singles and doubles resolutions map to imported effects without changing saved stats',()=>{
 for(const mode of ['singles','doubles']){
  const count=6,own=team('a',count,[mode==='singles'?'psychic':'surf','protect']),foe=team('b',count,['protect','splash']);
  const e=new OwnedBattle(mode,[own,foe],[1,2,3,4]);lead(e);
  const actions=mode==='singles'?[{kind:'move',index:1,target:0}]:[{kind:'move',index:1,target:0},{kind:'move',index:2,target:0}];
  e.choose(0,e.frame(0).decisionID,actions);
  e.choose(1,e.frame(1).decisionID,mode==='singles'?[{kind:'move',index:2,target:0}]:[{kind:'move',index:1,target:0},{kind:'move',index:2,target:0}]);
  const frame=e.frame(0);
  for(const effect of frame.effects)assert.ok(catalog.entries[effect.moveID+(effect.phase==='charge'?':charge':'')],effect.moveID);
  assert.ok(frame.own.every(p=>JSON.stringify(p.stats)===JSON.stringify(own[0].stats)));
  if(mode==='singles')assert.ok(frame.foe[0].hp<100);
  else{const surf=frame.effects.find(v=>v.moveID==='surf');assert.equal(surf.targets.length,2);assert.ok(surf.targets.some(t=>t.position.own&&t.hit));assert.ok(!surf.targets.some(t=>!t.position.own&&t.position.slot===0),'protected foe is excluded from the resolved spread list');assert.ok(surf.targets.some(t=>!t.position.own&&t.position.slot===1&&t.hit));}
 }
});
test('Volt Switch effect belongs to the outgoing Pokemon before forced replacement',()=>{
 const own=team('a',6,['voltswitch','protect']),foe=team('b',6,['splash']);
 const e=new OwnedBattle('singles',[own,foe],[1,2,3,4]);lead(e);
 for(let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 const frame=e.frame(0);assert.ok(frame.slots[0].mustSwitch);assert.equal(frame.own.find(p=>p.active).id,'a0');
 assert.ok(catalog.entries[frame.effects.find(v=>v.moveID==='voltswitch').moveID]);
 e.choose(0,frame.decisionID,[{kind:'switch',index:2,target:0}]);
 assert.equal(e.frame(0).own.find(p=>p.active).id,'a1');
});
