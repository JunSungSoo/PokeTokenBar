# Challenge implementation — engine and interactive UI

Implemented 2026-10-30. The Battle tab now opens the native challenge window: select six owned graduates and their held items, fight the automatic CPU, claim a reward, save and exit, or continue to the next fixed encounter.

## Implemented

- Explicit `challenge` engine profile: six combatants per side, singles only. Peer singles still selects three and doubles four. A challenge does not create a fake LAN peer or a response deadline.
- Twenty-seven fixed encounters / 24 characters / 162 slots. The reviewed six-species candidates are unchanged. Opponents are level 100, IV 31 except typed Hidden Power, EV 0 and fixed natures/items/abilities/moves. Every set passes the pinned Showdown generation-V `Obtainable` validator. The 16 species with missing/small usage samples have authored legal sets (17 slots); evidence flags distinguish them from reviewed analysis sets. Later encounters select another documented role where available; a single viable ability is not invented for variety.
- NPC items may use generation-V held-item mechanics already implemented by Showdown. This does not expand the player's selectable item catalog. `itemAdapted` marks a standard-set item replaced to satisfy the six-member item clause.
- Actual HP, base move PP, status, sleep origin and held items persist. Sketch replacements update only the run snapshot; checkpoints retain the original starting team so silent replay still reproduces learning the move. Dead leads are skipped, not healed. Battle-only stages/volatiles/weather are recreated per encounter. Base PP slots retain Showdown's shared references so switching and Transform cannot refund spent PP. Recompute Mega eligibility from the carried item, not an earlier registered item.
- Atomic run state, seed and command checkpoint; pending human commands are saved before submission. Reopening a battle silently replays accepted/pending commands with the same catalog/model/engine versions. Save failure does not publish a successful mutation. Corrupt/unsupported saves are preserved.
- One reward per nonfinal victory: floor(maxHP×0.35), at least 1, including revival; +3 PP to exactly one move; or a fresh eligible owned graduate replacing one slot. Replaced individual IDs cannot return. Remaining compatible gear is inherited; selecting a replacement cannot mint its collection-default item. An unavailable reward can be skipped only when HP/PP are full and there is no valid replacement.
- Actual win → reward → next encounter, loss/draw/surrender termination and final-win completion are tested through the real helper process. The collection's original profiles and ordinary peer battle history are not mutated by a run.

## Interactive UI

- The Battle tab exposes a challenge entry beside the existing peer lobby. An open challenge disables peer matching and trade; it does not replace either service with a fake peer.
- Six distinct eligible owned species, selection-order lead and the existing item picker/default precedence/item clause are reused. The Start button stays visible below long collection lists.
- The shared battle view observes a presentation adapter. Original GIFs, floating, move effects, cries, HP interpolation, Mega controls, field/stat panels and volume controls remain in the production rendering path.
- Twenty-four original PokéRogue trainer atlases cover all 27 encounters. Pinned asset/name revisions and SHA-256 hashes live in `Resources/BattleText/ChallengeTrainers/source.json`. Trainer names and UI strings cover all eight settings languages. The trainer stands on the opposing side while the player's entry plays, exits to the right, then releases the opposing entry queue. Opposing sprites and HP panels remain hidden during the introduction. Resume silently restores the current battle without replaying its original entrance.
- Victory waits for the final presentation to finish before displaying the three reward choices. HP healing/revival, one selected PP slot, and a newly built replacement are actionable controls. Reopening an unclaimed reward does not require an in-memory ended battle frame. Replacement validation builds only the new individual; existing run members remain frozen.
- Save-and-exit and Next remain visible and activate after the one reward is atomically saved. Next starts the next encounter with the saved HP/PP/status/items. Defeat or surrender exposes a new challenge from the beginning. Closing a live battle asks Cancel/Surrender; closing the saved intermission stops audio, engine and hidden rendering resources.
- Every encounter currently uses the existing battle BGM and the existing result cues. No gym/Elite Four/Red soundtrack split is enabled yet; encounter phase metadata remains available for that later change.

## Actual machine learning

The shipped JSON is a trained model, not handwritten scoring weights presented as training.

