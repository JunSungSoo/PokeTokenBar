#!/usr/bin/env python3
"""Import the curated battle arenas from the same pinned PokéRogue asset revision."""
import concurrent.futures
import hashlib
import json
import pathlib
import struct
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/PokeTokenBar/Resources/PokeRoguePlayer"
GROUPS = {
    "woods": ["plains", "forest", "snowy_forest"],
    "water": ["sea", "beach", "lake"],
    "highlands": ["mountain", "desert", "volcano"],
    "caves": ["cave", "ice_cave", "fairy_cave"],
    "settlements": ["town", "metropolis", "dojo"],
}


def main():
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    revision = manifest["assetRevision"]

    def fetch(key):
        name = f"images/arenas/{key}_bg.png"
        # Fetch from the pin even for existing assets; provenance must reflect upstream bytes.
        url = f"https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{revision}/{name}"
        data = urllib.request.urlopen(url, timeout=30).read()
        if data[:8] != b"\x89PNG\r\n\x1a\n" or struct.unpack(">II", data[16:24]) != (320, 180):
            raise ValueError(f"Unexpected original background: {name}")
        return key, name, data

    keys = [key for group in GROUPS.values() for key in group]
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        results = list(pool.map(fetch, keys))
    for key, name, data in results:
        target = OUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest["sha256"][name] = hashlib.sha256(data).hexdigest()
        manifest["originalPaths"][name] = name
    manifest["arenas"] = GROUPS
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")))
    print(f"Imported {len(results)} original arena backgrounds at {revision}")


if __name__ == "__main__":
    main()
