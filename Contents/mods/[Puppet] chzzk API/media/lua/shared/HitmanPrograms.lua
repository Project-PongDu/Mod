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

-- fixedTime (optional): aim duration in ticks instead of the distance-based one
-- (PONGDU: airborne troopers, features/airborne.lua AIM_TICKS)
-- PONGDU: turnRate (optional, deg/s) makes the Aim task turn gradually (ZAAim) instead of snapping
HitmanPrograms.Weapon.Aim = function(hitman, enemyCharacter, slot, fixedTime, turnRate)
    local tasks = {}

    local walkType = hitman:getVariableString("HitmanWalkType")
    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]
    local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
    local sound = weaponItem:getBringToBearSound()

    -- aim time calc
    local dist = HitmanUtils.DistTo(hitman:getX(), hitman:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local aimTimeMin = Hitman.Settings.GunReflexMin
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
        if fixedTime then time = fixedTime end

        local eid = HitmanUtils.GetCharacterID(enemyCharacter)
        local task = {action="Aim", anim=anim, sound=sound, x=enemyCharacter:getX(), y=enemyCharacter:getY(), time=time, eid=eid, turnRate=turnRate}
        table.insert(tasks, task)
    end
    return tasks
end

-- PONGDU: 자동 사격 속도(발/초)를 플레이어가 같은 총을 쏠 때와 맞춘다.
-- B41 자동 사격은 발마다 Bob_AttackRifle_Small 클립(3200틱 / 4800틱/초 = 0.667초)을
-- 한 번 재생하므로 발당 시간 = 0.667 / (노드 SpeedScale x 2D 블렌드 SpeedScale 0.8).
--   [6]Rotary : Arsenal AnimSets/player/ranged/firearm/AssaultRifle[6]Rotary.xml SpeedScale 15
--               -> 0.8 x 15 / 0.667 = 초당 18발 (1080 RPM)
--   Auto      : Arsenal 이 AssaultRifleDefault.xml 을 SpeedScale 8 로 덮는다 -> 초당 9.6발.
--               Arsenal 이 없으면 바닐라 autoShootSpeed 4 (SwipeStatePlayer) -> 초당 4.8발.
-- 표에 없는 모드는 nil (예전처럼 fire.interval 틱 간격).
local RIFLE_CLIP_S = 3200 / 4800
HitmanPrograms.Weapon.AutoRate = function(weaponItem)
    local fm = weaponItem:getFireMode()
    if fm == "[6]Rotary" then return 0.8 * 15 / RIFLE_CLIP_S end
    if fm == "Auto" then
        local arsenal = getScriptManager():FindItem("Base.XM214") ~= nil
        return 0.8 * (arsenal and 8 or 4) / RIFLE_CLIP_S
    end
    return nil
end

-- fire (optional): {bullets=n, interval=ticks, firstTime=ticks} replaces the
-- default burst rule (auto weapons: 2~7 rounds under 15 tiles, else 1 round).
-- Only honoured for weapons with an Auto fire mode.
-- PONGDU: when Weapon.AutoRate knows the fire mode, the whole plan is ONE Shoot
-- task (rate, left, window) that ZAShoot fires at that rate frame by frame
-- (the one-round-per-task pipeline costs at least 3 frames a round and cannot
-- reach 18 rounds/s). firstTime = ticks before the first round.
-- (PONGDU: airborne troopers, features/airborne.lua FirePlan)
HitmanPrograms.Weapon.Shoot = function(hitman, enemyCharacter, slot, fire)
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

    local hasAuto = false
    local modes = weaponItem:getFireModePossibilities()
    if modes then
        for i=0, modes:size()-1 do
            if modes:get(i) == "Auto" then
                hasAuto = true
                break
            end
        end
    end

    -- rotary guns (Arsenal miniguns: FireMode "[6]Rotary", no FireModePossibilities)
    -- count as automatic, but only for caller-defined fire plans so the default
    -- hitman burst rule stays exactly as it was
    if fire and not hasAuto then
        local fm = weaponItem:getFireMode()
        if fm and (fm:find("Rotary") or fm:find("Auto")) then hasAuto = true end
    end

    local bullets, interval = 1, 6
    if fire and hasAuto then
        bullets = fire.bullets or 1
        interval = fire.interval or interval
        if fire.firstTime then firingtime = fire.firstTime end
        -- never plan more rounds than are loaded (no phantom shots past an empty mag)
        local loaded = weapon.bulletsLeft or 0
        if bullets > loaded then bullets = math.max(1, loaded) end
    elseif hasAuto and dist < 15 then
        bullets = 2 + ZombRand(6)
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

    local rate = fire and hasAuto and HitmanPrograms.Weapon.AutoRate(weaponItem) or nil
    if rate then
        local delay = math.max(0, firingtime)
        local window = math.ceil(bullets / rate * 60) + 6
        table.insert(tasks, {action="Shoot", anim=anim, time=delay + window, window=window, rate=rate, left=bullets,
                             turnRate=fire.turnRate, slot=slot, x=x, y=y, z=z, eid=eid})
        return tasks
    end

    local task = {action="Shoot", anim=anim, time=firingtime, slot=slot, x=x, y=y, z=z, eid=eid}
    table.insert(tasks, task)
    for i=2, bullets do
        local task = {action="Shoot", anim=anim, time=interval, slot=slot, x=x, y=y, z=z, eid=eid}
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
