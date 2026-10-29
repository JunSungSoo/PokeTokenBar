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
const competitive=process.argv.includes('--competitive');
function competitiveTeam() {
  const members=[
    ['Garchomp',443,45,'Rough Skin','Jolly','choicescarf',['earthquake','outrage','stoneedge','fireblast']],
    ['Metagross',374,3,'Clear Body','Adamant','metagrossite',['meteormash','zenheadbutt','icepunch','bulletpunch']],
    ['Snorlax',446,50,'Thick Fat','Careful','leftovers',['bodyslam','crunch','curse','rest']],
    ['Excadrill',529,120,'Mold Breaker','Jolly','airballoon',['earthquake','ironhead','rockslide','swordsdance']],
    ['Weavile',215,60,'Pressure','Jolly','focussash',['icepunch','nightslash','iceshard','lowkick']],
    ['Gliscor',207,60,'Poison Heal','Impish','toxicorb',['earthquake','toxic','protect','substitute']]
  ];
  const rarity=members.map(m=>m[2]<=45?'rare':'uncommon');
  if(rarity.filter(r=>r==='rare').length!==2 || rarity.filter(r=>r==='uncommon').length!==4)throw Error('Invalid rarity budget');
  return members.map(([name,baseID,captureRate,ability,nature,item,moves],index)=>{
    const species=dex.species.get(name),iv=31,level=process.argv.includes('--level-100')?100:50,n=dex.natures.get(nature);
    const ivs=Object.fromEntries(Object.keys(species.baseStats).map(k=>[k,iv]));
    const stats=Object.fromEntries(Object.entries(species.baseStats).map(([k,base])=>{
      const raw=Math.floor((2*base+iv)*level/100)+(k==='hp'?level+10:5);
      return [k,k==='hp'?raw:Math.floor(raw*(n.plus===k?1.1:n.minus===k?.9:1))];
    }));
    for(const move of moves){
      const sources=dex.species.getLearnsetData(species.id).learnset?.[move]||[];
      if(!sources.some(s=>Number(s[0])<=5))throw Error(name+': no BW2 learning route for '+move);
    }
    return {id:'b'+index,speciesID:species.num,species:species.name,displayName:species.name,level,ability,nature,gender:'M',shiny:false,ivs,stats,moves,item};
  });
}
const teams = competitive ? {a:megaTestTeam('a'),b:competitiveTeam()} : megaTest ? {a:megaTestTeam('a'),b:megaTestTeam('b')} : {a:team('a'), b:team('b')};
if(process.argv.includes('--no-items'))for(const team of Object.values(teams))for(const pokemon of team)delete pokemon.item;
validateTeam(teams.a,6);validateTeam(teams.b,6);
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
for (const name of ['command.json','state.json','lineup.json']) { try { fs.unlinkSync(dir+'/'+name); } catch (e) { if (e.code !== 'ENOENT') throw e; } }
if(competitive)console.log('Competitive roster validated: 2 rare + 4 uncommon, legal BW2 move routes, unique held items, level '+teams.b[0].level+', no EVs.');
else console.log(megaTest ? 'Mega/item singles teams validated: unique held items, level 50, owned stats preserved.' : 'Random bring-six/pick-three singles teams validated: final species, no duplicates/items, level 50, owned stats preserved.');