1. Official public Showdown API sample: 198 gen5ou replay files. After team/Illusion/Transform checks, 191 games produce 6,967 action examples.
2. Split by SHA-256 of the whole replay ID: 159 games / 5,829 actions train, 32 games / 1,138 actions evaluate. Both sides and all turns of a game remain in one partition.
3. Conditional softmax action ranking with learned linear weights and L2 regularization (NumPy). Separate learned lead-ranking head: 318 training and 64 evaluation examples. Lead inputs use unordered public species, never the human's lead order, hidden set or current choice.
4. Behavior-cloned model action agreement: 40.95% on held-out replay actions; uniform-choice expectation 16.38%. Lead agreement: 35.94% versus six-way uniform 16.67%. These are reconstruction-limited agreement metrics, not battle win rates.
5. REINFORCE adaptation: 216 local battles using the project's exact engine, with regularization to the cloned prior. Validation chooses the deployed weights; a different matchup pairing and seeds are then held out from model selection.
6. Final held-out synthetic evaluation: 27 wins / 27 losses in 54 battles against a public type-adjusted base-power baseline. No truncated games. This is not human ladder performance or proof of expert play.

At runtime the shared policy ranks only legal available moves/switches. It sees its own available information and public opponent observations, not private opposing bench sets, hidden submitted actions or future observations. Scoring does not consume combat RNG; ties are deterministic. A policy/catalog/engine fingerprint prevents silently replaying a save under changed behavior. No model training, public matchmaking or network inference is performed by the distributed app.

## Limitations

- This is a small linear baseline. Public logs expose rounded HP and incomplete own move candidates; exact IV/EV/item reconstruction is not implemented. Training includes unranked replays. It is not an expert-strength model.
- The synthetic adaptation/evaluation is per battle, not an optimized 27-fight HP/PP campaign policy. User-owned graduation restrictions, arbitrary custom stats and the app's extra Mega/Fairy rules are not fully represented by the small evaluation set.
- All 27 opponent sets are engine-validated and every trainer atlas/name resolves. The interactive regression uses a two-encounter fixture through the real engine and production window; a complete human-played 27-fight campaign has not been performed. Test windows were rendered offscreen; no interactive window was opened on the monitor.
- Challenge run state is preserved; a separate lifetime challenge-result archive is not yet implemented.
- No ZIP, release note entry, commit or push was requested/performed for this stage.

## Reproduce

The app only needs its existing Node helper and the JSON weights. Development training uses `scripts/challenge/requirements.txt` (NumPy 2.3.5):

```sh
python3 scripts/challenge/fetch-replays.py --manifest docs/reference/challenge/training-sources.json
BattleEngine/runtime/node scripts/challenge/prepare-training.cjs
python3 scripts/challenge/train-policy.py
python3 scripts/challenge/finetune-policy.py
```

Pinned public replays may later disappear; the fetch command reports a reproduction failure rather than silently substituting newer games. Raw logs/examples/rollouts remain under ignored `build/challenge-training/`; the app bundles neither chats nor the raw replay corpus. The source manifest records public replay IDs and hashes. `challenge-policy.training.json` records the original imitation data provenance; `challenge-policy.json` also records adaptation/validation/final evaluation.

`prepare-opponents.cjs SOURCE` compiles the reviewed roster proposal and the reviewed BW analysis/usage snapshots; it is a development command, never a runtime network update. Production teams are checked in as `BattleEngine/challenge-opponents.json`.

## Verification

- Complete Node engine suite: 135 passing tests (`/tmp/ptb-challenge-engine-final.log`).
- Final challenge-native tests: 12 passing, including the actual engine process, two-encounter resource carry, deterministic resume, rejected-command recovery, surrender, model version mismatch and Sketch learning/replay (`/tmp/ptb-challenge-sketch.log`).
- Peer regression selection exercised 76 native tests; the manual interactive preview was intentionally skipped. The window-minimum failure was reproduced and fixed; the focused 27-test selection then passed, including singles/doubles/singles reuse and the injected minimum reset (`/tmp/ptb-challenge-native-focused.log`).
- LLVM region output was inspected for the write/acknowledge/replay/reward paths, not only a line-coverage percentage. `git diff --check` passed.

### Interactive UI verification (2026-10-30)

