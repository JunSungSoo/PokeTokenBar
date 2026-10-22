# PokéRogue original-player comparison prototype

Unmodified source timelines/assets: pagefaultgames/pokerogue-assets at 009cac30c39d3615c7b2c320c3984af368871031.
Unmodified runtime source: pagefaultgames/pokerogue at 13f1139f0aef39fa75b8b57268832d6c1d9aa742.
`adapter.ts` extracts AnimConfig/timed events and BattleAnim verbatim, adding dependency shims.
`original-player.js` is its mechanically transpiled ES module. The host supplies Pokémon GIF
frames exported by the existing native SpriteLoader, scene anchors, a deterministic clock,
minimal tone shader and Phaser 3.90.0. Both comparison panels execute this same original player;
they are not independent implementations, and this is not a full running PokéRogue game.
Original code/derived adapter: AGPL-3.0-only. Phaser: MIT. Mixed asset licenses and credits:
retain REUSE metadata, README, LICENSES and this manifest on redistribution.
No animation commands, invalid frames or sound events are filtered from the four timelines.
