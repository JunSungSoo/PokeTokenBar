const {test}=require('node:test');
const assert=require('node:assert/strict');
const {OwnedBattle}=require('../engine.cjs');
const stats={hp:143,atk:91,def:87,spa:96,spd:89,spe:107};
function mon(id,species,ability,moves=['splash']) {return {id,species,ability,moves,level:37,nature:'Hardy',ivs:Object.fromEntries(Object.keys(stats).map(k=>[k,17])),stats:{...stats}};}
function setup(ability, mode='singles', defender='Swift Swim') {
 const a=[mon('a','Gyarados',ability,['waterfall']),mon('b','Pikachu','Static'),mon('c','Eevee','Run Away')];
 const b=[mon('d',defender==='Clear Body'?'Tentacool':defender==='Defiant'?'Bisharp':'Magikarp',defender),mon('e','Raichu','Static'),mon('f','Pichu','Static')];
 if(mode==='doubles'){a.push(mon('g','Slowpoke','Oblivious'));b.push(mon('h','Eevee','Run Away'));}
 for(const [prefix,t] of [['a',a],['b',b]])for(const [species,ability] of [['Electabuzz','Static'],['Emolga','Static'],['Stunfisk','Static']].slice(0,6-t.length))t.push(mon(prefix+t.length,species,ability));
 const e=new OwnedBattle(mode,[a,b],[1,2,3,4]);
 for(let p=0;p<2;p++)if(e.frame(p).preview)e.choose(p,e.frame(p).decisionID,null,a.map((_,i)=>i+1));
 return e;
}
test('Intimidate lowers only opposing active Attack in singles and doubles and publicly announces ability',()=>{
 for(const mode of ['singles','doubles']) {
 const e=setup('Intimidate',mode);
 assert.ok(e.frame(0).log.some(l=>l.includes('|Intimidate|')));
 for(const p of e.battle.sides[1].active)assert.equal(p.boosts.atk,-1);
 for(const p of e.battle.sides[0].active)assert.equal(p.boosts.atk,0);
 for(const side of e.battle.sides)for(const p of side.pokemon)assert.deepEqual({hp:p.maxhp,...p.storedStats},stats);
 }
});
test('Moxie boosts Attack only after actual knockout, not merely dealing damage',()=>{
 for(const knockout of [false,true]){
 const e=setup('Moxie');if(knockout)e.battle.sides[1].active[0].hp=1;
 for(let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 assert.equal(e.battle.sides[0].active[0].boosts.atk,knockout?1:0);
 assert.equal(e.frame(0).log.some(l=>l.includes('|Moxie|')),knockout);
 assert.deepEqual(e.frame(0).own[0].stats,stats);
 }
});
test('Clear Body blocks Intimidate and exposes the blocking ability',()=>{
 const e=setup('Intimidate','singles','Clear Body');
 assert.equal(e.battle.sides[1].active[0].boosts.atk,0);
 assert.match(e.frame(0).log.join('\n'),/Clear Body/);
});
test('packaged ability choices exactly match every supported Gen V species and form',()=>{
 const fs=require('node:fs'),path=require('node:path');
 const {Dex}=require('pokemon-showdown'), dex=Dex.mod('gen5');
 const options=JSON.parse(fs.readFileSync(path.join(__dirname,'../../Sources/PokeTokenBar/Resources/BattleText/ability-options.json')));
 for(const s of dex.species.all().filter(s=>s.num>0&&s.num<=649&&s.gen<=5)) {
  assert.deepEqual(options[s.id],Object.entries(s.abilities).filter(([slot,name])=>['0','1','H'].includes(slot)&&dex.abilities.get(name).gen<=5).map(([slot,name])=>({name,slot:slot==='H'?3:Number(slot)+1,isHidden:slot==='H'})));
 }
});

test('Defiant reacts between Intimidate targets without preventing the second drop',()=>{
 const e=setup('Intimidate','doubles','Defiant');
 assert.equal(e.battle.sides[1].active[0].boosts.atk,1);
 assert.equal(e.battle.sides[1].active[1].boosts.atk,-1);
 const events=e.frame(0).log.filter(l=>/boost|ability/.test(l));
 assert.ok(events.findIndex(l=>l.includes('|Defiant|'))<events.findIndex(l=>l.includes('|p2b: Raichu|atk|1')));
});

test('own stage snapshots follow Intimidate, Moxie and switching, without disclosing opponent stats',()=>{
 for(const mode of ['singles','doubles']){
  const e=setup('Intimidate',mode);
  assert.equal(e.frame(1).own[0].boosts.atk,-1);
  assert.equal(e.frame(0).own[0].boosts.atk,0);
  assert.deepEqual(e.frame(1).own[0].stats,stats);
  assert.equal(e.frame(0).foe[0].boosts,undefined);
  assert.equal(e.frame(0).foe[0].stats,undefined);
 }
 const e=setup('Moxie');e.battle.sides[1].active[0].hp=1;
 for(let p=0;p<2;p++)e.choose(p,e.frame(p).decisionID,[{kind:'move',index:1,target:0}]);
 assert.equal(e.frame(0).own[0].boosts.atk,1);
 e.choose(1,e.frame(1).decisionID,[{kind:'switch',index:2}]);
 e.choose(0,e.frame(0).decisionID,[{kind:'switch',index:2}]);
 e.choose(1,e.frame(1).decisionID,[{kind:'move',index:1,target:0}]);
 assert.equal(e.frame(0).own.find(p=>p.id==='a').boosts.atk,0);
 assert.equal(e.frame(0).own.find(p=>p.active).boosts.atk,0);
});

test('real moves apply Gen V stages and stat ratios, cap at minus six, and Haze clears changes',()=>{
 const own=[mon('a','Gyarados','Moxie',['rest','dragon-dance']),mon('b','Vaporeon','Water Absorb',['haze']),mon('c','Pikachu','Static')];
 const foe=[mon('d','Eevee','Run Away',['growl','sand-attack','protect']),mon('e','Raichu','Static'),mon('f','Pichu','Static')];
 for(const [prefix,t] of [['a',own],['b',foe]])for(const species of ['Electabuzz','Emolga','Stunfisk'])t.push(mon(prefix+t.length,species,'Static'));
 const e=new OwnedBattle('singles',[own,foe],[1,2,3,4]);
 for(let p=0;p<2;p++)if(e.frame(p).preview)e.choose(p,e.frame(p).decisionID,null,[1,2,3]);
 function turn(a,b){e.choose(0,e.frame(0).decisionID,[a]);e.choose(1,e.frame(1).decisionID,[b]);}
 const move=i=>({kind:'move',index:i,target:0});
 for(let i=0;i<7;i++)turn(move(1),move(1));
 assert.equal(e.frame(0).own[0].boosts.atk,-6);
 assert.equal(e.battle.sides[0].active[0].getStat('atk',false,true),Math.floor(91*2/8));
 turn(move(2),move(2));
 assert.equal(e.frame(0).own[0].boosts.atk,-5);
 assert.equal(e.frame(0).own[0].boosts.spe,1);
 assert.equal(e.frame(0).own[0].boosts.accuracy,-1);
 assert.equal(e.battle.sides[0].active[0].getStat('spe',false,true),Math.floor(107*3/2));
 turn({kind:'switch',index:2},move(1));
 assert.equal(e.frame(0).own.find(p=>p.active).boosts.atk,-1);
 turn(move(1),move(3));
 assert.ok(Object.values(e.frame(0).own.find(p=>p.active).boosts).every(n=>n===0));
 assert.deepEqual(e.frame(0).own.find(p=>p.active).stats,stats);
});
