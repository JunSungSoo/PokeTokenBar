# Move effect integration review

Production update (2026-10-21): all real battles now use the complete original PokéRogue
player, timelines and arena at the original 1× rate. The effect-only/native/Showmotion approaches
described below are historical comparisons. See [current playback](local-battles.md#production-pokérogue-provider-2026-10-20)
and `PokeRogueOriginalPlayerTests` for implementation and validation.

Implementation update: the subsequent all-move request is implemented in `BattleEffectCatalog`,
`BattleRecipeCanvas` and the bundled `Resources/BattleEffects` catalog. It resolves all 559 current
canonical moves, retains 906 recipes including later-generation moves, and checks tagged variants
in 5/9/8/7/6/4/3/2/1 order before shared effects. Imported sources have no generation tags;
they are not represented as original generation-V/IX game animations. The following is the
original feasibility review; current behavior and validation are documented in `local-battles.md`.

Original Showmotion playback is now integrated separately through `ShowmotionPlayer` and
`Resources/Showmotion`, retaining the pinned Effekseer assets, runtime and renderer. Its nine
move handlers include six moves legal in the current generation-V battles. Other moves keep
the native catalog above. The on-screen Showmotion badge requires actual particle draw output;
loading or unavailable GPU playback alone does not count as an applied original effect.

Reviewed 2026-10-20. This is a feasibility review; application code and Pokémon sprite playback
are unchanged. Scope: move effects only, with existing front/back GIFs, idle motion, stance
alignment and battle controls retained.

## Sources and reproducible scope

- [Showmotion](https://github.com/shogun-drei/Showmotion/tree/76aaa0b2ae4f3fbe49a4024ae2b6521038cf6d50),
  commit `76aaa0b2ae4f3fbe49a4024ae2b6521038cf6d50`.
- [Showdown move animations](https://github.com/smogon/pokemon-showdown-client/blob/ab4b77b8f3a5712e8fbe03ce106ef2b70a874fdb/play.pokemonshowdown.com/src/battle-animations-moves.ts),
  commit `ab4b77b8f3a5712e8fbe03ce106ef2b70a874fdb`.
- [Showdown shared animation helpers and effect asset notices](https://github.com/smogon/pokemon-showdown-client/blob/ab4b77b8f3a5712e8fbe03ce106ef2b70a874fdb/play.pokemonshowdown.com/src/battle-animations.ts).

Compared actual table keys, including subsequent `BattleMoveAnims[...]` assignments, against
`Resources/BattleText/catalog.json` using the bundled Showdown dex's generation-V canonical IDs.
The current catalog has **560 entries, representing 559 canonical move IDs; all have a matching
Showdown animation table entry**. This establishes identifier coverage, not 559 distinct effects
or native rendering compatibility. Many entries share another move's or a common helper's animation.

Naively deleting punctuation matches only 559/560 catalog entries: `vicegrip` needs the dex alias
resolution to `visegrip`. Emit `move.id` from the authoritative engine rather than matching
localized display names. `quick-attack`, `volt-switch` and `will-o-wisp` then resolve to
`quickattack`, `voltswitch` and `willowisp` in every selected UI language.

## Repository comparison

| Source | Relevant coverage | Integration constraints | Recommended role |
| --- | --- | --- | --- |
| Showdown | Every current canonical move ID has a table entry | TypeScript functions depend on scene helpers, effect images, timing, positions and sprite methods; the file is not a collection of finished GIF/video clips | Primary reference for move-specific sequencing; adapt effect operations into the native renderer |
| Showmotion | Nine custom move handlers; six are generation V or earlier | Browser extension using Three.js WebGPU, WASM runtime and `.efkwgd` effect assets; explicitly falls back to original Showdown animations for doubles | Secondary visual reference for six enhanced profiles; investigate direct asset/runtime reuse separately |

The six eligible Showmotion moves are **Swords Dance, Shadow Ball, Will-O-Wisp, Psychic,
Hydro Pump and Gunk Shot**. Moonblast and Mystical Fire debuted in generation VI; Flower Trick
in generation IX. They are outside this app's BW2 move rules. The additional `land` effect is
a summon effect and is outside this move-only review. Showmotion supplies no custom handler for
the four current preview moves.

Neither source can be dropped directly into SwiftUI `Canvas`. Showmotion's effect package
requires its GPU/runtime machinery, and its hard-coded attack orientation/camera arrangement
would require a separate coordinate adapter for this app's sprite anchors and doubles slots.
Its complete effect directory is approximately 13.2 MB before the runtime and Three.js libraries;
that is repository file size, not an estimate of final compressed app growth. A transparent web
overlay would also need a verified rendering backend on the app's supported macOS versions.
It is not the recommended first integration.

## Current preview moves

| Display name (Korean) | Canonical ID | Upstream reference | Proposed native effect |
| --- | --- | --- | --- |
| 10만볼트 | `thunderbolt` | Repeated lightning strikes around the defender | Layered descending bolts with brief target sparks; use the existing native bolt drawing or a separately verified asset |
| 방어 | `protect` | Shared `selfstatus` wisps | Retain the existing shield and improve its ring/glow sequence; upstream does not provide a more elaborate dedicated barrier |
| 전광석화 | `quickattack` | Shared `fastattack`: wisps, attacker sprite afterimages and movement | Port the wind/impact timing; use an effect trail instead of replacing or moving the Pokémon GIF |
| 볼트체인지 | `voltswitch` | Traveling electric orb and expanding target bursts, plus sprite movement | Electric orb, trailing sparks and impact rings; retain engine-driven switching and coordinate the effect with the outgoing participant |

Showdown also changes attacker/defender position, opacity, scale and afterimages. Those operations
must be filtered out under the requested priority. Keep the current Pokémon animations; port
effect images/particles, their paths, timing and optional backdrop tint only. These will be
adaptations rather than pixel-identical reproductions of the original complete animation.

## Proposed implementation boundary

1. Extend `BattleVisualEvent` with a canonical `moveID`, preserving its public display name,
   ordered event ID, source slot, target slots and hit flags. Update the protocol revision if
   this field becomes required. Do not derive the key from translated UI text.
2. Resolve `moveID -> effect profile -> timed effect operations`. Each profile defines duration,
   source/target/field scope, particle or texture references, path, easing and impact time.
   Existing type/category rendering remains the fallback for profiles not yet ported.
3. Start with the four preview moves, then the six eligible Showmotion-inspired profiles, then
   shared families such as beams, punches, slashes, recovery, shields and stat changes. Broader
   identifier coverage is already established; visual profile coverage needs its own audit.
4. Use actual battlefield anchors and normalized vectors instead of browser-specific `x/y/z`
   positions. Spread moves such as Surf need all affected slots, including an ally when applicable.
   Field and self-target moves need explicit scopes rather than duplicating a target effect.
5. Replace the universal 0.85-second wait with each profile's timeline. Preserve ordered playback,
   cancellation on close, no replay on reconnect, bounded particles, input gating and Reduced Motion.
   Missed/immune/protected targets must suppress impact while allowing appropriate launch effects.
6. Capture participant identity/anchors at the relevant action boundary. The current engine sends
   a resolved frame with log events; for Volt Switch, fainting and replacement, merely attaching
   a delayed effect to the final slot can associate it with a different Pokémon. Detailed multi-hit,
   charge-turn and failure sequences also require more event information than a move name alone.

Acceptance checks for implementation: all catalog aliases map to canonical IDs; UI language
does not alter selection; the four preview moves visibly differ; both facings and all doubles
target slots align; no impact on misses/immunities/Protect; switching targets the correct identity;
profile duration controls input gating; Pokémon GIF frames and idle motion continue unchanged.

## Reuse conditions to resolve before copying assets

The move file declares CC0; the shared battle animation engine declares MIT, with additional
file-level notices. The client repository as a whole has different licensing. The shared source
explicitly lists exceptions for assets including `lightning.png`, `icicle.png`, `bone.png`,
`rocks.png`, `rock1.png` and `rock2.png`; do not label the complete asset directory CC0 or copy it
wholesale. A native reference implementation using the existing procedural bolts avoids making
those exception assets a dependency for the first preview moves.

No top-level reuse license was found in Showmotion's reviewed repository tree or README.
Its statement that the extension is free does not establish asset redistribution terms.
Directly bundling its effect files should wait until those terms are established; this does not
prevent reviewing its structure and developing independently implemented native effects now.

## Recommendation

Use Showdown's canonical-ID table and effect sequencing as the main reference, then adapt
Showmotion's six eligible visual concepts into selected enhanced native profiles. Keep the
current Pokémon sprites and their animation pipeline. Ship verified native profiles incrementally,
with the existing effects as fallback, rather than replacing the whole battle display or claiming
all matched table entries are already implemented.
