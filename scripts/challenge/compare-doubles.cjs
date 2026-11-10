// Fixed-seed, headless per-encounter comparison. Run from any directory.
'use strict';
const {OwnedBattle}=require('../../BattleEngine/engine.cjs');
const {chooseActions,PREVIOUS_REVISION}=require('../../BattleEngine/challenge-doubles-policy.cjs');
const {encounters}=require('../../BattleEngine/challenge-opponents.json');
const doubles=require('../../BattleEngine/challenge-doubles-opponents.json');
const {allowed}=require('../../BattleEngine/held-items.cjs');
const byID=new Map(encounters.map(e=>[e.id,e]));
const playerTeams=['blue','lance1','blaine'].map(id=>byID.get(id).team.map(p=>({...p,item:allowed.has(p.item)?p.item:''})));
const variants=['singles','doubles-v1','doubles-v2'];
const fresh=()=>({games:0,wins:0,losses:0,unfinished:0,turns:0,hp:0,fainted:0,winHP:0,winFainted:0,winPPSpent:0});
const totals=Object.fromEntries(variants.map(variant=>[variant,fresh()]));
const byTrainer={};

for (const [id,sets] of Object.entries(doubles)) {
  const oldTeam=byID.get(id).team;
  const newTeam=sets.map(set=>({...oldTeam.find(p=>p.speciesID===set.speciesID),...set,abilitySlot:undefined}));
  const trainer=byTrainer[id]=Object.fromEntries(variants.map(variant=>[variant,fresh()]));
  for (const [teamIndex,player] of playerTeams.entries()) for (const replicate of [0,1]) {
    const seed=[67+teamIndex,128+replicate,306,2048];
    for (const variant of variants) {
      const mode=variant==='singles'?'singles':'doubles';
      const engine=new OwnedBattle(mode,[player,variant==='doubles-v2'?newTeam:oldTeam],seed,{
        profile:'challenge',automaticOpponent:true,expectedPolicyRevision:variant==='doubles-v1'?PREVIOUS_REVISION:undefined
      });
      const initial=engine.frame(0).resources;
      for (let i=0; i<150 && !engine.battle.ended; i++) {
        engine.runCPU();
        const frame=engine.frame(0);
        if (frame.waiting) break;
        const actions=chooseActions(engine.battle.dex,frame);
        if (actions) engine.choose(0,frame.decisionID,actions);
        else engine.submitCommand(0,'default');
      }
      const result=engine.frame(0);
      const hp=result.resources.reduce((sum,p)=>sum+p.hp,0)/result.own.reduce((sum,p)=>sum+p.maxHP,0);
      const fainted=result.resources.filter(p=>p.hp===0).length;
      const totalPP=members=>members.flatMap(p=>p.moves).reduce((sum,m)=>sum+m.pp,0);
      for (const bucket of [totals[variant],trainer[variant]]) {
        bucket.games++;
        bucket.turns+=result.turn;
        bucket.hp+=hp;
        bucket.fainted+=fainted;
        if (result.winner===0) {
          bucket.wins++;
          bucket.winHP+=hp;
          bucket.winFainted+=fainted;
          bucket.winPPSpent+=totalPP(initial)-totalPP(result.resources);
        } else if (result.winner===1) bucket.losses++;
        else bucket.unfinished++;
      }
    }
  }
}
const report=stats=>Object.fromEntries(Object.entries(stats).map(([mode,s])=>[mode,{
  playerWins:s.wins,games:s.games,losses:s.losses,unfinished:s.unfinished,
  averageTurns:+(s.turns/s.games).toFixed(1),
  remainingHPPercent:+(100*s.hp/s.games).toFixed(1),
  averageFainted:+(s.fainted/s.games).toFixed(2),
  winHPPercent:s.wins?+(100*s.winHP/s.wins).toFixed(1):null,
  winAverageFainted:s.wins?+(s.winFainted/s.wins).toFixed(2):null,
  winPPSpent:s.wins?+(s.winPPSpent/s.wins).toFixed(1):null
}]));
console.log(JSON.stringify({totals:report(totals),byTrainer:Object.fromEntries(Object.entries(byTrainer).map(([id,stats])=>[id,report(stats)]))},null,2));
