HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Unload = {}
HitmanZombieActions.Unload.onStart = function(zombie, task)
    return true
end

HitmanZombieActions.Unload.onWorking = function(zombie, task)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
end

HitmanZombieActions.Unload.onComplete = function(zombie, task)

    local brain = HitmanBrain.Get(zombie)
    local weapon = brain.weapons[task.slot]

    if weapon.type == "mag" and weapon.clipIn then
        weapon.clipIn = false
        weapon.racked = false

        local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
        if weaponItem:isManuallyRemoveSpentRounds() then
            shooter:playSound(item:getShellFallSound())
            shooter:playSound(item:getShellFallSound())
        end
        
        if HitmanUtils.IsController(zombie) then
            local item = HitmanCompatibility.InstanceItem(task.drop)
            if item then
                zombie:getSquare():AddWorldInventoryItem(item, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
            end
        end
    end

    return true
end