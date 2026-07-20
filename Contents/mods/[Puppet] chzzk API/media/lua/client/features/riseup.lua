local _a = {}

-- 라이즈 업 데드 맨: 도네 플레이어 기준 반경 내 모든 시체(IsoDeadBody)를
-- 좀비로 되살린다.
--
-- 반경은 전용 샌드박스 변수 RiseUp_Radius (5~60, 기본 55)를 따른다.
-- 폭격(Bombard_Radius)과는 별개 변수 — 기본값만 55로 같을 뿐 서로 독립.
--
-- 권한 구조는 폭격과 정반대다.
--   좀비(IsoZombie)  = 클라이언트 권한 -> 폭격 킬은 클라별 분산 처리 (bombard.lua)
--   시체(IsoDeadBody) = 서버 권한      -> 부활은 서버 핸들러 한 곳에서만 처리
-- 바닐라도 MP 시체 제거를 서버 커맨드(/removezombies)로 우회하고, 시체는
-- 청크 데이터 + reanimated.bin 으로 서버에 저장된다. 클라 브로드캐스트로
-- 각자 reanimateNow() 하면 클라 수만큼 좀비가 중복 생성될 수 있으므로 금지.

local MARKER_DURATION_MS = 3000   -- 반경 표시 유지 시간

-- 바닥 반경 마커: ISSpawnHordeUI(바닐라 좀비떼 스폰 UI)가 쓰는 것과 동일한 API.
-- addGridSquareMarker(square, r, g, b, doAlpha, radius) -> marker 객체.
-- WorldMarkers는 로컬 렌더링이라 이 함수를 호출한 클라이언트 화면에만 보인다.
local function showRadiusMarker(square, radius)
    if not square then return end
    local marker = getWorldMarkers():addGridSquareMarker(square, 0.55, 0.05, 0.65, true, radius)
    marker:setScaleCircleTexture(true)

    local start = getTimestampMs()
    local function tick()
        if getTimestampMs() - start >= MARKER_DURATION_MS then
            marker:remove()
            Events.OnTick.Remove(tick)
        end
    end
    Events.OnTick.Add(tick)
end

-- 도네 발동 진입점. 서버에 좌표/반경만 넘기고 실제 부활은 server.lua 의
-- DOServer["PongDuRiseUp"]["RiseUp"] 이 수행한다.
-- SandboxVars는 파일 로드 시점엔 비어있을 수 있으므로 사용 시점에 읽는다.
function _a.a(player)
    if not player then return end
    local sv = SandboxVars and SandboxVars.PongDu
    local radius = (sv and tonumber(sv.RiseUp_Radius)) or 55

    getSoundManager():PlaySound("necromance", false, 1.0)
    sendClientCommand("PongDuDonation", "PlayAlert", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = radius,
    })
    sendClientCommand("PongDuRiseUp", "RiseUp", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = radius,
    })

    -- 도네이터 본인 화면에 반경 표시 (부활 시점과 동시, 3초간)
    showRadiusMarker(player:getCurrentSquare(), radius)
end

