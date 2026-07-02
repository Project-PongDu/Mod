HitmanZombieActions = HitmanZombieActions or {}

local function predicateAll(item)
    -- item:getType()
    return true
end

local function lootContainer(zombie, container, task)
    local isBareHands = Hitman.IsBareHands(zombie)
    local needPrimary = Hitman.NeedResupplySlot(zombie, "primary")
    local needSecondary = Hitman.NeedResupplySlot(zombie, "secondary")
    local weapons = Hitman.GetWeapons(zombie)

    local items = ArrayList.new()
    container:getAllEvalRecurse(predicateAll, items)

    for i=0, items:size()-1 do
        local item = items:get(i)
        if item:IsWeapon() then
            local weaponType = WeaponType.getWeaponType(item)
            if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
                local weaponItem = item

                local slot
                if weaponType == WeaponType.firearm then
                    slot = "primary"
                elseif weaponType == WeaponType.handgun then
                    slot = "secondary"
                end

                local allGood = false
                local toRemove = {}
                table.insert(toRemove, weaponItem)

                local newWeapon = {}
                newWeapon.name = weaponItem:getFullType()
                newWeapon.racked = false

                if HitmanCompatibility.UsesExternalMagazine(weaponItem) then
                    local magazineType = weaponItem:getMagazineType()
                    local magSize = 30

                    local bullets = 0
                    for j=0, items:size()-1 do
                        local item = items:get(j)
                        if item:getFullType() == magazineType and item:getCurrentAmmoCount() > 0 then
                            magSize = item:getMaxAmmo()
                            bullets = bullets + item:getCurrentAmmoCount()
                            allGood = true
                            table.insert(toRemove, item)
                        end
                    end

                    newWeapon.type = "mag"
                    newWeapon.clipIn = false
                    newWeapon.magName = magazineType
                    newWeapon.magSize = magSize
                    newWeapon.magCount = math.floor(bullets / magSize)
                    newWeapon.bulletsLeft = 1
                else
                    local ammoType = weaponItem:getAmmoType()
                    local ammoCount = 0

                    for j=0, items:size()-1 do
                        local item = items:get(j)
                        if item:getFullType() == ammoType then
                            ammoCount = ammoCount + 1
                            allGood = true
                            table.insert(toRemove, item)
                        end
                    end
                    newWeapon.type = "nomag"
                    newWeapon.bulletsLeft = 1
                    newWeapon.ammoSize = weaponItem:getMaxAmmo()
                    newWeapon.ammoCount = ammoCount
                    newWeapon.ammoName = ammoType
                end

                if allGood then
                    weapons[slot] = newWeapon

                    for i=1, #toRemove do
                        container:Remove(toRemove[i])
                        container:removeItemOnServer(toRemove[i])
                    end
                    break
                end

            else
                if isBareHands then
                    weapons.melee = item:getFullType()
                    container:Remove(item)
                    container:removeItemOnServer(item)
                    break
                end
            end
        end
    end

    local brain = HitmanBrain.Get(zombie)
    local syncData = {}
    syncData.id = brain.id
    syncData.weapons = weapons
    Hitman.ForceSyncPart(zombie, syncData)
    Hitman.UpdateItemsToSpawnAtDeath(zombie)

    --[[
    local success = false
    for _, v in pairs(task.toRemove) do
        for i=0, items:size()-1 do
            local item = items:get(i)
            local name = item:getFullType() 
            if v == name then
                container:Remove(item)
                container:removeItemOnServer(item)
                success = true
            end
        end
    end

    if success then
        local weapons = Hitman.GetWeapons(zombie)
        for k, v in pairs(task.toAdd) do
            weapons[k] = v
        end
        Hitman.SetWeapons(zombie, weapons)

        -- requires a sync
        local brain = HitmanBrain.Get(zombie)
        local syncData = {}
        syncData.id = brain.id
        syncData.weapons = weapons
        Hitman.ForceSyncPart(zombie, syncData)
    end
    ]]
    return success
end

HitmanZombieActions.LootWeapons = {}
HitmanZombieActions.LootWeapons.onStart = function(zombie, task)
    zombie:playSound("RummageInInventory")
    return true
end

HitmanZombieActions.LootWeapons.onWorking = function(zombie, task)
    zombie:faceLocation(task.x, task.y)
    if task.time <= 0 then return true end

    if zombie:getBumpType() ~= task.anim then 
        zombie:setBumpType(task.anim)
    end

    local emitter = zombie:getEmitter()
    if not emitter:isPlaying("RummageInInventory") then
        emitter:playSound("RummageInInventory")
    end
    return false
end

HitmanZombieActions.LootWeapons.onComplete = function(zombie, task)
    local emitter = zombie:getEmitter()
    if emitter:isPlaying("RummageInInventory") then
        emitter:stopSoundByName("ChainsawIdle")
    end

    local cell = getCell()
    local square = cell:getGridSquare(task.x, task.y, task.z)
    if square then
        local objects = square:getStaticMovingObjects()
        for i=0, objects:size()-1 do
            local object = objects:get(i)
            if instanceof (object, "IsoDeadBody") then
                local container = object:getContainer()
                if container and not container:isEmpty() then
                    local success = lootContainer(zombie, container, task)
                    if success then return true end
                end
            end
        end

        local objects = square:getObjects()
        for i=0, objects:size()-1 do
            local object = objects:get(i)
            local container = object:getContainer()
            if container and not container:isEmpty() then
                local success = lootContainer(zombie, container, task)
                if success then return true end
            end
        end
    end
    return true
end

