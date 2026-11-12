---
summary: "릴리스 실행 절차 — 문서·에셋 갱신 의무, 스크린샷 재생성 방법, release.sh 게이트의 함정."
read_when:
  - 버전을 배포할 때 (자연어 트리거 포함: "배포해줘", "릴리스 올려줘", "패치 배포")
  - release.sh 가 문서·에셋 경고나 하드 게이트로 중단됐을 때
  - UI 를 바꿔 스크린샷·랜딩을 갱신해야 할 때
---

# 릴리스 실행 절차

버전 결정 규칙과 트리거는 `CLAUDE.md` §릴리스에 있다. 이 문서는 그 다음의 *실행 세부*를 담는다.
체크리스트 원본은 `RELEASE.md`.

## 로컬 ZIP 배포

릴리즈노트 새 이력은 사용자가 추가·기록을 명시적으로 지시할 때만 작성한다.
ZIP 생성·갱신, 빌드, 커밋·푸시 또는 기존 노트 포함 요청만으로 이력을 추가하거나
배포 회차를 올리지 않는다. 지시가 없으면 날짜별 TXT·전체 이력·`history.json`을 유지하고
기존 전체 이력을 ZIP에 포함한다. 파일명 중복은 생성 시각으로 구분하며 노트 회차를 올리지 않는다.

새 이력 추가를 지시받으면 완성된 UTF-8 TXT 노트를 날짜별 `docs/releases/zip/`에
보관하고 전체 이력과 `history.json`도 갱신한다.
본문은 `YYYY-MM-DD (N차 배포)` 제목, 빈 줄, `- 변경사항` 목록만 사용한다.
날짜마다 회차를 1부터 부여하고 같은 날짜 안에서는 높은 회차부터 내림차순으로 표시한다.
다음 배포는 빈 줄로 구분한다. 날짜도 최신 날짜부터 내림차순으로 표시한다. 버전·검증·출처는
노트 본문 대신 메타데이터에 보관한다. 과거 기록 복원은 실제 ZIP, 배포 완료 메시지,
성공한 압축 명령, 커밋 등 출처와 불확실성을 구분한다.

```bash
PTB_NATIVE_ARCH_ONLY=1 PTB_SKIP_INSTALL=1 bash scripts/build-app.sh
python3 scripts/package-zip.py --app build/PokeTokenBar.app \
  --install-on-launch \
  --notes "docs/releases/zip/00-Release History.txt" \
  --output "$HOME/Desktop/PokeTokenBar-VERSION-arm64-YYYYMMDD.zip"
```

Drive·Desktop ZIP의 최상위에는 `Install PokeTokenBar.app`, `Release Notes.txt`,
`Release Metadata.json`을 넣는다. 사용자가 ZIP을 풀고 설치 앱을 열면
`/Applications/PokeTokenBar.app`을 설치하거나 새 버전으로 교체해 실행한다.
설치 앱은 실제 앱과 다른 번들 식별자를 사용하므로 기존 앱이 열려 있어도 실행된다.
기존 앱이 정상 종료를 거부하거나 설치 권한이 없으면 기존 앱을 보존한다.
권한이 필요한 경우 설치 앱에서 실제 앱을 Finder로 열고 macOS의 승인 절차를 통해 복사한다.
Homebrew 배포 ZIP은 기존처럼 실제 `PokeTokenBar.app`을 최상위에 둔다.
사용자가 버전 유지를 요청한 수정본은 `--install-on-launch --reinstall-same-version`으로
패키징한다. 해당 ZIP만 같은 버전의 앱도 교체하며, 더 높은 설치 버전은 교체하지 않는다.
기본 설치 ZIP의 동일 버전 건너뛰기 동작은 유지한다.
패키징 시각, 버전, 소스 HEAD, 작업 트리 변경 여부, 실행 파일 해시는 JSON에만 저장한다.
노트 부재, 잘못된 날짜/회차, 변경사항 없는 항목,
기존 출력 덮어쓰기, ZIP 손상, 실행 파일 변경을 거부한다. 원본 `.app`은 수정하지 않는다.
`release.sh`의 공개 ZIP도 같은 패키저를 사용한다. 로컬 ZIP 배포가 공개 채널 게시를
의미하지는 않는다. 아래 절차는 GitHub/Homebrew 공개 버전 배포에 적용한다.

### Drive 배포 버전

Drive 업데이트는 날짜·회차가 아니라 앱의 `CFBundleShortVersionString`과 공유 ZIP 파일명의
`MAJOR.MINOR.PATCH`를 비교한다. 현재 버전은 3.1.3이며 새 Drive 배포마다 앱 버전과 파일명
버전을 함께 올린다. 빌드 스크립트가 앱 내부 버전을 기록하고 ZIP 메타데이터에도 같은 값이
포함된다. 파일명에 인식 가능한 버전이 있으면 패키저는 앱 버전 불일치를 거부한다.
`PokeTokenBar-3.1.3.zip` 또는 `PokeTokenBar-3.1.3-261112.zip` 형식을 사용한다.
날짜·회차만 바꿔서는 업데이트 알림이 발생하지 않는다. 자동 배포 회차 기록은 사용하지 않는다.
구현/검증 범위는 `docs/reference/drive-updates.md`를 참고한다.

