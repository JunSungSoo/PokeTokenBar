const {test}=require('node:test');
const assert=require('node:assert/strict');
const {Dex}=require('pokemon-showdown');
const {OwnedBattle,validateTeam}=require('../engine.cjs');
const dex=Dex.mod('gen5');
const stats={hp:143,atk:91,def:87,spa:96,spd:89,spe:107};
function mon(species,ability,moves=['splash'],overrides={}) {
 return {species,ability,moves,level:50,nature:'Hardy',ivs:Object.fromEntries(Object.keys(stats).map(k=>[k,17])),stats:{...stats,hp:dex.species.get(species).num===292?1:143},...overrides};
}
const fillers=[['Smeargle','Own Tempo'],['Snorlax','Immunity'],['Blissey','Natural Cure'],['Raichu','Static'],['Scizor','Technician'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo']];
function team(prefix,first,second=null) {
 const result=[first,...(second?[second]:[])];
 for(const [s,a]of fillers)if(result.length<6&&!result.some(p=>dex.species.get(p.species).num===dex.species.get(s).num))result.push(mon(s,a));
 return result.map((p,i)=>({...p,id:prefix+i}));
}
function battle(mode,own=mon('Smeargle','Own Tempo'),foe=mon('Snorlax','Immunity'),ally=null,foeAlly=null) {
 return new OwnedBattle(mode,[team('a',own,ally),team('b',foe,foeAlly)],[1,2,3,4]);
}
function turn(e,a=1,b=1) {
 for(const [p,index]of [[0,a],[1,b]]) {
  const f=e.frame(p);
  e.choose(p,f.decisionID,f.slots.map((s,i)=>({kind:'move',index:i===0?index:1,target:s.moves[(i===0?index:1)-1].targetRequired?1:0})));
 }
}
function damage(e,move,source=0,target=1) {
 e.battle.prng.setSeed('1,2,3,4');
 return e.battle.actions.getDamage(e.battle.sides[source].active[0],e.battle.sides[target].active[0],{...e.battle.dex.getActiveMove(move),willCrit:false},true);
}
test('all 164 generation-V abilities remain in the engine; every non-item-dependent ability initializes in bring-six singles and doubles',()=>{
 const abilities=dex.abilities.all().filter(a=>a.exists&&a.num>0&&a.gen<=5);
 assert.equal(abilities.length,164);
 const species=dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5);
 let initialized=0;
 for(const a of abilities) {
  const s=species.find(s=>s.num!==493&&Object.values(s.abilities).includes(a.name));
  if(!s) { assert.equal(a.id,'multitype');assert.throws(()=>validateTeam(team('x',mon('Arceus',a.name)),6),/held item/);continue; }
  for(const mode of ['singles','doubles']) {
   const e=battle(mode,mon(s.name,a.name));
   const p=e.battle.sides[0].pokemon[0];
   assert.equal(p.baseAbility,a.id,`${mode} ${a.id}`);
   assert.equal(e.frame(0).own.length,mode==='singles'?3:4);assert.equal(e.frame(1).own.length,mode==='singles'?3:4);
   assert.equal(e.errors.length,0,`${mode} ${a.id}`);initialized++;
  }
 }
 assert.equal(initialized,326);
 // These abilities have no in-battle effect in BW2; do not import later-generation buffs.
 for(const id of ['runaway','honeygather','illuminate'])assert.ok(!Object.entries(dex.abilities.get(id)).some(([k,v])=>k.startsWith('on')&&typeof v==='function'),id);
});
test('weather setters, weather speed abilities and suppression use BW2 behavior in both modes',()=>{
 const cases=[['Ludicolo','Swift Swim','Politoed','Drizzle','raindance'],['Venusaur','Chlorophyll','Ninetales','Drought','sunnyday'],['Stoutland','Sand Rush','Tyranitar','Sand Stream','sandstorm']];
 for(const mode of ['singles','doubles'])for(const [s,a,f,fa,w]of cases) {
  const e=battle(mode,mon(s,a),mon(f,fa));
  assert.equal(e.frame(0).field.weather,w);assert.equal(e.battle.sides[0].active[0].getStat('spe'),214);
  assert.deepEqual(e.frame(0).field,e.frame(1).field);
  assert.equal(e.battle.field.weatherState.duration,0,'Gen V ability weather is permanent');
 }
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Rayquaza','Air Lock'),mon('Politoed','Drizzle'));
  assert.equal(e.frame(0).field.weather,'raindance');assert.equal(e.frame(0).field.weatherSuppressed,true);
  assert.equal(e.battle.field.effectiveWeather(),'');
 }
});
test('sun and rain modify actual Water/Fire damage and move-created weather expires',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Smeargle','Own Tempo',['rain-dance','sunny-day','splash']));
  const clearWater=damage(e,'water-gun'),clearFire=damage(e,'ember');
  turn(e,1);assert.equal(e.frame(0).field.weather,'raindance');
  assert.ok(damage(e,'water-gun')>clearWater);assert.ok(damage(e,'ember')<clearFire);
  turn(e,2);assert.equal(e.frame(0).field.weather,'sunnyday');
  assert.ok(damage(e,'water-gun')<clearWater);assert.ok(damage(e,'ember')>clearFire);
  for(let i=0;i<5;i++)turn(e,3);
  assert.equal(e.frame(0).field.weather,'');
 }
});
test('sand/hail residuals, Magic Guard immunity, rain healing and Hydration actually resolve',()=>{
 for(const mode of ['singles','doubles']) {
  for(const [species,ability,weather]of [['Tyranitar','Sand Stream','sandstorm'],['Abomasnow','Snow Warning','hail']]) {
   const e=battle(mode,mon('Snorlax','Immunity'),mon(species,ability));turn(e);
   assert.equal(e.frame(0).field.weather,weather);assert.equal(e.frame(0).own[0].hp,143-Math.floor(143/16));
   assert.equal(e.frame(1).own[0].hp,143);
   for(const [immuneSpecies,immuneAbility] of [['Clefable','Magic Guard'],['Mandibuzz','Overcoat']]) {
    const guard=battle(mode,mon(immuneSpecies,immuneAbility),mon(species,ability));turn(guard);
    assert.equal(guard.frame(0).own[0].hp,143);
   }
  }
  for(const [s,a,denominator]of [['Ludicolo','Rain Dish',16],['Parasect','Dry Skin',8]]) {
   const e=battle(mode,mon(s,a),mon('Politoed','Drizzle'));e.battle.sides[0].active[0].hp=70;turn(e);
   assert.equal(e.frame(0).own[0].hp,70+Math.floor(143/denominator));
  }
  const hydration=battle(mode,mon('Vaporeon','Hydration'),mon('Politoed','Drizzle'));
  hydration.battle.sides[0].active[0].setStatus('par');turn(hydration);assert.equal(hydration.frame(0).own[0].status,'');
 }
});
test('Levitate, Mold Breaker, Water Absorb, Volt Absorb, Flash Fire and Sap Sipper are functional',()=>{
 for(const mode of ['singles','doubles']) {
  const ordinary=battle(mode,mon('Pinsir','Hyper Cutter'),mon('Flygon','Levitate'));
  const breaker=battle(mode,mon('Pinsir','Mold Breaker',['earthquake']),mon('Flygon','Levitate'));
  assert.equal(damage(ordinary,'earthquake'),false);turn(breaker);assert.ok(breaker.frame(1).own[0].hp<143);
  for(const [species,ability,move]of [['Vaporeon','Water Absorb','water-gun'],['Jolteon','Volt Absorb','thunder-shock'],['Arcanine','Flash Fire','ember'],['Sawsbuck','Sap Sipper','vine-whip']]) {
   const e=battle(mode,mon('Smeargle','Own Tempo',[move]),mon(species,ability));
   e.battle.sides[1].active[0].hp=70;turn(e);
   if(['Water Absorb','Volt Absorb'].includes(ability))assert.equal(e.frame(1).own[0].hp,70+Math.floor(143/4));
   else assert.equal(e.frame(1).own[0].hp,70);
   if(ability==='Flash Fire')assert.ok(e.battle.sides[1].active[0].volatiles.flashfire);
   if(ability==='Sap Sipper')assert.equal(e.frame(1).own[0].boosts.atk,1);
  }
 }
});
test('Huge Power, Technician, Thick Fat, Prankster and Lightning Rod modify real combat',()=>{
 for(const mode of ['singles','doubles']) {
  const huge=battle(mode,mon('Azumarill','Huge Power')),normal=battle(mode,mon('Azumarill','Thick Fat'));
  assert.ok(damage(huge,'tackle')>damage(normal,'tackle'));
  const tech=battle(mode,mon('Scizor','Technician')),swarm=battle(mode,mon('Scizor','Swarm'));
  assert.ok(damage(tech,'bullet-punch')>damage(swarm,'bullet-punch'));
  const fat=battle(mode,mon('Smeargle','Own Tempo'),mon('Snorlax','Thick Fat')),immune=battle(mode,mon('Smeargle','Own Tempo'),mon('Snorlax','Immunity'));
  assert.ok(damage(fat,'ice-beam')<damage(immune,'ice-beam'));
  const priority=battle(mode,mon('Whimsicott','Prankster',['growl'],{stats:{...stats,spe:1}}),mon('Snorlax','Immunity',['splash'],{stats:{...stats,spe:200}}));turn(priority);
  assert.match(priority.frame(0).log.find(l=>l.startsWith('|move|')),/Whimsicott/);
 }
 const rod=battle('doubles',mon('Smeargle','Own Tempo',['thunderbolt']),mon('Snorlax','Immunity'),null,mon('Raichu','Lightning Rod'));
 turn(rod);assert.equal(rod.frame(1).own[0].hp,143);assert.equal(rod.frame(1).own[1].boosts.spa,1);
});
test('Trick Room reverses move order and expires; Gravity grounds Levitate targets',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Smeargle','Own Tempo',['trick-room','tackle','splash'],{stats:{...stats,spe:200}}),mon('Snorlax','Immunity',['splash'],{stats:{...stats,spe:1}}));
  turn(e,1);assert.ok(e.frame(0).field.conditions.includes('trickroom'));
  const before=e.frame(0).log.length;turn(e,2);
  assert.match(e.frame(0).log.slice(before).find(l=>l.startsWith('|move|')),/Snorlax/);
  for(let i=0;i<5;i++)turn(e,3);assert.ok(!e.frame(0).field.conditions.includes('trickroom'));
  const gravity=battle(mode,mon('Smeargle','Own Tempo',['gravity']),mon('Flygon','Levitate'));
  assert.equal(damage(gravity,'earthquake'),false);turn(gravity);
  assert.ok(gravity.frame(0).field.conditions.includes('gravity'));assert.ok(damage(gravity,'earthquake')>0);
 }
});
test('Reflect/Light Screen, Tailwind, hazards and room states are applied and synchronized by side',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Smeargle','Own Tempo',['reflect','light-screen','tailwind','stealth-rock']));
  const physical=damage(e,'tackle',1,0),special=damage(e,'water-gun',1,0);
  turn(e,1);assert.ok(damage(e,'tackle',1,0)<physical);
  turn(e,2);assert.ok(damage(e,'water-gun',1,0)<special);
  turn(e,3);assert.equal(e.battle.sides[0].active[0].getStat('spe'),214);
  turn(e,4);
  assert.ok(e.frame(0).field.ownSide.some(c=>c.id==='tailwind'));
  assert.ok(e.frame(1).field.foeSide.some(c=>c.id==='tailwind'));
  assert.ok(e.frame(0).field.foeSide.some(c=>c.id==='stealthrock'));
  const f=e.frame(1);e.choose(1,f.decisionID,f.slots.map((s,i)=>i===0?{kind:'switch',index:3}:{kind:'move',index:1,target:0}));
  const a=e.frame(0);e.choose(0,a.decisionID,a.slots.map(()=>({kind:'move',index:1,target:0})));
  assert.ok(e.frame(1).own.find(p=>p.active&&p.id==='b2').hp<143,'Entry hazard must deal damage');
  for(const move of ['magic-room','wonder-room']) {
   const room=battle(mode,mon('Smeargle','Own Tempo',[move]));turn(room);
   assert.ok(room.frame(0).field.conditions.includes(move.replace('-','')));
  }
 }
});
test('Illusion keeps the opposing species disguised until a real hit reveals it',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Zoroark','Illusion'),mon('Smeargle','Own Tempo',['tackle','psychic','soak']));
  const disguised=e.battle.sides[0].active[0].illusion;
  assert.ok(disguised);assert.equal(e.frame(1).foe[0].speciesID,disguised.species.num);
  assert.equal(e.frame(0).own[0].speciesID,571);
  assert.equal(e.frame(1).slots[0].moves[1].matchups[0].name,disguised.species.name);
  assert.equal(e.frame(1).slots[0].moves[1].matchups[0].multiplier,2**dex.getEffectiveness('Psychic',disguised),'Preview must compare visible disguise types, not reveal the hidden Dark type');
  if(mode==='doubles')assert.equal(e.frame(1).slots[0].moves[0].targets.find(t=>t.location===1).name.split(' · ')[1],disguised.species.name);
  turn(e,1,3);
  assert.equal(e.frame(1).foe[0].speciesID,disguised.species.num);
  assert.equal(e.frame(1).slots[0].moves[1].matchups[0].multiplier,1,'A public Soak type change remains visible while disguised');
  turn(e);assert.equal(e.frame(1).foe[0].speciesID,571);
 }
});
test('status immunity/cures, weather immunity, Sturdy and Wonder Guard use their real event hooks',()=>{
 for(const mode of ['singles','doubles']) {
  for(const [s,a,status]of [['Snorlax','Immunity','psn'],['Persian','Limber','par'],['Primeape','Vital Spirit','slp']]) {
   const e=battle(mode,mon(s,a));assert.equal(e.battle.sides[0].active[0].trySetStatus(status),false);
  }
  const cure=battle(mode,mon('Blissey','Natural Cure'));cure.battle.sides[0].active[0].setStatus('par');
  const old=cure.battle.sides[0].active[0];
  cure.choose(0,cure.frame(0).decisionID,cure.frame(0).slots.map((s,i)=>i===0?{kind:'switch',index:mode==='singles'?2:3}:{kind:'move',index:1,target:0}));
  cure.choose(1,cure.frame(1).decisionID,cure.frame(1).slots.map(()=>({kind:'move',index:1,target:0})));
  assert.equal(old.status,'');
  const sturdy=battle(mode,mon('Smeargle','Own Tempo',['dragon-rage']),mon('Donphan','Sturdy', ['splash'],{stats:{...stats,hp:20}}));
  turn(sturdy);assert.equal(sturdy.frame(1).own[0].hp,1);
  const wonder=battle(mode,mon('Smeargle','Own Tempo',['tackle','ember']),mon('Shedinja','Wonder Guard'));
  turn(wonder,1);assert.equal(wonder.frame(1).own[0].hp,1);
  turn(wonder,2);assert.equal(wonder.frame(1).own[0].fainted,true);
  const guard=battle(mode,mon('Tangrowth','Leaf Guard'),mon('Ninetales','Drought'));
  assert.equal(guard.battle.sides[0].active[0].trySetStatus('par'),false);
 }
});
test('Speed Boost, Magic Bounce, Imposter and Trace actually activate beyond initialization',()=>{
 for(const mode of ['singles','doubles']) {
  const speed=battle(mode,mon('Ninjask','Speed Boost'));turn(speed);assert.equal(speed.frame(0).own[0].boosts.spe,1);
  const bounce=battle(mode,mon('Smeargle','Own Tempo',['thunder-wave']),mon('Espeon','Magic Bounce'));
  turn(bounce);assert.equal(bounce.frame(0).own[0].status,'par');assert.equal(bounce.frame(1).own[0].status,'');
  const imposter=battle(mode,mon('Ditto','Imposter'),mon('Snorlax','Immunity'));
  assert.equal(imposter.battle.sides[0].active[0].transformed,true);
  assert.ok(imposter.battle.sides[1].active.some(p=>p.species.num===imposter.battle.sides[0].active[0].species.num));
  const trace=battle(mode,mon('Gardevoir','Trace'),mon('Snorlax','Immunity'),null,mon('Blissey','Natural Cure'));
  assert.ok(['immunity','naturalcure'].includes(trace.battle.sides[0].active[0].ability));
  assert.equal(trace.frame(0).own[0].ability,dex.abilities.get(trace.battle.sides[0].active[0].ability).name);
  assert.equal(trace.frame(0).foe[0].ability,undefined);
 }
});
test('Wonder Room swaps defensive calculations; suppressing weather disables and restores Swift Swim',()=>{
 for(const mode of ['singles','doubles']) {
  const room=battle(mode,mon('Smeargle','Own Tempo',['wonder-room'],{stats:{...stats,def:200,spd:20}}));
  const before=damage(room,'tackle',1,0);turn(room);
  assert.ok(damage(room,'tackle',1,0)>before);
  assert.equal(room.frame(0).own[0].stats.def,200,'Field mechanics must not rewrite owned base stats');
 }
 const e=battle('doubles',mon('Ludicolo','Swift Swim'),mon('Politoed','Drizzle'),mon('Rayquaza','Air Lock'));
 assert.equal(e.frame(0).field.weatherSuppressed,true);assert.equal(e.battle.sides[0].active[0].getStat('spe'),107);
 e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0},{kind:'switch',index:3}]);
 e.choose(1,e.frame(1).decisionID,e.frame(1).slots.map(()=>({kind:'move',index:1,target:0})));
 assert.equal(e.frame(0).field.weatherSuppressed,false);assert.equal(e.battle.sides[0].active[0].getStat('spe'),214);
});

