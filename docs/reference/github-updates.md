---
summary: "앱 내 업데이트 — JunSungSoo 포크 GitHub Releases, Ed25519 서명 매니페스트, 제자리 교체·재실행 인계."
read_when:
  - 앱 내 업데이트를 배포할 때 (scripts/publish-github-update.sh)
  - 업데이트 서명 키를 만들거나 옮기거나 백업할 때
  - UpdateChecker·Core/Update/* 또는 앱 시작의 재실행 인계를 건드릴 때
---

# 앱 내 업데이트 (GitHub Releases)

2026-11-18 Drive 공유 파일 확인을 대체했다. Drive ZIP(`--install-on-launch`)은 최초 설치용으로만 남는다.

## 흐름

1. **확인** — `GitHubReleaseSource.fetch()` 가 `JunSungSoo/PokeTokenBar` 의
   `releases/latest/download/PokeTokenBar-update.json` 과 `.sig` 를 받는다. API 를 쓰지 않아 호출 제한이 없다.
2. **신뢰** — 앱에 들어 있는 Ed25519 공개 키로 매니페스트 바이트의 서명을 검증한다. 버전은
   `MAJOR.MINOR.PATCH`, 자산 이름은 `PokeTokenBar-<version>.zip` 이어야 하고 크기는 600MB 이하다.
   다운로드 주소는 서명된 버전으로 앱이 만든다(네트워크에서 읽지 않음). 현재 버전보다 높을 때만 제안한다.
3. **설치** (버튼) — 배틀·챌린지·교환 중이면 거부한다. ZIP 크기·SHA-256 → 압축 해제(앱 하나만 허용) →
   번들 ID·버전·코드 서명 확인 → **차단 조건 재확인**(다운로드 중 배틀·교환이 시작될 수 있음) →
   실행 중인 번들 옆에 복사 후 원자적 맞바꾸기(`BundleInstallation`) → 내려받은 파일 삭제.
   종료 경로는 `defer` 를 건너뛰므로 삭제는 종료 전에 직접 하고, 앱 시작 때도 `Caches/PokeTokenBar/Updates` 를 비운다.
4. **재실행** — 새 번들을 `--ptb-wait-for-pid <pid>` 인자로 띄우고 기존 앱이 종료한다. 새 인스턴스는
   이전 프로세스가 끝난 뒤에 시작을 이어간다. 그냥 띄우면 `SingleInstance` 규칙상 새 쪽이 물러난다.
   30초 안에 이전 프로세스가 안 끝나면 새 쪽이 종료한다(디스크에는 새 버전이 남아 다음 실행부터 적용).
   교체 뒤 새 버전 실행에 실패하면 "설치됨, 다시 시작 필요"로 안내하고 재시도를 막는다(디스크는 이미 새 버전).

앱이 직접 받은 파일에는 격리 표시가 붙지 않아 Gatekeeper 확인 없이 열린다(2026-11-18 macOS 26.5 실측:
ad-hoc 서명 앱의 자기 교체·다른 앱 교체·로그인 항목 유지 모두 권한 요청 없음). 그래서 출처 검증은
Gatekeeper 가 아니라 **서명된 매니페스트 + 해시**가 맡는다. ad-hoc 코드 서명은 무결성만 증명한다.

## 서명 키

- `scripts/update-signing-key.sh init` — 로그인 키체인에 생성(이미 있으면 거부). 공개 키는
  `GitHubReleaseSource.publicKey` 에 있다.
- **키를 잃거나 바꾸면 이미 설치된 앱은 이후 업데이트를 받지 못한다.** `export` 출력값을 비밀번호 관리자 등에
  백업한다. 저장소·채팅에 붙여넣지 않는다.
- 다른 Mac 에서 배포하려면 백업 값을 `security add-generic-password -a poketokenbar-update
  -s "PokeTokenBar Update Signing Key"` 로 넣는다.

## 배포

```bash
# scripts/build-app.sh 의 VERSION 을 올리고 커밋·푸시한 뒤
scripts/publish-github-update.sh 3.2.2 notes.md     # PTB_DRY_RUN=1 이면 빌드·서명만
PTB_UPDATE_ARTIFACTS=build/github-update/3.2.2 swift test --filter testPublishedArtifacts
```

스크립트 게이트: 버전 = build-app.sh, 키체인 키 = 앱 공개 키, 미커밋 변경 없음, HEAD 가 origin 에 있음,
같은 태그 없음, universal(arm64+x86_64), 업로드 전 앱 공개 키로 서명 재검증. 자산 3개
(`PokeTokenBar-<v>.zip`, `PokeTokenBar-update.json`, `.sig`)를 `v<version>` 태그로 올린다.
초안·프리릴리스는 `releases/latest` 에 잡히지 않는다.

## 전환

이 기능은 2026-11-18 빌드(`PokeTokenBar-3.2.1-20261118.zip`, 3.2.2)부터 들어 있다. 그 이전 설치본은 Drive 만 확인하므로
이 기능이 든 버전을 Drive ZIP 으로 한 번 더 배포해야
그 뒤부터 GitHub 업데이트를 받는다.

## 한계

- `/Applications` 에 쓸 수 없는 계정, App Translocation 실행은 제자리 교체를 거부하고 다운로드 페이지를 안내한다.
- 서명이 바뀌므로 Claude 키체인 "항상 허용"은 업데이트마다 다시 묻는다(공증 없이는 해결 불가, defect-log 참고).
- 재실행 인계(실제 앱 종료 → 새 버전 시작)는 단위 테스트가 아닌 첫 실제 릴리스에서 확인한다.
- 매니페스트에 만료 시점이 없다. 릴리스 자산을 바꿀 수 있는 공격자는 현재보다 높지만 최신이 아닌 예전
  서명 매니페스트를 내려 중간 버전을 설치시키거나 업데이트를 묶어둘 수 있다(다운그레이드는 불가). 수용한 위험.
- 서명 키는 `/usr/bin/security` 에 접근이 허용돼 있어, 같은 사용자 권한의 프로세스는 확인 창 없이 읽을 수 있다.
  배포 Mac 이 오염되면 모든 설치본에 갈 업데이트에 서명할 수 있다. 매번 확인 창을 띄우려면 키를 `-T ""` 로 다시 넣는다.
