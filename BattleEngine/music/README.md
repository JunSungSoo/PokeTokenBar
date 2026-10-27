# Gold / Silver wild Pokémon battle BGM

The battle window uses **Battle! Wild Pokémon (Johto) (Day)** from the Gold/Silver/Crystal game-music archive, not a cover or our former score synthesizer.

- Archive: https://www.enls.eu/prelooped/album/?game=GSC (track GSC 010).
- Recording: https://www.enls.eu/prelooped/downloads/GSC/GSC%20010%20Battle%21%20Wild%20Pok%C3%A9mon%20%28Johto%29%20%28Day%29.ogg
- Cross-reference: https://www.zophar.net/music/gameboy-gbs/pokemon-gold (track 41, Battle vs Wild Pokemon).
- The archive identifies the game as Gold & Silver + Crystal (1999, Nintendo). Composition/game audio remain the property of their respective rights holders; archive availability is not a redistribution license.

The archived Vorbis file includes `LOOPSTART=1038645` and `LOOPLENGTH=1612668`, at 44,100 Hz stereo. `GoldSilverWildBattleIntro.wav` preserves frames 0–1038644 (23.552041 seconds); `GoldSilverWildBattleLoop.wav` preserves the following 1612668 frames (36.568435 seconds). Both are decoded PCM16. No synthesis, resampling, normalization, fades or musical edits are applied. The archive file is already a lossy recording; PCM conversion does not turn it into a lossless source capture.

`BattleMusicPlayer` schedules the intro once followed by the loop buffer on one `AVAudioPlayerNode`. Only the second buffer loops, maintaining the archived sample boundary without an app timer or a new player at the join. Battle playback requires no network. Muting, surrender, draw/interruption results, closing the window and disconnect stop both the node and audio engine.

Source and asset hashes are recorded in `wild-battle-source.json`. To reproduce, install `soundfile==0.13.1` in a temporary Python environment, then run `python3 scripts/import-battle-music.py <source.ogg>` or use `--download`. The importer rejects a different source hash. Normal builds copy the checked-in WAVs and provenance; no audio download or Python decoder is required.

## Trainer victory

Winning switches to **GSC 019 Victory! (Trainer)** from the same archive after the final action presentation completes. The original intro plays once and the archived loop repeats until the result window closes. The existing BGM volume and mute settings apply.

- Source: https://www.enls.eu/prelooped/downloads/GSC/GSC%20019%20Victory%21%20%28Trainer%29.ogg
- `LOOPSTART=444950`, `LOOPLENGTH=531648`, 44,100 Hz stereo PCM16.
- Provenance: `trainer-victory-source.json`.
- Reproduce: `python3 scripts/import-victory-music.py <source.ogg|--download>` with `soundfile==0.13.1`.

## Defeat fanfare

A local defeat plays **025 - Player Lost Fanfare** from **Pokémon Battle Revolution** once after the final presentation, then stops. It shares the BGM volume/mute control. Closing the result window stops it immediately; later presentation callbacks do not replay it.

- Archive: https://www.zophar.net/music/nintendo-wii/pokemon-battle-revolution
- Recording: https://fi.zophar.net/soundfiles/nintendo-wii/pokemon-battle-revolution/025%20-%20Player%20Lost%20Fanfare.mp3
- `BattleRevolutionPlayerLost.wav`: 138240 frames, 32,000 Hz stereo PCM16 (4.32 seconds).
- Provenance: `player-lost-source.json`.
- Reproduce: `python3 scripts/import-defeat-music.py <source.mp3|--download>` with `soundfile==0.13.1`. The archived MP3 is decoded without musical edits or resampling; it is not a lossless source capture.
