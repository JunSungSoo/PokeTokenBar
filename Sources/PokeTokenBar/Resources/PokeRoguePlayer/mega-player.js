// Battle-space adaptation of pinned FormChangePhase and Animation's spiral/arc/circle/spray.
// Original particle texture/audio and 60fps equations, visual clock at 2x; audio pitch stays original.
export class MegaAnimation {
 constructor({incoming,outgoing,addParticle,addBackdrop,playSound,reducedMotion=false,audioTail=0}){
  Object.assign(this,{incoming,outgoing,addParticle,playSound,reducedMotion});this.elapsed=0;this.wallElapsed=0;this.speed=2;this.particles=[];this.sounds=new Set();
  this.duration=Math.max((8250+250)/this.speed+(incoming.cryInfo?incoming.cryInfo.duration/incoming.cryInfo.rate*1000:0),audioTail);
  this.phase='charge';incoming.setVisible(false);
  this.backdrop=addBackdrop(0x000000);this.flash=addBackdrop(0xffffff);
  this.center={x:incoming.x,y:incoming.y-incoming.base.height/2};
 }
 advance(delta){
  this.wallElapsed+=delta;this.elapsed+=delta*this.speed;const t=this.elapsed,old=this.outgoing,p=this.incoming;
  const clamp=x=>Math.max(0,Math.min(1,x)),sine=x=>1-Math.cos(clamp(x)*Math.PI/2);
  const cubic=x=>{x=clamp(x);return x<.5?4*x*x*x:1-(-2*x+2)**3/2;};
  const sound=(name,at,config)=>{if(t>=at&&!this.sounds.has(name)){this.sounds.add(name);this.playSound(name,at/this.speed,config);}};
  if(!this.reducedMotion){sound('mega-charge',250);sound('mega-beam',3350);sound('mega-sparkle',4850);}
  sound('mega-shine',5750);
  if(p.cryInfo)sound(p.cryInfo.key,8250,{rate:p.cryInfo.rate});
  const glow=sine((t-250)/2000),cycle=cubic((t-4350)/500),reveal=sine((t-6000)/2000);
  if(old){old.setVisible(t<4850);old.setScale(1-.75*cycle);old.base.pipelineData.tone=[255*glow,255*glow,255*glow,0];}
  p.setVisible(t>=4350);p.setScale(.25+.75*cycle);p.base.pipelineData.tone=[255*(1-reveal),255*(1-reveal),255*(1-reveal),0];
  this.backdrop.setAlpha(.55*sine(t/250)*(1-sine((t-8000)/250)));
  this.flash.setAlpha(t<5750?0:t<6000?sine((t-5750)/250):1-reveal);
  const sin=(i,a)=>Math.sin(i*Math.PI/128)*a,cos=(i,a)=>Math.cos(i*Math.PI/128)*a;
  const plot=(key,at,update)=>{
   const age=t-at;if(age<0)return;
   const f=Math.floor(age*60/1000),v=update(f);let sprite=this.particles[key];
   if(!v){if(sprite)sprite.setVisible(false);return;}
   if(!sprite){sprite=this.addParticle();this.particles[key]=sprite;}
   sprite.setVisible(true).setPosition(this.center.x+v.x,this.center.y+v.y).setScale(v.scale??1);
  };
  if(!this.reducedMotion){
   for(let c=0;c<8;c++)for(let i=0;i<4;i++)plot(c*4+i,250+(c+1)*8000/60,f=>{
    if(f>80)return null;const trig=16*c+i*64+4*f,amp=48-Math.floor(f/2);
    return {x:cos(trig,amp),y:40-f*f/80+sin(trig,amp)/4,scale:1-f/80};
   });
   for(let c=0;c<6;c++)for(let i=0;i<9;i++)plot(32+c*9+i,3350+(c+1)*1000/60,f=>{
    if(f>20)return null;const amp=f?8+sin((f-1)*4,40):8;
    return {x:cos(i*16,amp),y:-40+f*f/5+sin(i*16,amp)/4,scale:.5};
   });
   for(let c=0;c<2;c++)for(let i=0;i<16;i++)plot(86+c*16+i,4850+c*32000/60,f=>{
    const amp=120-f*(c?8:4);if(amp<=8)return null;
    return {x:cos(i*16+4*f,amp),y:sin(i*16+4*f,amp)};
   });
   for(let i=0;i<56;i++)plot(118+i,5750+Math.max(0,i-7)*1000/60,f=>{
    const trig=(i%8)+f;if(trig>=128)return null;
    return {x:((3-i%8)*f)/3,y:Math.floor(f/4)-sin(trig,48+(i*17)%64),scale:f>108?1-(f-108)/20:1};
   });
  }
  this.phase=t<3350?'charge':t<4350?'arc':t<4850?'transform':t<5750?'gather':t<8250?'reveal':'cry';
  if(this.wallElapsed>=this.duration){this.phase='done';p.setVisible(true).setScale(1);p.base.pipelineData.tone=[0,0,0,0];if(old)old.setVisible(false);}
  return this.wallElapsed>=this.duration;
 }
 inspect(){return {elapsed:this.elapsed,wallElapsed:this.wallElapsed,speed:this.speed,duration:this.duration,phase:this.phase,source:this.incoming.key,
  particles:this.particles.filter(p=>p?.visible).length,incomingVisible:this.incoming.visible,outgoingVisible:this.outgoing?.visible??false,
  incomingScale:this.incoming.scaleX,backdropAlpha:this.backdrop.alpha,flashAlpha:this.flash.alpha};}
}
