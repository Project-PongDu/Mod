HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Unbarricade = {}
HitmanZombieActions.Unbarricade.onStart = function(zombie, task)
    zombie:playSound("BeginRemoveBarricadePlank")
    return true
end

HitmanZombieActions.Unbarricade.onWorking = function(zombie, task)
    zombie:faceLocationF(task.fx, task.fy)

    if task.time <= 0 then return true end

    if zombie:getBumpType() ~= task.anim then 
        zombie:setBumpType(task.anim)
    end
end

HitmanZombieActions.Unbarricade.onComplete = function(zombie, task)

    --zombie:getEmitter():stopAll()
    zombie:getEmitter():stopAll()
    zombie:playSound("RemoveBarricadePlank")

    if HitmanUtils.IsController(zombie) then
        local args = {x=task.x, y=task.y, z=task.z, index=task.idx}
        sendClientCommand(getSpecificPlayer(0), 't3_Commands', 'Unbarricade', args)
    end

    if HitmanUtils.IsController(zombie) then
        local item = HitmanCompatibility.InstanceItem("Base.Plank")
        if item then
            zombie:getSquare():AddWorldInventoryItem(item, ZombRandFloat(0.3, 0.7), ZombRandFloat(0.3, 0.7), 0)
        end
    end

    return true
end