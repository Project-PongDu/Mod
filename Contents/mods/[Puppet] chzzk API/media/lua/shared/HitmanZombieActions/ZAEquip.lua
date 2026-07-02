HitmanZombieActions = HitmanZombieActions or {}

HitmanZombieActions.Equip = {}
HitmanZombieActions.Equip.onStart = function(zombie, task)
    task.tick = 1

    --[[
    if task.itemSecondary then
        if hands == "barehand" or hands == "onehanded" or hands == "handgun" or hands == "throwing" then
            local oldSecondaryPrimary = zombie:getVariableString("HitmanSecondary")
            if oldSecondaryPrimary ~= task.itemSecondary then
                local secondaryItem = HitmanCompatibility.InstanceItem(task.itemSecondary)
                zombie:setSecondaryHandItem(secondaryItem)
                zombie:setVariable("HitmanSecondary", task.itemSecondary)

                local ls = secondaryItem:getLightStrength()
                if ls > 0 then
                    secondaryItem:setActivated(true)
                    zombie:setVariable("HitmanTorch", true)
                else
                    zombie:setVariable("HitmanTorch", false)
                end
            end
        else
            print ("ERROR: Cannot equip secondary item because primary item occupies both hands")
        end
    end]]

    local primaryItem = HitmanCompatibility.InstanceItem(task.itemPrimary)
    local attachmentType = primaryItem:getAttachmentType()
    for _, def in pairs(ISHotbarAttachDefinition) do
        if def.attachments then
            for k, v in pairs(def.attachments) do
                if k == attachmentType then
                    if def.type == "HolsterRight" then 
                        task.anim1 = "AttachHolsterRight"
                        task.anim2 = "AttachHolsterRightOut"
                        task.slot = v
                        return true
                    elseif def.type == "Back" then
                        task.anim1 = "AttachBack"
                        task.anim2 = "AttachBackOut"
                        task.slot = v
                        return true
                    elseif def.type == "SmallBeltLeft" then
                        task.anim1 = "AttachHolsterLeft"
                        task.anim2 = "AttachHolsterLeftOut"
                        task.slot = v
                        return true
                    end
                end
            end
        end
    end

    task.anim1 = "AttachHolsterLeft"
    task.anim2 = "AttachHolsterLeftOut"
    return true
end

HitmanZombieActions.Equip.onWorking = function(zombie, task)
    if task.tick == 1 then
        zombie:setBumpType(task.anim1)
    end

    if task.tick == 15 then
        if task.slot then
            zombie:setAttachedItem(task.slot, nil)
        end

        zombie:setBumpType(task.anim2)

        if task.itemPrimary then
            Hitman.SetHands(zombie, task.itemPrimary)
        end
    end

    if task.tick > 20 and zombie:getBumpType() ~= task.anim1 and zombie:getBumpType() ~= task.anim2 then 
        return true
    end

    task.tick = task.tick + 1

    return false
end

HitmanZombieActions.Equip.onComplete = function(zombie, task)
    return true
end

