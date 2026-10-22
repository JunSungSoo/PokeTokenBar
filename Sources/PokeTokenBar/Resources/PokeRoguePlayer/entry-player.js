// Adapted from pinned SummonPhase, SwitchSummonPhase and Animation.doDefaultPbOpenParticles.
// Original easing; appearance playback at 1.25x, recall at 1x, ball/particle atlases and pb_rel sound; native arena anchors/GIFs.
export class EntryAnimation {
 constructor({scene,field,incoming,outgoing,add,playSound,reducedMotion=false}) {
  Object.assign(this,{scene,field,incoming,outgoing,add,playSound,reducedMotion});
  this.elapsed=0;this.particles=[];this.released=false;this.recalled=false;
  this.recall=!!outgoing;this.phase=this.recall?'recall':'throw';this.delay=this.recall?1000:0;
  this.duration=this.delay+1900/1.25;this.incoming.setVisible(false);
  this.ball=add('entry-pb','pb').setOrigin(.5,.625).setVisible(false);
 }
 sound(at){this.playSound('entry-release',at);}
 advance(delta){
  this.elapsed+=delta;const t=this.elapsed;
  const tint=(base,a)=>base.setTint((Math.round(255-42*a)<<16)|(Math.round(255-214*a)<<8)|Math.round(255-214*a));
  const sine=p=>1-Math.cos(Math.min(1,Math.max(0,p))*Math.PI/2);
  if(this.outgoing){
   if(!this.recalled){this.recalled=true;this.sound(0);}
   const p=Math.min(1,t/250);this.outgoing.setScale(1-.5*sine(p));tint(this.outgoing.base,sine(p));
   if(t>=250)this.outgoing.setVisible(false);
  }
  const s=(t-this.delay)*1.25,p=this.incoming;
  if(s>=0&&s<650){
   const x=p.x-6,start=x+(p.own?-64:12),y=p.y-16;
   this.ball.setVisible(true).setX(start+(x-start)*Math.min(1,s/650));
   const startY=y-(p.own?52:42),peakY=y-(p.own?62:52);
   this.ball.setY(s<=150?startY+(peakY-startY)*(1-(1-s/150)**3):peakY+(y-peakY)*((s-150)/500)**3);
   this.ball.setAngle(s<=150?0:1440*(s-150)/500);
  }
  if(s>=650){
   if(!this.released){this.released=true;this.ball.setVisible(false);this.sound(this.delay+650/1.25);p.setVisible(true);}
   const growth=Math.min(1,(s-650)/250);p.setScale(.5+.5*sine(growth));
   if(growth<1)tint(p.base,1-sine(growth));else p.base.clearTint();
   // Seventeen staggered particles, eight radial directions, 16 fps, original 575 ms life.
   for(let i=0;i<17;i++){
    const age=s-650-(i+1)*20;
    if(age<0)continue;
    let particle=this.particles[i];
    if(!particle){particle=this.add('entry-particles','0.png');this.particles[i]=particle;}
    if(age>=575){particle.setVisible(false);continue;}
    const a=(i+1)*45*Math.PI/180,r=48*age/575;
    particle.setPosition(p.x+r*Math.cos(a),p.y-16+r*Math.sin(a));
    particle.setFrame(((i+4+Math.floor(age*16/1000))%4)+'.png');
    particle.setAlpha(age<500?1:1-sine((age-500)/75));
   }
  }
  this.phase=t<this.delay?'recall':s<650?'throw':s<900?'release':'settle';
  return t>=this.duration;
 }
 inspect(){return {elapsed:this.elapsed,duration:this.duration,phase:this.phase,recall:this.recall,
  incomingVisible:this.incoming.visible,outgoingVisible:this.outgoing?.visible??false,
  scale:this.incoming.scaleX,ball:{x:this.ball.x,y:this.ball.y,angle:this.ball.angle,visible:this.ball.visible},
  particles:this.particles.filter(p=>p.visible).length};}
}
