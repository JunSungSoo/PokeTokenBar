# Challenge implementation — engine and interactive UI

Implemented 2026-10-30. The Battle tab now opens the native challenge window: select six owned graduates and their held items, fight the automatic CPU, claim a reward, save and exit, or continue to the next fixed encounter.

## Implemented

- Explicit `challenge` engine profile: six combatants per side, singles only. Peer singles still selects three and doubles four. A challenge does not create a fake LAN peer or a response deadline.
- Twenty-seven fixed encounters / 24 characters / 162 slots. The reviewed six-species candidates are unchanged. Opponents use level 95 (gyms and Elite Four) or 100 (Blue, second-generation Lance and Red), IV 31 except typed Hidden Power, EV 0 and fixed natures/items/abilities/moves. Every set passes the pinned Showdown generation-V `Obtainable` validator. The 16 species with missing/small usage samples have authored legal sets (17 slots); evidence flags distinguish them from reviewed analysis sets. Later encounters select another documented role where available; a single viable ability is not invented for variety.
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


### Initial optional challenge points shop (superseded by randomized stock below)

- Every committed victory grants 100 challenge points, atomically with the result. Duplicate terminal frames cannot award twice. Balances belong to the current run and reset on a new challenge. Legacy saves receive 100 points per completed victory once; saved post-purchase balances are never recalculated/refunded on reopening.
- Four cards above the mandatory victory choice offer one-member full HP/PP/status recovery and revival (100), all move PP (50), 20% max-HP recovery (10) and 40% max-HP recovery (30). HP recovery follows the existing revival behavior; partial healing preserves status on a surviving member. Items are not regenerated. Purchases are immediate, repeatable within balance and optional.
- Shop access is limited to reward/intermission, after effects settle. The purchase sheet selects an eligible current team member and shows current HP/PP. Missing targets, unnecessary recovery and insufficient balance are rejected; debit and recovery commit in a single atomic run write before publishing. A failed write leaves both unchanged and can retry.
- Shopping never consumes the mandatory reward or permits Next early. After applying the mandatory reward, the player can continue without shopping. Loss/surrender disables shopping and a fresh run starts at zero points.
- Native production-view OCR verifies all four cards and prices (`/tmp/ptb-challenge-shop.png`). Regression covers genuine victory credits, duplicate/loss/QA-skip noncredits, all four products, repeated purchases, caps, single-target scope, status cure/revival, write failure, migration and no-reward bypass. Removing the affordability predicate deliberately fails the insufficient-balance test before restoration (`/tmp/ptb-shop-balance-mutation.log`).

- Shop release validation: the complete 57-test selection passed (`/tmp/ptb-challenge-shop-native-final.log`); eight focused shop tests, including the additional malformed-legacy boundary test, passed (`/tmp/ptb-challenge-shop-verified.log`). Full-HP status-only and PP-only purchase eligibility were checked separately (`/tmp/ptb-shop-eligibility-final.log`). All 143 engine tests pass in release preparation. LLVM regions are in `/tmp/ptb-shop-regions.txt`.
- Final ARM64 bundle checks passed: strict/deep signing, 4,356 matching source/resource files, both audio hashes, shop UI compiled in, test controls disabled, and all five boosts with owned stats unchanged through a real bundled-engine turn (`/tmp/ptb-rewards-shop-release-verification.json`). The pending November 2 second release includes both the reward changes and optional shop.


### Randomized recovery shop and explicit revival rewards

- Each non-final victory saves four distinct products sampled without replacement from eight: one-member full HP/PP/status recovery (100), all PP (50), HP 20% (10), HP 40% (30), status cure (40), Revive (30), living-team HP 30% (50), Max Revive (70). Reopening, purchasing and applying the mandatory reward preserve that victory's stock. The next actual victory replaces it; old pending saves receive one persisted initial stock.
- Ordinary recovery cannot target a fainted member. Team 30% adds floor(maxHP × 0.30), minimum one HP, individually to living members only and caps at maximum; it does not restore PP, clear status or revive. Status cure only clears major status/sleep counters. Revive restores one fainted member to half maximum HP (floor, minimum one), Max Revive to full HP; both clear status without restoring PP.
- Every non-final victory's mandatory list includes a fixed Revive choice, including three-win milestones. Ordinary HP/PP rewards require a living target. The three-win full-team reward retains full HP/PP/status recovery and revival. Purchases remain optional and repeatable; the mandatory single reward still blocks Next until applied. Five independent three-encounter stat rewards remain unchanged.
- Save validation requires exactly four distinct stock entries. Corrupt saves are preserved. Purchase validation also checks offered membership, eligibility and balance before one atomic debit/recovery commit. Existing saved progress/points are retained.

