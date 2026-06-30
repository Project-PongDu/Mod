Hitman = Hitman or {}

Hitman.SoundTab = Hitman.SoundTab or {}
Hitman.SoundTab.SPOTTED =           {prefix = "ZSSpotted_", chance = 90, randMax = 6, length = 10}
Hitman.SoundTab.HIT =               {prefix = "ZSHit_", chance = 100, randMax = 14, length = 0.1}
Hitman.SoundTab.BREACH =            {prefix = "ZSBreach_", chance = 80, randMax = 6, length = 10}
Hitman.SoundTab.RELOADING =         {prefix = "ZSReloading_", chance = 80, randMax = 6, length = 4}
Hitman.SoundTab.CAR =               {prefix = "ZSCar_", chance = 90, randMax = 6, length = 4}
Hitman.SoundTab.DEATH =             {prefix = "ZSDeath_", chance = 70, randMax = 8, length = 6}
Hitman.SoundTab.DEAD =              {prefix = "ZSDead_", chance = 100, randMax = 6, length = 3}
Hitman.SoundTab.BURN =              {prefix = "ZSBurn_", chance = 100, randMax = 3, length = 8}
Hitman.SoundTab.DRAGDOWN =          {prefix = "ZSDragdown_", chance = 100, randMax = 3, length = 8}
Hitman.SoundTab.INSIDE =            {prefix = "ZSInside_", chance = 40, randMax = 3, length = 25}
Hitman.SoundTab.OUTSIDE =           {prefix = "ZSOutside_", chance = 40, randMax = 3, length = 25}
Hitman.SoundTab.UPSTAIRS =          {prefix = "ZSUpstairs_", chance = 40, randMax = 1, length = 25}
Hitman.SoundTab.ROOM_KITCHEN =      {prefix = "ZSRoom_Kitchen_", chance = 40, randMax = 1, length = 25}
Hitman.SoundTab.ROOM_BATHROOM =     {prefix = "ZSRoom_Bathroom_", chance = 40, randMax = 1, length = 25}
Hitman.SoundTab.DEFENDER_SPOTTED =  {prefix = "ZSDefender_Spot_", chance = 80, randMax = 4, length = 8}
Hitman.SoundTab.THIEF_SPOTTED =     {prefix = "ZSThief_Spot_", chance = 80, randMax = 6, length = 12}

Hitman.SoundStopList = Hitman.SoundStopList or {}
table.insert(Hitman.SoundStopList, "BeginRemoveBarricadePlank")
table.insert(Hitman.SoundStopList, "BlowTorch")
table.insert(Hitman.SoundStopList, "GeneratorAddFuel")
table.insert(Hitman.SoundStopList, "GeneratorRepair")
table.insert(Hitman.SoundStopList, "GetWaterFromTapMetalBig")

Hitman.VisualDamage = {}

Hitman.VisualDamage.Melee = {"ZedDmg_BACK_Slash", "ZedDmg_BellySlashLeft", "ZedDmg_BellySlashRight", "ZedDmg_BELLY_Slash", 
                             "ZedDmg_ChestSlashLeft", "ZedDmg_CHEST_Slash", "ZedDmg_FaceSkullLeft", "ZedDmg_FaceSkullRight", 
                             "ZedDmg_HeadSlashCentre01", "ZedDmg_HeadSlashCentre02", "ZedDmg_HeadSlashCentre03", "ZedDmg_HeadSlashLeft01", 
                             "ZedDmg_HeadSlashLeft02", "ZedDmg_HeadSlashLeft03", "ZedDmg_HeadSlashLeftBack01", "ZedDmg_HeadSlashLeftBack02", 
                             "ZedDmg_HeadSlashRight01", "ZedDmg_HeadSlashRight02", "ZedDmg_HeadSlashRight03", "ZedDmg_HeadSlashRightBack01", 
                             "ZedDmg_HeadSlashRightBack02", "ZedDmg_HEAD_Skin", "ZedDmg_HEAD_Slash", "ZedDmg_Mouth01", 
                             "ZedDmg_Mouth02", "ZedDmg_MouthLeft", "ZedDmg_MouthRight", "ZedDmg_NoChin", 
                             "ZedDmg_NoEarLeft", "ZedDmg_NoEarRight", "ZedDmg_NoNose", "ZedDmg_ShoulderSlashLeft", 
                             "ZedDmg_ShoulderSlashRight", "ZedDmg_SkullCap", "ZedDmg_SkullUpLeft", "ZedDmg_SkullUpRight"}

