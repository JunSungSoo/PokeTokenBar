# 6세대 페어리 기술 조사 및 엔진 예외 적용

확인일: 2026-10-27 (Asia/Seoul). 아래 수치와 습득표는 **6세대 본가의 습득표가 아니라, 확인 시점 PokéRogue 원본 데이터**를 기준으로 한다. 대상 기술의 등장 세대만 6세대로 한정했다.

## 적용한 엔진 변경

- 6세대 신규 페어리 기술 14개만 `allowedFairyMoves` 예외로 허용했다. 7세대 이후 페어리 기술과 다른 타입의 6세대 이후 기술은 차단한다.
- 기술 실행 정의는 기존 Showdown 엔진의 6세대 데이터를 사용한다. PokéRogue의 별도 밸런스 수치를 자동으로 덮어쓰지는 않았다.
- 페어리의 공격·방어 상성만 추가했다. 기존 BW2의 강철→악/고스트 저항 등 다른 상성과 일반 포켓몬의 타입은 유지했다. 예: 일반 가디안은 BW2의 에스퍼 타입이며, 메가가디안은 기존 메가진화 데이터의 에스퍼/페어리다.
- 양쪽 앱의 규칙 리비전에 `/gen6-fairy-moves-v1`을 추가했다. 이전 규칙의 앱과 같은 규칙으로 취급하지 않는다.
- 초기 엔진 예외 검증: 엔진 118개, Swift 사전검증·프레임 통신 2개 통과.
- 2026-10-28 전체 연동 검증: 엔진·에셋 119개와 앱 회귀 테스트 42개 통과. 실제 14개 기술의 싱글·더블 행동, 15개 원본 타임라인의 양방향/전경/배경 재생, 효과음, GIF와 원본 속도·음량 유지, 필드 활성화를 검증했다.

**2026-10-28 연동:** 호환되는 222종의 기술 선택 목록과 8개 언어 카탈로그, 원본 이펙트 14개 및 지오컨트롤 충전을 연결했다. 기존 BW2 자동 기술배치는 유지하고 선택에만 보완 데이터를 병합한다. PokéRogue 고유 알 기술은 해당 습득 방식으로 표시하며, 문포스 설명은 엔진의 30% 확률과 일치시켰다. 아래 원본 조사는 당시 최신 에셋 기준이고, 실제 앱은 기존 연출과의 일관성을 위해 같은 기술을 기존 에셋 리비전 `009cac30…`에서 가져왔다. 자세한 해시는 `gen6-fairy-source.json`과 플레이어 manifest에 기록했다.

## 기술 수치와 이펙트

명중률의 `필중`은 명중률 판정을 생략한다는 의미다. 변화 기술의 `—`는 명중률 숫자를 사용하지 않는 경우다. `위력 —`는 피해 기술이 아니다. 프레임 수는 원본 JSON의 프레임 개수이며 초 단위 재생시간이 아니다.

| 기술 | 영문 ID | 분류 | 위력 | 명중 | PP | 원본 연출 프레임 | 배경 참조 | 전용 효과음 참조 수 |
|---|---|---|---:|---|---:|---|---:|---:|
| 문포스 | `moonblast` | 특수 | 95 | 100% | 15 | 59 / 59 | 1 | 2 |
| 매지컬샤인 | `dazzlinggleam` | 특수 | 80 | 100% | 10 | 39 | 1 | 1 |
| 치근거리기 | `playrough` | 물리 | 90 | 90% | 10 | 64 | 0 | 4 |
| 드레인키스 | `drainingkiss` | 특수 | 50 | 100% | 10 | 17 | 0 | 2 |
| 차밍보이스 | `disarmingvoice` | 특수 | 40 | 필중 | 15 | 17 / 17 | 0 | 0 |
| 요정의바람 | `fairywind` | 특수 | 40 | 100% | 30 | 34 | 1 | 1 |
| 초롱초롱눈동자 | `babydolleyes` | 변화 | — | 100% | 30 | 24 | 1 | 1 |
| 아로마미스트 | `aromaticmist` | 변화 | — | — | 20 | 74 | 1 | 1 |
| 트릭가드 | `craftyshield` | 변화 | — | — | 10 | 38 / 38 | 0 | 1 |
| 플라워가드 | `flowershield` | 변화 | — | — | 10 | 27 | 0 | 1 |
| 미스트필드 | `mistyterrain` | 변화 | — | — | 10 | 29 | 1 | 1 |
| 페어리록 | `fairylock` | 변화 | — | — | 10 | 42 | 0 | 1 |
| 지오컨트롤 | `geomancy` | 변화 | — | — | 10 | 51 | 1 | 1 |
| 파멸의빛 | `lightofruin` | 특수 | 140 | 90% | 5 | 49 | 1 | 3 |

