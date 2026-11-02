#!/usr/bin/env python3
"""Decode the user-provided champion OGG without trimming or changing playback rate."""
import hashlib,json,pathlib,sys
import soundfile as sf
root=pathlib.Path(__file__).resolve().parents[1]
source=pathlib.Path(sys.argv[1] if len(sys.argv)>1 else root/'BattleEngine/music/RubySapphireChampionVictory.ogg')
data,rate=sf.read(source,dtype='int16',always_2d=True)
out=root/'BattleEngine/RubySapphireChampionVictory.wav';sf.write(out,data,rate,subtype='PCM_16')
metadata={'source':'User-provided /tmp/RubySapphireChampionVictory.ogg','sourceSHA256':hashlib.sha256(source.read_bytes()).hexdigest(),'pcmSHA256':hashlib.sha256(data.tobytes()).hexdigest(),'wavSHA256':hashlib.sha256(out.read_bytes()).hexdigest(),'sampleRate':rate,'channels':data.shape[1],'frames':len(data),'playback':'entire original track, repeated without rate or trim changes'}
(root/'BattleEngine/music/champion-victory-source.json').write_text(json.dumps(metadata,indent=2)+'\n')
print(metadata)
