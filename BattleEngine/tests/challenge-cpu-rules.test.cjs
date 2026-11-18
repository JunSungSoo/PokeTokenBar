const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const policy=require('../challenge-policy.cjs');
const rules=require('../challenge-cpu-rules.cjs');
const {battleDex}=require('../held-items.cjs');
const {encounters}=require('../challenge-opponents.json');
const dex=battleDex();
const SHIPPED_REVISION='02bc7a49e2b6208e0adaaf4e626b56dd9244ff0e676c6c39060bb0098c3bb1e6';

const sets={Snorlax:['Thick Fat',['bodyslam','earthquake','crunch','rest']],Ludicolo:['Swift Swim',['gigadrain','surf','icebeam','raindance']],
 Tyranitar:['Sand Stream',['crunch','stoneedge','earthquake','pursuit']],Gengar:['Levitate',['shadowball','focusblast','sludgebomb','thunderbolt']],
 Machamp:['No Guard',['dynamicpunch','stoneedge','icepunch','bulletpunch']],Raichu:['Static',['thunderbolt','surf','grassknot','focusblast']],
 Skarmory:['Sturdy',['bravebird','spikes','roost','whirlwind']],Blissey:['Natural Cure',['seismictoss','softboiled','toxic','thunderwave']]};
function player(names,level){
 return names.map((species,i)=>({id:'p'+i,species,ability:sets[species][0],moves:sets[species][1],level,nature:'Hardy',
  ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:380,atk:250,def:230,spa:230,spd:230,spe:200}}));
}
function trainer(id,lead){
 const team=encounters.find(encounter=>encounter.id===id).team.slice(),index=team.findIndex(member=>member.species===lead);
 return index>0?[team[index],...team.filter((_,i)=>i!==index)]:team;
}
function opening(id,lead,names,revision){
 const team=trainer(id,lead);
 const e=new OwnedBattle('singles',[player(names,team[0].level),team],[7,7,7,7],{profile:'challenge',expectedPolicyRevision:revision});
 for(const side of [0,1])if(e.frame(side).preview)e.choose(side,e.frame(side).decisionID,null,e.frame(side).own.map((_,i)=>i+1));
 return e;
}
function cpuMove(e){
 const {chooseCPU,model}=e.cpuPolicy,frame=e.frame(1),pick=chooseCPU(e.battle.dex,frame,model,e.cpuContext());
 return pick.kind==='move'?dex.moves.get(frame.slots[0].moves[pick.index-1].name).id:'switch';
}

// MARK: - Versioning

test('saved runs keep the shipped model byte-for-byte and replay without the rules',()=>{
 const unguarded=policy.loadPolicy('challenge-policy-v2.json'),current=policy.loadPolicy();
 assert.equal(unguarded.revision,SHIPPED_REVISION);
 assert.equal(unguarded.cpuRules,undefined);
 assert.equal(current.cpuRules,rules.RULES);
 assert.notEqual(current.revision,SHIPPED_REVISION);
 assert.deepEqual(current.weights,unguarded.weights,'the learned weights are unchanged');
 assert.equal(policy.resolvePolicy(SHIPPED_REVISION).model.revision,SHIPPED_REVISION);
 assert.throws(()=>policy.resolvePolicy('unknown'),/policy version changed/);
});

test('Hypno no longer opens with Protect; the shipped revision still does',()=>{
 assert.equal(cpuMove(opening('sabrina','Hypno',['Snorlax','Tyranitar','Gengar','Machamp','Raichu','Ludicolo'],SHIPPED_REVISION)),'protect');
 const move=cpuMove(opening('sabrina','Hypno',['Snorlax','Tyranitar','Gengar','Machamp','Raichu','Ludicolo']));
 assert.notEqual(move,'protect');
 assert.equal(move,'seismictoss','fixed damage is valued instead of scored as power 0');
});

test('fixed damage outranks a Protect that would have a reason to stall',()=>{
 const e=opening('sabrina','Hypno',['Snorlax','Tyranitar','Gengar','Machamp','Raichu','Ludicolo']);
 e.battle.sides[0].active[0].setStatus('tox');
 assert.equal(cpuMove(e),'seismictoss','Protect is allowed here, so only the valued Seismic Toss wins');
});

