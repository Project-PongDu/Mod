HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.SmashWindow = {}
HitmanZombieActions.SmashWindow.onStart = function(zombie, task)
    return true
end

HitmanZombieActions.SmashWindow.onWorking = function(zombie, task)
    zombie:faceLocationF(task.x, task.y)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
end

HitmanZombieActions.SmashWindow.onComplete = function(zombie, task)

    local cell = zombie:getSquare():getCell()
    local square = cell:getGridSquare(task.x, task.y, task.z)
    if square then
        local window = square:getWindow()
        if window then
            window:smashWindow()
        end
    end
    return true
end