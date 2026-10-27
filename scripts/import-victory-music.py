#!/usr/bin/env python3
"""Decode the pinned archived GSC trainer-victory recording without resynthesis or resampling.

Requires soundfile==0.13.1. Pass an existing OGG path, or --download.
Normal app builds use the checked-in PCM assets and do not run this utility.
"""
import hashlib
import io
import json
from pathlib import Path
import struct
import sys
import urllib.request

import soundfile as sf

ROOT = Path(__file__).resolve().parent.parent
PAGE = 'https://www.enls.eu/prelooped/album/?game=GSC'
URL = 'https://www.enls.eu/prelooped/downloads/GSC/GSC%20019%20Victory%21%20%28Trainer%29.ogg'
SHA256 = '130d7f6503edcfc41dd468dddeca5926ba909878ccad43cd49a3b0e4e31b714e'

def main():
    if len(sys.argv) != 2:
        raise SystemExit('Usage: import-victory-music.py <source.ogg|--download>')
    if sys.argv[1] == '--download':
        with urllib.request.urlopen(URL, timeout=45) as response:
            data = response.read()
    else:
        data = Path(sys.argv[1]).read_bytes()
    if hashlib.sha256(data).hexdigest() != SHA256:
        raise SystemExit('Source hash differs from the verified archived recording')
    offset = data.index(b'\x03vorbis') + 7
    length = struct.unpack_from('<I', data, offset)[0]
    offset += 4 + length
    count = struct.unpack_from('<I', data, offset)[0]
    offset += 4
    tags = {}
    for _ in range(count):
        length = struct.unpack_from('<I', data, offset)[0]
        offset += 4
        key, value = data[offset:offset + length].decode('utf-8').split('=', 1)
        tags[key.upper()] = value
        offset += length
    start, length = int(tags['LOOPSTART']), int(tags['LOOPLENGTH'])
    samples, rate = sf.read(io.BytesIO(data), dtype='int16', always_2d=True)
    if not (0 < start < start + length <= len(samples)):
        raise SystemExit('Invalid source loop metadata')
    assets = ROOT / 'BattleEngine'
    files = {}
    for name, frames in [('GoldSilverTrainerVictoryIntro.wav', samples[:start]),
                         ('GoldSilverTrainerVictoryLoop.wav', samples[start:start + length])]:
        path = assets / name
        sf.write(path, frames, rate, subtype='PCM_16')
        files[name] = {'frames': len(frames), 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}
    provenance = {'track': 'GSC 019 Victory! (Trainer)',
                  'sourcePage': PAGE, 'sourceURL': URL, 'sourceSHA256': SHA256,
                  'sampleRate': rate, 'channels': samples.shape[1],
                  'loopStartFrame': start, 'loopFrameCount': length,
                  'conversion': 'Vorbis decode to PCM16; no resynthesis, resampling, fades or normalization',
                  'files': files}
    (assets / 'music/trainer-victory-source.json').write_text(json.dumps(provenance, indent=2, ensure_ascii=False) + '\n')
    print(json.dumps(provenance, ensure_ascii=False, indent=2))

if __name__ == '__main__':
    main()
