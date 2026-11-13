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

## Detail loading performance

The type-aware title/tooltip helpers originally resolved the selected form for
every move in every menu. That recomputed all collected forms and sorted them on
the main actor. The view now captures one `PokemonDetailPresentation`, shares a
single move-text table, and aggregates only the requested species before sorting.
Arceus form labels use the bundled type translations without API requests.

Headless, coverage-instrumented debug measurements on 2026-11-13 used the same copied
save (173 entries), cached metadata and 108 choices in four move menus:

| Measurement | Seconds |
| --- | ---: |
| Prior title/tooltip generation, including repeated collection aggregation | 7.3617 |
| New snapshot and four menu-choice lists, median of five runs | 0.0160 |
| New snapshot and menus with 1,000 synthetic entries | 0.0177 |

These measure presentation-data construction, not full app navigation, networking,
image decoding or native menu layout. The new measurement also includes context
creation and localized option sorting. Automated correctness tests have no timing
threshold; shared-machine load must not make them flaky. The real save is unchanged.

To repeat the copied-save benchmark, supply `PTB_DETAIL_BENCHMARK_STATE` and
`PTB_DETAIL_BENCHMARK_DETAILS` (a cached `{"details": ...}` snapshot) and run
`swift test --enable-code-coverage --filter PokemonDetailPerformanceTests`.
The test imports the copy into a separate temporary store.
