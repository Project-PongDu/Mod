# 퐁듀 — 좀보이드 B41 치지직 후원연동 시스템

**최종 업데이트**: 2026-07-06 (커밋 3dc53e0 이후 코드 대조 최신화)

---

## 📋 프로젝트 구조

### 1. **퐁듀** (`gui.py`)

- **상태**: 기능 완성 ✅ (t3 로컬 환경에서 구동 확인)
- 역할: 치지직 후원 이벤트 → `rewards.txt` 릴레이
- 기술: PyQt5 + chzzkpy (비공식) + asyncio
- 배포: PyInstaller `--onefile` → `PongDu.exe` (V3.1.1에서 실행파일/윈도우 타이틀 "PongDu"로 개명 — 소스 내 한글 "퐁듀"는 CP949 인코딩 문제로 회피)

### 2. **인게임 모드** (`t3chzzkDonation`, "[Puppet] chzzk API")

- **상태**: 인프라 완료, 18개 featureId 중 13개 구현 완료 / 5개 스텁
- 역할: `rewards.txt` 읽기 → 게임 이펙트 트리거 (히트맨 NPC, 폭격, 텔레포트, 좀비 룰렛, 스킬 물약 등)
- 기술: B41 Lua + 멀티플레이어 통신 (`sendClientCommand`, modData)
- 아키텍처: featureId 기반 디스패치 (`rewardManager.lua`)

---

## ✅ 완료된 작업

### 퐁듀 (V3.1.1)

- ✅ Chzzk 채널 자동 해석 (URL / 채널명 / UUID)
- ✅ rewards.txt 경로 자동 탐지 + 수동 지정
- ✅ 도네 실시간 로깅 + 테스트 주입
- ✅ 리워드 티어 편집 UI
  - 금액 ↔ featureId 매핑 (표 형식)
  - 행 추가/삭제/저장
  - `reward_preset.json` 자동 export
  - 기본 티어 11개로 확장 (`random_skill_potion` 30000원, `mutant_spawn` 40000원, `rise_up_dead_man` 200000원 추가)
- ✅ 리워드 프리셋 import
  - JSON 파일 불러오기 (체크리스트에서)
  - 다중 서버/스트리머용 티어 동기화 가능
  - 프리셋 존재 시 편집 UI 잠금 (초기화는 게이트에서만)
- ✅ 라인 포맷 (모드 규약): `amount,featureId,sender,message` (URL 인코딩)
- ✅ 19세 방송 감지 + 쿠키 지원 (네이버 NID)
- ✅ 런처 게이트 (화이트리스트 검증 → 방송/PZ/인게임 상태 체크 → 자동 연동)
- ✅ 감시 (MainGuard): PZ 종료 감지 + 19세 전환 감지 + 인게임 이탈 감지
- ✅ 단일 실행 exe 패키징 (`build.bat`, 아이콘 임베드)
- ✅ **PZ 원클릭 최적화** (신규, V3.x)
  - Steam 설치 경로 자동 탐지 (레지스트리 HKCU/HKLM → 드라이브 스캔 → `libraryfolders.vdf` 파싱, `appmanifest_108600.acf`로 PZ 위치 특정)
  - JVM 힙(`-Xms`/`-Xmx`)을 시스템 RAM 절반으로 자동 설정 (256MB 단위 절사, 최소 2048MB) — `ProjectZomboid64.json`(vmArgs)과 `ProjectZomboid64.bat`(직접 실행용) 둘 다 패치
  - 좀비 연산 관련 class 파일 9개 교체 (`opt_conf/` 리소스, 복사 후 바이트 검증)
  - 최초 적용 시 원본 자동 백업 (`puppet_opt_backup/`), 언제든 복원 가능
  - 상태 3단계 감지: `applied` / `partial`(게임 업데이트로 class 갱신 등) / `none`
  - 권한 문제 시 UAC 승격 재실행 (`--pz-optimize` / `--pz-restore` 플래그로 자기 자신 재호출, `ShellExecuteW runas`)
  - PZ 실행 중이면 파일 교체 차단 (충돌 방지)

### 인게임 모드 (V2.x)

- ✅ 리워드 수신 인프라
  - `DonationReceiver.lua`: 4필드 파싱 (`amount,featureId,sender,message`)
  - `rewardManager.lua`: featureId 기반 디스패치 (18개 슬롯)
