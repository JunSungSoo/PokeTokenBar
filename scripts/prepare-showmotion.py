#!/usr/bin/env python3
"""Pin original Showmotion assets and generate the minimal native host adapter."""
import concurrent.futures
import hashlib
import json
import pathlib
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1] / 'Sources/PokeTokenBar/Resources/Showmotion'
REVISION = '76aaa0b2ae4f3fbe49a4024ae2b6521038cf6d50'
BASE = f'https://raw.githubusercontent.com/shogun-drei/Showmotion/{REVISION}/'


def main():
    tree = json.load(urllib.request.urlopen(
        f'https://api.github.com/repos/shogun-drei/Showmotion/git/trees/{REVISION}?recursive=1'))['tree']
    entries = [e for e in tree if e['type'] == 'blob' and
               (e['path'].startswith(('libs/runtime/', 'libs/three/', 'libs/utils/', 'libs/wgsl/', 'libs/effects/'))
                or e['path'] in ('engine.js', 'custom-battle-animations.js', 'README.md'))
               and '/land/' not in e['path']]

    def fetch(entry):
        file = ROOT / entry['path']
        if not file.exists():
            file.parent.mkdir(parents=True, exist_ok=True)
            file.write_bytes(urllib.request.urlopen(BASE + entry['path'], timeout=40).read())
        data = file.read_bytes()
        blob = hashlib.sha1(b'blob ' + str(len(data)).encode() + b'\0' + data).hexdigest()
        if blob != entry['sha']:
            raise ValueError(f'Original source changed: {file}')
        return entry['path'], hashlib.sha256(data).hexdigest()

    with concurrent.futures.ThreadPoolExecutor(max_workers=8) as executor:
        hashes = dict(executor.map(fetch, entries))
    source = (ROOT / 'engine.js').read_text()
    patches = [
        ('        foregroundEfkContext = createEfkContext();',
         '        foregroundEfkContext = createEfkContext();\n        globalThis.ptbShowmotion.contexts = [backgroundEfkContext, foregroundEfkContext];'),
        ('                    handle.setRotation(rx, ry, rz);',
         '                    handle.setRotation(rx, ry, rz);\n                    globalThis.ptbShowmotion.handles.push(handle);'),
        ('        lifecycle.timer = timer;',
         '        lifecycle.timer = timer;\n        globalThis.ptbShowmotion.timer = timer;'),
        ('            requestAnimationFrame(animate);',
         '            if (globalThis.ptbShowmotion.paused) { globalThis.ptbShowmotion.resume = () => animate(performance.now()); return; }\n            requestAnimationFrame(animate);'),
        ('        effekseerDisabled = true;\n        stopAllEffects();',
         '        globalThis.ptbPost?.({kind:"error", message:"Effekseer "+scope+": "+String(error)});\n        effekseerDisabled = true;\n        stopAllEffects();'),
        ('rect?.width || battleRoot?.clientWidth', 'battleRoot?.clientWidth || rect?.width'),
        ('rect?.height || battleRoot?.clientHeight', 'battleRoot?.clientHeight || rect?.height'),
    ]
    for before, after in patches:
        if source.count(before) != 1:
            raise ValueError(f'Adapter patch no longer matches: {before}')
        source = source.replace(before, after)
    (ROOT / 'ptb-engine.js').write_text(source)
    (ROOT / 'source-sha256.json').write_text(json.dumps(
        {'repository': 'https://github.com/shogun-drei/Showmotion', 'revision': REVISION,
         'files': dict(sorted(hashes.items())), 'adapter': 'ptb-engine.js'}, indent=2) + '\n')
    print(f'Verified {len(hashes)} pinned original Showmotion files; generated adapter.')


if __name__ == '__main__':
    main()
