local randomteleport = {}
local global = require("global")
require("ISUI/ISPanel")

-- ── 랜덤 텔레포트 (random_teleport) ──────────────────────────────────────────
-- 발동 시점 위치를 원점으로, 반경 RT_MinDist~RT_MaxDist(기본 100~200)타일
-- 링 안의 랜덤 좌표로 이동.
-- 좌표 검증은 2단계:
--   1) 사전 검사 (텔포 전, 청크 로딩 불필요):
--      getWorld():getMetaGrid():isValidSquare(x,y)  -- 맵 바운딩 박스 밖 제외
--      getWorld():getMetaGrid():isValidChunk(x/10,y/10) -- 셀 info==null (-1,-1류
--      존재하지 않는 지역) 제외
--   2) 사후 검사 (텔포 후, 청크 로딩 완료 대기):
--      100~200타일은 클라이언트 로딩 범위 밖이라 getGridSquare가 nil을 돌려주므로
--      물타일 여부는 먼저 이동한 뒤 청크가 스트리밍되면 확인할 수밖에 없다.
--      로딩된 스퀘어가 물타일 / 바닥 없음 / 솔리드(벽·나무)면 원점 기준으로
--      재추첨해서 다시 텔포. MAX_ATTEMPTS 초과 시 원점 복귀 (안전망).

local MAX_ATTEMPTS       = 15    -- 사후 검증 실패 시 재추첨 한도
local MAX_PREROLLS       = 200   -- 메타그리드 사전 검사 재추첨 한도
local LOAD_TIMEOUT_TICKS = 600   -- 청크 로딩 대기 한도 (약 10초 @60fps)

local state = nil   -- 진행 중이면 {origin, cx, cy, attempts, waitTicks}
local tickHandler = nil

-- ── 샌드박스 옵션 (사용 시점에 읽음) ─────────────────────────────────────────
-- 거리: PongDu.RT_MinDist / RT_MaxDist (기본 100~200). max < min이면 min으로 클램프.
local function distCfg()
    local sv = SandboxVars and SandboxVars.PongDu
    local mn = (sv and tonumber(sv.RT_MinDist)) or 100
    local mx = (sv and tonumber(sv.RT_MaxDist)) or 200
    if mn < 1 then mn = 1 end
    if mx < mn then mx = mn end
    return mn, mx
end

-- 생존 복귀: PongDu.RT_Return (기본 꺼짐) / RT_SurviveMinutes (기본 5분)
local function returnCfg()
    local sv = SandboxVars and SandboxVars.PongDu
    local on = sv ~= nil and sv.RT_Return == true
    local mins = (sv and tonumber(sv.RT_SurviveMinutes)) or 5
    if mins < 1 then mins = 1 end
    return on, mins
end

-- 메타그리드 기준 사전 검사: 맵 범위 밖 / 존재하지 않는 셀 걸러냄
local function isMetaValid(x, y)
    local meta = getWorld():getMetaGrid()
    if not meta then return false end
    if not meta:isValidSquare(x, y) then return false end
    if not meta:isValidChunk(math.floor(x / 10), math.floor(y / 10)) then return false end
    return true
end

-- 원점 기준 반경 min~max 링 안에서 메타 유효 좌표 하나 추첨. 실패 시 nil.
local function rollCandidate(ox, oy)
    local minR, maxR = distCfg()
    for _ = 1, MAX_PREROLLS do
        local r = minR + ZombRand(maxR - minR + 1)
        local a = math.rad(ZombRand(360))
        local x = math.floor(ox + r * math.cos(a) + 0.5)
        local y = math.floor(oy + r * math.sin(a) + 0.5)
        if isMetaValid(x, y) then return x, y end
    end
    return nil
end

-- 차량 탑승 중이면 강제 하차. B41엔 removePassenger가 없고 exit(chr)가 정석:
-- clearPassenger + setVehicle(nil) + collidable 복구 + MP sendExit 동기화까지 처리
-- (바닐라 ISExitVehicle:perform 참조).
local function forceExitVehicle(p)
    local v = p:getVehicle()
    if not v then return end
    v:exit(p)
    p:PlayAnim("Idle")
    global.b(" random_teleport: forced exit from vehicle before teleport")
