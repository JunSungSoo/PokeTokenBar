#!/usr/bin/env python3
"""Decode the pinned Battle Revolution defeat fanfare. Requires soundfile==0.13.1."""
import hashlib
import io
import json
from pathlib import Path
import sys
import urllib.request
import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
URL = 'https://fi.zophar.net/soundfiles/nintendo-wii/pokemon-battle-revolution/025%20-%20Player%20Lost%20Fanfare.mp3'
SHA256 = '2b45a56a5952fbf28fcce6e4ffaf03330a83f415cc0a4a3c570e9274ca30f12b'

def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: import-defeat-music.py <source.mp3|--download>')
    if sys.argv[1] == '--download':
        with urllib.request.urlopen(URL, timeout=45) as response:
            data = response.read()
    else:
        data = Path(sys.argv[1]).read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit('Source hash differs from the verified archive recording')
    samples, rate = sf.read(io.BytesIO(data), dtype='int16', always_2d=True)
    target = ROOT / 'BattleEngine/BattleRevolutionPlayerLost.wav'
    sf.write(target, samples, rate, subtype='PCM_16')
    provenance = {'track': '025 - Player Lost Fanfare', 'game': 'Pokémon Battle Revolution',
        'sourcePage': 'https://www.zophar.net/music/nintendo-wii/pokemon-battle-revolution',
        'sourceURL': URL, 'sourceSHA256': SHA256,
        'sampleRate': rate, 'channels': samples.shape[1], 'frames': len(samples),
        'playback': 'Once; no loop',
        'conversion': 'MP3 decode to PCM16; no resynthesis, resampling, fades or normalization',
        'file': target.name, 'sha256': hashlib.sha256(target.read_bytes()).hexdigest()}
    (ROOT / 'BattleEngine/music/player-lost-source.json').write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(provenance, indent=2, ensure_ascii=False))

if __name__ == '__main__':
    main()
