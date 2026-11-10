'use strict';

const {Dex}=require('pokemon-showdown');
const REVISION='ptb-challenge-doubles-v3';
const gen5=Dex.mod('gen5');
const weatherAbilities={drizzle:'rain',drought:'sun',sandstream:'sand',snowwarning:'hail'};
const weatherMoves={raindance:'rain',sunnyday:'sun',sandstorm:'sand',hail:'hail'};
const weatherUsers={swiftswim:'rain',chlorophyll:'sun',solarpower:'sun',sandrush:'sand',sandforce:'sand',icebody:'hail'};
const spreadImmunities={Ground:['levitate'],Water:['waterabsorb','stormdrain','dryskin'],
  Electric:['voltabsorb','lightningrod','motordrive'],Fire:['flashfire']};
const poolCache=new Map();
const FEATURE_NAMES=['speed','fastSlowGap','bulk','offense','differentTypes','mutualTypeCover',
  'weatherAbilityPair','fakeOutAndOffense','tailwindAndOffense','trickRoomAndSlowPartner','spreadGroundWithImmunity',
  'intimidateOrRedirect','matchupAcrossRoster','matchupFloor'];

function multiplier(dex,type,types) {
  return dex.getImmunity(type,types) ? 2 ** dex.getEffectiveness(type,types) : 0;
}

function speciesProfile(name) {
  const s=gen5.species.get(name);
  if (!s.exists || s.gen>5) throw Error('Unrecognized generation V species: '+name);
  if (poolCache.has(s.id)) return poolCache.get(s.id);
  const profile={types:s.types,stats:s.baseStats,abilities:Object.values(s.abilities).map(Dex.toID),moves:gen5.species.getMovePool(s.id)};
  poolCache.set(s.id,profile);
  return profile;
}

function leadFeatures(first,second,foes) {
  const a=speciesProfile(first), b=speciesProfile(second), opponents=foes.map(speciesProfile);
  const speed=p=>p.stats.spe/100, bulk=p=>(p.stats.hp+p.stats.def+p.stats.spd)/300;
  const offense=p=>Math.max(p.stats.atk,p.stats.spa)/130;
  const weather=(x,y)=>x.abilities.some(v=>weatherAbilities[v]&&y.abilities.some(w=>weatherUsers[w]===weatherAbilities[v]));
  const support=(x,y,id)=>x.moves.has(id) ? offense(y) : 0;
  const cover=(x,y)=>gen5.types.names().filter(t=>multiplier(gen5,t,x.types)>1&&multiplier(gen5,t,y.types)<1).length;
  const ground=(x,y)=>x.moves.has('earthquake')&&(y.types.includes('Flying')||y.abilities.includes('levitate'));
  const coverages=opponents.map(foe=>Math.max(...[...a.types,...b.types].map(type=>multiplier(gen5,type,foe.types))));
  return [
    (speed(a)+speed(b))/2,Math.abs(speed(a)-speed(b)),(bulk(a)+bulk(b))/2,(offense(a)+offense(b))/2,
    Number(a.types.every(t=>!b.types.includes(t))),(cover(a,b)+cover(b,a))/6,
    Number(weather(a,b)||weather(b,a)),
    Math.max(support(a,b,'fakeout'),support(b,a,'fakeout')),
    Math.max(support(a,b,'tailwind'),support(b,a,'tailwind')),
    Math.max(a.moves.has('trickroom')?Math.max(0,1-speed(b)):0,b.moves.has('trickroom')?Math.max(0,1-speed(a)):0),
    Number(ground(a,b)||ground(b,a)),
    Number([a,b].some(p=>p.abilities.includes('intimidate')||p.moves.has('followme')||p.moves.has('ragepowder'))),
    coverages.reduce((sum,n)=>sum+Math.log2(Math.max(n,.25)),0)/opponents.length,Math.min(...coverages)
  ];
}

