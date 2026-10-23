// Host viewport adaptation; pinned PokéRogue timelines and runtime stay untouched.
const viewportMatrices=new WeakMap();
export function renderTimedSurface(object, render, args, viewport) {
 let matrix=viewportMatrices.get(viewport);
 if(!matrix){
  const scale=Math.max(viewport.width/320,viewport.height/180);
  matrix=new window.Phaser.GameObjects.Components.TransformMatrix(scale,0,0,scale,
      (viewport.width-320*scale)/2,(viewport.height-180*scale)/2);
  viewportMatrices.set(viewport,matrix);
 }
 // Replace only the parent camera matrix. Authored positions, scales and tween
 // values stay untouched, without Float32 cancellation against the actor scale.
 const mapped=[...args];mapped[3]=matrix;
 return render.apply(object,mapped);
}

export function adaptTimedBackgrounds(config, owner) {
 const add='AnimTimedAddBgEvent',update='AnimTimedUpdateBgEvent';
 const frames=[...config.frameTimedEvents.entries()].sort((a,b)=>a[0]-b[0]);
 for(const [,events]of frames){
  // Some exported animations put their fade-in before creation in the same frame.
  // Execute creation first without changing that frame's authored clock.
  events.sort((a,b)=>(a.getEventType()===add?0:1)-(b.getEventType()===add?0:1));
 }
 const events=frames.flatMap(([,events])=>events).filter(e=>[add,update].includes(e.getEventType()));
 for(let i=0;i<events.length;i++){
  const event=events[i];if(event.getEventType()!==update)continue;
  const before=events.slice(0,i).reverse();
  const start=before.findIndex(e=>e.getEventType()===add);
  const after=events.slice(i+1),end=after.findIndex(e=>e.getEventType()===add);
  const segment=[...before.slice(0,start<0?before.length:start),event,...after.slice(0,end<0?after.length:end)];
  const moving=(event.bgX??0)!==0||(event.bgY??0)!==0;
  // Exported scrolling commands carry opacity=0 even while a separate fade is active.
  // Preserve that fade until the explicit fade-out, or the final scrolling fade-out.
  const separateFade=segment.some(e=>e!==event&&e.opacity===0&&(e.bgX??0)===0&&(e.bgY??0)===0);
  const laterFade=after.slice(0,end<0?after.length:end).some(e=>e.opacity===0);
  const movementOnly=moving&&event.opacity===0&&(separateFade||laterFade);
  event.execute=animation=>{
   const props={};
   if(moving||event.opacity===undefined){
    if(event.bgX!==undefined)props.x=event.bgX*.5-320;
    if(event.bgY!==undefined)props.y=event.bgY*.5-284;
   }
   if(event.opacity!==undefined&&!movementOnly)props.alpha=event.opacity/255;
   owner.tweens.add({targets:animation.bgSprite,duration:event.duration*50,...props});
   return event.duration*2;
  };
 }
}
