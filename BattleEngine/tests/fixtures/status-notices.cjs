// Actual public scene logs for the native transient-announcement regression.
const assert = require('node:assert/strict');
const {OwnedBattle} = require('../../engine.cjs');
function team(prefix, move, speed) {
  return [['Raichu','Static'],['Blissey','Natural Cure'],['Vaporeon','Water Absorb'],['Slowbro','Own Tempo'],['Scizor','Technician'],['Parasect','Effect Spore']].map(([species,ability],i)=>({id:prefix+i,species,ability,moves:[move],level:50,nature:'Hardy',ivs:{hp:31,atk:31,def:31,spa:31,spd:31,spe:31},stats:{hp:500,atk:100,def:300,spa:100,spd:300,spe:speed}}));
}
const result = {};
for (const move of ['fakeout','spore','toxic','willowisp','sandstorm']) {
  const own=team('a',move,200);own[0].species='Smeargle';own[0].ability='Own Tempo';
  const engine=new OwnedBattle('singles',[own,team('b','tackle',50)],[1,2,3,4]);
  for (let turn=0;turn<(move==='willowisp'?3:1);turn++) {
    for (const p of [0,1]) { const f=engine.frame(p);engine.choose(p,f.decisionID,[{kind:'move',index:1,target:0}]); }
  }
  result[move]=[engine.frame(0),engine.frame(1)];
}
assert(result.fakeout[0].log.some(l=>l.startsWith('|cant|')&&l.includes('|flinch')));
assert(result.spore[0].log.some(l=>l.startsWith('|cant|')&&l.includes('|slp')));
for (const [move,cause] of [['toxic','psn'],['willowisp','brn'],['sandstorm','Sandstorm']]) {
  assert(result[move][0].log.some(l=>l.startsWith('|-damage|')&&l.includes('[from] '+cause)),move);
}
process.stdout.write(JSON.stringify(result));
