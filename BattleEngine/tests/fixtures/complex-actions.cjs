const {OwnedBattle}=require('../../engine.cjs');
function mon(species,ability,moves,speed=200){return {species,ability,moves,level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:120,def:100,spa:120,spd:100,spe:speed}};}
function team(prefix,first){return [first,...[['Smeargle','Own Tempo'],['Blissey','Natural Cure'],['Raichu','Static'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician']].filter(([s])=>s!==first.species).slice(0,5).map(([s,a])=>mon(s,a,['splash'],70))].map((m,i)=>({...m,id:prefix+i}));}
function run(mode,kind){
 const source=kind==='multi'?mon('Cloyster','Skill Link',['bulletseed']):kind==='drain'?mon('Conkeldurr','Guts',['drainpunch']):kind==='recoil'||kind==='recoilKO'?mon('Arcanine','Flash Fire',['flareblitz']):kind==='spread'?mon('Vaporeon','Water Absorb',['surf']):mon('Raichu','Static',[kind==='knockout'?'dragonrage':'splash']);
 const target=mon('Snorlax','Immunity',[kind==='guard'?'protect':'dragonrage'],50);
 if(kind==='residual'||kind==='residualKO')target.moves=['splash'];
 if(kind==='guard')source.moves=['thunderbolt'];
 const e=new OwnedBattle(mode,[team('a',source),team('b',target)],[1,2,3,4]);
 if(kind==='drain')e.battle.sides[0].active[0].hp=200;
 if(kind==='recoilKO')e.battle.sides[0].active[0].hp=1;
 if(kind==='knockout')e.battle.sides[1].active[0].hp=40;
 if(kind==='residual'){
  e.battle.sides[0].active[0].setStatus('tox');e.battle.sides[1].active[0].setStatus('brn');
  e.battle.field.setWeather('sandstorm',e.battle.sides[0].active[0]);
 }
 if(kind==='residualKO'){e.battle.sides[0].active[0].hp=1;e.battle.sides[0].active[0].setStatus('psn');}
 const initial=[e.frame(0),e.frame(1)];
 for(const p of [0,1]){
  const f=e.frame(p);e.choose(p,f.decisionID,f.slots.map((slot,i)=>({kind:'move',index:1,target:slot.moves[0].targetRequired ? 1:0})));
 }
 return {initial,resolved:[e.frame(0),e.frame(1)]};
}
function fixtures(){return Object.fromEntries(['singles','doubles'].flatMap(mode=>['multi','drain','recoil','recoilKO','spread','guard','knockout','residual','residualKO'].map(kind=>[mode+'-'+kind,run(mode,kind)])));}
module.exports={fixtures};
if(require.main===module)process.stdout.write(JSON.stringify(fixtures()));
