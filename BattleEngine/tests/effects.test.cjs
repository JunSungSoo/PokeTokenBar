const {test}=require('node:test');
const assert=require('node:assert/strict');
const fs=require('node:fs'),path=require('node:path'),crypto=require('node:crypto');
const {Dex}=require('pokemon-showdown');
const {OwnedBattle}=require('../engine.cjs');
const root=path.join(__dirname,'../../Sources/PokeTokenBar/Resources/BattleEffects');
const catalog=JSON.parse(fs.readFileSync(path.join(root,'catalog.json')));
test('all app moves resolve through canonical dex IDs including the Vice Grip alias',()=>{
 const moves=JSON.parse(fs.readFileSync(path.join(root,'../BattleText/catalog.json'))).moves;
 for(const id of Object.keys(moves)) {
  const canonical=Dex.mod('gen5').moves.get(id).id;
  assert.equal(catalog.aliases[id],canonical,id);
  assert.ok(catalog.recipes[canonical],id);
 }
 assert.equal(new Set(Object.values(catalog.aliases)).size,573);
 for(const id of ['moonblast','mysticalfire','flowertrick'])assert.ok(catalog.recipes[id].operations.length,id);
 assert.deepEqual(catalog.generationPriority,[5,9,8,7,6,4,3,2,1]);
});
test('every exported timeline is finite and all packaged textures match their hashes',()=>{
 const hashes=JSON.parse(fs.readFileSync(path.join(root,'source-sha256.json'))).textures;
 for(const [id,recipe]of Object.entries(catalog.recipes)) {
  assert.equal(recipe.generation,null,'shared source must not be relabelled as a game generation');
  assert.ok(recipe.duration>0&&recipe.duration<=2.5,id);
  assert.ok(recipe.operations.length<=64,id);
  for(const op of recipe.operations) {
   assert.ok(op.finish>=op.begin,id);
   for(const p of [op.start,op.end])for(const value of Object.values(p))assert.ok(Number.isFinite(value),id);
   if(op.texture)assert.ok(hashes[op.texture],id);
  }
 }
 for(const [name,hash]of Object.entries(hashes)) {
  assert.match(name,/^[\w-]+\.(png|jpg)$/);
  assert.equal(crypto.createHash('sha256').update(fs.readFileSync(path.join(root,'textures',name))).digest('hex'),hash,name);
 }
 for(const name of ['lightning.png','icicle.png','bone.png','rocks.png','rock1.png','rock2.png'])assert.equal(hashes[name],undefined);
 assert.deepEqual(catalog.coverage.discardedOperations.map(x=>x.move).sort(),['matchagotcha','spinout']);
});
test('later-generation effects do not bypass the explicit Fairy move exception',()=>{
 for(const move of ['mysticalfire','flowertrick']) {
  assert.ok(catalog.recipes[move]);
  const team=['Pikachu','Raichu','Pichu','Electabuzz','Emolga','Stunfisk'].map((species,i)=>({id:String(i),species,level:37,ability:'Static',
   nature:'Hardy',gender:'M',moves:[i===0?move:'thunderbolt'],
   ivs:{hp:17,atk:17,def:17,spa:17,spd:17,spe:17},stats:{hp:143,atk:91,def:87,spa:96,spd:89,spe:107}}));
  assert.throws(()=>new OwnedBattle('singles',[team,team]),/Unsupported move/);
 }
});
