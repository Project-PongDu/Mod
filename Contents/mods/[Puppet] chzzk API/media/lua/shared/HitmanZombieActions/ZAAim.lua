HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Aim = {}
HitmanZombieActions.Aim.onStart = function(zombie, task)
    task.tick = 1
    zombie:setBumpType(task.anim)
    return true
end

HitmanZombieActions.Aim.onWorking = function(zombie, task)
    task.tick = task.tick + 1
    zombie:faceLocationF(task.x, task.y)
    if zombie:getBumpType() ~= task.anim then 
        if task.tick < 10 then
            zombie:setBumpType(task.anim)
            -- print (task.tick .. " " .. task.anim)
        else
            return true
        end
    end
    return false
end

HitmanZombieActions.Aim.onComplete = function(zombie, task)
    Hitman.SetAim(zombie, true)
    return true
end