- ✅ 히트맨 NPC 시스템 (Bandits 모드와 완전 네임스페이스 격리)
  - 히트맨 AI (`HitmanBrain`), `Sharpshooter`(발사 간격 단축) + `Knifemaster`(구 Berserker, 단검 전용 공격속도 가속 — 판정 타이머 `Hitman.KnifemasterSpeedMult`와 애니메이션 `CombatSpeed` 변수 동기화, 찌르기/스윙 랜덤 혼합) 전문성
  - Heartsight 탐지: Recon(+13) / Tracker(+53) 가산 적용
  - 플레이어/NPC 추적 (`GetTarget`)
  - modData 네임스페이싱 (충돌 방지)
- ✅ 폭격 시스템 (Bombard)
  - 서버 → 전체 브로드캐스트 → 각 클라이언트가 자신이 소유한 좀비만 킬 (B41 좀비 권한 모델 대응)
- ✅ 기능 구현 완료 (13개)
  - debuff_roulette / buff_roulette / zombie_roulette
  - sprinter5 / bandit_melee / vaccine / bandit_ranged / exile / missile / backroom
  - **random_skill_potion**: 시크릿 물약 7종 (`serum_supreme` + 근력/지구력/달리기/은신 등 미니 세럼 6종), 확률 디스패치 supreme 1% / strength 9% / fitness 10% / 나머지 20%씩 (`ZombRand(100)` 합 100 고정), `OnEat` 핸들러 `skillpotion.lua`로 통합
    - ✅ (수정 완료) `media/scripts/*.txt`의 `--` 주석 → `/* */` 교체 완료, `serum_strength` 블록 정상 파싱 확인
  - **rise_up_dead_man**: 도네 플레이어 반경 내 모든 시체(`IsoDeadBody`) 좀비로 부활
    - 클라: `riseup.lua` — 좌표/반경만 서버 전송 (시체는 서버 권한 객체이므로 부활도 서버 한 곳에서만 처리, 폭격과 권한 모델 정반대)
    - 서버: `server.lua`의 `DOServer["Schedule"]["RiseUp"]` — 반경 내 스퀘어 순회(0~7층) → `IsoDeadBody:reanimateNow()`
    - 현재 플레이어 시체도 구분 없이 부활 대상에 포함됨 (`isFakeDead()` 필터 미적용 — 의도적 방치, 원하면 필터 추가 가능)
    - 스프린터 스피드 타입: 엔진 유지에 의존하지 않고 영속 레지스트리 재적용으로 해결 (`makeSprinter`가 `registerMutant(a,"sprinter")` 등록 → 부활 시 클라이언트가 재적용)
    - 발동범위 표시: 시전 시 반경 시각화 (`riseup.lua`)
    - 특수좀비(뮤턴트) 부활 시 능력 유지: 영속 레지스트리 방식으로 구현 완료 — 아래 "부활 지속성 아키텍처" 참고
  - **mutant_spawn** (`mutant-zombies` 브랜치, 기존 `cdda_spawn` 대체 — CDDA 모드 의존성 제거): 스크리머 / 브루트 / 로치 중 1마리 랜덤 소환
    - `mutantspawn.lua`: 외부 모드 의존 없이 독립 구현, 서버가 좀비 스폰 후 `sendServerCommand("PEvents","MutantMark",{zedId,kind})`로 타입 브로드캐스트
    - 각 클라이언트가 `OnServerCommand`로 수신 → `onlineID` 키로 `_pending` 테이블에 저장 → `OnZombieUpdate`에서 실제 행동/외형 적용
    - 로치 변형은 `media/AnimSets/zombie-crawler/*/roach_*.xml`의 `PuppetRoach` 불리언 조건 + `m_SpeedScale`로 이동/공격 속도 커스텀 (AnimSet additive vs last-wins 동작은 아직 미검증)
    - 소환 대사: 욕(SWEAR 10종) + 종류 + 마무리(ENDMENT 7종) 3파트 랜덤 조합 외침 (번역 키 기반, 예: "시발, 브루트잖아!")
    - 네임태그: `TextDrawObject` 기반 머리 위 표기 (`_showTags` TTL 관리, 후원자 어트리뷰션 포함), `Donation_MutantNameTag` 샌드박스 옵션으로 토글
    - ✅ `gui.py`(퐁듀) V3.1.1 기준 `FEATURES` 라벨도 동기화 완료: `mutant_spawn`→"특수좀비 소환", `random_skill_potion`→"신체 강화 혈청", `rise_up_dead_man`→"강령술" (전부 "(미구현)" 꼬리표 제거됨)
