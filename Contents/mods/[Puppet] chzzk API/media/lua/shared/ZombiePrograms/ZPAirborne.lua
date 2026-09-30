HitmanZombiePrograms = HitmanZombiePrograms or {}

-- ═══════════════════════════════════════════════════════════════════════════
--  공수부대원 (fire_support/airborne) 이동 프로그램 -- 순찰
--
--  호위 대상(소환자 = 후원받은 플레이어, 없으면 최근접 플레이어 --
--  HitmanUtils.GetTrackedPlayer)을 중심으로 반지름 PATROL_R 원 위에 순찰 지점
--  PATROL_POINTS 개를 깔고, 한 방향으로 한 지점씩 돈다.
--    - 지점 사이는 총을 겨눈 채 걷는다(WalkAim).
--    - 지점에 닿으면 바깥쪽(호위 대상 반대편)을 향해 PATROL_SCAN 틱 동안 경계한다.
--    - 지점은 매번 호위 대상의 "현재" 위치로 다시 계산하므로 대상이 움직이면
--      순찰 원도 같이 따라간다.
--    - 대원마다 시작 지점과 도는 방향을 id 로 정해, 여러 명이면 흩어져 돈다.
--    - 막힌 지점(벽/물/실내외가 대상과 다름)은 건너뛴다. 한 구간이
--      PATROL_LEG_MS 안에 안 끝나면(길막) 다음 지점으로 넘어간다.
--    - 호위 대상과 LEASH_R 보다 멀어지면 순찰을 멈추고 원 위 가장 가까운 지점으로
--      달려 복귀한다.
--  교전(표적 고정/후퇴)은 HitmanUpdate.lua ManageCombat + features/airborne.lua 가
--  맡고 여기선 이동만 만든다. 탄이 바닥난 근접 모드에서는 ManageCombat 이 남긴
--  추격 지점(brain.abChase)으로 붙는다.
--  강하/착지 중에는 features/airborne.lua 가 AI 를 잡고 있어 호출되지 않는다.
-- ═══════════════════════════════════════════════════════════════════════════
HitmanZombiePrograms.Airborne = {}
HitmanZombiePrograms.Airborne.Stages = {}

local PATROL_R      = 6      -- 순찰 원 반지름 (타일)
local PATROL_POINTS = 8      -- 원 위 순찰 지점 수 (45도 간격)
local PATROL_REACH  = 1.3    -- 지점 도착 판정 거리
local PATROL_SCAN   = 120    -- 지점마다 경계하는 시간 (틱, 1/60초)
local PATROL_LEG_MS = 8000   -- 한 구간 최대 시간 (길막 대비)
local LEASH_R       = 12     -- 호위 대상과 이보다 멀면 달려서 복귀
local CHASE_TTL_MS  = 1000   -- ManageCombat 추격 지점 유효시간

local TWO_PI = math.pi * 2

local function ringPoint(ex, ey, i)
    local a = (i % PATROL_POINTS) * TWO_PI / PATROL_POINTS
    return ex + math.cos(a) * PATROL_R, ey + math.sin(a) * PATROL_R
end

-- 호위 대상과 같은 실내/실외인, 서 있을 수 있는 칸만 순찰 지점으로 쓴다
local function pointOk(cell, x, y, z, outside)
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), z)
    if not sq or not sq:isFree(false) then return false end
    if sq:Is(IsoFlagType.water) then return false end
    return sq:isOutside() == outside
end

-- 원 위에서 대원 쪽에 가장 가까운 지점 번호
local function nearestIndex(ex, ey, bx, by)
    local a = math.atan2(by - ey, bx - ex)
    if a < 0 then a = a + TWO_PI end
    return math.floor(a / (TWO_PI / PATROL_POINTS) + 0.5) % PATROL_POINTS
end

HitmanZombiePrograms.Airborne.Init = function(hitman)
end

-- 착지 직후 1회: 총을 든 채로 순찰하게 주무기(없으면 보조무기)를 꺼낸다.
-- 히트맨은 원래 첫 교전에서야 무기를 드는데, 호위병이 맨손으로 서 있으면 어색하다.
HitmanZombiePrograms.Airborne.Prepare = function(hitman)
    local tasks = {}
    Hitman.ForceStationary(hitman, false)

    local brain = HitmanBrain.Get(hitman)
    local weapons = brain and brain.weapons
    local gun = weapons and ((weapons.primary and weapons.primary.name) or (weapons.secondary and weapons.secondary.name))
    if gun and not hitman:isPrimaryEquipped(gun) then
        tasks = HitmanPrograms.Weapon.Switch(hitman, gun)
        print("[PongDu][Airborne] trooper id=" .. tostring(brain.id) .. " ready, equipping " .. tostring(gun))
    end
    return {status=true, next="Main", tasks=tasks}
