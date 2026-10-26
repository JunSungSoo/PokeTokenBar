# Held items and the BW2 Mega extension

The default battle rules remain BW2. The explicitly requested Mega extension adds
only the Mega forms reached by the 64 Champions-listed Mega Stones whose base
Pokédex number is 1–649. It does not upgrade the normal species, move pool or
normal ability selection to a later generation. Fairy Feather stays excluded.
No itemless Mega evolution (Rayquaza) or Mega Stones absent from the reviewed
Champions list are added. This is an app-specific mixed ruleset, not official BW2
or an exact implementation of Champions rules.

## Selection and storage

- The whitelist has 36 normal items: 17 type boosters, 6 offensive boosters,
  3 recovery items, 5 survival/contact/status items, 3 order/speed items, Sitrus and Lum.
- Items are configured per Pokémon while drafting the six-member registration team.
  Clicking an item previews its localized description on the right; only Apply
  assigns it. Tabs filter All, Mega Stones, Recovery, Attack boosts, Type boosts,
  Survival, Turn order and Berries. Every tab retains recency/name ordering and
  includes None to remove an item. Toxic Orb is in Survival and applies toxic
  at turn end using BW2 immunity, Poison Heal and Guts rules. Switching tabs does not apply a preview.
  Cancel leaves both the assignment and usage history unchanged.
  Mega Stones are offered only for the matching species/default form. There is
  no purchase or inventory economy.
- Assignments are match-local and become immutable at six-member registration.
  They do not modify collection profiles. Removing a member frees its item;
  a new match starts with no assigned items. Consumed items only change the simulation.
- Applied choices record a local count and recency in one UserDefaults record.
  Recently applied items appear first; unused items follow localized name order.
  Previewing an item does not change ordering. No item is not a usage record.
- The same item cannot be assigned twice among all six members, including reserves.
  None can repeat; opponents can use the same item. The draft, team builder,
  registration/ready coordinator and authoritative engine enforce this clause.
  Engine validation occurs before the six are sliced to the selected three/four.
- The item whitelist and names are shared between the native app and helper via
  generated identical `held-items.json` files. Unknown items, mismatched stones,
  future normal species/abilities/moves and pre-transformed Mega registration are
  rejected. Items are not disclosed by the public six-member roster or hidden
  opponent battle-state fields. Public item/consumption logs remain public.

## Simulation

- A separate `ptbmegabw2` dex copies BW2 data and imports only reviewed Mega forms,
  stones and their additional abilities. Classic Mega forms/abilities use Gen VI
  definitions; newer Mega forms use the pinned simulator's Gen IX definitions.
  Existing Gen V abilities keep their Gen V behavior.
- Base owned stats remain exact. A Mega non-HP stat is the imported owned value
  plus the difference between the Mega and base stat calculated with the same
  level, IVs, zero EVs and nature. The Pokémon's current HP, maximum HP, damage and
  boosts are preserved. Mega multipliers such as Huge Power remain engine events.
- The upstream action queue handles Mega evolution, move priority, Speed,
  Trick Room, switching, ability triggers and one Mega evolution per trainer.
  Turn order uses the pre-Mega Speed when chosen, as in the legacy Mega rules;
  the new Speed applies to later decisions. The checkbox selects at most one slot
  in doubles and the engine also rejects a second evolution.
- Gen V item effects stay Gen V: Normal Gem is 1.5×, not modern 1.3×. PokéRogue
  move effects are still chosen by move. Item changes and consumption are localized
  temporary notices. Existing smooth HP presentation remains awaited.
- Mega-only added abilities are localized separately. Their added Electric Terrain
  is included in the field panel with actual timing and original PokéRogue field
  animation. Fairy typing on the relevant Mega forms is supported without adding
  Fairy Feather or future normal moves/species.

## Appearance and sources

Original non-Mega GIFs remain unchanged. All 64 Mega forms use pinned PokéRogue
artwork, including original rear and standard shiny atlas pairs: 256 variants,
8 animated and 248 single-frame originals. Multi-frame sources run at the original
10 FPS; single-frame sources stay static. Frames are reconstructed on the original
transparent canvas using each variant's own TexturePacker/Aseprite JSON. Normal
and shiny sheets must never share metadata: their frame counts and layouts differ.
There are no base-form, front-for-rear, color or external-provider substitutions.
Original PNG/JSON bytes and hashes are retained in `mega-sprites/source/`.

Mega cache keys include the exported content hash. Older Showdown/PokéAPI GIFs,
disk images and decoded frame caches cannot override the new original artwork.
Normal species cache keys and GIFs remain unchanged. Existing PokéRogue visible
bounds and camera fitting apply to Mega forms. Collection form catalogs are unchanged.

- Champions whitelist source: https://www.serebii.net/pokemonchampions/items.shtml
  (reviewed 2026-10-26; the source list is checked in as 81 stone names before
  filtering by base species).
- Rules: pinned `pokemon-showdown` 0.11.11.
- Item names: PokeAPI CSV, with explicitly authored Portuguese/Russian names.
  Item descriptions and extra Mega ability text are authored translations of the
  selected rules, not claims of official translations. New abilities without an
  established local name use descriptive localized labels.
- Original Electric Terrain animation and dependencies use the existing pinned
  PokéRogue asset revision and manifest hashes.

Regenerate rules/translations with `scripts/export-held-items.cjs`,
`scripts/prepare-held-items.py`, and `scripts/prepare-mega-text.py`; regenerate
Mega-only art with `scripts/prepare-mega-sprites.py`. Input CSV hashes and artwork
URLs/hashes are recorded with the checked-in generated resources.

## Validation

Real simulator tests exercise all 36 normal items, all 64 Mega Stones in singles
and doubles, preserved nonstandard owned HP/stats, one evolution, public privacy,
rejected inputs, added abilities and Electric Terrain. Native tests verify draft assignment, explicit application, recency persistence,
localized sorting and native row previews, six-member item uniqueness, team registration and
Mega requests through the process bridge, legacy-provider cache rejection, original move rendering with a Mega GIF
and a static-only form, and every bundled image. A mutation that restores upstream
max-HP recalculation must fail the Mega HP-preservation sweep.
