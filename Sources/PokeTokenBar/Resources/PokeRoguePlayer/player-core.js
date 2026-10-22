import {BattleAnim,bindScene} from './original-player.js';
const Phaser=window.Phaser;
export class Clock {
 constructor(owner){this.owner=owner;this.now=0;this.counters=[];this.tweens=[];}
 addCounter(config){const item={config,due:this.now+config.duration,remaining:config.repeat||0};this.counters.push(item);return item;}
 add(config){const start=this.now;const targets=Array.isArray(config.targets)?config.targets:[config.targets];for(const target of targets){if(!target)continue;const values={};for(const key of ['x','y','alpha'])if(config[key]!==undefined)values[key]=[target[key],config[key]];this.tweens.push({target,values,start,duration:config.duration||0});}}
 updateTween(time){for(const t of this.tweens){const p=t.duration?Phaser.Math.Clamp((time-t.start)/t.duration,0,1):1;if(t.target?.active)for(const [key,[a,b]]of Object.entries(t.values))t.target[key]=a+(b-a)*p;}this.tweens=this.tweens.filter(t=>t.target?.active&&time<t.start+t.duration);}
 advance(ms){const end=this.now+ms;let iterations=0;while(iterations++<10000){this.counters.sort((a,b)=>a.due-b.due);const item=this.counters[0];if(!item||item.due>end)break;this.now=item.due;this.updateTween(this.now);bindScene(this.owner);if(item.remaining>0){item.remaining--;item.due+=item.config.duration;item.config.onRepeat?.();}else{this.counters.shift();item.config.onComplete?.();}}this.now=end;this.updateTween(end);}
 reset(){this.now=0;this.counters=[];this.tweens=[];}
}
export class TonePipeline extends Phaser.Renderer.WebGL.Pipelines.SinglePipeline {
 constructor(game){super({game,fragShader:`precision mediump float;uniform sampler2D uMainSampler;varying vec2 outTexCoord;varying vec4 outTint;uniform vec4 tone;void main(){vec4 color=texture2D(uMainSampler,outTexCoord)*outTint;float luma=dot(color.rgb,vec3(.299,.587,.114));color.rgb=mix(color.rgb,vec3(luma),tone.w);color.rgb+=tone.rgb*(color.a/255.0);gl_FragColor=color;}`});}
 onBind(object){this.flush();const t=object?.pipelineData?.tone||[0,0,0,0];this.set4f('tone',t[0],t[1],t[2],t[3]);}
}
export class OriginalMove extends BattleAnim {
 constructor(config,user,target,opposing){super(user,target);this.config=config;this.opposing=opposing;}
 getAnim(){return this.config;}
 isOppAnim(){return this.opposing;}
}