## 1. 문서·이미지 갱신 (매 릴리스 필수 — "할까요?" 묻지 말고 무조건 한다)

`./scripts/release.sh --check-only` 로 경고를 확인한 뒤 아래를 모두 반영한다.

- **README.md/ko/ja**: 기능 목록·how-it-works·스크린샷 참조.
- **랜딩(gh-pages orphan 브랜치) — 필수.** `git worktree add /tmp/ptb-ghpages gh-pages` → `index.html`
  기능 카드(f#) + i18n 사전(en/ko/ja 동시·키 정합) 갱신 → 커밋 → `git push origin gh-pages` →
  `git worktree remove`. (Pages 자동 재빌드. 커밋은 gh-pages log 모방 = `landing:` 프리픽스.)
- **스크린샷(`assets/`)**: UI(`Sources/PokeTokenBar/UI/`) 변경 시 재생성. 기존 방식 = **HTML 렌더**
  (팝오버 라이브 캡처 아님) — Chrome `--headless --screenshot --force-device-scale-factor=2` 로 다크
  팝오버를 720px PNG 로 그린다. 애니 GIF(home)는 프레임 합성 후 `gifsicle -O3 --lossy` 로 최적화
  (PIL 재인코딩 단독은 용량 팽창 주의). 언어별 이미지(`settings.png`/`-ko`/`-ja` 등) 각 README 참조.
- homebrew-tap cask caveat.

### 게이트의 함정

- `release.sh` 문서검토는 *커밋된* 상태를 비교 → 스크린샷을 스테이징만 하면 경고 프롬프트가
  여전히 뜬다. 갱신을 미리 커밋한다. 릴리스 커밋에는 이미 스테이징된 다른 변경도 함께 담기므로 대상도 확인한다.
- **신규 기능 = 신규 에셋 (하드 게이트, 프롬프트로 못 넘김).** 직전 태그 이후 `Sources/**/UI/` 를 건드린
  `feat:` 커밋이 있는데 `assets/` 에 **새로 추가된** 파일이 없으면 `release.sh` 가 중단한다
  (**예외 없음** — 통과시키려면 에셋을 만들거나 커밋 타입을 바꿔야 한다). 기존 staleness 검사는 "에셋이 하나라도 바뀌었나"만
  보기 때문에 **기존 스크린샷만 다시 그려도 통과**한다 — 2.5.0 에서 플로팅 펫이 이미지 없이 나간 경로가
  정확히 이것이다(`settings.png` 를 갱신해 둔 탓에 조용히 통과). 갱신(stale)과 커버리지(신규)는 다른 질문이다.

## 2. 실행

먼저 `RELEASE.md`의 릴리스 노트·기여자 절차에 따라 준비한다.

- `release-notes-template.md`를 복사하고 v2.5.3처럼 영어 New / Fixed / Other / Contributors 및
  Install / Upgrade를 작성한다. 필수 섹션을 지우거나 `Release vX.Y.Z` 한 줄로 대체하지 않는다.
- 직전 공개 릴리스 태그부터 배포 대상까지의 PR·직접 커밋을 확인해 외부 기여자 목록을 만든다.
  PR 작성자와 실제 공동기여자를 빠짐없이 확인하고 `PTB_CONTRIBUTORS_FILE`과 노트의 Contributors를 맞춘다.
  기존 릴리스 목록 재사용이나 날짜만으로 범위를 정하는 방식은 쓰지 않는다.
- 실제 공동작업이 확인된 릴리스 준비 커밋만 `PTB_COAUTHORS_FILE`에 참여자의 이름·이메일을 지정한다.
  기본은 없음이며 Claude/Codex 등 특정 이름을 자동으로 붙이지 않는다.
- 노트 원문과 기여자 목록 검사를 마친 뒤 적용 버전과 노트 요약을 사용자에게 보여준다.

그 다음 반드시 `main` 브랜치에서:

```bash
# 직전 릴리스 이후 변경을 요약해 노트 파일 작성
PTB_NOTES_FILE=/tmp/ptb-notes.md PTB_ZIP_NOTES_FILE=docs/releases/zip/YYYY-MM-DD.txt PTB_CONTRIBUTORS_FILE=/tmp/ptb-contributors.txt ./scripts/release.sh <version>
```

스크립트가 노트·Contributors 검증 → test-gate → 문서검토 → 범프 → 빌드검증 → 커밋·push →
GitHub Release → cask → Pages를 순서대로 수행한다. 빌드 단계에서 기존 로컬 앱 종료·교체도 수행한다.
노트나 기여자가 누락되면 앱 교체·push 전에 중단하며, 게시에는 검증한 노트 파일을 그대로 사용한다.

## 3. 검증

완료 후 `brew upgrade --cask poke-token-bar` 로 실제 업그레이드 동작을 확인한다.


## Standalone resource and installer validation

The app embeds `PokeTokenBar_PokeTokenBar.bundle` inside `Contents/Resources`; the
legacy resource directory names are relative aliases into it. Do not place a bundle
alias in the app root: strict macOS signing rejects unsealed root content.
`AppResources.module` resolves the shipped bundle before the SwiftPM checkout.

Verify resource resolution with a standalone app, not just source-byte comparisons.
App Translocation may give a correctly signed launched app a different URL: compare
validated code identity for that mount rather than treating every path change as a
concurrent installation. Never remove quarantine to make a verification pass.
