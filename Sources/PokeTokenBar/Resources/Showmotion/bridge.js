// Native integration only: original Showmotion effect assets, camera, bloom and WASM runtime.
const runtime=window.ptbShowmotion;
const stage=document.querySelector('#stage');
const scene={$battle:[stage],$sprite:[document.querySelector('#sprites')],$stat:[document.querySelector('#stats')]};
const room={battle:{scene}};
const effectIDs=new Set(['swordsdance','moonblast','mysticalfire','shadowball','willowisp','psychic','hydropump','gunkshot','flowertrick']);
window.ptbStop=()=>{
 runtime.paused=true;window.pksEffekseer?.stopAll();
 for(const ctx of runtime.contexts)ctx.stopAllEffects();
};
const ready=(async()=>{
 if(!navigator.gpu)throw Error('WebGPU unavailable');
 await window.init3DScene(stage,room);
 if(!window.pksEffekseer||runtime.contexts.length!==2)throw Error('Original Showmotion renderer did not initialize');
 ptbPost({kind:'ready'});
})().catch(error=>ptbPost({kind:'unavailable',message:String(error)}));
window.ptbPlay=async payload=>{
 try{
  await ready;
  if(!effectIDs.has(payload.moveID)||!window.pksEffekseer)throw Error('Original effect unavailable');
  // Upstream suspends effects briefly after the WebView becomes visible.
  const resumeDeadline=performance.now()+3000;
  while(window.pksEffekseer.isSuspended()&&performance.now()<resumeDeadline)
   await new Promise(resolve=>setTimeout(resolve,25));
  if(document.hidden||window.pksEffekseer.isSuspended())throw Error('Effect surface is not visible');
  ptbStop();runtime.handles=[];
  // Preserve the original camera and animation. The effect-only stage is anchored to the participants.
  stage.style.width='640px';stage.style.height='360px';
  const own=payload.own,foe=payload.foe;
  if(own&&foe){
   // Projected original camera anchors. Hydro Pump's nozzle is in front of its caster.
   const near=payload.moveID==='hydropump'?{x:263.8134,y:239.5487}:{x:217.6465,y:266.6360};
   const far={x:441.7500,y:135.1487};
   const sx=Math.max(0.3,Math.abs(foe.x-own.x)/(far.x-near.x)),sy=Math.max(0.3,Math.abs(own.y-foe.y)/(near.y-far.y));
   stage.style.transformOrigin='0 0';
   stage.style.transform=`matrix(${sx},0,0,${sy},${own.x-near.x*sx},${own.y-near.y*sy})`;
  }
  const base=new URL(`libs/effects/${payload.moveID}/`,location.href).href;
  runtime.paused=false;runtime.timer?.reset?.();runtime.resume?.();
  const pair={foreground:base+payload.moveID+'.efkwgd',
   background:payload.moveID==='moonblast'?base+'moonblast_bg.efkwgd':undefined,
   position:[0,0,0],rotation:payload.ownSource?[0,0,0]:[0,180,0]};
  await window.pksEffekseer.playPair(pair);
  // The first WebView visibility transition can invalidate the upstream loading epoch.
  // Retry the now-cached asset once after the upstream resume suppression has elapsed.
  if(!runtime.handles.length&&!document.hidden){
   await new Promise(resolve=>setTimeout(resolve,1100));
   await window.pksEffekseer.playPair(pair);
  }
  if(!runtime.handles.length)throw Error('Original Showmotion effect did not create a handle');
  const start=performance.now();let particles=0,draws=0,lastDraw=start;
  let finished=false,announced=false;
  const finish=()=>{
   if(finished)return;finished=true;document.removeEventListener('visibilitychange',hidden);
   ptbStop();ptbPost({kind:'finished',id:payload.id,particles,draws,played:particles>0&&draws>0});
  };
  const hidden=()=>{if(document.hidden)finish();};
  document.addEventListener('visibilitychange',hidden);
  const monitor=()=>{
   if(finished)return;
   const currentDraws=Math.max(...runtime.contexts.map(c=>c.getDrawCallCount()));
   particles=Math.max(particles,...runtime.contexts.map(c=>c.getTotalParticleCount()));
   draws=Math.max(draws,currentDraws);
   if(!announced&&particles>0&&draws>0){announced=true;ptbPost({kind:'started',id:payload.id});}
   if(currentDraws>0)lastDraw=performance.now();
   if(performance.now()-start<9000&&performance.now()-lastDraw<600&&runtime.handles.some(handle=>handle.exists))requestAnimationFrame(monitor);
   else finish();
  };
  requestAnimationFrame(monitor);
 }catch(error){ptbStop();ptbPost({kind:'failed',id:payload.id,message:String(error)});}
};
