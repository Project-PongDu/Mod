HitmanZombiePrograms = HitmanZombiePrograms or {}

-- ═══════════════════════════════════════════════════════════════════════════
--  공수부대원 (fire_support/airborne) 이동 프로그램
--
--  호위 대상(소환자 = 후원받은 플레이어, 없으면 최근접 플레이어 --
--  HitmanUtils.GetTrackedPlayer) 주변 WANDER_R 타일 안을 배회한다.
--  교전(자기 위협 > 호위 대상 위협)은 HitmanUpdate.lua ManageCombat 이 맡고
--  여기선 이동만 만든다. 단, 탄이 바닥난 근접 모드에서는 ManageCombat 이 남긴
--  추격 지점(brain.abChase)으로 붙는다.
--  강하/착지 중에는 features/airborne.lua 가 AI 를 잡고 있어 호출되지 않는다.
-- ═══════════════════════════════════════════════════════════════════════════
HitmanZombiePrograms.Airborne = {}
HitmanZombiePrograms.Airborne.Stages = {}

local WANDER_R      = 10     -- 호위 대상 중심 배회 반경 (타일)
local WANDER_MIN_R  = 3      -- 호위 대상에게 너무 붙지 않게
local RUN_R         = 15     -- 이보다 멀면 달려서 따라붙는다
local WANDER_MAX_MS = 8000   -- 배회 지점 하나에 쓰는 최대 시간 (막힌 지점 대비)
local CHASE_TTL_MS  = 1000   -- ManageCombat 추격 지점 유효시간
local PAUSE_CHANCE  = 3      -- 배회 지점 도착 시 1/N 확률로 잠깐 선다

local function pointNear(ex, ey)
    local ang  = ZombRand(628) / 100.0
    local dist = WANDER_MIN_R + ZombRand((WANDER_R - WANDER_MIN_R) * 10) / 10.0
    return ex + math.cos(ang) * dist, ey + math.sin(ang) * dist
end

HitmanZombiePrograms.Airborne.Init = function(hitman)
end

-- 착지 직후 1회: 총을 든 채로 배회하게 주무기(없으면 보조무기)를 꺼낸다.
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
        brain.abWander = nil
        local cd = HitmanUtils.DistTo(bx, by, chase.x, chase.y)
        table.insert(tasks, HitmanUtils.GetMoveTask(0, chase.x, chase.y, chase.z, "Run", cd, false))
        return {status=true, next="Main", tasks=tasks}
    end

    -- 호위 대상과 멀어졌으면 대상 주변으로 복귀
    if dist > WANDER_R then
        brain.abWander = nil
        local tx, ty = pointNear(ex, ey)
        local walkType = dist > RUN_R and "Run" or "Walk"
        table.insert(tasks, HitmanUtils.GetMoveTask(0, tx, ty, ez, walkType, dist, false))
        return {status=true, next="Main", tasks=tasks}
    end

    -- 배회: 지점 하나를 도착/시간초과/대상 이탈까지 유지한다. 매번 새로 뽑으면
    -- 짧은 GoTo 가 계속 갈아끼워져 제자리에서 방향만 바꾼다.
    local w = brain.abWander
    if w then
        local wd = HitmanUtils.DistTo(bx, by, w.x, w.y)
        local drift = HitmanUtils.DistTo(w.x, w.y, ex, ey)
        if wd < 1.2 or now > w.untilMs or drift > WANDER_R then
            brain.abWander = nil
            if wd < 1.2 and ZombRand(PAUSE_CHANCE) == 0 then
                table.insert(tasks, {action="Time", anim="ShiftWeight", time=120})
                return {status=true, next="Main", tasks=tasks}
            end
        else
            table.insert(tasks, HitmanUtils.GetMoveTask(0, w.x, w.y, w.z, "Walk", wd, false))
            return {status=true, next="Main", tasks=tasks}
        end
    end

    local tx, ty = pointNear(ex, ey)
    brain.abWander = { x = tx, y = ty, z = ez, untilMs = now + WANDER_MAX_MS }
    table.insert(tasks, HitmanUtils.GetMoveTask(0, tx, ty, ez, "Walk", HitmanUtils.DistTo(bx, by, tx, ty), false))
    return {status=true, next="Main", tasks=tasks}
end
