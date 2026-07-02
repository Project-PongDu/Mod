require "HitmanCompatibility"
-- shared subprograms available as subs for other programs

local function predicateAll(item)
    -- item:getType()
	return true
end

local function predicateMelee(item)
    if item:IsWeapon() then
        local weaponType = WeaponType.getWeaponType(item)
        if weaponType ~= WeaponType.firearm and weaponType ~= WeaponType.handgun then
            return true
        end
    end
    return false
end

HitmanPrograms = HitmanPrograms or {}

HitmanPrograms.Weapon = HitmanPrograms.Weapon or {}

HitmanPrograms.Weapon.Switch = function(hitman, itemName)

    local tasks = {}

    -- check what is equipped that needs to be deattached
    local old = hitman:getPrimaryHandItem()
    if old then
        local sound = old:getUnequipSound()
        local task = {action="Unequip", sound=sound, time=100, itemPrimary=old:getFullType()}
        table.insert(tasks, task)
    end

    -- grab new weapon
    local new = HitmanCompatibility.InstanceItem(itemName)
    if new then
        local sound = new:getEquipSound()
        local task = {action="Equip", sound=sound, itemPrimary=itemName}
        table.insert(tasks, task)
    end
    return tasks
end

HitmanPrograms.Weapon.Aim = function(hitman, enemyCharacter, slot)
    local tasks = {}

    local walkType = hitman:getVariableString("HitmanWalkType")
    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]
    local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
    local sound = weaponItem:getBringToBearSound()

    -- aim time calc
    local dist = HitmanUtils.DistTo(hitman:getX(), hitman:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local aimTimeMin = SandboxVars.Hitmans.General_GunReflexMin or 18
    local aimTimeSurp = math.floor(dist * 5)
    if walkType == "WalkAim" then
        aimTimeMin = 1
        -- aimTimeSurp = aimTimeSurp
    end

    if instanceof(enemyCharacter, "IsoZombie") then
        aimTimeSurp = math.floor(aimTimeSurp / 2)
    else
        -- player handicap
        aimTimeSurp = aimTimeSurp + 10
    end

    -- choose anim
    if aimTimeMin + aimTimeSurp > 0 then

        local anim
        local asn = enemyCharacter:getActionStateName()
        local down = enemyCharacter:isProne() or enemyCharacter:isBumpFall() or asn == "onground" or asn == "getup"
        if slot == "primary" then
            if dist < 2.5 and down then
                anim = "AimRifleLow"
            else
                if walkType == "WalkAim" then
                    anim = "AimRifle"
                else
                    anim = "IdleToAimRifle"
                end
            end
        else
            if dist < 2.5 and down then
                anim = "AimPistolLow"
            else
                if walkType == "WalkAim" then
                    anim = "AimPistol"
                else
                    anim = "IdleToAimPistol"
                end
            end
        end

        local aimTimeIndividual = brain.rnd and brain.rnd[2] or 0
        local time = aimTimeMin + aimTimeSurp +aimTimeIndividual
        if time > 60 then time = 60 end

        local task = {action="Aim", anim=anim, sound=sound, x=enemyCharacter:getX(), y=enemyCharacter:getY(), time=time}
        table.insert(tasks, task)
    end
    return tasks
end

HitmanPrograms.Weapon.Shoot = function(hitman, enemyCharacter, slot)
    local tasks = {}

    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]
    local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
    local fireTimeIndividual = brain.rnd and brain.rnd[2] or 0

    local dist = HitmanUtils.DistTo(hitman:getX(), hitman:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local firingtime = weaponItem:getRecoilDelay() + math.floor(dist ^ 1.1) + fireTimeIndividual
    if Hitman.HasExpertise(hitman, Hitman.Expertise.Sharpshooter) then
        firingtime = firingtime / 2
    end

    local bullets = 1
    local modes = weaponItem:getFireModePossibilities()
    if modes then
        for i=0, modes:size()-1 do
            local mode = modes:get(i)
            if dist < 15 and mode == "Auto" then
                bullets = 2 + ZombRand(6)
                break
            end
        end
    end

    local anim
    local asn = enemyCharacter:getActionStateName()
    local down = enemyCharacter:isProne() or enemyCharacter:isBumpFall() or asn == "onground" or asn == "getup"
    if slot == "primary" then
        if dist < 2.5 and down then
            anim = "AimRifleLow"
        else
            anim = "AimRifle"
        end
    else
        if dist < 2.5 and down then
            anim = "AimPistolLow"
        else
            anim = "AimPistol"
        end
    end

    local fd = enemyCharacter:getForwardDirection()
    fd:setLength(2)

    local x, y, z = enemyCharacter:getX() + fd:getX(), enemyCharacter:getY() + fd:getY(), enemyCharacter:getZ()
    local eid = HitmanUtils.GetCharacterID(enemyCharacter)
    local task = {action="Shoot", anim=anim, time=firingtime, slot=slot, x=x, y=y, z=z, eid=eid}
    table.insert(tasks, task)
    for i=2, bullets do
        local task = {action="Shoot", anim=anim, time=6, slot=slot, x=x, y=y, z=z, eid=eid}
        table.insert(tasks, task)
    end

    return tasks
end
HitmanPrograms.Weapon.Rack = function(hitman, slot)
    local tasks = {}

    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]

    local primaryItem = HitmanCompatibility.InstanceItem(weapon.name)
    local reloadType = primaryItem:getWeaponReloadType()
    local magazineType = primaryItem:getMagazineType()

    local rackSound = primaryItem:getRackSound()
    local rackAnim
    if reloadType == "boltaction" then
        rackAnim = "RackRifle"
    elseif reloadType == "boltactionnomag" then
        rackAnim = "RackRifleAim" -- this is different than in Reload
    elseif reloadType == "shotgun" then
        rackAnim = "RackShotgunAim" -- this is different than in Reload
    elseif reloadType == "doublebarrelshotgun" then
        rackAnim = "RackDBShotgun"
    elseif reloadType == "doublebarrelshotgunsawn" then
        rackAnim = "RackDBShotgun"
    elseif reloadType == "handgun" then
        rackAnim = "RackPistol"
    elseif reloadType == "revolver" then
        rackAnim = "RackRevolver"
    end

    if not weapon.racked then
        local task = {action="Rack", slot=slot, anim=rackAnim, sound=rackSound, time=90}
        table.insert(tasks, task)
        return tasks
    end
