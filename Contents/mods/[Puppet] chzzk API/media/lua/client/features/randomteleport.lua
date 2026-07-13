local randomteleport = {}
local global = require("global")

-- ── 랜덤 텔레포트 (random_teleport) ──────────────────────────────────────────
-- 발동 시점 위치를 원점으로, 반경 100~200타일 링 안의 랜덤 좌표로 이동.
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

local MIN_RADIUS         = 100
local MAX_RADIUS         = 200
local MAX_ATTEMPTS       = 15    -- 사후 검증 실패 시 재추첨 한도
local MAX_PREROLLS       = 200   -- 메타그리드 사전 검사 재추첨 한도
local LOAD_TIMEOUT_TICKS = 600   -- 청크 로딩 대기 한도 (약 10초 @60fps)

local state = nil   -- 진행 중이면 {origin, cx, cy, attempts, waitTicks}
local tickHandler = nil

-- 메타그리드 기준 사전 검사: 맵 범위 밖 / 존재하지 않는 셀 걸러냄
local function isMetaValid(x, y)
    local meta = getWorld():getMetaGrid()
    if not meta then return false end
    if not meta:isValidSquare(x, y) then return false end
    if not meta:isValidChunk(math.floor(x / 10), math.floor(y / 10)) then return false end
    return true
end

-- 원점 기준 반경 100~200 링 안에서 메타 유효 좌표 하나 추첨. 실패 시 nil.
local function rollCandidate(ox, oy)
    for _ = 1, MAX_PREROLLS do
        local r = MIN_RADIUS + ZombRand(MAX_RADIUS - MIN_RADIUS + 1)
        local a = math.rad(ZombRand(360))
        local x = math.floor(ox + r * math.cos(a) + 0.5)
        local y = math.floor(oy + r * math.sin(a) + 0.5)
        if isMetaValid(x, y) then return x, y end
    end
    return nil
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
        getSoundManager():PlaySound("exile_exit", false, 1.0)
        global.b(string.format(" random_teleport: landed at %d,%d (attempt %d)",
            state.cx, state.cy, state.attempts))
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

    local v = player:getVehicle()
    if v then v:removePassenger(player) end

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
