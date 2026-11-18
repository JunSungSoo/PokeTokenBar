#!/bin/bash
# Manage the Ed25519 key that signs GitHub update manifests (login keychain).
# Losing this key stops installed apps from accepting future updates — keep a backup.
# Usage: scripts/update-signing-key.sh init | public | export | sign <file>
set -euo pipefail
cd "$(dirname "$0")/.."

SERVICE="PokeTokenBar Update Signing Key"
ACCOUNT="poketokenbar-update"
TOOL="scripts/update-signing.swift"

read_key() {
    security find-generic-password -a "$ACCOUNT" -s "$SERVICE" -w 2>/dev/null \
        || { echo "✗ 서명 키가 키체인에 없습니다. 먼저 'init' 을 실행하세요." >&2; exit 1; }
}

case "${1:-}" in
init)
    if security find-generic-password -a "$ACCOUNT" -s "$SERVICE" >/dev/null 2>&1; then
        echo "✗ 서명 키가 이미 있습니다. 덮어쓰면 설치된 앱이 업데이트를 받지 못합니다." >&2
        exit 1
    fi
    KEYS=$(xcrun swift "$TOOL" new-key)
    PRIVATE=$(printf '%s\n' "$KEYS" | sed -n 1p)
    PUBLIC=$(printf '%s\n' "$KEYS" | sed -n 2p)
    # `security -i` reads the command from stdin so the key never appears in the process list.
    printf 'add-generic-password -a "%s" -s "%s" -T /usr/bin/security -w "%s"\n' "$ACCOUNT" "$SERVICE" "$PRIVATE" | security -i
    unset PRIVATE KEYS
    echo "공개 키(앱의 GitHubReleaseSource.publicKey 에 넣는다): $PUBLIC"
    echo "백업: scripts/update-signing-key.sh export 출력값을 안전한 곳(비밀번호 관리자 등)에 보관하세요."
    ;;
public)
    read_key | xcrun swift "$TOOL" public-key
    ;;
export)
    echo "⚠️  아래 값은 개인 키입니다. 저장소·채팅·클라우드 메모에 붙여넣지 마세요." >&2
    read_key
    ;;
sign)
    [[ $# -eq 2 ]] || { echo "Usage: $0 sign <file>" >&2; exit 1; }
    read_key | xcrun swift "$TOOL" sign "$2"
    ;;
*)
    echo "Usage: $0 init | public | export | sign <file>" >&2
    exit 1
    ;;
esac
