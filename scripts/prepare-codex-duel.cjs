// Local interactive duel fixtures; never reads or changes the user's collection.
const fs = require('node:fs');
const {Dex, Teams} = require('../BattleEngine/node_modules/pokemon-showdown');
const {OwnedBattle, validateTeam} = require('../BattleEngine/engine.cjs');
const dex = Dex.mod('gen5');
const finals = new Set(require('../Sources/PokeTokenBar/Resources/BattleText/final-species.json'));
const dir = 'build/codex-duel';
fs.mkdirSync(dir, {recursive: true});
function team(prefix) {
  const result = [], used = new Set();
  while (result.length < 6) {
    for (const set of Teams.generate('gen5randombattle')) {
      const species = dex.species.get(set.species);
      if (!finals.has(species.num) || species.num === 493 || species.forme || used.has(species.num)) continue;
      const ivs = Object.fromEntries(['hp','atk','def','spa','spd','spe'].map(k => [k, set.ivs?.[k] ?? 31]));
      const stats = Object.fromEntries(Object.entries(species.baseStats).map(([k, base]) =>
        [k, k === 'hp' ? species.num === 292 ? 1 : Math.floor((2*base+ivs[k])*0.5)+60 : Math.floor((2*base+ivs[k])*0.5)+5]));
      result.push({id:prefix+result.length,speciesID:species.num,species:species.name,displayName:species.name,
        level:50,ability:set.ability,nature:'Hardy',gender:set.gender || '',shiny:false,ivs,stats,moves:set.moves});
      used.add(species.num);
      if (result.length === 6) break;
    }
  }
  validateTeam(result, 6);
  return result;
}
function megaTestTeam(prefix) {
  const members=[['Charizard','charizarditex',['flamethrower','airslash','dragonclaw','protect']],['Blastoise','leftovers',['surf','icebeam','protect','aquatail']],['Venusaur','miracleseed',['energyball','sludgebomb','protect','synthesis']],['Raichu','sitrusberry',['thunderbolt','quickattack','protect','voltswitch']],['Gengar','lifeorb',['shadowball','psychic','thunderbolt','protect']],['Snorlax','lumberry',['bodyslam','crunch','rest','earthquake']]];
  return members.map(([name,item,moves],index)=>{
    const species=dex.species.get(name),ivs=Object.fromEntries(['hp','atk','def','spa','spd','spe'].map(k=>[k,17]));
    const stats=Object.fromEntries(Object.entries(species.baseStats).map(([k,base])=>[k,Math.floor((2*base+17)*0.5)+(k==='hp'?60:5)]));
    return {id:prefix+index,speciesID:species.num,species:species.name,displayName:species.name,level:50,ability:species.abilities[0],nature:'Hardy',gender:'M',shiny:false,ivs,stats,moves,item};
  });
}
const megaTest=process.argv.includes('--mega-test');
const teams = megaTest ? {a:megaTestTeam('a'),b:megaTestTeam('b')} : {a:team('a'), b:team('b')};
const battle = new OwnedBattle('singles', [teams.a, teams.b]);
for (let side=0; side<2; side++) {
  const frame=battle.frame(side);
  for (const mon of frame.own) {
    const original=(side === 0 ? teams.a : teams.b).find(p => p.id === mon.id);
    if (mon.maxHP !== original.stats.hp || mon.level !== original.level) throw Error('Owned stats changed');
    for (const [key, value] of Object.entries(original.stats)) if (mon.stats[key] !== value) throw Error('Owned stat changed: '+key);
  }
}
fs.writeFileSync(dir+'/teams.json', JSON.stringify(teams));
for (const name of ['command.json','state.json']) { try { fs.unlinkSync(dir+'/'+name); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
console.log(megaTest ? 'Mega/item singles teams validated: unique held items, level 50, owned stats preserved.' : 'Random bring-six/pick-three singles teams validated: final species, no duplicates/items, level 50, owned stats preserved.');