- Full Node suite: 135 passing (`/tmp/ptb-challenge-ui-engine-final.log`). The initial sandbox-only attempt could not run the loopback-server test; the unrestricted local test rerun passed all tests.
- Shared-window regression selection: nine passing peer/entry tests, including both modes' original entry renderer, window reuse, auxiliary windows, result music and item/Mega control fit (`/tmp/ptb-challenge-ui-final.log`).
- Native challenge verification: 19 passing tests, recorded in `/tmp/ptb-challenge-ui-verified.log`: real CPU wins, final-effect gating, item selection/duplicate rejection, PP carry after saving and advancing, restored reward healing/revival, replacement with an incoming-only provider, member validation, all trainer atlases/names, offscreen production entrance and window teardown.
- Offscreen production UI captures: `/tmp/ptb-challenge-selection.png`, `/tmp/ptb-challenge-trainer.png`, `/tmp/ptb-challenge-battle.png`, `/tmp/ptb-challenge-reward.png`. These use a controlled two-encounter test fixture, not the user's collection.
- Restoring the old frame-only reward guard deliberately made the saved-victory healing regression fail (zero HP and unclaimed reward remained); restoring the fix makes it pass. LLVM region output for the reward and adapter paths is in `/tmp/ptb-challenge-ui-regions.txt`.

### Trainer handoff, Charizard assets and size follow-up

- Entry-only native masking retains stationary Pokémon through the trainer/foe handoff; native GIFs and floating continue, with duplicate WebKit actors hidden. The global native mask is retained for move/Mega playback. Existing queue-only tests had not asserted nonparticipating native visibility.
- The initial entry announcement now shows a localized enemy-trainer appearance message, with Korean subject particles, in the existing temporary notice area. Restored battles do not replay it.
- Normal Charizard's four front/back/shiny variants now use pinned PokéRogue atlases reconstructed at 10 FPS instead of BW PokéAPI GIFs. Source files/hashes are in `PokeRoguePlayer/base-sprites`; `scripts/prepare-charizard-sprites.py` reproduces them. Provenance-keyed cache names ignore old provider files. Other ordinary species still use their existing GIF provider; Mega assets remain unchanged.
- Ordinary physical-height extents are unchanged. Extents above 140 are smoothly compressed toward 160, preventing a very large reserve/form from shrinking the entire shared camera. Species still have distinct relative sizes and proportional front/back art.
- Real WebGL/native regression samples the entire opposing entry. Restoring the former mask reproduces disappearing native actors; restoring the former height calculation fails the Charizard minimum-size regression (80.14 points in the tested giant-reserve team).

- Final follow-up verification: 24 native tests passed (`/tmp/ptb-entry-continuity-final.log`), covering original Charizard hashes/144-frame GIFs and old cache rejection, continuous own display during foe entry, Korean/localized trainer notices, size bounds, original moves, Mega effects, single/double entries and the production challenge window. LLVM regions inspected in `/tmp/ptb-entry-continuity-regions.txt`; `git diff --check` passed. No monitor test window, package or release note was produced.

### Fixed opponent-type arenas

- Both challenge and peer modes now choose a bundled original PokéRogue arena from the opponent's registered six species, replacing match-ID randomness. Dual types count once each; the most frequent wins. Ties use the explicit stable `BattleArena.typeOrder`, independent of team order or process hashes. Peer players may have different backdrops because each faces a different team.
- The mapping covers all 18 supported types: fire/volcano, water/lake, grass-bug-poison/forest, rock-flying-dragon/mountain, electric-steel/metropolis, ground/desert, ice/ice cave, fighting/dojo, psychic-fairy/fairy cave, ghost-dark/cave and normal/plains. No new or unverified artwork is introduced.
- The arena stays fixed through switches, transformations and battle actions. A challenge's next encounter uses that encounter's fixed roster; loading the same encounter chooses the same arena.
- Eleven tests passed (`/tmp/ptb-opponent-type-arenas.log`): type mapping/ties/unknown fallback, all 27 challenge rosters including expected specialist arenas, original asset hashes and fills at both battle dimensions, peer singles/doubles stability and the production challenge UI. LLVM regions: `/tmp/ptb-opponent-type-arena-regions.txt`.

### Red's End-biome arena

