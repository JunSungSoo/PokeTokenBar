# PokéRogue move-effect feasibility review

Production update (2026-10-27): battle sprite extent now uses the collection's
PokéAPI height source: `90 * metres^0.3` before the shared roster/form camera.
Original atlas bounds retain proportions and front/back differences, rather than
using metres as the vertical pixel height of long or horizontal Pokémon. The
height importer covers all 649 species and all 64 permitted Mega forms, storing
CSV hashes and PokéAPI IDs independently from the original atlas metadata.

Mega presentation adapts pinned FormChangePhase and Animation spiral/arc/circle/
spray equations into battle coordinates. It uses original evo_sparkle pixels and
charge/beam/sparkle/shine audio, charge/cycle/reveal phases at 2× speed, then the form cry at its original pitch.
The queue waits for original-pitch sound tails as well as the visual completion. The modal evolution video, fanfare/BGM replacement and
out-of-battle confirmation UI are intentionally excluded from this battle adapter.
Native GIFs keep advancing; effects volume/live mute and the existing arena/notice
layers remain in force. The queue defers Showdown's preceding detailschange,
commits the new form at completed reveal, and waits before the next action.

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


## Original status activation playback (2026-10-23)

- Import eight unmodified common timelines (sleep, poison, toxic, paralysis, confusion,
  burn, frozen, attract), graphics and authored sounds into `statusEntries`. The regular
  player preparation script regenerates them alongside moves/weather/entry resources.
  Pinned assets remain `009cac30c39d3615c7b2c320c3984af368871031`; original paths and
  SHA-256 records are retained in the production manifest.
- Runtime reference: PokéRogue `13f1139f0aef39fa75b8b57268832d6c1d9aa742`,
  [MovePhase triggerStatus](https://github.com/pagefaultgames/pokerogue/blob/13f1139f0aef39fa75b8b57268832d6c1d9aa742/src/phases/move-phase.ts),
  [PostTurnStatusEffectPhase](https://github.com/pagefaultgames/pokerogue/blob/13f1139f0aef39fa75b8b57268832d6c1d9aa742/src/phases/post-turn-status-effect-phase.ts),
  and [ConfusedTag/InfatuatedTag](https://github.com/pagefaultgames/pokerogue/blob/13f1139f0aef39fa75b8b57268832d6c1d9aa742/src/data/battler-tags.ts).
  Each common animation uses the affected Pokémon as both user and target.
- BW2 remains authoritative: do not copy PokéRogue's paralysis probability, confusion
  probability or burn damage formula. Render actual Showdown status application, blocked
  action, confusion/attract activation and poison/burn residual events. Toxic residual
  logs use `[from] psn`; distinguish toxic using the captured battler condition.
- Keep each original effect/sound at its authored tempo, original GIF cadence, existing
  idle floating, localized notices and effect volume. Residual HP commits only after
  playback completes. Cure, flinch, successful paralyzed actions and confusion self-damage
  do not duplicate common animations. Existing flinch/cure notifications remain visible.


## Original entry cries (2026-10-23)

Bundle all 649 BW2 species cries plus six distinct form cries from the existing
pinned PokéRogue asset revision. `prepare-pokerogue-cries.py` regenerates their
manifest paths and hashes. The mapping follows pinned
[PokemonSpecies.getCryKey](https://github.com/pagefaultgames/pokerogue/blob/13f1139f0aef39fa75b8b57268832d6c1d9aa742/src/data/pokemon-species.ts#L545);
all other supported forms share the base-species cry. Both teams use SummonPhase's
post-growth timing and 0.85x playback at HP <=25%. Keep the prior 1.25x ball motion,
original GIF/floating and shiny sequence. Decode entry-source cries only, cache
with the existing bounded audio cache, and play them once on the foreground audio
owner using the effects volume. Include decoded cry length in entry completion
and reduced-motion audio waits. No BGM setting or simulator mechanics change.

### Weather damage feedback

Actual BW2 Sandstorm/Hail damage scenes now use a dedicated awaited weather-hit
phase: original `se/hit.wav` and six visibility states at 100ms intervals, followed
by the shared smooth HP drain. No transient weather-damage text is displayed.
This intentionally enables normal-hit feedback for weather damage: pinned
PokéRogue's `WeatherEffectPhase` uses INDIRECT and its `DamageAnimPhase` skips
blink/audio for that result. Both reference sources and the untouched sound are
bundled with hashes/provenance. Immunity and Cloud Nine remain engine-controlled;
only an actual damage log can start the feedback. Effects volume/live mute apply,
and the background WebKit surface stays silent.

## Random battle arenas

`BattleArena` selects one of 15 original PokéRogue backgrounds per match: plains,
forest, snowy forest; sea, beach, lake; mountain, desert, volcano; cave, ice cave,
fairy cave; town, metropolis, dojo. Ruins and special locations are excluded.
The SHA-256 digest of the shared random handshake match ID chooses a stable arena
on both peers, independently of engine RNG. Reconnection, turns and switching
preserve it. The next match's fresh nonces choose again; repeats are allowed.
This is cosmetic and does not imply weather, terrain or stat changes.

Regenerate the unmodified 320×180 backgrounds with
`python3 scripts/prepare-pokerogue-arenas.py` after preparing the base player.
The importer uses `manifest.json`'s pinned asset revision and records every
source path and SHA-256 in that manifest, along with the five curated groups.
`BattleArenaTests` verifies all 15 resources and their viewport coverage at both
production sizes; `BattleTests` verifies the real handshake and engine lifecycle
on both peers in singles and doubles. Native GIFs, floating and effect layers
retain their existing behavior.

Arena matrix QA: `BattleArenaVisualTests` mounts the production layer modifier
outside every monitor and checks all 15 arenas × two formats × four representative
moves (Close Combat, Thunder, Quick Attack, Surf) × both attacker perspectives
(240 combinations). It checks native HUD/background/foreground/notice sibling
order, original actor/particle depth, finite geometry, visible effects, completion
and transparent cleanup. `PTB_ARENA_CAPTURE_DIR=/tmp/ptb-arena-audit` saves the
machine-readable matrix and diagnostic composites. Those composites combine
actual original WebGL surfaces at the same 750 ms timestamp, production arena and
notice views, and explicitly labeled HUD probes; they are not full BattleView
screenshots. Full production singles/doubles geometry, native front/back GIF
cadence and bounded localized notice stacks retain their separate native tests.
