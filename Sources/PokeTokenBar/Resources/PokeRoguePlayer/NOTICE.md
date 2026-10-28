# PokéRogue original production animation player

Complete source timelines, GRAPHIC/USER/TARGET commands, timed backgrounds and sounds are
bundled without filtering. Pinned assets: pagefaultgames/pokerogue-assets 009cac30c39d3615c7b2c320c3984af368871031.
The verbatim AnimConfig/timed-event and BattleAnim source ranges are transpiled mechanically
from runtime 13f1139f0aef39fa75b8b57268832d6c1d9aa742. Phaser version 3.90.0.
Host adapters supply current native GIF frames, actual battle anchors, guarded lifecycle and
serialized frame stepping. Showdown remains the authoritative BW2 battle rules engine.
Original and derived runtime code: AGPL-3.0-only. Phaser: MIT. Mixed asset licenses/credits:
see root/directory REUSE.toml, README, original/LICENSE and LICENSES. Preserve all notices and
manifest hashes on redistribution. No claim of a blanket MIT or CC0 asset license.

Common Gen V weather timelines are bundled separately from move entries. Field-start presentation reuses the corresponding original move timeline when no dedicated common animation exists. Battle mechanics remain BW2 engine-authoritative.

The native host maps original 320×180 SCREEN-focus graphics to its arena viewport. USER-focused graphics for global field conditions run for every active battler, sharing one original background and audible sound owner; original timelines, actor sprite scale and frame timing remain unchanged.


Entry/recall presentation is adapted in entry-player.js from the pinned runtime's
SummonPhase, SwitchSummonPhase, Animation.doDefaultPbOpenParticles and Poké Ball tint.
Unmodified source references live in original/entry/. Original pb/pb_particles atlases
and se/pb_rel.wav retain their pinned bytes, source paths, hashes and existing upstream
licensing/attribution. The host adapts coordinates to native GIF anchors, preserves
original throw/release easing and staggered radial particles. Appearance and its settle
pause play at 1.25x speed (520ms throw, 200ms growth, 1520ms total); recall retains
its original timing. Adjacent same-side double entries share a clock and sound owner. The collection currently has no captured ball type, so the standard Poké Ball
is used. The existing effects-volume control applies to release/recall audio.

pokemon-sizes.json derives per-species/form/front/back visible animation bounds from
atlas JSON at the pinned asset revision. Each record preserves its source SHA-256;
prepare-pokerogue-sizes.py verifies source Git blob hashes before extraction. Existing
PokéAPI GIF artwork/cadence remains in use; atlas bounds preserve aspect and facing ratios.
All battlers share one camera scale. Native and original-player actors use the same
size/feet anchors; atlas cells retain natural dimensions instead of 64px normalization.

Standard shiny entries append the original shiny atlas (35 frames at 32fps) and
se/sparkle.wav after ball appearance/settle. This preserves the authored animation
through its final frame (1093.75ms), exceeding ShinySparklePhase's 1000ms wait slightly
so the next native action cannot cut the sparkle short. Both assets retain pinned bytes.

The host timed-background adapter maps the original 320x180 arena to the native viewport
with a centred cover transform, independently of Pokémon camera scale, including timed
foreground surfaces. Original timeline bytes, assets, event clocks and layers are unchanged.
It creates same-frame backgrounds before fading them, separates exported scrolling defaults
from independent opacity fades, and retains the final authored fade-out.

Entry cries use original pinned audio/cry/*.m4a for all 649 BW2 species and six
forms with distinct cries (Sky Shaymin, Therian trio, Black/White Kyurem).
PokemonSpecies.getCryKey selects these form suffixes; other supported forms use
the species cry. SummonPhase starts the cry after the 250ms growth animation,
slowing it to 0.85x at HP <=25%. The host's existing 1.25x appearance clock is
preserved; cry audio retains its original rate, subject only to the low-HP rule.
Cries share the user's effects volume, play only on the foreground audio owner,
and extend the serialized entry lifetime if their decoded duration requires it.
All original asset hashes, audio REUSE notices and licenses remain applicable.

Weather damage hit feedback adapts DamageAnimPhase's 100ms sprite blinking and
se/hit.wav. Original weather INDIRECT damage intentionally omits this feedback;
the host explicitly enables normal-hit feedback for actual BW2 sandstorm/hail
damage at the user's request, with no damage numbers/notices. The authored hit
audio is unchanged; the six visibility states end at 500ms before HP interpolation.

Battle arenas use 15 unchanged original images/arenas/*_bg.png assets from the
assetRevision recorded in manifest.json, curated as three arenas per environmental
group (woods, water, highlands, caves, settlements). Both peers derive the same
cosmetic selection from their shared random match nonces using SHA-256; this
does not change battle weather, terrain, statistics or engine RNG. Native Pokémon
GIFs, floating animation and existing sprite stages remain unchanged.

Battle display size now uses original PokéAPI CSV height (decimetres), including
all 649 species and 64 permitted Mega forms: extent = 90 * metres^0.3, normalized
against the largest front/back atlas dimension before the existing shared camera.
Physical length is never forced into vertical image height. Source CSV snapshots
and hashes are preserved in original/physical/ and pokemon-heights.json.

MegaAnimation is a battle-space adaptation of pinned FormChangePhase and Animation
spiral/arc/circle/spray commands, using unchanged evo_sparkle and charge/beam/
sparkle/shine sounds. Source references live in original/mega/. The visual clock runs at 2x (2026-10-27 user setting); GIF cadence, audio pitch,
effects gain and old/new sprite/size identity are preserved. Playback waits for
original-pitch sound/cry tails before advancing.
The battle adapter omits the modal evolution video, BGM/fanfare replacement and
confirmation UI. It holds the preceding detailschange scene until the Mega reveal
finishes; cancellation never commits an old scene.

## Generation-VI Fairy moves

Fourteen Fairy moves plus Geomancy charging are bundled as complete source JSON timelines
from the same pinned asset revision 009cac30c39d3615c7b2c320c3984af368871031. Their original
GRAPHIC/USER/TARGET instructions, timed backgrounds and sound events remain intact.
`manifest.json.fairyMoves` and `BattleText/gen6-fairy-source.json` record the source files
and hashes. The loopback server serves authored M4A sounds as audio/mp4 alongside WAVs;
all sounds follow the existing effects-volume control. Pokémon GIF/floating playback,
original 1× effect timing, HP/notice ordering and foreground/background layers use the
same production player. Misty Terrain and Fairy Lock are global field presentations;
Fairy Lock's emitted `-fieldactivate` log is handled explicitly and is not double-played.