- Red alone overrides the opponent-type selection with PokéRogue's original `images/arenas/end_bg.png`, the End biome used for the Eternatus encounter. Source reference: https://wiki.pokerogue.net/gameplay:modes:classic#end_biome .
- The background uses the existing pinned asset revision `009cac30c39d3615c7b2c320c3984af368871031`; the reproduction importer, original path and SHA-256 manifest include it. It is in the special group and is not selected by the ordinary type mapping.
- Every other challenge encounter retains its opponent-type arena; peer battles are unchanged. The override depends on the stable encounter ID `red`, so entering again or resuming selects the same background.
- Validation: 11 tests passed (`/tmp/ptb-red-end-arena.log`), including the Red-only override for all 27 encounters, original image hashes, both viewport sizes and the production challenge UI. Both override/type-fallback LLVM regions were inspected (`/tmp/ptb-red-end-arena-regions.txt`).

### Interactive QA app and Red sun team

- `scripts/build-challenge-test-app.py` builds a separate ARM64 local test app, marked with `PTBChallengeTestMode`. It opens the Battle tab and exposes “Instant win (test)” in challenge battles. Ordinary builds omit that marker; the engine session also rejects the test action when disabled. The button sends an actual opponent surrender to the engine, so the normal victory/reward/save/next flow runs without restoring HP/PP. Test runs use a separate `challenge-test-run-v1.json` and a one-time `challenge-test-companion-v1.json` snapshot of the real collection. The marked QA app exposes Battle and Collection tabs; rewards never mutate the production collection. Subsequent launches preserve the QA snapshot instead of overwriting it.
- Red's six individuals now have IV 31 in every stat (displayed star value 32), level 100 and the existing zero-EV/nature policy. Recalculate imported stats from those IVs, including Pikachu's former Hidden Power IV reductions. Perfect IVs change its Hidden Power type according to normal BW rules.
- Red Charizard holds Charizardite Y and uses Weather Ball, Solar Beam, Fire Blast and Air Slash. This is an explicit user-requested post-BW compatibility exception, labeled separately from usage evidence. `scripts/challenge/red-overrides.cjs` reapplies it after roster generation. Mega Y's Drought and changed stats use the shared Mega engine; CPU move choices request Mega Evolution whenever eligible. Other NPC modern items remain rejected unless they are explicitly supported matching Mega Stones.
- Full engine tests: 136 passing (`/tmp/ptb-red-mega-engine-verified.log`). Six native session tests passed (`/tmp/ptb-challenge-test-win-native.log`), including a real test-mode victory preserving resources, reward transition and disabled-mode rejection. The engine revision was advanced to guard old deterministic replays against changed CPU Mega choices.

### Victory footer and champion completion

- End-only frames (including test opponent surrender) now complete an idle presentation queue using the decision token. New damage/move/entry events still drain first. The actual production-window regression reproduces the former missing reward footer without calling presentation completion from the test. Restoring the old behavior leaves the screen stuck in `battle`, as reported.
- The reward footer stays visible. Save-and-exit can preserve an unclaimed reward; Next activates after claiming the one reward. Existing HP/PP carry and atomic reward handling remain in place.
- Final Red victory replaces the battle/result music with the supplied `RubySapphireChampionVictory.ogg`, decoded without trimming or rate changes into PCM WAV (44,100 Hz stereo, 2,178,255 frames). The complete track repeats through the existing BGM mixer/volume. Original OGG, WAV and SHA-256/PCM metadata are retained; `prepare-champion-music.py` reproduces the conversion with SoundFile.
- The six final run members appear individually in order, hold briefly and fade out, followed by the exact `Champion!` title. A bottom Close button appears only alongside the completed trophy/Champion title, after all six introductions and fades. Closing cancels the animation task and stops music.
- An optional per-individual `championAchievedAt` field preserves old save compatibility. Only the final six individual IDs receive the gold trophy, not retired members or other same-species individuals. The collection is atomically written before badges publish, repeated awards keep the original date, and a restored cleared run retries missing awards. Trophy icons appear in the collection grid, the individual/loadout section and the capture-log card.