-- ── 부활 좀비 기상 모션 복원 ──────────────────────────────────────────────
-- 강령술이 fakeDead 경로(옷 유지)를 타면서 부활 좀비의 isReanimatedPlayer가
-- false가 됐다. 그런데 클라가 "이 좀비 지금 누워있다"를 아는 바닐라 경로
-- 두 개가 전부 isReanimatedPlayer 게이트다:
--
--   NetworkZombieSimulator.ParseZombie:184
--     if (zombie0.isReanimatedPlayer()) {
--         zombie0.getStateMachine().changeState(ZombieOnGroundState.instance(), null);
--     }
--   NetworkZombieVariables.setBooleanVariables:95
--     if (zombie0.isReanimatedPlayer()) { zombie0.setOnFloor(...); }  -- 비트는 오지만 버려짐
--
-- 그래서 서버는 눕혀놨는데 클라는 선 채로 그린다 -> 기상 모션 소실.
--
-- ★★ 핵심 메커니즘 (IsoGameCharacter.actionStateChanged:11272 확증):
--   B41 좀비의 AI 상태머신은 애니메이터(ActionContext)의 '노예'다.
--   AnimSet 노드가 전이될 때마다 actionStateChanged가
--   m_stateUpdateLookup[노드명] 으로 stateMachine.changeState를 다시 건다
--   (IsoZombie.initializeStates:354 의 "onground"->ZombieOnGroundState 매핑).
--   즉 Lua에서 changeState(ZombieOnGroundState)를 박아도, 애니메이터가
--   onground 노드로 실제 전이하지 못하면 다음 AnimSet 전이 한 방에 AI가
--   서있는 상태로 되돌려진다. 눕히기의 진짜 트리거는 changeState가 아니라
--   "bonfloor" 애님 변수(setOnFloor, IsoGameCharacter:708 바인딩)이며,
--   changeState는 그 사이 AI 공백(타겟 획득 차단)을 메우는 보조일 뿐이다.
--
-- ★ 밀집 더미 위 발동 시 '즉시 기립' 증상의 로그 확증 (300부활 세션):
--   getup-ok 346건 중 131건이 laydown 후 1초 미만 — 눕기+기상 모션이
--   물리적으로 불가능한 시간. anim=lunge 115 / attack 14 = 플레이어가
--   더미 위에 서 있으면 부활 좀비가 거리 0에서 즉시 타겟을 잡고 lunge로
--   전이 -> 원샷 laydown이 위 메커니즘으로 무효화된 것.
--   rescue 117건(700ms)은 "애니메이터가 300마리 부하로 아직 전이 못 함"을
--   고착으로 오판해 모션 없이 강제 기립시킨 — 즉시 기립의 직접 생산자.
--
-- 대응: 원샷 laydown -> "눕히기 강제 유지 루프(enforcement)"로 전환.
--   laydown 후 ENFORCE_MS 동안 매 스캔마다 애니메이터가 lying 노드에
--   도달했는지 확인하고, 아니면 setTarget(nil) + setOnFloor(true) +
--   changeState 를 재적용한다. 애니메이터가 onground에 정착하면 그때부터
--   updateInternal이 타겟 블록을 스킵하므로 재획득 걱정 없이 손을 뗀다.
--   rescue는 enforcement 만료 '후'에도 AI=onground+애니=standing 인 진짜
--   고착에만 발동한다 (기존 700ms -> 사실상 ENFORCE_MS로 지연).
--
-- ★★ 전이 아크 소스 확증 (PZ-Library "PZ 41.78.19 Anims"/actiongroups/zombie):
--   · lunge/transitions.xml : 전이 18개 중 bOnFloor→onground 아크 '없음'
--     → lunge 중인 좀비는 setOnFloor만으론 절대 안 눕는다. 대신
--     <isFalse>bHasTarget</isFalse> → idle 아크가 있어 setTarget(nil)이
--     1틱 안에 lunge를 강제 이탈시킨다 (setTarget(nil)이 필수인 이유).
--   · idle/otherTransitions.xml : <isTrue>bOnFloor</isTrue> → onground.
--     원본 주석부터 "This handles zombies being already on the ground,
--     like newly-reanimated corpses." — 정확히 이 용도의 공식 아크.
--   · attack, face-target : bOnFloor→onground 직행 아크 보유 — 공격 모션
--     중이어도 setOnFloor(true)만으로 즉시 눕는다.
--   · onground/transitions.xml : 소유 좀비(bClient=false)는
--     reanimateTimer<=0 에서만 getup — 눕은 뒤 기상 모션 보장.
--     (원격 좀비는 서버 realState 추종 아크 — 우리 개입 불필요)
--   즉 applyLaydown의 setTarget(nil)→setOnFloor(true) 순서가 어느 노드에서
--   출발하든 최대 2틱(lunge→idle→onground) 안에 눕는 경로를 보장한다.
--
-- 현 구조는 2계층 x 2조건 트리거다 (via= 로그로 어느 경로가 작동했는지 관측):
--   [계층] zu    : OnZombieUpdate(IsoZombie:2102) — 좀비 자신의 update 페이즈,
--                  즉 그 프레임 '렌더 전'에 발화. 첫 update에서 눕히면 서있는
--                  포즈가 화면에 그려질 프레임 자체가 없다. OnTick 스캔(등장 →
--                  다음 틱 사이 1~수 프레임 서있는 모습 노출)의 잔여 플래시
--                  ("벌떡 일어났다 다시 눕는" 증상) 제거용. 창 활성 중에만
--                  동작해 평시 오버헤드 0. 바닐라 전례: YouHaveOneDay.lua가
--                  같은 이벤트에서 Hit() 등 상태 조작을 수행.
--   [계층] tick  : OnTick 스캔 — zu가 못 잡은 케이스(창 열리기 전 도착분의
--                  소급 처리 등) 폴백 + enforcement/고착 감시 구동.
--   [조건] window   : 서버 RiseUp 핸들러가 부활 완료 직후 브로드캐스트하는
--                 GetupWindow(x,y,r)를 받아 창을 연다. 창(4초, 좀비 패킷이
--                 커맨드보다 먼저 온 경우 대비 소급 2초) 안에서 반경 내에
--                 "처음 관측된" 좀비를 무조건 눕힌다. realState 무의존.
--   [조건] realState: 관측 초기(4초) 동안 realState가 onground로 확인되면 눕힌다.
--
-- 낙하 중 좀비(좀비레인 등, z가 소수이거나 realState=="falling")는 눕히면
-- 공중에 눕는 연출사고가 나므로 관측 즉시 영구 제외한다.
--
-- 서버/네트워크 영향 없음 — 순수 클라 로컬 상태 보정.
local _seen = {}      -- [onlineID] = 최초 관측 시각(ms)
local _done = {}      -- [onlineID] = true (눕혔거나 제외 확정 — 더 안 건드림)
local _laid = {}      -- [onlineID] = {t=최초 laydown 시각, tries=재적용 횟수,
                      --               laidOk=애니메이터 lying 도달 확인 여부,
                      --               pinned=밟힘 리셋 우회 플래그 ON 여부}
