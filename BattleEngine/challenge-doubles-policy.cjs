'use strict';

// This policy reads its own request and public opponent state. Showdown still
// resolves damage, secondary effects, priority and the order of execution.
const REVISION = 'ptb-challenge-doubles-v2';
const PREVIOUS_REVISION = 'ptb-challenge-doubles-v1';
const weatherMoves = {sunnyday:'sunnyday',raindance:'raindance',sandstorm:'sandstorm',hail:'hail'};
const speedWeather = {'swift swim':'raindance',chlorophyll:'sunnyday','sand rush':'sandstorm'};
const guards = new Set(['protect','detect','endure','quickguard','wideguard']);
const recovery = new Set(['recover','slackoff','roost','softboiled','milkdrink','moonlight','morningsun','synthesis']);
const clamp = (value, minimum, maximum) => Math.max(minimum,Math.min(maximum,value));
const alive = p => p && !p.fainted;
const hp = p => p.hp / p.maxHP;
const stage = n => n >= 0 ? (2+n)/2 : 2/(2-n);
const ability = p => (p?.ability || '').toLowerCase();
const weatherType = (weather,type) => weather === 'sunnyday' ? (type === 'Fire' ? 1.5 : type === 'Water' ? .5 : 1) :
  weather === 'raindance' ? (type === 'Water' ? 1.5 : type === 'Fire' ? .5 : 1) : 1;

function effectiveness(dex,type,target) {
  const types=dex.species.get(target.name).types;
  return dex.getImmunity(type,types) ? 2 ** dex.getEffectiveness(type,types) : 0;
}

function allyImpact(dex,move,ally) {
  const a=ability(ally);
  if (move.type==='Ground' && a==='levitate' || move.type==='Fire' && a==='flash fire' ||
      move.type==='Electric' && ['lightning rod','motor drive','volt absorb'].includes(a) ||
      move.type==='Water' && ['water absorb','dry skin','storm drain'].includes(a)) return 0;
  return effectiveness(dex,move.type,ally);
}

function speed(dex,p) {
  return p.effectiveSpeed ?? (2*dex.species.get(p.name).baseStats.spe+36)*p.level/100*
    stage(p.speedStage || 0)*(p.status==='par' ? .25 : 1);
}

function statusScore(context,p,move,target,meta) {
  const {dex,field,weather,enemies,allies}=context, id=meta.id;
  const ownEffect = name => field.ownSide.some(effect=>effect.id===name);
  if (weatherMoves[id]) {
    if (weather===id || field.weatherSuppressed) return -1;
    return allies.reduce((sum,ally)=>sum+(speedWeather[ability(ally)]===id ? .20 : 0)+
      (dex.species.get(ally.name).types.some(type=>weatherType(id,type)>1) ? .14 : 0),0)-.06;
  }
  if (id==='tailwind' || id==='trickroom') {
    if (id==='tailwind' ? ownEffect(id) : field.conditions.includes(id)) return -1;
    const faster = allies.filter(a=>enemies.some(e=>speed(dex,a)>speed(dex,e))).length;
    return faster < allies.length ? .39 : .07;
  }
  if (id==='reflect' || id==='lightscreen') return ownEffect(id) ? -1 : .27;
  if (recovery.has(id)) {
    const threshold=p.cpuRecoveryThreshold ?? .52;
    return hp(p)<threshold ? (p.cpuRecoveryThreshold ? .9 : .62)*(1-hp(p)) : -.4;
  }
  if (id==='rest') return hp(p)<.27 && !p.effects?.includes('taunt') ? .37 : -.5;
  if (id==='helpinghand') return .01;
  if (id==='ragepowder' || id==='followme') return .04;
  if (guards.has(id)) {
    const danger = context.danger(p);
    return (meta.id==='protect' || meta.id==='detect' ? (1-hp(p))*.19+danger*.035 : .03) - .14;
  }
  if (meta.status) {
    if (!alive(target) || target.status) return -1;
    const types=dex.species.get(target.name).types;
    if (meta.status==='brn'&&types.includes('Fire') || meta.status==='par'&&!dex.getImmunity(move.type,types)) return -1;
    return {slp:.37,brn:.24,par:.21,tox:.19,psn:.14}[meta.status] ?? .13;
  }
  if (meta.boosts) {
    const usable=Object.entries(meta.boosts).some(([stat,amount])=>amount>0 && (p.boosts?.[stat] || 0)<4);
    return usable ? (hp(p)>.6 ? .26 : .04) : -.6;
  }
  if (id==='taunt' || id==='encore') return .04;
  return .02;
}

