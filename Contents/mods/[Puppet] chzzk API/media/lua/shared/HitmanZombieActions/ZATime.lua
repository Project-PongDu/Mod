HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Time = {}
HitmanZombieActions.Time.onStart = function(zombie, task)
    return true
end

HitmanZombieActions.Time.onWorking = function(zombie, task)
    -- zombie:addLineChatElement(task.action .. task.time, 0.5, 0.5, 0.5)
    if zombie:getBumpType() ~= task.anim then return true end
    return false
--[[
    if not zombie:getVariableString("BumpAnimFinished") then
        return false
    else
        return true
    end
    ]]
end

HitmanZombieActions.Time.onComplete = function(zombie, task)
    return true
end