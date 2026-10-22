#!/usr/bin/env python3
"""Read-only asset feasibility audit; never imports upstream assets into the application.

Prepare an external checkout with battle-anims and images/battle_anims available, then:
  python3 scripts/audit-pokerogue-effects.py /path/to/pokerogue-assets --output /tmp/audit.json
The checkout's pinned HEAD tree is the dependency-existence source; audio need not be checked out.
"""
import argparse
import collections
import json
import pathlib
import re
import struct
import subprocess

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('assets', type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path, required=True)
args = parser.parse_args()
project = pathlib.Path(__file__).resolve().parent.parent
catalog = json.loads((project/'Sources/PokeTokenBar/Resources/BattleEffects/catalog.json').read_text())
canonical = sorted(set(catalog['aliases'].values()))
def git(*command):
    return subprocess.check_output(['git','-C',str(args.assets),*command],text=True).strip()
revision = git('rev-parse','HEAD')
paths = set(git('ls-tree','-r','--name-only','HEAD').splitlines())
def key(name):
    return re.sub('[^a-z0-9]', '', name.lower())
files = {key(pathlib.PurePosixPath(p).stem):p for p in paths if p.startswith('battle-anims/') and p.endswith('.json')}
rows = []
for move in canonical:
    path = files.get(move)
    if path is None:
        rows.append({'move':move,'classification':'missing-definition'})
        continue
    data = json.loads((args.assets/path).read_text())
    variants = data if isinstance(data,list) else [data]
    effect_entries = frames = 0
    sheets, backgrounds, audio, missing, invalid = set(), set(), set(), set(), set()
    for animation in variants:
        frames += len(animation.get('frames',[]))
        sheet = animation.get('graphic')
        cells = None
        if sheet:
            sheets.add(sheet)
            png = 'images/battle_anims/'+sheet+'.png'
            if png not in paths:
                missing.add(png)
            else:
                header = (args.assets/png).read_bytes()[:24]
                width,height = struct.unpack('>II', header[16:24])
                cells = (width//96)*(height//96)
        for frame in animation.get('frames',[]):
            for entry in frame:
                if not entry or entry.get('target') != 2 or not entry.get('visible',True) or entry.get('opacity',255) <= 0:
                    continue
                effect_entries += 1
                index = entry.get('graphicFrame',0)
                if cells is not None and not 0 <= index < cells:
                    invalid.add((sheet,index,cells))
        for events in animation.get('frameTimedEvents',{}).values():
            for event in events:
                name = event.get('resourceName')
                if not name:
                    continue
                if event.get('eventType') == 'AnimTimedAddBgEvent':
                    backgrounds.add(name)
                    resource = 'images/battle_anims/'+name+'.png'
                elif event.get('eventType') == 'AnimTimedSoundEvent':
                    audio.add(name)
                    resource = 'audio/battle_anims/'+name
                else:
                    continue
                if resource not in paths:
                    missing.add(resource)
    classification = ('empty' if not frames else 'effect-graphics' if effect_entries else
                      'background-without-effect-graphics' if backgrounds else 'motion-without-effect-graphics')
    rows.append(dict(move=move,path=path,classification=classification,variants=len(variants),
                     frames=frames,effectEntries=effect_entries,sheets=sorted(sheets),
                     backgrounds=sorted(backgrounds),audio=sorted(audio),missingResources=sorted(missing),
                     frameIndexWarnings=sorted(invalid)))
report = dict(assetRevision=revision,projectCanonicalMoves=len(canonical),
              counts=dict(collections.Counter(row['classification'] for row in rows)),
              missingResourceMoves=[row['move'] for row in rows if row.get('missingResources')],
              frameIndexWarningMoves=[row['move'] for row in rows if row.get('frameIndexWarnings')],rows=rows)
args.output.write_text(json.dumps(report,indent=2,ensure_ascii=False)+'\n')
print(json.dumps({k:v for k,v in report.items() if k!='rows'},indent=2))
