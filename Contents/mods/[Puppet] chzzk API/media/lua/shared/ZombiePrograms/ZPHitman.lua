ZombiePrograms = ZombiePrograms or {}

ZombiePrograms.Hitman = {}
ZombiePrograms.Hitman.Stages = {}

ZombiePrograms.Hitman.Init = function(hitman)
end

ZombiePrograms.Hitman.Prepare = function(hitman)
    local tasks = {}

    Hitman.ForceStationary(hitman, false)

    return {status=true, next="Main", tasks=tasks}
end

ZombiePrograms.Hitman.Main = function(hitman)
    local tasks = {}
    local cell = getCell()
    local bx, by, bz = hitman:getX(), hitman:getY(), hitman:getZ()
    local endurance = 0.00
    local walkType = "Run"

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

    local config = {}
    config.mustSee = true
    config.hearDist = 7

    if Hitman.HasExpertise(hitman, Hitman.Expertise.Recon) then
        config.hearDist = 20
    elseif Hitman.HasExpertise(hitman, Hitman.Expertise.Tracker) then
        config.hearDist = 60
    end

    local target, enemy = HitmanUtils.GetTarget(hitman, config)

    -- engage with target
    if target.x and target.y and target.z then
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

    local task = {action="Time", anim="Shrug", time=200}
    table.insert(tasks, task)

    return {status=true, next="Main", tasks=tasks}
end