test('silent Regenerator recovery is explained to its owner without revealing it to the opponent',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Slowbro','Regenerator'));
  e.battle.sides[0].active[0].hp=70;
  e.choose(0,e.frame(0).decisionID,e.frame(0).slots.map((s,i)=>i===0?{kind:'switch',index:mode==='singles'?2:3}:{kind:'move',index:1,target:0}));
  e.choose(1,e.frame(1).decisionID,e.frame(1).slots.map(()=>({kind:'move',index:1,target:0})));
  assert.ok(e.frame(0).log.some(l=>l.startsWith('|-heal|')&&l.includes('ability: Regenerator')));
  assert.ok(!e.frame(1).log.some(l=>l.includes('ability: Regenerator')));
  assert.equal(e.frame(0).own.find(p=>p.speciesID===80).hp,70+Math.floor(143/3));
 }
});

test('Regenerator explanation is not fabricated for active healing or full-health switching',()=>{
 for(const mode of ['singles','doubles']) {
  const active=battle(mode,mon('Slowbro','Regenerator',['slack-off']));active.battle.sides[0].active[0].hp=70;turn(active);
  assert.ok(active.frame(0).own[0].hp>70);
  assert.ok(!active.frame(0).log.some(l=>l.includes('ability: Regenerator')));
  const full=battle(mode,mon('Slowbro','Regenerator'));
  full.choose(0,full.frame(0).decisionID,full.frame(0).slots.map((s,i)=>i===0?{kind:'switch',index:mode==='singles'?2:3}:{kind:'move',index:1,target:0}));
  full.choose(1,full.frame(1).decisionID,full.frame(1).slots.map(()=>({kind:'move',index:1,target:0})));
  assert.ok(!full.frame(0).log.some(l=>l.includes('ability: Regenerator')));
 }
});

