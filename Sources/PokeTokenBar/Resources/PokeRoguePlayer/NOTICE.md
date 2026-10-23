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
PokéAPI GIF artwork/cadence remains in use, fitted without distortion to those bounds.
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