local _windows = {}   -- {x, y, r2, arrived, expires} : 서버 GetupWindow 수신분
local _lastScan = 0
local SCAN_INTERVAL_MS = 200   -- 평시 스캔 간격 (창 활성 중엔 매 틱)
local WINDOW_MS        = 4000  -- 창 유지: 서버측 기상 타이머(30~90틱)보다 약간 길게
local PRE_GRACE_MS     = 2000  -- 좀비 패킷이 커맨드보다 먼저 도착한 경우 소급 폭
local YOUNG_MS         = 4000  -- 최초 관측 후 이 시간까지만 재평가
local ANIM_SETTLE_MS   = 400   -- laydown 후 첫 검사까지 유예 (애니 전이 최소 시간)
local ENFORCE_MS       = 3000  -- 눕히기 강제 유지 기간 — 이 안에선 rescue 금지
local TRACK_CAP_MS     = 30000 -- 추적 하드캡 (북키핑 정리용 — 조치 없음)
local UNPIN_FLAG_AT    = 8     -- 기상 타이머가 이 값 이하로 내려오면 밟힘 리셋 우회 시작

-- Kahlua엔 표준 next()가 노출돼 있지 않다 — pairs로 공백 판정.
local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

-- 만료 창 정리. 반환값: 활성 창 존재 여부.
-- ★ 창 활성 중엔 스캔을 매 틱으로 돌린다: enforcement 재적용은 애니메이터의
--   전이 타이밍 싸움이라 200ms 간격으론 진다. 바닐라 ParseZombie가 생성
--   '직후'(애니메이터 1틱도 돌기 전) 눕히는 것과 같은 이유.
local function pruneWindows()
    local now = getTimestampMs()
    for i = #_windows, 1, -1 do
        if now > _windows[i].expires then table.remove(_windows, i) end
    end
    return #_windows > 0
end

local function insideWindow(z, firstSeen)
    for i = 1, #_windows do
        local w = _windows[i]
        if firstSeen >= w.arrived - PRE_GRACE_MS then
            local dx = z:getX() - w.x
            local dy = z:getY() - w.y
            if dx * dx + dy * dy <= w.r2 then return true end
        end
    end
    return false
end

-- 눕히기 1회 적용 (최초/재적용 공용).
-- setTarget(nil): lunge/attack 노드는 bhastarget 없이는 유지되지 않는다 —
-- 플레이어 발밑 부활 좀비의 즉시 타겟 획득 -> lunge 선점을 여기서 끊는다.
-- AI가 ZombieOnGroundState인 동안은 updateInternal이 타겟 블록을 스킵하므로
-- 재획득도 봉쇄된다 (actionStateChanged가 AI를 되돌리기 전까지).
local function applyLaydown(z)
    return pcall(function()
        z:setTarget(nil)
        z:setOnFloor(true)
        z:changeState(ZombieOnGroundState.instance())
    end)
end

local function layDown(z, zid, why)
    _done[zid] = true
    local ok, err = applyLaydown(z)
    if ok then _laid[zid] = { t = getTimestampMs(), tries = 0, laidOk = false, pinned = false } end
    print("[PongDu][RiseUp][Getup] laydown zid=" .. tostring(zid)
        .. " via=" .. why .. " ok=" .. tostring(ok)
        .. (ok and "" or (" err=" .. tostring(err))))