- ✅ 후원 알림 UI
  - 우상단 후원 알림 패널 — 드래그 이동(위치 저장), X 버튼으로 개별 닫기, 표시 토글
- ✅ 샌드박스 옵션 6종 (`Hitmans_Donation` 페이지)
  - `Donation_ShowPanel` — 후원 알림 패널 표시 토글
  - `Donation_PrepDelay` — 이펙트 적용 대기시간 (0~10초)
  - `Donation_BombardDelay` — 폭격 발동 대기시간 (10~300초, 기본 60)
  - `Donation_BombardRadius` — 폭격 반경 (5~60타일, 기본 55)
  - `Donation_RiseUpRadius` — 부활 반경 (5~60타일, 기본 55, 폭격 반경과 완전 별개 변수)
  - `Donation_MutantNameTag` — 뮤턴트 네임태그 표시 토글
  - 전부 `SandboxVars.Hitmans` 사용 시점 읽기 (`SandboxVars and SandboxVars.Hitmans` nil 가드 패턴)

---

## 🧬 부활 지속성 아키텍처 (구현 완료, 인게임 최종 검증 대기)

`rise_up_dead_man`으로 특수좀비(뮤턴트/스프린터) 시체를 부활시켜도 능력이 유지되는 구조.
초기 시도(`MutantDied` 클라 보고 → `deadRegistry` armed marks)는 **폐기**하고 영속 레지스트리 방식으로 재설계함.

- **영속 레지스트리** (`ModData.getOrCreate("PuppetMutants")`, 서버):
  - 키: `HitmanUtils.GetZombieID(zed)` — `persistentOutfitID`에서 모자 상태 비트(16번)를 마스킹한 정규화 ID (모자 벗겨져도 불변)
  - 값: `{k=종류, s=후원자}` (구버전 문자열 항목과 호환 위해 읽기는 `regEntry` 경유)
  - 글로벌 ModData는 서버 세이브에 저장 → **서버 재시작 후 부활에도 유효**
  - 등록 시점: 뮤턴트 스폰 시 + `makeSprinter` 호출 시 (`"sprinter"` 종류)
- **부활 시 재적용 흐름** (`server.lua` `DOServer["Schedule"]["RiseUp"]`):
  1. 시체의 pid는 사망까지 안정 (로그로 검증) → 정규화 키로 레지스트리 조회 = 특수좀비 여부 판정
  2. `reanimateNow()` 후 부활 좀비는 pid를 **새로 발급**받아 직조회 불가 → 부활 좌표+종류를 `sendServerCommand("PEvents","MutantRevive",{x,y,z,kind,sender,key})`로 전 클라 브로드캐스트
  3. 각 클라이언트의 `OnZombieUpdate`(발화 100% 검증됨)가 해당 위치 부활 좀비에 능력 재적용
- **재접속 자동부활 버그 픽스** (커밋 `3602ed6`): `reanimateNow()`로 부활한 좀비는 엔진 `ReanimateTimer`를 물고 있어, 재사망 시 시체에 `reanimateTime`이 박히고 청크 세이브에 직렬화됨 → 서버 재부팅 후 로드 시 자동 부활하는 버그
  - ① 부활 직후 `_riseSweeps` 등록 → `EveryOneMinute` 3회 스윕으로 반경 내(이동 여유 +60타일) 좀비들의 `ReanimateTimer` 제거
  - ② `Events.LoadGridsquare` 훅: 로드되는 좀비 시체의 `reanimateTime`을 0으로 소급 세정
- **관측성**: 서버 `srvlog`("RiseUp: N corpses, N pid-readable, N special marks") + `MutantReviveDebug` 클라 브로드캐스트로 클라 `console.txt`만으로 전 과정 관측 가능
- **남은 것**: 인게임 최종 검증 (부활 후 능력 유지 + 서버 재부팅 시나리오)

---

## 🚧 진행 중 / 남은 작업

### **A. 모드: 5개 featureId 스텁 구현** (우선순위 높음)

