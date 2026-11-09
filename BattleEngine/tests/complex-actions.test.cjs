const {test}=require('node:test'),assert=require('node:assert/strict');
const {fixtures}=require('./fixtures/complex-actions.cjs');
const cases=fixtures();
function changes(match,p){const f=match.resolved[p],last=match.initial[p].scenes.at(-1).id;return f.scenes.filter(s=>s.id>last).map(s=>({scene:s,line:f.log[s.id-f.logOffset]}));}
for(const mode of ['singles','doubles']){
 test(`${mode}: each Skill Link strike has its own immutable HP checkpoint in both perspectives`,()=>{
  const m=cases[mode+'-multi'];
  for(const p of [0,1]){
   const hits=changes(m,p).filter(s=>s.line.startsWith('|-damage|p2a:'));
   assert.equal(hits.length,5);
   const hp=hits.map(({scene:s})=>p===0?s.foe[0].hp:s.own[0].hp);
   assert.ok(hp.every((v,i)=>i===0||v<hp[i-1]));
   const count=changes(m,p).find(s=>s.line.startsWith('|-hitcount|'));
   assert.ok(count.scene.id>hits.at(-1).scene.id);
  }
 });
 test(`${mode}: drain and recoil keep target damage before user HP changes and the next action`,()=>{
  for(const kind of ['drain','recoil'])for(const p of [0,1]){
   const m=cases[mode+'-'+kind],events=changes(m,p),damage=events.find(s=>s.line.startsWith('|-damage|p2a:'));
   const ownChange=events.find(s=>s.line.startsWith(kind==='drain'?'|-heal|p1a:':'|-damage|p1a:'));
   const user=s=>p===0?s.own[0]:s.foe[0];
   assert.equal(user(damage.scene).hp,user(m.initial[p]).hp);
   assert.ok(damage.scene.id<ownChange.scene.id);
   assert.ok(kind==='drain'?user(ownChange.scene).hp>user(damage.scene).hp:user(ownChange.scene).hp<user(damage.scene).hp);
   const counter=events.find(s=>s.line.startsWith('|move|p2a:'));
   assert.ok(ownChange.scene.id<counter.scene.id);
  }
 });
 test(`${mode}: Protect prevents damage; recoil and direct knockouts stop invalid counterattacks`,()=>{
  for(const p of [0,1])assert.equal(changes(cases[mode+'-guard'],p).filter(s=>s.line.startsWith('|-damage|')).length,0);
  for(const kind of ['recoilKO','knockout','residualKO']){
   const m=cases[mode+'-'+kind],f=m.resolved[0],who=kind!=='knockout'?'p1a:':'p2a:';
   assert.ok(changes(m,0).some(s=>s.line.startsWith('|faint|'+who)));
   const defeatedOwn=kind!=='knockout';
   if(kind==='knockout')assert.ok(!f.effects.some(s=>s.id>m.initial[0].scenes.at(-1).id&&!s.source.own&&s.source.slot===0));
   assert.ok(m.resolved[defeatedOwn?0:1].slots.some(s=>s.mustSwitch));
  }
 });
 test(`${mode}: end-turn weather and status damage remain distinct and follow actions`,()=>{
  const m=cases[mode+'-residual'];
  for(const p of [0,1]){
   const events=changes(m,p),damage=events.filter(s=>s.line.startsWith('|-damage|'));
   const lastAction=Math.max(...events.filter(s=>s.line.startsWith('|move|')).map(s=>s.scene.id));
   assert.ok(damage.every(s=>s.scene.id>lastAction));
   assert.ok(damage.some(s=>s.line.includes('[from] Sandstorm')));
   assert.ok(damage.some(s=>s.line.includes('[from] psn')));
   assert.ok(damage.some(s=>s.line.includes('[from] brn')));
   const own=damage.filter(s=>s.line.startsWith('|-damage|p1a:'));
   assert.equal(own.length,2);
   assert.ok(own[0].scene.id<own[1].scene.id);
  }
 });
}