- **14개 모두 원본 타임라인과 참조 이미지/배경/효과음 파일이 저장소에 존재한다.** 15개 JSON(지오컨트롤 충전 포함)의 참조 경로를 저장소 트리와 대조했고 누락은 없었다. 아로마미스트는 별도 그래픽 시트 없이 배경 이벤트 중심이다.
- 차밍보이스의 타임라인에는 전용 효과음 파일 참조가 없다. 원본 그림/동작 연출은 있으며, 소리를 보강할 경우 별도 확인이 필요하다.
- 지오컨트롤은 발동 51프레임 외에 충전 23프레임 JSON이 별도로 있다.
- 조사 시에는 원본 플레이어에 14개가 없었으나, 현재는 원본 14개와 충전 연출을 연결했다. 기존 Showdown 대체 이펙트보다 PokéRogue 원본 재생 경로를 우선한다.

### 수치 차이

- **문포스:** 현재 PokéRogue 소스와 한국어 설명은 특공 하락 10%다. 이번 엔진 예외는 기존 Showdown 6세대 정의를 사용하므로 30%다. 위력 95·명중 100·PP 15는 같다.
- 6세대에 새로 만들어진 기술만 조사했다. 애교부리기·천사의키스·달의불빛처럼 이전 세대에 만들어졌다가 페어리로 재분류된 기술은 새 예외에 포함하지 않았으며 기존 BW2 정의를 유지한다.

## 습득 포켓몬 범위

- 아래 일반 목록은 프로젝트가 현재 배틀 참가를 허용하는 **전국도감 1~649번의 최종 진화체**만 표시한다. 육성 완료/보유 여부는 각 사용자의 컬렉션에서 추가 판정된다.
- PokéRogue 원본의 레벨업·진화/기억 기술·기술머신과 진화 전 포켓몬으로부터의 상속을 포함한다. 특히 기술머신도 진화 전 목록을 재귀적으로 합산하는 원본 `getTms` 규칙을 반영했다.
- **PokéRogue 고유 알 기술**은 본가의 교배 알 기술과 다르다. 해당 스타터의 잠금 해제 및 진화 계통 상속을 전제로 하는 후보이며, 현재 프로젝트에 같은 잠금 해제 시스템이 있다고 가정하지 않는다.
- 스케치, 전투 중 일시적 기술 복사, 융합은 일반 습득 목록에서 제외했다. 후대 지역폼·후대 진화체도 현재 참가 가능 목록에 추가하지 않는다.
- [전체 1~5세대 습득 경로 CSV](gen6-fairy-move-learners.csv)는 미진화체까지 포함하며, 현재 배틀 참가 가능 여부를 별도 열로 구분한다.

### 문포스

상대 특공 -1, PokéRogue 발동 확률 10%.

일반 습득 경로: **12종**. 픽시, 푸크린, 라플레시아, 질뻐기, 야부엉, 아르코, 가디안, 파비코리, 루나톤, 크레세리아, 몽얌나, 엘풍

PokéRogue 고유 알 기술로만 추가되는 후보: **17종**. 라이츄, 나인테일, 아쿠스타, 마임맨, 뮤츠, 뮤, 메가니움, 네이티오, 헬가, 밀로틱, 무우마직, 다크라이, 다부니, 심보러, 조로아크, 고디모아젤, 샹델라

### 매지컬샤인

더블배틀에서 인접한 상대 모두를 공격.

