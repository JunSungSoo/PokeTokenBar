'use strict';
const {Battle, Dex, Pokemon} = require('pokemon-showdown');
const crypto = require('node:crypto');
const {battleDex,heldItem,allowed:allowedItems,allowedFairyMoves}=require('./held-items.cjs');
const REVISION = 'ptb-bw2-owned-stats-v1/showdown-0.11.11/move-details-v1/species-clause-v1/effects-v2/stats-stages-v1/move-targets-v1/final-team-v1/six-hidden-order-v1/field-state-v1/event-notices-v1/field-timers-v1/move-accuracy-v1/bring-six-pick-three-four-v1/public-roster-preview-v1/locked-roster-v1/action-scenes-v1/held-items-mega-v1/item-clause-v1/gen6-fairy-moves-v1';
const keys = ['hp','atk','def','spa','spd','spe'];
function validateTeam(team, count) {
  if (!Array.isArray(team) || team.length !== count) throw Error(`Select exactly ${count} Pokémon`);
  const ids = new Set(), speciesIDs = new Set(), items=new Set();
  return team.map(mon => {
    if (!mon.id || ids.has(mon.id)) throw Error('Duplicate individual');
    ids.add(mon.id);
    const dex = Dex.mod('gen5');
    const species = dex.species.get(mon.species);
    if(species.isMega)throw Error('Register the base Pokémon, not its Mega form');
    const item=heldItem(mon.item,species);
    if(item){if(items.has(item))throw Error('Duplicate held item');items.add(item);}
    if (!species.exists || species.gen > 5 || species.num < 1 || species.num > 649) throw Error('Unsupported species');
    if (species.num === 493) throw Error('Arceus cannot battle: its type depends on a held item.');
    if (speciesIDs.has(species.num)) throw Error('Duplicate species: only one Pokémon of each species per team.');
    speciesIDs.add(species.num);
    if (!Number.isInteger(mon.level) || mon.level < 5 || mon.level > 100) throw Error('Invalid level');
    for (const k of keys) if (!Number.isInteger(mon.stats?.[k]) || mon.stats[k] < 1 || mon.stats[k] > 1000) throw Error('Invalid stat');
    if (species.num === 292 && mon.stats.hp !== 1) throw Error('Shedinja must have 1 HP');
    let ability = dex.abilities.get(mon.ability);
    if (mon.form && species.forme && mon.abilitySlot && !Object.values(species.abilities).includes(ability.name)) {
      const slot = mon.abilitySlot === 3 ? 'H' : String(mon.abilitySlot - 1);
      ability = dex.abilities.get(species.abilities[slot] || '');
    }
    if (!ability.exists || ability.gen > 5 || !Object.values(species.abilities).includes(ability.name)) {
      throw Error(`${species.name}: ability is incompatible with generation V (${mon.ability})`);
    }
    if (!Array.isArray(mon.moves) || mon.moves.length < 1 || mon.moves.length > 4 || new Set(mon.moves).size !== mon.moves.length) throw Error('Invalid moves');
    for (const name of mon.moves) {
      const move = battleDex().moves.get(name);
      if (!move.exists || (move.gen > 5 && !allowedFairyMoves.has(move.id))) throw Error(`Unsupported move: ${name}`);
    }
    if (!keys.every(k => Number.isInteger(mon.ivs?.[k]) && mon.ivs[k] >= 0 && mon.ivs[k] <= 31)) throw Error('Invalid IVs');
    const nature = dex.natures.get(mon.nature);
    if (!nature.exists) throw Error('Invalid nature');
    return {name: species.name, species: species.name, level: mon.level, gender: mon.gender || '',
      ability: ability.name, nature: nature.name, moves: mon.moves, ivs: mon.ivs,
      evs: Object.fromEntries(keys.map(k => [k,0])), shiny: !!mon.shiny, item,
      ptbMegaStats:allowedItems.get(item)?.mega?.stats, ptbStats: {...mon.stats}, ptbBaseStats: {...species.baseStats}, ptbID: mon.id, ptbForm: mon.form, ptbMoves: mon.moves};
  });
}
function publicLog(log, player, bounded = true) {
  const result = [];
  for (let i=0; i<log.length; i++) {
    if (log[i].startsWith('|split|')) {
      const own = log[i] === `|split|p${player + 1}`;
      const line = log[i + (own ? 1 : 2)];
      if (line) result.push(line);
      i += 2;
    } else if (!log[i].startsWith('|debug|') && !log[i].startsWith('|error|')) result.push(log[i]);
  }
  return bounded ? result.slice(-160) : result;
}
function currentForm(p) {
  const defaults={201:'a',351:'normal',386:'normal',412:'plant',413:'plant',421:'overcast',422:'west',423:'west',479:'normal',487:'altered',492:'land',493:'normal',550:'red-striped',555:'standard',585:'spring',586:'spring'};
  const actual=(p.species.forme || '').toLowerCase().replace(/ /g,'-');
  if (actual) return actual;
  if ([201,422,423,585,586].includes(p.species.num) && p.baseSpecies.num===p.species.num) return p.set.ptbForm || defaults[p.species.num];
  return defaults[p.species.num] || null;
}
class OwnedBattle {
  constructor(mode, teams, seed = Array.from({length:4}, () => crypto.randomInt(65536))) {
    if (!['singles','doubles'].includes(mode)) throw Error('Invalid mode');
    const count = 6;
    // Register six; only the ordered first three/four enter the simulation.
    // Unselected reserves cannot switch in, receive effects or prevent a loss.
    const battleSize = mode === 'singles' ? 3 : 4;
    const sets = teams.map(t => validateTeam(t, count).slice(0, battleSize));
    this.errors = [];
    this.inputCounter = 0;
    battleDex();
    this.battle = new Battle({format: {
      ...Dex.formats.get('gen5customgame'),
      id: 'ptbownedstats', name:'PokeTokenBar BW2 + Mega', mod:'ptbmegabw2', gameType:mode,
      ruleset:['Cancel Mod'],
      pokemon:{updateMaxHp(){
        // Mega forms retain the owned individual's HP scale and current damage.
        if(this.species.isMega && this.set.ptbStats)return;
        return Pokemon.prototype.updateMaxHp.call(this);
      }},
      battle: {
        spreadModify(base, set) {
          const original = Battle.prototype.spreadModify.call(this, base, set);
          // Only the original species uses imported stats. Genuine form changes keep engine mechanics.
          if (set.ptbStats && keys.every(k => base[k] === set.ptbBaseStats[k])) return {...set.ptbStats};
          if(set.ptbMegaStats && keys.every(k=>base[k]===set.ptbMegaStats[k])){
            const baseline=Battle.prototype.spreadModify.call(this,set.ptbBaseStats,set);
            return Object.fromEntries(keys.map(k=>[k,k==='hp'?set.ptbStats.hp:Math.max(1,set.ptbStats[k]+original[k]-baseline[k])]));
          }
          return original;
        }
      }
    }, seed, send:(type, data) => {
      const text = Array.isArray(data) ? data.join('\n') : String(data);
      if (type === 'sideupdate' && text.includes('|error|')) this.errors.push(text);
    }});
    // Observe the actual initialized timer, including callbacks and successful restarts.
    // Weak keys expire with removed effects; no battle rules or durations are modified.
    this.fieldDurations = new WeakMap();
    const singleEvent = this.battle.singleEvent;
    const durations = this.fieldDurations;
    this.battle.singleEvent = function(event, effect, state, ...args) {
      const result = singleEvent.call(this, event, effect, state, ...args);
      if (['FieldStart','FieldRestart','SideStart','SideRestart','TerrainStart','TerrainRestart'].includes(event) && result && state?.duration > 0) {
        durations.set(state, state.duration);
      }
      return result;
    };
    // Observe protocol emission without changing the simulator's action queue or RNG.
    // Capture immutable, perspective-filtered state at each state-bearing log entry.
    // The outer depth keeps private split lines atomic (never leak the secret branch).
    this.scenes = [[], []];
    let emissionDepth = 0;
    for (const method of ['add', 'addMove', 'addSplit']) {
      const original = this.battle[method];
      const owner = this;
      this.battle[method] = function(...args) {
        const start = this.log.length;
        emissionDepth++;
        try { return original.apply(this, args); }
        finally {
          emissionDepth--;
          if (!emissionDepth && this.sides.every(s=>s?.pokemon?.length)) owner.captureScenes(start);
        }
      };
    }
    this.battle.setPlayer('p1',{name:'p1',team:sets[0]});
    this.battle.setPlayer('p2',{name:'p2',team:sets[1]});
    // No PP Ups: the app has no PP-Up inventory.
    for (const side of this.battle.sides) for (const p of side.pokemon) {
      for (const m of p.moveSlots) m.pp = m.maxpp = this.battle.dex.moves.get(m.id).pp;
      p.baseMoveSlots = p.moveSlots.map(m => ({...m}));
    }
    // Starting without Team Preview creates requests before the no-PP-Up adjustment.
    this.battle.makeRequest('move');
    this.battle.sendUpdates();
  }
  choose(player, decisionID, actions, order) {
    if (![0,1].includes(player) || this.battle.ended) throw Error('Battle is not accepting commands');
    if (this.frame(player).decisionID !== decisionID) throw Error('Stale battle command');
    const side = this.battle.sides[player];
    if (side.isChoiceDone() || side.activeRequest?.wait) throw Error('Already submitted');
    let command;
    if (side.activeRequest?.teamPreview) {
      if (!Array.isArray(order) || order.length !== side.pokemon.length || new Set(order).size !== order.length || order.some(i => !Number.isInteger(i) || i < 1 || i > side.pokemon.length)) throw Error('Invalid lead order');
      command = `team ${order.join('')}`;
    } else {
      if (!Array.isArray(actions) || actions.length !== side.active.length) throw Error('Choose every active slot');
      command = actions.map(a => {
        if (a.kind === 'pass') return 'pass';
        if (a.kind === 'switch' && Number.isInteger(a.index) && a.index >= 1 && a.index <= side.pokemon.length) return `switch ${a.index}`;
        if (a.kind === 'move' && Number.isInteger(a.index) && a.index >= 1 && a.index <= 4 && Number.isInteger(a.target) && Math.abs(a.target) <= 2) return `move ${a.index}${a.target ? ' '+a.target : ''}${a.mega===true ? ' mega':''}`;
        throw Error('Invalid action');
      }).join(', ');
    }
    this.errors = [];
    const regenerators = this.battle.getAllActive().filter(p=>p.getAbility().id==='regenerator')
      .map(p=>({pokemon:p,hp:p.hp,label:p.toString()}));
    if (!this.battle.choose(`p${player+1}`,command)) throw Error(this.errors.join(' ').replace(/^.*\|error\|/, '') || 'Illegal battle command');
    // Regenerator heals silently in the upstream simulator. Report actual owned HP changes
    // privately; never disclose the opponent's bench HP or an unrevealed ability.
    for (const {pokemon:p,hp,label} of regenerators) {
      if (!p.isActive && !p.fainted && p.hp>hp) {
        this.battle.addSplit(p.side.id,['-heal',label,`${p.hp}/${p.maxhp}`,'[from] ability: Regenerator']);
      }
    }
    this.battle.sendUpdates();
  }
  surrender(player) {
    if (![0,1].includes(player)) throw Error('Invalid player');
    if (!this.battle.ended) this.battle.win(`p${2-player}`);
    this.battle.sendUpdates();
  }
  captureScenes(start) {
    const b=this.battle;
    for(const player of [0,1]) {
      const previous=publicLog(b.log.slice(0,start),player,false).length;
      const added=publicLog(b.log.slice(start),player,false);
      for(const [index,line] of added.entries()) {
        // Ignore housekeeping, but retain all public changes, switches, failures and fainting.
        if(!/^\|(move|switch|drag|replace|faint|cant|detailschange|swap|-[^|]+)\|/.test(line)) continue;
        this.scenes[player].push({id:previous+index,...this.scene(player)});
      }
      const offset=Math.max(0,previous+added.length-160);
      this.scenes[player]=this.scenes[player].filter(s=>s.id>=offset);
    }
  }
  scene(player) {
    const b=this.battle, side=b.sides[player];
    const mon = (p, own) => {
      const appearance = !own && p.illusion ? p.illusion : p;
      return {id:p.set.ptbID, speciesID:appearance.species.num, name:appearance.species.name,
      level:p.level, shiny:!!appearance.set.shiny, form:currentForm(appearance), active:p.side.active.includes(p), fainted:p.fainted || p.hp === 0,
      hp:own ? p.hp : Math.ceil(p.hp / p.maxhp * 100), maxHP:own ? p.maxhp : 100,
      status:p.status || '', stats:own ? {hp:p.maxhp,...p.storedStats} : undefined,
      boosts:own ? {...p.boosts} : undefined, ability:own ? p.getAbility().name : undefined, item:own ? p.item:undefined, mega:!!appearance.species.isMega};
    };
    // Only public battlefield conditions and their actual finite durations.
    const visibleSide = new Set(['reflect','lightscreen','safeguard','mist','tailwind','stealthrock','spikes','toxicspikes','luckychant','rainbow','swamp','seaoffire']);
    const timing = state => state?.duration > 0 ? {remaining:state.duration,maximum:this.fieldDurations.get(state) || state.duration} : null;
    const sideEffects = target => Object.keys(target.sideConditions).filter(id=>visibleSide.has(id)).sort().map(id=>({id,layers:target.sideConditions[id].layers || 1,timing:timing(target.sideConditions[id])}));
    const field = {weather:b.field.weather || '', weatherSuppressed:!!b.field.weather && b.field.suppressingWeather(),
      weatherTiming:timing(b.field.weatherState),
      conditions:[...Object.keys(b.field.pseudoWeather),...(b.field.terrain?[b.field.terrain]:[])].sort(),
      conditionTimings:Object.fromEntries([...Object.entries(b.field.pseudoWeather),...(b.field.terrain?[[b.field.terrain,b.field.terrainState]]:[])].flatMap(([id,state])=>timing(state)?[[id,timing(state)]]:[])),
      ownSide:sideEffects(side), foeSide:sideEffects(side.foe)};
    for(const id of ['mudsport','watersport'])if(b.getAllActive().some(p=>p.volatiles[id]))field.conditions.push(id);
    return {turn:b.turn,own:side.pokemon.map(p=>mon(p,true)),foe:side.foe.active.filter(Boolean).map(p=>mon(p,false)),field};
  }
  frame(player) {
    const b=this.battle, side=b.sides[player], request=side.activeRequest || {};
    const appearance = target => target.side === side ? target : (target.illusion || target);
    const visibleTypes = target => {
      if (!target.illusion || target.side === side) return target.getTypes();
      const slot = target.getSlot() + ':';
      // Type-changing status moves are public even while Illusion remains intact.
      for (let i=b.log.length-1;i>=0;i--) {
        const f=b.log[i].split('|');
        if (!(f[2] || '').startsWith(slot)) continue;
        if (f[1]==='-start' && f[3]==='typechange') return f[4].split('/');
        if (['switch','drag','replace'].includes(f[1])) break;
      }
      return target.illusion.getTypes();
    };
    const benches = side.pokemon.filter(p => !p.isActive && !p.fainted).length;
    let forcedCount = 0;
    const slots = side.active.map((p, i) => {
      const force = !!request.forceSwitch?.[i] && ++forcedCount <= benches;
      const data=request.active?.[i];
      return {slot:i, mustSwitch:force, canPass: request.forceSwitch ? !force : !p || p.fainted,
        trapped:!!data?.trapped,canMegaEvo:!!data?.canMegaEvo,
        moves:(data?.moves || []).map((m,j) => {
          const move=b.dex.moves.get(m.id);
          let type = move.id === 'hiddenpower' ? p.hpType : move.type;
          if(type==='Normal')for(const [ability,converted]of Object.entries({pixilate:'Fairy',aerilate:'Flying',refrigerate:'Ice',dragonize:'Dragon'})){
            if(p.hasAbility(ability)){type=converted;break;}
          }
          const matchups = side.foe.active.filter(t=>t && !t.fainted).map(t=>({
            location:p.getLocOf(t), name:appearance(t).species.name,
            multiplier:move.category==='Status' ? null : b.dex.getImmunity(type,visibleTypes(t)) ? 2 ** b.dex.getEffectiveness(type,visibleTypes(t)) : 0
          }));
          const selectable = ['normal','any','adjacentAlly','adjacentAllyOrSelf','adjacentFoe'].includes(m.target);
          const targets = selectable && b.gameType === 'doubles' ? [...side.foe.active,...side.active]
            .filter(t => t && !t.fainted && b.validTargetLoc(p.getLocOf(t),p,m.target))
            .map(t => ({location:p.getLocOf(t),name:`${t.side===side ? 'Ally' : 'Foe'} ${Math.abs(p.getLocOf(t))} · ${appearance(t).species.name}`})) : [];
          return {index:j+1,name:m.move,apiName:(p.set.ptbMoves || []).find(n=>b.dex.moves.get(n).id===m.id) || move.name.toLowerCase().replace(/ /g,'-'),pp:m.pp ?? 1,maxPP:m.maxpp ?? 1,disabled:!!m.disabled,type,
            power:move.basePower,accuracy:move.accuracy,category:move.category,description:move.desc || move.shortDesc || '',matchups,
            targetRequired:selectable && b.gameType==='doubles',targets,targetScope:m.target};
        })};
    });
    const allLog=publicLog(b.log,player,false), logOffset=Math.max(0,allLog.length-160);
    const log=allLog.slice(logOffset);
    const position = token => {
      const match=/^p([12])([ab])(?::|$)/.exec(token);
      return match ? {own:Number(match[1])-1===player,slot:match[2]==='a'?0:1} : null;
    };
    const effects=log.flatMap((entry,index)=>{
      if(!entry.startsWith('|move|')) return [];
      const parts=entry.split('|'), source=position(parts[2]);
      if(!source) return [];
      const move=b.dex.moves.get(parts[3]);
      const spread=parts.find(p=>p.startsWith('[spread] '));
      const tokens=spread ? spread.slice(9).split(',') : [parts[4] || parts[2]];
      let next=index+1;while(next<log.length && !log[next].startsWith('|move|') && !log[next].startsWith('|turn|')) next++;
      const following=log.slice(index+1,next);
      const targets=tokens.flatMap(token=>{
        const target=position(token.trim());if(!target) return [];
        const blocked=following.some(line=>{
          const fields=line.split('|');
          return ((fields[1]==='-immune' || fields[1]==='-miss' || fields[1]==='-fail') &&
            fields.slice(2).some(f=>f.slice(0,3)===token.trim().slice(0,3))) ||
            (fields[1]==='-activate' && fields[2]?.slice(0,3)===token.trim().slice(0,3) && fields[3]==='move: Protect');
        });
        return [{position:target,hit:!blocked && !parts.includes('[miss]')}];
      });
      // Use the public animation type; do not disclose IV-derived Hidden Power types to the foe.
      const charging=following.some(line=>line.startsWith('|-prepare|'+parts[2]+'|'));
      return [{id:logOffset+index,move:move.name,moveID:move.id,phase:charging?'charge':'move',type:move.type,
        category:move.category,source,targets:targets.length ? targets : [{position:source,hit:true}]}];
    });
    const decisionID = `${b.turn}:${side.requestState}:${side.activeRequest?.rqid || ''}:${b.log.length}`;
    return {revision:REVISION,turn:b.turn,decisionID,preview:!!request.teamPreview,
      waiting:!!request.wait || side.isChoiceDone() || b.ended,
      ...this.scene(player),slots,
      log,logOffset,effects,scenes:this.scenes[player].filter(s=>s.id>=logOffset), ended:b.ended,
      winner:b.ended ? (b.winner==='p1' ? 0 : b.winner==='p2' ? 1 : -1) : null};
  }
}
module.exports={OwnedBattle,validateTeam,REVISION};
if (require.main === module) {
  let engine;
  require('node:readline').createInterface({input:process.stdin,crlfDelay:Infinity}).on('line',line=>{
    if (Buffer.byteLength(line)>262144) {process.exitCode=1;return;}
    try {
      const input=JSON.parse(line);
      if (input.kind==='validate') {
        if (!['singles','doubles'].includes(input.mode)) throw Error('Invalid mode');
        const sets=validateTeam(input.team,6);
        process.stdout.write(JSON.stringify({validated:true,abilities:sets.map(p=>p.ability)})+'\n');
        return;
      }
      if (input.kind==='start') engine=new OwnedBattle(input.mode,input.teams,input.seed);
      else if (!engine) throw Error('Engine not started');
      else if (input.kind==='choose') engine.choose(input.player,input.decisionID,input.actions,input.order);
      else if (input.kind==='surrender') engine.surrender(input.player);
      else throw Error('Unknown engine command');
      process.stdout.write(JSON.stringify({id:input.id,frames:[engine.frame(0),engine.frame(1)]})+'\n');
    } catch(error) {process.stdout.write(JSON.stringify({error:String(error.message)})+'\n');}
  });
}
