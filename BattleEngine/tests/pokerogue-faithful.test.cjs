const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto'),{execFileSync}=require('node:child_process');
const root=path.resolve(__dirname,'../../Tests/PokeTokenBarTests/Fixtures/PokeRogueFaithful');
test('original-player host modules parse before opening a WebKit comparison window',()=>{
 for(const name of ['host.js','original-player.js'])execFileSync(process.execPath,['--input-type=module','--check'],{input:fs.readFileSync(path.join(root,name)),stdio:['pipe','pipe','pipe']});
});
test('four complete PokéRogue timelines and pinned runtime retain their source hashes',()=>{
 const m=JSON.parse(fs.readFileSync(path.join(root,'manifest.json')));
 assert.deepEqual(m.moves,['thunderbolt','protect','quick-attack','volt-switch']);
 for(const [name,hash]of Object.entries(m.originalSHA256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,name))).digest('hex'),hash,name);
 const source=fs.readFileSync(path.join(root,'original/battle-anims.ts'),'utf8'),adapter=fs.readFileSync(path.join(root,'adapter.ts'),'utf8');
 for(const [start,end]of [['export class AnimConfig','export const moveAnims'],['interface GraphicFrameData','export class CommonBattleAnim']])assert.ok(adapter.includes(source.slice(source.indexOf(start),source.indexOf(end))));
});
const production=path.resolve(__dirname,'../../Sources/PokeTokenBar/Resources/PokeRoguePlayer');
test('every production move retains the complete original timeline and all offline dependencies',()=>{
 const m=JSON.parse(fs.readFileSync(path.join(production,'manifest.json')));
 assert.equal(Object.keys(m.entries).length,573);
 assert.equal(Object.keys(m.entries).filter(k=>!k.endsWith(':charge')).length,559);
 for(const [name,hash]of Object.entries(m.sha256))assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(production,name))).digest('hex'),hash,name);
 let user=false,target=false;
 for(const [key,entry]of [...Object.entries(m.entries),...Object.entries(m.fieldEntries||{})]){
  const raw=JSON.parse(fs.readFileSync(path.join(production,entry.file))),variants=Array.isArray(raw)?raw:[raw];
  assert.deepEqual(variants.map(v=>v.frames.length),entry.frames,key);
  for(const v of variants)for(const frame of v.frames)for(const command of frame){if(command.target===0)user=true;if(command.target===1)target=true;}
  for(const image of [...entry.graphics,...entry.backgrounds])assert.ok(fs.existsSync(path.join(production,'images/battle_anims',image+'.png')),key+': '+image);
  for(const sound of entry.sounds)assert.ok(fs.existsSync(path.join(production,'audio/battle_anims',sound)),key+': '+sound);
 }
 assert.ok(user&&target,'Full original USER/TARGET commands must survive packaging');
 for(const name of ['battle-player.js','player-core.js','original-player.js'])execFileSync(process.execPath,['--input-type=module','--check'],{input:fs.readFileSync(path.join(production,name))});
});
