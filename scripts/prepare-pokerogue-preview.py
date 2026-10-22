#!/usr/bin/env python3
"""Copy only the 48 audited non-particle previews from a pinned external asset checkout."""
import hashlib,json,pathlib,shutil,subprocess,sys
root=pathlib.Path(__file__).resolve().parent.parent
source=pathlib.Path(sys.argv[1]);pin='009cac30c39d3615c7b2c320c3984af368871031'
assert subprocess.check_output(['git','-C',str(source),'rev-parse','HEAD'],text=True).strip()==pin
report=json.loads(subprocess.check_output([sys.executable,str(root/'scripts/audit-pokerogue-effects.py'),str(source),'--output','/tmp/ptb-pokerogue-preview-audit.json'],text=True))
audit=json.loads(pathlib.Path('/tmp/ptb-pokerogue-preview-audit.json').read_text())
out=root/'Tests/PokeTokenBarTests/Fixtures/PokeRoguePreview';out.mkdir(parents=True,exist_ok=True)
rows=[r for r in audit['rows'] if r['classification']!='effect-graphics']
assert len(rows)==48
paths={r['path'] for r in rows}
paths|={'images/battle_anims/'+g+'.png' for r in rows for g in r['backgrounds']}
paths|={'REUSE.toml','battle-anims/REUSE.toml','images/REUSE.toml','README.md','LICENSES/LicenseRef-POKEMON-REBORN.txt','LICENSES/AGPL-3.0-only.txt','LICENSES/CC-BY-NC-SA-4.0.txt'}
hashes={}
for p in sorted(paths):
 data=(source/p).read_bytes();dest=out/p;dest.parent.mkdir(parents=True,exist_ok=True);dest.write_bytes(data);hashes[p]=hashlib.sha256(data).hexdigest()
(out/'manifest.json').write_text(json.dumps({'repository':'https://github.com/pagefaultgames/pokerogue-assets','revision':pin,'moves':rows,'sha256':hashes},indent=2)+'\n')
(out/'NOTICE.md').write_text('''# PokéRogue development preview fixtures

Pinned original JSON and background PNG files from pagefaultgames/pokerogue-assets.
Revision: 009cac30c39d3615c7b2c320c3984af368871031.
Only 15 background, 30 motion and 3 empty definitions are included, for a development comparison.
Original files are unchanged and SHA-256 hashes are recorded in manifest.json.
Root and directory REUSE.toml files, the original README and relevant license texts are retained.
JSON declarations include AGPL-3.0-only and Pokémon Reborn/Gen8 source metadata; graphical
assets retain their source notices and the README's default CC-BY-NC-SA-4.0 terms where applicable.
This is not a blanket CC0 or MIT asset pack. Original authors and attribution details remain in
the retained notices. The preview adapter is independently implemented and does not embed Phaser.
No sound assets or replacement Pokémon sprites are included. Normal battles do not use these fixtures.
''')
print('Prepared',len(rows),'moves and',len(paths),'source files')
