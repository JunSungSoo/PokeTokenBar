const {test}=require('node:test'),assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
const root=path.resolve(__dirname,'../../Sources/PokeTokenBar/Resources/PokeRoguePlayer');
test('weather normal-hit feedback blinks only its actor at the original 100ms cadence',async()=>{
 const {WeatherHitAnimation}=await import('data:text/javascript;base64,'+fs.readFileSync(path.join(root,'weather-hit-player.js')).toString('base64'));
 let sounds=0;const base={visible:true,setVisible(value){this.visible=value;}};
 const animation=new WeatherHitAnimation({actor:{key:'foe-1',base},playSound(){sounds++;}});
 assert.equal(base.visible,false);assert.equal(animation.done,false);
 for(const [i,visible]of [true,false,true,false,true].entries()){
  assert.equal(animation.advance(100),i===4);assert.equal(base.visible,visible);
 }
 assert.equal(sounds,1);assert.equal(animation.inspect().source,'foe-1');
 animation.advance(500);assert.equal(base.visible,true);assert.equal(sounds,1);
});