end

-- ── AI/애니메이터 정합성 조정기 ──────────────────────────────────────────
-- ★ 1차 시도(이동거리+6초 timeout 휴리스틱)의 실패 로그 확증:
--   밀집 부활 더미에서는 좀비들이 서로를 밟아 isBeingSteppedOn()이 기상
--   타이머를 계속 리셋한다(ZombieOnGroundState.execute) — 6초 이상 눕는 게
--   정상이다. 이걸 timeout이 고착으로 오판해 AI만 idle로 밀면, 기상 타이머는
--   ZombieOnGroundState.execute 안에서만 감소하므로 애니메이터가 lying에서
--   영원히 못 나오는 역방향 데드락이 된다.
--
-- 2차(현행): 애니메이터를 직접 읽는다.
--   getCurrentActionContextStateName() (IsoGameCharacter:1058, Kahlua 노출)
--   이 ActionContext 노드명을 반환 — "onground"류 = 시각적으로 누움.
--   enforcement 기간 안에서는 어긋남 = "아직 전이 못 함"으로 보고 재적용,
--   기간 만료 후에도 남는 어긋남만 사분면 로직으로 교정한다:
--     AI=onground + 애니=standing → idle로 rescue   (진짜 고착 — 애니메이터가
--                                   전이 안 하면 actionStateChanged도 안 와서
--                                   AI가 onground에 영구 방치되는 케이스)
--     AI=idle    + 애니=onground → onground로 revert (역방향 데드락 치유
--                                   — revert로 타이머 재가동, 자연 기상)
--   일관 lying은 방치(기상은 바닐라 몫), 일관 standing은 추적 종료.
-- ── 밟힘 리셋 우회기 (unpin) ─────────────────────────────────────────────
-- 문제: 밟힌 좀비는 영원히 못 일어난다. ZombieOnGroundState.execute:
--   setReanimateTimer(timer - multiplier/1.6)
--   if (timer <= 2) { if (bClient) {
--       if (isBeingSteppedOn() && !isReanimatedPlayer()) timer = Rand(60)+30 } }
-- 밟힘 판정(isBeingSteppedOn, IsoGameCharacter:10247)은 "isOnFloor()가
-- false인(=서있는) 캐릭터"의 본 충돌만 세므로, 먼저 일어난 좀비들이 아직
-- 누운 좀비 위에 서 있는 한 리셋 루프가 끝나지 않는다. 캐시 필드가 아닌
-- 실시간 계산이라 세터도 없다.
--
-- 타이머 직접 조작이 불가능한 이유 (프레임 순서 확증):
--   update 페이즈: stateMachine.update() -> execute (감쇠 + 리셋)
--                  (IsoGameCharacter:8342)
--   postupdate    : actionContext.update() -> 전이 평가 (getup 아크는
--                  reanimateTimer<=0 요구) (IsoGameCharacter:9929)
--   OnTick        : IsoWorld.update() 완료 '후' 발화 (IngameState:1311)
--   OnZombieUpdate: execute '전' 발화 (IsoZombie:2102 -> super.update:2145)
--   => 어느 Lua 훅에서 타이머를 음수로 박아도 다음 전이 평가 전에 execute가
--      한 번 끼어들어 "감쇠 -> <=2 체크 -> 리셋"을 수행한다. 구조적 패배.
--
-- 유일한 레버: 리셋 조건의 !isReanimatedPlayer(). setReanimatedPlayer(true)
-- (IsoZombie:3418, public)면 리셋이 스킵되고 타이머가 자연 감쇠로 0을 뚫어
-- getup 아크가 발동한다.
--
-- 부작용 통제 — 플래그는 비트32로 서버/원격에 양방향 동기화되고
-- (NetworkZombieVariables:75/87), 서버의 ReanimatedPlayers 영속화·사망 시
-- 특수 처리 등에 관여하므로 켜두는 시간을 최소화한다:
--   · 대상: 우리가 눕힌(_laid 추적) + 애니메이터 onground 정착 좀비만
--   · ON  : getReanimateTimer() <= UNPIN_FLAG_AT (카운트다운 막바지 수 틱 전)
--   · OFF : onground 노드 이탈(getup 진입) 즉시 / rescue / track-cap
--   => 노출 창 ~10틱(수백 ms). 이 창에 월드 세이브·사망이 겹칠 확률은 무시
--      가능한 수준. 밟히지 않은 좀비에겐 리셋 자체가 없으므로 플래그는
--      무해한 no-op — isBeingSteppedOn() 호출(본 충돌 연산)을 아끼기 위해
--      밟힘 여부는 확인하지 않고 타이머만 본다.
--   · 만약의 revert(changeState->enter)와 겹쳐도 enter의
--     removeDeadBody(reanimatedBodyID)는 기본값 -1이라 Bodies.get(-1)=null
--     no-op (IsoDeadBody:1540, NetworkZombieAI:53 확증).
local LYING_NODES = {
    ["onground"] = true, ["getup"] = true, ["getdown"] = true,
    ["falldown"] = true, ["falling"] = true,
    ["fakedead"] = true, ["fakedead-attack"] = true,
}