function actualProfile(dex,pokemon) {
  const mega=dex.items.get(pokemon.item || '').megaStone?.[pokemon.species];
  const species=dex.species.get(mega || pokemon.species);
  const ability=Dex.toID(mega ? species.abilities[0] : pokemon.ability);
  const moves=pokemon.moves.map(id=>{
    const move=dex.moves.get(id);
    if(move.id!=='hiddenpower')return move;
    const hp=gen5.getHiddenPower(pokemon.ivs);
    return {...move,type:hp.type,basePower:hp.power};
  });
  const weather=weatherAbilities[ability] || moves.map(m=>weatherMoves[m.id]).find(Boolean);
  return {species,ability,moves,weather,stats:pokemon.ptbStats};
}

function attack(dex,attacker,defender) {
  return Math.max(.08,...attacker.moves.filter(m=>m.category!=='Status').map(move=>{
    let type=move.type, power=move.basePower || 55;
    if (move.id==='weatherball'&&attacker.weather) {
      type={sun:'Fire',rain:'Water',sand:'Rock',hail:'Ice'}[attacker.weather];
      power=100;
    }
    if (spreadImmunities[type]?.includes(defender.ability)) return 0;
    const physical=move.category==='Physical';
    const offense=attacker.stats[physical?'atk':'spa'];
    const defense=defender.stats[physical?'def':'spd'];
    const stab=attacker.species.types.includes(type)?1.5:1;
    const accuracy=move.accuracy===true?1:move.accuracy/100;
    return Math.min(4,Math.sqrt(offense/defense)*power/100*stab*accuracy*multiplier(dex,type,defender.species.types));
  }));
}

function setSynergy(dex,a,b) {
  const contribution=(x,y)=>{
    const spread=x.moves.filter(m=>m.category!=='Status'&&m.target==='allAdjacent');
    const friendlyFire=spread.map(m=>spreadImmunities[m.type]?.includes(y.ability)?0:multiplier(dex,m.type,y.species.types));
    const weather=x.weather && (weatherUsers[y.ability]===x.weather ||
      y.moves.some(m=>m.id==='weatherball'||m.id==='solarbeam'&&x.weather==='sun'));
    const support=x.moves.some(m=>['fakeout','tailwind','helpinghand','followme','ragepowder'].includes(m.id));
    return (weather ? .35 : 0)+(support ? .12 : 0)+(spread.length ? .10-.15*Math.max(...friendlyFire) : 0);
  };
  return contribution(a,b)+contribution(b,a);
}

function chooseLineup(dex,trainer,registered,model=require('./challenge-doubles-lineup-model.json')) {
  // Sort the full registered roster independently of the four selected by the player.
  const opponent=registered.slice().sort((a,b)=>a.species.localeCompare(b.species,'en'));
  const names=opponent.map(p=>p.species), foes=opponent.map(p=>actualProfile(dex,p));
  const own=trainer.map(p=>actualProfile(dex,p));
  const matchups=own.map(p=>foes.map(q=>Math.log2(1+attack(dex,p,q))-.65*Math.log2(1+attack(dex,q,p))));
  let best=null,bestScore=-Infinity;
  for(let a=0;a<6;a++)for(let b=a+1;b<6;b++){
    const features=leadFeatures(trainer[a].species,trainer[b].species,names);
    const learned=features.reduce((sum,x,i)=>sum+x*model.weights[i],0);
    const leadCoverage=foes.reduce((sum,_,i)=>sum+Math.max(matchups[a][i],matchups[b][i]),0)/foes.length;
    const synergy=setSynergy(dex,own[a],own[b]);
    for(let c=0;c<6;c++)for(let d=c+1;d<6;d++){
      if([c,d].some(i=>i===a||i===b))continue;
      const lineup=[a,b,c,d];
      const coverage=foes.map((_,i)=>Math.max(...lineup.map(j=>matchups[j][i])));
      const score=coverage.reduce((sum,x)=>sum+x,0)/foes.length+.3*Math.min(...coverage)+.55*leadCoverage+
        .30*synergy+.15*learned+.10*lineup.reduce((sum,j)=>sum+matchups[j].reduce((x,y)=>x+y,0)/foes.length,0);
      if(score>bestScore){bestScore=score;best=lineup;}
    }
  }
  return [...best,...trainer.map((_,i)=>i).filter(i=>!best.includes(i))].map(i=>trainer[i]);
}

module.exports={REVISION,FEATURE_NAMES,leadFeatures,chooseLineup};