end

local function movePlayer(p, x, y, z)
    p:setX(x)
    p:setY(y)
    p:setZ(z)
    p:setLx(x)
    p:setLy(y)
    p:setLz(z)
    getWorld():update()
end

-- 로딩 완료된 스퀘어가 착지 가능한지: 물타일 X / 바닥 없음 X / 솔리드(벽·나무) X
local function isLandable(sq)
    if sq:Is(IsoFlagType.water) then return false end
    if sq:getFloor() == nil then return false end
    if sq:isSolid() then return false end
    return true
end

local function stopLoop()
    if tickHandler then
        Events.OnTick.Remove(tickHandler)
        tickHandler = nil
    end
    state = nil
end

-- ── 생존 복귀 (RT_Return, 기본 꺼짐) ─────────────────────────────────────────
-- 착지 확정 시점부터 생존시간(RT_SurviveMinutes, 분) 카운트다운. 살아서 버티면
-- exile과 동일하게 원래 위치로 자동 복귀. 상태는 player modData
-- (rtReturnTime/rtOrigin)에 저장해 재접속 복구를 지원한다 -- exile의
-- returnTime/originalPosition과 키를 분리해 두 기능이 동시 진행돼도 서로 안
-- 덮는다. 사망 시 취소 (exile과 동일 정책).
-- 카운트다운 중 랜텔 재발동 시: 최초 원점(rtOrigin)은 유지하고 타이머만 리셋
-- -> 어디로 연쇄 텔포되든 복귀 지점은 "맨 처음 발동한 자리".
local RTReturnTimerDisplay = ISPanel:derive("RTReturnTimerDisplay")
local _retTick  = nil
local _retPanel = nil

function RTReturnTimerDisplay:new(player)
    local w = getCore():getScreenWidth()
    local h = getCore():getScreenHeight()
    -- 폭격(h-150)/레인(h-180) 타이머와 동시 표시 대비 30px 위
    local o = ISPanel:new(w / 2 - 80, h - 210, 160, 25)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o:noBackground()
    return o
end

function RTReturnTimerDisplay:render()
    local t = self.player:getModData().rtReturnTime or 0
    local sec = math.floor(t / 60)
    self:drawTextCentre(getText("IGUI_donation_random_teleport") .. " "
        .. string.format("%02d:%02d", math.floor(sec / 60), sec % 60),
        self.width / 2, 0, 0.55, 1.0, 0.55, 1, UIFont.Small)
end

function RTReturnTimerDisplay:update()
    if (self.player:getModData().rtReturnTime or 0) <= 0 then
        self:removeFromUIManager()
        _retPanel = nil
    end
end

local function rtDoReturn(p)
    local md = p:getModData()
    local o = md.rtOrigin
    if o then
        getSoundManager():PlaySound("exile_exit", false, 1.0)
        forceExitVehicle(p)
        movePlayer(p, o.x, o.y, o.z)
        global.b(" random_teleport: survived, returned to origin")
    end
    md.rtReturnTime = 0
    md.rtOrigin = nil
end

local function rtStopCountdown(p)
    local md = p and p:getModData()
    if md then
        md.rtReturnTime = 0
        md.rtOrigin = nil
    end
    if _retTick then
        Events.OnTick.Remove(_retTick)
        _retTick = nil
    end
end

local function rtStartTicker(p)
    local md = p:getModData()
    if _retTick then Events.OnTick.Remove(_retTick) end
    _retTick = function()
        if not md.rtReturnTime or md.rtReturnTime <= 0 then
            Events.OnTick.Remove(_retTick)
            _retTick = nil
            return
        end
        md.rtReturnTime = md.rtReturnTime - 1
        if md.rtReturnTime <= 0 then
            md.rtReturnTime = 0
            rtDoReturn(p)
            Events.OnTick.Remove(_retTick)
            _retTick = nil
        end
    end
    Events.OnTick.Add(_retTick)
    if not _retPanel then
        _retPanel = RTReturnTimerDisplay:new(p)
        _retPanel:addToUIManager()
        _retPanel:setVisible(true)
    end