Hitman.VisualDamage.Gun = {"ZedDmg_BulletBelly01", "ZedDmg_BulletBelly02", "ZedDmg_BulletBelly03", "ZedDmg_BulletChest01", 
                           "ZedDmg_BulletChest02", "ZedDmg_BulletChest03", "ZedDmg_BulletChest04", "ZedDmg_BulletFace01",
                           "ZedDmg_BulletFace02", "ZedDmg_BulletForehead01", "ZedDmg_BulletForehead02", "ZedDmg_BulletForehead03",
                           "ZedDmg_BulletLeftTemple", "ZedDmg_BulletRightTemple", "ZedDmg_BELLY_Bullet", "ZedDmg_BELLY_Shotgun",
                           "ZedDmg_CHEST_Bullet", "ZedDmg_CHEST_Shotgun", "ZedDmg_HEAD_Bullet", "ZedDmg_HEAD_Shotgun",
                           "ZedDmg_ShotgunBelly", "ZedDmg_ShotgunChestCentre", "ZedDmg_ShotgunChestLeft", "ZedDmg_ShotgunChestRight",
                           "ZedDmg_ShotgunFaceFull", "ZedDmg_ShotgunFaceLeft", "ZedDmg_ShotgunFaceRight", "ZedDmg_ShotgunLeft",
                           "ZedDmg_ShotgunRight"}

Hitman.Expertise = {}
Hitman.Expertise.Assasin = 1
Hitman.Expertise.Breaker = 2
Hitman.Expertise.Electrician = 3
Hitman.Expertise.Cook = 4
Hitman.Expertise.Goblin = 5
Hitman.Expertise.Infected = 6
Hitman.Expertise.Mechanic = 7
Hitman.Expertise.Medic = 8
Hitman.Expertise.Recon = 9
Hitman.Expertise.Thief = 10
Hitman.Expertise.Repairman = 11
Hitman.Expertise.Tracker = 12
Hitman.Expertise.Trapper = 13
Hitman.Expertise.Traitor = 14
Hitman.Expertise.Sacrificer = 15
Hitman.Expertise.Zombiemaster = 16
Hitman.Expertise.Berserker = 17

Hitman.Engine = true

local function predicateAll(item)
    return true
end


function Hitman.ForceSyncPart(zombie, syncData)
    sendClientCommand(getSpecificPlayer(0), 'Commands', 'HitmanUpdatePart', syncData)
end

