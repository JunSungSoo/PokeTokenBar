'use strict';
const {test}=require('node:test'),assert=require('node:assert/strict');
const {fixtures}=require('./fixtures/targetless-moves.cjs');
test('Explosion and Self-Destruct do not animate a queued attack with no living target',()=>{
 const cases=fixtures();assert.equal(Object.keys(cases).length,12);
 for(const [key,{frames,pp}]of Object.entries(cases))for(const [player,frame]of frames.entries()){
  const ownSource=effect=>effect.source.own===(player===0)&&effect.source.slot===0;
  if(key.endsWith('-retarget')){
   const attack=frame.effects.find(e=>e.moveID==='thunderbolt'&&ownSource(e));
   assert(attack,key);assert.deepEqual(attack.targets,[{position:{own:player===1,slot:1},hit:true}]);
  }else if(key.endsWith('-recover')){
   assert(frame.effects.some(e=>e.moveID==='recover'&&ownSource(e)),key);
   assert(frame.log.some(l=>l.startsWith('|-heal|p1a: Smeargle|')),key);
  }else{
   assert(!frame.effects.some(e=>e.moveID==='thunderbolt'&&ownSource(e)),key);
   if(key.endsWith('-ko')){
    assert(!frame.log.some(l=>l.startsWith('|move|p1a:')),key);assert.equal(pp.after,pp.before);
   }else{
    assert(frame.log.some(l=>l.startsWith('|move|p1a:')&&l.includes('[notarget]')),key);
    assert.equal(pp.after,pp.before-1,'Engine-authoritative failure PP must not be refunded');
   }
  }
  assert(frame.effects.some(e=>['explosion','selfdestruct'].includes(e.moveID)),key);
 }
});