function choices(context,slot) {
  const {dex,frame,foes,weather}=context;
  if (slot.canPass) return [{action:{kind:'pass'},score:0,hits:[]}];
  if (slot.mustSwitch) return frame.own.flatMap((p,i)=>alive(p)&&!p.active ?
    [{action:{kind:'switch',index:i+1},score:-i*.0001,hits:[]}] : []);
  const p=frame.own[slot.slot];
  if (!alive(p)) return [];
  return slot.moves.filter(move=>!move.disabled && move.pp>0).flatMap(move=>{
    const meta=dex.moves.get(move.apiName), id=meta.id;
    const ally=frame.own[1-slot.slot];
    const targets=move.targetRequired ? move.targets.map(t=>t.location) : [0];
    return targets.flatMap(target=>{
      const targetMon=target>0 ? foes.get(target) : frame.own[-target-1];
      if (move.category!=='Status' && target<0) return [];
      const action={kind:'move',index:move.index,target};
      const makeChoice = mega => {
        const result={action:mega?{...action,mega:true}:action,id,score:mega ? .30 : 0,hits:[],slot:slot.slot,
          allyHit:0,target,targetMon};
        const forecastWeather=mega && p.item==='charizarditey' ? 'sunnyday' : weather;
        if (forecastWeather!==weather) result.weather=forecastWeather;
        const accuracy=move.accuracy===true ? 1 : (move.accuracy || 100)/100;
        if (move.category==='Status') {
          result.score+=accuracy*statusScore(context,p,move,targetMon,meta);
          return result;
        }
        if (id==='fakeout' && p.activeMoveActions>0) {
          result.score-=1;
          return result;
        }
        const spread=['allAdjacent','allAdjacentFoes','all'].includes(move.targetScope);
        const count=foes.size+(move.targetScope==='allAdjacent'&&alive(ally)?1:0);
        const power=(move.power || (id==='struggle'?50:45))*(spread&&count>1?.75:1);
        const attack=move.category==='Physical'?'atk':'spa', defense=move.category==='Physical'?'def':'spd';
        const atk=(p.stats?.[attack] || 150)*stage(p.boosts?.[attack] || 0);
        const burn=p.status==='brn' && attack==='atk' && ability(p)!=='guts' ? .5 : 1;
        const type=id==='weatherball' && forecastWeather ? ({sunnyday:'Fire',raindance:'Water',sandstorm:'Rock',hail:'Ice'}[forecastWeather] || move.type) : move.type;
        const effectivePower=id==='weatherball'&&forecastWeather ? 100*(spread&&count>1?.75:1) : power;
        const stab=dex.species.get(p.name).types.includes(type)?1.5:1;
        const charge=id==='solarbeam' && forecastWeather!=='sunnyday' ? .5 : 1;
        const scale=(2*p.level/5+2)*effectivePower*atk*burn*stab*weatherType(forecastWeather,type)*charge*.925/50;
        for (const [loc,foe] of foes) {
          if (!spread && target && target!==loc) continue;
          const species=dex.species.get(foe.name);
          const estimatedHP=(2*species.baseStats.hp+31)*foe.level/100+foe.level+10;
          const estimatedDefense=(2*species.baseStats[defense]+31)*foe.level/100+5;
          const typeEffect=type===move.type ? move.matchups.find(m=>m.location===loc)?.multiplier : effectiveness(dex,type,foe);
          const damage=(scale/estimatedDefense+2)/estimatedHP*(typeEffect ?? 1);
          const before = meta.priority>0 || (speed(dex,p)>speed(dex,foe))!==frame.field.conditions.includes('trickroom');
          result.hits.push({loc,damage,accuracy,before});
          if (id==='fakeout' && damage>0) result.score+=.24;
        }
        if (move.targetScope==='allAdjacent' && alive(ally)) {
          result.allyHit=(scale/(ally.stats?.[defense] || 150)+2)/ally.maxHP*allyImpact(dex,{type},ally)*accuracy;
        }
        return result;
      };
      return slot.canMegaEvo ? [makeChoice(true),makeChoice(false)] : [makeChoice(false)];
    });
  });
}

