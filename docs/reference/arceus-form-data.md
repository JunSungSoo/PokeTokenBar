# Arceus form presentation

Verified on 2026-11-13 using PokéAPI and the project's pinned Pokémon Showdown Gen V dex.

- PokéAPI's [Arceus Fire form](https://pokeapi.co/api/v2/pokemon-form/10046/)
  identifies the Fire type but points back to the shared Pokémon resource, #493.
- The [Showdown species data](https://github.com/smogon/pokemon-showdown/blob/master/data/pokedex.ts)
  gives every Arceus form six base stats of 120 (720 total), Multitype, a height of
  3.2 m and a weight of 320 kg. The BW2 learnset is shared across types.
- [Judgment's implementation](https://github.com/smogon/pokemon-showdown/blob/master/data/moves.ts)
  uses the held Plate's type. The pinned Gen V engine reports power 100, accuracy
  100, 10 base PP and the Special category. In the collection's fixed type forms,
  its displayed type follows that form. Other moves retain their own types.
- Fairy Arceus is already a collectible form in this app. Its display uses the
  same shared stats and learnset, even though Fairy is absent from the BW2 type table.

Presentation projects shared metadata onto the selected form. It does not rewrite
the cached Pokémon resource, individual IVs, moves, abilities or battle eligibility.
The existing ownership restriction on the form picker remains in place.
