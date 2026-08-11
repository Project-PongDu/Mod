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
function PongDuCompat.isOwnedZombie(zombie)
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

PongDuCompat.patchRandomZombies()
Events.OnGameStart.Add(PongDuCompat.patchRandomZombies)
Events.OnServerStarted.Add(PongDuCompat.patchRandomZombies)
