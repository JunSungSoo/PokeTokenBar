#!/usr/bin/env python3
"""Import the curated battle arenas and their platforms from the same pinned PokéRogue asset revision."""
import concurrent.futures
import hashlib
import json
import pathlib
import struct
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parents[1]
OUT = ROOT / "Sources/PokeTokenBar/Resources/PokeRoguePlayer"
GROUPS = {
    "woods": ["plains", "forest", "snowy_forest"],
    "water": ["sea", "beach", "lake"],
    "highlands": ["mountain", "desert", "volcano"],
    "caves": ["cave", "ice_cave", "fairy_cave"],
    "settlements": ["town", "metropolis", "dojo"],
    "special": ["end"],  # Red-only override; never selected by the ordinary type mapping.
}
BACKGROUND_SIZE = (320, 180)
FIELD_SIZE = (320, 132)
PLATFORM_SIDES = ("a", "b")  # a: player platform, b: enemy platform


def main():
    manifest_path = OUT / "manifest.json"
    manifest = json.loads(manifest_path.read_text())
    revision = manifest["assetRevision"]

    def fetch(name):
        # Fetch from the pin even for existing assets; provenance must reflect upstream bytes.
        url = f"https://raw.githubusercontent.com/pagefaultgames/pokerogue-assets/{revision}/{name}"
        try:
            data = urllib.request.urlopen(url, timeout=30).read()
        except urllib.error.HTTPError as error:
            # Only animated platforms ship a frame atlas next to the sheet.
            if error.code == 404 and name.endswith(".json"):
                return name, None
            raise
        if name.endswith(".png") and data[:8] != b"\x89PNG\r\n\x1a\n":
            raise ValueError(f"Unexpected original arena layer: {name}")
        if name.endswith("_bg.png") and struct.unpack(">II", data[16:24]) != BACKGROUND_SIZE:
            raise ValueError(f"Unexpected original background: {name}")
        return name, data

    keys = [key for group in GROUPS.values() for key in group]
    names = [f"images/arenas/{key}_bg.png" for key in keys]
    for key in keys:
        for side in PLATFORM_SIDES:
            names += [f"images/arenas/{key}_{side}.png", f"images/arenas/{key}_{side}.json"]
    with concurrent.futures.ThreadPoolExecutor(max_workers=5) as pool:
        results = [(name, data) for name, data in pool.map(fetch, names) if data is not None]
    atlases = {name for name, _ in results if name.endswith(".json")}
    # Validate everything before the first write so a bad pin never leaves a partial import.
    for name, data in results:
        if name.endswith(("_a.png", "_b.png")) and struct.unpack(">II", data[16:24]) != FIELD_SIZE \
                and (name[:-4] + ".json") not in atlases:
            raise ValueError(f"Platform is neither a field layer nor an atlas: {name}")
    for name, data in results:
        target = OUT / name
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        manifest["sha256"][name] = hashlib.sha256(data).hexdigest()
        manifest["originalPaths"][name] = name
    manifest["arenas"] = GROUPS
    manifest_path.write_text(json.dumps(manifest, separators=(",", ":")))
    print(f"Imported {len(results)} original arena files at {revision}")


if __name__ == "__main__":
    main()
