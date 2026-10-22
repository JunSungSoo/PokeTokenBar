import {AnimConfig,bindScene} from './original-player.js';
import {Clock,TonePipeline,OriginalMove} from './player-core.js';
const backgroundOnly=new URLSearchParams(location.search).get('layer')==='background';
const post=m=>window.webkit?.messageHandlers.rogue.postMessage({...m,layer:backgroundOnly?'background':'foreground'});
window.addEventListener('unhandledrejection',e=>post({kind:'error',message:String(e.reason?.stack||e.reason)}));
let scene,manifest,field,actors=[],runs=[],done=true,physical=0,generation=0,rawDefinitions=new Map(),pending=false;
const assets=new Map();
const resourceOrder=[],soundOrder=[];
let effectsVolume=0;
const soundEvents=[];
window.ptbSetEffectsVolume=value=>{effectsVolume=Number.isFinite(value)?Math.max(0,Math.min(1,value)):0.35;if(scene)scene.sound.setVolume(backgroundOnly?0:effectsVolume);return effectsVolume;};
async function json(path){if(rawDefinitions.size>=24&&!rawDefinitions.has(path))rawDefinitions.delete(rawDefinitions.keys().next().value);if(!rawDefinitions.has(path))rawDefinitions.set(path,fetch(path).then(r=>{if(!r.ok)throw Error('Missing original timeline '+path);return r.json();}));return rawDefinitions.get(path);}
function loadAssets(entry){return new Promise((resolve,reject)=>{
 const graphics=new Set(entry.graphics),names=[...entry.graphics,...entry.backgrounds];let needed=0;
 for(const name of names){if(scene.textures.exists(name))continue;needed++;const url='images/battle_anims/'+encodeURIComponent(name)+'.png';if(graphics.has(name))scene.load.spritesheet(name,url,{frameWidth:96,frameHeight:96});else scene.load.image(name,url);}
 // Sound events retain their authored duration, while the native Gold/Silver BGM stays independent.
 for(const name of entry.sounds){const key='battle_anims/'+name;if(scene.cache.audio.exists(key))continue;needed++;scene.load.audio(key,'audio/battle_anims/'+encodeURIComponent(name));}
 if(!needed){resolve();return;}
 const fail=file=>{scene.load.off('complete',finish);reject(Error('Missing original asset '+file.key));};
 const finish=()=>{scene.load.off('loaderror',fail);
 for(const name of names){const i=resourceOrder.indexOf(name);if(i>=0)resourceOrder.splice(i,1);resourceOrder.push(name);}
 while(resourceOrder.length>24){const old=resourceOrder.shift();if(!names.includes(old))scene.textures.remove(old);}
 for(const name of entry.sounds){const key='battle_anims/'+name;const i=soundOrder.indexOf(key);if(i>=0)soundOrder.splice(i,1);soundOrder.push(key);}
 while(soundOrder.length>48){const old=soundOrder.shift();scene.sound.removeByKey(old);scene.cache.audio.remove(old);}
 resolve();};scene.load.once('complete',finish);scene.load.once('loaderror',fail);scene.load.start();
 });}
