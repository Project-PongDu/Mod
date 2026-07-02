HitmanZombieActions = HitmanZombieActions or {}

local function ShovePlayer (attacker, player)
    local facing = player:isFacingObject(attacker, 0.5)

    player:clearVariable("BumpFallType")
    player:setBumpType("stagger")

    if HitmanUtils.HitmanRand(3) == 1 then
        player:setBumpFall(true)
    else
        player:setBumpFall(false)
    end

    if facing then
        player:setBumpFallType("pushedFront")
    else
        player:setBumpFallType("pushedBehind")
    end
end

local function ShoveZombie (attacker, zombie)
    local facing = zombie:isFacingObject(attacker, 0.5)
    if facing then
        -- zombie:setBumpType("ZombiePushedFront")
        zombie:setStaggerBack(true)
        zombie:setKnockedDown(true)
        zombie:setHitReaction("")
    else
        zombie:setBumpType("ZombiePushedBack")
    end
end

HitmanZombieActions.Push = {}
HitmanZombieActions.Push.onStart = function(hitman, task)

    local anim = "Shove"

    if anim then
        task.anim = anim
        Hitman.UpdateTask(hitman, task)
        hitman:setBumpType(anim)
    else
        return false
    end

    return true
end

HitmanZombieActions.Push.onWorking = function(hitman, task)
    hitman:faceLocation(task.x, task.y)

    local bumpType = hitman:getBumpType()
    if bumpType ~= task.anim then return false end

    if not task.hit and task.time <= 40 then

        task.hit = true

        local asn = hitman:getActionStateName()
        -- print ("SHOVE AS:" .. asn)
        if asn == "getup" or asn == "getup-fromonback" or asn == "getup-fromonfront" or asn == "getup-fromsitting"
                 or asn =="staggerback" or asn == "staggerback-knockeddown" or asn == "falldown" then return false end

        local enemy = HitmanZombie.Cache[task.eid]
        if enemy then 
            local brainHitman = HitmanBrain.Get(hitman)
            local brainEnemy = HitmanBrain.Get(enemy)
            if HitmanUtils.AreEnemies(brainEnemy, brainHitman) then
            -- if not brainEnemy or not brainEnemy.clan or brainHitman.clan ~= brainEnemy.clan or (brainHitman.hostile and not brainEnemy.hostile) then 
                ShoveZombie (hitman, enemy)
            end
        end

        if Hitman.IsHostile(hitman) then
            local playerList = HitmanPlayer.GetPlayers()
            for i=0, playerList:size()-1 do
                local player = playerList:get(i)
                if player then
                    local eid = HitmanUtils.GetCharacterID(player)
                    if player:isAlive() and eid == task.eid then
                        ShovePlayer (hitman, player)
                    end
                end
            end
        end
    end
    return false
end

HitmanZombieActions.Push.onComplete = function(hitman, task)
    return true
end