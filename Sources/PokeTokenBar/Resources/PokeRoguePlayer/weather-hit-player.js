// DamageAnimPhase normal-hit cadence, explicitly enabled for weather INDIRECT damage.
export class WeatherHitAnimation {
 constructor({actor,playSound}){this.actor=actor;this.elapsed=0;this.duration=500;this.done=false;playSound();this.actor.base.setVisible(false);}
 advance(delta){
  this.elapsed+=delta;this.done=this.elapsed>=this.duration;
  this.actor.base.setVisible(this.done||Math.floor(this.elapsed/100)%2===1);
  return this.done;
 }
 inspect(){return {source:this.actor.key,elapsed:this.elapsed,visible:this.actor.base.visible,done:this.done};}
}