local function unpin(z, zid, rec, why)
    if not rec.pinned then return end
    rec.pinned = false
    local ok = pcall(function() z:setReanimatedPlayer(false) end)
    print("[PongDu][RiseUp][Getup] unpin zid=" .. tostring(zid)
        .. " why=" .. why .. " ok=" .. tostring(ok))
end

local function rescueStuck(z, zid, tries)
    local ok, err = pcall(function()
        z:setOnFloor(false)
        z:changeState(ZombieIdleState.instance())
    end)
    print("[PongDu][RiseUp][Getup] rescue zid=" .. tostring(zid)
        .. " tries=" .. tostring(tries) .. " ok=" .. tostring(ok)
        .. (ok and "" or (" err=" .. tostring(err))))
end

local function revertToGround(z, zid)
    local ok, err = pcall(function()
        z:setOnFloor(true)
        z:changeState(ZombieOnGroundState.instance())
    end)
    print("[PongDu][RiseUp][Getup] revert zid=" .. tostring(zid)
        .. " ok=" .. tostring(ok)
        .. (ok and "" or (" err=" .. tostring(err))))
end

-- laydown 추적분 검사. 반환: 처리 완료 여부(true면 대기열에서 제거).
local function checkLaid(z, zid, rec, now)
    local elapsed = now - rec.t
    if elapsed < ANIM_SETTLE_MS then return false end   -- 애니 전이 유예
    if elapsed > TRACK_CAP_MS then
        unpin(z, zid, rec, "trackcap")
        print("[PongDu][RiseUp][Getup] track-cap zid=" .. tostring(zid)
            .. " laidOk=" .. tostring(rec.laidOk))
        return true
    end

    local ai, anim
    local ok = pcall(function()
        ai = z:getCurrentState()
        anim = z:getCurrentActionContextStateName()
    end)
    if not ok then return false end
    local aiGround = (ai == ZombieOnGroundState.instance())
    local lying = LYING_NODES[anim] or false

    if lying then
        rec.laidOk = true
        if anim == "onground" then
            -- 밟힘 리셋 우회: 카운트다운 막바지에만 잠깐 플래그를 올린다.
            if not rec.pinned then
                local timer
                pcall(function() timer = z:getReanimateTimer() end)
                if timer and timer <= UNPIN_FLAG_AT then
                    local okp = pcall(function() z:setReanimatedPlayer(true) end)
                    if okp then
                        rec.pinned = true
                        print("[PongDu][RiseUp][Getup] pin zid=" .. tostring(zid)
                            .. " timer=" .. tostring(timer))
                    end
                end
            end
        else
            -- onground 이탈(getup 등 진입): 즉시 해제
            unpin(z, zid, rec, "leftground")
        end
        -- 역방향 데드락: 애니 lying인데 AI가 idle (rescue 잔재 등)
        if not aiGround and anim == "onground" and ai == ZombieIdleState.instance() then
            revertToGround(z, zid)
        end
        return false                 -- 일관 lying 또는 전이 중: 대기 (기상은 바닐라 몫)
    end

    unpin(z, zid, rec, "standing")   -- lying 이탈 후 미해제분 안전망

    -- 애니메이터 standing류 --------------------------------------------------
    if not rec.laidOk and elapsed <= ENFORCE_MS then
        -- 아직 한 번도 못 눕힘 + enforcement 기간 내: 재적용.
        -- lunge 선점이든 애니메이터 부하 지연이든 여기서 계속 밀어붙인다.
        rec.tries = rec.tries + 1
        applyLaydown(z)
        return false
    end

    if aiGround then
        -- enforcement 만료 후에도 AI=onground + 애니=standing: 진짜 고착.
        unpin(z, zid, rec, "rescue")
        rescueStuck(z, zid, rec.tries)
        return false                 -- revert 필요 여부 계속 감시
    end

    -- 일관 standing: laidOk면 정상 기상 완료, 아니면 눕히기 최종 실패 (관측용 구분)
    if rec.laidOk then
        print("[PongDu][RiseUp][Getup] getup-ok zid=" .. tostring(zid)
            .. " after=" .. tostring(elapsed) .. "ms anim=" .. tostring(anim))
    else
        print("[PongDu][RiseUp][Getup] never-laid zid=" .. tostring(zid)
            .. " after=" .. tostring(elapsed) .. "ms anim=" .. tostring(anim)
            .. " tries=" .. tostring(rec.tries))
    end
    return true
