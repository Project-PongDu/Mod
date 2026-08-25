-- ═══════════════════════════════════════════════════════════════════════════
--  Random Zombies - Day and Night (workshop id: RandomZombiesFull) 호환 패치
--
--  [문제]
--  RZ는 OnTick에서 getCell():getZombieList() 전수를 돌며, onlineID 해시로
--  좀비를 속도/체력/인지 버킷에 배정하고 매 주기(기본 7.5초)마다 강제로
--  덮어쓴다. 덮어쓰기 경로가 makeInactive(true/false) -> DoZombieStats()인데,
--  DoZombieStats()는 마지막에 walkType을 speedType 기준으로 무조건 재생성한다
--  (IsoZombie.java:2643). 즉 퐁듀가 setWalkType("sprintN")으로 준 뜀걸음이
--  통째로 날아간다. cognition 재배정 경로(updateCognition)도 DoZombieStats를
--  루프로 돌려 같은 결과를 낸다. 체력도 distribution.normal ~= 100이면 매 주기
--  버킷값으로 setHealth 된다.
--
--  퐁듀 특수좀비의 스탯은 PuppetMutantInit 가드로 "1회만" 적용되므로,
--  RZ의 무한 재적용이 항상 이긴다 -> 소환 직후엔 정상, 수 초 뒤 일반 좀비화.
--
--  [해결]
--  RZ의 rzf_zombiesManager 모듈 테이블을 require로 가져와(PZ의 require는
--  LuaManager.RunLuaInternal의 loaded/loadedReturn 캐시를 타므로 RZ 본체가
--  잡고 있는 것과 동일 인스턴스다) updateZombie를 래핑한다. 퐁듀 소유 좀비면
--  원본을 호출하지 않고 즉시 반환 -> RZ가 해당 좀비를 아예 인식하지 못한다.
--  updateAllZombies가 zombiesManager.updateZombie를 테이블 필드로 조회하므로
--  로드 순서와 무관하게 적용된다. RZ 미설치 시 require가 nil을 반환하고
--  패치는 no-op이다.
--
--  이 파일이 lua/server에 있는 이유: B41 클라이언트는 media/lua/server도
--  전부 로드하며, RZ 역시 클라/서버 양쪽에서 각각 OnTick 루프를 돌린다.
--  한 파일로 양쪽을 동시에 덮는다.
-- ═══════════════════════════════════════════════════════════════════════════

PongDuCompat = PongDuCompat or {}

-- 퐁듀가 스탯 소유권을 주장하는 좀비 판별.
--   PuppetMutant  : 뮤턴트 4종(screamer/brute/roach/tracer) + 스프린터
--                   (mutant_spawn, zombie_rain, sprinter5 부활 경로 공통 마커)
--   isSprinter    : server.lua makeSprinter 경로
--   hitmanBrain   : 히트맨 NPC (좀비 객체를 NPC로 쓰므로 체력/크롤 개입 시 파손)
--   Hitman 변수   : 브레인 부착 전/후 과도 구간 방어
-- 영구 소유(개체 정체성 자체가 퐁듀 것). 블러드문처럼 "한시적으로 스탯만
-- 빌려 쓰는" 마커는 여기 포함하지 않는다 -- 블러드문이 매 스윕 재변환 대상을
-- 고를 때 이 함수를 쓰기 때문에, 자기 마커까지 여기서 걸리면 한 번 변환된
-- 좀비를 두 번 다시 못 건드린다(스트리밍 아웃/인으로 speedType 이 리셋돼도
-- 복구 불가).
function PongDuCompat.isSpecialZombie(zombie)
    if not zombie then return false end
    local md = zombie:getModData()
    if md then
        if md["PuppetMutant"] then return true end
        if md["isSprinter"] then return true end
        if md["hitmanBrain"] then return true end
    end
    if zombie:getVariableBoolean("Hitman") then return true end
    return false
end

-- RZ 제외 판정용. 영구 소유 + 한시적 스탯 점유(블러드문)를 모두 포함한다.
-- 블러드문 마커는 이벤트 종료 시 지워지고, 그때부터 RZ 가 회수해간다.
function PongDuCompat.isOwnedZombie(zombie)
    if PongDuCompat.isSpecialZombie(zombie) then return true end
    if not zombie then return false end
    local md = zombie:getModData()
    if md and md["PongDuBloodMoon"] then return true end
    return false
end

function PongDuCompat.patchRandomZombies()
    if PongDuCompat.rzPatched then return end

    local ok, rzf = pcall(require, "rzf_zombiesManager")
    if not ok or type(rzf) ~= "table" or type(rzf.updateZombie) ~= "function" then
        print("[PongDuCompat] RandomZombies not present - no patch needed")
        return
    end

    local original = rzf.updateZombie
    rzf.updateZombie = function(zombie, distribution, speedType, cognition)
        if PongDuCompat.isOwnedZombie(zombie) then
            return true   -- RZ 원본의 "skipped" 반환값과 동일
        end
        return original(zombie, distribution, speedType, cognition)
    end

    PongDuCompat.rzPatched = true
    print("[PongDuCompat] RandomZombies detected - updateZombie wrapped, PongDu zombies excluded")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  BLTRandomZombies (workshop id: BLTRandomZombies) 호환 패치
