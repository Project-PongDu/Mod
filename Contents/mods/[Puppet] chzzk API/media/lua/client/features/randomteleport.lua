local randomteleport = {}
local global = require("global")
require("ISUI/ISPanel")
local timerStack = require("utils/timerStack")
local colorMap = require("utils/colorMap")
local textOutline = require("utils/textOutline")
local zone = require("utils/zone")

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
-- 세이프존(세이프하우스 +10타일)은 위 조건과 별개로 무조건 제외한다. 판정은
-- 사전 검사 단계에서 끝난다 -- 세이프하우스 목록은 클라에 동기화돼 있어
-- 청크 로딩 없이 좌표만으로 판정 가능하다 (utils/zone.c).
--
-- 방식(PongDu.RT_Mode, 드롭다운):
--   1 편도   : 위 링 텔포만 하고 끝.
--   2 왕복   : 링 텔포 후 생존시간(RT_SurviveMinutes) 버티면 원점 복귀.
--              (구 RT_Return 불리언 옵션을 이 값으로 흡수했다.)
--   3 랜덤 플레이어에게 : 본인·스태프(accessLevel ~= "None")·사망자를 뺀
--              접속자 중 한 명의 위치로 편도 이동.
--      접속자 전체 목록은 서버에만 있다 -- 클라의 getOnlinePlayers()는
--      GameClient가 아는 플레이어뿐이라 멀리 있는 사람이 빠질 수 있다.
--      그래서 서버(server/PongDuRandomTeleportServer.lua)에 후보 목록을
--      요청하고, 응답을 받아 클라에서 세이프존 필터 + 추첨 + 이동한다.
--      후보가 없거나(SP 포함) 응답/청크 로딩이 시간 초과되거나 대상 주변에
--      착지할 칸이 없으면 편도로 대신 발동한다 -- 후원이 증발하지 않게.

local MAX_ATTEMPTS       = 15    -- 사후 검증 실패 시 재추첨 한도
local MAX_PREROLLS       = 200   -- 메타그리드 사전 검사 재추첨 한도
local LOAD_TIMEOUT_TICKS = 600   -- 청크 로딩 대기 한도 (약 10초 @60fps)
local REQUEST_TIMEOUT_TICKS = 300   -- 서버 후보 목록 응답 대기 한도 (약 5초)
local TARGET_SPOT_RADIUS = 4     -- 대상 주변 착지칸 탐색 반경 (차량 위 대비)

local MODE_ONEWAY    = 1
local MODE_ROUNDTRIP = 2
local MODE_PLAYER    = 3

local CMD_MODULE = "PongDuRT"

-- 진행 중이면 kind별로:
--   "ring"    {origin, cx, cy, attempts, waitTicks}
--   "request" {req, waitTicks}                      -- 서버 응답 대기
--   "player"  {origin, name, tx, ty, tz, waitTicks} -- 대상 위치 청크 로딩 대기
local state = nil
local reqSeq = 0
local onTickDispatch   -- 아래에서 정의 (ensureLoop가 먼저 참조)
local tickHandler = nil

-- ── 샌드박스 옵션 (사용 시점에 읽음) ─────────────────────────────────────────
-- 거리: PongDu.RT_MinDist / RT_MaxDist. 두 옵션은 서로 독립이라 샌박에서
-- max < min으로 설정할 수 있다 -- 이건 min으로 클램프한다(값 범위 자체는
-- sandbox-options.txt가 보장하므로 하한 클램프는 없음).
local function distCfg()
    local sv = SandboxVars.PongDu
    local mn, mx = sv.RT_MinDist, sv.RT_MaxDist
    if mx < mn then mx = mn end
    return mn, mx
end

-- 방식: PongDu.RT_Mode (1 편도 / 2 왕복 / 3 랜덤 플레이어에게)
local function modeCfg()
    return SandboxVars.PongDu.RT_Mode
end

-- 왕복 생존시간(분): PongDu.RT_SurviveMinutes
local function surviveMinutesCfg()
    return SandboxVars.PongDu.RT_SurviveMinutes
end

-- 메타그리드 기준 사전 검사: 맵 범위 밖 / 존재하지 않는 셀 걸러냄
local function isMetaValid(x, y)
    local meta = getWorld():getMetaGrid()
    if not meta then return false end
    if not meta:isValidSquare(x, y) then return false end
    if not meta:isValidChunk(math.floor(x / 10), math.floor(y / 10)) then return false end
    return true