end

HitmanPrograms.Weapon.Reload = function(hitman, slot)
    local tasks = {}

    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]

    local primaryItem = HitmanCompatibility.InstanceItem(weapon.name)
    local reloadType = primaryItem:getWeaponReloadType()
    local magazineType = primaryItem:getMagazineType()
    local unloadSound = primaryItem:getEjectAmmoSound()
    local loadSound = primaryItem:getInsertAmmoSound()
    local rackSound = primaryItem:getRackSound()

    local clipMode
    local unloadAnim
    local loadAnim
    local rackAnim

    if reloadType == "boltaction" or (reloadType == "boltactionnomag" and magazineType) then -- b41 wrongly indicates hunting rifle as nomag weapon
        clipMode = true
        unloadAnim = "UnloadRifle"
        loadAnim = "LoadRifle"
        rackAnim = "RackRifle"
    elseif reloadType == "boltactionnomag" then
        clipMode = false
        unloadAnim = "UnloadShotgun"
        loadAnim = "LoadShotgun"
        rackAnim = "RackRifle"
    elseif reloadType == "shotgun" then
        clipMode = false
        unloadAnim = "UnloadShotgun"
        loadAnim = "LoadShotgun"
        rackAnim = "RackShotgun"
    elseif reloadType == "doublebarrelshotgun" then
        clipMode = false
        unloadAnim = "UnloadDBShotgun"
        loadAnim = "LoadDBShotgun"
        rackAnim = "RackDBShotgun"
    elseif reloadType == "doublebarrelshotgunsawn" then
        clipMode = false
        unloadAnim = "UnloadDBShotgun"
        loadAnim = "LoadDBShotgun"
        rackAnim = "RackDBShotgun"
    elseif reloadType == "handgun" then
        clipMode = true
        unloadAnim = "UnLoadPistol"
        loadAnim = "LoadPistol"
        rackAnim = "RackPistol"
    elseif reloadType == "revolver" then
        clipMode = false
        unloadAnim = "UnloadRevolver"
        loadAnim = "LoadRevolver"
        rackAnim = "RackRevolver"
    end

    if (weapon.type == "mag" and weapon.bulletsLeft <= 0 and weapon.magCount > 0) or
       (weapon.type == "nomag" and weapon.bulletsLeft < weapon.ammoSize and weapon.ammoCount > 0) then
        
        if clipMode then 
            if weapon.clipIn then
                local task = {action="Unload", slot=slot, drop=magazineType, anim=unloadAnim, sound=unloadSound, time=90}
                table.insert(tasks, task)
                return tasks
            else
                local task = {action="Load", slot=slot, anim=loadAnim, sound=loadSound, time=90}
                table.insert(tasks, task)
                return tasks
            end
        else
            local task = {action="Load", slot=slot, anim=loadAnim, sound=loadSound, time=90}
            table.insert(tasks, task)
            return tasks
        end
    elseif not weapon.racked then
        local task = {action="Rack", slot=slot, anim=rackAnim, sound=rackSound, time=90}
        table.insert(tasks, task)
        return tasks
    end

    return tasks
