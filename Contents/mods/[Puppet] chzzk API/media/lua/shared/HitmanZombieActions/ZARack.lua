HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Rack = {}
HitmanZombieActions.Rack.onStart = function(zombie, task)
    return true
end

HitmanZombieActions.Rack.onWorking = function(zombie, task)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
end

HitmanZombieActions.Rack.onComplete = function(zombie, task)

    local brain = HitmanBrain.Get(zombie)
    local weapon = brain.weapons[task.slot]
    weapon.racked = true

    return true
end