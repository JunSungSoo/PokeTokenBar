const {test}=require('node:test'),assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const policy=require('../challenge-policy.cjs');
function team(prefix,first){return [first,...[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']].filter(([s])=>s!==first.species).slice(0,5).map(([species,ability])=>({species,ability,moves:['splash']}))].map((p,i)=>({level:100,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:100,spa:100,spd:100,spe:120},...p,id:prefix+i}));}
function battle(own={species:'Scizor',ability:'Technician',moves:['bulletpunch','ironhead','swordsdance','roost']},options={}){return new OwnedBattle('singles',[team('a',{species:'Mew',ability:'Synchronize',moves:['splash']}),team('b',own)],[1,2,3,4],{profile:'challenge',...options});}
const feature=(o,c,key,dex)=>policy.features(dex,o,c)[policy.FEATURES.indexOf(key)];
test('AI speed is current owned speed, including stages, paralysis, Tailwind, item and reward bonuses; Trick Room is applied once',()=>{
 const e=battle(undefined,{challengeBoosts:{spe:1}}),p=e.battle.sides[1].active[0],human=e.battle.sides[0].active[0];
 p.boosts.spe=2;p.setStatus('par');p.setItem('choicescarf');e.battle.sides[1].addSideCondition('tailwind',p);
 human.boosts.spe=-1;
 const rng=e.battle.prng.getSeed(),f=e.frame(1),o=policy.observation(f);
 assert.equal(o.own.effectiveSpeed,p.getStat('spe'));
 assert.equal(policy.estimatedSpeed(e.battle.dex,o.own),p.getStat('spe'));
 assert.equal(f.foe[0].effectiveSpeed,undefined);assert.equal(f.foe[0].stats,undefined);
 assert.equal(o.foe.boosts.spe,0,'public reward +1 and battle stage -1 combine');
 const attack={kind:'move',move:'Iron Head'};
 const tempo=feature(o,attack,'attackTempo',e.battle.dex);
 assert.notEqual(tempo,0);
 e.battle.field.addPseudoWeather('trickroom',p);
 const room=policy.observation(e.frame(1));
 assert.equal(room.own.effectiveSpeed,o.own.effectiveSpeed);
 assert.equal(feature(room,attack,'attackTempo',e.battle.dex),-tempo);
 assert.deepEqual(e.battle.prng.getSeed(),rng,'Observation/scoring/field setup must not consume combat RNG');
});
test('weather speed abilities use effective speed rather than species base speed',()=>{
 const e=battle({species:'Kingdra',ability:'Swift Swim',moves:['surf','agility']}),p=e.battle.sides[1].active[0];
 const before=policy.observation(e.frame(1)).own.effectiveSpeed;
 e.battle.field.setWeather('raindance',p);
 assert.equal(policy.observation(e.frame(1)).own.effectiveSpeed,before*2);
});
test('actual knockout count replaces the constant six-opponent input',()=>{
 const e=battle({species:'Scizor',ability:'Technician',moves:['dragonrage']});
 e.battle.sides[0].active[0].hp=40;e.battle.sides[1].active[0].storedStats.spe=200;
 assert.equal(policy.observation(e.frame(1)).foeSurvivors,6);
 for(const p of [1,0]){const f=e.frame(p);e.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]);}
 const f=e.frame(1);assert.equal(f.foeTeamStatus.fainted,1);assert.equal(policy.observation(f).foeSurvivors,5);
});
test('status effects and survivors alter candidate differences, not only a cancelling constant',()=>{
 const e=battle(),dex=e.battle.dex,o=policy.observation(e.frame(1));
 const physical={kind:'move',move:'Iron Head'},special={kind:'move',move:'Flash Cannon'},hazard={kind:'move',move:'Stealth Rock'};
 const burned=structuredClone(o);burned.own.status='brn';
 assert.equal(feature(o,physical,'burnedPhysical',dex),0);
 assert.ok(feature(burned,physical,'burnedPhysical',dex)>feature(burned,special,'burnedPhysical',dex));
 burned.own.ability='Guts';assert.equal(feature(burned,physical,'burnedPhysical',dex),0);
 const sleeping=structuredClone(o);sleeping.own.status='slp';
 assert.equal(feature(sleeping,physical,'sleepBlocked',dex),1);
 assert.equal(feature(sleeping,{kind:'move',move:'Sleep Talk'},'sleepUsable',dex),1);
 const status=structuredClone(o);status.foe.status='par';
 assert.equal(feature(status,{kind:'move',move:'Thunder Wave'},'statusBlocked',dex),1);
 assert.equal(feature(o,hazard,'hazardFoeBench',dex),1);
 const last=structuredClone(o);last.foeSurvivors=1;
 assert.equal(feature(last,hazard,'hazardFoeBench',dex),0);
 const model=policy.loadPolicy();
 const margin=(observation,a,b)=>{const x=policy.features(dex,observation,a),y=policy.features(dex,observation,b);return x.reduce((sum,v,i)=>sum+(v-y[i])*model.weights[i],0);};
 assert.notEqual(margin(o,physical,special),margin({...o,own:{...o.own,status:'brn'}},physical,special));
 assert.notEqual(margin(o,hazard,physical),margin(last,hazard,physical));
 const fast={...o,own:{...o.own,effectiveSpeed:1000}},slow={...o,own:{...o.own,effectiveSpeed:1}};
 assert.notEqual(margin(fast,physical,{kind:'move',move:'Agility'}),margin(slow,physical,{kind:'move',move:'Agility'}));
});
test('private opponent stats, ability, item and unrevealed bench moves never enter speed estimation or learned decisions',()=>{
 const e=battle(),human=e.battle.sides[0].active[0];
 const before=policy.observation(e.frame(1)),decision=policy.chooseCPU(e.battle.dex,e.frame(1));
 human.storedStats.spe=999;human.set.item='choicescarf';human.ability='immunity';
 e.battle.sides[0].pokemon[1].moveSlots[0].pp=0;
 assert.deepEqual(policy.observation(e.frame(1)),before);
 assert.deepEqual(policy.chooseCPU(e.battle.dex,e.frame(1)),decision);
});
test('v1 checkpoints retain the original policy and lead/decision behavior; unknown revisions fail',()=>{
 const legacy=require('../challenge-policy-v1.cjs'),old=legacy.loadPolicy(),resolved=policy.resolvePolicy(old.revision);
 assert.equal(resolved.model.featureVersion,'bw-public-action-v1');assert.equal(resolved.chooseCPU,legacy.chooseCPU);
 const e=battle(undefined,{expectedPolicyRevision:old.revision}),f=e.frame(1);
 assert.deepEqual(e.cpuPolicy.chooseCPU(e.battle.dex,f,e.cpuPolicy.model),legacy.chooseCPU(e.battle.dex,f,old));
 assert.throws(()=>policy.resolvePolicy('unknown'),/version changed/);
 assert.equal(policy.resolvePolicy().model.featureVersion,'bw-public-action-v2');
});