일반 습득 경로: **55종**. 라이츄, 픽시, 푸크린, 라플레시아, 후딘, 독파리, 팬텀, 슬리퍼, 아쿠스타, 마임맨, 뮤, 메가니움, 랜턴, 네이티오, 전룡, 아르코, 솜솜코, 해루미, 에브이, 키링키, 그랑블루, 해피너스, 세레비, 가디안, 깜까미, 볼비트, 네오비트, 피그킹, 파비코리, 점토도리, 다크펫, 치렁, 지라치, 로즈레이드, 체리꼬, 무우마직, 네오라이트, 토게키스, 엘레이드, 대코파스, 유크시, 엠라이트, 아그놈, 크레세리아, 피오네, 마나피, 쉐이미, 비크티니, 몽얌나, 다부니, 엘풍, 심보러, 치라치노, 탱탱겔, 메로엣타

PokéRogue 고유 알 기술로만 추가되는 후보: **2종**. 폴리곤Z, 불카모스

### 치근거리기

상대 공격 -1, 발동 확률 10%.

일반 습득 경로: **46종**. 라이츄, 픽시, 푸크린, 페르시온, 윈디, 날쌩마, 쥬레곤, 뮤, 블레이범, 다꼬리, 아르코, 마릴리, 그랑블루, 링곰, 코리갑, 밀탱크, 그라에나, 직구리, 게을킹, 델케티, 입치트, 플러시, 볼비트, 네오비트, 파비코리, 앱솔, 지라치, 렌트라, 파치리스, 체리꼬, 이어롭, 몬냥이, 스컹탱크, 토게키스, 유크시, 엠라이트, 아그놈, 쉐이미, 바랜드, 레파르다스, 엘풍, 치라치노, 바라철록, 맘복치, 툰베어, 메로엣타

PokéRogue 고유 알 기술로만 추가되는 후보: **3종**. 켄타로스, 앤테이, 에레키블

### 드레인키스

가한 피해의 75% 회복. 특수 기술이지만 접촉 판정.

일반 습득 경로: **26종**. 버터플, 라이츄, 픽시, 푸크린, 슬리퍼, 루주라, 뮤, 마릴리, 에브이, 가디안, 입치트, 네오비트, 밀로틱, 치렁, 분홍장이, 사랑동이, 라티아스, 체리꼬, 무우마직, 토게키스, 엘레이드, 눈여아, 유크시, 엠라이트, 아그놈, 다부니

PokéRogue 고유 알 기술로만 추가되는 후보: **1종**. 마나피

피카츄의 `cute-cosplay` 형태에도 전용 레벨 기술이 있으나 현재 프로젝트의 일반 피카츄/라이츄 데이터와 동일하게 취급하면 안 된다.

### 차밍보이스

명중률 판정 생략, 소리 기술, 인접한 상대 모두.

일반 습득 경로: **28종**. 라이츄, 픽시, 푸크린, 라프라스, 뮤, 메가니움, 마릴리, 해피너스, 로파파, 가디안, 폭음룡, 델케티, 네오비트, 파비코리, 밀로틱, 치렁, 라티아스, 엠페르트, 엘레이드, 피오네, 마나피, 쉐이미, 야나키, 바오키, 앗차키, 다부니, 스완나, 메로엣타

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 요정의바람

바람 판정이 있는 특수 공격.

일반 습득 경로: **4종**. 솜솜코, 입치트, 토게키스, 엘풍

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 초롱초롱눈동자

우선도 +1, 상대 공격 -1.

일반 습득 경로: **17종**. 나인테일, 샤미드, 쥬피썬더, 부스터, 에브이, 블래키, 링곰, 직구리, 델케티, 사랑동이, 렌트라, 이어롭, 리피아, 글레이시아, 바랜드, 다부니, 치라치노

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 아로마미스트

인접한 아군 1마리의 특방 +1.

일반 습득 경로: **1종**. 비퀸

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 트릭가드

우선도 +3. 이번 턴 아군 측을 상대의 변화 기술로부터 보호.

일반 습득 경로: **1종**. 데스니칸

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 플라워가드

필드에 있는 풀 타입 포켓몬의 방어 +1. 상대 풀 타입도 포함.

일반 습득 경로: **2종**. 해루미, 체리꼬

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 미스트필드

