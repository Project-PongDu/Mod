HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.UnbarricadeMetal = {}
HitmanZombieActions.UnbarricadeMetal.onStart = function(zombie, task)
    zombie:playSound("BlowTorch")
    return true
end

HitmanZombieActions.UnbarricadeMetal.onWorking = function(zombie, task)
    zombie:faceLocation(task.fx, task.fy)
    
    if task.time <= 0 then return true end

    if zombie:getBumpType() ~= task.anim then 
        zombie:setBumpType(task.anim)
    end

    return false
end

HitmanZombieActions.UnbarricadeMetal.onComplete = function(zombie, task)

    --zombie:getEmitter():stopAll()
    zombie:getEmitter():stopAll()
    zombie:playSound("RemoveBarricadeMetal")

    if HitmanUtils.IsController(zombie) then
        local args = {x=task.x, y=task.y, z=task.z, index=task.idx}
        sendClientCommand(getSpecificPlayer(0), 'Commands', 'Unbarricade', args)
    end

    if HitmanUtils.IsController(zombie) then
        local item = HitmanCompatibility.InstanceItem("Base.SheetMetal")
        if item then
            zombie:getSquare():AddWorldInventoryItem(item, ZombRandFloat(0.3, 0.7), ZombRandFloat(0.3, 0.7), 0)
        end
    end

    return true
end