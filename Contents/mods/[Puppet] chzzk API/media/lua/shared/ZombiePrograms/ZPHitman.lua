HitmanZombiePrograms = HitmanZombiePrograms or {}

HitmanZombiePrograms.Hitman = {}
HitmanZombiePrograms.Hitman.Stages = {}

-- [hitman id] = last logged chase mode, for transition-only logging
local chaseLogMode = {}

local function LogChase(hitman, mode, target)
    local brain = HitmanBrain.Get(hitman)
    if not brain or chaseLogMode[brain.id] == mode then return end
    chaseLogMode[brain.id] = mode
    if target and target.x then
        print(string.format("[PongDu][Hitman] id=%s chase=%s pid=%s dist=%.1f", tostring(brain.id), mode, tostring(target.id), target.dist or -1))
    else
        print("[PongDu][Hitman] id=" .. tostring(brain.id) .. " chase=" .. mode)
    end
end

HitmanZombiePrograms.Hitman.Init = function(hitman)
end

HitmanZombiePrograms.Hitman.Prepare = function(hitman)
    local tasks = {}

    Hitman.ForceStationary(hitman, false)

    return {status=true, next="Main", tasks=tasks}
end

HitmanZombiePrograms.Hitman.Main = function(hitman)
    local tasks = {}
    local cell = getCell()
    local bx, by, bz = hitman:getX(), hitman:getY(), hitman:getZ()
    local endurance = 0.00
    local walkType = "Run"

    local config = {}
    config.mustSee = true
    config.hearDist = 7

    if Hitman.HasExpertise(hitman, Hitman.Expertise.Recon)
    and Hitman.HasExpertise(hitman, Hitman.Expertise.Tracker) then
        config.hearDist = 80

    elseif Hitman.HasExpertise(hitman, Hitman.Expertise.Recon) then
        config.hearDist = 20

    elseif Hitman.HasExpertise(hitman, Hitman.Expertise.Tracker) then
            config.hearDist = 60
    end

    -- PONGDU: players only (see HitmanUtils.GetTarget). Zombies are never chased.
    local target, enemy = HitmanUtils.GetTarget(hitman, config)

    -- engage with a player that is seen or heard: top priority
    if target.x and target.y and target.z and not target.tracked then
        LogChase(hitman, "seen", target)

        local targetSquare = cell:getGridSquare(target.x, target.y, target.z)
        if targetSquare then
            Hitman.SayLocation(hitman, targetSquare)
        end

        local tx, ty, tz = target.x, target.y, target.z

        if enemy then
            if target.fx and target.fy and (enemy:isRunning()  or enemy:isSprinting()) then
                tx, ty = target.fx, target.fy
            end
        end

        local walkType = Hitman.GetCombatWalktype(hitman, enemy, target.dist)

        table.insert(tasks, HitmanUtils.GetMoveTask(endurance, tx, ty, tz, walkType, target.dist))
        return {status=true, next="Main", tasks=tasks}
    end

    -- nobody perceived: light up the room first (helps spotting), then keep tracking
    local room = hitman:getSquare():getRoom()
    if room then
        local lsList = room:getLightSwitches()
        local distBest = math.huge
        local lsBest
        for i=0, lsList:size()-1 do
            local ls = lsList:get(i)
            local square = ls:getSquare()
            if not ls:isActivated() and square:isFree(false) then
                local tx, ty, tz = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
                local dist = HitmanUtils.DistTo(bx, by, tx, ty)
                if dist < distBest then
                    distBest = dist
                    lsBest = ls
                end
            end
        end

        if lsBest then
            local square = lsBest:getSquare()
            local tx, ty, tz = square:getX() + 0.5, square:getY() + 0.5, square:getZ()
            local dist = HitmanUtils.DistTo(bx, by, tx, ty)
            if distBest < 1.2 and bz == tz then
                local task = {action="LightToggle", time=20, active=true, x=tx, y=ty, z=tz}
                table.insert(tasks, task)
                return {status=true, next="Main", tasks=tasks}
            else
                table.insert(tasks, HitmanUtils.GetMoveTask(endurance, tx, ty, tz, walkType, dist, false))
                return {status=true, next="Main", tasks=tasks}
            end
        end
    end

    -- track the summoner (donation recipient) or the closest player
    if target.x and target.y and target.z then
        LogChase(hitman, "tracked", target)

        local walkType = Hitman.GetCombatWalktype(hitman, nil, target.dist)
        table.insert(tasks, HitmanUtils.GetMoveTask(endurance, target.x, target.y, target.z, walkType, target.dist))
        return {status=true, next="Main", tasks=tasks}
    end

    LogChase(hitman, "none")
    local task = {action="Time", anim="Shrug", time=200}
    table.insert(tasks, task)

    return {status=true, next="Main", tasks=tasks}
end
