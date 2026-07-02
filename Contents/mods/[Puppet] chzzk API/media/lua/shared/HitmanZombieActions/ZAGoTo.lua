HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.GoTo = {}
HitmanZombieActions.GoTo.onStart = function(zombie, task)

    zombie:setVariable("HitmanWalkType", task.walkType)

    if not Hitman.IsMoving(zombie) then
        local dist = HitmanUtils.DistTo(zombie:getX(), zombie:getY(), task.x, task.y)
        if dist > 2 then
            local bump
            if task.walkType == "Run" then
                bump = "IdleToRun"
            elseif task.walkType == "Walk" then
                bump = "IdleToWalk"
            end

            if bump then
                zombie:setBumpType(bump)
            end
        end
        Hitman.SetMoving(zombie, true)
    elseif task.walkType == "Run" then
        local shouldTurn = false
        local faceDir = zombie:getDirectionAngle()
        local targetDir = HitmanUtils.CalcAngle(zombie:getX(), zombie:getY(), task.x, task.y)
        local angleDifference = faceDir - targetDir
        if angleDifference > 180 then
            angleDifference = angleDifference - 360
        elseif angleDifference < -180 then
            angleDifference = angleDifference + 360
        end
        if math.abs(angleDifference) > 130 then
            shouldTurn = true
            local bump = "IdleToRun"
            zombie:faceLocation(task.x, task.y)
            zombie:setBumpType(bump)
        end
    end

    if HitmanUtils.IsController(zombie) then
        zombie:pathToLocationF(task.x, task.y, task.z)
    end

    return true
end

HitmanZombieActions.GoTo.onWorking = function(zombie, task)

    return false
end

HitmanZombieActions.GoTo.onComplete = function(zombie, task)
    return true
end