#### `rewardManager.lua`에 등록된 스텁 5개

(`cdda_spawn`은 `mutant_spawn`으로 대체 완료 — 아래 표에서 제외)

| featureId            | 라벨               | 설계 메모                                                           | 의존성       | 추정 난이도 |
| -------------------- | ------------------ | ------------------------------------------------------------------- | ------------ | ----------- |
| `random_weapon`      | 랜덤 무기 뽑기     | 티어별 무기 등급 확률 테이블 (예: 1000원→T1 낮음, 100000원→T3 높음) | 인벤토리 API | ⭐⭐        |
| `vehicle_kit`        | 차량소환 키트      | `zone.a()` 안전지대 체크 재사용 + 차량 스폰                         | 차량 API     | ⭐⭐⭐      |
| `revive_ticket`      | 즉시부활 티켓      | 기절 해제 (`immediate=true` 스텁만 등록) — 실제 구현 필요           | Status API   | ⭐          |
| `secret_passage_kit` | 비밀통로 공사 키트 | `bombard.lua`의 `transmitAddObjectToSquare` 패턴 재사용 (벽 제거)   | 맵 API       | ⭐⭐⭐      |
| `horde_night`        | 호드나이트         | 대량 좀비 스폰 + 서버 부하 관리 (스폰 큐 확장)                      | Spawn API    | ⭐⭐⭐      |

**진행 전략**:

1. 난이도 ⭐부터 시작 (revive_ticket 제일 간단)
2. 각 구현 후 `luac5.1 -p` 문법 검증
3. B41 vanilla Lua 소스 참고:
   - `https://raw.githubusercontent.com/t3qquq/myPZ-Configs/refs/heads/main/pz41_lua_source.txt`
   - (bash_tool curl로 다운로드 후 grep/awk로 탐색, web_fetch 비권장 — 파일 크기)

---

### **B. 앱: `profits.txt` → xlsx 통계 스크립트** (우선순위 중간)

**배경**:

- `profits.txt` 형식: 한 줄당 `<streamer PZ 사용자명>\t<rewards.txt 한 줄>` (raw line = `amount,featureId,sender,message`), CRLF
- 클라이언트가 티어 유효성과 무관하게 **모든** 후원을 `sendClientCommand("DonationStats","Record",...)`로 전송, 호스트가 `player:getUsername()`으로 라벨링
- 시즌 종료 후 이 파일을 정리해 수익 리포트 생성

**요구사항**:

- 입력: `profits.txt`
- 출력: 4-sheet xlsx
  - **Sheet1 (Summary)**: 스트리머별 총 수익, 티어별 기여도
  - **Sheet2 (Daily)**: 날짜별 누적 수익 (시계열)
  - **Sheet3 (Top Donors)**: 상위 후원자 (sender별)
  - **Sheet4 (Raw)**: 전체 기록 (filters 포함)
- 기술: Python `openpyxl` 또는 `pandas` + `xlsxwriter`
- 스크립트: `stats_generator.py` (독립 실행 가능, cli 파라미터 받음)
- **상태**: 포맷 확정, 아직 미착수

**예상 코드량**: ~200–300 lines (읽기 + 파싱 + 표 생성)

---

### **C. 기타 개선 (낮은 우선순위)**

#### 퐁듀

- 🔄 Naver 자동 로그인 (19+ 시 PyQtWebEngine 임베드 웹뷰) — 비기술 사용자 UX 개선
- 🔄 코드 서명 (AV 경고 감소)

#### 모드

- `bandit.lua` NPC 킬 로직: 현재 클라이언트 사이드(`HitmanZombie.GetAll()`) — 서버사이드 Kaboom 핸들러로 이전 검토 중 (서버 컨텍스트에서 `HitmanZombie.GetAll()` 사용 가능 여부 확인 필요)
- 🗑 dead code cleanup ("나중에 다이어트"):
  - `rewardManager.lua` 큐 함수 (`.b` / `.c`)
  - `ManageSocialDistance` 호출
  - `HitmanMenu.lua` 스탈 메뉴 엔트리 (Looter / Companion)

---

## 🔧 개발 참조

### 소스 저장소