양 진영에 미스트필드 설치. 통상 5턴, 접지한 포켓몬의 상태이상 방지와 드래곤 피해 감소.

일반 습득 경로: **11종**. 픽시, 푸크린, 마임맨, 뮤, 마릴리, 가디안, 입치트, 엘레이드, 다부니, 엘풍, 맘복치

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

### 페어리록

다음 턴까지 양측 교체를 제한하는 필드 효과.

일반 습득 경로: **0종**. 현재 참가 가능한 포켓몬 중 없음.

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

원본의 대표 습득 포켓몬은 클레피(707번), 레벨 1이다. 현재 프로젝트의 포켓몬 범위 밖이다.

### 지오컨트롤

한 턴 충전 후 사용자의 특공·특방·스피드 각각 +2.

일반 습득 경로: **0종**. 현재 참가 가능한 포켓몬 중 없음.

PokéRogue 고유 알 기술로만 추가되는 후보: **0종**. 없음.

원본의 대표 습득 포켓몬은 제르네아스(716번), 레벨 70이다. 아마루스 계통·디안시에는 고유 알 기술도 있다. 모두 현재 범위 밖이다.

### 파멸의빛

가한 피해의 50% 반동.

일반 습득 경로: **0종**. 현재 참가 가능한 포켓몬 중 없음.

PokéRogue 고유 알 기술로만 추가되는 후보: **1종**. 란쿨루스

원본에는 영원의꽃 플라엣테 계열 데이터의 레벨 50 기술로도 존재한다. 해당 형태는 현재 프로젝트의 1~5세대 포켓몬 범위 밖이다.

## 이펙트 원본 파일

모두 같은 에셋 리비전으로 확인했다. 아래 이미지명/음원명은 JSON이 직접 참조하는 파일명이며 외형을 추정한 설명이 아니다.

- **문포스**: [moonblast.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/moonblast.json)
  - 그래픽: `PRAS- Moonblast`; 배경: `PRAS- Starry BG`.
  - 효과음: `PRSFX- Moonblast1.wav`, `PRSFX- Moonblast2.wav`.
- **매지컬샤인**: [dazzling-gleam.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/dazzling-gleam.json)
  - 그래픽: `PRAS- Recovery`; 배경: `PRAS- Dazzling Gleam`.
  - 효과음: `PRSFX- Dazzling Gleam.wav`.
- **치근거리기**: [play-rough.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/play-rough.json)
  - 그래픽: `PRAS- Love`; 배경: 없음.
  - 효과음: `PRSFX- Play Rough1.wav`, `PRSFX- Play Rough2.wav`, `PRSFX- Play Rough3.wav`, `PRSFX- Play Rough4.wav`.
- **드레인키스**: [draining-kiss.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/draining-kiss.json)
  - 그래픽: `PRAS- Draining Kiss`; 배경: 없음.
  - 효과음: `PRSFX- Draining Kiss1.wav`, `PRSFX- Draining Kiss2.wav`.
- **차밍보이스**: [disarming-voice.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/disarming-voice.json)
  - 그래픽: `PRAS- Sound`; 배경: 없음.
  - 효과음: 타임라인 내 파일 참조 없음.
- **요정의바람**: [fairy-wind.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/fairy-wind.json)
  - 그래픽: `PRAS- Fairy Wind`; 배경: `PRAS- Fairy Wind BG`.
  - 효과음: `PRSFX- Fairy Wind.wav`.
- **초롱초롱눈동자**: [baby-doll-eyes.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/baby-doll-eyes.json)
  - 그래픽: `PRAS- Baby Doll Eyes`; 배경: `PRAS- Baby Doll Eyes BG`.
  - 효과음: `PRSFX- Baby Doll Eyes.wav`.
- **아로마미스트**: [aromatic-mist.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/aromatic-mist.json)
  - 그래픽: 별도 그래픽 시트 없음; 배경: `PRAS- Mist FG`.
  - 효과음: `PRSFX- Aromatic Mist.wav`.
- **트릭가드**: [crafty-shield.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/crafty-shield.json)
  - 그래픽: `PRAS- Crafty Shield`; 배경: 없음.
  - 효과음: `PRSFX- Crafty Shield.wav`.
