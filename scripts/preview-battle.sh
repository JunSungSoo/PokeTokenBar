#!/usr/bin/env bash
# Native macOS battle sandbox. Keeps input/audio on a real NSApplication event loop.
set -euo pipefail
cd "$(dirname "$0")/.."
swift build --arch arm64 --build-tests
PREVIEW_APP="$PWD/build/PokeTokenBarBattlePreview.app"
if [[ "${PTB_MEGA_DESIGN_PREVIEW:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarMegaPreview.app"
elif [[ "${PTB_SIZE_PREVIEW:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        PREVIEW_APP="$PWD/build/PokeTokenBarSizeDoublePreview.app"
    else
        PREVIEW_APP="$PWD/build/PokeTokenBarSizePreview.app"
    fi
elif [[ "${PTB_ENTRY_PREVIEW:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        PREVIEW_APP="$PWD/build/PokeTokenBarEntryDoublePreview.app"
    else
        PREVIEW_APP="$PWD/build/PokeTokenBarEntryPreview.app"
    fi
elif [[ "${PTB_FIELD_EFFECTS_PILOT:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarFieldPreview.app"
elif [[ "${PTB_FAITHFUL_PIKACHU:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarPokeRoguePreview.app"
elif [[ "${PTB_ITEM_PREVIEW:-0}" == "1" || "${PTB_ROSTER_PREVIEW:-0}" == "1" || "${PTB_LOBBY_PREVIEW:-0}" == "1" || "${PTB_MATCHMAKING_PREVIEW:-0}" == "1" || "${PTB_MATCHING_DUEL:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarLobbyPreview.app"
elif [[ "${PTB_LOADOUT_PREVIEW:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarLoadoutPreview.app"
elif [[ "${PTB_ABILITY_BATTLE:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarAbilityPreview.app"
elif [[ "${PTB_POKEROGUE_PREVIEW:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarPokeRoguePreview.app"
elif [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
    PREVIEW_APP="$PWD/build/PokeTokenBarBattleDoublePreview.app"
fi
mkdir -p "$PREVIEW_APP/Contents/MacOS"
mkdir -p "$PREVIEW_APP/Contents/Resources"
ditto Sources/PokeTokenBar/Resources/BattleText "$PREVIEW_APP/Contents/Resources/BattleText"
ditto Sources/PokeTokenBar/Resources/BattleEffects "$PREVIEW_APP/Contents/Resources/BattleEffects"
ditto Sources/PokeTokenBar/Resources/Showmotion "$PREVIEW_APP/Contents/Resources/Showmotion"
ditto Sources/PokeTokenBar/Resources/PokeRogue "$PREVIEW_APP/Contents/Resources/PokeRogue"
ditto Sources/PokeTokenBar/Resources/PokeRoguePlayer "$PREVIEW_APP/Contents/Resources/PokeRoguePlayer"
ditto Tests/PokeTokenBarTests/Fixtures/PokeRogueFaithful "$PREVIEW_APP/Contents/Resources/PokeRogueFaithful"
ditto Tests/PokeTokenBarTests/Fixtures/PokeRoguePreview "$PREVIEW_APP/Contents/Resources/PokeRoguePreview"
if [[ "${PTB_SIZE_PREVIEW:-0}" == "1" ]]; then
    python3 - "$PREVIEW_APP" <<'GIFS'
import concurrent.futures,pathlib,sys,urllib.request
folder=pathlib.Path(sys.argv[1])/'Contents/Resources/PokeRogueSizeGIFs';folder.mkdir(exist_ok=True)
def fetch(item):
    ident,back,shiny=item;name=('back-' if back else '')+str(ident)+('-sha.gif' if shiny else '-a.gif');target=folder/name
    if not target.exists():
        url='https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white/animated/'+('back/' if back else '')+('shiny/' if shiny else '')+str(ident)+'.gif'
        target.write_bytes(urllib.request.urlopen(url,timeout=30).read())
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:list(pool.map(fetch,[(id,back,shiny) for id in [25,143,321,384] for back in [False,True] for shiny in ([False,True] if id==25 else [False])]))
GIFS
fi
python3 - "$PREVIEW_APP" <<'PY'
import pathlib, plistlib, sys
app = pathlib.Path(sys.argv[1])
(app/'Contents/Info.plist').write_bytes(plistlib.dumps({
    'CFBundleIdentifier':'dev.poketokenbar.megapreview' if 'MegaPreview' in app.name else 'dev.poketokenbar.sizedoublepreview' if 'SizeDoublePreview' in app.name else 'dev.poketokenbar.sizepreview' if 'SizePreview' in app.name else 'dev.poketokenbar.entrydoublepreview' if 'EntryDoublePreview' in app.name else 'dev.poketokenbar.entrypreview' if 'EntryPreview' in app.name else 'dev.poketokenbar.fieldpreview' if 'FieldPreview' in app.name else 'dev.poketokenbar.lobbypreview' if 'LobbyPreview' in app.name else 'dev.poketokenbar.loadoutpreview' if 'LoadoutPreview' in app.name else 'dev.poketokenbar.abilitypreview' if 'AbilityPreview' in app.name else 'dev.poketokenbar.pokeroguepreview' if 'PokeRoguePreview' in app.name else 'dev.poketokenbar.battledoublepreview' if 'DoublePreview' in app.name else 'dev.poketokenbar.battlepreview',
    'CFBundleExecutable':'PTBBattlePreview',
    'CFBundleName':'PokeTokenBar Battle Preview',
    'CFBundlePackageType':'APPL', 'LSUIElement':False,
}))
PY
# Link the actual application objects, retaining their production UI/engine/resources.
# The sandbox entry point replaces the SwiftUI app entry point only in this development app.
swiftc -parse-as-library -target arm64-apple-macos14.0 \
    -I .build/arm64-apple-macosx/debug/Modules scripts/BattlePreview.swift scripts/PikachuEffectComparison.swift scripts/PokeRogueEffectComparison.swift scripts/PokemonSizeComparison.swift \
    @.build/arm64-apple-macosx/debug/PokeTokenBar.product/Objects.LinkFileList \
    -lsqlite3 -Xlinker -e -Xlinker _previewmain \
    -o "$PREVIEW_APP/Contents/MacOS/PTBBattlePreview"
codesign --force --sign - "$PREVIEW_APP"
if [[ "${PTB_MEGA_DESIGN_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --mega-design-preview
elif [[ "${PTB_SIZE_PREVIEW:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        open -n "$PREVIEW_APP" --args --size-preview --doubles
    else
        open -n "$PREVIEW_APP" --args --size-preview ${PTB_BACKGROUND_PREVIEW:+--background-preview} ${PTB_STATUS_PREVIEW:+--status-preview} ${PTB_CRY_PREVIEW:+--cry-preview}
    fi
elif [[ "${PTB_ENTRY_PREVIEW:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        open -n "$PREVIEW_APP" --args --rogue-battle --entry-demo --doubles
    else
        open -n "$PREVIEW_APP" --args --rogue-battle --entry-demo
    fi
elif [[ "${PTB_FIELD_EFFECTS_PILOT:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --rogue-battle --field-effects-pilot
elif [[ "${PTB_FAITHFUL_PIKACHU:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --faithful-pikachu
elif [[ "${PTB_MATCHING_DUEL:-0}" == "1" ]]; then
    if [[ "${PTB_MEGA_TEST:-0}" == "1" ]]; then
        BattleEngine/runtime/node scripts/prepare-codex-duel.cjs --mega-test
        open -n "$PREVIEW_APP" --args --matching-duel --mega-test
    else
        BattleEngine/runtime/node scripts/prepare-codex-duel.cjs
        open -n "$PREVIEW_APP" --args --matching-duel
    fi
elif [[ "${PTB_MATCHMAKING_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --matchmaking
elif [[ "${PTB_ROSTER_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --roster-preview
elif [[ "${PTB_ITEM_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --item-preview
elif [[ "${PTB_LOBBY_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --lobby
elif [[ "${PTB_LOADOUT_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --loadout
elif [[ "${PTB_NOTICE_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --rogue-battle --abilities --notices-demo
elif [[ "${PTB_ABILITY_BATTLE:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --rogue-battle --abilities
elif [[ "${PTB_POKEROGUE_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --pokerogue --move "${PTB_POKEROGUE_MOVE:-surf}"
elif [[ "${PTB_CODEX_DUEL:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --versus-codex
elif [[ "${PTB_NARROW_BATTLE_PREVIEW:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        open -n "$PREVIEW_APP" --args --rogue-battle --narrow-preview --doubles
    else
        open -n "$PREVIEW_APP" --args --rogue-battle --narrow-preview
    fi
elif [[ "${PTB_FIELD_BATTLE:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --rogue-battle --fields --doubles
elif [[ "${PTB_HP_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --rogue-battle --hp-preview
elif [[ "${PTB_ROGUE_BATTLE:-0}" == "1" ]]; then
    if [[ "${PTB_BATTLE_DOUBLES:-0}" == "1" ]]; then
        open -n "$PREVIEW_APP" --args --rogue-battle --doubles
    else
        open -n "$PREVIEW_APP" --args --rogue-battle
    fi
elif [[ "${PTB_PIKACHU_COMPARE:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --compare-pikachu
elif [[ "${PTB_SHOWMOTION_PREVIEW:-0}" == "1" ]]; then
    open -n "$PREVIEW_APP" --args --showmotion
else
    open -n "$PREVIEW_APP"
fi
