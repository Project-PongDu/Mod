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
        task.pathOwnerId = HitmanUtils.GetCharacterID(getSpecificPlayer(0))
    end

    return true
end

HitmanZombieActions.GoTo.onWorking = function(zombie, task)

    -- COMPAT: same controller-handoff issue as Move (see ZAMove.lua). GoTo
    -- only issues pathToLocationF once, in onStart, on whichever client was
    -- controller at that moment. If authority hands off to a new closest
    -- player mid-task, re-issue it here so movement doesn't silently stall
    -- while the walk animation keeps playing.
    local isController = HitmanUtils.IsController(zombie)
    HitmanUtils.CheckAuthMismatch(zombie, isController, "GoTo")
    if isController then
        local myId = HitmanUtils.GetCharacterID(getSpecificPlayer(0))
        if task.pathOwnerId ~= myId then
            zombie:pathToLocationF(task.x, task.y, task.z)
            task.pathOwnerId = myId
        end
    end

    return false
end

HitmanZombieActions.GoTo.onComplete = function(zombie, task)
    return true
end



