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
-- ★ 구 버전(realState 관측만)이 실패한 이유: "클라가 좀비를 처음 본 순간
--   realState == onground"라는 전제가 타이밍 의존적이다. 반증 —
--   ① 바닐라가 부활 플레이어를 눕힐 때 realState를 안 쓰고 isReanimatedPlayer
--      게이트로 명시적 changeState를 한다. realState만으로 충분했다면 이
--      게이트는 존재할 이유가 없다.
--   ② 바닐라 죽은척 좀비도 원격 클라에선 기상 모션이 없다. 걔네 서버
--      realState도 onground를 거치는데 클라가 못 눕는다 = 첫 패킷에
--      onground가 실려온다는 보장이 없다는 방증.
--
-- 현 구조는 2중 트리거다 (어느 쪽이 실제 작동하는지 via= 로그로 관측 가능):
--   1) window   : 서버 RiseUp 핸들러가 부활 완료 직후 브로드캐스트하는
--                 GetupWindow(x,y,r)를 받아 창을 연다. 창(4초, 좀비 패킷이
--                 커맨드보다 먼저 온 경우 대비 소급 2초) 안에서 반경 내에
--                 "처음 관측된" 좀비를 무조건 눕힌다. realState 무의존.
--   2) realState: 관측 초기(4초) 동안 realState가 onground로 확인되면 눕힌다.
--                 (구 버전 경로 — fallback으로 유지)
--
-- "처음 본 좀비만" 조건이 핵심 — 이미 idle로 정착한 좀비에 changeState를
-- 반복하면 enter()가 기상 타이머(30~90)를 계속 재세팅해 영원히 못 일어나고,
-- ActionContext가 이미 idle 애님에 정착한 뒤엔 강제 전이가 안 먹을 수 있다.
-- 바닐라 ParseZombie도 같은 이유로 '생성 직후'에만 눕힌다.
--
-- 낙하 중 좀비(좀비레인 등, z가 소수이거나 realState=="falling")는 눕히면
-- 공중에 눕는 연출사고가 나므로 관측 즉시 영구 제외한다.
--
-- 서버/네트워크 영향 없음 — 순수 클라 로컬 상태 보정.
local _seen = {}      -- [onlineID] = 최초 관측 시각(ms)
local _done = {}      -- [onlineID] = true (눕혔거나 제외 확정 — 더 안 건드림)
local _laidAt = {}    -- [onlineID] = 눕힌 시각(ms) — 유지 검증 대기열
local _windows = {}   -- {x, y, r2, arrived, expires} : 서버 GetupWindow 수신분
local _lastScan = 0
local SCAN_INTERVAL_MS = 200   -- 평시 스캔 간격 (창 활성 중엔 매 틱)
local WINDOW_MS        = 4000  -- 창 유지: 서버측 기상 타이머(30~90틱)보다 약간 길게
local PRE_GRACE_MS     = 2000  -- 좀비 패킷이 커맨드보다 먼저 도착한 경우 소급 폭
local YOUNG_MS         = 4000  -- 최초 관측 후 이 시간까지만 재평가
local VERIFY_MS        = 500   -- 눕힌 뒤 이 시점에 상태 유지 여부 검증(진단용)

-- 만료 창 정리. 반환값: 활성 창 존재 여부.
-- ★ 창 활성 중엔 스캔을 매 틱으로 돌린다: 로그 분석 결과 laydown 커버리지는
--   100%였는데도(892/892, ok=true) 일부가 벌떡 서는 증상 — 스캔 간격(200ms)
--   동안 클라 애니메이터가 idle에 정착해버리면 AI 상태만 onground가 되고
--   시각 전이가 안 걸릴 수 있다. 바닐라 ParseZombie는 생성 '직후'(애니메이터
--   1틱도 돌기 전) 눕힌다 — 매 틱 스캔으로 그 타이밍에 최대한 붙인다.
-- Kahlua엔 표준 next()가 노출돼 있지 않다 — pairs로 공백 판정.
local function isEmpty(t)
    for _ in pairs(t) do return false end
    return true
end

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

local function layDown(z, zid, why)
    _done[zid] = true
    local ok, err = pcall(function()
        z:setOnFloor(true)
        z:changeState(ZombieOnGroundState.instance())
    end)
    if ok then _laidAt[zid] = getTimestampMs() end
    print("[PongDu][RiseUp][Getup] laydown zid=" .. tostring(zid)
        .. " via=" .. why .. " ok=" .. tostring(ok)
        .. (ok and "" or (" err=" .. tostring(err))))
end

-- 눕힌 뒤 VERIFY_MS 시점의 상태 유지 검증 (진단용).
-- held=false = 네트워크 상태 동기화가 강제 상태를 걷어냄(역전 가설)
-- held=true인데 벌떡 섰다 = 애니메이터 미전이(정착 가설)
local function verifyLaid(z, zid)
    local held, name
    pcall(function()
        local st = z:getCurrentState()
        held = (st == ZombieOnGroundState.instance())
        name = tostring(st)
    end)
    print("[PongDu][RiseUp][Getup] verify zid=" .. tostring(zid)
        .. " held=" .. tostring(held) .. " state=" .. tostring(name))
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
                local rs
                pcall(function() rs = z:getRealState() end)
                local zz = z:getZ()
                if z:isDead() or rs == "falling" or zz ~= math.floor(zz) then
                    _done[zid] = true          -- 사망/낙하 중: 영구 제외
                elseif rs == "onground" then
                    layDown(z, zid, "realState")
                elseif insideWindow(z, first) then
                    layDown(z, zid, "window")
                end
            end
        end
    end

    -- 유지 검증 패스
    for zid, t in pairs(_laidAt) do
        if now - t >= VERIFY_MS then
            local z = alive[zid]
            if z then verifyLaid(z, zid) end
            _laidAt[zid] = nil
        end
    end

    for zid in pairs(_seen) do
        if not alive[zid] then
            _seen[zid] = nil
            _done[zid] = nil
            _laidAt[zid] = nil
        end
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    local active = pruneWindows()
    -- 창 활성 중이거나 검증 대기 좀비가 있으면 매 틱, 아니면 200ms 간격
    if not active and isEmpty(_laidAt) then
        if now - _lastScan < SCAN_INTERVAL_MS then return end
    end
    _lastScan = now
    local ok, err = pcall(getupScan)
    if not ok then
        print("[PongDu][RiseUp][Getup] scan error: " .. tostring(err))
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