- Verification: 63 native challenge tests pass (`/tmp/ptb-random-shop-final.log`). The production window renders four new product cards and correct prices in `/tmp/ptb-random-challenge-shop.png`, with OCR assertions. Removing the living-HP eligibility guard fails 12 assertions (`/tmp/ptb-random-shop-mutation.log`); after restoring it, all 11 shop tests pass (`/tmp/ptb-random-shop-restored.log`). Source-region inspection (`/tmp/ptb-random-shop-regions.txt`) confirms status cure, both revivals, team-only HP healing, migration and stock validation execute. The exhaustive-switch revive fallback is intentionally unreachable because those cases return before the living-only guard. No release history, ZIP or Git publication was requested for this change.


### Audit: collection edits do not refresh a started team's loadout

- Registration copies the six `BattlePokemon` value objects into the run save. Launch and
  replay use `checkpoint.initialTeam`; subsequent encounters take `run.team`. The battle HUD
  reads simulator frames. None of these paths rebuilds existing members from the collection.
- Added an integration regression that starts through the UI model, edits Charizard's move
  (Return → Protect), ability (Blaze → Solar Power) and default item using the same persisted
  APIs used by Collection/Pokédex, then reconciles UI selection. The test verifies the saved
  collection really changed, while the full registered team and current frame did not.
- The regression closes/reopens the run, resumes its real engine, wins using the frozen move,
  claims a reward and starts the next encounter. Checkpoints, ability, move slots, item and
  carried PP still match the registered snapshot. A provider that rejects existing members
  prevents silently rebuilding them during resume or advance.
- No collection-to-run leak was found, so no runtime behavior change or additional guard was
  necessary. An inline comment records the snapshot contract. Existing explicit replacement
  rewards and battle-earned Sketch persistence remain supported. All three focused native
  regressions pass (`/tmp/ptb-challenge-frozen-verified.log`).


### November 2 third ZIP release

- The user approved the exact third-release note before packaging; the first and second
  records remain unchanged. All 64 native challenge tests and all 143 engine tests pass.
- The ARM64 2.5.6 release bundle passes strict/deep signature verification, 4,356 resource
  hash comparisons, champion-track hashes, test-mode exclusion and a real packaged-engine
  turn with all five stat boosts while owned stats remain unchanged.
- Archive: `PokeTokenBar-2.5.6-arm64-20261102-challenge-shop-random.zip`; packaged `2026-11-02T14:49:20+09:00`;
  SHA-256 `24d585dc03d168d5200e9b0116cc041d5622f0ca4d31c281ae42f2e192cac8bc`. The ZIP contains the complete descending release history,
  app and release metadata; integrity, note bytes and packaged executable are verified.


### Recovery rule correction after the third release

- Active shop stock is now six products, still four distinct saved offers per victory.
  Revive/Max Revive are removed from offers and the fixed revival reward is removed.
  Their enum values remain decode-only for released saves; migration preserves retained
  offers, points, resources and run ID, then fills removed slots from active products once.
- All HP recovery products and individual HP rewards can revive at their advertised amount.
  Revival clears the revived member's status/sleep counters. Partial HP recovery on a living
  member preserves ailments. Full recovery retains HP/PP/status cure; the three-win team
  reward still fully heals/revives/cures everyone.
- PP items/rewards can target a fainted member but never change HP. Status-cure items only
  target living, affected members. This distinction follows the user's explicit clarification.
- Only `beginEncounter` clears sleep before capturing the next checkpoint. Poison, toxic
  poison, burn, paralysis and freeze persist. Reloading a pending reward does not cure them;
  replaying an unfinished battle retains real sleep and its exact remaining duration.
- The native integration fixture carries all six major statuses across a victory, wakes only
  the sleeper on the next actual engine start, then uses Rest and resumes its sleeping state
  deterministically. Existing collection-loadout freezing, shop atomicity and milestone cure
  regressions remain in the challenge suite.

