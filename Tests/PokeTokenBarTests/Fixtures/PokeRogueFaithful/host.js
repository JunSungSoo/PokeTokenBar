// Scene adapter only. Animation commands run in the verbatim upstream BattleAnim implementation.
import {AnimConfig,BattleAnim,bindScene} from './original-player.js';
const post=data=>window.webkit?.messageHandlers.faithful.postMessage(data);
window.addEventListener('error',e=>post({kind:'error',message:String(e.error||e.message)}));
window.addEventListener('unhandledrejection',e=>post({kind:'error',message:String(e.reason?.stack||e.reason)}));
const panelCount=new URLSearchParams(location.search).get('panels')==='1'?1:2;
const moves=['thunderbolt','protect','quick-attack','volt-switch'];
let scene,panels=[],sprites,started=false,paused=false,rate=1,reverse=false,move='thunderbolt',sameLayout=true,loop=true,sound=false;
let physical=0,pauseUntil=0,lastPost=0;
class Clock {
 constructor(owner){this.owner=owner;this.now=0;this.counters=[];this.tweens=[];}
 addCounter(config){const item={config,due:this.now+config.duration,remaining:config.repeat||0};this.counters.push(item);return item;}
 add(config){const start=this.now;const targets=Array.isArray(config.targets)?config.targets:[config.targets];for(const target of targets){if(!target)continue;const values={};for(const key of ['x','y','alpha'])if(config[key]!==undefined)values[key]=[target[key],config[key]];this.tweens.push({target,values,start,duration:config.duration||0});}}
 updateTween(time){for(const t of this.tweens){const p=t.duration?Phaser.Math.Clamp((time-t.start)/t.duration,0,1):1;if(t.target?.active)for(const [key,[a,b]]of Object.entries(t.values))t.target[key]=a+(b-a)*p;}this.tweens=this.tweens.filter(t=>t.target?.active&&time<t.start+t.duration);}
 advance(ms){const end=this.now+ms;let iterations=0;while(iterations++<10000){this.counters.sort((a,b)=>a.due-b.due);const item=this.counters[0];if(!item||item.due>end)break;this.now=item.due;this.updateTween(this.now);bindScene(this.owner);if(item.remaining>0){item.remaining--;item.due+=item.config.duration;item.config.onRepeat?.();}else{this.counters.shift();item.config.onComplete?.();}}this.now=end;this.updateTween(end);}
 reset(){this.now=0;this.counters=[];this.tweens=[];}
}
class TonePipeline extends Phaser.Renderer.WebGL.Pipelines.SinglePipeline {
 constructor(game){super({game,fragShader:`precision mediump float;uniform sampler2D uMainSampler;varying vec2 outTexCoord;varying vec4 outTint;uniform vec4 tone;void main(){vec4 color=texture2D(uMainSampler,outTexCoord)*outTint;float luma=dot(color.rgb,vec3(.299,.587,.114));color.rgb=mix(color.rgb,vec3(luma),tone.w);color.rgb+=tone.rgb*(color.a/255.0);gl_FragColor=color;}`});}
 onBind(object){this.flush();const t=object?.pipelineData?.tone||[0,0,0,0];this.set4f('tone',t[0],t[1],t[2],t[3]);}
}
class OriginalMove extends BattleAnim {
 constructor(config,user,target,opposing){super(user,target);this.config=config;this.opposing=opposing;}
 getAnim(){return this.config;}
 isOppAnim(){return this.opposing;}
}
const meta={};
function sprite(x,y,key,frame){return scene.add.sprite(x,y,key,frame);}
function actor(panel,own,x,y){
 const p=scene.add.container(x,y);p.own=own;p.visible=true;p.shiny=false;p.variant=0;
 const base=sprite(0,0,own?'pikachu-back':'pikachu-front','gif-0').setOrigin(.5,1).setPipeline('NativeTone');p.add(base);panel.field.add(p);
 base.pipelineData.tone=[0,0,0,0];base.pipelineData.spriteColors=[];base.pipelineData.fusionSpriteColors=[];
 p.getSprite=()=>base;p.isOnField=()=>true;p.getTag=()=>null;p.isPlayer=()=>own;p.getBattleSpriteKey=()=>own?'pikachu-back':'pikachu-front';p.cry=()=>null;
 p.getSpriteScale=()=>1;p.getSubstituteOffset=()=>[0,0];p.base=base;p.gifFrame=-1;
 return p;
}
function createPanel(index,offset=index*320){
 const field=scene.add.container(offset,0);const mask=scene.make.graphics({x:0,y:0,add:false});mask.fillStyle(0xffffff).fillRect(offset,0,320,180);field.setMask(mask.createGeometryMask());
 const panel={index,field,audioEnabled:index===1&&sound,done:true,events:[],actors:[]};panel.clock=new Clock(panel);panel.tweens=panel.clock;panel.add={tileSprite:(...args)=>scene.add.tileSprite(...args).setVisible(false),rectangle:(...args)=>scene.add.rectangle(...args).setVisible(false)};
 panel.sound=scene.sound;panel.addFieldSprite=(x,y,key,frame)=>sprite(x,y,key,frame);
 panel.addPokemonSprite=(_p,x,y,texture,frame)=>sprite(x,y,texture,frame).setPipeline('NativeTone');
 panel.getEnemyPokemon=()=>panel.actors[1];panel.getPlayerPokemon=()=>panel.actors[0];
 panel.getEnemyField=()=>[panel.actors[1]];panel.getPlayerField=()=>[panel.actors[0]];
 return panel;
}
function resetPanel(panel){
 panel.clock.reset();panel.field.removeAll(true);panel.events=[];panel.done=false;panel.audioEnabled=panel.index===1&&sound;
 const bg=scene.add.image(160,90,'current-battle-background');panel.field.add(bg);
 const anchors=panel.index===0||sameLayout?[[106,148],[234,84]]:[[61,165],[263,84]];
 for(const [x,y]of anchors){const shadow=scene.add.ellipse(x,y+5,95,22,0x919e66).setStrokeStyle(3,0xffffff,.35);panel.field.add(shadow);}
 panel.actors=anchors.map(([x,y],i)=>actor(panel,i===0,x,y));
 updateGIF(panel);
 const data=scene.cache.json.get(move),variants=Array.isArray(data)?data:[data],opposing=reverse&&variants.length>1;
 const config=new AnimConfig(variants[reverse&&variants.length>1?1:0]);
 const user=panel.actors[reverse?1:0],target=move==='protect'?user:panel.actors[reverse?0:1];
 // The opponent direction variant swaps USER/TARGET exactly as upstream MoveAnim does.
 bindScene(panel);panel.animation=new OriginalMove(config,user,target,opposing);
 panel.animation.play(false,()=>{panel.done=true;panel.finishedAt=physical;});
}
function updateGIF(panel){
 if(!sprites)return;
 for(const p of panel.actors){const source=meta[p.own?'back':'front'];const cycle=source.delays.reduce((a,b)=>a+b,0)*1000;let position=physical%cycle,index=0;while(index<source.delays.length-1&&position>=source.delays[index]*1000){position-=source.delays[index]*1000;index++;}
  if(index!==p.gifFrame){p.gifFrame=index;p.base.setFrame('gif-'+index);p.base.emit('animationupdate',null,{textureFrame:'gif-'+index});}
 }
}
async function installAtlas(name,data){
 const images=await Promise.all(data.frames.map(src=>new Promise((resolve,reject)=>{const i=new Image();i.onload=()=>resolve(i);i.onerror=reject;i.src=src;})));
 const columns=Math.min(32,images.length),rows=Math.ceil(images.length/columns);const texture=scene.textures.createCanvas(name,64*columns,64*rows);
 texture.context.imageSmoothingEnabled=false;
 images.forEach((image,i)=>{texture.context.drawImage(image,(i%columns)*64,Math.floor(i/columns)*64,64,64);texture.add("gif-"+i,0,(i%columns)*64,Math.floor(i/columns)*64,64,64);});texture.refresh();
}
function restart(){if(!sprites)return;for(const p of panels)resetPanel(p);pauseUntil=0;started=true;}
function trace(panel){return panel.field.list.flatMap((p,index)=>{
 if(p===panel.actors[0]||p===panel.actors[1])return [];
 if(!p.texture)return [];
 return [{index,texture:p.displayTexture?.key||p.texture.key,frame:String(p.frame?.name),x:p.x,y:p.y,sx:p.scaleX,sy:p.scaleY,angle:p.angle,alpha:p.alpha,visible:p.visible,tone:p.pipelineData?.tone||[]}];
 });}