- Final validation: 15 focused native UI/celebration tests passed (`/tmp/ptb-champion-ui-verified.log`), including original champion PCM/frame metadata, sequential/cancelled celebration, production final-screen render, legacy save decode, exact-ID/idempotent trophy persistence, atomic-write failure, the no-event production victory footer and normal challenge transitions. The broader 29-test selection also passed before the final render fixture was added, including normal final-knockout playback and result music (`/tmp/ptb-champion-verified.log`). Full engine suite: 136 passing (`/tmp/ptb-champion-engine-final.log`). LLVM regions: `/tmp/ptb-champion-regions-final.txt`. Screens: `/tmp/ptb-challenge-reward-fixed.png`, `/tmp/ptb-champion-complete.png`.


### Champion shiny reward

- Closing the cleared Champion scene through its bottom button or native X first opens a localized graduate picker. Any unreleased, non-shiny stored graduate is eligible, including an individual outside the final six and legacy graduates without a complete battle profile. Existing shiny and released records are excluded.
- Selection previews the shiny sprite. Applying changes only that individual's shiny flag; stats, nature, moves, ability, held-item defaults and trophy remain intact. The button then closes the window. Claim later/X can defer the picker; reopening restores the entitlement. A new challenge cannot overwrite an unclaimed clear.
- The run persists the selected recipient before collection mutation. An atomic collection write contains both the shiny flag and a run-ID claim ledger; only then is the run receipt acknowledged. A crash between the two files resumes the same claim instead of granting another Pokémon. Failed collection writes publish neither the shiny flag nor the ledger and can be retried.
- Validation: 33 challenge-native tests passed (`/tmp/ptb-champion-shiny-final.log`), covering close/X, deferred/reopened rewards, an outside-team graduate, legacy eligibility, exactly one recipient, crash recovery, write failure/retry and QA snapshot isolation. Full engine suite: 136 passing (`/tmp/ptb-challenge-resumed-engine.log`). The duplicate-recipient guard is also mutation-tested before the final passing run. The production reward screen is rendered offscreen from fixture data, without awarding anything to the user's collection.


### Resumed final verification (2026-11-02)

- 52 native tests passed (`/tmp/ptb-challenge-resumed-native-final.log`): challenge engine/session, resource carry, rewards, celebration, shiny receipts, QA isolation, item defaults, entry continuity and the complete arena rendering matrix. Engine tests: 136 passing (`/tmp/ptb-challenge-resumed-engine.log`).
- The full visual audit exposed an obsolete total of 240 after adding Red's End biome; all render assertions had passed. Its expected total now follows the mode/arena catalogs, and all 256 arena/move/direction cases pass. The earlier fixed-count version fails on exactly this matrix.
- Disabling the collection's duplicate-run recipient guard made the actual close/reopen/claim regression fail (`/tmp/ptb-shiny-ledger-mutation.log`); the original guard was restored before the final passing run. LLVM source regions were inspected in `/tmp/ptb-champion-shiny-regions.txt`, including write/recovery and window-close paths. Defensive invalid-input branches are not claimed as covered.
- Offscreen production picker render: `/tmp/ptb-champion-shiny-reward.png`, using controlled fixture graduates. Python script syntax, bundled challenge JSON and staged whitespace checks passed. No release-note entry or ZIP was generated for this work.


### Test-only next-trainer traversal

- The marked QA app shows Next trainer beside Instant win on the battlefield, and on the victory-reward footer. It can skip the current battle or its unclaimed reward without fabricating a victory. The ordinary app provides neither control and the session rejects test traversal when disabled.
- Traversal atomically advances exactly one encounter, keeps current HP/PP/status/items, clears the previous replay checkpoint and starts the next real CPU encounter. The UI remounts the battlefield, resets the trainer entrance and selects that opponent's original arena and configured BGM immediately. Ordinary trainers use the shared battle BGM; Red uses separate user-supplied Ruby/Sapphire champion battle and victory tracks, retaining its End arena.
- Playback/submitted-action gating prevents changing encounters in the middle of an effect. Red has no next encounter: the traversal button is disabled there, while Instant win can exercise the full Champion celebration and shiny reward.
- Regression runs the actual engine through all 27 encounters to Red with spent PP carried forward, checks disabled-mode rejection and the terminal boundary, and also traverses an unclaimed victory reward. A UI-model test verifies fresh trainer intro state, Misty's water arena, configured battle music and playback gating. Removing the session's test-mode guard deliberately fails the traversal regression; the guard is restored before the passing run.

