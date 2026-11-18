#!/bin/bash
# Build, sign and publish an in-app update to the fork's GitHub Releases.
# Usage: scripts/publish-github-update.sh <version> [notes-file]   (PTB_DRY_RUN=1 builds and signs only)
set -euo pipefail
cd "$(dirname "$0")/.."

REPO="JunSungSoo/PokeTokenBar"
VERSION="${1:-}"
NOTES="${2:-}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Usage: $0 <MAJOR.MINOR.PATCH> [notes-file]" >&2; exit 1; }
BUILD_VERSION=$(sed -n 's/^VERSION="\(.*\)"$/\1/p' scripts/build-app.sh)
[[ "$VERSION" == "$BUILD_VERSION" ]] || { echo "✗ scripts/build-app.sh 의 VERSION($BUILD_VERSION)과 다릅니다." >&2; exit 1; }
[[ -z "$NOTES" || -f "$NOTES" ]] || { echo "✗ 노트 파일이 없습니다: $NOTES" >&2; exit 1; }

# Installed apps trust only the key compiled into GitHubReleaseSource.
APP_KEY=$(sed -n 's/.*publicKey = Data(base64Encoded: "\([^"]*\)").*/\1/p' Sources/PokeTokenBar/Core/Update/GitHubReleaseSource.swift)
SIGNING_KEY=$(scripts/update-signing-key.sh public)
[[ -n "$APP_KEY" && "$APP_KEY" == "$SIGNING_KEY" ]] || { echo "✗ 키체인 서명 키가 앱에 들어 있는 공개 키와 다릅니다." >&2; exit 1; }

if [[ "${PTB_DRY_RUN:-0}" != "1" ]]; then
    # Untracked sources would be built into the release without being in the tagged commit.
    [[ -z "$(git status --porcelain --untracked-files=normal -- . ':!default.profraw' ':!build')" ]] \
        || { echo "✗ 커밋하지 않은 변경(미추적 파일 포함)이 있습니다." >&2; exit 1; }
    HEAD_SHA=$(git rev-parse HEAD)
    git fetch -q origin
    git branch -r --contains "$HEAD_SHA" | grep -q "origin/" || { echo "✗ HEAD 를 먼저 origin 에 푸시하세요." >&2; exit 1; }
    if gh release view "v$VERSION" -R "$REPO" >/dev/null 2>&1; then
        echo "✗ v$VERSION 릴리스가 이미 있습니다." >&2; exit 1
    fi
fi

echo "==> universal 앱 빌드"
PTB_SKIP_INSTALL=1 bash scripts/build-app.sh
lipo build/PokeTokenBar.app/Contents/MacOS/PokeTokenBar -verify_arch arm64 x86_64
codesign --verify --deep --strict build/PokeTokenBar.app
APP_VERSION=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" build/PokeTokenBar.app/Contents/Info.plist)
[[ "$APP_VERSION" == "$VERSION" ]] || { echo "✗ 빌드된 앱 버전 $APP_VERSION" >&2; exit 1; }

OUT="build/github-update/$VERSION"
rm -rf "$OUT"; mkdir -p "$OUT"
ZIP="$OUT/PokeTokenBar-$VERSION.zip"
MANIFEST="$OUT/PokeTokenBar-update.json"
ditto -c -k --keepParent build/PokeTokenBar.app "$ZIP"
SIZE=$(stat -f %z "$ZIP")
SHA=$(shasum -a 256 "$ZIP" | awk '{print $1}')
printf '{"asset":"PokeTokenBar-%s.zip","sha256":"%s","size":%s,"version":"%s"}' "$VERSION" "$SHA" "$SIZE" "$VERSION" > "$MANIFEST"
scripts/update-signing-key.sh sign "$MANIFEST" > "$MANIFEST.sig"
xcrun swift scripts/update-signing.swift verify "$APP_KEY" "$MANIFEST" "$MANIFEST.sig"
echo "==> $ZIP ($SIZE bytes, sha256 $SHA)"

if [[ "${PTB_DRY_RUN:-0}" == "1" ]]; then
    echo "PTB_DRY_RUN=1 — 업로드하지 않았습니다: $OUT"
    exit 0
fi
NOTE_ARGS=(--notes "PokeTokenBar v$VERSION")
[[ -n "$NOTES" ]] && NOTE_ARGS=(--notes-file "$NOTES")
gh release create "v$VERSION" -R "$REPO" --target "$HEAD_SHA" --title "PokeTokenBar v$VERSION" \
    "${NOTE_ARGS[@]}" "$ZIP" "$MANIFEST" "$MANIFEST.sig"
echo "==> https://github.com/$REPO/releases/tag/v$VERSION"
