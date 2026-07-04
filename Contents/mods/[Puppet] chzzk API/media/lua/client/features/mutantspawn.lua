local _a = {}

local zone   = require("utils/zone")
local global = require("global")

-- ═══════════════════════════════════════════════════════════════════════════
--  뮤턴트 (mutant_spawn): 스크리머 / 브루트 / 로치 중 1마리 랜덤 소환.
--
--  CDDA Zombies 모드에서 스크리머·브루트의 동작 로직만 떼어 자체 이식했다
--  (밴딧 -> 히트맨 이식과 동일 방식). CDDA 모드 의존성 없음 — 타입 배정도
--  CDDA의 CZList/RequestZombieType 대신 modData["PuppetMutant"] 하나로 처리.
--
--    스크리머 : HP 1, 일반 걸음. 타깃이 생기면 주기적으로 비명
--               (mutant_scream1/2 재생 + 반경 50 월드사운드로 주변 좀비 유인).
--               CDDA_ZombieFunction.Scream 이식.
--    브루트   : HP 3, 스프린터, 괴력(Strength=1), 넉다운 면역(keepstand),
--               공격 중 플레이어를 밀쳐냄(attackFromWindowsLunge).
--               CDDA_ZombieFunction.Push + keepstand 이식.
--    로치     : HP 1, 크롤 전용 + 크롤 속도 3배. 자체 제작 —
--               AnimSets/zombie-crawler/*/roach_*.xml 노드가 PuppetRoach
--               애님 변수 조건으로 3배속 크롤을 재생 (조건 수가 많은 노드가
--               우선 선택되는 PZ 애님 규칙, Hitman 애님 변형과 동일 기법).
--
--  권한 구조: 좀비는 클라이언트 권한이므로 서버는 스폰 + modData 마킹만 하고
--  (server.lua MutantSpawn 핸들러), 실제 스탯/행동은 각 클라이언트의
--  OnZombieUpdate 적용기가 처리한다. 좀비 스트리밍/재사용으로 애님 변수가
--  풀리면 PuppetMutantInit 가드가 리셋되므로 다음 틱에 자동 재적용된다.
-- ═══════════════════════════════════════════════════════════════════════════

local KINDS = { "screamer", "brute", "roach" }

local haloKey = {
    screamer = "IGUI_donation_mutant_screamer",
    brute    = "IGUI_donation_mutant_brute",
    roach    = "IGUI_donation_mutant_roach",
}

-- 비명 쿨다운(ms, 실시간). CDDA는 인게임 5분(기본 낮길이 기준 실시간 ~12.5초)
-- 주기였는데, 인게임 분 카운터 동기화 기계장치 대신 실시간 쿨다운으로 단순화.
local SCREAM_COOLDOWN_MS = 15000
local _nextScream = {}   -- [onlineID] = 다음 비명 허용 시각(ms). 클라 로컬.

-- 도네 발동 진입점 (rewardManager가 안전지대 대기까지 끝낸 뒤 호출).
-- 종류를 클라에서 굴리고, 좌표와 함께 서버에 스폰 요청. [public name: .a]
function _a.a(sender)
    local player = getPlayer()
    if not player then return end
    local kind = KINDS[ZombRand(#KINDS) + 1]
    sendClientCommand("PEvents", "MutantSpawn", {
        ["ZedX"]   = player:getX() + zone.b(),
        ["ZedY"]   = player:getY() + zone.b(),
        ["ZedZ"]   = player:getZ(),
        ["kind"]   = kind,
        ["sender"] = sender or "",
    })
    local key = haloKey[kind]
    if key then
        player:setHaloNote(getText(key), 255, 70, 70, 300)
    end
end

-- ── 1회 초기화 (클라별) ───────────────────────────────────────────────────────
-- 스탯류는 매 틱 재적용하면 안 되는 것들이라 PuppetMutantInit 애님 변수로
-- 가드. 변수는 좀비가 스트림 아웃되면 리셋 -> 다시 로드될 때 자동 재초기화.
local function initMutant(zombie, kind)
    if kind == "brute" then
        -- 괴력: CDDA_UpdateZombie와 동일하게 샌드박스 스왑 + DoZombieStats.
        local origStr = getSandboxOptions():getOptionByName("ZombieLore.Strength"):getValue()
        getSandboxOptions():set("ZombieLore.Strength", 1)   -- 1 = Superhuman
        zombie:DoZombieStats()
        getSandboxOptions():set("ZombieLore.Strength", origStr)
        zombie:setWalkType("sprint" .. tostring(ZombRand(5) + 1))
        zombie:setHealth(3.0)          -- CDDA Brute HP=3. DoZombieStats 뒤에 설정
    elseif kind == "screamer" then
        zombie:setHealth(1.0)          -- CDDA Screamer HP=1. 걸음은 기본값 유지
    elseif kind == "roach" then
        zombie:setHealth(1.0)
        zombie:setVariable("PuppetRoach", true)
        -- 타입2 크롤 변형 노드(CrawlerType==2, 조건 2개)와의 조건 수 동률을
        -- 없애기 위해 크롤 타입을 1로 고정 -> roach 노드가 항상 최다 조건.
        zombie:setVariable("CrawlerType", "1")
    end
    zombie:setVariable("PuppetMutantInit", true)
end

-- ── 스크리머: 비명 (CDDA_ZombieFunction.Scream 이식) ─────────────────────────
-- playSound는 클라 로컬 렌더링이라 각 클라가 각자 재생 = 전원이 들림.
-- addSound(월드사운드)는 각 클라가 자기 소유 좀비를 유인 -> 폭격(bombard)과
-- 같은 분산 처리 구조라 클라별 실행이 정답.
local function updateScreamer(zombie)
    local target = zombie:getTarget()
    if not target then return end
    local zid = zombie:getOnlineID()
    local now = getTimestampMs()
    if _nextScream[zid] and now < _nextScream[zid] then return end
    _nextScream[zid] = now + SCREAM_COOLDOWN_MS
    local player = getPlayer()
    if player and not player:HasTrait("Deaf") then
        zombie:playSound("mutant_scream" .. tostring(ZombRand(2) + 1))
    end
    -- 소스=좀비: 바닐라 addSound 패턴. 소스 본인은 월드사운드에 반응하지
    -- 않으므로 스크리머가 자기 비명을 쫓아가는 일도 자연 차단된다.
    addSound(zombie, zombie:getX(), zombie:getY(), zombie:getZ(), 50, 50)
end

-- ── 브루트: 넉다운 면역 + 밀치기 (keepstand + Push 이식) ─────────────────────
-- attackFromWindowsLunge는 플레이어 객체를 직접 밀쳐내므로 로컬 플레이어에게만
-- 적용 (CDDA는 이 가드가 없는데, 원격 플레이어 프록시에 걸면 무의미/부정확).
local function updateBrute(zombie)
    zombie:setKnockedDown(false)
    if zombie:isAttacking() then
        local target = zombie:getTarget()
        if target and instanceof(target, "IsoPlayer") and target:isLocalPlayer() then
            target:attackFromWindowsLunge(zombie)
        end
    end
end

-- ── 로치: 크롤 상태 유지 ─────────────────────────────────────────────────────
-- CDDA_UpdateZombie의 walktype 4 처리와 동일 패턴 — 상태가 풀려도 매 틱 복구.
local function updateRoach(zombie)
    if not zombie:isCrawling() then
        zombie:toggleCrawling()
    end
    zombie:setFallOnFront(true)
    zombie:setCanWalk(false)
end

-- ── 적용기 본체 ───────────────────────────────────────────────────────────────
-- 서버발 zombie transmitModData는 클라이언트에 전달되지 않으므로, 서버가
-- sendServerCommand("PEvents","MutantMark")로 쏜 zedId+kind를 받아두고
-- OnZombieUpdate에서 onlineID로 매칭한다 (폭격 NearbyExplosion과 같은 채널).
-- modData 경로는 SP/호스트 겸용 폴백으로 유지.
local _pending = {}   -- [onlineID] = kind

Events.OnServerCommand.Add(function(module, command, args)
    if module == "PEvents" and command == "MutantMark" then
        local zid  = args and tonumber(args["zedId"])
        local kind = args and args["kind"]
        if zid and kind then
            _pending[zid] = kind
        end
    end
end)

local function applyMutant(zombie)
    local kind = zombie:getModData()["PuppetMutant"] or _pending[zombie:getOnlineID()]
    if not kind then return end
    if zombie:getVariableBoolean("Hitman") then return end   -- NPC 오염 방지
    if not zombie:getVariableBoolean("PuppetMutantInit") then
        initMutant(zombie, kind)
    end
    if kind == "screamer" then
        updateScreamer(zombie)
    elseif kind == "brute" then
        updateBrute(zombie)
    elseif kind == "roach" then
        updateRoach(zombie)
    end
end
Events.OnZombieUpdate.Add(applyMutant)

-- 죽으면 로컬 마크/쿨다운 정리
Events.OnZombieDead.Add(function(zombie)
    local zid = zombie:getOnlineID()
    _pending[zid] = nil
    _nextScream[zid] = nil
end)

return _a