end

-- 원점 기준 반경 min~max 링 안에서 메타 유효 + 세이프존 밖 좌표 하나 추첨.
-- 실패 시 nil (세이프하우스가 링을 다 덮은 극단적 경우 포함).
local function rollCandidate(ox, oy)
    local minR, maxR = distCfg()
    for _ = 1, MAX_PREROLLS do
        local r = minR + ZombRand(maxR - minR + 1)
        local a = math.rad(ZombRand(360))
        local x = math.floor(ox + r * math.cos(a) + 0.5)
        local y = math.floor(oy + r * math.sin(a) + 0.5)
        -- 메타 유효 && 세이프존 밖 (둘 다 만족해야 후보로 채택)
        if isMetaValid(x, y) and not zone.c(x, y) then return x, y end
    end
    return nil
end

-- 차량 탑승 중이면 강제 하차. B41엔 removePassenger가 없고 exit(chr)가 정석:
-- clearPassenger + setVehicle(nil) + collidable 복구 + MP sendExit 동기화까지 처리
-- (바닐라 ISExitVehicle:perform 참조).
-- exit()은 OnExitVehicle을 발화하지 않는다. 이 이벤트를 소비하는 건
-- ISVehicleDashboard.onExitVehicle 하나뿐이고 거기서 setVehicle(nil) ->
-- removeFromUIManager 를 하므로, 빠뜨리면 대시보드가 화면에 남는다.
-- 엔진도 같은 상황(GameClient.receiveTeleport)에서 exit() 다음 줄에 붙여놨다.
local function forceExitVehicle(p)
    local v = p:getVehicle()
    if not v then return end
    v:exit(p)
    p:PlayAnim("Idle")
    triggerEvent("OnExitVehicle", p)
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

-- ── 생존 복귀 (RT_Mode = 왕복) ──────────────────────────────────────────────
-- 착지 확정 시점부터 생존시간(RT_SurviveMinutes, 분) 카운트다운. 살아서 버티면
-- exile과 동일하게 원래 위치로 자동 복귀. 상태는 player modData
-- (rtReturnMs/rtOrigin)에 저장해 재접속 복구를 지원한다 -- exile의
-- returnTime/originalPosition과 키를 분리해 두 기능이 동시 진행돼도 서로 안
-- 덮는다. 사망 시 취소 (exile과 동일 정책).
-- 카운트다운 중 랜텔 재발동 시: 세이프존 중 좀비룰렛류가 큐박스 슬롯에서 락되는
-- 것과 완전히 동일한 방식으로 처리한다 -- 도네큐박스가 randomteleport.isBusy()를
-- 매 틱 확인해서 슬롯에 자물쇠를 걸고, 카운트다운이 끝나 원점으로 복귀하면
-- 락이 풀리며 준비 카운트다운 후 다음 유닛이 발동된다. 즉 대기 상태가 큐박스
-- UI에 그대로 보이고, 접속 종료 시 저장/복원도 기존 큐 로직을 그대로 탄다.
-- (여기서 rtPending 같은 자체 큐를 들고 있으면 큐박스와 이중 관리가 된다.)
-- 남은 시간은 ms 단위(rtReturnMs), 감산은 실제 경과시간 기준 (utils/deltaTime).
-- 구버전 세이브의 rtReturnTime(틱, 1틱=1/60초 가정)은 복구 시 ms로 1회 환산한다.
local deltaTime = require("utils/deltaTime")

local function rtMigrateLegacy(md)
    if md.rtReturnTime ~= nil then
        if (md.rtReturnTime or 0) > 0 and not md.rtReturnMs then
            md.rtReturnMs = md.rtReturnTime * 1000 / 60
            global.b(" random_teleport: migrated legacy rtReturnTime ticks="
                .. tostring(md.rtReturnTime) .. " -> ms=" .. tostring(math.floor(md.rtReturnMs)))
        end
        md.rtReturnTime = nil
    end
end

local RTReturnTimerDisplay = ISPanel:derive("RTReturnTimerDisplay")
local _retTick  = nil
local _retPanel = nil

