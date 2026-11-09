# Challenge AI input and model review — 2026-11-06

The deployed v2 policy keeps the original 32 learned priors, adds 16 learned state/action
features, and uses a conservative 0.1 blend selected on development matchups. These
features make current conditions affect relative action scores. No online learning or
human-strength claim is added.

## Corrections

- Owned effective Speed comes from the actual simulator stat calculation, including
  stages, paralysis, items, abilities, weather and side effects. Opponent Speed is a
  neutral-stat estimate from public species, level, speed stage, paralysis and Tailwind;
  hidden IVs, EVs, nature, held items and abilities are not read. Trick Room reverses the
  speed comparison in the action-specific tempo features; it does not change move priority.
- Sleep, freeze, physical burn (with Guts exception), existing target status and public
  type immunity enter action-specific features. This does not guarantee a different
  selected action whenever a status changes.
- Opponent survivors use selected-team count minus public fainted count. Own survivors
  also exclude zero HP. Counts interact with hazards, setup, recovery and last-member
  offense instead of merely adding an identical constant to every candidate.
- Available PP, disabled moves, switching restrictions, the learned lead head and the
  explicitly authored Recover tactic remain in the selection path.

## Training and evaluation

The cached corpus contains 191 retained public BW replay games and 6,967 action examples.
The split remains 159 training games / 5,829 actions and 32 evaluation games / 1,138 actions.
The final model freezes the old learned priors, fits the 16 new features with actual masked
softmax/L2 training, then blends the fitted extension conservatively. The lead head is unchanged.

Fully updated/reinforced candidates were examined and rejected after lower development
performance. Development selection uses 81 fixed games at offsets 2000/4000. Previously
examined 8000-offset trials are not presented as the final untouched audit. The final
54-game audit uses offset 12000, pairing shift 11, after selection.

- Development: legacy 49/81 wins; selected v2 50/81 wins.
- Fresh audit: legacy 33/54 wins; selected v2 32/54 wins, no truncated games.
- Replay action agreement using the actual selected weights: legacy 40.60%, v2 41.12%.
- These small fixed tests do **not** establish a win-rate improvement. They use a public
  type-adjusted power baseline, independent battles, fixed NPC rosters and all available
  engine mechanics. They are not human ladder or persistent-resource campaign results.
- 7,290 counterfactual input comparisons check score and final-choice sensitivity. The
  burn-only status slice changes relative scores in 1,395 cases but changes no top choice
  in this sampled slice; Speed changes 6 choices and survivor count changes 10. Correct
  input sensitivity is separate from a claim that every input change must flip a choice.

Metrics, digests, counts and example decisions: [ai-input-review.json](ai-input-review.json).

## Saved battles and validation

`challenge-policy-v1.cjs` and the exact original `challenge-policy-v1.json` are bundled for
existing checkpoints. A checkpoint's digest selects both its old feature code and weights.
Replayed decisions, HP, PP and combat logs remain identical (excluding wall-clock protocol
stamps). New encounters use v2. Unknown digests reject without altering the save.

Verification: 174 engine tests and 13 native challenge/save tests pass. Mutation checks
restore stale owned Speed and constant-six opponent counts and confirm regression failure.
No monitor test window, release note entry, ZIP, commit or push is produced for this stage.

## Reproduce

Use the pinned NumPy dependency in `scripts/challenge/requirements.txt` and cached raw public
replays under `build/challenge-training/raw`:

```sh
BattleEngine/runtime/node scripts/challenge/prepare-training.cjs
build/challenge-training/venv/bin/python scripts/challenge/train-policy.py --warm-start BattleEngine/challenge-policy-v1.json --prior-strength .05 --freeze-prior
cp BattleEngine/challenge-policy.json build/challenge-training/ai-review-warm-candidate.json
build/challenge-training/venv/bin/python scripts/challenge/calibrate-policy.py
BattleEngine/runtime/node scripts/challenge/review-inputs.cjs
npm test --prefix BattleEngine
swift test --arch arm64 --enable-code-coverage --filter 'ChallengePolicyCompatibilityTests|ChallengeLevelTests|ChallengeRunTests'
```

The calibration script records every candidate's development result. Run `rollouts.cjs`
with the saved old/new models and the documented final offsets for the independent audit;
`report-input-review.py` gathers the named review outputs and evaluates actual selected
weights against the game-held-out replay partition. No network access is used for inference.
