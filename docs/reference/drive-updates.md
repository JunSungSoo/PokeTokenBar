# Drive version updates

The current app version is 3.1.0. `scripts/build-app.sh` writes that version into both
`CFBundleShortVersionString` and `CFBundleVersion`; the QA builder uses the same short version.
Every subsequent Drive distribution must raise the app version and ZIP filename version.

The existing Home update banner and Settings check now use only this fixed public share:
https://drive.google.com/file/d/1NYVOMV8fMqf-UGM-dIfKZ3wKV4PtITrN/view

The GitHub latest-release request and automatic Homebrew upgrade/termination paths have been
removed. The old GitHub skip preference is not reused. A valid newer Drive version uses the
existing localized notice and Update button. The button opens the fixed share in the default
external browser; it does not download/install silently or stop the running app.

Supported filenames include:

- `PokeTokenBar-3.0.1.zip`
- `PokeTokenBar-3.0.1-261102(1).zip`
- `PokeTokenBar-3.0.1-arm64-20261102-update.zip`

Only the three numeric version components decide whether an update is available. Date/round
changes within 3.0.0 do not notify. Installing 3.0.1 hides a 3.0.1 offer; an older 2.5.6 file
never prompts a 3.0.0 installation to downgrade. Prereleases/unrecognized filenames, login
pages and failed metadata requests do not produce an offer or start the successful-check
cooldown. App startup, opening Home and returning to Home check with a 30-minute successful
lookup cooldown; overlapping checks share one in-flight request. Settings can force a check.

Fetching uses an ephemeral session and reads at most 1 MiB of public HTML metadata, never
the ZIP content. No Drive API key or user credentials are embedded. Drive HTML layout changes
may require updating the title parser; malformed responses fail without replacing an offer.

ZIP packaging retains the app's embedded version unchanged and records it in Release
Metadata.json. `scripts/package-zip.py` rejects a recognizable PokeTokenBar ZIP filename whose
version differs from the app version. The former date/round stamping proposal was superseded
by the user's explicit switch to version-based updates; no deployment counter is maintained.
ZIP creation does not add a release-note entry unless explicitly requested.

Validation: 22 native checker/parser/production-Home tests pass, including the opt-in live
Drive fetch; 8 packaging tests pass. Removing the filename end anchor fails the disguised
non-ZIP regression, restored before the final native run. Source regions are inspected in
`/tmp/ptb-drive-version-regions.txt`; network error branches are not exhaustively simulated.
All 145 engine tests also pass during the 3.0.0 ARM64 release build. The actual signed 3.0.0
app is packaged into a temporary validation ZIP; Info.plist, Release Metadata.json, archive
filename and executable match, while existing release-note bytes and the source app remain
unchanged (`/tmp/ptb-drive-3-package-validation.json`). No new release-note entry is added.


## November 2 fifth ZIP release

The user requested release notes and a Desktop distribution. The existing four release-note
entries are preserved, with the fifth prepended. Final validation: 22 native tests with live
Drive lookup, 8 packaging tests, 145 engine tests, ARM64 signatures, 4,356 resource matches,
audio hashes and a real packaged-engine turn. Test controls are absent from the release app.

Archive: `PokeTokenBar-3.0.0-261102(5).zip`, packaged `2026-11-02T17:43:30+09:00`.
SHA-256: `c90147e6135eaa6538c2e68ee13e79dff58b9973afe97f6767b4fa5d905e153a`. Both app version fields and ZIP metadata are 3.0.0;
the complete five-entry November 2 history and executable match the verified source bundle.


## Published Drive 3.0.0 verification

After the user replaced the shared file, a read-only request returned HTTP 200 and the title
`PokeTokenBar-3.0.0.zip - Google Drive`. The app's actual URLSession fetch likewise returns
3.0.0. With `PTB_DRIVE_LIVE_PROBE=1 PTB_DRIVE_EXPECTED_VERSION=3.0.0`, all 23 native tests
pass (`/tmp/ptb-drive-published-3-verification.log`). The published response is fed into the
real checker and production Home renderer: an older-version fixture offers 3.0.0, current
3.0.0 and newer 3.0.1 installations do not offer it, and the update action requests exactly
the pinned Drive share URL without clearing the notice before installation. The callback
is captured in the test; no browser window is opened or ZIP downloaded by this verification.
The production-render screenshot is `/tmp/ptb-drive-live-3-notice.png`. No runtime fix or
new release package is needed; only repeatable live-response verification was added.


## Actual browser handoff verification (November 3)

A separate visible preview assumes installed version 2.5.6 and uses the production banner,
DriveReleaseSource and UpdateChecker, including its default NSWorkspace browser opener.
The preview uses its own defaults suite, separate from both the production app and its own
bundle identifier. The live response displayed “v3.0.0 사용 가능 (현재 2.5.6)”. Clicking the
visible Update button with native UI automation opened a new Google Chrome tab at the pinned
Drive file URL. Chrome showed `PokeTokenBar-3.0.0.zip - Google Drive`, the matching file ID
and a Download button. The ZIP was not downloaded or installed. Both the preview and Drive
tab remain open for inspection; production app data and release notes are unchanged.


## November 3 local 3.0.1 distribution

The user explicitly raised the app version to 3.0.1 after the initial local candidate was
assembled and before any commit/push. The old 3.0.0 candidate was moved off Desktop into
an ignored build backup and is not a separate release. Both release app version fields,
the QA short version, archive filename and package metadata are now 3.0.1. This ZIP has
not been uploaded to Drive by the agent. Existing comparator tests cover 3.0.0 seeing a
3.0.1 offer and 3.0.1 suppressing that same offer. The shared file must be replaced with
the 3.0.1-named ZIP before installed older apps can discover this distribution.

Release checks: 152 engine tests, 104 native tests (2 opt-in network probes skipped, zero
failures), 8 package tests, ARM64 app/helper signatures, 4,356 exact resource matches and
actual bundled-engine checks for all 27 teams/162 NPCs plus an automatic recovery turn.
Package verification independently opens the archive and checks version 3.0.1, executable
SHA-256, exact catalog and release-note bytes. Trainer-specific finale details are removed
from the release-note text at the user's request; gameplay and internal technical reference
documents remain complete. Final artifact hashes are recorded in the ZIP release ledger.