- Final traversal verification: all 36 challenge-native tests passed (`/tmp/ptb-challenge-next-final.log`). Session/UI/store LLVM regions were inspected (`/tmp/ptb-challenge-next-regions.txt`); the disabled-mode guard and effect-busy early return executed. The 27-encounter test exercises the last-encounter rejection and uses Instant win on Red to enter the normal clear path. ARM64 QA app is rebuilt with the marked test controls; production saves are not reset.


### Encounter-specific entrance titles

- The eight Elite Four encounters announce “사천왕 {name}이/가 등장했다.”; Red announces “포켓몬 마스터 레드가 등장했다.”. Gym leaders keep the existing opponent wording; Blue and final Lance now use Champion wording as described below. Equivalent titles are localized in all eight languages.
- Retain the original encounter ID separately from the shared sprite/name key, so Koga's gym and Elite Four appearances and Lance's Elite Four/champion appearances remain distinct. Opening-only messages and Korean subject-particle selection are preserved. The two focused announcement tests pass, covering all Elite Four encounters, Red, repeated-role trainers, unchanged resume messages and localized names (`/tmp/ptb-trainer-title-tests.log`).


### Returning trainers, champions and Red battle music

- The second Koga, Bruno and Lance encounters display a localized `(Gen II)` suffix in all opponent names and entrance messages, including Korean `(2세대)`. Shared sprite keys remain unchanged. Green/Blue and the final Lance announce the Champion title; earlier Elite Four appearances retain Elite Four titles. Korean subject particles follow the base trainer name rather than the parenthesized suffix.
- Red's victory music uses the exact supplied `/tmp/RubySapphireChampionVictory.ogg` source, already bundled as the losslessly decoded `RubySapphireChampionVictory.wav`. Original/archived source SHA-256 matches `468696310084e61b0d5c2f6ca14e5163eb36d898bf76e02b32ea0754a7dc5196`. The existing BGM volume and complete-track looping apply. The victory celebration uses that track; ordinary loss/result and reward-screen music behavior remains unchanged.
- Five focused announcement/music tests pass, including the real Red CPU session from battle through clear and reward-screen silence, the original PCM/frame/hash verification, and normal opponent traversal (`/tmp/ptb-challenge-roles-red-music-final.log`).


### Separate Red battle and victory audio

- Corrected the requested split: Red battles use `/tmp/RubySapphireChampionBattle.ogg`; only the settled Red win/Champion celebration uses `/tmp/RubySapphireChampionVictory.ogg`. Pending final-action effects keep the battle track until the normal presentation completes. Ordinary trainers retain Gold/Silver battle audio.
- Archived the new source under `BattleEngine/music` and decoded it to `RubySapphireChampionBattle.wav`: 44,100 Hz stereo, 4,119,954 frames, complete-track repeat at the original rate. SHA-256/PCM metadata is in `champion-battle-source.json`; reproduce with `prepare-champion-music.py --battle`. Both normal and QA bundles include the new WAV. Existing BGM volume controls apply to both cues.
- Focused tests cover the distinct source/WAV hashes, original frame counts/rate/looping, real Red battle → pending victory → settled victory → reward-screen silence, and ordinary trainer music (`/tmp/ptb-red-separated-music.log`).


### Trophy-gated close and ZIP packaging

- Champion Close now appears only when the trophy/Champion scene is complete. An actual production SwiftUI render verifies the introduction has no Close text and the completed scene contains both Champion and Close. Captures: `/tmp/ptb-champion-before-trophy.png`, `/tmp/ptb-champion-complete.png`.
- Restoring the former unconditional footer deliberately fails that rendered-text regression (`/tmp/ptb-champion-close-mutation.log`); the mutation is restored before final validation. The user explicitly requested a November 2 release-note entry and an ARM64 Desktop ZIP for all accumulated challenge and presentation changes.

- Final cumulative native selection: 54 tests passed (`/tmp/ptb-challenge-zip-native-final.log`), covering challenge traversal, resources/rewards, trainer titles, both Red tracks, actual trophy-gated Close rendering, entry continuity and item defaults. Build preparation reran the complete engine suite: 136 passing (`/tmp/ptb-challenge-release-build.log`). LLVM source regions for the celebration and cue transitions were inspected (`/tmp/ptb-challenge-zip-regions.txt`).