test('the engine hands the CPU its last move, a pending Wish and the foe visible volatiles',()=>{
 const e=opening('sabrina','Hypno',['Snorlax','Tyranitar','Gengar','Machamp','Raichu','Ludicolo']);
 assert.deepEqual(e.cpuContext(),{lastMove:undefined,wishPending:false,foeEffects:[]});
 const hypno=e.battle.sides[1].active[0],target=e.battle.sides[0].active[0];
 hypno.lastMove=e.battle.dex.moves.get('protect');
 e.battle.sides[1].addSlotCondition(hypno,'wish',hypno);
 target.addVolatile('substitute');target.addVolatile('leechseed',hypno);target.addVolatile('focusenergy');
 assert.deepEqual(e.cpuContext(),{lastMove:'protect',wishPending:true,foeEffects:['substitute','leechseed']},
  'only publicly visible volatiles are passed');
});

// MARK: - Individual rules

const own=(extra={})=>({hp:100,maxHP:100,boosts:{},effects:[],...extra});
const foe=(extra={})=>({name:'Snorlax',status:'',effects:[],...extra});
const reason=(move,ownState=own(),foeState=foe(),field={},context={})=>rules.pointlessReason(dex,dex.moves.get(move),ownState,foeState,field,context);

test('protection needs a reason and is never repeated',()=>{
 assert.match(reason('protect'),/without a reason/);
 assert.equal(reason('protect',own(),foe(),{},{wishPending:true}),null);
 assert.equal(reason('detect',own(),foe({status:'tox'})),null);
 assert.equal(reason('protect',own(),foe({effects:['leechseed']})),null);
 assert.match(reason('protect',own(),foe({status:'tox'}),{},{lastMove:'detect'}),/consecutive/);
});

test('setup stops at +2 in every raised stat',()=>{
 assert.equal(reason('calmmind',own({boosts:{spa:1,spd:1}})),null);
 assert.match(reason('calmmind',own({boosts:{spa:2,spd:2}})),/already high/);
 assert.equal(reason('calmmind',own({boosts:{spa:0,spd:4}})),null,'one stat can still rise');
 assert.match(reason('irondefense',own({boosts:{def:6}})),/already high/);
 assert.match(reason('shellsmash',own({boosts:{atk:2,spa:2,spe:2,def:-1,spd:-1}})),/already high/);
});

test('status, healing, substitute, weather and side conditions that cannot work are dropped',()=>{
 assert.match(reason('thunderwave',own(),foe({status:'par'})),/no effect/);
 assert.match(reason('thunderwave',own(),foe({name:'Swampert'})),/no effect/);
 assert.match(reason('toxic',own(),foe({name:'Skarmory'})),/no effect/);
 assert.match(reason('willowisp',own(),foe({name:'Arcanine'})),/no effect/);
 assert.match(reason('leechseed',own(),foe({name:'Ludicolo'})),/no effect/);
 assert.match(reason('toxic',own(),foe({effects:['substitute']})),/no effect/);
 assert.equal(reason('toxic',own(),foe()),null);
 assert.match(reason('moonlight'),/full HP/);
 assert.equal(reason('moonlight',own({hp:60})),null);
 assert.match(reason('wish',own({hp:60}),foe(),{},{wishPending:true}),/pending/);
 assert.match(reason('substitute',own({effects:['substitute']})),/cannot be made/);
 assert.match(reason('substitute',own({hp:25})),/cannot be made/);
 assert.match(reason('sunnyday',own(),foe(),{weather:'sunnyday'}),/weather/);
 assert.equal(reason('sunnyday',own(),foe(),{weather:'raindance'}),null);
 assert.match(reason('spikes',own(),foe(),{foeSide:[{id:'spikes',layers:3}]}),/maximum/);
 assert.equal(reason('spikes',own(),foe(),{foeSide:[{id:'spikes',layers:2}]}),null);
 assert.match(reason('reflect',own(),foe(),{ownSide:[{id:'reflect',layers:1}]}),/already active/);
});

test('a foe Substitute blocks only single-target moves that cannot pass it',()=>{
 const shielded=foe({effects:['substitute']});
 for(const move of ['whirlwind','roar','spikes','stealthrock','raindance','reflect','haze','healbell'])
  assert.equal(reason(move,own(),shielded),null,move+' still works behind a Substitute');
 for(const move of ['toxic','thunderwave','leechseed','confuseray'])
  assert.match(reason(move,own(),shielded),/no effect/,move);
});

test('a mon whose every move is pointless still acts',()=>{
 const frame={own:[{active:true,...own({boosts:{def:6}})}],foe:[foe()],field:{}};
 const actions=[{kind:'move',move:'Iron Defense'},{kind:'move',move:'Harden'}];
 assert.deepEqual(rules.meaningfulActions(dex,frame,actions),actions);
 const withSwitch=[...actions,{kind:'switch',index:2}];
 assert.deepEqual(rules.meaningfulActions(dex,frame,withSwitch),withSwitch,'moves are not dropped just to force a switch');
});