end

HitmanZombiePrograms.Airborne.Main = function(hitman)
    local tasks = {}
    local brain = HitmanBrain.Get(hitman)
    local now = getTimestampMs()
    local bx, by = hitman:getX(), hitman:getY()

    local escort = HitmanUtils.GetTrackedPlayer(hitman)
    if not escort then
        table.insert(tasks, {action="Time", anim="ShiftWeight", time=150})
        return {status=true, next="Main", tasks=tasks}
    end
    local ex, ey, ez = escort:getX(), escort:getY(), escort:getZ()
    local dist = HitmanUtils.DistTo(bx, by, ex, ey)

    -- 근접 모드 추격: 사거리에 들면 ManageCombat 이 친다
    local chase = brain.abChase
    if chase and now - chase.t < CHASE_TTL_MS then
        local cd = HitmanUtils.DistTo(bx, by, chase.x, chase.y)
        table.insert(tasks, HitmanUtils.GetMoveTask(0, chase.x, chase.y, chase.z, "Run", cd, false))
        return {status=true, next="Main", tasks=tasks}
    end

    local p = brain.abPatrol
    if not p then
        local id = tonumber(brain.id) or 0
        p = { i = id % PATROL_POINTS, dir = (math.floor(id / PATROL_POINTS) % 2 == 0) and 1 or -1 }
        brain.abPatrol = p
        print(string.format("[PongDu][Airborne] patrol start id=%s point=%d dir=%d r=%d",
            tostring(brain.id), p.i, p.dir, PATROL_R))
    end

    -- 호위 대상과 멀어졌으면 원 위 가장 가까운 지점으로 달려 복귀
    if dist > LEASH_R then
        p.i = nearestIndex(ex, ey, bx, by)
        p.legUntil = nil
        local tx, ty = ringPoint(ex, ey, p.i)
        table.insert(tasks, HitmanUtils.GetMoveTask(0, tx, ty, ez, "Run", HitmanUtils.DistTo(bx, by, tx, ty), false))
        return {status=true, next="Main", tasks=tasks}
    end

    -- 이번 지점이 막혀 있으면 같은 방향으로 다음 지점을 찾는다
    local cell = getCell()
    local esq = escort:getSquare()
    local outside = esq == nil or esq:isOutside()
    local tx, ty
    for _ = 1, PATROL_POINTS do
        tx, ty = ringPoint(ex, ey, p.i)
        if pointOk(cell, tx, ty, ez, outside) then break end
        p.i = (p.i + p.dir) % PATROL_POINTS
        p.legUntil = nil
        tx = nil
    end
    if not tx then
        -- 순찰 원 전체가 막힘(좁은 실내 등): 대상 곁에서 대기
        table.insert(tasks, {action="Time", anim="ShiftWeight", time=120})
        return {status=true, next="Main", tasks=tasks}
    end

    local d = HitmanUtils.DistTo(bx, by, tx, ty)
    if d <= PATROL_REACH then
        -- 도착: 바깥쪽을 보며 경계 후 다음 지점으로
        hitman:faceLocationF(tx + (tx - ex), ty + (ty - ey))
        p.i = (p.i + p.dir) % PATROL_POINTS
        p.legUntil = nil
        table.insert(tasks, {action="Time", anim="AimRifle", time=PATROL_SCAN})
        return {status=true, next="Main", tasks=tasks}
    end

    if not p.legUntil then p.legUntil = now + PATROL_LEG_MS end
    if now > p.legUntil then
        -- 길이 막혀 못 간 지점은 건너뛴다
        print(string.format("[PongDu][Airborne] patrol skip id=%s point=%d (not reached in %dms)",
            tostring(brain.id), p.i, PATROL_LEG_MS))
        p.i = (p.i + p.dir) % PATROL_POINTS
        p.legUntil = nil
        table.insert(tasks, {action="Time", anim="ShiftWeight", time=30})
        return {status=true, next="Main", tasks=tasks}
    end

    table.insert(tasks, HitmanUtils.GetMoveTask(0, tx, ty, ez, "WalkAim", d, false))
    return {status=true, next="Main", tasks=tasks}
end