| 이름               | URL                                                                                       | 용도                                |
| ------------------ | ----------------------------------------------------------------------------------------- | ----------------------------------- |
| PZ B41 Vanilla Lua | https://raw.githubusercontent.com/t3qquq/myPZ-Configs/refs/heads/main/pz41_lua_source.txt | 엔진 API 탐색 (bash_tool curl 권장) |
| 모드 소스 (최신)   | https://github.com/t3qquq/Chzzk-Zomboid-Donation-Mod                                      | featureId 구현 대상                 |
| 앱 소스            | https://github.com/t3qquq/Chzzk-Zomboid-Donation-App                                      | 티어/프리셋 UI                      |

### 빌드 / 배포

```bash
# 모드: Lua 문법 검증
luac5.1 -p t3chzzkDonation/media/lua/client/...lua

# 앱: exe 빌드
cd [퐁듀 폴더]
build.bat
# → dist/PongDu.exe
```

- ✅ 앱 저장소 `build.bat` 최신화 완료: `--name PongDu --icon=pongdu.ico --add-data "pongdu.ico;." --add-data "opt_conf;opt_conf"` (PZ 원클릭 최적화용 class 패치 9종 번들 포함) → `dist/PongDu.exe`

### 테스트 서버

- **설정**: 로컬 싱글플레이 또는 localhost 멀티플레이
- **검증 포인트**:
  1. `rewards.txt` 라인 추가 확인
  2. 모드 콘솔 메시지 (DonationReceiver 파싱)
  3. 게임 이펙트 발동 (히트맨/폭격/텔레포트/스킬 물약 등)

---

## 📊 진행 요약

| 영역              | 완료율   | 비고                                                     |
| ----------------- | -------- | -------------------------------------------------------- |
| 인프라 (양쪽)     | 100%     | 통신 규약 + 런처 완성                                    |
| 기능 구현 (모드)  | 72%      | 13/18 완료 (mutant_spawn 포함), 5개 스텁 대기            |
| UI 편의 (앱)      | 100%     | 티어 편집/프리셋 import/export/잠금 완료                 |
| 통계 도구 (앱)    | 0%       | profits.txt → xlsx 미착수 (포맷은 확정)                  |
| **프로젝트 전체** | **~78%** | 모드 스텁 5개가 남은 큰 덩어리 (부활 지속성은 구현 완료, 검증 대기) |

---

## 📝 주의사항

### PZ B41 멀티플레이어 권한

- `IsoZombie`는 클라이언트 소유(owner `UdpConnection`) — 서버사이드 상태 변경은 소유 클라이언트 동기화 패킷에 덮어써짐
- 반드시 서버 → 브로드캐스트 → 각 클라이언트가 자신의 좀비만 킬

### PZ 스크립트 파일 포맷 (`media/scripts/*.txt`)

- `/* */` 블록 주석만 지원, `--`(Lua 스타일) 주석은 무효 — 파서가 바로 다음 아이템 블록 전체를 삼켜버림

### 한글 처리

- Lua 소스 내 직접 UTF-8 한글 리터럴 **사용 금지** → `\ddd` 바이트 이스케이프 또는 `getText()` 키 사용
- 번역 파일 (`IG_UI_*.txt`): UTF-16 BE + CRLF 필수

### modData 네임스페이싱

- 키 충돌 = 2틱마다 크로스모드 데이터 삭제 (조용히 발생 — Lua 전역 충돌보다 위험)
- 항상 모드 접두사 사용 (예: `hitmanBrain`, `hitmanZid`, `hitmanPreserve`)

### 기타

- `getGameVersion()`은 숫자가 아닌 Java 객체 반환 — 숫자 비교에 절대 사용 금지, B41 상수 하드코딩
- `DebugLog`는 콜러블 함수가 아닌 Java 클래스 객체 — `DebugLog(...)` 호출 시 `RuntimeException`
- Passive 스킬(근력/지구력) 만렙: `AddXP()`보다 `LevelPerk()` x10이 더 안정적

---

## 🎯 다음 단계

**즉시**: 부활 지속성 인게임 최종 검증 — 부활 후 능력 유지 + 서버 재부팅 자동부활 억제 확인 (`RiseUp:` srvlog / `MutantReviveDebug` 클라 로그로 관측)
**단기**: 모드 스텁 1개 (revive_ticket, 가장 간단) 구현 → random_weapon
**중기**: vehicle_kit, secret_passage_kit, horde_night 완료
**후기**: profits.txt → xlsx 스크립트