end

HitmanPrograms.Weapon.Resupply = function(hitman)
    local tasks = {}

    local cell = getCell()
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local isBareHands = Hitman.IsBareHands(hitman)
    local needPrimary = Hitman.NeedResupplySlot(hitman, "primary")
    local needSecondary = Hitman.NeedResupplySlot(hitman, "secondary")
    local objectList = {}
    local bestDist = 100
    local destObject
    for y=-3, 3 do
        for x=-3, 3 do
            local square = cell:getGridSquare(zx + x, zy + y, zz)
            if square then

                -- loot bodies
                if square:getDeadBody() then
                    local objects = square:getStaticMovingObjects()
                    for i=0, objects:size()-1 do
                        local object = objects:get(i)
                        if instanceof (object, "IsoDeadBody") then
                            local container = object:getContainer()
                            if container and not container:isEmpty() then
                                table.insert(objectList, object)
                            end
                        end
                    end
                end
                
                -- loot shelfs
                local objects = square:getObjects()
                for i=0, objects:size()-1 do
                    local object = objects:get(i)
                    local container = object:getContainer()
                    if container and not container:isEmpty() then
                        table.insert(objectList, object)
                    end
                end

                for i=1, #objectList do
                    local object = objectList[i]
                    local container = object:getContainer()
                    local dist = math.abs(x) + math.abs(y)

                    -- find melee
                    if isBareHands then
                        local items = ArrayList.new()
                        container:getAllEvalRecurse(predicateMelee, items)
                        if items:size() > 0 and dist < bestDist then
                            bestDist = dist
                            destObject = object
                        end
                    end

                    -- find primary or secondary
                    if needPrimary or needSecondary then
                        local items = ArrayList.new()
                        container:getAllEvalRecurse(predicateAll, items)
                        for i=0, items:size()-1 do
                            local item = items:get(i)
                            if item:IsWeapon() then
                                local weaponItem = item
                                local weaponType = WeaponType.getWeaponType(weaponItem)

                                if (needPrimary and weaponType == WeaponType.firearm) or
                                    (needSecondary and weaponType == WeaponType.handgun) then
                                    
                                    if HitmanCompatibility.UsesExternalMagazine(weaponItem) then
                                        local magazineType = weaponItem:getMagazineType()
                                        for j=0, items:size()-1 do
                                            local item = items:get(j)
                                            if item:getFullType() == magazineType and item:getCurrentAmmoCount() > 0 then
                                                bestDist = dist
                                                destObject = object
                                            end
                                        end
                                    else
                                        local ammoType = weaponItem:getAmmoType()
                                        for j=0, items:size()-1 do
                                            local item = items:get(j)
                                            if item:getFullType() == ammoType then
                                                bestDist = dist
                                                destObject = object
                                            end
                                        end
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end

    if destObject then
        local square = destObject:getSquare()
        local lx, ly, lz = square:getX(), square:getY(), square:getZ() 
        local ax, ay, az = lx, ly, lz
        
        if not square:isFree(false) then
            local asquare = AdjacentFreeTileFinder.Find(square, hitman)
            if asquare then
                ax, ay, az = asquare:getX(), asquare:getY(), asquare:getZ()
            end
        end
        local dist = HitmanUtils.DistTo(zx, zy, ax, ay)

        if dist > 0.9 then
            local task = HitmanUtils.GetMoveTask(0.01, ax + 0.5, ay + 0.5, az, "Run", dist, false)
            table.insert(tasks, task)
            return tasks
        else
            local task = {action="LootWeapons", anim="LootLow", time=250, x=lx, y=ly, z=lz}
            table.insert(tasks, task)
            return tasks
        end
    end
    return tasks
end
