const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
function team(prefix,speed=100,hp=500,moves=['dragonrage']) {
 return [['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']].map(([species,ability],i)=>({
  id:prefix+i,species,ability,moves,level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp,atk:100,def:100,spa:100,spd:100,spe:speed}}));
}
function command(e,p,actions){e.choose(p,e.frame(p).decisionID,actions);}
function move(index=1,target=0){return {kind:'move',index,target};}
function line(f,s){return f.log[s.id-f.logOffset];}
function recent(e,p,last){const f=e.frame(p);return [f,f.scenes.filter(s=>s.id>last)];}
function last(e){return e.frame(0).scenes.at(-1)?.id??-1;}
test('each attack retains pre-hit state, then only its own damage before the second action, in both perspectives/modes',()=>{
 for(const mode of ['singles','doubles']){
 const e=new OwnedBattle(mode,[team('a',200),team('b',80)],[1,2,3,4]);const before=last(e);
 const actions=mode==='singles'?[move()]:[move(1,1),move(1,2)];
 command(e,0,actions);command(e,1,actions);
 for(const p of [0,1]){
  const [f,scenes]=recent(e,p,before);const attacks=scenes.filter(s=>line(f,s).startsWith('|move|'));
  assert.equal(attacks.length,mode==='singles'?2:4);
  assert.equal(attacks[0].own[0].hp,500);assert.equal(attacks[0].foe[0].hp,100);
  const firstDamage=scenes.find(s=>line(f,s).startsWith('|-damage|'));
  if(p===0){assert.equal(firstDamage.foe[0].hp,92);assert.equal(firstDamage.own[0].hp,500);}
  else {assert.equal(firstDamage.own[0].hp,460);assert.equal(firstDamage.foe[0].hp,100);}
  for(const s of scenes) for(const foe of s.foe){assert.equal(foe.stats,undefined);assert.equal(foe.ability,undefined);assert.equal(foe.boosts,undefined);assert.equal(foe.maxHP,100);}
  assert.ok(Buffer.byteLength(JSON.stringify(f))<1024*1024);
 }
 }
});
test('switch snapshot changes species before the incoming Pokémon takes the attack, not before the switch',()=>{
 const e=new OwnedBattle('singles',[team('a',50),team('b',200)],[1,2,3,4]);const before=last(e);
 command(e,0,[{kind:'switch',index:2}]);command(e,1,[move()]);
 const [f,scenes]=recent(e,0,before);const swap=scenes.find(s=>line(f,s).startsWith('|switch|'));
 assert.equal(swap.own.find(p=>p.active).id,'a1');assert.equal(swap.own.find(p=>p.active).hp,500);
 const attack=scenes.find(s=>line(f,s).startsWith('|move|'));
 assert.ok(swap.id<attack.id);assert.equal(attack.own.find(p=>p.active).hp,500);
 const damage=scenes.find(s=>line(f,s).startsWith('|-damage|'));
 assert.equal(damage.own.find(p=>p.active).hp,460);
});
test('voluntary switching precedes even priority attacks regardless of speed and Trick Room in both modes',()=>{
 for(const mode of ['singles','doubles'])for(const room of [false,true])for(const speed of [50,250]){
  const own=team('a',speed,500,['amnesia']);own[2].ability='Lightning Rod';
  const e=new OwnedBattle(mode,[own,team('b',200,500,['quickattack'])],[1,2,3,4]);
  if(room)e.battle.field.addPseudoWeather('trickroom',e.battle.sides[0].active[0]);
  const before=last(e),incoming=mode==='singles'?2:3;
  command(e,0,mode==='singles'?[{kind:'switch',index:incoming}]:[{kind:'switch',index:incoming},move()]);
  command(e,1,mode==='singles'?[move()]:[move(1,1),move(1,2)]);
  for(const player of [0,1]){
   const [f,scenes]=recent(e,player,before);
   const swap=scenes.find(s=>line(f,s).startsWith('|switch|'));
   const attacks=scenes.filter(s=>line(f,s).startsWith('|move|'));
   assert.ok(swap && attacks.length>0);
   assert.ok(attacks.every(s=>swap.id<s.id),`${mode}: switching must finish before moves, room=${room}, speed=${speed}`);
   const members=player===0?swap.own:swap.foe;
   assert.equal(members[0].id,'a'+(incoming-1));
   assert.equal(members[0].hp,player===0?500:100,'incoming Pokémon is unharmed at the switch event');
  }
 }
});
test('Trick Room state begins at its event; subsequent equal-priority attacks reverse speed order',()=>{
 const e=new OwnedBattle('singles',[team('a',50,500,['trickroom','dragonrage']),team('b',200,500,['amnesia','dragonrage'])],[1,2,3,4]);
 let before=last(e);command(e,0,[move()]);command(e,1,[move()]);
 let [f,scenes]=recent(e,0,before);const room=scenes.find(s=>line(f,s).startsWith('|-fieldstart|'));
 assert.ok(room.field.conditions.includes('trickroom'));assert.ok(scenes.filter(s=>s.id<room.id).every(s=>!s.field.conditions.includes('trickroom')));
 before=last(e);command(e,0,[move(2)]);command(e,1,[move(2)]);
 [f,scenes]=recent(e,0,before);assert.ok(line(f,scenes.find(s=>line(f,s).startsWith('|move|'))).includes('p1a:'));
});
test('a knockout cancels the defeated move, requests a legal replacement, and ends only when the selected team is gone',()=>{
 for(const mode of ['singles','doubles']){
 const e=new OwnedBattle(mode,[team('a',200,40),team('b',50,40)],[1,2,3,4]);
 let guard=0;
 while(!e.frame(0).ended && guard++<12){
  const before=last(e);
  for(const p of [0,1]){
   const f=e.frame(p);if(f.waiting)continue;
   const used=new Set();const actions=f.slots.map(slot=>{
    if(slot.canPass)return {kind:'pass'};
    if(slot.mustSwitch){const index=f.own.findIndex((m,i)=>!m.active&&!m.fainted&&!used.has(i));assert.ok(index>=0);used.add(index);return {kind:'switch',index:index+1};}
    return move(1,mode==='doubles'?(f.foe.findIndex(m=>!m.fainted)+1):0);
   });command(e,p,actions);
  }
  const [f,scenes]=recent(e,0,before);
  const faint=scenes.find(s=>line(f,s).startsWith('|faint|'));
  if(faint){assert.ok(faint.foe.some(p=>p.hp===0&&p.fainted));assert.ok(!f.effects.filter(m=>m.id>before).some(m=>!m.source.own),'KO before the slower action must cancel it');}
  for(const slot of e.frame(1).slots.filter(s=>s.mustSwitch))assert.ok(e.frame(1).own.some(p=>!p.active&&!p.fainted));
 }
 assert.ok(e.frame(0).ended);assert.equal(e.frame(0).winner,0);assert.ok(e.frame(1).own.every(p=>p.fainted));
 }
});
test('bounded snapshots survive log rollover without retaining private or unbounded history',()=>{
 const e=new OwnedBattle('doubles',[team('a',200,500,['growl']),team('b',80,500,['growl'])],[1,2,3,4]);
 for(let i=0;i<35;i++)for(const p of [0,1])command(e,p,[move(),move()]);
 for(const p of [0,1]){const f=e.frame(p);assert.ok(f.logOffset>0);assert.ok(f.scenes.length<=160);assert.ok(f.scenes.every(s=>s.id>=f.logOffset));assert.ok(Buffer.byteLength(JSON.stringify(f))<1024*1024);}
});