async function atlas(key,payload){
 if(scene.textures.exists(key))return;
 const images=await Promise.all(payload.frames.map(src=>new Promise((resolve,reject)=>{const image=new Image();image.onload=()=>resolve(image);image.onerror=()=>reject(Error('Invalid native GIF frame'));image.src=src;})));
 const columns=Math.min(32,images.length),rows=Math.ceil(images.length/columns),t=scene.textures.createCanvas(key,64*columns,64*rows);t.context.imageSmoothingEnabled=false;
 images.forEach((image,i)=>{t.context.drawImage(image,(i%columns)*64,Math.floor(i/columns)*64,64,64);t.add('gif-'+i,0,(i%columns)*64,Math.floor(i/columns)*64,64,64);});t.refresh();
 assets.set(key,payload);
}
// Keep source timing/depth operations intact; render separate native surfaces around the HUD.
function layer(object,kind){
 object.setData('battleLayer',kind);
 const render=object.renderWebGL;
 object.renderWebGL=function(...args){if(backgroundOnly===(kind==='background'))return render.apply(this,args);};
 return object;
}
function orderLayers(){const rank={background:0,actor:1,effect:2};field.list.sort((a,b)=>(rank[a.getData('battleLayer')]??1)-(rank[b.getData('battleLayer')]??1));}
function makeActor(data,scale){
 const p=layer(scene.add.container(data.x/scale,data.y/scale),'actor');field.add(p);p.own=data.own;p.slot=data.slot;p.key=data.key;p.visible=true;p.shiny=false;p.variant=0;p.gif=-1;
 const base=scene.add.sprite(0,0,data.texture,'gif-0').setOrigin(.5,1).setPipeline('NativeTone');p.add(base);p.base=base;p.textureKey=data.texture;
 base.pipelineData.tone=[0,0,0,0];base.pipelineData.spriteColors=[];base.pipelineData.fusionSpriteColors=[];
 p.getSprite=()=>base;p.isOnField=()=>true;p.getTag=()=>null;p.isPlayer=()=>data.own;p.getBattleSpriteKey=()=>data.texture;p.cry=()=>null;p.getSpriteScale=()=>1;p.getSubstituteOffset=()=>[0,0];return p;
}
function gif(){for(const p of actors){const data=assets.get(p.textureKey),cycle=data.delays.reduce((a,b)=>a+b,0)*1000;let pos=physical%cycle,i=0;while(i<data.delays.length-1&&pos>=data.delays[i]*1000){pos-=data.delays[i]*1000;i++;}if(i!==p.gif){p.gif=i;p.base.setFrame('gif-'+i);p.base.emit('animationupdate',null,{textureFrame:'gif-'+i});}}}
function timedLayer(resource){return /\bFG\b/i.test(resource)||resource==='PRAS- Sketch + Lick'?'effect':'background';}
function facade(index,user){
 const add={tileSprite:(...args)=>layer(scene.add.tileSprite(...args),timedLayer(args[4])),rectangle:(...args)=>layer(scene.add.rectangle(...args),'background')};
 const audioEnabled=!backgroundOnly&&index===0;
 const sound={get:key=>scene.sound.get(key),play:(key,config)=>{
  if(audioEnabled){soundEvents.push({key,volume:config.volume*scene.sound.volume,pitch:config.rate,clock:owner.clock.now});if(soundEvents.length>48)soundEvents.shift();}
  return scene.sound.play(key,config);
 }};
 const owner={field,audioEnabled,sound,add,done:false};owner.clock=new Clock(owner);owner.tweens=owner.clock;
 // One authored background and caster representation for a spread move; each target still gets its own original target/graphic track.
 if(index>0)owner.add={tileSprite:(...args)=>add.tileSprite(...args).setVisible(false),rectangle:(...args)=>add.rectangle(...args).setVisible(false)};
 owner.addFieldSprite=(x,y,key,frame)=>layer(scene.add.sprite(x,y,key,frame),'effect');
 owner.addPokemonSprite=(p,x,y,texture,frame)=>{const sprite=layer(scene.add.sprite(x,y,texture,frame).setPipeline('NativeTone'),'actor');if(index>0&&p===user){const set=sprite.setVisible;sprite.setVisible=function(){return set.call(this,false);};}return sprite;};
 owner.getEnemyPokemon=()=>actors.find(a=>!a.own);owner.getPlayerPokemon=()=>actors.find(a=>a.own);
 owner.getEnemyField=()=>actors.filter(a=>!a.own);owner.getPlayerField=()=>actors.filter(a=>a.own);return owner;
}
function clear(){generation++;soundEvents.length=0;scene.sound.stopAll();scene.sound.removeAll();for(const r of runs)r.clock.reset();runs=[];actors=[];field.removeAll(true);done=true;scene.game.step(performance.now(),0);scene.game.loop.sleep();}
window.ptbPrepare=async function(payload){
 if(pending)throw Error('Original player is already preparing');pending=true;
 try{
 clear();window.ptbSetEffectsVolume(payload.effectsVolume??effectsVolume);
 if(!backgroundOnly&&effectsVolume>0){scene.sound.unlock();await scene.sound.context?.resume();}
 const run=generation,entry=manifest.entries[payload.move];if(!entry)throw Error('Unsupported original move '+payload.move);
 const definition=await json(entry.file);await loadAssets(entry);
 const current=new Set(payload.actors.map(a=>a.texture));
 for(const actor of payload.actors){await atlas(actor.texture,actor.sprite);const data=assets.get(actor.texture);assets.delete(actor.texture);assets.set(actor.texture,data);}
 for(const key of [...assets.keys()])if(assets.size>16&&!current.has(key)){assets.delete(key);scene.textures.remove(key);}
 if(run!==generation)throw Error('Original playback canceled');
 scene.scale.resize(payload.width,payload.height);const scale=payload.scale;field.setScale(scale);
 actors=payload.actors.map(a=>makeActor(a,scale));physical=performance.now();gif();
 const user=actors.find(a=>a.key===payload.source);if(!user)throw Error('Missing original move actor');
 const targets=payload.targets.map(t=>actors.find(a=>a.key===t.key)).filter(Boolean);if(!targets.length)targets.push(user);
 const variants=Array.isArray(definition)?definition:[definition],opposing=!user.own&&variants.length>1;
 for(const [index,target]of targets.entries()){
  const owner=facade(index,user),config=new AnimConfig(variants[opposing?1:0]);
  if(!payload.hit)config.frames=config.frames.map(fs=>fs.filter(f=>f.target===0||(f.target===2&&(f.focus===2||f.focus===4))));
  bindScene(owner);owner.animation=new OriginalMove(config,user,target,opposing);runs.push(owner);owner.animation.play(false,()=>{owner.done=true;});
 }
 done=false;scene.game.loop.sleep();return {frames:runs[0].animation.config.frames.length};
 }finally{pending=false;}
};
window.ptbAdvance=function(delta){physical=performance.now();gif();for(const r of runs){if(r.done)continue;bindScene(r);r.clock.advance(delta);}done=runs.every(r=>r.done);orderLayers();scene.game.isPaused=false;scene.game.step(performance.now(),0);scene.game.loop.sleep();return {done,clock:runs[0]?.clock.now||0};};
window.ptbFinish=function(){clear();return true;};
window.ptbInspect=()=>({done,effectsVolume:scene.sound.volume,audioState:scene.sound.context?.state,soundEvents:[...soundEvents],playingSounds:scene.sound.sounds.filter(s=>s.isPlaying).length,soundInstances:scene.sound.sounds.length,layer:backgroundOnly?'background':'foreground',layers:field.list.map(a=>a.getData('battleLayer')),actors:actors.map(a=>({key:a.key,gif:a.gif,x:a.x,y:a.y})),tracks:runs.length,sprites:field.list.filter(a=>a.texture).map(a=>({texture:a.texture.key,x:a.x,y:a.y,visible:a.visible})),graphics:field.list.filter(a=>a.texture?.key?.startsWith('PRAS-')).length,clock:runs[0]?.clock.now||0,backdrops:field.list.filter(a=>a.type==='TileSprite').map(a=>({resource:a.displayTexture?.key,layer:a.getData('battleLayer'),visible:a.visible,alpha:a.alpha}))});
fetch('manifest.json').then(r=>r.json()).then(m=>{
 manifest=m;
 new Phaser.Game({type:Phaser.WEBGL,parent:'stage',width:800,height:320,transparent:true,pixelArt:true,render:{antialias:false,roundPixels:false,preserveDrawingBuffer:true},scene:{
 create(){scene=this;this.game.renderer.pipelines.add('NativeTone',new TonePipeline(this.game));field=this.add.container(0,0);post({kind:'ready'});setTimeout(()=>this.game.loop.sleep(),0);},update(){}
 }});
}).catch(e=>post({kind:'error',message:String(e)}));
