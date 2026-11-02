#!/usr/bin/env python3
"""Decode the user-provided champion OGG without trimming or changing playback rate."""
import argparse,hashlib,json,pathlib
import soundfile as sf
root=pathlib.Path(__file__).resolve().parents[1]
parser=argparse.ArgumentParser();parser.add_argument('source',nargs='?');parser.add_argument('--battle',action='store_true');args=parser.parse_args()
stem='RubySapphireChampionBattle' if args.battle else 'RubySapphireChampionVictory'
kind='battle' if args.battle else 'victory'
source=pathlib.Path(args.source) if args.source else root/f'BattleEngine/music/{stem}.ogg'
data,rate=sf.read(source,dtype='int16',always_2d=True)
out=root/f'BattleEngine/{stem}.wav';sf.write(out,data,rate,subtype='PCM_16')
metadata={'source':f'User-provided /tmp/{stem}.ogg','sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'pcmSHA256':hashlib.sha256(data.tobytes()).hexdigest(),'wavSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'sampleRate':rate,'channels':data.shape[1],'frames':len(data),'playback':'entire original track, repeated without rate or trim changes'}
(root/f'BattleEngine/music/champion-{kind}-source.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(metadata)
