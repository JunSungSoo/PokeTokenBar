const {test}=require('node:test'),assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const species=[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Scizor','Technician'],['Slowbro','Own Tempo']];
function team(prefix,move='tackle'){return species.map(([s,a],i)=>({id:prefix+i,species:s,ability:a,moves:[move,'splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100}}));}
function setup(resources,mode='singles'){return new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4],{profile:'challenge',resources});}
function turn(e){for(const p of [0,1]){const f=e.frame(p);e.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]);}}
test('challenge has six combatants; ordinary singles/doubles retain three/four',()=>{
 assert.equal(setup().frame(0).own.length,6);
 for(const [mode,count]of [['singles',3],['doubles',4]]){const e=new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4]);assert.equal(e.frame(0).own.length,count);assert.equal(e.frame(0).resources,undefined);}
 assert.throws(()=>setup(undefined,'doubles'),/profile/);
});
test('actual HP, PP, dead members, status and consumed items survive a new encounter before entry',()=>{
 const e=setup();turn(e);const before=e.frame(0).resources;
 before[0].hp=0;before[1].hp=179;before[1].status='brn';before[1].moves[0].pp=0;before[2].item='';
 const next=setup([before,null]),f=next.frame(0);
 assert.deepEqual(f.foeTeamStatus,{selected:6,fainted:0});
 assert.deepEqual(next.frame(1).foeTeamStatus,{selected:6,fainted:1});
 assert.equal(f.own.length,6);assert.equal(f.own.find(p=>p.active).id,'a1');assert.equal(f.own.find(p=>p.id==='a0').hp,0);
 assert.equal(f.own.find(p=>p.id==='a1').hp,179);assert.equal(f.slots[0].moves[0].pp,0);assert.equal(f.slots[0].moves[0].disabled,true);
 assert.equal(f.resources.find(p=>p.id==='a1').status,'brn');assert.equal(f.own[0].stats.atk,120);
 assert.ok(f.scenes.filter(s=>s.own.some(p=>p.active)).every(s=>s.own.find(p=>p.id==='a0').hp===0));
});
test('malformed resources cannot heal, restore PP, duplicate members or start an all-dead run',()=>{
 const state=setup().frame(0).resources;
 for(const edit of [s=>s[0].hp=501,s=>s[0].moves[0].pp=999,s=>s[0].moves[0].id='earthquake',s=>s[1].id=s[0].id,s=>s.forEach(p=>p.hp=0)]){
  const copy=structuredClone(state);edit(copy);assert.throws(()=>setup([copy,null]));
 }
 assert.throws(()=>new OwnedBattle('singles',[team('a'),team('b')],[1,2,3,4],{resources:[state,null]}),/only available/);
});
test('bench PP is preserved, Transform exports original slots, and sleep carries its original duration',()=>{
 const state=setup().frame(0).resources;state[5].moves[0].pp=3;state[0].status='slp';state[0].sleepStart=3;state[0].sleepRemaining=1;
 const e=setup([state,null]);assert.equal(e.frame(0).resources.find(p=>p.id==='a5').moves[0].pp,3);
 assert.equal(e.frame(0).resources[0].sleepStart,3);
 // BW resets the sleep counter when a Pokemon enters, as in an ordinary switch-in.
 assert.equal(e.battle.sides[0].active[0].statusState.time,3);
});
test('spent PP is exported exactly and switching cannot refund it in either profile',()=>{
 for(const profile of ['peer','challenge']){
  const e=new OwnedBattle('singles',[team('a'),team('b')],[1,2,3,4],{profile});turn(e);
  const first=e.battle.sides[0].pokemon.find(p=>p.set.ptbID==='a0');assert.equal(first.moveSlots[0].pp,34);
  if(profile==='challenge')assert.equal(e.frame(0).resources.find(p=>p.id==='a0').moves[0].pp,34);
  e.choose(0,e.frame(0).decisionID,[{kind:'switch',index:2,target:0}]);e.choose(1,e.frame(1).decisionID,[{kind:'move',index:2,target:0}]);
  assert.equal(first.moveSlots[0].pp,34);
 }
});
test('all 27 fixed six-member NPC teams are obtainable in BW and instantiate with the learned CPU',()=>{
 const {encounters}=require('../challenge-opponents.json'),{Dex,TeamValidator}=require('pokemon-showdown');
 const validator=new TeamValidator({...Dex.formats.get('gen5customgame'),id:'ptbtestlegality',name:'BW legality',ruleset:['Obtainable']});
 assert.equal(encounters.length,27);assert.equal(new Set(encounters.map(e=>e.id)).size,27);
 for(const encounter of encounters){
  const items=new Set();
  for(const p of encounter.team){assert.equal(p.level,encounter.index<24?95:100);assert.equal(p.moves.length,4);assert.equal(validator.validateSet(encounter.id==='red'&&p.speciesID===6?{...structuredClone(p),item:'',moves:p.moves.filter(m=>m!=='weatherball')}:structuredClone(p)),null,encounter.id+' '+p.species);assert.ok(!items.has(p.item));items.add(p.item);}
  const e=new OwnedBattle('singles',[team('a'),encounter.team],[1,2,3,4],{profile:'challenge'});e.runCPU();assert.equal(e.frame(1).waiting,true);assert.equal(e.frame(0).own.length,6);
 }
});
test('learned CPU uses only a perspective-filtered observation and emits a legal action',()=>{
 const {chooseCPU,features,observation,loadPolicy}=require('../challenge-policy.cjs');const e=setup(),f=e.frame(1),model=loadPolicy();
 assert.ok(model.training.trainDecisions>0);assert.ok(model.training.evaluationGames>0);
 const before=chooseCPU(e.battle.dex,f);e.battle.sides[0].pokemon[1].moveSlots[0].pp=0;e.battle.sides[0].pokemon[1].ability='pressure';
 assert.deepEqual(chooseCPU(e.battle.dex,e.frame(1)),before,'Hidden bench information cannot affect the CPU');
 const rng=e.battle.prng.getSeed();chooseCPU(e.battle.dex,f);assert.deepEqual(e.battle.prng.getSeed(),rng,'Scoring cannot consume battle RNG');
 assert.ok(features(e.battle.dex,observation(f),{kind:'move',move:'Tackle'}).every(Number.isFinite));
 e.runCPU();e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);e.runCPU();assert.equal(e.frame(1).waiting,true);
});
test('Transform never exports copied PP and carried item removal disables Mega Evolution',()=>{
 const own=team('a');own[0].moves=['transform','splash'];
 const e=new OwnedBattle('singles',[own,team('b')],[1,2,3,4],{profile:'challenge'});turn(e);
 assert.equal(e.battle.sides[0].active[0].transformed,true);
 const state=e.frame(0).resources[0];assert.deepEqual(state.moves.map(m=>m.id),['transform','splash']);assert.equal(state.moves[0].pp,9);
 const char=team('a');char[0]={...char[0],species:'Charizard',ability:'Blaze',item:'charizarditex'};
 const first=new OwnedBattle('singles',[char,team('b')],[1,2,3,4],{profile:'challenge'}),r=first.frame(0).resources;r[0].item='';
 const next=new OwnedBattle('singles',[char,team('b')],[1,2,3,4],{profile:'challenge',resources:[r,null]});assert.equal(next.frame(0).slots[0].canMegaEvo,false);
});
test('learned lead selection cannot inspect player order or hidden build details',()=>{
 const {chooseLead,leadFeatures,loadPolicy}=require('../challenge-policy.cjs'),{battleDex}=require('../held-items.cjs'),model=loadPolicy();
 const {encounters}=require('../challenge-opponents.json'),own=encounters[0].team,foe=encounters[26].team;
 assert.ok(model.lead.trainingExamples>0);assert.ok(model.lead.evaluationExamples>0);
 assert.equal(chooseLead(battleDex(),own,foe),chooseLead(battleDex(),own,foe.slice().reverse().map(p=>({...p,moves:['splash'],ability:'None',stats:{hp:1}}))));
 assert.ok(leadFeatures(battleDex(),own[0].species,foe.map(p=>p.species)).every(Number.isFinite));
});
test('Red has six perfect-IV members and Charizard automatically Mega evolves to Y with sun moves',()=>{
 const {Dex}=require('pokemon-showdown'),{chooseCPU,FEATURES}=require('../challenge-policy.cjs');
 const red=require('../challenge-opponents.json').encounters.find(e=>e.id==='red');
 for(const p of red.team){assert.deepEqual(Object.values(p.ivs),[31,31,31,31,31,31]);const species=Dex.mod('gen5').species.get(p.species),nature=Dex.mod('gen5').natures.get(p.nature);
  for(const [k,base]of Object.entries(species.baseStats)){const raw=2*base+31;assert.equal(p.stats[k],k==='hp'?raw+110:Math.floor((raw+5)*(nature.plus===k?1.1:nature.minus===k?.9:1)));}}
 const char=red.team.find(p=>p.speciesID===6);assert.equal(char.item,'charizarditey');assert.ok(char.moves.includes('weatherball'));assert.ok(char.moves.includes('solarbeam'));
 const own=team('a').map(p=>({...p,moves:['splash']})),foe=[char,...red.team.filter(p=>p!==char)];
 const e=new OwnedBattle('singles',[own,foe],[1,2,3,4],{profile:'challenge'});
 const a=chooseCPU(e.battle.dex,e.frame(1),{weights:FEATURES.map(()=>0)});assert.equal(a.kind,'move');assert.equal(a.mega,true);
 e.choose(1,e.frame(1).decisionID,[a]);e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 assert.equal(e.battle.sides[1].active[0].species.name,'Charizard-Mega-Y');assert.equal(e.battle.sides[1].active[0].ability,'drought');assert.equal(e.battle.field.weather,'sunnyday');
 assert.ok(e.battle.log.some(l=>l.includes('|Weather Ball|')));
 const offset=e.battle.log.length;
 e.choose(1,e.frame(1).decisionID,[{kind:'move',index:2,target:0}]);e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0}]);
 assert.ok(e.battle.log.slice(offset).some(l=>l.includes('|Solar Beam|')));assert.ok(e.battle.log.slice(offset).some(l=>l.includes('|-anim|p2a: Charizard|Solar Beam|')),'Sun resolves the charged move immediately');assert.ok(e.battle.log.slice(offset).some(l=>l.startsWith('|-damage|p1')),'Solar Beam deals damage on the same turn');
});