function RTReturnTimerDisplay:new(player)
    local w = getCore():getScreenWidth()
    -- y좌표는 timerStack이 등록 순서에 맞춰 잡아준다(register 전까지는 임시값 0).
    -- 다른 타이머(봄바드/레인/화력지원)와 동일 규격: 폭 240, 폰트 Medium.
    local o = ISPanel:new(w / 2 - 120, 0, 240, 30)
    setmetatable(o, self)
    self.__index = self
    o.player = player
    o:noBackground()
    return o
end

function RTReturnTimerDisplay:render()
    local t = self.player:getModData().rtReturnMs or 0
    local sec = math.floor(t / 1000)
    local col = colorMap.get("random_teleport")
    textOutline.drawCentre(self, getText("IGUI_donation_random_teleport") .. " "
        .. string.format("%02d:%02d", math.floor(sec / 60), sec % 60),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
end

function RTReturnTimerDisplay:update()
    if (self.player:getModData().rtReturnMs or 0) <= 0 then
        timerStack.unregister(self)
        self:removeFromUIManager()
        _retPanel = nil
    end
end

local function rtDoReturn(p)
    local md = p:getModData()
    local o = md.rtOrigin
    if o then
        getSoundManager():PlaySound("anomaly_reversed", false, 1.0)
        forceExitVehicle(p)
        movePlayer(p, o.x, o.y, o.z)
        global.b(" random_teleport: survived, returned to origin")
    end
    md.rtReturnMs = 0
    md.rtOrigin = nil
    -- 대기 중이던 후속 랜텔은 큐박스 슬롯에 락 상태로 남아 있다. 여기서
    -- rtReturnMs가 0이 되는 순간 다음 틱에 락이 풀리며 큐박스가 알아서 발동한다.
end

local function rtStopCountdown(p)
    local md = p and p:getModData()
    if md then
        md.rtReturnMs = 0
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
        if not md.rtReturnMs or md.rtReturnMs <= 0 then
            Events.OnTick.Remove(_retTick)
            _retTick = nil
            return
        end
        md.rtReturnMs = md.rtReturnMs - deltaTime.ms()
        if md.rtReturnMs <= 0 then
            md.rtReturnMs = 0
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
        timerStack.register(_retPanel)
    end
end

-- 링 착지 확정 시 호출. 방식이 왕복이 아니면 아무것도 안 함.
local function rtArmReturn(p, origin)
    if modeCfg() ~= MODE_ROUNDTRIP then return end
    local mins = surviveMinutesCfg()
    local md = p:getModData()
    if not md.rtOrigin then
        md.rtOrigin = { x = origin.x, y = origin.y, z = origin.z }
    end
    md.rtReturnTime = nil
    md.rtReturnMs = mins * 60 * 1000   -- 분 -> ms (실제 경과시간 감산, 폭격과 동일)
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
    rtMigrateLegacy(md)
    if md.rtReturnMs and md.rtReturnMs > 0 and md.rtOrigin then
        if modeCfg() == MODE_ROUNDTRIP then
            rtStartTicker(p)
        else
            -- 접속 종료 사이에 방식이 왕복에서 바뀐 경우: 복귀 없이 취소.
            -- 남겨두면 isBusy는 false인데 복귀만 따로 도는 어긋난 상태가 된다.
            global.b(" random_teleport: saved return countdown discarded (mode="
                .. tostring(modeCfg()) .. ")")
            md.rtReturnMs = 0
            md.rtOrigin = nil
        end
    end
    _rtRecoveryDone = true
    Events.OnTick.Remove(rtRecovery)
end
Events.OnTick.Add(rtRecovery)

local function ensureLoop()
    if tickHandler then return end
    tickHandler = onTickDispatch
    Events.OnTick.Add(tickHandler)
end

-- 링 텔포 시작 (편도/왕복, 그리고 랜덤 플레이어 방식의 대체 발동).
-- origin: 복귀/포기 시 돌아갈 좌표. 실패 시 false.
local function startRing(p, origin, why)
    local cx, cy = rollCandidate(origin.x, origin.y)
    if not cx then
        global.b(" random_teleport: no meta-valid candidate around origin, aborting")
        stopLoop()
        return false
    end
    forceExitVehicle(p)
    state = { kind = "ring", origin = origin, cx = cx, cy = cy, attempts = 1, waitTicks = 0 }
    global.b(string.format(" random_teleport: ring start mode=%s reason=%s origin=%d,%d target=%d,%d",
        tostring(modeCfg()), tostring(why), math.floor(origin.x), math.floor(origin.y), cx, cy))
    movePlayer(p, cx + 0.5, cy + 0.5, 0)
    ensureLoop()
    return true
end

-- 랜덤 플레이어 방식이 실패했을 때 편도로 대체 발동. 원점은 이동 전 위치.
local function fallbackRing(p, origin, why)
    global.b(" random_teleport: player mode fallback to one-way, reason=" .. tostring(why))
    startRing(p, origin, "fallback:" .. tostring(why))
end

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

local function tickRing(p)
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
        rtArmReturn(p, state.origin)   -- 생존 복귀 (왕복 방식일 때만)
        stopLoop()
    else
        rerollOrGiveUp(p)
    end
end

local function tickRequest(p)
    state.waitTicks = state.waitTicks + 1
    if state.waitTicks > REQUEST_TIMEOUT_TICKS then
        local origin = { x = p:getX(), y = p:getY(), z = p:getZ() }
        global.b(" random_teleport: target list request timed out, req=" .. tostring(state.req))
        fallbackRing(p, origin, "request timeout")
    end
end

-- 대상 주변 착지칸 탐색. 대상 칸 자체를 먼저 보고, 막혀 있으면(대상이 차량에
-- 타고 있는 경우 등) 반경을 넓혀 테두리 칸만 훑는다. 차량과 겹치는 칸은 제외 --
-- 차체 안에 끼면 물리 충돌로 튕기거나 갇힌다.
local function isSpotFree(sq)
    return sq ~= nil and isLandable(sq) and not sq:isVehicleIntersecting()
end

local function findSpotNear(tx, ty, tz)
    local cell = getCell()
    if isSpotFree(cell:getGridSquare(tx, ty, tz)) then return tx, ty end
    for r = 1, TARGET_SPOT_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                if math.abs(dx) == r or math.abs(dy) == r then
                    if isSpotFree(cell:getGridSquare(tx + dx, ty + dy, tz)) then
                        return tx + dx, ty + dy
                    end
                end
            end
        end
    end
    return nil
end

local function tickPlayer(p)
    local sq = getCell():getGridSquare(state.tx, state.ty, state.tz)
    if sq == nil then
        state.waitTicks = state.waitTicks + 1
        if state.waitTicks > LOAD_TIMEOUT_TICKS then
            global.b(" random_teleport: chunk load timeout at target " .. tostring(state.name))
            fallbackRing(p, state.origin, "target chunk timeout")
        end
        return
    end

    local x, y = findSpotNear(state.tx, state.ty, state.tz)
    if not x then
        global.b(string.format(" random_teleport: no landable spot near target %s at %d,%d,%d",
            tostring(state.name), state.tx, state.ty, state.tz))
        fallbackRing(p, state.origin, "no spot near target")
        return
    end
    movePlayer(p, x + 0.5, y + 0.5, state.tz)
    global.b(string.format(" random_teleport: landed near player %s at %d,%d,%d",
        tostring(state.name), x, y, state.tz))
    stopLoop()
end

onTickDispatch = function()
    if not state then
        stopLoop()
        return
    end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then
        stopLoop()
        return
    end
    if state.kind == "ring" then
        tickRing(p)
    elseif state.kind == "request" then
        tickRequest(p)
    elseif state.kind == "player" then
        tickPlayer(p)
    else
        global.b(" random_teleport: unknown state kind " .. tostring(state.kind))
        stopLoop()
    end
end

-- 서버 후보 목록 응답. 요청 번호가 현재 대기 중인 것과 다르면(시간 초과 후
-- 늦게 온 응답 등) 버린다 -- 이미 편도로 대체 발동했을 수 있다.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= CMD_MODULE or command ~= "Targets" then return end
    local req = tonumber(args and args["req"])
    if not state or state.kind ~= "request" or req ~= state.req then
        global.b(" random_teleport: stale target list ignored, req=" .. tostring(req))
        return
    end
    local p = getSpecificPlayer(0)
    if not p or p:isDead() then
        stopLoop()
        return
    end

    local origin = { x = p:getX(), y = p:getY(), z = p:getZ() }
    local cands, total, inZone = {}, 0, 0
    local list = args["list"]
    if type(list) == "table" then
        for _, t in pairs(list) do
            local x = t and tonumber(t["x"])
            local y = t and tonumber(t["y"])
            local z = t and tonumber(t["z"])
            if x and y and z then
                total = total + 1
                -- 세이프존 제외는 링 텔포와 같은 기준 (utils/zone.c)
                if zone.c(x, y) then
                    inZone = inZone + 1
                else
                    cands[#cands + 1] = { name = tostring(t["name"]), x = x, y = y, z = z }
                end
            end
        end
    end
    global.b(string.format(" random_teleport: target list received total=%d inSafezone=%d usable=%d",
        total, inZone, #cands))

    if #cands == 0 then
        fallbackRing(p, origin, "no eligible player")
        return
    end

    local t = cands[ZombRand(#cands) + 1]
    forceExitVehicle(p)
    state = { kind = "player", origin = origin, name = t.name,
              tx = t.x, ty = t.y, tz = t.z, waitTicks = 0 }
    global.b(string.format(" random_teleport: picked player %s at %d,%d,%d",
        t.name, t.x, t.y, t.z))
    movePlayer(p, t.x + 0.5, t.y + 0.5, t.z)
end)

-- isBusy(player) -> true면 지금 랜텔을 새로 발동하면 안 되는 상태.
-- 도네큐박스(DonationReceiver)가 매 틱 확인해서 슬롯에 자물쇠(락)를 걸고,
-- false로 바뀌면 락이 풀리며 준비 카운트다운 후 다음 유닛이 발동된다.
--   1) 진행 중(state ~= nil): 서버 응답 대기 / 착지 검증 루프. 좌표가 아직 확정
--      안 됐다. 이 상태에서 재발동하면 기존 루프가 버려지고 원점이 현재(=텔포된)
--      위치로 갱신돼 복귀 지점이 어긋난다. 방식과 무관하게 잠근다.
--   2) 복귀 카운트다운 진행 중(방식 = 왕복 && rtReturnMs > 0): 타이머가 끝나
--      원점으로 돌아올 때까지 다음 텔포를 잠근다.
function randomteleport.isBusy(player)
    if state ~= nil then return true end
    if not player then return false end
    if modeCfg() ~= MODE_ROUNDTRIP then return false end
    local md = player:getModData()
    rtMigrateLegacy(md)   -- 복구보다 먼저 호출돼도 구버전 값을 놓치지 않게
    return (md.rtReturnMs or 0) > 0
end

-- 랜덤 텔레포트 발동  [public name: .a]
function randomteleport.a(player)
    if not player then return end

    -- 안전망. 정상 경로(큐박스)는 isBusy 동안 슬롯을 락해두므로 여기 도달하지
    -- 않는다. 큐박스를 거치지 않는 직접 호출까지 통과시키면 복귀 원점이 어긋나므로
    -- 막는다 -- 이 경로엔 재큐잉할 곳이 없어 요청은 버려진다.
    if randomteleport.isBusy(player) then
        global.b(" random_teleport: aborted, busy (landing check or return countdown active)")
        return
    end

    -- 이미 진행 중이면 기존 루프를 버리고 현재 위치 기준으로 새로 시작
    stopLoop()

    local mode = modeCfg()
    global.b(" random_teleport: start mode=" .. tostring(mode))
    local origin = { x = player:getX(), y = player:getY(), z = player:getZ() }

    if mode == MODE_PLAYER then
        -- SP는 sendServerCommand가 아무것도 안 하므로 응답이 영영 안 온다.
        -- 어차피 다른 접속자도 없으니 바로 편도로 대체한다.
        if not isClient() then
            fallbackRing(player, origin, "not multiplayer")
            return
        end
        reqSeq = reqSeq + 1
        state = { kind = "request", req = reqSeq, waitTicks = 0 }
        ensureLoop()
        sendClientCommand(player, CMD_MODULE, "Targets", { ["req"] = reqSeq })
        global.b(" random_teleport: target list requested, req=" .. tostring(reqSeq))
        return
    end

    startRing(player, origin, "mode")
end

return randomteleport
