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

local KINDS = { "screamer", "brute", "roach", "tracer" }

local haloKey = {
    screamer = "IGUI_mutant_name_screamer",
    brute    = "IGUI_mutant_name_brute",
    roach    = "IGUI_mutant_name_roach",
    tracer   = "IGUI_mutant_name_tracer",
}

-- 소환 외침: 욕(SWEAR) + 종류(mutateType) + 마무리(ENDMENT) 3파트를 랜덤 조합.
-- 예) "시발, 브루트잖아!" / "젠장, 로치 출현!"  (ENDMENT 쪽에 필요한 공백을 미리 포함시켜둠)
local SWEAR_KEYS = {
    "IGUI_mutant_swear_1", "IGUI_mutant_swear_2", "IGUI_mutant_swear_3",
    "IGUI_mutant_swear_4", "IGUI_mutant_swear_5", "IGUI_mutant_swear_6",
    "IGUI_mutant_swear_7", "IGUI_mutant_swear_8", "IGUI_mutant_swear_9",
    "IGUI_mutant_swear_10",
}
local ENDMENT_KEYS = {
    "IGUI_mutant_endment_1", "IGUI_mutant_endment_2", "IGUI_mutant_endment_3",
    "IGUI_mutant_endment_4", "IGUI_mutant_endment_5", "IGUI_mutant_endment_6",
    "IGUI_mutant_endment_7",
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
        local swear   = getText(SWEAR_KEYS[ZombRand(#SWEAR_KEYS) + 1])
        local endment = getText(ENDMENT_KEYS[ZombRand(#ENDMENT_KEYS) + 1])
        local msg = swear .. ", " .. getText(key) .. endment
        processShoutMessage(msg)
        addSound(player, player:getX(), player:getY(), player:getZ(), 30, 30)
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
    elseif kind == "sprinter" then
        -- 부활한 뛰좀 재적용 경로 (원 스폰은 서버 makeSprinter가 처리)
        zombie:setWalkType("sprint" .. tostring(ZombRand(5) + 1))
    elseif kind == "tracer" then
        -- 트레이서: 스프린터 워크타입 + 실제 이동속도.
        -- ※주의(2차 정정): zombie.speedType = 1 은 크래시남(x13 리포트) -
        -- speedType은 registerVariableCallbacks()에 안 걸린 순수 Java int
        -- 필드라 Lua 점(dot) 대입 자체가 불가(Kahlua tableSet 실패, non-table).
        -- 실이동속도의 진짜 원인은 speedType이 아니라 DoZombieSpeeds()가
        -- 갱신하는 AnimFrameIncrease였으므로 그쪽만 직접 호출하면 충분하다.
        zombie:setWalkType("sprint" .. tostring(ZombRand(5) + 1))
        zombie:DoZombieSpeeds(2)
    end
    print("[PuppetMutant] init " .. tostring(kind) .. " zid=" .. tostring(zombie:getOnlineID()))
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

-- ── 트레이서: 파쿠르 시스템 ─────────────────────────────────────────────────
-- 검증된 워크샵 모드 3종을 트레이서 전용으로 게이팅해 이식:
--   Vaulting Zombies      : 낮은담장/창문 클라임 애님을 볼트로 교체
--                           (climbfence·climbwindow TR* 노드, 여기선 Sprint 버전)
--   Stay Away From Windows: 충돌한 닫힌 창문 즉시 파괴 (OnObjectCollide)
--   ZombieClimbsWall      : 높은담장(FenceTypeHigh) 클라임 (hitreaction TR* 노드
--                           + anims_X/Zombie/TR_ClimbWall_*.X 에셋)
-- + DiveThroughWindows의 창문 볼트 트릭: 창문을 깬 직후 climbOverFence를 직접
--   호출하면 climbfence 스테이트가 창문 개구부를 '담장'처럼 취급해 볼트로
--   관통한다 (스테이트의 isIgnoreCollide가 시작-도착 스퀘어 간 충돌을 무시).
-- 파쿠르 실패는 전 구간 0%: climbfence/climbwindow outcome을 매 틱 success로
-- 강제하고(트립·런지 차단), 높은담장 클라임은 확률 굴림 없이 무조건 Success.

-- 이벤트 핸들러(OnObjectCollide 등)용 트레이서 판별. applyMutant 경로 밖에서도
-- 쓰이므로 modData 직조회 + 풀 재활용 스테일 가드(Zid 대조)를 그대로 적용.
local function isTracer(zombie)
    local md = zombie:getModData()
    return md["PuppetMutant"] == "tracer"
        and md["PuppetMutantZid"] == zombie:getOnlineID()
end

-- ── 트레이서: 높은담장 클라임 (ZombieClimbsWall 이식, 리키잉 버전) ──────────
-- ※핵심 교훈: 진행 판정을 hitreaction 문자열로 하면 안 된다. hitreaction은
--   MP 동기화 변수(NetworkVariables.HitReaction)인 데다 ZombieHitReactionState.
--   exit()가 ""로 강제 클리어할 수 있어서, 상태 키로 쓰면 지워지는 순간
--   TRClimbWallStarted=true만 영구 잔류하는 데드락에 빠진다 (담장 앞에서
--   '아직 넘는 중'처럼 굳는 증상). 원본 ZombieClimbsWall처럼 진행 판정은
--   Started 변수로만 하고, hitreaction은 매 틱 재주입해 자가복구시킨다.
local function updateTracerWallClimb(zombie)
    -- 담장 볼트/창문 통과 스테이트 중에는 벽클라임 로직 전체 배제
    -- (해당 스테이트도 collidable을 만지므로 아래 정리 분기와 간섭 금지)
    local st = zombie:getCurrentState()
    if st == ClimbOverFenceState.instance()
        or st == ClimbThroughWindowState.instance() then
        return
    end

    -- [진행 구간] Start 애님 종료(Started=true) ~ Success 애님 종료
    if zombie:getVariableBoolean("TRClimbWallStarted") then
        zombie:setVariable("bPathfind", false)
        zombie:setVariable("bMoving", true)
        if zombie:isCollidable() then zombie:setCollidable(false) end
        -- 트레이서는 100% 성공: 굴림 없이 즉시 Success 노드 조건 재주입.
        -- 엔진이 hitreaction을 지워도 다음 틱에 복구된다.
        if not zombie:isVariable("hitreaction", "TRClimbWallReactionSuccess") then
            zombie:setVariable("hitreaction", "TRClimbWallReactionSuccess")
        end
        return
    end

    -- [정리 구간] Started=false인데 collidable이 꺼져 있으면 Success 애님이
    -- 방금 끝난 것 -> 관통 상태 복구 + hitreaction 잔여값 제거
    if not zombie:isCollidable() then
        zombie:setCollidable(true)
        if zombie:isVariable("hitreaction", "TRClimbWallReactionSuccess") then
            zombie:setVariable("hitreaction", nil)
        end
        return
    end

    -- [트리거 스캔] 전방 3타일 박스에서 FenceTypeHigh 탐색 -> 정면 응시 유도
    -- -> 충돌 프레임에 발동 (원본 ClimbWallFunction 이식). 이 지점은
    -- Started=false 확정 구간이므로 재트리거가 항상 열려 있다.
    if zombie:isOnFloor() or zombie:isStaggerBack() then return end
    if not zombie:getTarget() then return end
    local baseSq = zombie:getCurrentSquare()
    if not baseSq then return end

    local fdx, fdy, countX, countY
    if zombie:getForwardDirection():getX() >= 0 then
        fdx, countX = math.ceil(zombie:getForwardDirection():getX()), 1
    else
        fdx, countX = math.floor(zombie:getForwardDirection():getX()), -1
    end
    if zombie:getForwardDirection():getY() >= 0 then
        fdy, countY = math.ceil(zombie:getForwardDirection():getY()), 1
    else
        fdy, countY = math.floor(zombie:getForwardDirection():getY()), -1
    end

    local cell = getCell()
    for x = 0, fdx + countX * 3, countX do
        for y = 0, fdy + countY * 3, countY do
            local square = cell:getGridSquare(baseSq:getX() + x, baseSq:getY() + y, baseSq:getZ())
            if square then
                local objects = square:getObjects()
                for i = 0, objects:size() - 1 do
                    local object = objects:get(i)
                    local properties = object:getProperties()
                    if properties and properties:Val("FenceTypeHigh") then
                        -- 경로탐색이 담장을 우회하지 않도록 직진 상태로 고정
                        if zombie:getVariableBoolean("bPathfind")
                            or not zombie:getVariableBoolean("bMoving") then
                            zombie:setVariable("bPathfind", false)
                            zombie:setVariable("bMoving", true)
                        end
                        if not zombie:isFacingObject(object, 0.5) then
                            zombie:faceThisObject(object)
                        end
                        if zombie:isCollidedThisFrame()
                            and zombie:isFacingObject(object, 0.5) then
                            zombie:setVariable("hitreaction", "TRClimbWallReactionStart")
                        end
                        return
                    end
                end
            end
        end
    end
end

-- ── 트레이서: 창문 즉시파괴 + 볼트 관통 ─────────────────────────────────────
-- Stay Away From Windows(충돌 즉시 파괴) + DiveThroughWindows(볼트 관통) 결합.
-- 닫힌 창문은 충돌 이벤트가 뜨는 순간 깨고, 같은 프레임에 climbOverFence를
-- 호출해 thump/climbwindow를 거치지 않고 바로 Sprint 볼트로 통과한다.
-- (열린/이미 깨진 창문은 충돌이 발생하지 않고 AI가 climbwindow 스테이트로
--  진입 -> climbwindow/TR* 노드가 같은 Sprint 볼트 애님을 재생.)
local function onTracerCollide(character, collider)
    if not instanceof(character, "IsoZombie") then return end
    if not instanceof(collider, "IsoWindow") then return end
    if not isTracer(character) then return end
    if character:getVariableBoolean("ClimbingFence") then return end -- 볼트 중 재트리거 방지
    if collider:isBarricaded() then return end   -- 바리케이드는 바닐라 thump에 위임

    if not collider:IsOpen() and not collider:isSmashed() then
        if collider:isInvincible() then return end
        collider:smashWindow()
        collider:update()
    end

    -- 창문의 부착 방향(N창/W창)과 좀비 위치로 클라임 방향을 산출해 담장 볼트
    -- 강제. climbOverFence는 목적지 walkable만 검사하는 제네릭 경로라 좀비에
    -- 안전하다 (ClimbOverWallState 하드캐스트 크래시 경로와 무관).
    local wsq = collider:getSquare()
    local zsq = character:getCurrentSquare()
    if not wsq or not zsq or wsq:getZ() ~= zsq:getZ() then return end
    local dir
    if collider:getNorth() then
        dir = (zsq:getY() >= wsq:getY()) and IsoDirections.N or IsoDirections.S
    else
        dir = (zsq:getX() >= wsq:getX()) and IsoDirections.W or IsoDirections.E
    end
    character:climbOverFence(dir)
end
Events.OnObjectCollide.Add(onTracerCollide)

-- 피격 시 클라임 강제 해제 (ZombieClimbsWall FixClimbHit 이식) - 애님이 끊겨도
-- collidable=false로 남아 영구 관통 상태가 되는 것을 차단.
Events.OnHitZombie.Add(function(zombie)
    -- hitreaction은 피격 순간 엔진이 먼저 지웠을 수 있으므로 Started도 함께 본다
    if zombie:getVariableBoolean("TRClimbWallStarted")
        or zombie:isVariable("hitreaction", "TRClimbWallReactionStart")
        or zombie:isVariable("hitreaction", "TRClimbWallReactionSuccess") then
        zombie:setCollidable(true)
        zombie:setVariable("TRClimbWallStarted", false)
        zombie:setVariable("hitreaction", nil)
    end
end)

-- ── 트레이서: 매 틱 적용기 ──────────────────────────────────────────────────
local function updateTracer(zombie)
    -- climbfence/climbwindow TR* 애님 노드 게이팅용 (매 틱 세팅)
    zombie:setVariable("PuppetTracer", true)

    -- 밀치기/약한 피격 넉다운 면역 (브루트 keepstand와 동일 기법).
    -- 엔진이 넉다운을 강한 피격과 구분하는 별도 플래그를 안 두므로
    -- 전체 넉다운 면역이 된다.
    zombie:setKnockedDown(false)

    -- 낙하 무력화: DoLand()가 fallTime>50이면 확률로 bHardFall을 세워 엎어짐
    -- 분기를 태운다. 매 틱 억제해 착지 후 즉시 추격을 잇는다.
    if zombie:getVariableBoolean("bHardFall") then
        zombie:setVariable("bHardFall", false)
    end

    -- 파쿠르 실패 0%: 스테이트 enter()가 확정한 outcome(lunge/fall/obstacle)을
    -- 매 틱 success로 덮어쓴다 (OnZombieUpdate는 enter() 이후 실행 - 검증됨).
    -- 단 "falling"(반대편 바닥 없음)은 실패가 아니라 지형 낙하이므로 유지 -
    -- 덮어쓰면 허공에서 착지 모션이 재생된다.
    local state = zombie:getCurrentState()
    if state == ClimbOverFenceState.instance() then
        if not zombie:isVariable("ClimbFenceOutcome", "falling") then
            zombie:setVariable("ClimbFenceOutcome", "success")
        end
    elseif state == ClimbThroughWindowState.instance() then
        if not zombie:isVariable("ClimbWindowOutcome", "falling") then
            zombie:setVariable("ClimbWindowOutcome", "success")
        end
    end

    -- 폴백: 충돌 이벤트를 놓치고 thump 상태로 들어간 경우에도 창문은 즉시
    -- 파괴한다 (다음 프레임 충돌 볼트 or climbwindow로 자연 연결).
    local thumpTarget = zombie:getThumpTarget()
    if thumpTarget and instanceof(thumpTarget, "IsoWindow")
        and not thumpTarget:isDestroyed() then
        thumpTarget:smashWindow()
    end

    updateTracerWallClimb(zombie)
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
local _pending = {}   -- [onlineID] = { k=종류, s=후원자, e=만료시각(ms) }
local PENDING_MS = 120000   -- MutantMark 유효시간(2분). 이후엔 레지스트리(pid)로 재적용.

-- 만료 검사 겸용 리더. 만료된 항목은 즉시 제거 (ID 재활용 하이재킹 방지).
local function pendingEntry(zid)
    local p = _pending[zid]
    if not p then return nil end
    if type(p) == "table" and p["e"] and getTimestampMs() > p["e"] then
        _pending[zid] = nil
        return nil
    end
    return p
end

-- 영속 레지스트리: 서버가 특수좀비 탄생 시 글로벌 ModData "PuppetMutants"에
-- 정규화ID -> kind 로 등록해둔다 (server.lua registerMutant 참고). 이 ID는
-- 사망->시체->부활 내내 유지되므로 부활 좀비도 조회에 걸려 자동 재적용된다.
-- 모자 비트 마스킹까지 등록/조회가 같은 함수(HitmanUtils.GetZombieID)를 쓴다.
local _registry = {}  -- [정규화ID 문자열] = kind 또는 {k=종류, s=후원자}

-- 레지스트리/펜딩 항목 겸용 리더 (구버전 문자열 항목 호환)
local function regEntry(v)
    if type(v) == "table" then return v["k"], v["s"] end
    return v, nil
end

local function mutantKey(zombie)
    if HitmanUtils and HitmanUtils.GetZombieID then
        return tostring(HitmanUtils.GetZombieID(zombie))
    end
    return tostring(zombie:getPersistentOutfitID())
end

Events.OnReceiveGlobalModData.Add(function(name, data)
    if name == "PuppetMutants" and type(data) == "table" then
        _registry = data
        print("[PuppetMutant] registry received, entries follow")
        for k, v in pairs(_registry) do
            print("[PuppetMutant]   " .. tostring(k) .. " = " .. tostring(v))
        end
    end
end)
Events.OnGameStart.Add(function()
    ModData.request("PuppetMutants")
end)

-- 부활 마크: 서버 RiseUp이 특수좀비 시체를 판별하면 부활 위치+종류를
-- 브로드캐스트한다. 부활 좀비는 pid가 새로 발급돼 레지스트리 직조회가
-- 불가하므로, 클라가 마크 스퀘어(±1)의 미적용 좀비에게 능력을 재적용한다.
local _reviveMarks = {}   -- { {x,y,z,kind,expire}, ... }
local REVIVE_MARK_MS = 20000

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PEvents" then return end
    if command == "MutantMark" then
        local zid  = args and tonumber(args["zedId"])
        local kind = args and args["kind"]
        if zid and kind then
            -- 만료시각 포함: OnZombieDead가 안 뜨고 죽은 좀비의 스테일 항목이
            -- onlineID 재활용으로 새 좀비를 하이재킹하는 것을 차단.
            -- 만료 뒤 스트림-인 재적용은 레지스트리(pid)가 담당한다.
            _pending[zid] = { ["k"] = kind, ["s"] = args["sender"],
                              ["e"] = getTimestampMs() + PENDING_MS }
        end
    elseif command == "MutantRevive" then
        local x, y = tonumber(args and args["x"]), tonumber(args and args["y"])
        local kind = args and args["kind"]
        if x and y and kind then
            _reviveMarks[#_reviveMarks + 1] = {
                x = x, y = y, z = tonumber(args["z"]) or 0,
                kind = kind, sender = args["sender"],
                expire = getTimestampMs() + REVIVE_MARK_MS,
            }
            print("[PuppetMutant] revive mark " .. tostring(kind)
                .. " @" .. tostring(x) .. "," .. tostring(y)
                .. " key=" .. tostring(args["key"]))
        end
    elseif command == "MutantReviveDebug" then
        print("[PuppetMutant] riseup total=" .. tostring(args and args["total"])
            .. " pid-readable=" .. tostring(args and args["readable"])
            .. " special=" .. tostring(args and args["marked"]))
    end
end)

-- 마크 매칭: 마크 스퀘어 ±1 안의 좀비면 소모하고 종류 반환.
-- 같은 스퀘어에 이종 시체가 동시 부활하면 클라별 배정이 어긋날 수 있는
-- 알려진 한계가 있으나(드묾), 재등록으로 이후 사이클부터는 pid로 고정된다.
local function matchReviveMark(zombie)
    if #_reviveMarks == 0 then return nil end
    local zx = math.floor(zombie:getX())
    local zy = math.floor(zombie:getY())
    local zz = math.floor(zombie:getZ())
    local now = getTimestampMs()
    for i = #_reviveMarks, 1, -1 do
        local m = _reviveMarks[i]
        if now > m.expire then
            table.remove(_reviveMarks, i)
        elseif math.abs(m.x - zx) <= 1 and math.abs(m.y - zy) <= 1 and m.z == zz then
            table.remove(_reviveMarks, i)
            return m.kind, m.sender
        end
    end
    return nil
end

local function applyMutant(zombie)
    local md = zombie:getModData()
    local curZid = zombie:getOnlineID()
    -- ★풀 재활용 방어 (호드매니저 둔갑 근본원인): B41은 죽은 좀비의 IsoZombie
    -- 객체를 풀에 반환 후 새 좀비에 재사용하는데 modData가 안 지워진다. 죽은
    -- 특좀 객체가 호드 좀비로 재활용되면 md["PuppetMutant"]가 그대로 딸려와
    -- 새 좀비가 특좀으로 둔갑한다(서버 로그: 호드 시점 REG/MutantMark 전무인데
    -- 클라는 resolution 경로 없이 바로 init). md에 소유 onlineID를 함께 박아,
    -- 현재 좀비 zid와 다르면 스테일(재활용)로 간주하고 폐기한다.
    if md["PuppetMutant"] and md["PuppetMutantZid"] ~= curZid then
        print("[PuppetMutant] STALE md rejected kind=" .. tostring(md["PuppetMutant"])
            .. " mdZid=" .. tostring(md["PuppetMutantZid"]) .. " curZid=" .. tostring(curZid))
        md["PuppetMutant"] = nil
        md["PuppetMutantSender"] = nil
        md["PuppetMutantZid"] = nil
        zombie:setVariable("PuppetMutantInit", false)
    end
    local kind, sender = md["PuppetMutant"], md["PuppetMutantSender"]
    -- 서버 MutantMark(pending)가 권위값. 좀비 스트림-인이 MutantMark보다 먼저
    -- 도착한 경우 스테일 pending으로 오배정된 kind가 md에 캐시될 수 있는데,
    -- 진짜 마크가 도착하는 즉시 여기서 교정한다.
    local p = pendingEntry(curZid)
    if p then
        local pk, ps = regEntry(p)
        if pk and kind and pk ~= kind then
            print("[PuppetMutant] corrected " .. tostring(kind) .. " -> " .. tostring(pk)
                .. " zid=" .. tostring(curZid))
            kind, sender = pk, ps
            md["PuppetMutant"] = pk
            md["PuppetMutantSender"] = ps
            md["PuppetMutantZid"] = curZid
            zombie:setVariable("PuppetMutantInit", false)   -- 올바른 kind로 재초기화
        elseif not kind then
            kind, sender = pk, ps
        end
        -- ★1회용 소비: MutantMark는 "방금 스폰한 그 좀비"를 지목하는 일회성
        -- 신호다. 적용 즉시 항목을 지워야 onlineID 재활용으로 새 좀비가 죽은
        -- 특좀의 스테일 항목에 걸려 같은 종류로 둔갑하는 것을 막는다.
        _pending[curZid] = nil
    end
    -- pid(persistentOutfitID) 레지스트리 조회 경로 제거.
    -- persistentOutfitID는 좀비 고유 ID가 아니라 '옷차림' 공유 ID라, 이전에
    -- 등록된 특좀과 같은 옷을 입은 일반좀비(예: 호드매니저 소환분)가 같은
    -- key로 조회에 걸려 그 특좀 종류로 둔갑하는 오탐이 났다. 부활 판별은
    -- 서버가 시체 modData로 정확히 하고, 클라 능력적용은 아래 revive-mark로
    -- 처리하므로 pid 경로는 순수 오탐원 -> 완전 삭제.
    if not kind and zombie:isAlive()
        and not zombie:getVariableBoolean("PuppetMutantInit") then
        kind, sender = matchReviveMark(zombie)
        if kind then
            print("[PuppetMutant] resolved via REVIVE-MARK key="
                .. tostring(mutantKey(zombie)) .. " kind=" .. tostring(kind)
                .. " zid=" .. tostring(zombie:getOnlineID()))
        end
    end
    if not kind then return end
    -- 클라 로컬 캐시: 이후 조회/네임태그 렌더가 modData만 보면 되게.
    -- 소유 zid를 함께 박아 풀 재활용 스테일 판별의 기준으로 삼는다.
    if not md["PuppetMutant"] then md["PuppetMutant"] = kind end
    if sender and not md["PuppetMutantSender"] then md["PuppetMutantSender"] = sender end
    md["PuppetMutantZid"] = curZid
    if zombie:getVariableBoolean("Hitman") then return end   -- NPC 오염 방지
    if not zombie:getVariableBoolean("PuppetMutantInit") then
        initMutant(zombie, kind)
        _a.pokeTag(zombie)                             -- 소환/부활 직후 잠깐 표기
    end
    _a.pokeTagOnHover(zombie)                          -- 조준+마우스 올림
    if zombie:isAttacking() then                       -- 나를 공격 중일 때
        local t = zombie:getTarget()
        if t and instanceof(t, "IsoPlayer") and t:isLocalPlayer() then
            _a.pokeTag(zombie)
        end
    end
    if kind == "screamer" then
        updateScreamer(zombie)
    elseif kind == "brute" then
        updateBrute(zombie)
    elseif kind == "roach" then
        updateRoach(zombie)
    elseif kind == "tracer" then
        updateTracer(zombie)
    end
end
Events.OnZombieUpdate.Add(applyMutant)

-- 죽으면 로컬 마크/쿨다운 정리 + 서버에 사망 좌표 리포트.
-- 죽을 때 로컬 캐시만 정리한다.
-- (예전엔 좌표 death-mark를 서버로 보고했지만, 서버가 시체 modData를 직접
--  읽는 방식으로 바뀌어 death-mark 자체가 불필요해졌다. registry 폴백도
--  옷차림 pid 충돌로 일반좀비의 잘못된 death-mark를 유발하던 오탐원이라 제거.)
Events.OnZombieDead.Add(function(zombie)
    local zid = zombie:getOnlineID()
    _pending[zid] = nil
    _nextScream[zid] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  네임태그: 특수좀비 머리 위 표기 (CDDA CDDA_ShowZombieType 이식)
--  트리거(각 100프레임 페이드): ① 소환/부활 직후  ② 조준 중 마우스 올림
--  ③ 좀비가 로컬 플레이어 공격  ④ 좀비를 타격
--  표기: 후원자가 있으면 "%1의 %2" ("테스트후원자의 브루트"), 없으면 이름만.
-- ═══════════════════════════════════════════════════════════════════════════
local TAG_TTL = 300

local NAME_KEY = {
    screamer = "IGUI_mutant_name_screamer",
    brute    = "IGUI_mutant_name_brute",
    roach    = "IGUI_mutant_name_roach",
    sprinter = "IGUI_mutant_name_sprinter",
    tracer   = "IGUI_mutant_name_tracer",
}

local TAG_COLOR = {      -- 스크리머/브루트는 CDDA 원본 색, 로치는 바퀴 갈색
    brute    = {255, 0, 0},
    screamer = {139, 0, 81},
    roach    = {181, 101, 29},
    sprinter = {255, 165, 0},
    tracer   = {0, 200, 180},   -- 파쿠르 테마 청록
}

local _showTags = {}     -- [onlineID] = { zombie=, ttl=, tdo=TextDrawObject }

-- 서버 샌드박스 스위치. 기존 Donation_ShowPanel/PrepDelay와 동일하게
-- 사용 시점에 읽는다 (SandboxVars는 파일 로드 시점엔 비어있음).
local function nameTagEnabled()
    local sv = SandboxVars and SandboxVars.Hitmans
    if sv and sv.Donation_MutantNameTag == false then return false end
    return true      -- 옵션 없음(구버전 세이브) -> 기본값: 표시
end

-- CDDA_GetScreenXY 이식: 월드좌표 -> 화면좌표 (줌 보정 포함)
local function screenXY(zombie, offY)
    local sx = IsoUtils.XToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)
    local sy = IsoUtils.YToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)
    sx = sx - IsoCamera.getOffX() - zombie:getOffsetX()
    sy = sy - IsoCamera.getOffY() - zombie:getOffsetY() - offY
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom
end

local function pokeTag(zombie)
    if not nameTagEnabled() then return end
    local zid = zombie:getOnlineID()
    local t = _showTags[zid]
    if t then
        t.ttl = TAG_TTL
        t.zombie = zombie
    else
        _showTags[zid] = { zombie = zombie, ttl = TAG_TTL }
    end
end
_a.pokeTag = pokeTag

local function tagText(kind, sender)
    local name = getText(NAME_KEY[kind] or NAME_KEY.roach)
    if sender and sender ~= "" then
        return getText("IGUI_mutant_tag_owned", sender, name)
    end
    return name
end

-- 트리거 ②: 조준 중 마우스 올림 (applyMutant에서 특수좀비에 한해 호출)
local function pokeTagOnHover(zombie)
    local player = getPlayer()
    if not player or not player:IsAiming() then return end
    if not zombie:isAlive() or not player:CanSee(zombie) then return end
    local zx, zy = screenXY(zombie, 90)
    local mx, my = getMouseX(), getMouseY()
    if math.abs(zx - mx) < 15 and math.abs(zy - my) < 30 then
        pokeTag(zombie)
    end
end
_a.pokeTagOnHover = pokeTagOnHover

-- 트리거 ④: 타격 시 (CDDA_FuncOnHit과 동일 이벤트)
Events.OnWeaponHitCharacter.Add(function(attacker, target, _weapon, _damage)
    if not instanceof(target, "IsoZombie") then return end
    if not (attacker and instanceof(attacker, "IsoPlayer") and attacker:isLocalPlayer()) then return end
    if target:getModData()["PuppetMutant"] then
        pokeTag(target)
    end
end)

-- 렌더: CDDA와 동일하게 OnTick에서 배치드로우, ttl로 페이드아웃
local function renderTags()
    local player = getPlayer()
    for zid, t in pairs(_showTags) do
        local zombie = t.zombie
        local kind, sender = nil, nil
        if zombie and player and t.ttl > 0
            and zombie:isAlive() and player:CanSee(zombie) then
            kind   = zombie:getModData()["PuppetMutant"]
            sender = zombie:getModData()["PuppetMutantSender"]
        end
        if kind then
            local sx, sy = screenXY(zombie, 190)
            t.tdo = t.tdo or TextDrawObject.new()
            local c = TAG_COLOR[kind] or {255, 255, 255}
            local a = t.ttl / TAG_TTL
            t.tdo:setDefaultColors(c[1] / 255, c[2] / 255, c[3] / 255, a)
            t.tdo:setOutlineColors(0, 0, 0, a)
            t.tdo:ReadString(UIFont.Small, tagText(kind, sender), -1)
            t.tdo:AddBatchedDraw(sx, sy - t.tdo:getHeight(), true)
            t.ttl = t.ttl - 1
        else
            _showTags[zid] = nil
        end
    end
end
Events.OnTick.Add(renderTags)

return _a