- Verification: all 65 then-current native challenge tests passed
  (`/tmp/ptb-recovery-correction.log`); the added sleep-boundary integration plus all 12
  shop tests passed (`/tmp/ptb-recovery-boundary.log`). Disabling the new sleep-reset
  predicate fails four assertions; after restoring it, the same 13 tests pass
  (`/tmp/ptb-recovery-restored.log`). LLVM regions are inspected in
  `/tmp/ptb-recovery-regions.txt`; retired-item application remains intentionally unreachable
  after eligibility rejects decode-only cases. This later change does not alter published notes.


### Seven-product shop with per-product price inflation

- Base prices are team full HP/PP/status recovery and revival 100; one member's all PP 30;
  one selected move's maximum PP 10; individual HP 20% 10; individual HP 40% 20;
  living-member status cure 10; team HP 50% 50. Four distinct products still appear per win.
- Every successful purchase raises only that product's next price by five points, irrespective
  of target member or move slot. Run-local counters survive stock refresh, close/reopen and
  subsequent encounters. New runs reset them; older saves without counters begin at base prices.
- The price used by card labels, the purchase button, affordability checks and atomic debit
  comes from the same run helper. Counter update, recovery and point debit commit together;
  failed writes and rejected/no-op purchases do not raise prices. External saved counters are
  validated before price multiplication against a bound implied by awarded points/minimum price.
- Selected-move recovery requires an explicit valid depleted move index at commit. The target
  picker can inspect any member with depleted PP, including a fainted member, and shows move
  names/current/max PP. Only the chosen slot changes; PP recovery never revives. Full recovery
  now covers every registered member with a single charge. Half-HP team recovery preserves
  living members' status and cures members it revives, leaving PP untouched.
- The former `teamHeal30` serialized key is retained by the `teamHeal50` case so a saved
  offer upgrades without resetting stock, points or progression. Removed revive-item save
  migration remains supported. Collection loadout freezing and sleep-boundary rules remain.

- Verification: all 69 native challenge tests pass (`/tmp/ptb-shop-prices-final.log`). The
  selected-move sheet renders both move names and PP totals, and native OCR verifies the
  purchase button changes from 10 to 15 points after a purchase. Product tests cover per-item
  counts, same product on different slots, refreshed stock, reload, fresh-run reset, rejected
  slots, failed writes, old saved stock and malformed counters. Removing the increment fails
  five assertions (`/tmp/ptb-shop-inflation-mutation.log`), then restoration passes the full suite.
  Source regions are inspected (`/tmp/ptb-shop-prices-regions.txt`); the apply-layer missing-slot
  return is intentionally unentered because the committing store rejects a missing slot first.


### Victory points increase every three encounters

- The per-victory award is `100 + 20 * floor(encounterIndex / 3)` using the zero-based
  encounter index: 1–3 award 100 each, 4–6 award 120 each, continuing to 25–27 at 260 each.
  Twenty-seven actual victories earn 4,860 points before shop spending. Defeats, duplicate
  terminal frames and QA skips retain their existing non-award behavior.
- Award validation and the purchase-count bound use the cumulative maximum for the run's
  encounter count, avoiding the former 2,700-point ceiling. External malformed count/HP
  validation still runs before cumulative arithmetic. The victory result and points remain
  one atomic save commit.
- Existing stored balances are retained without retroactive refunds/recalculation. A legacy
  save with no point field receives the cumulative tiered total for completed victories once.
  Current stock and product purchase counts remain intact. Shop guidance is translated in
  all eight languages to describe the three-encounter increment.
- A full 27-victory store regression verifies every tier, duplicate rejection, reopening each
  checkpoint, the 4,860-point total and final clear. Legacy/spent-balance regressions cover
  the first 3→4 boundary while preserving product inflation history.

- Verification: all 16 shop/point tests pass (`/tmp/ptb-tiered-points.log`). Restoring the old
  balance ceiling deliberately fails the normal 19th-win commit; restoring the cumulative
  ceiling passes both 27-victory and legacy/spent-balance tests
  (`/tmp/ptb-tiered-points-restored.log`). Source regions are inspected in
  `/tmp/ptb-tiered-points-regions.txt`. The isolated QA app is rebuilt with current source
  while preserving its existing fourth-victory reward checkpoint.


