// Converts the pinned, generation-independent Showdown move table into offline native timelines.
// No Pokémon sprite operations are imported. Run after prepare-battle-engine.sh.
const fs=require('node:fs'),path=require('node:path'),vm=require('node:vm'),crypto=require('node:crypto');
const {transformSync}=require(process.env.PTB_EFFECT_ESBUILD || '../BattleEngine/node_modules/esbuild');
const {Dex}=require('../BattleEngine/node_modules/pokemon-showdown');
const revision='ab4b77b8f3a5712e8fbe03ce106ef2b70a874fdb';
const base=`https://raw.githubusercontent.com/smogon/pokemon-showdown-client/${revision}/play.pokemonshowdown.com/`;
const output=path.resolve(__dirname,'../Sources/PokeTokenBar/Resources/BattleEffects');
const excluded=new Set(['lightning.png','icicle.png','bone.png','rocks.png','rock1.png','rock2.png']);
async function main() {
  const source=async name=>{
    const file=process.env.PTB_EFFECT_SOURCE_DIR && path.join(process.env.PTB_EFFECT_SOURCE_DIR,name==='battle-animations.ts'?'showdown-animations.ts':'showdown-moves.ts');
    if(file)return fs.readFileSync(file,'utf8');
    const reply=await fetch(base+'src/'+name);if(!reply.ok)throw Error(reply.status+' '+name);return reply.text();
  };
  const [shared,moves]=await Promise.all([source('battle-animations.ts'),source('battle-animations-moves.ts')]);
  const context={window:{},Config:{routes:{client:'play.pokemonshowdown.com'}},Math:Object.create(Math)};
  let seed=1;context.Math.random=()=>((seed=(seed*1664525+1013904223)>>>0)/4294967296);
  vm.createContext(context);
  const load=(code,extra={})=>{
    const module={exports:{}};Object.assign(context,{module,exports:module.exports,...extra});
    vm.runInContext(transformSync(code,{loader:'ts',format:'cjs',target:'es2020'}).code,context,{timeout:10000});
    return module.exports;
  };
  const helpers=load(shared.slice(shared.indexOf('const BattleEffects:'))+'\nexport { BattleEffects };');
  const tables=load(moves.replace(/^import .*;\n/gm,''),{BattleOtherAnims:helpers.BattleOtherAnims});
  const recipes={}, assets={},failures=[], discardedOperations=[];
  for(const id of Object.keys(tables.BattleMoveAnims).sort()) {
    const move=Dex.moves.get(id);if(!move.exists)continue;
    for(const phase of ['anim',...(tables.BattleMoveAnims[id].prepareAnim?['prepareAnim']:[])]) {
    const recipeID=phase==='anim'?id:id+':charge';
    seed=1;
    const operations=[];
    const sprite=(z,front)=>({x:0,y:0,z,isFrontSprite:front,isMissedPokemon:false,sp:{pokemon:true},
      behind(n){return z+(front?1:-1)*n;},leftof(n){return (front?1:-1)*n;},
      anim(){return this;},delay(){return this;}});
    const attacker=sprite(0,false),defender=sprite(200,true);
    const scene={timeOffset:0,battle:{gen:5,mySide:attacker},backgroundEffect(){},
      $bg:{delay(){return this;},animate(){return this;}},
      wait(ms){this.timeOffset+=ms;},
      showEffect(effect,start,end,easing='linear',after='') {
        if(typeof effect!=='string')return; // Sprite afterimages are intentionally excluded.
        const asset=helpers.BattleEffects[effect];if(!asset)throw Error('Unknown texture '+effect);
        const a={x:0,y:0,z:0,scale:1,opacity:1,...start};
        const b={...a,...end};
        const begin=(start.time||0)+this.timeOffset,finish=(end.time||((start.time||0)+500))+this.timeOffset;
        const point=p=>({x:p.x,y:p.y,z:p.z,scaleX:p.xscale??p.scale,scaleY:p.yscale??p.scale,opacity:p.opacity});
        if(![...Object.values(point(a)),...Object.values(point(b)),begin,finish].every(Number.isFinite)) {
          // Two upstream ninth-generation loops divide by i at i=0. Discard that invalid particle.
          discardedOperations.push({move:id,effect});return;
        }
        const texture=asset.url && /^[\w-]+\.(png|jpg)$/.test(asset.url) && !excluded.has(asset.url)?asset.url:null;
        if(texture)assets[texture]={width:asset.w,height:asset.h};
        operations.push({effect,texture,width:asset.w,height:asset.h,start:point(a),end:point(b),begin,finish,easing,after});
      }};
    try { tables.BattleMoveAnims[id][phase](scene,[attacker,defender]); }
    catch(error){failures.push({id,error:String(error)});}
    const duration=Math.max(650,...operations.map(op=>op.finish+(op.after?180:0)));
    recipes[recipeID]={generation:null,source:'showdown-shared',duration:Math.min(2500,duration)/1000,
      timeScale:Math.min(2500,duration)/duration,category:move.category,type:move.type,
      scope:phase==='prepareAnim' || ['self','allySide','allyTeam'].includes(move.target)?'self':(['all','field'].includes(move.target)?'field':'target'),
      operations};
    }
  }
  const catalog=JSON.parse(fs.readFileSync(path.join(output,'../BattleText/catalog.json')));
  const aliases=Object.fromEntries(Object.keys(catalog.moves).map(id=>[id,Dex.mod('gen5').moves.get(id).id]));
  for(const [id,canonical] of Object.entries(aliases))if(!recipes[canonical])throw Error('Unmapped move '+id);
  if(failures.length)throw Error('Exporter must not silently discard unsupported operations: '+JSON.stringify(failures));
  fs.mkdirSync(path.join(output,'textures'),{recursive:true});
  const hashes={};
  const names=Object.keys(assets).sort();
  for(let i=0;i<names.length;i+=8)await Promise.all(names.slice(i,i+8).map(async name=>{
    const target=path.join(output,'textures',name);
    let data;
    if(fs.existsSync(target))data=fs.readFileSync(target);
    else { const reply=await fetch(base+'fx/'+name);if(!reply.ok)throw Error(reply.status+' '+name);
      data=Buffer.from(await reply.arrayBuffer());fs.writeFileSync(target,data); }
    hashes[name]=crypto.createHash('sha256').update(data).digest('hex');
  }));
  const data={schema:1,revision,generationPriority:[5,9,8,7,6,4,3,2,1],aliases,recipes,assets,
    coverage:{catalogEntries:Object.keys(aliases).length,canonicalMoves:new Set(Object.values(aliases)).size,
      importedRecipes:Object.keys(recipes).filter(id=>!id.includes(':')).length,
      preparationRecipes:Object.keys(recipes).filter(id=>id.includes(':')).length,discardedOperations,
      nativeFallbacks:Object.entries(recipes).filter(([,r])=>!r.operations.length).map(([id])=>id)}};
  fs.writeFileSync(path.join(output,'catalog.json'),JSON.stringify(data));
  fs.writeFileSync(path.join(output,'source-sha256.json'),JSON.stringify({revision,
    sources:{moves:crypto.createHash('sha256').update(moves).digest('hex'),shared:crypto.createHash('sha256').update(shared).digest('hex')},textures:hashes},null,2)+'\n');
  console.log(JSON.stringify(data.coverage,null,2));
}
main().catch(error=>{console.error(error);process.exitCode=1;});
