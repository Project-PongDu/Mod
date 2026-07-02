HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Die = {}
HitmanZombieActions.Die.onStart = function(zombie, task)
    zombie:clearAttachedItems()
    if task.fire == true then
        Hitman.Say(zombie, "BURN", true)
    else
        Hitman.Say(zombie, "DRAGDOWN", true)
    end
    return true
end

HitmanZombieActions.Die.onWorking = function(zombie, task)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
end

HitmanZombieActions.Die.onComplete = function(zombie, task)
    --zombie:Kill(getCell():getFakeZombieForHit(), true)

    zombie:setHealth(0)
    zombie:clearAttachedItems()
    zombie:changeState(ZombieOnGroundState.instance())
    zombie:setAttackedBy(getCell():getFakeZombieForHit())
    zombie:becomeCorpse()

    return true
end