### Opponent level tiers

- Rounds 1–12 use level 75, rounds 13–16 level 90, and rounds 17–27 (Elite Four,
  champions and Red) level 100. All 162 opponents' six stats are rebuilt from the Gen V
  species base stats, existing IVs, nature and zero EVs with the normal floor operations.
  Rounds 17–27 retain their exact prior member data. No team, move, ability or item changes.
- `scripts/challenge/level-policy.cjs` is invoked after the Red overrides in roster generation;
  reapplying it is deterministic. The fixed-roster Korean report now shows each round's level.
- The new catalog accepts only the exact reviewed preceding catalog version/hash. Adopting
  it saves the new version without changing run identity, player loadouts/resources, points,
  rewards or the in-flight checkpoint. A resumed old battle uses that checkpoint's level-100
  opponent; the next encounter uses the new level tier. Unknown catalog hashes and mismatched
  encounter counts remain rejected without rewriting the original save.
- The user's QA app/window was terminated without resetting test progress. No new test window
  is opened by this change. All 145 engine tests and 14 native session/level tests pass,
  including all 162 stat/engine comparisons, generation reproducibility, old-battle resume,
  transition to the new level and rejection of unreviewed saves.

- Removing the reviewed-version allowlist deliberately fails two assertions (an unknown
  catalog becomes writable); restoring it passes both focused level/resume tests.
  Source-region inspection confirms both the catalog adoption and rejection paths execute
  (`/tmp/ptb-opponent-levels-regions.txt`). Generated-data comparison confirms that all fixed
  loadout fields are unchanged and all level-100 teams retain their complete prior data.


### November 2 fourth ZIP release

- Existing first/second/third release notes remain unchanged; the fourth records all subsequent
  recovery, shop/inflation, point-tier, move-speed and opponent-level changes.
- Final validation passes 83 native tests, 145 engine tests, strict/deep ARM64 app/helper
  signatures, 4,356 matching resources, audio hashes, production test-mode exclusion and a
  packaged-engine turn with all five boosts and unchanged owned stats. The packaged catalog
  contains the 75/90/100 level policy and reviewed prior-version compatibility.
- Archive: `PokeTokenBar-2.5.6-arm64-20261102-challenge-update.zip`; packaged `2026-11-02T16:02:05+09:00`;
  SHA-256 `d0607228082f4e39adf83b78308551ebd2b800c16159a540ad4bdad6fbd3c126`. ZIP integrity, full release history and executable match.


## Role levels and per-encounter preparation (2026-11-03)

- Gym leaders (rounds 1–16) now use level 90; Elite Four (17–24, including first-generation
  Lance) level 95; Blue, second-generation Lance and Red (25–27) level 100. The fixed
  moves, abilities, IVs, nature and zero-EV policy are unchanged. All six stats are rebuilt
  from the new level. The prior tiered catalog is explicitly compatible: an already-started
  battle retains its checkpoint; the next encounter uses the new catalog.
- Initial registration and Next now lead to preparation, showing all six opposing species and types. The shared peer-battle preview orders all six owned members by click order; the first is LEAD. The
  existing categorized item picker edits held items with species/form and duplicate-item
  restrictions. Start commits order and items before creating the engine checkpoint.
- Preparation edits only the frozen run team and carried resources. It does not reload
  collection moves, abilities, stats, HP, PP or status. Items are synchronized into both
  the registered team and carried resource records because the engine restores carried
  items after set creation. Save and Exit persists preparation; reopening it can edit again.
  A saved ongoing battle replays its checkpoint without reopening preparation.
- Preparation cannot bypass the mandatory victory reward, modify an ongoing battle,
  resume a loss, or alter membership. Replacement remains an explicit victory reward.

Validation: 75 challenge native tests and all 145 engine tests pass. After the layout and
item-memory adjustments, 32 preparation/level/run/UI tests and the final 11 focused tests
pass. `/tmp/ptb-challenge-preparation.png` is an offscreen production-window render using
fixture teams. Removing the duplicate-item guard makes the saved-byte regression fail;
the guard is restored before the final passing run. Source-region review in
`/tmp/ptb-challenge-preparation-regions.txt` confirms the reachable phase/membership,
item-eligibility and duplicate-item rejection paths execute. Missing-ID fallback branches
inside the maps are unreachable after the equal-member-ID set validation and existing
run-resource validation; no fabricated invalid run is used to inflate their coverage.


