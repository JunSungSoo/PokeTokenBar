const {test}=require('node:test'),assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const species=[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Scizor','Technician'],['Slowbro','Own Tempo']];
function team(prefix,move='tackle'){return species.map(([s,a],i)=>({id:prefix+i,species:s,ability:a,moves:[move,'splash'],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:150,spa:120,spd:150,spe:100}}));}
function setup(resources,mode='singles'){return new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4],{profile:'challenge',resources});}
function turn(e){for(const p of [0,1]){const f=e.frame(p);e.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]);}}
test('challenge has six combatants; ordinary singles/doubles retain three/four',()=>{
 assert.equal(setup().frame(0).own.length,6);
 for(const [mode,count]of [['singles',3],['doubles',4]]){const e=new OwnedBattle(mode,[team('a'),team('b')],[1,2,3,4]);assert.equal(e.frame(0).own.length,count);assert.equal(e.frame(0).resources,undefined);}
 const doubles=setup(undefined,'doubles');
 assert.equal(doubles.frame(0).own.length,6);
 assert.equal(doubles.frame(0).slots.length,2);
 assert.deepEqual(doubles.frame(0).own.filter(p=>p.active).map(p=>p.id),['a0','a1']);
 assert.equal(doubles.frame(0).foeTeamStatus.selected,6);
});
test('four-member doubles challenge rejects switches to either unselected member',()=>{
 const legacy=setup(undefined,'doubles');
 const resources=legacy.frame(0).resources.slice(0,4);
 const e=new OwnedBattle('doubles',[team('a'),team('b')],[1,2,3,4],{
  profile:'challenge',challengeBattleSize:4,resources:[resources,null]
 });
 const frame=e.frame(0);
 assert.equal(frame.foeTeamStatus.selected,4);
 assert.deepEqual(frame.resources.map(p=>p.id),['a0','a1','a2','a3']);
 const move={kind:'move',index:1,target:1};
 for(const index of [5,6]){
  assert.throws(()=>e.choose(0,frame.decisionID,[{kind:'switch',index},move]),/Invalid action/i);
 }
 e.choose(0,frame.decisionID,[{kind:'switch',index:4},move]);
 e.runCPU();
 assert.ok(e.frame(0).own.find(p=>p.id==='a3').active);
});
test('learned doubles lead and four-member selection adapt to sets without seeing the player lineup',()=>{
 const {REVISION,FEATURE_NAMES}=require('../challenge-doubles-lineup.cjs');
 const model=require('../challenge-doubles-lineup-model.json');
 const sets=require('../challenge-doubles-opponents.json');
 const {encounters}=require('../challenge-opponents.json');
 const roster=id=>sets[id].map(set=>({...encounters.find(e=>e.id===id).team.find(p=>p.speciesID===set.speciesID),...set}));
 const preview=roster('misty').map(p=>({...p,item:'',moves:['surf']}));
 const trainer=roster('brock');
 const open=(player,revision=REVISION)=>new OwnedBattle('doubles',[player,trainer],[1,2,3,4],{
  profile:'challenge',challengeBattleSize:4,automaticOpponent:true,expectedPolicyRevision:revision
 });
 const fields=e=>e.frame(1).own.map(p=>p.id);
 const first=open(preview);
 assert.equal(fields(first).length,4);
 assert.notDeepEqual(fields(first),fields(open(preview.map(p=>({...p,moves:['earthquake']})))));
 assert.deepEqual(fields(first),fields(open(preview.slice().reverse())));
 assert.deepEqual(fields(open(preview,'ptb-challenge-doubles-v2')),trainer.slice(0,4).map(p=>p.id));
 assert.deepEqual(model.featureNames,FEATURE_NAMES);
 assert.ok(model.holdout.logLoss<Math.log(15));
 first.runCPU();
 assert.equal(first.frame(1).waiting,true);
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
test('doubles CPU replaces two fainted slots and a one-survivor team can still act',()=>{
 const initial=setup(undefined,'doubles');
 const own=initial.frame(0).resources,foe=initial.frame(1).resources;
 foe[0].hp=1;foe[1].hp=1;
 const battle=setup([own,foe],'doubles');
 battle.runCPU();
 battle.choose(0,battle.frame(0).decisionID,[1,2].map(target=>({kind:'move',index:1,target})));
 assert.deepEqual(battle.frame(1).slots.map(slot=>slot.mustSwitch),[true,true]);
 battle.runCPU();
 assert.deepEqual(battle.frame(1).own.filter(p=>p.active).map(p=>p.id),['b2','b3']);
 assert.equal(battle.frame(0).resources.length,6);
 for(let i=0;i<5;i++)own[i].hp=0;
 const last=setup([own,null],'doubles');
 const frame=last.frame(0);
 assert.deepEqual(frame.own.filter(p=>p.active&&!p.fainted).map(p=>p.id),['a5']);
 assert.equal(frame.slots[1].canPass,true);
 last.runCPU();
 last.choose(0,last.frame(0).decisionID,[{kind:'move',index:1,target:1},{kind:'pass'}]);
 assert.equal(last.frame(0).turn,2);
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

test('all 14 doubles rosters preserve six species and levels with obtainable BW sets and fixed leads',()=>{
 const {encounters}=require('../challenge-opponents.json'),doubles=require('../challenge-doubles-opponents.json');
 const {Dex,TeamValidator}=require('pokemon-showdown');
 const validator=new TeamValidator({...Dex.formats.get('gen5customgame'),id:'ptbdoubleslegality',name:'BW legality',ruleset:['Obtainable']});
 assert.deepEqual(Object.keys(doubles),['brock','misty','ltsurge','erika','koga1','sabrina','blaine','giovanni',
   'lorelei','bruno1','agatha','lance1','blue','red']);
 for(const [index,[id,sets]] of Object.entries(doubles).entries()){
  const original=encounters.find(e=>e.id===id).team;
  const roster=sets.map(set=>({...original.find(p=>p.speciesID===set.speciesID),...set}));
  assert.deepEqual(new Set(roster.map(p=>p.speciesID)),new Set(original.map(p=>p.speciesID)));
  assert.equal(new Set(roster.map(p=>p.item)).size,6);
  for(const p of roster){
   assert.equal(p.level,index<12?95:100);
   assert.equal(new Set(p.moves).size,4);
   const megaY=id==='red'&&p.speciesID===6;
   const bwSet=megaY?{...p,item:'',moves:p.moves.filter(m=>m!=='weatherball')}:p;
   assert.equal(validator.validateSet(structuredClone(bwSet)),null,id+' '+p.species);
   if(id==='red') assert.ok(Object.values(p.ivs).every(iv=>iv===31));
  }
  const e=new OwnedBattle('doubles',[team('a'),roster],[1,2,3,4],{profile:'challenge',automaticOpponent:true});
  assert.deepEqual(e.frame(1).own.filter(p=>p.active).map(p=>p.id),roster.slice(0,2).map(p=>p.id));
  e.runCPU();
  e.choose(0,e.frame(0).decisionID,[1,2].map(target=>({kind:'move',index:1,target})));
  assert.ok(e.frame(0).turn>1 || e.frame(0).slots.some(slot=>slot.mustSwitch));
  if(id==='red') {
   assert.equal(e.battle.sides[1].active[0].species.name,'Charizard-Mega-Y');
   assert.equal(e.battle.field.weather,'sunnyday');
   const mewtwo=roster.find(p=>p.speciesID===150);
   assert.equal(mewtwo.item,'lifeorb');assert.equal(mewtwo.cpuRecoveryThreshold,.65);
   assert.deepEqual(mewtwo.moves,['psystrike','shadowball','recover','flamethrower']);
  }
 }
});

test('doubles AI evaluates friendly fire and partner Protect in the same action pair',()=>{
 const {chooseActions}=require('../challenge-doubles-policy.cjs');
 const own=team('b');
 own[0]={...own[0],species:'Golem',ability:'Sturdy',moves:['earthquake'],stats:{...own[0].stats,atk:270}};
 own[1]={...own[1],species:'Jolteon',ability:'Volt Absorb',moves:['thunderbolt','protect'],stats:{...own[1].stats,hp:90}};
 const e=new OwnedBattle('doubles',[team('a').map(p=>({...p,moves:['splash']})),own],[1,2,3,4],{profile:'challenge'});
 const f=e.frame(1),seed=e.battle.prng.getSeed();
 assert.deepEqual(chooseActions(e.battle.dex,f),[{kind:'move',index:1,target:0},{kind:'move',index:2,target:0}]);
 assert.equal(e.battle.prng.getSeed(),seed);
 e.runCPU();
 e.choose(0,e.frame(0).decisionID,[{kind:'move',index:1,target:0},{kind:'move',index:1,target:0}]);
 assert.equal(e.frame(1).resources.find(p=>p.id==='b1').hp,90);
 assert.ok(e.frame(0).resources.slice(0,2).every(p=>p.hp<500));
});

test('doubles AI splits lethal attacks and ignores an unrevealed foe set or choice',()=>{
 const {chooseActions}=require('../challenge-doubles-policy.cjs');
 const initial=setup(undefined,'doubles'),foe=initial.frame(0).resources;
 foe[0].hp=foe[1].hp=1;
 const e=setup([foe,null],'doubles');
 const choose=()=>chooseActions(e.battle.dex,e.frame(1));
 const before=choose();
 assert.deepEqual(before.map(a=>a.target).sort(),[1,2]);
 e.battle.sides[0].pokemon[2].moveSlots[0].pp=0;
 e.battle.sides[0].pokemon[2].ability='pressure';
 e.choose(0,e.frame(0).decisionID,[1,1].map(target=>({kind:'move',index:1,target})));
 assert.deepEqual(choose(),before);
 e.runCPU();
 assert.equal(e.frame(0).own.filter(p=>p.fainted).length,2);
});