test('public field timers retain actual starting duration, count down, reset and expire in both modes',()=>{
 for(const mode of ['singles','doubles']) {
  const e=battle(mode,mon('Smeargle','Own Tempo',['rain-dance','trick-room','reflect','splash']));
  turn(e,1);
  assert.deepEqual(e.frame(0).field.weatherTiming,{remaining:4,maximum:5});
  turn(e,4);
  assert.deepEqual(e.frame(0).field.weatherTiming,{remaining:3,maximum:5});
  turn(e,2);
  assert.deepEqual(e.frame(0).field.conditionTimings.trickroom,{remaining:4,maximum:5});
  turn(e,3);
  assert.deepEqual(e.frame(0).field.ownSide.find(c=>c.id==='reflect').timing,{remaining:4,maximum:5});
  assert.deepEqual(e.frame(1).field.foeSide.find(c=>c.id==='reflect').timing,{remaining:4,maximum:5});
  turn(e,4);
  assert.equal(e.frame(0).field.weather,'');
  assert.equal(e.frame(0).field.weatherTiming,null);
  for(let i=0;i<4;i++)turn(e,4);
  assert.equal(e.frame(0).field.conditionTimings.trickroom,undefined);
  assert.equal(e.frame(0).field.ownSide.find(c=>c.id==='reflect'),undefined);
  turn(e,1);
  assert.deepEqual(e.frame(0).field.weatherTiming,{remaining:4,maximum:5});
  // Real callbacks initialize these public side effects with four turns.
  const side=e.battle.sides[0],source=side.active[0];
  side.addSideCondition('tailwind',source);
  assert.deepEqual(e.frame(0).field.ownSide.find(c=>c.id==='tailwind').timing,{remaining:4,maximum:4});
  turn(e,4);
  assert.deepEqual(e.frame(0).field.ownSide.find(c=>c.id==='tailwind').timing,{remaining:3,maximum:4});
  const permanent=battle(mode,mon('Rayquaza','Air Lock'),mon('Politoed','Drizzle'));
  assert.equal(permanent.frame(0).field.weatherTiming,null);
  assert.equal(permanent.frame(0).field.weatherSuppressed,true);
  side.addSideCondition('spikes',source);
  assert.equal(e.frame(0).field.ownSide.find(c=>c.id==='spikes').timing,null);
 }
});

test('same-type attacks receive BW2 STAB and Adaptability in singles and doubles without altering owned stats',()=>{
 for(const mode of ['singles','doubles'])for(const [species,ability,multiplier]of [['Smeargle','Own Tempo',1.5],['Porygon-Z','Adaptability',2]]) {
  const e=battle(mode,mon(species,ability,['tri-attack']));
  const attacker=e.battle.sides[0].active[0];
  const originalStats={...e.frame(0).own[0].stats};
  attacker.setType(['Water']);const neutral=damage(e,'triattack');
  attacker.setType(['Normal']);const stab=damage(e,'triattack');
  assert.ok(Math.abs(stab-neutral*multiplier)<=2,`${mode} ${ability}: ${neutral} -> ${stab} expected x${multiplier}`);
  assert.ok(stab>neutral);
  assert.deepEqual(e.frame(0).own[0].stats,originalStats);
 }
});