window.faithfulInitialize=async function(payload){
 meta.back=payload.back;meta.front=payload.front;
 await installAtlas('pikachu-back',payload.back);await installAtlas('pikachu-front',payload.front);sprites=payload;restart();post({kind:'ready',renderer:scene.game.renderer.type===Phaser.WEBGL?'WebGL':'Canvas',backFrames:payload.back.frames.length,frontFrames:payload.front.frames.length});
};
window.faithfulConfigure=function(config){move=config.move||move;reverse=!!config.reverse;rate=config.rate||1;sameLayout=config.sameLayout!==false;loop=config.loop!==false;sound=!!config.sound;paused=false;restart();return true;};
window.faithfulPause=function(value){paused=value;return true;};
window.faithfulSeek=function(frame){paused=true;restart();for(const p of panels){bindScene(p);p.clock.advance((frame+1)*50+.001);}return window.faithfulInspect();};
window.faithfulInspect=function(){const a=trace(panels[0]),b=trace(panels[1]||panels[0]);return {move,reverse,paused,ready:!!sprites,done:panels.map(p=>p.done),clock:panels[0]?.clock.now,physical,hidden:document.hidden,loopFrame:scene.game.loop.frame,frame:Math.max(-1,Math.floor(panels[0]?.clock.now/50)-1),equal:JSON.stringify(a)===JSON.stringify(b),traces:[a,b],gifFrames:panels.map(p=>p.actors.map(a=>a.gifFrame)),actors:panels.map(p=>p.actors.map(a=>({x:a.x,y:a.y,visible:a.base.visible,frame:a.gifFrame}))),sourceFrames:scene.cache.json.get(move)?.length||scene.cache.json.get(move)?.frames?.length};};
window.faithfulStop=function(){started=false;for(const p of panels)p.clock.reset();scene.sound.stopAll();};
window.faithfulRenderStep=(delta=16.667)=>{scene.update(performance.now(),delta);return window.faithfulInspect();};
new Phaser.Game({type:Phaser.WEBGL,parent:'stage',width:320*panelCount,height:180,scale:{mode:Phaser.Scale.FIT,autoCenter:Phaser.Scale.CENTER_BOTH},pixelArt:true,transparent:false,backgroundColor:'#879653',audio:{disableWebAudio:false},render:{antialias:false,roundPixels:false,preserveDrawingBuffer:true},scene:{
 preload(){scene=this;
  for(const id of moves)this.load.json(id,'battle-anims/'+id+'.json');
  for(const name of ['PRAS- Electric','PRAS- Protect','PRAS- Strike'])this.load.spritesheet(name,'images/battle_anims/'+encodeURIComponent(name)+'.png',{frameWidth:96,frameHeight:96});
  this.load.image('PRAS- Black BG','images/battle_anims/PRAS-%20Black%20BG.png');
  this.load.image('arena-bg','images/arenas/plains_bg.png');
  for(const name of ['PRSFX- Thunderbolt1.wav','PRSFX- Thunderbolt2.wav','PRSFX- Protect.wav',"PRSFX- King's Shield1.wav","PRSFX- King's Shield2.wav",'PRSFX- Quick Attack.wav','PRSFX- Volt Switch1.wav','PRSFX- Volt Switch2.wav'])this.load.audio('battle_anims/'+name,'audio/battle_anims/'+encodeURIComponent(name));
 },
 create(){scene=this;this.game.renderer.pipelines.add('NativeTone',new TonePipeline(this.game));const bg=this.textures.createCanvas('current-battle-background',320,180);const g=bg.context.createLinearGradient(0,0,0,180);g.addColorStop(0,'rgb(156,179,163)');g.addColorStop(1,'rgb(219,222,181)');bg.context.fillStyle=g;bg.context.fillRect(0,0,320,180);bg.refresh();panels=panelCount===1?[createPanel(1,0)]:[createPanel(0),createPanel(1)];post({kind:'loaded'});},
 update(time,delta){physical=performance.now();if(!started)return;for(const p of panels){updateGIF(p);if(!paused&&!p.done)p.clock.advance(Math.min(delta,100)*rate);}
  if(!paused&&panels.every(p=>p.done)){if(!pauseUntil)pauseUntil=physical+1000;if(loop&&physical>=pauseUntil)restart();}
  if(time-lastPost>100){lastPost=time;post({kind:'status',...window.faithfulInspect()});}
 }
}});