- Release bundle verification passed: ARM64 app and helper, strict/deep signature validation, 4,356 matching source/resource files, both audio hashes, test marker absent and an actual CPU battle turn through the bundled engine (`/tmp/ptb-challenge-release-verification.json`). No installed app was replaced. The ZIP includes the full descending Korean release-note history, with November 2 (1st release) added at the user's request.


### Periodic recovery and independently expiring team rewards

- Victories 3/6/9/12/15/18/21/24 offer team-wide full HP/PP recovery (including revival, status cure and sleep-counter cleanup), replacement, and one random team-buff option. Other pre-Elite victories retain HP +35% / one move PP +3 / replacement, plus a random buff. From victory 16, individual HP becomes full recovery/revival and PP recovery restores all slots of the selected individual. Red's final victory retains the Champion/trophy/shiny ending.
- Each completed non-final victory rolls exactly one of Attack+Sp. Atk +1 or Speed +1 with equal probability. Commit that offer with the victory before displaying it; reload never rerolls a committed choice. Legacy pending rewards migrate once to a persisted offer. A full recovery never recreates consumed items.
- Each selected buff applies to the whole player team for the next two encounters. Instances retain independent IDs/countdowns, stack additively, survive member replacement and switching, and expire once per terminal encounter commit. The initial buff list is checkpointed for deterministic mid-battle replay. A nonterminal frame or reload cannot spend duration. QA traversal consumes the encounter it skips, but cannot bypass an unclaimed reward.
- The engine maintains ordinary boost state separately and temporarily combines reward stages only for synchronous stat/damage evaluation. Standard critical-hit/Unaware checks see the combined stages; move/ability boost changes retain their original Contrary/Simple behavior. Ordinary Haze/clears and switches leave the external challenge reward active. Normal/combined upper caps prevent ineffective extra boosts above +6. Owned stored stats and collection profiles remain unchanged; Mega stat changes and Trick Room use the shared engine calculations.
- Reward UI uses the saved tier/offer, shows team targets and independent remaining-battle counters, and removes the former no-reward skip route. Next stays disabled until an actual reward commits; test traversal is also rejected on the reward screen. Closing/reopening preserves the mandatory choice. Completed Champion screens hide unused future-battle counters.
- Engine revision advances with these mechanics. The immediately preceding checkpoint revision can replay only with no checkpointed buffs; native regression confirms the previous no-buff replay remains deterministic.
- Fixed-roster report: [27 encounters / 162 Pokémon / 648 moves](opponent-rosters.ko.md), generated by `scripts/challenge/report-rosters.cjs` from the actual fixed constants and localized catalog. Hidden Power types come from the Gen V dex and each fixed individual's IVs.

- Final verification: 46 native challenge tests passed (`/tmp/ptb-challenge-rewards-verified.log`) and 142 engine tests passed (`/tmp/ptb-challenge-rewards-engine.log`). Removing duration decrement made the expiry regression fail six assertions (`/tmp/ptb-reward-expiry-mutation.log`); restored before the passing run. LLVM regions for both duration branches, full recovery and offered-buff validation were inspected (`/tmp/ptb-rewards-regions.txt`).
- The isolated QA app opens at the third-victory reward with the user's existing test-team copy. This explicit fixture includes a fainted member, poison/sleep, spent PP and one remaining encounter of the power buff, with another power option offered to test stacking. Previous test progress was backed up; production collection/run saves were untouched. Native accessibility confirms exactly three options, a usable Apply and a disabled Next before application.


### Defeat is terminal, including after app restart

- Verified with an actual CPU victory that knocks out all six player members after a prior encounter win and power reward. The run persists `lost`; reopening yields the result screen, while engine resume, start-next, test traversal, advance and reward application are rejected.
- New challenge returns to six-member selection and starts a distinct run at Brock/encounter 0, with fresh HP/PP/status, no team buffs and no retired IDs. Completed progress and temporary rewards cannot carry into the retry. The surrender and draw-ending regressions also pass. Three focused tests passed (`/tmp/ptb-challenge-loss-restart.log`); production behavior already enforced this contract, so only regression coverage was added.