- **플라워가드**: [flower-shield.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/flower-shield.json)
  - 그래픽: `PRAS- Grass`; 배경: 없음.
  - 효과음: `PRSFX- Flower Shield.wav`.
- **미스트필드**: [misty-terrain.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/misty-terrain.json)
  - 그래픽: `PRAS- Orbs`; 배경: `PRAS- Misty Terrain BG`.
  - 효과음: `PRSFX- Misty Terrain.wav`.
- **페어리록**: [fairy-lock.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/fairy-lock.json)
  - 그래픽: `PRAS- Fairy Lock`; 배경: 없음.
  - 효과음: `PRSFX- Fairy Lock.wav`.
- **지오컨트롤**: [geomancy.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/geomancy.json)
  - 그래픽: `PRAS- Geomancy`; 배경: `PRAS- Geomancy BG`.
  - 효과음: `PRSFX- Geomancy.wav`.
- **파멸의빛**: [light-of-ruin.json](https://github.com/pagefaultgames/pokerogue-assets/blob/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims/light-of-ruin.json)
  - 그래픽: `PRAS- Strike`; 배경: `PRAS- Flash FG`.
  - 효과음: `Blow1.m4a`, `Saint7.m4a`, `Saint8.m4a`.

## 연결 작업 및 남은 규칙 범위

1. 완료: 조사한 한국어/다국어 기술명·설명과 위력·명중·PP·대상 정보를 앱 기술 카탈로그에 추가한다.
2. 완료: 기존 BW2 습득표는 유지하고, 허용한 14개 페어리 기술에 한해 별도 습득 데이터로 병합한다. PokéRogue 고유 알 기술도 호환 포켓몬의 선택지로 넣고 습득 방식을 구분해 표시한다.
3. 완료: 14개 원본 타임라인, 지오컨트롤 충전, 이미지·배경·효과음을 해시와 함께 번들링하고 기술 ID/충전 단계에 매핑한다.
4. 완료: 문포스처럼 PokéRogue와 본가/기존 엔진이 다른 부가효과는 선택한 규칙에 맞게 설명과 계산을 일치시킨다.
5. 일반 포켓몬의 페어리 재분류는 이번 엔진 예외와 별개다. 바꾸려면 능력치·타입·상성 안내가 함께 일치하도록 별도 범위를 정한다.

## 확인한 원본

- [PokéRogue 기술 정의](https://github.com/pagefaultgames/pokerogue/blob/39fe0aa2c29a48fb57897c1b31b03e8039e59b15/src/data/moves/move.ts)
- [PokéRogue 습득표·종 데이터](https://github.com/pagefaultgames/pokerogue/tree/39fe0aa2c29a48fb57897c1b31b03e8039e59b15/src/data/balance/species)
- [진화 전 기술머신 상속](https://github.com/pagefaultgames/pokerogue/blob/39fe0aa2c29a48fb57897c1b31b03e8039e59b15/src/data/species-data-registry.ts)
- [레벨 기술 상속](https://github.com/pagefaultgames/pokerogue/blob/39fe0aa2c29a48fb57897c1b31b03e8039e59b15/src/field/learnsets.ts)
- [PokéRogue 고유 알 기술](https://github.com/pagefaultgames/pokerogue/blob/39fe0aa2c29a48fb57897c1b31b03e8039e59b15/src/data/balance/moves/egg-moves.ts)
- [한국어 기술명·설명](https://github.com/pagefaultgames/pokerogue-locales/blob/b24c6f3d1b3f4449440d0200487e614e69b5df3d/ko/move.json)
- [원본 이펙트](https://github.com/pagefaultgames/pokerogue-assets/tree/8250b23677d4918801fc6fc1e95b6dd1c30ef6c4/battle-anims)

런타임: `39fe0aa2c29a48fb57897c1b31b03e8039e59b15` / 에셋: `8250b23677d4918801fc6fc1e95b6dd1c30ef6c4` / 번역: `b24c6f3d1b3f4449440d0200487e614e69b5df3d`. 현재 앱의 기존 에셋 리비전(`009cac30…`)과 구분해 조사했다.
