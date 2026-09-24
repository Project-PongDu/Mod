HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Move = {}

-- DIAG: how long a hitman waits for PolygonalMap2 to hand back a path.
-- Hitmen always have target == nil, so their requests sit in the lowest
-- priority queue behind every aggro zombie; long waits show up here.
local PATH_WAIT_WARN_MS = 1000
local PATH_LOG_COOLDOWN_MS = 2000
local lastPathLogMs = 0

local function PathLog(msg)
    local now = getTimestampMs()
    if now - lastPathLogMs < PATH_LOG_COOLDOWN_MS then return end
    lastPathLogMs = now
    local zcnt = HitmanZombie and HitmanZombie.LastSize or -1
    print("[PongDu][Hitman] " .. msg .. " zombiesInCell=" .. tostring(zcnt))
end
HitmanZombieActions.Move.onStart = function(zombie, task)

    if not zombie:getSquare():isFree(false) then
        local asquare = AdjacentFreeTileFinder.Find(zombie:getSquare(), zombie)
        if asquare then
            zombie:setX(asquare:getX() + 0.5)
            zombie:setY(asquare:getY() + 0.5)
        end
    end

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
        zombie:getPathFindBehavior2():pathToLocation(task.x, task.y, task.z)
        zombie:getPathFindBehavior2():cancel()
        zombie:setPath2(nil)
        task.pathOwnerId = HitmanUtils.GetCharacterID(getSpecificPlayer(0))
        task.pathReqMs = getTimestampMs()
        task.pathGot = nil
    end

    return true
end

HitmanZombieActions.Move.onWorking = function(zombie, task)

    zombie:setVariable("HitmanWalkType", task.walkType)

    if HitmanCompatibility.GetGameVersion() >= 42 then
        if task.backwards then
            zombie:setAnimatingBackwards(true)
        else
            zombie:setAnimatingBackwards(false)
        end
    end

    --[[
    if zombie:getSquare():isFree(false) then
        zombie:setCollidable(true)
    else
        zombie:setCollidable(false)
    end]]
    -- local finder = zombie:getFinder()
    local isController = HitmanUtils.IsController(zombie)
    HitmanUtils.CheckAuthMismatch(zombie, isController, "Move")
    if isController then
        local cell = getCell()

        -- COMPAT: controller authority (closest-player) can flip mid-task in MP.
        -- pathToLocation was only issued once, in onStart, by whoever was
        -- controller back then. If a different client just became controller,
        -- its pathFindBehavior2 was never given this destination, so update()
        -- would run on an empty/stale path -> the zombie's animation keeps
        -- playing while it doesn't actually move (looks like slow motion).
        -- Re-issue the path request on handoff.
        local myId = HitmanUtils.GetCharacterID(getSpecificPlayer(0))
        if task.pathOwnerId ~= myId then
            zombie:getPathFindBehavior2():pathToLocation(task.x, task.y, task.z)
            zombie:getPathFindBehavior2():cancel()
            zombie:setPath2(nil)
            task.pathOwnerId = myId
            task.pathReqMs = getTimestampMs()
            task.pathGot = nil
        end

        --[[if ZombRand(1000) == 1 then
            zombie:getPathFindBehavior2():pathToLocation(task.x+1, task.y+1, task.z)
            zombie:getPathFindBehavior2():cancel()
            zombie:setPath2(nil)
        end]]

        local result = zombie:getPathFindBehavior2():update()

        -- path2 stays nil until PathFindBehavior2 receives the finished path
        if task.pathReqMs and not task.pathGot and zombie:getPath2() then
            task.pathGot = true
            local waited = getTimestampMs() - task.pathReqMs
            if waited >= PATH_WAIT_WARN_MS then
                PathLog("slow path: waited " .. waited .. "ms (hitman=" .. tostring(HitmanUtils.GetZombieID(zombie)) .. ")")
            end
        end

        if result == BehaviorResult.Failed then
            if task.pathReqMs then
                PathLog("path failed after " .. (getTimestampMs() - task.pathReqMs) .. "ms, gotPath=" .. tostring(task.pathGot == true)
                    .. " (hitman=" .. tostring(HitmanUtils.GetZombieID(zombie)) .. ")")
            end
            return true
        end
        if result == BehaviorResult.Succeeded then
            return true
        end
    end

    return false
end

HitmanZombieActions.Move.onComplete = function(zombie, task)
    if HitmanUtils.IsController(zombie) then
        zombie:getPathFindBehavior2():cancel()
        zombie:getPathFindBehavior2():reset()
    end
    return true
end