### Five independent rewards lasting three encounters

- Fresh random offers are now Attack, Sp. Atk, Speed, Defense or Sp. Def, each a single +1 stage to the entire team, selected uniformly from five choices. HP was explicitly excluded by the user. Every new instance lasts three completed encounters; each instance stacks and expires independently. All eight UI languages show the individual stat and the three-encounter duration.
- Defense and Sp. Def enter the same combined-stage damage path as offense/speed; engine regression compares real physical/special damage with equivalent ordinary stages and verifies no HP/offensive-stat increase.
- Already-active legacy `power` (Attack+Sp. Atk) instances retain their original remaining duration and replay behavior. That legacy value is excluded from random candidates and cannot be freshly claimed. A pending legacy combined offer migrates once to a new saved five-way offer. The previous reward engine revision remains replay-compatible; the pre-reward revision remains compatible without reward snapshots.
- Three-encounter stacking is verified at remaining lists `[3]`, `[2,3]`, `[1,2]`, `[1]`, then expiry, including a nonterminal frame and reload. The new reward set is explicitly asserted to contain exactly five independent non-HP keys.
- Verification: 49 native challenge tests passed (`/tmp/ptb-five-rewards-native.log`); all 143 engine tests passed (`/tmp/ptb-five-rewards-engine.log`). A focused previous-reward-checkpoint replay test is recorded separately (`/tmp/ptb-five-rewards-legacy.log`).

- Focused final coverage selection: nine tests passed (`/tmp/ptb-five-rewards-focused.log`), including all five stat mappings/translations, three-battle expiry and old/new replay. LLVM regions were inspected (`/tmp/ptb-five-rewards-regions.txt`). Rebuilt the isolated QA app without resetting progress; the actual fourth-victory screen displays “팀 전체 방어 +1 · 다음 3전 지속 · 중복 적용”, with Apply requiring a valid choice and Next disabled until claim.


### Optional challenge points shop

- Every committed victory grants 100 challenge points, atomically with the result. Duplicate terminal frames cannot award twice. Balances belong to the current run and reset on a new challenge. Legacy saves receive 100 points per completed victory once; saved post-purchase balances are never recalculated/refunded on reopening.
- Four cards above the mandatory victory choice offer one-member full HP/PP/status recovery and revival (100), all move PP (50), 20% max-HP recovery (10) and 40% max-HP recovery (30). HP recovery follows the existing revival behavior; partial healing preserves status on a surviving member. Items are not regenerated. Purchases are immediate, repeatable within balance and optional.
- Shop access is limited to reward/intermission, after effects settle. The purchase sheet selects an eligible current team member and shows current HP/PP. Missing targets, unnecessary recovery and insufficient balance are rejected; debit and recovery commit in a single atomic run write before publishing. A failed write leaves both unchanged and can retry.
- Shopping never consumes the mandatory reward or permits Next early. After applying the mandatory reward, the player can continue without shopping. Loss/surrender disables shopping and a fresh run starts at zero points.
- Native production-view OCR verifies all four cards and prices (`/tmp/ptb-challenge-shop.png`). Regression covers genuine victory credits, duplicate/loss/QA-skip noncredits, all four products, repeated purchases, caps, single-target scope, status cure/revival, write failure, migration and no-reward bypass. Removing the affordability predicate deliberately fails the insufficient-balance test before restoration (`/tmp/ptb-shop-balance-mutation.log`).

- Shop release validation: the complete 57-test selection passed (`/tmp/ptb-challenge-shop-native-final.log`); eight focused shop tests, including the additional malformed-legacy boundary test, passed (`/tmp/ptb-challenge-shop-verified.log`). Full-HP status-only and PP-only purchase eligibility were checked separately (`/tmp/ptb-shop-eligibility-final.log`). All 143 engine tests pass in release preparation. LLVM regions are in `/tmp/ptb-shop-regions.txt`.
- Final ARM64 bundle checks passed: strict/deep signing, 4,356 matching source/resource files, both audio hashes, shop UI compiled in, test controls disabled, and all five boosts with owned stats unchanged through a real bundled-engine turn (`/tmp/ptb-rewards-shop-release-verification.json`). The pending November 2 second release includes both the reward changes and optional shop.
