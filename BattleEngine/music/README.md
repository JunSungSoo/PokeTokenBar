# Gold / Silver wild Pokémon battle BGM

The battle window uses **Battle! Wild Pokémon (Johto) (Day)** from the Gold/Silver/Crystal game-music archive, not a cover or our former score synthesizer.

- Archive: https://www.enls.eu/prelooped/album/?game=GSC (track GSC 010).
- Recording: https://www.enls.eu/prelooped/downloads/GSC/GSC%20010%20Battle%21%20Wild%20Pok%C3%A9mon%20%28Johto%29%20%28Day%29.ogg
- Cross-reference: https://www.zophar.net/music/gameboy-gbs/pokemon-gold (track 41, Battle vs Wild Pokemon).
- The archive identifies the game as Gold & Silver + Crystal (1999, Nintendo). Composition/game audio remain the property of their respective rights holders; archive availability is not a redistribution license.

The archived Vorbis file includes `LOOPSTART=1038645` and `LOOPLENGTH=1612668`, at 44,100 Hz stereo. `GoldSilverWildBattleIntro.wav` preserves frames 0–1038644 (23.552041 seconds); `GoldSilverWildBattleLoop.wav` preserves the following 1612668 frames (36.568435 seconds). Both are decoded PCM16. No synthesis, resampling, normalization, fades or musical edits are applied. The archive file is already a lossy recording; PCM conversion does not turn it into a lossless source capture.

`BattleMusicPlayer` schedules the intro once followed by the loop buffer on one `AVAudioPlayerNode`. Only the second buffer loops, maintaining the archived sample boundary without an app timer or a new player at the join. Battle playback requires no network. Muting, surrender, results and disconnect stop both the node and audio engine.

Source and asset hashes are recorded in `wild-battle-source.json`. To reproduce, install `soundfile==0.13.1` in a temporary Python environment, then run `python3 scripts/import-battle-music.py <source.ogg>` or use `--download`. The importer rejects a different source hash. Normal builds copy the checked-in WAVs and provenance; no audio download or Python decoder is required.
