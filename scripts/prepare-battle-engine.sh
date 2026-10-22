#!/bin/bash
# Reproduce the offline battle helper. No changes to an installed app.
set -euo pipefail
cd "$(dirname "$0")/.."
npm ci --prefix BattleEngine --ignore-scripts --omit=optional --no-audit
VERSION=22.18.0
ROOT="$PWD/BattleEngine/runtime"
mkdir -p "$ROOT"
if [[ ! -x "$ROOT/node" ]]; then
    curl -fsSL "https://nodejs.org/dist/v$VERSION/SHASUMS256.txt" -o "$ROOT/SHASUMS256.txt"
    for ARCH in arm64 x64; do
        FILE="node-v$VERSION-darwin-$ARCH.tar.gz"
        curl -fsSL "https://nodejs.org/dist/v$VERSION/$FILE" -o "$ROOT/$FILE"
        (cd "$ROOT"; awk -v file="$FILE" '$2 == file' SHASUMS256.txt | shasum -a 256 -c -)
        tar -xzf "$ROOT/$FILE" -C "$ROOT"
    done
    lipo -create "$ROOT/node-v$VERSION-darwin-arm64/bin/node" "$ROOT/node-v$VERSION-darwin-x64/bin/node" -output "$ROOT/node"
    chmod +x "$ROOT/node"
    codesign --force -s - "$ROOT/node"
fi
lipo "$ROOT/node" -verify_arch arm64 x86_64
node --test BattleEngine/tests/*.test.cjs