## Shared click-order preview (2026-11-03)

Preparation now reuses `BattleTeamPreview` directly, with its selection limit set to six.
Peer battles keep their existing three/four limits. Each new preparation starts unselected;
clicking appends to the order and clicking a selected card removes it and renumbers the
remaining cards. Start and preparation Save/Exit require all six. The first selected card
shows LEAD. Opponent green/red borders and type-matchup tooltips use the exact same
last-selected-member lookup and BW2 type comparison as peer battles; neutral stays unchanged.
The held-item controls and carried HP/PP remain below the shared two-row preview.


## Red psychic slot replaced with Mewtwo (2026-11-03)

The user approved Mewtwo instead of Espeon, with Pressure, Timid and Psystrike / Ice Beam /
Recover / Fire Blast. It retains level 100, all IVs 31 and zero EVs; recalculated stats are
HP 353 / Atk 230 / Def 216 / SpA 344 / SpD 216 / Spe 325. Wise Glasses replaces the old
screen extender because this set has no screens and the Red team already uses Life Orb
and Expert Belt. The fixed override is reproducible from the original roster generator
and explicitly marked as a user-authored set, not an observed usage statistic.
The v4 role-level catalog is compatible: current battle checkpoints keep their original
opponents, while a newly started Red encounter uses Mewtwo. All 146 engine tests pass,
including BW legality, catalog regeneration and a real Recover turn with HP restoration
and PP consumption. Both native catalog/save compatibility tests pass.


## Life Orb Mewtwo with explicit recovery priority (2026-11-03)

The revised user-approved moves are Psystrike / Shadow Ball / Recover / Flamethrower, with
Life Orb. Red's Venusaur now holds Black Sludge to preserve the six-member item clause;
its existing moves, Chlorophyll, nature and stats are unchanged. The catalog generator
reproduces this assignment and all fixed sets remain BW-obtainable.

Mewtwo's NPC record carries `cpuRecoveryThreshold: 0.65`. The optional field round-trips
through the native BattlePokemon and checkpoint, becomes an NPC-only set property, and
is visible only in that side's own CPU observation. At or below 65% HP, legal Recover is
prioritized; disabled/empty-PP Recover and forced switches use the normal legal candidates.
At full HP Recover is excluded. Above the cutoff the unchanged learned model scores the
remaining choices. This is an explicit authored encounter tactic, not a claim of new ML
training. No other opponent has the field, and player sets cannot enable it.

Older opponent checkpoints omit the field and retain their original learned decisions and
held items; the old model JSON/revision is unchanged. The prior v5 catalog is explicitly
compatible. A new Red encounter receives the new set and tactic. Tests exercise the real
CPU healing turn, threshold boundaries, full HP, exhausted PP, disabled moves and legacy
checkpoint behavior. A strongly attacking injected model still selects Recover below the
cutoff; removing the priority in an in-memory mutation makes that regression fail. No
source mutation remains on disk.


## Role-aware team item assignment (2026-11-03)

The fixed fallback list is removed. An offline authored preference compiler checks the
actual four moves, ability, evolution stage, defensive profile and reviewed set role,
then finds the maximum total candidate score subject to one item per team. Scores are
engineering preferences, not observed item usage or empirical win-rate estimates. The
pinned original set recommendations in `scripts/challenge/item-reference.json` add a
small preference only to compatible candidates. The application still reads a fixed
catalog and never runs the optimizer, downloads recommendations or randomizes equipment.

The sweep covers all 162 slots and changes 89 items; looking only at earlier duplicate
fallbacks missed incompatible original slash variants. Physical/special boosters require
matching moves; fixed-damage supporters do not receive offense boosts; Choice items cannot
lock recovery/setup/support except deliberate Trick/Switcheroo/Sleep Talk variants.
Eviolite, Black Sludge, screens/weather extensions, Guts/Quick Feet orbs, Harvest berries,
Shell Smash White Herb, Unburden gems, Endure/Reversal berries and Sturdy/Custap are ranked
for the actual build. Hidden Power types use the fixed IVs; Levitate does not need Air
Balloon. Explicit Red Mewtwo Life Orb, Mega Charizard Y stone and Venusaur Black Sludge
are reserved before conflicting team choices; Mewtwo's 65% recovery tactic remains intact.