function Hitman.AddTask(zombie, task)
    local brain = HitmanBrain.Get(zombie)
    if brain then

        if #brain.tasks > 9 then
            print ("[WARN] Task queue too big, flushing!")
            brain.tasks = {}
        end

        table.insert(brain.tasks, task)
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.AddTaskFirst(zombie, task)
    local brain = HitmanBrain.Get(zombie)
    if brain then

        if #brain.tasks > 9 then
            print ("[WARN] Task queue too big, flushing!")
            brain.tasks = {}
        end

        table.insert(brain.tasks, 1, task)
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.GetTask(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        if #brain.tasks > 0 then
            return brain.tasks[1]
        end
    end
    return nil
end

function Hitman.HasTask(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.HasTask(brain)
    end
end

function Hitman.HasTaskType(zombie, taskType)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.HasTaskType(brain, taskType)
    end
end

function Hitman.HasMoveTask(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.HasMoveTask(brain)
    end
end

function Hitman.HasActionTask(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.HasActionTask(brain)
    end
end

function Hitman.UpdateTask(zombie, task)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        table.remove(brain.tasks, 1)
        table.insert(brain.tasks, 1, task)
        --HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.RemoveTask(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        table.remove(brain.tasks, 1)
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.ClearTasks(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.lock == true then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        -- HitmanBrain.Update(zombie, brain)
    end

    local emitter = zombie:getEmitter()
    local stopList = Hitman.SoundStopList

    for _, stopSound in pairs(stopList) do
        if emitter:isPlaying(stopSound) then
            emitter:stopSoundByName(stopSound)
        end
    end
end

function Hitman.ClearMoveTasks(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.action ~= "Move" and task.action ~= "GoTo" then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.ClearOtherTasks(zombie, exception)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        local newtasks = {}
        for _, task in pairs(brain.tasks) do
            if task.lock == true or task.action == exception then
                table.insert(newtasks, task)
            end
        end

        brain.tasks = newtasks
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.UpdateEndurance(zombie, delta)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        if not brain.endurance then brain.endurance = 1.00 end
        brain.endurance = brain.endurance + delta
        if brain.endurance < 0 then brain.endurance = 0 end
        if brain.endurance > 1 then brain.endurance = 1 end
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.GetInfection(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        if not brain.infection then brain.infection = 0 end
        return brain.infection
    end
    return nil
end

function Hitman.UpdateInfection(zombie, delta)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        if not brain.infection then brain.infection = 0 end
        brain.infection = brain.infection + delta
        -- if brain.infection > 90 then print (brain.infection) end
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.ForceStationary(zombie, stationary)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.stationary = stationary
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsForceStationary(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.stationary
    end
end

function Hitman.SetNearFire(zombie, nearFire)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.nearFire = nearFire
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsNearFire(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.nearFire
    end
end

function Hitman.SetSleeping(zombie, sleeping)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.sleeping = sleeping
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsSleeping(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.sleeping
    end
end

function Hitman.SetAim(zombie, aim)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.aim = aim
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsAim(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.aim
    end
end

function Hitman.SetMoving(zombie, moving)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.moving = moving
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsMoving(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.moving
    end
end


function Hitman.HasExpertise(zombie, exp)
    local brain = HitmanBrain.Get(zombie)
    if brain and brain.exp then
        for _, v in pairs(brain.exp) do
            if v == exp then return true end
        end
    end
    return false
end

-- Functions that require brain sync below

-- Hitman ownership
function Hitman.GetMaster(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.master
    end
end

function Hitman.SetMaster(zombie, master)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.master = master
        -- HitmanBrain.Update(zombie, brain)
        -- sendClientCommand(getPlayer(), 'Commands', 'HitmanUpdate', brain)
    end
end

-- Hitman Programs
function Hitman.GetProgram(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.program
    end
end

function Hitman.SetProgram(zombie, program, programParams)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.program = {}
        brain.program.name = program
        brain.program.stage = "Prepare"

        -- HitmanBrain.Update(zombie, brain)
    end
    -- sendClientCommand(getPlayer(), 'Commands', 'HitmanUpdate', brain)
end

function Hitman.SetProgramStage(zombie, stage)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.program.stage = stage
        -- HitmanBrain.Update(zombie, brain)
    end
    -- sendClientCommand(getPlayer(), 'Commands', 'HitmanUpdate', brain)
end

-- Hitman hostility
function Hitman.SetHostile(zombie, hostile)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.hostile = hostile
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.SetHostileP(zombie, hostileP)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.hostileP = hostileP
        -- HitmanBrain.Update(zombie, brain)
    end
end

function Hitman.IsHostile(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.hostile or brain.hostileP
    end
end

-- Hitman weapons
function Hitman.GetWeapons(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return brain.weapons
    end
end

function Hitman.GetBestWeapon(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        local weapons = brain.weapons
        if weapons.primary.bulletsLeft > 0 or 
           (weapons.primary.type == "mag" and weapons.primary.magCount > 0) or 
           (weapons.primary.type == "nomag" and weapons.primary.ammoCount > 0) then

            return weapons.primary.name
        elseif weapons.secondary.bulletsLeft > 0 or 
           (weapons.secondary.type == "mag" and weapons.secondary.magCount > 0) or 
           (weapons.secondary.type == "nomag" and weapons.secondary.ammoCount > 0) then

            return weapons.secondary.name
        else
            return weapons.melee
        end
    end
end

function Hitman.IsOutOfAmmo(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.IsOutOfAmmo(brain)
    end
end

function Hitman.IsBareHands(zombie)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.IsBareHands(brain)
    end
end

function Hitman.SetHands(zombie, itemType)
    local brain = HitmanBrain.Get(zombie)
    local primaryItem = HitmanCompatibility.InstanceItem(itemType)
    primaryItem = HitmanUtils.ModifyWeapon(primaryItem, brain)
    zombie:setPrimaryHandItem(primaryItem)
    zombie:setVariable("HitmanPrimary", itemType)

    local hands
    if primaryItem:IsWeapon() then
        local primaryItemType = WeaponType.getWeaponType(primaryItem)

        if primaryItemType == WeaponType.barehand then
            hands = "barehand"
        elseif primaryItemType == WeaponType.firearm then
            hands = "rifle"
        elseif primaryItemType == WeaponType.handgun then
            hands = "handgun"
        elseif primaryItemType == WeaponType.heavy then
            hands = "twohanded"
        elseif primaryItemType == WeaponType.onehanded then
            hands = "onehanded"
        elseif primaryItemType == WeaponType.spear then
            hands = "spear"
        elseif primaryItemType == WeaponType.twohanded then
            hands = "twohanded"
        elseif primaryItemType == WeaponType.throwing then
            hands = "throwing"
        elseif primaryItemType == WeaponType.chainsaw then
            hands = "chainsaw"
        else
            hands = "onehanded"
        end
    else
        hands = "item"
    end

    zombie:setVariable("HitmanPrimaryType", hands)
end

function Hitman.NeedResupplySlot(zombie, slot)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        return HitmanBrain.NeedResupplySlot(brain, slot)
    end
end

function Hitman.SetWeapons(zombie, weapons)
    local brain = HitmanBrain.Get(zombie)
    if brain then
        brain.weapons = weapons
        -- HitmanBrain.Update(zombie, brain)
        Hitman.UpdateItemsToSpawnAtDeath(zombie)
        -- sendClientCommand(getPlayer(), 'Commands', 'HitmanUpdate', brain)
    end
end

-- This translates weapons, loot, inventory to actual items to be
-- spawned at hitman death
function Hitman.UpdateItemsToSpawnAtDeath(zombie)
    
    local brain = HitmanBrain.Get(zombie)
    local weapons = brain.weapons
    --zombie:setPrimaryHandItem(nil)
    --zombie:resetEquippedHandsModels()
    zombie:clearItemsToSpawnAtDeath()

    -- keyring / id
    if brain.fullname then
        HitmanCompatibility.AddId(zombie, brain.fullname)
    end

    -- update inventory
    local inventory = zombie:getInventory()
    local items = ArrayList.new()
    inventory:getAllEvalRecurse(predicateAll, items)
    for i=0, items:size()-1 do
        local item = items:get(i)
        item:getModData().preserve = true
        zombie:addItemToSpawnAtDeath(item)
    end

    -- update weapons that the hitman has
    if weapons.melee and weapons.melee ~= "Base.BareHands" then 
        local item = HitmanCompatibility.InstanceItem(weapons.melee)
        if item then
            item:getModData().preserve = true
            item = HitmanCompatibility.SetRandomCondition(item, 0.8)
            zombie:addItemToSpawnAtDeath(item)
        end
    end

    if weapons.primary then
        if weapons.primary.name then

            local gun = HitmanCompatibility.InstanceItem(weapons.primary.name)
            if gun then
                gun = HitmanUtils.ModifyWeapon(gun, brain)
                gun:getModData().preserve = true
                gun = HitmanCompatibility.SetRandomCondition(gun, 0.8)
                zombie:addItemToSpawnAtDeath(gun)
            end

            if weapons.primary.type == "mag" and weapons.primary.magName then
                local mag = HitmanCompatibility.InstanceItem(weapons.primary.magName)
                if mag then
                    mag:getModData().preserve = true
                    mag:setCurrentAmmoCount(weapons.primary.bulletsLeft)
                    mag:setMaxAmmo(weapons.primary.magSize)
                    zombie:addItemToSpawnAtDeath(mag)
                end

                for i=1, weapons.primary.magCount do
                    local mag = HitmanCompatibility.InstanceItem(weapons.primary.magName)
                    if mag then
                        mag:getModData().preserve = true
                        mag:setCurrentAmmoCount(weapons.primary.magSize)
                        mag:setMaxAmmo(weapons.primary.magSize)
                        zombie:addItemToSpawnAtDeath(mag)
                    end
                end
            elseif weapons.primary.type == "nomag" and weapons.primary.ammoName then
                for i=1, weapons.primary.ammoCount do
                    local ammo = HitmanCompatibility.InstanceItem(weapons.primary.ammoName)
                    if ammo then
                        ammo:getModData().preserve = true
                        zombie:addItemToSpawnAtDeath(ammo)
                    end
                end
            end
        end
    end

    if weapons.secondary then
        if weapons.secondary.name then

            local gun = HitmanCompatibility.InstanceItem(weapons.secondary.name)
            if gun then
                gun = HitmanUtils.ModifyWeapon(gun, brain)
                gun:getModData().preserve = true
                gun = HitmanCompatibility.SetRandomCondition(gun, 0.8)
                zombie:addItemToSpawnAtDeath(gun)
            end

            if weapons.secondary.type == "mag" and weapons.secondary.magName then
                local mag = HitmanCompatibility.InstanceItem(weapons.secondary.magName)
                if mag then
                    mag:getModData().preserve = true
                    mag:setCurrentAmmoCount(weapons.secondary.bulletsLeft)
                    mag:setMaxAmmo(weapons.secondary.magSize)
                    zombie:addItemToSpawnAtDeath(mag)
                end

                for i=1, weapons.secondary.magCount do
                    local mag = HitmanCompatibility.InstanceItem(weapons.secondary.magName)
                    if mag then
                        mag:getModData().preserve = true
                        mag:setCurrentAmmoCount(weapons.secondary.magSize)
                        mag:setMaxAmmo(weapons.secondary.magSize)
                        zombie:addItemToSpawnAtDeath(mag)
                    end
                end
            elseif weapons.secondary.type == "nomag" and weapons.secondary.ammoName then
                for i=1, weapons.secondary.ammoCount do
                    local ammo = HitmanCompatibility.InstanceItem(weapons.secondary.ammoName)
                    if ammo then
                        ammo:getModData().preserve = true
                        zombie:addItemToSpawnAtDeath(ammo)
                    end
                end
            end
        end
    end

    -- update loot items that the hitman has
    --[[
    local loot = brain.loot
    if loot then
        for _, itemType in pairs(brain.loot) do
            local item = HitmanCompatibility.InstanceItem(itemType)
            if item then
                if item:IsDrainable() then
                    item:setUses(1+ZombRand(2))
                elseif item:IsWeapon() then
                    item:setCondition(1+ZombRand(3))
                end
                zombie:addItemToSpawnAtDeath(item)
            end
        end
    end]]

    -- clothing
    --[[
    if brain.clothing then
        for _, itemType in pairs(brain.clothing) do
            local item = HitmanCompatibility.InstanceItem(itemType)
            item:getModData().preserve = true
            zombie:addItemToSpawnAtDeath(item)
        end
    end]]

    local bag
    if brain.bag and brain.bag.name then
        bag = HitmanCompatibility.InstanceItem(brain.bag.name)
        if bag then
            bag:getModData().preserve = true
            zombie:addItemToSpawnAtDeath(bag)
        end
    end

    local loot = {}
    local lootBag = {}
    -- update loot

    -- essential loot
    table.insert(loot, {itemType="Base.WaterBottle", chance=100, n=1})
    table.insert(loot, {itemType="Base.HandTorch", chance=40, n=1})
    table.insert(loot, {itemType="Base.Soap2", chance=40, n=1})

    table.insert(lootBag, {itemType="Base.TinnedBeans", chance=5, n=4})
    table.insert(lootBag, {itemType="Base.CannedCarrots2", chance=6, n=4})
    table.insert(lootBag, {itemType="Base.CannedChili", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedCorn", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedCornedBeef", chance=4, n=4})
    table.insert(lootBag, {itemType="Base.CannedFruitCocktail", chance=5, n=4})
    table.insert(lootBag, {itemType="Base.CannedMushroomSoup", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedPeaches", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedPeas", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedPineapple", chance=2, n=4})
    table.insert(lootBag, {itemType="Base.CannedPotato2", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedSardines", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.TinnedSoup", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedBolognese", chance=7, n=4})
    table.insert(lootBag, {itemType="Base.CannedTomato2", chance=5, n=4})
    table.insert(lootBag, {itemType="Base.TinOpener", chance=85, n=1})
    table.insert(lootBag, {itemType="Base.WaterBottle", chance=20, n=2})
    table.insert(lootBag, {itemType="Base.Book", chance=10, n=2})
    
    -- experise loot
    if Hitman.HasExpertise(zombie, Hitman.Expertise.Assasin) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Breaker) then
        table.insert (loot, {itemType="Base.Crowbar", chance=100, n=1})
        table.insert (loot, {itemType="Base.BlowTorch", chance=100, n=1})
        table.insert (loot, {itemType="Base.WeldingMask", chance=100, n=1})
        table.insert (lootBag, {itemType="Base.Sledgehammer", chance=1, n=1})
        table.insert (lootBag, {itemType="Base.PropaneTank", chance=4, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Electrician) then
        table.insert (loot, {itemType="Base.Screwdriver", chance=100, n=1})
        table.insert (lootBag, {itemType="Base.LightBulbBox", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.ElectricWire", chance=20, n=3})
        table.insert (lootBag, {itemType="Base.ElectronicsScrap", chance=30, n=5})
        table.insert (lootBag, {itemType="Base.BookElectrician1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookElectrician2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookElectrician3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookElectrician4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookElectrician5", chance=2, n=1})
        table.insert (lootBag, {itemType="Base.ElectronicsMag1", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.ElectronicsMag2", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.ElectronicsMag3", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.ElectronicsMag4", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.ElectronicsMag5", chance=3, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Cook) then
        table.insert (lootBag, {itemType="Base.Pot", chance=30, n=1})
        table.insert (lootBag, {itemType="Base.Pan", chance=30, n=1})
        table.insert (lootBag, {itemType="Base.Salt", chance=30, n=1})
        table.insert (lootBag, {itemType="Base.Pepper", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.Spoon", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.Spatula", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.Bowl", chance=20, n=2})
        table.insert (lootBag, {itemType="Base.KitchenKnife", chance=50, n=1})
        table.insert (lootBag, {itemType="Base.Charcoal", chance=20, n=2})
        table.insert (lootBag, {itemType="Base.Matches", chance=50, n=1})
        table.insert (lootBag, {itemType="camping.CampfireKit", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookCooking1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookCooking2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookCooking3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookCooking4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookCooking5", chance=2, n=1})
        table.insert (lootBag, {itemType="Base.CookingMag1", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.CookingMag2", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.CookingMag3", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.CookingMag4", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.CookingMag5", chance=3, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Goblin) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Infected) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Mechanic) then
        table.insert (loot, {itemType="Base.Wrench", chance=100, n=1})
        table.insert (loot, {itemType="Base.LugWrench", chance=100, n=1})
        table.insert (loot, {itemType="Base.Jack", chance=100, n=1})
        table.insert (loot, {itemType="Base.PetrolCan", chance=100, n=1})
        table.insert (lootBag, {itemType="Base.ScrewsBox", chance=7, n=1})
        table.insert (lootBag, {itemType="Base.BookMechanic1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookMechanic2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookMechanic3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookMechanic4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookMechanic5", chance=2, n=1})
        table.insert (lootBag, {itemType="Base.MechanicMag1", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.MechanicMag2", chance=3, n=1})
        table.insert (lootBag, {itemType="Base.MechanicMag3", chance=3, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Medic) then
        table.insert (loot, {itemType="Base.Bandage", chance=100, n=2})
        table.insert (lootBag, {itemType="Base.SutureNeedle", chance=50, n=1})
        table.insert (lootBag, {itemType="Base.AlcoholBandage", chance=12, n=10})
        table.insert (lootBag, {itemType="Base.BandageBox", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.SutureNeedle", chance=50, n=3})
        table.insert (lootBag, {itemType="Base.SutureNeedleBox", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.SutureNeedleHolder", chance=50, n=1})
        table.insert (lootBag, {itemType="Base.Tweezers", chance=50, n=1})
        table.insert (lootBag, {itemType="Base.Stethoscope", chance=30, n=1})
        table.insert (lootBag, {itemType="Base.Antibiotics", chance=10, n=3})
        table.insert (lootBag, {itemType="Base.Disinfectant", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.Pills", chance=80, n=2})
        table.insert (lootBag, {itemType="Base.AlcoholWipes", chance=50, n=2})
        table.insert (lootBag, {itemType="Base.BookFirstAid1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookFirstAid2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookFirstAid3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookFirstAid4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookFirstAid5", chance=2, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Recon) then
        table.insert (lootBag, {itemType="Base.BookForaging1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookForaging2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookForaging3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookForaging4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookForaging5", chance=2, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap1", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap2", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap3", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap4", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap5", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap6", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap7", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap8", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.LouisvilleMap9", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.MarchRidgeMap", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.MuldraughMap", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.RiversideMap", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.RosewoodMap", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.WestpointMap", chance=20, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Thief) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Repairman) then
        table.insert (loot, {itemType="Base.Hammer", chance=100, n=1})
        table.insert (lootBag, {itemType="Base.Woodglue", chance=20, n=3})
        table.insert (lootBag, {itemType="Base.DuctTape", chance=20, n=3})
        table.insert (lootBag, {itemType="Base.Epoxy", chance=20, n=1})
        table.insert (lootBag, {itemType="Base.BatteryBox", chance=10, n=3})
        table.insert (lootBag, {itemType="Base.BookMaintenance1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookMaintenance2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookMaintenance3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookMaintenance4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookMaintenance5", chance=2, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Tracker) then
        local city = HitmanUtils.GetCity(zombie)
        if city then
            local maps = HitmanUtils.GetCityMap(city)
            for i=1, #maps do
                table.insert (lootBag, {itemType=maps[i], chance=100, n=1})
            end
        end
        table.insert (loot, {itemType="Base.Pencil", chance=100, n=1})
        table.insert (loot, {itemType="Base.Eraser", chance=20, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Trapper) then
        table.insert (lootBag, {itemType="Base.TrapCage", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.TrapSnare", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookTrapping1", chance=10, n=1})
        table.insert (lootBag, {itemType="Base.BookTrapping2", chance=8, n=1})
        table.insert (lootBag, {itemType="Base.BookTrapping3", chance=6, n=1})
        table.insert (lootBag, {itemType="Base.BookTrapping4", chance=4, n=1})
        table.insert (lootBag, {itemType="Base.BookTrapping5", chance=2, n=1})
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Traitor) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Sacrificer) then
    end

    if Hitman.HasExpertise(zombie, Hitman.Expertise.Zombiemaster) then
    end

    -- personal loot
    -- idea: add personal story letters
    local personality = brain.personality or {}
    if personality.alcoholic then
        table.insert(loot, {itemType="Base.Vodka", chance=50, n=5})
        table.insert(loot, {itemType="Base.Whiskey", chance=40, n=4})
        table.insert(loot, {itemType="Base.Gin", chance=30, n=3})
    end

    if personality.smoker then
        table.insert(loot, {itemType="Base.CigaretteSingle", chance=50, n=20})
        table.insert(loot, {itemType="Base.Lighter", chance=100, n=1})
    end

    if personality.compulsiveCleaner then
        table.insert(lootBag, {itemType="Base.Soap2", chance=50, n=20})
        table.insert(lootBag, {itemType="Base.ToiletPaper", chance=50, n=20})
    end

    if personality.comicsCollector then
        table.insert(lootBag, {itemType="Base.ComicBook", chance=50, n=30})
    end

    if personality.gameCollector then
        table.insert(lootBag, {itemType="Base.VideoGame", chance=50, n=20})
    end

    if personality.hottieCollector then
        table.insert(lootBag, {itemType="Base.HottieZ", chance=50, n=30})
    end

    if personality.toyCollector then
        table.insert(lootBag, {itemType="Base.Doll", chance=50, n=20})
    end

    if personality.underwearCollector then
        local i = 1 + ZombRand(5)
        if i == 1 then
            table.insert(lootBag, {itemType="Base.Underpants_White", chance=50, n=30})
        elseif i == 2 then
            table.insert(lootBag, {itemType="Base.Underpants_Black", chance=50, n=30})
        elseif i == 3 then
            table.insert(lootBag, {itemType="Base.FrillyUnderpants_Black", chance=50, n=30})
        elseif i == 4 then
            table.insert(lootBag, {itemType="Base.FrillyUnderpants_Pink", chance=50, n=30})
        elseif i == 5 then
            table.insert(lootBag, {itemType="Base.FrillyUnderpants_Red", chance=50, n=30})
        end
    end

    if personality.videoCollector then
    end

    if personality.fromPoland then
        table.insert(loot, {itemType="Base.Perogies", chance=50, n=30})
    end

    -- save loot
    for _, tab in pairs(loot) do
        for i=1, tab.n do
            local r = ZombRand(100)
            if tab.chance > r then
                local item = HitmanCompatibility.InstanceItem(HitmanCompatibility.GetLegacyItem(tab.itemType))
                if item then
                    item:getModData().preserve = true
                    zombie:addItemToSpawnAtDeath(item)
                end
            end
        end
    end

    -- save loot in bag
    if bag then
        for _, tab in pairs(lootBag) do
            for i=1, tab.n do
                local r = ZombRand(100)
                if tab.chance > r then
                    local item = HitmanCompatibility.InstanceItem(HitmanCompatibility.GetLegacyItem(tab.itemType))
                    if item then
                        bag:getInventory():AddItem(item)
                    else
                        print ("[WARN] Unknown item: " .. tab.itemType)
                    end
                end
            end
        end
    
        zombie:addItemToSpawnAtDeath(bag)
    end
    
end

function Hitman.SurpressZombieSounds(hitman)
    HitmanCompatibility.SurpressZombieSounds(hitman)
end

function Hitman.PickVoice(zombie)
    local maleOptions = {"1", "2", "3", "4"} -- , "14", "16", "18", "21"}
    local femaleOptions = {"1", "2", "4"}

    if zombie:isFemale() then
        return HitmanUtils.Choice(femaleOptions)
    else
        return HitmanUtils.Choice(maleOptions)
    end
end

function Hitman.Say(zombie, phrase, force)
    local brain = HitmanBrain.Get(zombie)
    if not brain then return end
    
    if not force and brain.speech and brain.speech > 0 then return end
    if force then zombie:getEmitter():stopAll() end
    
    local player = getSpecificPlayer(0)
    local dist = HitmanUtils.DistTo(player:getX(), player:getY(), zombie:getX(), zombie:getY())
    
    if dist <= 14 then
        local voice

        local sex = "Male"
        if zombie:isFemale() then 
            sex = "Female" 
        end

        if brain.voice then 
            voice = brain.voice
        else
            -- if voice was not assigned on spawn then preserve backward compatibility
            if zombie:isFemale() then 
                voice = 3
            else
                voice = 1 + math.abs(brain.id) % 5
                if voice > 4 then voice = 1 end
            end
        end

        local config = Hitman.SoundTab[phrase]
        if config then
            local r = ZombRand(100)
            if r < config.chance then
                local sound = config.prefix .. sex .. "_" .. voice .. "_" .. tostring(1 + ZombRand(config.randMax))
                local length = config.length or 2

                -- text captions
                if SandboxVars.Hitmans.General_Captions then
                    local text = "IGUI_Hitmans_Speech_" .. sound
                    if brain.hostile or brain.hostileP then
                        zombie:addLineChatElement(getText(text), 0.8, 0.1, 0.1)
                    else
                        zombie:addLineChatElement(getText(text), 0.1, 0.8, 0.1)
                    end
                end

                -- audiable speech
                if SandboxVars.Hitmans.General_Speak then
                    zombie:getEmitter():playVocals(sound)
                end

                brain.speech = length

                addSound(getSpecificPlayer(0), zombie:getX(), zombie:getY(), zombie:getZ(), 5, 50)
            end
        end
    end

end

function Hitman.SayLocation(hitman, targetSquare)
    local hitmanSquare = hitman:getSquare()
    local targetBuilding = targetSquare:getBuilding()
    local hitmanBuilding = hitmanSquare:getBuilding()

    if targetBuilding and not hitmanBuilding then
        Hitman.Say(hitman, "INSIDE")
    end
    if not targetBuilding and hitmanBuilding then
        Hitman.Say(hitman, "OUTSIDE")
    end
    if targetBuilding and hitmanBuilding then
        if hitman:getZ() < targetSquare:getZ() then
            Hitman.Say(hitman, "UPSTAIRS")
        else
            local room = targetSquare:getRoom()
            if room then
                local roomName = room:getName()
                if roomName == "kitchen" then
                    Hitman.Say(hitman, "ROOM_KITCHEN")
                end
                if roomName == "bathroom" then
                    Hitman.Say(hitman, "ROOM_BATHROOM")
                end
            end
        end
    end
end

function Hitman.AddVisualDamage(hitman, handWeapon)
    
    if handWeapon then
        local itemVisual
        local weaponType = WeaponType.getWeaponType(handWeapon)
        if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
            itemVisual = HitmanUtils.Choice(Hitman.VisualDamage.Gun)
        else
            itemVisual = HitmanUtils.Choice(Hitman.VisualDamage.Melee)
        end

        hitman:addVisualDamage(itemVisual)
    end
end

function Hitman.GetCombatWalktype(hitman, enemy, dist)
    local world = getWorld()
    local cm = world:getClimateManager()
    local dls = cm:getDayLightStrength()

    local walkType = "Walk"

    if dls < 0.3 then
        if SandboxVars.Hitmans.General_SneakAtNight then
            walkType = "SneakWalk"
        end
    end

    if hitman and dist then
        if dist > 7 then
            walkType = "Run"
        elseif dist > 4 then
            walkType = "Walk"
        else
            walkType = "WalkAim"
        end

        if enemy then

            local enemyWeapon = enemy:getPrimaryHandItem()
            if enemyWeapon and enemyWeapon:IsWeapon() then
                local weaponType = WeaponType.getWeaponType(enemyWeapon)
                if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
                    walkType = "Run"
                end
            end
            
            local hitmanWeapon = hitman:getPrimaryHandItem()
            if hitmanWeapon and hitmanWeapon:IsWeapon() then
                local weaponType = WeaponType.getWeaponType(hitmanWeapon)
                if weaponType == WeaponType.firearm or weaponType == WeaponType.handgun then
                    local wrange = HitmanCompatibility.GetMaxRange(hitmanWeapon)

                    if dist > wrange + 10 then
                        walkType = "Run"
                    elseif dist > wrange + 4 then
                        walkType = "Walk"
                    else
                        walkType = "WalkAim"
                    end
                end
            end

        end

        if hitman:getHealth() < 0.8 then
            walkType = "Limp"
        end 
    end
    return walkType
end

function Hitman.GetSkinTexture(female, idx)
    if female then
        return "FemaleBody0" .. tostring(idx)
    else
        return "MaleBody0" .. tostring(idx) .. "a"
        --return "MaleBody0" .. tostring(idx)
    end
end

function Hitman.GetHairColor(idx)
    local desc = SurvivorFactory.CreateSurvivor(SurvivorType.Neutral, false)
    local hairColors = desc:getCommonHairColor()
    local tab = {}
    local info = ColorInfo.new()
    for i=1, hairColors:size() do
        local color = hairColors:get(i-1)
        info:set(color:getRedFloat(), color:getGreenFloat(), color:getBlueFloat(), 1)
        table.insert(tab, { r=info:getR(), g=info:getG(), b=info:getB() })
    end
    return tab[idx]
end

function Hitman.GetHairStyle(female, idx)
    local hairStyles = getAllHairStyles(female)
    local tab = {}
    for i=1, hairStyles:size() do
        local styleId = hairStyles:get(i-1)
        local hairStyle = female and getHairStylesInstance():FindFemaleStyle(styleId) or getHairStylesInstance():FindMaleStyle(styleId)
        if not hairStyle:isNoChoose() then
            table.insert(tab, styleId)
        end
    end
    return tab[idx]
end

function Hitman.GetBeardStyle(female, idx)
    if female then return end
    local tab = {}
    local beardStyles = getAllBeardStyles()
    for i=1, beardStyles:size() do
        local styleId = beardStyles:get(i-1)
        table.insert(tab, styleId)
    end
    return tab[idx]
end
