const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../../Sources/PokeTokenBar/Resources/PokeRoguePlayer');
function object(){return {visible:true,scaleX:1,alpha:0,base:{height:80,pipelineData:{}},x:120,y:250,key:'own-0',setVisible(v){this.visible=v;return this;},setScale(v){this.scaleX=v;return this;},setAlpha(v){this.alpha=v;return this;},setPosition(x,y){this.x=x;this.y=y;return this;}};}
test('Mega preserves source phase timing, old/new visibility, particles and sound ownership',async()=>{
 const {MegaAnimation}=await import('data:text/javascript;base64,'+fs.readFileSync(path.join(root,'mega-player.js')).toString('base64'));
 for(const reducedMotion of [false,true]){
  const incoming=object(),outgoing=object(),sounds=[];incoming.cryInfo={key:'cry/6',duration:.8,rate:1};
  const a=new MegaAnimation({incoming,outgoing,addParticle:object,addBackdrop:object,playSound:(key,at)=>sounds.push([key,at]),reducedMotion});
  assert.equal(incoming.visible,false);a.advance(500);assert.equal(outgoing.visible,true);assert.equal(incoming.visible,false);
  assert.equal(a.inspect().particles>0,!reducedMotion);assert(a.backdrop.alpha>0);
  a.advance(1675);assert.equal(a.inspect().phase,'transform');assert.equal(incoming.visible,true);assert.equal(incoming.scaleX,.25);
  a.advance(250);assert.equal(outgoing.visible,false);assert.equal(incoming.scaleX,1);assert.equal(a.inspect().phase,'gather');
  a.advance(500);assert(a.flash.alpha>0);a.advance(1200);assert.equal(a.inspect().phase,'cry');
  assert.equal(a.advance(924),false);assert.equal(a.advance(1),true);
  assert.equal(incoming.visible,true);assert.equal(outgoing.visible,false);assert.equal(incoming.scaleX,1);assert.deepEqual(incoming.base.pipelineData.tone,[0,0,0,0]);
  const expected=reducedMotion?['mega-shine','cry/6']:['mega-charge','mega-beam','mega-sparkle','mega-shine','cry/6'];
  assert.deepEqual(sounds.map(x=>x[0]),expected);a.advance(1000);assert.equal(sounds.length,expected.length);assert.equal(a.inspect().speed,2);assert.equal(sounds.find(x=>x[0]==='mega-shine')[1],2875);
 }
});
test('2x visuals do not truncate the original-pitch sound tail',async()=>{
 const {MegaAnimation}=await import('data:text/javascript;base64,'+fs.readFileSync(path.join(root,'mega-player.js')).toString('base64'));
 const a=new MegaAnimation({incoming:object(),outgoing:object(),addParticle:object,addBackdrop:object,playSound(){},audioTail:5341});
 assert.equal(a.advance(4250),false);assert.equal(a.inspect().phase,'cry');
 assert.equal(a.advance(1090),false);assert.equal(a.advance(1),true);
});
