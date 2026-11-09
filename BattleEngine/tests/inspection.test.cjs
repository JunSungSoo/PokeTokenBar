'use strict';
const {test} = require('node:test');
const assert = require('node:assert/strict');
const {OwnedBattle} = require('../engine.cjs');

function team(prefix, species = 'Smeargle', ability = 'Own Tempo', moves = ['tackle', 'recover', 'curse', 'weatherball']) {
  return [species, 'Blissey', 'Raichu', 'Vaporeon', 'Slowbro', 'Scizor'].map((name, index) => ({
    id: prefix + index, species: name, ability: index === 0 ? ability : {
      Blissey:'Natural Cure', Raichu:'Static', Vaporeon:'Water Absorb', Slowbro:'Own Tempo', Scizor:'Technician'
    }[name],
    level:100, nature:'Hardy', moves:index === 0 ? moves : ['splash'],
    ivs:{hp:31, atk:31, def:31, spa:31, spd:31, spe:31},
    stats:{hp:500, atk:100, def:200, spa:100, spd:200, spe:100}
  }));
}
function engine(own = team('a'), foe = team('b', 'Snorlax', 'Immunity')) {
  return new OwnedBattle('singles', [own, foe], [1, 2, 3, 4], {profile:'challenge'});
}
test('Weather Ball inspection follows effective weather without changing battle state or RNG', () => {
  for (const [weather, type] of [['sunnyday','Fire'], ['raindance','Water'], ['sandstorm','Rock'], ['hail','Ice']]) {
    const battle = engine();
    battle.battle.field.setWeather(weather, battle.battle.sides[0].active[0]);
    const log = [...battle.battle.log], seed = battle.battle.prng.getSeed();
    const move = battle.frame(0).slots[0].moves.find(move => move.apiName === 'weatherball');
    assert.equal(move.type, type);
    assert.equal(move.power, 100);
    battle.frame(0); battle.frame(1);
    assert.deepEqual(battle.battle.log, log);
    assert.deepEqual(battle.battle.prng.getSeed(), seed);
  }
  const battle = engine(team('a'), team('b', 'Golduck', 'Cloud Nine'));
  battle.battle.field.setWeather('sunnyday', battle.battle.sides[0].active[0]);
  assert.equal(battle.frame(0).slots[0].moves[3].type, 'Normal');
  assert.equal(battle.frame(0).slots[0].moves[3].power, 50);
});
test('Struggle never displays type resistance or Ghost immunity', () => {
  const battle = engine(team('a'), team('b', 'Gengar', 'Levitate'));
  for (const slot of battle.battle.sides[0].pokemon[0].moveSlots) slot.pp = 0;
  battle.battle.makeRequest('move');
  const move = battle.frame(0).slots[0].moves[0];
  assert.equal(move.name, 'Struggle');
  assert.equal(move.ignoresTypeMatchup, true);
  assert.equal(move.matchups[0].multiplier, 1);
});
test('Curse inspection uses the current user type for its target', () => {
  for (const [species, ability, target] of [['Smeargle','Own Tempo','self'], ['Gengar','Levitate','normal']]) {
    const battle = engine(team('a', species, ability));
    assert.equal(battle.frame(0).slots[0].moves[2].targetScope, target);
  }
});
test('Normalize uses the BW rule after move type resolution', () => {
  const battle = engine(team('a', 'Delcatty', 'Normalize', ['thunderbolt', 'tackle']));
  const moves = battle.frame(0).slots[0].moves;
  assert.equal(moves[0].type, 'Normal');
});
test('disabled move reasons and ongoing effects use own authoritative state only', () => {
  const battle = engine();
  const pokemon = battle.battle.sides[0].active[0];
  pokemon.addVolatile('taunt', battle.battle.sides[1].active[0]);
  pokemon.addVolatile('substitute');
  pokemon.moveSlots[0].pp = 0;
  battle.battle.runEvent('DisableMove', pokemon);
  battle.battle.makeRequest('move');
  const frame = battle.frame(0);
  assert.equal(frame.slots[0].moves[0].disableReason, 'pp');
  assert.equal(frame.slots[0].moves[1].disableReason, 'taunt');
  assert.ok(frame.own[0].effects.includes('taunt'));
  assert.ok(frame.own[0].effects.includes('substitute'));
  assert.equal(battle.frame(1).foe[0].effects, undefined);
  pokemon.removeVolatile('taunt');
  for (const slot of pokemon.moveSlots) { slot.disabled = false; slot.disabledSource = ''; }
  battle.battle.makeRequest('move');
  assert.ok(!battle.frame(0).own[0].effects.includes('taunt'));
  assert.equal(battle.frame(0).slots[0].moves[1].disableReason, undefined);
});