end

-- 신규 관측 좀비 1마리 판정 (zu/tick 공용). first=최초 관측 시각, tag=계층 표기.
local function evaluateNew(z, zid, first, tag)
    local rs
    pcall(function() rs = z:getRealState() end)
    local zz = z:getZ()
    if z:isDead() or rs == "falling" or zz ~= math.floor(zz) then
        _done[zid] = true          -- 사망/낙하 중: 영구 제외
    elseif rs == "onground" then
        layDown(z, zid, "realState" .. tag)
    elseif insideWindow(z, first) then
        layDown(z, zid, "window" .. tag)
    end
end

local function getupScan()
    local player = getSpecificPlayer(0)
    if not player then return end
    local cell = player:getCell()
    if not cell then return end
    local zlist = cell:getZombieList()
    if not zlist then return end

    local now = getTimestampMs()
    local alive = {}
    for i = 0, zlist:size() - 1 do
        local z = zlist:get(i)
        if z then
            local zid = z:getOnlineID()
            alive[zid] = z
            local first = _seen[zid]
            if not first then
                first = now
                _seen[zid] = now
            end
            if not _done[zid] and now - first <= YOUNG_MS then
                evaluateNew(z, zid, first, "")
            end
        end
    end

    -- 고착 감시 + enforcement 패스
    for zid, rec in pairs(_laid) do
        local z = alive[zid]
        if z and checkLaid(z, zid, rec, now) then
            _laid[zid] = nil
        end
    end

    for zid in pairs(_seen) do
        if not alive[zid] then
            _seen[zid] = nil
            _done[zid] = nil
            _laid[zid] = nil
        end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    local active = pruneWindows()
    -- 창 활성 중이거나 enforcement/고착 감시 대기 좀비가 있으면 매 틱, 아니면 200ms 간격
    if not active and isEmpty(_laid) then
        if now - _lastScan < SCAN_INTERVAL_MS then return end
    end
    _lastScan = now
    local ok, err = pcall(getupScan)
    if not ok then
        print("[PongDu][RiseUp][Getup] scan error: " .. tostring(err))
    end
end)

-- 렌더 전 선눕히기: 창 활성 중에만. 좀비 update 페이즈 내부라 여기서 눕히면
-- 그 프레임에 바로 lying으로 그려진다 (OnTick 경로의 1~수 프레임 플래시 제거).
Events.OnZombieUpdate.Add(function(z)
    if #_windows == 0 then return end   -- 평시 오버헤드 0 (창 없으면 즉시 탈출)
    if not z then return end
    local zid = z:getOnlineID()
    if _done[zid] then return end
    local now = getTimestampMs()
    local first = _seen[zid]
    if not first then
        first = now
        _seen[zid] = now
    end
    if now - first > YOUNG_MS then return end
    local ok, err = pcall(evaluateNew, z, zid, first, "@zu")
    if not ok then
        print("[PongDu][RiseUp][Getup] zu error: " .. tostring(err))
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuRiseUp" or command ~= "GetupWindow" then return end
    local x = tonumber(args and args["x"])
    local y = tonumber(args and args["y"])
    local r = tonumber(args and args["r"]) or 55
    if not x or not y then return end
    local now = getTimestampMs()
    local rr = r + 5   -- 부활 직후 미세 이동 여유
    _windows[#_windows + 1] = {
        x = x, y = y, r2 = rr * rr,
        arrived = now, expires = now + WINDOW_MS,
    }
    print("[PongDu][RiseUp][Getup] window open @" .. tostring(x) .. "," .. tostring(y)
        .. " r=" .. tostring(r))
end)

return _a