test('data-power-0 attacks are valued from public information',()=>{
 const observation=(level,ownHP,foeSpecies)=>({own:{species:'Hypno',level,hp:ownHP},foe:{species:foeSpecies,level:50,hp:1}});
 const power=(move,o,candidate={})=>rules.effectivePower(dex,dex.moves.get(move),o,candidate,policy.estimatedSpeed);
 assert.equal(power('seismictoss',observation(95,1,'Snorlax')),120);
 assert.equal(power('nightshade',observation(50,1,'Snorlax')),65);
 assert.equal(power('return',observation(50,1,'Snorlax')),102);
 assert.equal(power('grassknot',observation(50,1,'Snorlax')),120);
 assert.equal(power('lowkick',observation(50,1,'Pikachu')),20);
 assert.equal(power('reversal',observation(50,0.01,'Snorlax')),200);
 assert.equal(power('reversal',observation(50,1,'Snorlax')),20);
 assert.equal(power('hiddenpower',observation(50,1,'Snorlax'),{power:70}),70);
 assert.equal(power('thunderbolt',observation(50,1,'Snorlax')),95,'listed power is untouched');
});

// MARK: - Whole encounters

test('across singles encounters the CPU never picks a move that cannot help',()=>{
 const pointless=[];let moves=0;
 const teams=[['Snorlax','Ludicolo','Tyranitar','Gengar','Machamp','Raichu'],['Ludicolo','Blissey','Skarmory','Gengar','Tyranitar','Machamp']];
 for(const id of ['sabrina','misty','bugsy','falkner','agatha','erika','brock'])for(const [index,names] of teams.entries()){
  const team=trainer(id);
  const e=new OwnedBattle('singles',[player(names,team[0].level),team],[index+1,2,3,4],{profile:'challenge',automaticOpponent:true});
  const last={};
  for(let guard=0;guard<80&&!e.battle.ended&&e.battle.turn<=25;guard++){
   e.runCPU();
   const frame=e.frame(0);
   if(frame.preview){e.choose(0,frame.decisionID,null,frame.own.map((_,i)=>i+1));continue;}
   if(!frame.slots?.length||frame.waiting)break;
   const mon=e.battle.sides[1].active[0],target=e.battle.sides[0].active[0];
   const before={name:mon?.name,boosts:{...mon?.boosts},full:mon?.hp===mon?.maxhp,sub:!!mon?.volatiles.substitute,foeStatus:target?.status,
    weather:e.battle.field.weather,spikes:e.battle.sides[0].sideConditions.spikes?.layers||0};
   const slot=frame.slots[0],start=e.battle.log.length;
   if(slot.mustSwitch)e.choose(0,frame.decisionID,[{kind:'switch',index:frame.own.findIndex(p=>!p.active&&!p.fainted)+1}]);
   else e.choose(0,frame.decisionID,[{kind:'move',index:slot.moves.find(m=>!m.disabled&&m.pp>0).index,target:0}]);
   for(const line of e.battle.log.slice(start)){
    const parts=line.split('|');if(parts[1]!=='move'||!parts[2].startsWith('p2a')||parts[2].split(': ')[1]!==before.name)continue;
    const move=dex.moves.get(parts[3]),where=`${id} ${before.name} ${move.name}`;moves++;
    if(['protect','detect'].includes(move.id)&&['protect','detect'].includes(last[before.name]))pointless.push(where+' repeated');
    const raised=Object.entries({...(move.boosts||{}),...(move.self?.boosts||{})}).filter(([,amount])=>amount>0).map(([stat])=>stat);
    if(move.target==='self'&&move.category==='Status'&&raised.length&&raised.every(stat=>before.boosts[stat]>=rules.SETUP_CAP))pointless.push(where+' over cap');
    if(move.status&&before.foeStatus)pointless.push(where+' on statused');
    if(['recover','roost','softboiled','moonlight','synthesis','rest','wish'].includes(move.id)&&before.full)pointless.push(where+' at full');
    if(move.id==='substitute'&&before.sub)pointless.push(where+' behind substitute');
    if(move.weather&&before.weather===move.id)pointless.push(where+' same weather');
    if(move.id==='spikes'&&before.spikes>=3)pointless.push(where+' fourth layer');
    last[before.name]=move.id;
   }
  }
 }
 assert.ok(moves>150,`enough CPU moves were observed (${moves})`);
 assert.deepEqual(pointless,[]);
});