end

-- 착지 확정 시 호출. 옵션 꺼짐이면 아무것도 안 함.
local function rtArmReturn(p, origin)
    local on, mins = returnCfg()
    if not on then return end
    local md = p:getModData()
    if not md.rtOrigin then
        md.rtOrigin = { x = origin.x, y = origin.y, z = origin.z }
    end
    md.rtReturnTime = mins * 60 * 60   -- 분 -> 틱 (폭격/유배와 동일: 1틱 = 1 감산)
    rtStartTicker(p)
end

-- 사망 시 복귀 취소
Events.OnPlayerDeath.Add(function(p)
    if not p or not p:isLocalPlayer() then return end
    rtStopCountdown(p)
end)

-- 재접속 복구: 다른 기능들과 동일 패턴 (OnTick에서 플레이어 로드 확인 후 1회)
local _rtRecoveryDone = false
local function rtRecovery()
    if _rtRecoveryDone then
        Events.OnTick.Remove(rtRecovery)
        return
    end
    local p = getSpecificPlayer(0)
    if not p then return end
    local md = p:getModData()
    if md.rtReturnTime and md.rtReturnTime > 0 and md.rtOrigin then
        rtStartTicker(p)
    end
    _rtRecoveryDone = true
    Events.OnTick.Remove(rtRecovery)
end
Events.OnTick.Add(rtRecovery)

-- 재추첨 + 재텔포. 후보 고갈 / 한도 초과면 원점 복귀 후 종료.
local function rerollOrGiveUp(p)
    state.attempts = state.attempts + 1
    if state.attempts > MAX_ATTEMPTS then
        global.b(" random_teleport: attempts exceeded, returning to origin")
        movePlayer(p, state.origin.x, state.origin.y, state.origin.z)
        stopLoop()
        return
    end
    local nx, ny = rollCandidate(state.origin.x, state.origin.y)
    if not nx then
        global.b(" random_teleport: no meta-valid candidate, returning to origin")
        movePlayer(p, state.origin.x, state.origin.y, state.origin.z)
        stopLoop()
        return
    end
    state.cx, state.cy = nx, ny
    state.waitTicks = 0
    movePlayer(p, nx + 0.5, ny + 0.5, 0)
end

local function onTick()
    if not state then
        stopLoop()
        return
    end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then
        stopLoop()
        return
    end

    local sq = getCell():getGridSquare(state.cx, state.cy, 0)
    if sq == nil then
        -- 청크 스트리밍 대기
        state.waitTicks = state.waitTicks + 1
        if state.waitTicks > LOAD_TIMEOUT_TICKS then
            global.b(" random_teleport: chunk load timeout, rerolling")
            rerollOrGiveUp(p)
        end
        return
    end

    if isLandable(sq) then
        global.b(string.format(" random_teleport: landed at %d,%d (attempt %d)",
            state.cx, state.cy, state.attempts))
        rtArmReturn(p, state.origin)   -- 생존 복귀 (옵션 켜져 있을 때만)
        stopLoop()
    else
        rerollOrGiveUp(p)
    end
end

-- 랜덤 텔레포트 발동  [public name: .a]
function randomteleport.a(player)
    if not player then return end
    -- 이미 진행 중이면 기존 루프를 버리고 현재 위치 기준으로 새로 시작
    stopLoop()

    forceExitVehicle(player)

    local origin = { x = player:getX(), y = player:getY(), z = player:getZ() }
    local cx, cy = rollCandidate(origin.x, origin.y)
    if not cx then
        global.b(" random_teleport: no meta-valid candidate around origin, aborting")
        return
    end

    state = { origin = origin, cx = cx, cy = cy, attempts = 1, waitTicks = 0 }
    movePlayer(player, cx + 0.5, cy + 0.5, 0)

    tickHandler = onTick
    Events.OnTick.Add(tickHandler)
end

return randomteleport
