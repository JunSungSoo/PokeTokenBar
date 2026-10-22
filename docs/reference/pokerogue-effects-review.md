# PokéRogue move-effect feasibility review

Production update (2026-10-21): all real battles now use the complete original PokéRogue
player, timelines and arena at the original 1× rate. The effect-only/native/Showmotion approaches
described below are historical comparisons. See [current playback](local-battles.md#production-pokérogue-provider-2026-10-20)
and `PokeRogueOriginalPlayerTests` for implementation and validation.

Reviewed 2026-10-20 against this project's 559 canonical move IDs. This is a data/source
review, not an import or successful live rendering claim. Application effects and Pokémon
animation code are unchanged by this review.

## Result

PokéRogue is a strong candidate for a broad **2D sprite-sheet effect layer**. All 559 current
move IDs have a corresponding JSON file, and every named main graphic, timed background and
sound dependency exists in the pinned asset tree. This does **not** establish 559 complete,
unique, visually acceptable effects with Pokémon motion removed, nor Showmotion-style 3D quality.

Asset repository: https://github.com/pagefaultgames/pokerogue-assets

Audited revision: `009cac30c39d3615c7b2c320c3984af368871031` (`beta`).

The runtime reviewed is `pagefaultgames/pokerogue`'s `beta` branch on the review date:

- [Player and data schema](https://github.com/pagefaultgames/pokerogue/blob/beta/src/data/battle-anims.ts)
- [Frame targets/focus/blending enums](https://github.com/pagefaultgames/pokerogue/blob/beta/src/enums/move-anims-common.ts)
- [Asset loader](https://github.com/pagefaultgames/pokerogue/blob/beta/src/scene-base.ts)

Runtime references above are moving links; an implementation must pin its own reviewed source
revision. The numerical audit below is pinned to the asset revision above.

## Reproducible coverage

`BattleEffects/catalog.json` aliases are canonicalized before matching hyphenated JSON filenames.
This also handles the existing Vice Grip/Vise Grip alias. The audit parses actual JSON frames,
not just filenames, and checks dependencies against the complete Git tree.

| Classification | Moves | Meaning for an effect-only integration |
| --- | ---: | --- |
| Visible GRAPHIC frame entries | 511 | Particle/sprite assets can be ported; still requires runtime and visual validation |
| Background but no visible GRAPHIC entry | 15 | Retain timed backgrounds; removing Pokémon motion loses part of the original composition |
| Motion without separate GRAPHIC/background | 30 | Keeping our Pokémon animations needs existing fallback or new effect-only staging |
| No frames | 3 | Nature Power, Rest, Secret Power need fallback, called-move or status/healing event handling |
| Missing definition | 0 | Filename coverage is complete |

There are 774 direction/configuration definitions across the 559 files; two definitions in a
file are not two game generations. Dependencies include 256 main sheet names and 82 background
names (336 unique PNG files in their union), plus 787 referenced sound names. No referenced
resource was missing from the tree. The 559 original JSON files total 29,951,003 bytes and the
336 required PNGs total 1,125,143 bytes, before any conversion/compression. Audio sizes and final
application growth have not been measured.

See [per-move audit](pokerogue-effect-coverage.csv), including the exception lists.

Reproduce without importing assets into the application:

```sh
git clone --depth 1 --filter=blob:none --no-checkout --branch beta \
  https://github.com/pagefaultgames/pokerogue-assets.git /tmp/pokerogue-assets-review
git -C /tmp/pokerogue-assets-review sparse-checkout set battle-anims images/battle_anims LICENSES
git -C /tmp/pokerogue-assets-review checkout 009cac30c39d3615c7b2c320c3984af368871031
python3 scripts/audit-pokerogue-effects.py /tmp/pokerogue-assets-review --output /tmp/pokerogue-audit.json
```

If the remote branch has moved beyond this commit, explicitly fetch the recorded commit first.

## Pikachu's four sample moves

All four JSONs and their PNG/background/audio dependencies exist. No static graphic-frame
index warning was found in these four samples.

| Canonical move | JSON timeline frames | Direction/configuration definitions | Main sheet | Notes |
| --- | ---: | ---: | --- | --- |
| `thunderbolt` | 26 | 1 | `PRAS- Electric` | Electrical frames, timed black background, two timed sounds |
| `protect` | 20 per definition | 2 | `PRAS- Protect` | Five-frame hexagonal shield sheet; timed sound events |
| `quickattack` | 13 per definition | 2 | `PRAS- Strike` | Impact sheet; a substantial part of the original uses Pokémon movement |
| `voltswitch` | 25 per definition | 2 | `PRAS- Electric` | Electrical frame sequence and two timed sounds |

The main sheet sizes are Electric 480×1248, Protect 480×96, Strike 480×576. The upstream loader
slices them into 96×96 cells. They are low-resolution 2D effects. Viewing the actual Electric
and Protect sheets confirms pixel artwork rather than 3D particles; playing them in a GPU
renderer would not change their authored style into Showmotion's effect style.

## Integration design

Keep Showdown as the authoritative BW2 rules engine and preserve the current stats, move IDs,
localization, PP, move selection, sprite GIFs and idle animation. Import only presentation data.

1. Convert JSON to a bounded local timeline keyed by canonical move ID. Retain the original
   frame cadence and direction variants; do not copy the whole Phaser game or its global scene.
2. Retain only `AnimFrameTarget.GRAPHIC` operations. The original player hides the real user
   and target and creates animated replacement Pokémon sprites. Running that player unchanged
   would violate our existing-animation requirement. Exclude its USER/TARGET sprite creation,
   transforms, tint and hiding paths.
3. Map TARGET/USER/USER_TARGET/SCREEN focus to actual sprite anchors, including self effects,
   opposing attackers and doubles slots. Preserve mirror, zoom, rotation and opacity semantics.
4. Implement NORMAL/ADD/SUBTRACT blending, timed background creation/updates, and separate
   behind/in-front effect layers. A single foreground Canvas does not reproduce behind-sprite
   effects. Existing native render operations cannot directly decode this different schema.
5. Preserve event ordering, cancellation, bounded timelines, Reduce Motion and no-replay on
   reconnect. Suppress target impact on missed, immune or protected targets. Coordinate
   switching, multi-hit, charge, weather and healing with engine events rather than names alone.
6. Keep existing/original Showmotion profiles as fallback/alternatives for empty, motion-only,
   invalid or visually weak imports. Never label an imported 2D profile as a Showmotion original.
7. Keep assets offline and load/cache only the selected move's sheets, instead of decoding every
   sheet into memory. Sound effects are optional for the first comparison and should not replace
   the existing Gold/Silver BGM or its saved volume.

The data does not establish an original-game generation for each animation. Do not label a
file Gen 5 or Gen 9 using the move's introduction generation or direction variant count. The
existing 5→9→8→7→6→4→3→2→1 preference needs actual provenance tags before it can choose variants.

## Static exceptions requiring validation

With upstream's 96×96 slicing, six moves reference at least one visible frame index outside
their named PNG's cell count: `bravebird`, `energyball`, `hex`, `moonlight`, `torment`, `twister`.
This is a static import warning, not a claim that each whole move is broken in the live game;
Phaser's missing-frame behavior and authored intent need runtime comparison. An importer must
not read outside a sheet or silently claim a faithful effect after discarding such operations.

The 15 background-only cases include Surf, Psychic and Trick Room. The 30 motion-only cases
include Double Team and Tail Whip. These demonstrate why removing Pokémon animation requires
coverage auditing beyond matching all 559 filenames. A future effect-only importer needs
explicit fallback for these 48 cases, not an empty successful match.

## Provenance and reuse

The [asset README](https://github.com/pagefaultgames/pokerogue-assets#license) declares per-file
REUSE metadata and mixed licenses. The root `REUSE.toml` identifies animation JSONs as code
under AGPL-3.0-only; `battle-anims/REUSE.toml` also records Pokémon Reborn and Gen 8 Animation
Project source groups. The bundled `LICENSES/LicenseRef-POKEMON-REBORN.txt` includes a borrowing
statement requiring the relevant credits. Graphics/audio must be checked independently against
their own notices and the README's default terms. Neither an open GitHub repository nor
noncommercial use establishes a blanket CC0/MIT grant for this entire collection. An actual
import should retain a per-file provenance/license manifest and review overlapping metadata.
This review has not copied any of those assets into application resources.

## Recommendation

Proceed with a **four-move PokéRogue comparison prototype** before any 559-move import:
Thunderbolt, Protect, Quick Attack and Volt Switch, using the source PNGs and timing, effect-only
filtering and no sound initially. Compare existing effects, the authored sample and PokéRogue
on the same Pokémon stage. If the pixel-art style is approved, expand the data adapter and
validate the 48 fallback cases and six frame-index warnings. This offers broad reusable 2D
coverage; it is not a shortcut to hundreds of Showmotion-quality 3D effects.