function evaluate(context,pair) {
  const [first,second]=pair;
  if (first?.action.kind==='switch' && second?.action.kind==='switch' && first.action.index===second.action.index ||
      first?.action.mega && second?.action.mega) return -Infinity;
  let score=0;
  for (let i=0;i<pair.length;i++) {
    const choice=pair[i], partner=pair[1-i], ally=context.frame.own[1-i];
    score+=choice.score;
    const partnerGuards=['protect','detect'].includes(partner?.id);
    const guardReliability=partnerGuards ? (ally?.guardStreak ? .3 : 1) : 0;
    score-=choice.allyHit ? (Math.min(choice.allyHit,hp(ally))*1.45+(choice.allyHit>=hp(ally)?.55:0))*(1-guardReliability) : 0;
    if (choice.id==='helpinghand') score+=partner?.hits.length && partner.action.kind==='move' ? .22 : -.5;
    if (choice.id==='ragepowder' || choice.id==='followme') {
      score+=partner?.hits.length && hp(context.frame.own[i])>.65 && hp(ally)<.45 ? .33 : -.25;
    }
    if (guards.has(choice.id) && guards.has(partner?.id)) score-=.12;
    if (choice.id && choice.id===partner?.id &&
        (weatherMoves[choice.id] || ['tailwind','trickroom','reflect','lightscreen'].includes(choice.id) ||
        (choice.target>0 && context.dex.moves.get(choice.id).status && choice.target===partner.target))) score-=.4;
    if ((weatherMoves[choice.id] || choice.weather) && partner?.hits.length) {
      const next=choice.weather || weatherMoves[choice.id];
      const partnerMove=context.frame.slots[partner.slot].moves.find(m=>m.index===partner.action.index);
      const firstActor=choice.weather || speed(context.dex,context.frame.own[i])>speed(context.dex,ally);
      if (firstActor && next!==context.weather && !context.frame.field.weatherSuppressed) {
        const delta=partner.id==='solarbeam' && next==='sunnyday' ? .18 :
          (weatherType(next,partnerMove.type)-weatherType(context.weather,partnerMove.type))*.35;
        score+=delta;
      }
    }
  }
  for (const [loc,foe] of context.foes) {
    let outcomes=[{remaining:hp(foe),probability:1}];
    const hits=pair.flatMap(c=>c.hits.filter(h=>h.loc===loc)).sort((a,b)=>Number(b.before)-Number(a.before));
    for (const hit of hits) {
      outcomes=outcomes.flatMap(({remaining,probability})=>{
        const landed=probability*hit.accuracy, damage=Math.min(remaining,hit.damage);
        score+=damage*landed*(hit.before?1.08:1);
        return [
          {remaining:remaining-damage,probability:landed},
          {remaining,probability:probability-landed}
        ];
      });
    }
    score+=.52*outcomes.reduce((sum,o)=>sum+(o.remaining===0?o.probability:0),0);
  }
  return score;
}

function chooseActions(dex,frame) {
  const foes=new Map(frame.foe.flatMap((p,i)=>alive(p)?[[p.position ?? i+1,p]]:[]));
  const allies=frame.own.filter(p=>p.active && alive(p)), enemies=[...foes.values()];
  const context={dex,frame,foes,allies,enemies,field:frame.field,
    weather:frame.field.weatherSuppressed?'':frame.field.weather,
    danger:p=>enemies.reduce((sum,foe)=>sum+Math.max(...dex.species.get(foe.name).types.map(type=>effectiveness(dex,type,p))),0)};
  const [left,right]=frame.slots.map(slot=>choices(context,slot));
  let best=null, bestScore=-Infinity;
  for (const a of left || []) for (const b of right || [null]) {
    const pair=b?[a,b]:[a], score=evaluate(context,pair);
    if (score>bestScore) {bestScore=score;best=pair.map(c=>c.action);}
  }
  return best;
}

module.exports={REVISION,PREVIOUS_REVISION,chooseActions};