The entire reviewed six-member assignment is recorded with an item rationale in the
catalog. `opponent-items.ko.md` lists all 27 teams' prior/new items and reasons;
`opponent-rosters.ko.md` now includes held items alongside moves and abilities. Previous
v6 catalogs are compatible and in-flight checkpoints keep their old exact equipment.

Validation: 152 engine tests pass, including all 162 fixed items reaching the actual NPC
frames, legal BW sets, role regressions, global allocation and real White Herb/Flame Orb
turns. Fifteen native catalog/session tests pass; the final three-test catalog run also
checks the new Donphan and Blastoise items after the shared resources are loaded. Full
regeneration from the pinned Smogon/usage snapshots matches the checked-in catalog exactly.
The in-memory greedy mutation fails the global assignment and fixed-catalog regressions.
Logs: `/tmp/ptb-role-items-engine-final.log`, `/tmp/ptb-role-items-native.log`,
`/tmp/ptb-role-items-native-final.log`, `/tmp/ptb-role-items-mutation.log`.


## Gym and Elite Four level 95 (2026-11-03)

After the user difficulty test, rounds 1–24 (all gyms and Elite Four, including first-
generation Lance) use level 95. Rounds 25–27 (Blue, second-generation Lance and Red)
remain level 100. The offline level policy recomputes all six stats with the existing
nature, IVs and zero EVs. Species, moves, abilities, role-optimized held items and Mewtwo's
recovery tactic are unchanged. The v7 item catalog is compatible; existing live battle
checkpoints retain their exact original opponents and subsequent encounters use the new
level policy. No release-note entry or release package is created by this adjustment.


## Shop target lock after animated victory (2026-11-03)

Live inspection of a user's 3.0.1 first intermission confirmed affordable HP recovery with
all targets and Buy disabled. The saved points/resources were valid. The final effect
callback removed the battle view before its deferred busy reset reached the model, so
`effectsBusy` incorrectly remained true on the shop screen. The model now clears terminal
busy state synchronously, ignores late non-battle busy callbacks and gates purchases on
settled authoritative reward presentation rather than the removed view's mirrored flag.
Existing balances, prices, offers, recovery rules and pending mandatory rewards are retained.
The running user app/save were only inspected; no points were spent and no app was replaced.

Validation: 40 native UI/shop tests pass. The real-engine regression fails 14 assertions
on the old source (`/tmp/ptb-shop-busy-before.log`), then succeeds with the fix. The mounted
animated-victory test completes six actual attacks through production effects without
manual presentation completion and purchases PP recovery after the mandatory reward,
verifying a 100-to-70 point debit. Source-region inspection confirms the terminal reset,
late callback filter and reward purchase path execute (`/tmp/ptb-shop-busy-regions.txt`).
The running 3.0.1 user's shop was left open, its purchase sheet canceled, and saved points
were neither spent nor rewritten by this investigation. No ZIP, release note or commit/push
is produced for this fix unless requested separately.


## Requested 3.0.2 local distribution (2026-11-03)

The user requested packaging this fix as 3.0.2, a new November 3 second release-note entry,
a Desktop ZIP and then commit/push. Both app version fields and the QA short version are
updated together. The first-release notes and the earlier trainer-finale redaction remain
intact. Release verification reuses the successful 40 UI/shop tests, including the actual
mounted animated KO-to-intermission purchase, and reruns the full 152-test engine suite
in the release builder plus version-check and packaging checks. User app data is not
migrated or edited; installation is skipped by the local release builder.

Final release verification: the ARM64 app reports 3.0.2 in both version fields and omits
PTBChallengeTestMode. All 4,356 source resources match; the actual bundled helper checks
27 teams/162 NPC levels, items and stats, preserves owned stats and executes a CPU recovery
turn. The ZIP executable differs from the prior 3.0.1 release and matches the verified
3.0.2 source bundle. The second-release notes precede the first and retain the requested
trainer-finale redaction. Archive hashes and packaging time are in the ZIP release ledger.