--
--  [문제]
--  RZ와 동일한 원리다. OnTick에서 셀 좀비 전수를 훑으며 onlineID 해시로
--  속도/체력/인지 버킷을 배정하고, makeInactive(true/false)로 DoZombieStats()를
--  강제 호출한다(IsoZombie.java:4079). DoZombieStats()는 speedType 기준으로
--  walkType을 무조건 재생성하므로(2644) 퐁듀가 준 sprintN이 날아간다.
--
--  [RZ 방식이 안 통하는 이유]
--  RZ는 갱신 함수가 rzf_zombiesManager.updateZombie라는 모듈 테이블 필드라
--  래핑이 가능했다. BLT는 updateZombies / updateZombiesTick이 전부 파일 로컬
--  업밸류고, BLTRandomZombies 테이블에는 진단용 함수만 노출돼 있어 좀비 1마리
--  단위로 끼어들 지점이 없다.
--
--  [대신 쓰는 구멍: BLT 자신의 스킵 캐시]
--  BLT는 같은 좀비를 매 사이클 재처리하지 않으려고 좀비 modData에 세대번호와
--  마지막 좌표를 박아둔다(randomzombies_server.lua:589~596):
--
--      if modData.BLTgen == currentGen and diffX < 20 and diffY < 20 and diffZ < 1
--      then skipped else <스탯 덮어쓰기> end
--
--  즉 퐁듀 좀비의 modData에 "이번 세대에 이미 처리했다"고 미리 찍어두면 BLT는
--  그 좀비를 건드리지 않고 지나간다. 사후 복구가 아니라 원천 차단이라 RZ
--  패치와 동일하게 깜빡임이 없다.
--
--  [세대번호를 알아내는 법]
--  generation은 로컬이라 직접 못 읽지만, BLT가 방문한 모든 좀비에 nextGen을
--  찍어두므로 셀에서 역으로 읽어낼 수 있다. 패스 시작 시점 기준으로
--    - 직전 패스에서 방문된 좀비 : BLTgen == 이번 currentGen
--    - 오래 전 값이 남은 좀비    : 그보다 작음
--    - currentGen보다 큰 값      : 존재 불가 (아직 아무도 방문 안 됨)
--  이므로 "non-nil BLTgen의 최댓값 == currentGen"이 성립한다.
--
--  패스 시작 시점을 잡는 훅으로는 makeDistribution을 쓴다. 이건 테이블 필드로
--  호출되고(:789 cacheDist = Lib.makeDistribution()), 좀비를 하나라도 처리하기
--  전에 불리며, 진행 중인 패스가 남아 있으면 그 위쪽에서 early return 되므로
--  "패스 1회당 정확히 1번"이 보장된다.
-- ═══════════════════════════════════════════════════════════════════════════

PongDuCompat.bltGen = nil   -- 마지막으로 관측한 BLT currentGen

-- 좀비 하나에 "이번 세대 처리 완료" 도장을 찍는다. 좌표까지 현재 칸으로
-- 맞춰야 20타일 이동 검사에도 안 걸린다. BLT 미설치거나 아직 세대를 모르면
-- 아무것도 안 한다(no-op).
function PongDuCompat.bltStamp(zombie)
    local gen = PongDuCompat.bltGen
    if not gen or not zombie then return end
    local sq = zombie:getCurrentSquare()
    if not sq then return end
    local md = zombie:getModData()
    md.BLTgen = gen
    md.BLTx = sq:getX()
    md.BLTy = sq:getY()
    md.BLTz = sq:getZ()
end

local function bltOnPassStart()
    local cell = getCell()
    if not cell then return end
    local zeds = cell:getZombieList()
    if not zeds then return end

    -- ① 이번 패스의 currentGen 관측 (non-nil BLTgen 최댓값)
    local gen = nil
    local n = zeds:size()
    for i = 0, n - 1 do
        local g = zeds:get(i):getModData().BLTgen
        if g and (not gen or g > gen) then gen = g end
    end
    if not gen then return end   -- BLT가 아직 한 바퀴도 안 돌았다
    PongDuCompat.bltGen = gen

    -- ② 퐁듀 소유 좀비에 선제 도장
    local marked = 0
    for i = 0, n - 1 do
        local z = zeds:get(i)
        if PongDuCompat.isOwnedZombie(z) then
            PongDuCompat.bltStamp(z)
            marked = marked + 1
        end
    end
    if marked > 0 and not PongDuCompat.bltLogged then
        PongDuCompat.bltLogged = true
        print("[PongDuCompat] BLTRandomZombies skip-cache stamping active (gen=" ..
            tostring(gen) .. ", marked=" .. tostring(marked) .. ")")
    end
end

function PongDuCompat.patchBLTRandomZombies()
    if PongDuCompat.bltPatched then return end
    if type(BLTRandomZombies) ~= "table"
        or type(BLTRandomZombies.makeDistribution) ~= "function" then
        print("[PongDuCompat] BLTRandomZombies not present - no patch needed")
        return
    end

    local original = BLTRandomZombies.makeDistribution
    BLTRandomZombies.makeDistribution = function(...)
        -- 스탬핑이 터져도 BLT 본체는 정상 동작해야 한다.
        local ok, err = pcall(bltOnPassStart)
        if not ok then
            print("[PongDuCompat] BLT stamp error: " .. tostring(err))
        end
        return original(...)
    end

    PongDuCompat.bltPatched = true
    print("[PongDuCompat] BLTRandomZombies detected - makeDistribution wrapped, PongDu zombies pre-stamped")
end

-- 로드 시점 즉시 시도는 하지 않는다. BLT의 randomzombies_server.lua가 우리보다
-- 늦게 로드되면 function Lib.makeDistribution 정의가 래퍼를 덮어쓰기 때문.
-- 모든 파일 로드가 끝난 뒤인 OnGameStart에서만 건다.
PongDuCompat.patchRandomZombies()
Events.OnGameStart.Add(PongDuCompat.patchRandomZombies)
Events.OnServerStarted.Add(PongDuCompat.patchRandomZombies)
Events.OnGameStart.Add(PongDuCompat.patchBLTRandomZombies)
