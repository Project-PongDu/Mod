local function predicateRemovable(item)
    if not item:getModData().hitmanPreserve and not instanceof(item, "Clothing") then
        return true 
    end
end

local function predicateAll(item)
	return true
end

-- ============================================================================
-- PERF helpers
-- ============================================================================

-- Frame counter driven by OnTick. Replaces the old shared uTick, which only
-- advanced when a hitman update ran to the very end: a hitman sitting in an
-- early-return state (onground, getup, staggerback...) froze it, so every
-- zombie's UpdateZombies ran either every frame or never.
local frameNo = 0

-- zombie -> hitman repath throttle, keyed by zombie id, value = frame after
-- which the zombie may re-evaluate/re-issue its path to a hitman
local REPATH_INTERVAL_FRAMES = 30
local repathTab = {}

-- counters for the periodic diagnostics line (see OnHitmanTick)
local PERF_LOG_INTERVAL_MS = 30000
local perfLogAt = 0
local perfStats = {repath = 0, repathThrottled = 0, remoteSkipped = 0, hitmanUpd = 0, hitmanMs = 0, hitmanMaxMs = 0}

local function ResetPerfStats()
    perfStats.repath = 0
    perfStats.repathThrottled = 0
    perfStats.remoteSkipped = 0
    perfStats.hitmanUpd = 0
    perfStats.hitmanMs = 0
    perfStats.hitmanMaxMs = 0
end

-- Weapon ranges depend only on weapon type and scope tier, so cache them
-- instead of instancing an InventoryItem (plus a scope item) on every combat
-- scan. Ported from Bandits B42.
local WeaponRangeCache = {melee = {}, ranged = {}}

-- thresholds must stay identical to HitmanUtils.ModifyWeapon
local function GetScopeTier(brain)
    local sight = brain and brain.accuracyBoost or 0
    if sight >= 1 and sight <= 2 then return "x2" end
    if sight > 2 and sight <= 3 then return "x4" end
    if sight > 3 then return "x8" end
    return "none"
end

local function GetMeleeRangeCached(weaponType)
    if not weaponType then return 0 end
    local cached = WeaponRangeCache.melee[weaponType]
    if cached then return cached end

    local range = 0
    local item = HitmanCompatibility.InstanceItem(weaponType)
    if item then
        range = item:getMaxRange()
    else
        print("[PongDu][Hitman] melee range: cannot instance " .. tostring(weaponType) .. ", using 0")
    end
    WeaponRangeCache.melee[weaponType] = range
    return range
end

local function GetRangedRangeCached(weaponType, brain)
    if not weaponType then return 0 end
    -- profile scope (brain.scope, HitmanUtils.ModifyWeapon) changes the range too
    local key = weaponType .. "|" .. GetScopeTier(brain) .. "|" .. tostring(brain and brain.scope or "")
    local cached = WeaponRangeCache.ranged[key]
    if cached then return cached end

    local range = 0
    local item = HitmanCompatibility.InstanceItem(weaponType)
    if item then
        item = HitmanUtils.ModifyWeapon(item, brain)
        range = HitmanCompatibility.GetMaxRange(item)
    else
        print("[PongDu][Hitman] ranged range: cannot instance " .. tostring(weaponType) .. ", using 0")
    end
    WeaponRangeCache.ranged[key] = range
    return range
end

local function CalcSpottedScore(player, dist)
    if not instanceof(player, "IsoPlayer") then return end

    local square = player:getSquare()
    if not square then return end
    local spottedScore = square:getLightLevel(0)

    if player:isRunning() then spottedScore = spottedScore + 0.1 end
    if player:isSprinting() then spottedScore = spottedScore + 0.12 end

    if player:isSneaking() then
        spottedScore = spottedScore - 0.1
        local objects = square:getObjects()
        for i = 0, objects:size() - 1 do
            local object = objects:get(i)
            local props = object and object:getProperties()
            if props and props:Is(IsoFlagType.vegitation) and props:Is(IsoFlagType.canBeCut) then
                spottedScore = spottedScore - 0.15
                break
            end
        end
    end

    -- distance-based adjustment
    if dist <= 8 then
        spottedScore = spottedScore + (0.65 - (dist * 0.075))
    end

    return spottedScore
end

-- checks if the line of fire is clear from friendlies
local function IsShotClear (shooter, enemy)

    local cell = getCell()

    local x0 = math.floor(shooter:getX())
    local y0 = math.floor(shooter:getY())
    local x1 = math.floor(enemy:getX())
    local y1 = math.floor(enemy:getY())
    local z = enemy:getZ()

    local dx = math.abs(x1 - x0)
    local dy = math.abs(y1 - y0)
    local sx = (x0 < x1) and 1 or -1
    local sy = (y0 < y1) and 1 or -1
    local err = dx - dy

    local cx, cy, cz = x0, y0, z

    local brainShooter = HitmanBrain.Get(shooter)
    local shooterId = HitmanUtils.GetCharacterID(shooter)

    local i = 0
    while true do

        -- last iteration
        -- must mirror the sweep in ZAShoot manageLineOfFire
        local isLast = (cx == x1 and cy == y1)
        local list = {}
        if isLast then
            local r = (i > 1) and 2 or 1
            for x = -r, r do
                for y = -r, r do
                    table.insert(list, {x = cx + x, y = cy + y, z=cz})
                end
            end
        else
            table.insert(list, {x=cx, y=cy, z=cz})
        end

        for _, c in pairs(list) do
            local square = cell:getGridSquare(c.x, c.y, c.z)
            -- point blank: the target square is reached within the first 2 steps
            if (i > 1 or isLast) and square then

                local chrs = square:getMovingObjects()
                for i=0, chrs:size()-1 do
                    local chr = chrs:get(i)
                    if instanceof(chr, "IsoPlayer") and not (brainShooter.hostile or brainShooter.hostileP) then
                        -- shooter:addLineChatElement("PLAYER IN LINE", 0.8, 0.8, 0.1)
                        return false
                    elseif instanceof(chr, "IsoZombie") and HitmanUtils.GetCharacterID(chr) ~= shooterId then
                        local brainEnemy = HitmanBrain.Get(chr)
                        if not HitmanUtils.AreEnemies(brainEnemy, brainShooter) then
                        -- if brainEnemy and brainEnemy.clan and brainShooter.clan == brainEnemy.clan and (not brainShooter.hostile or brainEnemy.hostile) then
                            -- shooter:addLineChatElement("FRIENDLY IN LINE", 0.8, 0.8, 0.1)
                            return false
                        end
                    end
                end
            end
        end

        if cx == x1 and cy == y1 then break end
        local e2 = 2 * err
        if e2 > -dy then
            err = err - dy
            cx = cx + sx
        end
        if e2 < dx then
            err = err + dx
            cy = cy + sy
        end
        i = i + 1
    end

    return true
end

-- turns a zombie into a hitman
local function Hitmanize(zombie, brain)

    -- load brain
    HitmanBrain.Update(zombie, brain)

    -- just in case
    zombie:setNoTeeth(true)

    -- used to determine if zombie is a hitman, can be used by other mods
    zombie:setVariable("Hitman", true)

    -- hitman primary and secondary hand items
    zombie:setVariable("HitmanPrimary", "")
    zombie:setVariable("HitmanSecondary", "")

    -- hitman walking type defined in animations
    zombie:setWalkType("Walk")
    zombie:setVariable("HitmanWalkType", "Walk")

    -- this shit here is important, removes black screen crashes
    -- with this var set, game engine skips testDefense function that
    -- wrongly refers to moodles, which zombie object does not have
    zombie:setVariable("ZombieHitReaction", "Chainsaw")

    -- stfu
    zombie:getEmitter():stopAll()

    zombie:setPrimaryHandItem(nil)
    zombie:setSecondaryHandItem(nil)
    zombie:resetEquippedHandsModels()
    zombie:clearAttachedItems()

    -- makes hitman unstuck after spawns
    zombie:setTurnAlertedValues(-5, 5)

end

-- turns hitman into a zombie
local function Zombify(hitman)
    hitman:setNoTeeth(false)
    hitman:setUseless(false)
    hitman:setVariable("Hitman", false)
    hitman:setVariable("HitmanPrimary", "")
    hitman:setVariable("HitmanSecondary", "")
    hitman:setWalkType("2")
    hitman:setVariable("HitmanWalkType", "")
    hitman:setPrimaryHandItem(nil)
    hitman:setSecondaryHandItem(nil)
    hitman:resetEquippedHandsModels()
    hitman:clearAttachedItems()
    HitmanBrain.Remove(hitman)
end

-- applies human look for a hitmanized zaombie
local function ApplyVisuals(hitman, brain)
    local hitmanVisuals = hitman:getHumanVisual()
    if not hitmanVisuals then return end

    local skin = hitmanVisuals:getSkinTexture()
    if not skin or skin:find("^FemaleBody") or skin:find("^MaleBody") then return end

    local itemVisuals = hitman:getItemVisuals()

    if brain.cid then

        if Hitman.HasExpertise(hitman, Hitman.Expertise.Recon) then
            hitman:setVariable("MovementSpeed", 1.20)
        else
            hitman:setVariable("MovementSpeed", 0.70)
        end

        hitman:setHealth(brain.health)

        if brain.skin then
            hitmanVisuals:setSkinTextureName(Hitman.GetSkinTexture(brain.female, brain.skin))
        end

        if brain.hairType then
            hitmanVisuals:setHairModel(Hitman.GetHairStyle(brain.female, brain.hairType)) 
        end

        if not hitman:isFemale() and brain.beardType then
            local beardModel = Hitman.GetBeardStyle(brain.female, brain.beardType)
            if beardModel then
                hitmanVisuals:setBeardModel(beardModel) 
            end
        end

        if brain.hairColor then
            local hairColor = Hitman.GetHairColor(brain.hairColor)
            local icolor = ImmutableColor.new(hairColor.r, hairColor.g, hairColor.b)
            hitmanVisuals:setHairColor(icolor) 
            hitmanVisuals:setBeardColor(icolor) 
        end

        -- items must be applied in a good order, hence the double loop
        for _, bodyLocationDef in pairs(HitmanCompatibility.GetBodyLocationsOrdered()) do
            for bodyLocation, itemType in pairs(brain.clothing) do
                if bodyLocation == bodyLocationDef then
                    local item = HitmanCompatibility.InstanceItem(itemType)
                    if item then
                        --[[
                        local clothingItem = item:getClothingItem()
                        if clothingItem then
                            local itemVisual = hitmanVisuals:addClothingItem(itemVisuals, clothingItem)
                        end]]
                        local itemVisual = ItemVisual.new()
                        itemVisual:setItemType(itemType)
                        itemVisual:setClothingItemName(itemType)

                        if brain.tint[bodyLocation] then
                            local color = HitmanUtils.dec2rgb(brain.tint[bodyLocation])
                            local immutableColor = ImmutableColor.new(color.r, color.g, color.b, 1)
                            itemVisual:setTint(immutableColor)
                        end

                        itemVisuals:add(itemVisual)
                    end
                end
            end
        end

        for _, slot in pairs({"primary", "secondary", "melee"}) do

            if brain.weapons[slot].name then
                local weapon = HitmanCompatibility.InstanceItem(brain.weapons[slot].name)

                if weapon then
                    weapon = HitmanUtils.ModifyWeapon(weapon, brain)

                    local attachmentType = weapon:getAttachmentType()

                    for _, def in pairs(ISHotbarAttachDefinition) do
                        if def.type == "HolsterRight" or def.type == "Back" or def.type == "SmallBeltLeft" then
                            if def.attachments then
                                for k, v in pairs(def.attachments) do
                                    if k == attachmentType then
                                        hitman:setAttachedItem(v, weapon)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end

        if brain.bag and brain.bag.name then
            local item = HitmanCompatibility.InstanceItem(brain.bag.name)
            if item then
                --[[
                local clothingItem = item:getClothingItem()
                local itemVisual = hitmanVisuals:addClothingItem(itemVisuals, clothingItem)]]

                local itemVisual = ItemVisual.new()
                itemVisual:setItemType(brain.bag.name)
                itemVisual:setClothingItemName(brain.bag.name)
                local immutableColor = ImmutableColor.new(0.1, 0.1, 0.1, 1)
                itemVisual:setTint(immutableColor)
                itemVisuals:add(itemVisual)
            end
            -- hitman:setWornItem(item:canBeEquipped(), item)
        end
        
    else
        if brain.skinTexture then 
            hitmanVisuals:setSkinTextureName(brain.skinTexture)
        end
        if brain.hairStyle then 
            hitmanVisuals:setHairModel(brain.hairStyle) 
        end
        if brain.hairColor then
            hitmanVisuals:setHairColor(ImmutableColor.new(brain.hairColor.r, brain.hairColor.g, brain.hairColor.b))
        end
        if brain.beardStyle then 
            hitmanVisuals:setBeardModel(brain.beardStyle)
        end
        if brain.beardColor then
            hitmanVisuals:setBeardColor(ImmutableColor.new(brain.beardColor.r, brain.beardColor.g, brain.beardColor.b))
        end
    end

    hitmanVisuals:randomDirt()
    hitmanVisuals:removeBlood()

    -- Cleanup blood/dirt
    local maxIndex = BloodBodyPartType.MAX:index()
    for i = 0, maxIndex - 1 do
        local part = BloodBodyPartType.FromIndex(i)
        hitmanVisuals:setBlood(part, 0)
        hitmanVisuals:setDirt(part, 0)
    end

    -- Cleanup item visuals
    
    for i = 0, itemVisuals:size() - 1 do
        local item = itemVisuals:get(i)
        if item then
            for j = 0, maxIndex - 1 do
                local part = BloodBodyPartType.FromIndex(j)
                item:removeHole(j)
                item:setBlood(part, 0)
                item:setDirt(part, 0)
            end
            item:setInventoryItem(nil)
        end
    end

    -- Remove hitman-specific body visuals
    local bodyVisuals = hitmanVisuals:getBodyVisuals()
    local toRemove, toRemoveCount = {}, 0
    for i = 0, bodyVisuals:size() - 1 do
        local item = bodyVisuals:get(i)
        if item and HitmanUtils.ItemVisuals[item:getItemType()] then
            toRemoveCount = toRemoveCount + 1
            toRemove[toRemoveCount] = item:getItemType()
        end
    end
    for i = 1, toRemoveCount do
        hitmanVisuals:removeBodyVisualFromItemType(toRemove[i])
    end

    --[[
    local clothing = HitmanCustom.GetClothing("hitman1")

    for i=1, #clothing do
        local item = HitmanCompatibility.InstanceItem(clothing[i])
        local clothingItem = item:getClothingItem()
        local itemVisual = hitmanVisuals:addClothingItem(itemVisuals, clothingItem)
    end]]

    -- Reset model to apply changes
    hitman:resetModelNextFrame()
    hitman:resetModel()

    Hitman.UpdateItemsToSpawnAtDeath(hitman)
end

-- updates hitman torches light
local function ManageTorch(hitman)
    if not Hitman.Settings.CarryTorches then return end

    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local vehicle = hitman:getVehicle()
    local cell = getCell()

    if vehicle then return end
    
    local colors = {r = 1, g = 1, b = 0.8}

    local md = hitman:getModData()
    if not md.torch then md.torch = {} end

    if hitman:isProne() then
        --[[
        local lightSource = IsoLightSource.new(zx, zy, zz, colors.r, colors.g, colors.b, 2, 2)
        if lightSource then
            getCell():addLamppost(lightSource)
        end]]
    else
        local theta = hitman:getDirectionAngle() * 0.0174533  -- Convert degrees to radians
        for i = 2, 14 do
            local fadeFactor = i * 0.05
            local lx = math.floor(zx + (i * math.cos(theta)))
            local ly = math.floor(zy + (i * math.sin(theta)))
            local lz = zz + 32

            if md.torch[i] then
                md.torch[i]:setActive(false)
                -- print ("REM: x: ".. md.torch[i]:getX() .. " y:" .. md.torch[i]:getY() .. " z:" .. md.torch[i]:getZ() .. " i:" .. i)
                cell:removeLamppost(md.torch[i])
            end

            -- print ("ADD x: ".. lx .. " y:" .. ly .. " z:" .. lz .. " i:" .. i)
            ls = IsoLightSource.new(lx, ly, zz, colors.r, colors.g, colors.b, i * 0.5, 20)
            md.torch[i] = ls
            cell:addLamppost(md.torch[i])
            
        end
    end
end

-- update hitman chainsaw sound
local function ManageChainsaw(hitman)
    if hitman:isPrimaryEquipped("AuthenticZClothing.Chainsaw") then
        local emitter = hitman:getEmitter()
        if not emitter:isPlaying("ChainsawIdle") then
            hitman:playSound("ChainsawIdle")
        end
    end
end

-- updates hitman being on fire
local function ManageOnFire(hitman)
    if hitman:isOnFire() then
        if not Hitman.HasTaskType(hitman, "Die") then
            Hitman.ClearTasks(hitman)
            Hitman.AddTask(hitman, {action="Die", lock=true, anim="Die", fire=true, time=250})
        end
        return
    end

    local cell = hitman:getCell()
    local bx, by, bz = hitman:getX(), hitman:getY(), hitman:getZ()

    if Hitman.HasActionTask(hitman) then return end

    for x = -2, 2 do
        for y = -2, 2 do
            local testSquare = cell:getGridSquare(bx + x, by + y, bz)
            if testSquare and testSquare:haveFire() then
                Hitman.ClearTasks(hitman)
                Hitman.AddTask(hitman, {action="Time", anim="Cough", time=200})
                return
            end
        end
    end
end

-- reduces cooldown for hitman speech
local function ManageSpeechCooldown(brain)
    if brain.speech and brain.speech > 0 then
        brain.speech = brain.speech - 0.01
        if brain.speech < 0 then brain.speech = 0 end
        -- HitmanBrain.Update(hitman, brain)
    end
end

-- reduces cooldown for hitman sounds
local function ManageSoundCoolDown(brain)
    if brain.sound and brain.sound > 0 then
        brain.sound = brain.sound - 0.001
        if brain.sound < 0 then brain.sound = 0 end
        -- HitmanBrain.Update(hitman, brain)
    end
end

-- applies tweaks based on hitman action state
-- action states that clear the task queue and stop this update
local ClearTaskActionStates = {
    ["getup"] = true,
    ["getup-fromonback"] = true,
    ["getup-fromonfront"] = true,
    ["getup-fromsitting"] = true,
    ["staggerback"] = true,
    ["staggerback-knockeddown"] = true,
}

local function ManageActionState(hitman)
    local asn = hitman:getActionStateName()

    -- PERF (ported from Bandits B42): plain branches instead of building a
    -- table of 11 closures on every call. Behaviour per state is unchanged.
    if asn == "onground" then
        if not hitman:getVehicle() then
            if hitman:isUnderVehicle() then
                local bx, by = hitman:getX(), hitman:getY()
                hitman:setX(bx + 0.5)
                hitman:setY(by + 0.5)
            end
            Hitman.ClearTasks(hitman)
            return false
        end
        return true
    elseif asn == "turnalerted" then
        hitman:changeState(ZombieIdleState.instance())
        hitman:clearAggroList()
        hitman:setTarget(nil)
        return true
    elseif asn == "pathfind" then
        return false
    elseif asn == "lunge" then
        hitman:setUseless(true)
        hitman:clearAggroList()
        hitman:setTarget(nil)
        return true
    elseif asn and ClearTaskActionStates[asn] then
        Hitman.ClearTasks(hitman)
        return false
    end

    -- Default behavior (for undefined states)
    hitman:setTarget(nil)
    hitman:setTargetSeenTime(0)
    hitman:setUseless(getWorld():getGameMode() ~= "Multiplayer" or Hitman.IsForceStationary(hitman))

    return true
end

-- manages endurance regain tasks 
local function ManageEndurance(hitman)
    -- hitmen never tire / never stop to rest (relentless pursuit)
    return {}
end

-- manages tasks related to hitman health
local function ManageHealth(hitman)
    local tasks = {}

    -- temporarily removed until bleeding bug in week one investigation is complete
    if Hitman.Settings.BleedOut then
        local healing = false
        local health = hitman:getHealth()
        if health < 0.7 then
            local zx, zy = hitman:getX(), hitman:getY()

            -- purely visual so random allowed
            if ZombRand(16) == 0 then
                local bx = zx - 0.5 + ZombRandFloat(0.1, 0.9)
                local by = zy - 0.5 + ZombRandFloat(0.1, 0.9)
                hitman:getChunk():addBloodSplat(bx, by, 0, ZombRand(20))
            end
            hitman:setHealth(health - 0.00005)
        end
    end

    if Hitman.Settings.Infection then
        local brain = HitmanBrain.Get(hitman)
        if brain.infection and brain.infection > 0 then
            -- print ("INFECTION: " .. brain.infection)
            Hitman.UpdateInfection(hitman, 0.001)
            if brain.infection >= 100 then
                Hitman.ClearTasks(hitman)
                local task = {action="Zombify", anim="Faint", lock=true, time=200}
                table.insert(tasks, task)
            end
        end
    end
    return tasks
end

-- manages collisions with doors, windows, fences and other objects
local function ManageCollisions(hitman)
    local tasks = {}

    if Hitman.HasActionTask(hitman) then return {} end

    if not hitman:isCollidedThisFrame() then return {} end

    local weapons = Hitman.GetWeapons(hitman)

    local fd = hitman:getForwardDirection()
    local fdx = math.floor(fd:getX() + 0.5)
    local fdy = math.floor(fd:getY() + 0.5)

    local sqs = {}
    table.insert(sqs, {x = math.floor(hitman:getX()), y = math.floor(hitman:getY()), z = hitman:getZ()})
    table.insert(sqs, {x = math.floor(hitman:getX()) + fdx, y=math.floor(hitman:getY()) + fdy, z = hitman:getZ()})

    local cell = getCell()
    for _, s in pairs(sqs) do
        local square = cell:getGridSquare(s.x, s.y, s.z)
        if square then

            -- local safehouse = SafeHouse.isSafeHouse(square, nil, true)
            -- print ("SQ X:" .. square:getX() .. " Y:" .. square:getY())
            local objects = square:getObjects()
            for i = 0, objects:size() - 1 do
                local object = objects:get(i)
                local properties = object:getProperties()

                if properties then
                    local lowFence = properties:Val("FenceTypeLow")
                    local hoppable = object:isHoppable()

                    -- LOW FENCE COLLISION
                    if lowFence or hoppable then
                        if hitman:isFacingObject(object, 0.5) then
                            local params = hitman:getStateMachineParams(ClimbOverFenceState.instance())
                            local raw = KahluaUtil.rawTostring2(params) -- ugly but works
                            local endx = string.match(raw, "3=(%d+)")
                            local endy = string.match(raw, "4=(%d+)")

                            if endx and endy then
                                hitman:changeState(ClimbOverFenceState.instance())
                                hitman:setBumpType("ClimbFenceEnd")
                            end
                        else
                            hitman:faceThisObject(object)
                        end
                        return tasks
                    end

                    -- HIGH FENCE COLLISION
                    local highFence = properties:Val("FenceTypeHigh")
                    if highFence and hoppable then
                        if hitman:getVariableBoolean("bPathfind") or not hitman:getVariableBoolean("bMoving") then
                            hitman:setVariable("bPathfind", false)
                            hitman:setVariable("bMoving", true)
                        end

                        if hitman:isFacingObject(object, 0.5) then

                            -- hitman:changeState(ClimbOverFenceState.instance())
                            if not hitman:getVariableBoolean("ClimbWallStartEnded") then
                                hitman:setVariable("hitreaction", "ClimbWallStart")
                            else
                                hitman:setCollidable(false)
                                hitman:setVariable("hitreaction", "ClimbWallSuccess")
                            end


                        else
                            hitman:faceThisObject(object)
                        end
                        return tasks
                    end

                    -- WINDOW COLLISIONS
                    if instanceof(object, "IsoWindow") then
                        if hitman:isFacingObject(object, 0.5) then
                            if object:isBarricaded() then
                                Hitman.Say(hitman, "BREACH")
                                local barricade = object:getBarricadeOnSameSquare()
                                if not barricade then barricade = object:getBarricadeOnOppositeSquare() end
                                local fx, fy
                                if barricade then
                                    if properties:Is(IsoFlagType.WindowN) then
                                        fx = barricade:getX()
                                        fy = barricade:getY() - 0.5
                                    else
                                        fx = barricade:getX() - 0.5
                                        fy = barricade:getY()
                                    end

                                else
                                    barricade = object:getBarricadeOnOppositeSquare()
                                    if properties:Is(IsoFlagType.WindowN) then
                                        fx = barricade:getX()
                                        fy = barricade:getY() + 0.5
                                    else
                                        fx = barricade:getX() + 0.5
                                        fy = barricade:getY()
                                    end
                                end

                                if Hitman.Settings.RemoveBarricade and Hitman.HasExpertise(hitman, Hitman.Expertise.Breaker) then
                                    if barricade:isMetal() or barricade:isMetalBar() then
                                        if not hitman:isPrimaryEquipped("Hitmans.PropaneTorch") then
                                            local stasks = HitmanPrograms.Weapon.Switch(hitman, "Hitmans.PropaneTorch")
                                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                                        end
                                        local task = {action="UnbarricadeMetal", anim="BlowtorchHigh", time=500, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                        table.insert(tasks, task)
                                        return tasks
                                    else
                                        anim = "RemoveBarricadeCrowbarMid"
                                        local planks = barricade:getNumPlanks()
                                        if planks == 2 or planks == 4 then
                                            anim = "RemoveBarricadeCrowbarHigh"
                                        end
                                        if not hitman:isPrimaryEquipped("Base.Crowbar") then
                                            local stasks = HitmanPrograms.Weapon.Switch(hitman, "Base.Crowbar")
                                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                                        end
                                        local task = {action="Unbarricade", anim=anim, time=300, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                        table.insert(tasks, task)
                                        return tasks
                                    end
                                else
                                    if not hitman:isPrimaryEquipped(weapons.melee) then
                                        local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                        for _, t in pairs(stasks) do table.insert(tasks, t) end
                                    end
                                    local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                    table.insert(tasks, task)
                                    return tasks
                                end

                            elseif not object:IsOpen() and not object:isSmashed() then
                                if true then
                                    Hitman.Say(hitman, "BREACH")
                                    local task = {action="SmashWindow", anim="WindowSmash", time=25, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ()}
                                    table.insert(tasks, task)
                                elseif not object:isPermaLocked() then
                                    local task = {action="OpenWindow", anim="WindowOpen", time=25, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ()}
                                    table.insert(tasks, task)
                                    return tasks
                                end

                            elseif object:canClimbThrough(hitman) then
                                ClimbThroughWindowState.instance():setParams(hitman, object)
                                hitman:changeState(ClimbThroughWindowState.instance())
                                hitman:setBumpType("ClimbWindow")
                                return tasks
                            end
                        end

                    elseif false and (properties:Is(IsoFlagType.WindowW) or properties:Is(IsoFlagType.WindowN)) then
                        ClimbThroughWindowState.instance():setParams(hitman, object)
                        hitman:changeState(ClimbThroughWindowState.instance())
                        hitman:setBumpType("ClimbWindow")
                        return tasks
                    end

                    -- DOOR COLLISIONS
                    if instanceof(object, "IsoDoor") or (instanceof(object, 'IsoThumpable') and object:isDoor() == true) then
                        if hitman:isFacingObject(object, 0.5) then

                            if object:isBarricaded() then
                                local barricade = object:getBarricadeOnSameSquare()
                                local fx, fy
                                if barricade then
                                    if properties:Is(IsoFlagType.doorN) then
                                        fx = barricade:getX()
                                        fy = barricade:getY() - 1
                                    else
                                        fx = barricade:getX() - 1
                                        fy = barricade:getY()
                                    end

                                else
                                    barricade = object:getBarricadeOnOppositeSquare()
                                    if properties:Is(IsoFlagType.doorN) then
                                        fx = barricade:getX()
                                        fy = barricade:getY() + 1
                                    else
                                        fx = barricade:getX() + 1
                                        fy = barricade:getY()
                                    end
                                end
                                local sameSide = barricade:getSquare():getX() == hitman:getSquare():getX() and barricade:getSquare():getY() == hitman:getSquare():getY()

                                if Hitman.Settings.RemoveBarricade and Hitman.HasExpertise(hitman, Hitman.Expertise.Breaker) and sameSide then
                                    anim = "RemoveBarricadeCrowbarMid"
                                    local planks = barricade:getNumPlanks()
                                    if planks == 2 or planks == 4 then
                                        anim = "RemoveBarricadeCrowbarHigh"
                                    end
                                    if not hitman:isPrimaryEquipped("Base.Crowbar") then
                                        local stasks = HitmanPrograms.Weapon.Switch(hitman, "Base.Crowbar")
                                        for _, t in pairs(stasks) do table.insert(tasks, t) end
                                    end
                                    local task = {action="Unbarricade", anim=anim, time=300, fx=fx, fy=fy, x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                    table.insert(tasks, task)
                                    return tasks
                                else
                                    if not hitman:isPrimaryEquipped(weapons.melee) then
                                        local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                        for _, t in pairs(stasks) do table.insert(tasks, t) end
                                    end
                                    local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                    table.insert(tasks, task)
                                    return tasks
                                end

                            elseif not object:IsOpen() then
                                if IsoDoor.getDoubleDoorIndex(object) > -1 then

                                    if object:isLocked() or object:isLockedByKey() or object:isObstructed() then
                                        if hitman:isPrimaryEquipped(weapons.melee) then
                                            local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                            table.insert(tasks, task)
                                        else
                                            local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                                            return tasks
                                        end
                                    else
                                        IsoDoor.toggleDoubleDoor(object, true)
                                        local doorSound = properties:Is("DoorSound") and properties:Val("DoorSound") or "WoodDoor"
                                        doorSound = doorSound .. "Open"
                                        hitman:playSound(doorSound)
                                    end

                                elseif IsoDoor.getGarageDoorIndex(object) > -1 then
                                
                                    local exterior = hitman:getCurrentSquare():Is(IsoFlagType.exterior)
                                    if exterior and (object:isLocked() or object:isLockedByKey()) then
                                        if hitman:isPrimaryEquipped(weapons.melee) then
                                            local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                            table.insert(tasks, task)
                                        else
                                            local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                                            return tasks
                                        end
                                    else
                                        IsoDoor.toggleGarageDoor(object, true)
                                        local doorSound = properties:Is("DoorSound") and properties:Val("DoorSound") or "WoodDoor"
                                        doorSound = doorSound .. "Open"
                                        hitman:playSound(doorSound)
                                    end
                                else

                                    -- door locks are complicated... 
                                    local test11=object:isLocked()
                                    local test12=object:isLockedByKey()
                                    local test13=hitman:getCurrentSquare():getRoom()
                                    local test14=object:getProperties():Is("forceLocked")
                                    local test15=object:isObstructed()
                                    if ((object:isLocked() or object:isLockedByKey()) and (not hitman:getCurrentSquare():getRoom() or object:getProperties():Is("forceLocked"))) or object:isObstructed() then
                                        if hitman:isPrimaryEquipped(weapons.melee) then
                                            local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), idx=object:getObjectIndex()}
                                            table.insert(tasks, task)
                                        else
                                            local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                                            return tasks
                                        end
                                    else
                                        object:DirtySlice()
                                        IsoGridSquare.RecalcLightTime = -1.0
                                        square:InvalidateSpecialObjectPaths()
                                        object:ToggleDoorSilent()
                                        square:RecalcProperties()
                                        object:syncIsoObject(false, 1, nil, nil)
                                        LuaEventManager.triggerEvent("OnContainerUpdate")
                                        if HitmanCompatibility.GetGameVersion() >= 42 then
                                            object:invalidateRenderChunkLevel(FBORenderChunk.DIRTY_OBJECT_MODIFY)
                                        end

                                        --[[
                                        local args = {
                                            x = object:getSquare():getX(),
                                            y = object:getSquare():getY(),
                                            z = object:getSquare():getZ(),
                                            index = object:getObjectIndex()
                                        }
                                        sendClientCommand(getSpecificPlayer(0), 'Hitman_Commands', 'OpenDoor', args)

                                        -- Get the square of the object
                                        local square = getSpecificPlayer(0):getSquare()

                                        -- Recalculate vision blocked for the surrounding tiles in a r-tile radius
                                        local radius = 5
                                        for dx = -radius, radius do
                                            for dy = -radius, radius do
                                                -- if dx ~= 0 and dy ~= 0 then
                                                    local surroundingSquare = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                                                    --local surroundingSquare = getCell():getGridSquare(square:getX(), square:getY() + 1, square:getZ())
                                                    if surroundingSquare then
                                                        
                                                        --
                                                        square:ReCalculateCollide(surroundingSquare)
                                                        square:ReCalculatePathFind(surroundingSquare)
                                                        square:ReCalculateVisionBlocked(surroundingSquare)
                                                        surroundingSquare:ReCalculateCollide(square)
                                                        surroundingSquare:ReCalculatePathFind(square)
                                                        surroundingSquare:ReCalculateVisionBlocked(square)
                                                        --
                                                        
                                                        surroundingSquare:InvalidateSpecialObjectPaths()
                                                        surroundingSquare:RecalcProperties()
                                                        surroundingSquare:RecalcAllWithNeighbours(true)
                                                    end
                                                -- end
                                            end
                                        end
                                        ]]
                                        local doorSound = properties:Is("DoorSound") and properties:Val("DoorSound") or "WoodDoor"
                                        doorSound = doorSound .. "Open"
                                        hitman:playSound(doorSound)
                                    end
                                end
                            end
                        else
                            hitman:faceThisObject(object)
                        end
                    end

                    -- THUMPABLE COLLISIONS
                    if instanceof(object, "IsoThumpable") and not properties:Val("FenceTypeLow") then
                        local isWallTo = hitman:getSquare():isSomethingTo(object:getSquare())
                        if not isWallTo then
                            if hitman:isPrimaryEquipped(weapons.melee) then
                                local task = {action="Destroy", anim="ChopTree", x=object:getSquare():getX(), y=object:getSquare():getY(), z=object:getSquare():getZ(), soundEnd=object:getThumpSound(), time=80}
                                table.insert(tasks, task)
                            else
                                local stasks = HitmanPrograms.Weapon.Switch(hitman, weapons.melee)
                                for _, t in pairs(stasks) do table.insert(tasks, t) end
                                return tasks
                            end
                        end
                    end
                end
            end
        end
    end

    return tasks
end

-- PONGDU: combat tuning
-- zombies aggro'd on the hitman (UpdateZombies sets their target within 3 tiles)
-- are the top priority; only these plain zombies are ever fought
local THREAT_DIST = 3
-- a ranged hitman shoves with the gun in hand when an enemy is this close
local GUN_SHOVE_DIST = 1.0
-- after a gun shove the hitman keeps shooting, even at contact range, for this long (ms)
local GUN_SHOVE_COOLDOWN = 2500

local gunShoveTime = {}   -- [hitman id] = timestamp of the last gun shove
local combatLogKey = {}   -- [hitman id] = last logged target key

-- logs target changes only, so the console is not flooded every tick
local function LogTarget(brain, tier, enemy, dist, gunSlot)
    local eid = enemy and HitmanUtils.GetCharacterID(enemy)
    local key = tier .. ":" .. tostring(eid)
    if combatLogKey[brain.id] == key then return end
    combatLogKey[brain.id] = key
    if enemy then
        print(string.format("[PongDu][Hitman] id=%s target=%s eid=%s dist=%.2f mode=%s", tostring(brain.id), tier, tostring(eid), dist, gunSlot and ("gun:" .. gunSlot) or "melee"))
    else
        print("[PongDu][Hitman] id=" .. tostring(brain.id) .. " target=none")
    end
end

-- drops per-hitman combat state when the hitman dies
local function ClearCombatState(brain)
    gunShoveTime[brain.id] = nil
    combatLogKey[brain.id] = nil
end

-- true while the gun slot has ammo anywhere (loaded, magazines or loose rounds)
local function SlotHasAmmo(w)
    if not w or not w.name then return false end
    if (w.bulletsLeft or 0) > 0 then return true end
    if w.type == "mag" and (w.magCount or 0) > 0 then return true end
    if w.type == "nomag" and (w.ammoCount or 0) > 0 then return true end
    return false
end

-- gun slot a ranged hitman fights with; nil once every gun is dry (melee mode)
local function GetGunSlot(hitman, weapons)
    local p, s = weapons.primary, weapons.secondary
    if p.name and (p.bulletsLeft or 0) > 0 then return "primary" end
    -- rifle is empty but the pistol in hand is loaded: keep shooting instead of reloading
    if s.name and (s.bulletsLeft or 0) > 0 and hitman:isPrimaryEquipped(s.name) then return "secondary" end
    if SlotHasAmmo(p) then return "primary" end
    if SlotHasAmmo(s) then return "secondary" end
    return nil
end

-- closest plain zombie that is targeting this hitman within THREAT_DIST
local function FindThreatZombie(hitman, zx, zy, zz)
    local cache = HitmanZombie.Cache
    local best, bestDist
    for id, light in pairs(HitmanZombie.CacheLightZ) do
        local dx, dy = light.x - zx, light.y - zy
        if math.abs(dx) <= THREAT_DIST and math.abs(dy) <= THREAT_DIST then
            local dist = math.sqrt((dx * dx) + (dy * dy))
            if dist <= THREAT_DIST and (not bestDist or dist < bestDist) then
                local zombie = cache[id]
                if zombie and zombie:isAlive() and math.abs(zombie:getZ() - zz) < 0.5
                   and not zombie:getVariableBoolean("Bandit")
                   and zombie:getTarget() == hitman
                   and HitmanUtils.LineClear(hitman, zombie) then
                    best, bestDist = zombie, dist
                end
            end
        end
    end
    return best, bestDist
end

-- standing targets only; knocked down / climbing ones get shot instead
local function CanBeShoved(enemy)
    if enemy:isProne() then return false end
    local asn = enemy:getActionStateName()
    return asn ~= "onground" and asn ~= "sitonground" and asn ~= "climbfence" and asn ~= "bumped"
       and asn ~= "getup" and asn ~= "falldown"
end

-- manages melee and weapon combat
-- target priority: 1) zombies aggro'd on the hitman within THREAT_DIST
--                  2) players
--                  3) hitmen of other clans / Bandits NPCs
-- airborne troopers (program "Airborne", features/airborne.lua) instead:
--                  1) the closest enemy within 10 tiles of the trooper (own
--                     survival first), then hostile hitmen shooting at it
--                  2) the worst threat to the escorted player (drone-style
--                     ranking, special pool = mutants + hostile hitmen)
--                  never players, never tier 3. Targets are sticky (see
--                  PickSelfThreat/PickEscortThreat), a retarget turns instantly,
--                  aims for AIM_TICKS and fires per FirePlan (full auto <= 30 tiles)
-- ranged mode: while any gun has ammo the hitman never uses melee weapons;
--              enemies at contact range get shoved with the gun in hand, then shot
local function ManageCombat(hitman)

    if hitman:isCrawling() then return {} end
    if Hitman.IsSleeping(hitman) then return {} end
    -- if hitman:getActionStateName() == "bumped" then return {} end

    local tasks = {}
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local brain = HitmanBrain.Get(hitman)
    local weapons = brain.weapons
    local gunSlot = GetGunSlot(hitman, weapons)
    local isNeedPrimary = HitmanBrain.NeedResupplySlot(brain, "primary")
    local isNeedSecondary = HitmanBrain.NeedResupplySlot(brain, "secondary")
    local isBareHands = HitmanBrain.IsBareHands(brain)
    local isOutside = hitman:getSquare():isOutside()
    local isTrooper = PongDuAirborne ~= nil and brain.program ~= nil and brain.program.name == "Airborne"

    local bestDist = 40
    local enemyCharacter, switchTo, fireSlot
    local tier = "none"
    local reload, resupply = false, false
    local combat, switch, firing, shove, escape = false, false, false, false, false
    local friendlies, friendliesBwd, enemies, enemiesBwd = 0, 0, 0, 0
    local sx, sy = 0, 0

    -- THIS GOVERNS LOW-PRIORITY TASKS
    if not HitmanBrain.HasActionTask(brain) then

        -- PEACFUL RELOAD FLAG
        for _, slot in pairs({"primary", "secondary"}) do
            if weapons[slot].name then
                if (weapons[slot].type == "mag" and weapons[slot].bulletsLeft <= 0 and weapons[slot].magCount > 0) or
                   (weapons[slot].type == "nomag" and weapons[slot].bulletsLeft < weapons[slot].ammoSize and weapons[slot].ammoCount > 0) or
                    weapons[slot].racked == false then

                    if hitman:isPrimaryEquipped(weapons[slot].name) then
                        reload = true
                    end
                end
            end
        end

        -- RESUPPLY FLAG
        -- airborne troopers never leave their escort to go looting
        if (isBareHands or isNeedPrimary or isNeedSecondary) and not isTrooper then
            resupply = true
        end
    end

    -- SWITCH WEAPON DISTANCES
    local meleeDist = isOutside and 2.6 or 1.2
    local meleeDistPlayer = isOutside and 3.5 or 1.2
    local escapeDist = 5.2
    local bwdDist = 2.8

    -- PRIORITY 1: ZOMBIES AGGRO'D ON THIS HITMAN
    -- (airborne trooper: every enemy within 10 tiles, closest first, then a
    --  hostile hitman shooting at it from further away)
    local threat, threatDist
    if isTrooper then
        threat, threatDist = PongDuAirborne.PickSelfThreat(hitman, brain)
        if not threat then
            threat, threatDist = PongDuAirborne.FindAttacker(hitman, brain)
        end
    else
        threat, threatDist = FindThreatZombie(hitman, zx, zy, zz)
    end
    if threat then
        bestDist, enemyCharacter, tier = threatDist, threat, "threat"
    end

    -- PRIORITY 2 (airborne trooper): WORST THREAT TO THE ESCORTED PLAYER
    if not enemyCharacter and isTrooper then
        local escort = HitmanUtils.GetTrackedPlayer(hitman)
        local t = escort and PongDuAirborne.PickEscortThreat(hitman, brain, escort)
        if t then
            local tx, ty = t:getX(), t:getY()
            bestDist = math.sqrt(((zx - tx) * (zx - tx)) + ((zy - ty) * (zy - ty)))
            enemyCharacter, tier = t, "escort"
        end

    -- PRIORITY 2: PLAYERS
    elseif not enemyCharacter and (brain.hostile or brain.hostileP) then
        local playerList = HitmanPlayer.GetPlayers()

        for i=0, playerList:size()-1 do
            local potentialEnemy = playerList:get(i)
            if potentialEnemy and potentialEnemy:isAlive() and hitman:CanSee(potentialEnemy) and not potentialEnemy:isBehind(hitman) and (instanceof(potentialEnemy, "IsoPlayer") and not HitmanPlayer.IsGhost(potentialEnemy)) then
                local px, py, pz = potentialEnemy:getX(), potentialEnemy:getY(), potentialEnemy:getZ()
                local dist = math.sqrt(((zx - px) * (zx - px)) + ((zy - py) * (zy - py))) -- no function call for performance
                if dist < bestDist and math.abs(zz - pz) < 0.5 then
                    local spottedScore = CalcSpottedScore(potentialEnemy, dist)
                    if not hitman:getSquare():isSomethingTo(potentialEnemy:getSquare()) and spottedScore > 0.32 then
                        bestDist, enemyCharacter, tier = dist, potentialEnemy, "player"
                    end
                end
            end
        end
    end

    -- PRIORITY 3: HITMANS FROM OTHER CLANS AND BANDITS NPCS
    -- Plain zombies are never picked here: hitmen hunt players and only kill the
    -- zombies that come for them (priority 1). The loop also counts nearby
    -- enemies/friendlies for the backward swing and the B42 backpedal.
    local scanTargets = not enemyCharacter and not isTrooper
    local cache, potentialEnemyList = HitmanZombie.Cache, HitmanZombie.CacheLight
    for id, light in pairs(potentialEnemyList) do

        -- quick manhattan check for performance boost
        -- once a target is locked only the counting radius (escapeDist) matters
        local mdist = math.abs(light.x - zx) + math.abs(light.y - zy)
        if mdist < 57 and (scanTargets or mdist < 8) then

            if HitmanUtils.AreEnemies(light.brain, brain) then

                -- PERF: reject by cached distance before the costly CanSee / light checks.
                -- A candidate only matters if it can beat bestDist or counts toward
                -- escape (escapeDist). +1 tile margin covers cache staleness (rebuilt every 4 ticks).
                -- plain zombies are never candidates, so they only need the counting radius
                local candidate = scanTargets and (light.brain or (cache[id] and cache[id]:getVariableBoolean("Bandit")))
                local ldx, ldy = light.x - zx, light.y - zy
                local limit = ((candidate and bestDist > escapeDist) and bestDist or escapeDist) + 1
                local inRange = (ldx * ldx) + (ldy * ldy) < limit * limit

                -- load real instance here
                local potentialEnemy = inRange and cache[id] or nil
                if potentialEnemy and potentialEnemy:isAlive() and hitman:CanSee(potentialEnemy) then
                    local pesq = potentialEnemy:getSquare()
                    if pesq and pesq:getLightLevel(0) > 0.31 and not hitman:getSquare():isSomethingTo(pesq) then
                        local px, py, pz = potentialEnemy:getX(), potentialEnemy:getY(), potentialEnemy:getZ()
                        local dist = math.sqrt(((zx - px) * (zx - px)) + ((zy - py) * (zy - py)))
                        if dist < escapeDist then
                            local rad = math.rad(potentialEnemy:getDirectionAngle())
                            sx = sx + math.cos(rad)
                            sy = sy + math.sin(rad)
                            enemies = enemies + 1
                            if dist < bwdDist then
                                enemiesBwd = enemiesBwd + 1
                            end
                        end
                        if candidate and dist < bestDist then
                            bestDist, enemyCharacter, tier = dist, potentialEnemy, "npc"
                        end
                    end
                end
            else
                local distSq = ((zx - light.x) * (zx - light.x)) + ((zy - light.y) * (zy - light.y))
                if distSq < 27.04 then
                    friendlies = friendlies + 1
                    if distSq < 5.76 then
                        friendliesBwd = friendliesBwd + 1
                    end
                end
            end
        end
    end

    LogTarget(brain, tier, enemyCharacter, bestDist, gunSlot)

    -- DECIDE THE ACTION AGAINST THE CHOSEN TARGET, only one flag can be true
    if enemyCharacter then
        local isPlayer = instanceof(enemyCharacter, "IsoPlayer")
        local sameFloor = math.abs(zz - enemyCharacter:getZ()) < 0.5
        local asn = enemyCharacter:getActionStateName()

        if gunSlot then
            -- RANGED MODE: guns only until every round is spent
            local gunName = weapons[gunSlot].name
            if not hitman:isPrimaryEquipped(gunName) then
                Hitman.Say(hitman, "SPOTTED")
                switch = true
                switchTo = gunName
            else
                local lastShove = gunShoveTime[brain.id] or 0
                local shoveReady = getTimestampMs() - lastShove > GUN_SHOVE_COOLDOWN
                -- a shot that is already lined up is not thrown away for a shove
                if sameFloor and bestDist < GUN_SHOVE_DIST and shoveReady and CanBeShoved(enemyCharacter)
                   and not HitmanBrain.HasTaskType(brain, "Shoot") then
                    shove = true
                else
                    local maxRangeGun = GetRangedRangeCached(gunName, brain)
                    -- troopers skip IsShotClear: their rounds cannot hurt players or
                    -- friendly hitmen (ZAShoot hit() filters both), and the escort
                    -- stands right next to the most urgent targets, so the 5x5
                    -- friendly check would veto exactly the shots that matter
                    if bestDist < maxRangeGun and (isTrooper or IsShotClear(hitman, enemyCharacter)) then
                        firing = true
                        fireSlot = gunSlot
                    end
                end
            end

        elseif weapons.melee and sameFloor and (isPlayer or asn ~= "falldown") then
            -- MELEE MODE: no ammo left in any gun
            local dist = bestDist
            if dist <= (isPlayer and meleeDistPlayer or meleeDist) then
                if hitman:isPrimaryEquipped(weapons.melee) then
                    local maxRangeMelee = GetMeleeRangeCached(weapons.melee)
                    local prone = enemyCharacter:isProne()
                    local fix = 0
                    if not isPlayer then
                        fix = prone and -0.2 or 0.1
                    end

                    if dist <= maxRangeMelee + fix then
                        if isPlayer then
                            shove = dist < 0.5 and not prone and asn ~= "onground" and asn ~= "sitonground" and asn ~= "climbfence" and asn ~= "bumped"
                        else
                            shove = dist < 0.5 and not prone and asn ~= "onground" and asn ~= "climbfence" and asn ~= "bumped" and asn ~= "getup" and asn ~= "falldown"
                        end
                        shove = shove and not Hitman.HasExpertise(hitman, Hitman.Expertise.Knifemaster)
                        combat = not shove
                    end
                else
                    switch = true
                    switchTo = weapons.melee
                end
            end
        end
    end

    -- airborne trooper out of ammo: tell ZPAirborne where to run (melee reach)
    if isTrooper then
        if enemyCharacter and not gunSlot and not (combat or shove or switch) then
            brain.abChase = { x = enemyCharacter:getX(), y = enemyCharacter:getY(),
                              z = enemyCharacter:getZ(), t = getTimestampMs() }
        else
            brain.abChase = nil
        end
    end

    if shove then
        if not HitmanBrain.HasTaskType(brain, "Push") then
            Hitman.ClearTasks(hitman)
            local veh = enemyCharacter:getVehicle()
            if veh then Hitman.Say(hitman, "CAR") end

            if hitman:isFacingObject(enemyCharacter, 0.5) then
                local eid = HitmanUtils.GetCharacterID(enemyCharacter)
                local task = {action="Push", anim="Shove", sound="AttackShove", time=60, endurance=-0.05, eid=eid, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ()}
                table.insert(tasks, task)
                if gunSlot then
                    gunShoveTime[brain.id] = getTimestampMs()
                    print(string.format("[PongDu][Hitman] id=%s gun shove eid=%s dist=%.2f", tostring(brain.id), tostring(eid), bestDist))
                end
            else
                hitman:faceThisObject(enemyCharacter)
            end
        end

    elseif switch then
        if not HitmanBrain.HasActionTask(brain) then
            Hitman.ClearTasks(hitman)
            local stasks = HitmanPrograms.Weapon.Switch(hitman, switchTo)
            for _, t in pairs(stasks) do table.insert(tasks, t) end
        end

    elseif combat then
        if not HitmanBrain.HasTaskTypes(brain, {"Smack", "Push", "Equip", "Unequip"}) then
            Hitman.ClearTasks(hitman)
            local veh = enemyCharacter:getVehicle()
            if veh then Hitman.Say(hitman, "CAR") end

            if hitman:isFacingObject(enemyCharacter, 0.5) then
                local shouldHitMoving = false
                if enemiesBwd >= friendliesBwd + 1 then
                    shouldHitMoving = true
                end
                local eid = HitmanUtils.GetCharacterID(enemyCharacter)
                local task = {action="Smack", time=65, endurance=-0.03, shm=shouldHitMoving, weapon=weapons.melee, eid=eid, x=enemyCharacter:getX(), y=enemyCharacter:getY(), z=enemyCharacter:getZ()}
                table.insert(tasks, task)
            else
                hitman:faceThisObject(enemyCharacter)
            end


        elseif instanceof(enemyCharacter, "IsoPlayer") and not Hitman.HasActionTask(hitman) then
            local task = {action="Time", anim="Smoke", time=250}
            table.insert(tasks, task)
            Hitman.Say(hitman, "DEATH")
        end

    elseif HitmanCompatibility.GetGameVersion() >= 42 and enemiesBwd >= 2 then
        if not Hitman.HasMoveTask(hitman) and not Hitman.HasTaskType(hitman, "Push") and not Hitman.HasTaskType(hitman, "Hit") then
            Hitman.ClearTasks(hitman)
            -- hitman:addLineChatElement("Slow", 0.8, 0.8, 0.1)
            local mrad = math.atan2(sy, sx)
            local mdeg = math.deg(mrad)
            local l = 1
            local nbx = zx + (l * math.cos(mrad))
            local nby = zy + (l * math.sin(mrad))
            local nbz = zz
            local task = HitmanUtils.GetMoveTask(0.01, nbx, nby, nbz, "WalkBwdAim", l, false)
            task.backwards = true
            task.lock = false
            table.insert(tasks, task)
        end

    elseif firing then
        -- a zombie that came for the hitman overrides a shot lined up on someone else
        local eid = HitmanUtils.GetCharacterID(enemyCharacter)
        -- troopers drop a shot lined up on another target at once: their target
        -- only changes when it died or a clearly closer/more urgent enemy showed up
        -- (the rest of a burst would otherwise go into a corpse)
        if tier == "threat" or isTrooper then
            local cur = Hitman.GetTask(hitman)
            if cur and (cur.action == "Aim" or cur.action == "Shoot") and cur.eid ~= eid then
                Hitman.ClearTasks(hitman)
                if not isTrooper then
                    print("[PongDu][Hitman] id=" .. tostring(brain.id) .. " threat preempts shot, eid=" .. tostring(eid))
                end
            end
        end

        -- Push: a gun shove in progress must land before the follow-up shot is planned
        if not HitmanBrain.HasTaskTypes(brain, {"Shoot", "Aim", "Rack", "Equip", "Unequip", "Load", "Unload", "Push"}) then

            Hitman.ClearTasks(hitman)
            if enemyCharacter:isAlive() then

                local veh = enemyCharacter:getVehicle()
                if veh then Hitman.Say(hitman, "CAR") end

                local facing = hitman:isFacingObject(enemyCharacter, 0.1)
                if not facing and isTrooper then
                    -- faceThisObject turns instantly: no idle frame on a retarget
                    hitman:faceThisObject(enemyCharacter)
                    facing = true
                end
                if facing then
                    local weapon = weapons[fireSlot]
                    if weapon.bulletsLeft > 0 then
                        if not weapon.racked then
                            local stasks = HitmanPrograms.Weapon.Rack(hitman, fireSlot)
                            for _, t in pairs(stasks) do table.insert(tasks, t) end

                        elseif not Hitman.IsAim(hitman) then
                            local aimTime = isTrooper and PongDuAirborne.AIM_TICKS or nil
                            local stasks = HitmanPrograms.Weapon.Aim(hitman, enemyCharacter, fireSlot, aimTime)
                            for _, t in pairs(stasks) do table.insert(tasks, t) end

                        else
                            local fire = isTrooper and PongDuAirborne.FirePlan(bestDist) or nil
                            local stasks = HitmanPrograms.Weapon.Shoot(hitman, enemyCharacter, fireSlot, fire)
                            for _, t in pairs(stasks) do table.insert(tasks, t) end
                        end

                    else
                        -- loaded rounds are spent, reserve is left (GetGunSlot guarantees it)
                        Hitman.Say(hitman, "RELOADING")

                        local stasks = HitmanPrograms.Weapon.Reload(hitman, fireSlot)
                        for _, t in pairs(stasks) do table.insert(tasks, t) end
                    end
                else
                    hitman:faceThisObject(enemyCharacter)
                end

            elseif instanceof(enemyCharacter, "IsoPlayer") then
                local task = {action="Time", anim="Smoke", time=250}
                table.insert(tasks, task)
                Hitman.Say(hitman, "DEATH")
            end

        end
    elseif reload then
        if not HitmanBrain.HasActionTask(brain) then
            for _, slot in pairs({"primary", "secondary"}) do
                if weapons[slot].name and hitman:isPrimaryEquipped(weapons[slot].name) then
                    Hitman.ClearTasks(hitman)
                    Hitman.Say(hitman, "RELOADING")
                    local stasks = HitmanPrograms.Weapon.Reload(hitman, slot)
                    for _, t in pairs(stasks) do table.insert(tasks, t) end
                end
            end
        end
    elseif resupply then
        if not HitmanBrain.HasTask(brain) then
            local stasks = HitmanPrograms.Weapon.Resupply(hitman)
            for _, t in pairs(stasks) do table.insert(tasks, t) end
        end
    end

    return tasks
end

-- manages multiplayer social distance hack
local function ManageSocialDistance(hitman)
    local bx, by, bz = hitman:getX(), hitman:getY(), hitman:getZ()
    local brain = HitmanBrain.Get(hitman)
    
    if brain.program.name ~= "Companion" then return end

    local playerList = HitmanPlayer.GetPlayers()

    -- Iterate through players
    for i = 0, playerList:size() - 1 do
        local player = playerList:get(i)
        if player then
            -- Cache player's position and vehicle status
            local px, py, pz = player:getX(), player:getY(), player:getZ()
            local veh = player:getVehicle()
            local asn = hitman:getActionStateName()
            
            -- Calculate distance only once and check if conditions are met
            -- local dist = HitmanUtils.DistToManhattan(bx, by, px, py)
            local dist = math.sqrt(((bx - px) * (bx - px)) + ((by - py) * (by - py)))
            if bz == pz and dist < 3 and not veh and asn ~= "onground" then
                -- Cache closest zombie and hitman locations
                local closestZombie = HitmanUtils.GetClosestZombieLocation(player)
                local closestHitman = HitmanUtils.GetClosestHitmanLocation(player)

                -- If both distances are greater than 10, switch to "CompanionGuard" program
                if closestZombie.dist > 10 and closestHitman.dist > 10 then
                    if Hitman.GetProgram(hitman).name ~= "CompanionGuard" then
                        Hitman.SetProgram(hitman, "CompanionGuard", {})
                    end
                end
            end
        end
    end
end

-- table of hitmans being attacked by zombies
local biteTab = {}

-- manages zombie behavior towards hitmans
local function UpdateZombies(zombie)

    zombie:setVariable("NoLungeAttack", true)
    
    if zombie:getVariableBoolean("Hitman") then return end

    local asn = zombie:getActionStateName()
    local zid = zombie:getModData().hitmanZid
    if zid and biteTab[zid] and zombie:getBumpType() == "Bite" and asn == "bumped" then
        local tick = biteTab[zid].tick
        if tick == 9 then
            local hitman = biteTab[zid].hitman
            local dist = HitmanUtils.DistTo(zombie:getX(), zombie:getY(), hitman:getX(), hitman:getY())
            if dist < 0.8 then 
                if ZombRand(4) == 1 then
                    zombie:playSound("ZombieBite")
                else
                    zombie:playSound("ZombieScratch")
                end

                local teeth = HitmanCompatibility.InstanceItem("Base.RollingPin")
                HitmanCompatibility.Splash(hitman, teeth, zombie)
                hitman:setHitFromBehind(zombie:isBehind(hitman))
        
                if instanceof(hitman, "IsoZombie") then
                    hitman:setHitAngle(zombie:getForwardDirection())
                    hitman:setPlayerAttackPosition(hitman:testDotSide(zombie))
                end
        
                if not hitman:isOnKillDone() then
                    Hitman.ClearTasks(hitman)
                    -- hitman:setBumpDone(true)
                    hitman:Hit(teeth, zombie, 1.01, false, 1, false)
                    Hitman.UpdateInfection(hitman, 0.001)

                    local h = hitman:getHealth()
                    local id = HitmanUtils.GetCharacterID(hitman)
                    local args = {id=id, h=h}
                    sendClientCommand(getSpecificPlayer(0), 'Hitman_Sync', 'Health', args)
                end
            end
        elseif tick >= 16 then
            biteTab[zid] = nil
            zombie:getModData().hitmanZid = nil
            return
        end
        biteTab[zid].tick = tick + 1
        return
    end

    if asn == "bumped" or asn == "onground" or asn == "climbfence" or asn == "getup" then
        return
    end
    if zombie:isProne() then return end

    -- Recycle brain and handle useless state
    HitmanBrain.Remove(zombie)
    if zombie:isUseless() then
        zombie:setUseless(false)
    end

    -- Handle primary and secondary hand items
    local phi = zombie:getPrimaryHandItem()
    if phi then zombie:setPrimaryHandItem(nil) end
    local shi = zombie:getSecondaryHandItem()
    if shi then zombie:setSecondaryHandItem(nil) end

    -- Handle zombie target and teeth state
    local target = zombie:getTarget()
    if target and instanceof(target, "IsoZombie") then
        zombie:setVariable("ZombieBiteDone", true)
        zombie:setNoTeeth(true)
    else
        zombie:setNoTeeth(false)
    end

    -- Clear invalid target
    --[[
    if target and (not target:isAlive() or not zombie:CanSee(target)) then
        zombie:setTarget(nil)
    end]]

    -- Stop sound if playing
    --[[
    local emitter = zombie:getEmitter()
    if emitter:isPlaying("ChainsawIdle") then
        emitter:stopSoundByName("ChainsawIdle")
    end]]

    -- Fetch zombie coordinates and closest hitman location
    local zx, zy, zz = zombie:getX(), zombie:getY(), zombie:getZ()

    -- PERF (ported from Bandits B42): inline nearest-hitman search.
    -- GetClosestHitmanLocation allocated a result table per zombie per call
    -- and compared real distances; this uses squared distances and no table.
    local selfId = HitmanUtils.GetZombieID(zombie)
    local enemyId
    local enemyDistSq = 900 -- 30 tiles, same radius as before
    for hid, h in pairs(HitmanZombie.CacheLightB) do
        if hid ~= selfId then
            local dx, dy = h.x - zx, h.y - zy
            local dsq = (dx * dx) + (dy * dy)
            if dsq < enemyDistSq then
                enemyDistSq, enemyId = dsq, hid
            end
        end
    end

    local hitman = enemyId and HitmanZombie.Cache[enemyId]

    -- If hitman is in range, proceed
    if hitman then
        --local player = HitmanUtils.GetClosestPlayerLocation(zombie, true)

        -- Skip if player is closer than the hitman
        --if player.dist < enemy.dist then return end

        local bx, by, bz = hitman:getX(), hitman:getY(), hitman:getZ()
        local dist = math.sqrt(((bx - zx) * (bx - zx)) + ((by - zy) * (by - zy)))

        -- Standard movement if hitman is far
        if dist > 3 then
            -- zombie:addLineChatElement(tostring(ZombRand(100)) .. " far", 0.6, 0.6, 1)

            -- PERF/MP: pathToCharacter() cancels the zombie's pending PolygonalMap2
            -- request and queues a new one (PathFindBehavior2.setData). Issuing it
            -- every other frame for every nearby zombie flooded the path queue and
            -- starved the hitman's own requests (hitman has no target -> lowest queue).
            -- 1) only the owning client paths the zombie; on other clients the
            --    result is overwritten by the owner's sync anyway.
            --    isRemoteZombie() is authOwner == nil, also true in SP -> isClient() guard.
            -- 2) owner re-evaluates at most every REPATH_INTERVAL_FRAMES per zombie.
            if isClient() and zombie:isRemoteZombie() then
                perfStats.remoteSkipped = perfStats.remoteSkipped + 1
            else
                local nextFrame = repathTab[selfId]
                if nextFrame and nextFrame > frameNo then
                    perfStats.repathThrottled = perfStats.repathThrottled + 1
                else
                    repathTab[selfId] = frameNo + REPATH_INTERVAL_FRAMES
                    if zombie:CanSee(hitman) then
                        zombie:pathToCharacter(hitman)
                        perfStats.repath = perfStats.repath + 1
                    end
                end
            end

        -- Approach hitman if in range
        else
            -- zombie:addLineChatElement(string.format("mid %.2f", enemy.dist), 0.6, 0.6, 1)
            local player = getSpecificPlayer(0)
            -- local tempTarget = HitmanUtils.CloneIsoPlayer(hitman)
            -- if zombie:CanSee(hitman) and zombie:CanSee(player) then
                -- if HitmanCompatibility.GetGameVersion() >= 42 then
                    -- zombie:pathToCharacter(hitman)
                -- end
                -- if not zombie:getTarget() then
                    -- zombie:addLineChatElement(string.format("SPOTTED %.2f", enemy.dist), 0.6, 0.6, 1)
                    -- zombie:changeState(LungeState.instance())
                    -- zombie:getPathFindBehavior2():cancel()
                    -- zombie:setPath2(nil)
                    zombie:spotted(player, true)
                    zombie:setTarget(hitman)
                    zombie:setAttackedBy(hitman)
                    
                    
                    --tempTarget:removeFromWorld()
                    -- tempTarget = nil

                -- end
            -- end
            if dist < 0.80 and math.abs(zz - bz) < 0.3 then
                
                local isWallTo = zombie:getSquare():isSomethingTo(hitman:getSquare())
                if not isWallTo then


                    if zombie:isFacingObject(hitman, 0.3) then
                        -- Optimized close-range attack logic
                        local attackingZombiesNumber = 0
                        for id, attackingZombie in pairs(HitmanZombie.CacheLightZ) do
                            -- local distManhattan = HitmanUtils.DistToManhattan(attackingZombie.x, attackingZombie.y, enemy.x, enemy.y)
                            if math.abs(attackingZombie.x - bx) + math.abs(attackingZombie.y - by) < 1 then
                                -- local dist = HitmanUtils.DistTo(attackingZombie.x, attackingZombie.y, enemy.x, enemy.y)
                                local dist = math.sqrt(((attackingZombie.x - bx) * (attackingZombie.x - bx)) + ((attackingZombie.y - by) * (attackingZombie.y - by)))
                                if dist < 0.6 then
                                    attackingZombiesNumber = attackingZombiesNumber + 1
                                    if attackingZombiesNumber > 2 then break end
                                end
                            end
                        end

                        -- If more than 2 zombies attacking, initiate death task
                        if attackingZombiesNumber > 2 then
                            if not Hitman.HasTaskType(hitman, "Die") then
                                Hitman.ClearTasks(hitman)
                                local task = {action="Die", lock=true, anim="Die", time=300}
                                Hitman.AddTask(hitman, task)
                            end
                            return
                        end

                        if zombie:getBumpType() ~= "Bite" and asn ~= "staggerback" then
                            -- prevents zombie into entering real attack state (we want simulate out own attack)
                            -- zombie:setVariable("bAttack", false)
                            hitman:setZombiesDontAttack(true)
                            zombie:setBumpType("Bite")
                            local zid = HitmanUtils.GetCharacterID(zombie)
                            zombie:getModData().hitmanZid = zid 
                            biteTab[zid] = {hitman=hitman, tick=0}
                            -- zombie:addLineChatElement("BITE", 0.8, 0.8, 0.1)
                        end
                    else
                        zombie:faceThisObject(hitman)
                    end
                end
            end
        end
    end
end


local function ProcessTask(hitman, task)

    if not task.action then return end
    if not task.state then task.state = "NEW" end

    if task.state == "NEW" then
        if not task.time then task.time = 1000 end
        -- hitman:addLineChatElement(task.action, 0.8, 0.8, 0.1)
        if task.action ~= "Shoot" and task.action ~= "Aim" and task.action ~= "Rack"  and task.action ~= "Load" then
            Hitman.SetAim(hitman, false)
        end

        if task.action ~= "Move" and task.action ~= "GoTo" then
            hitman:getPathFindBehavior2():cancel()
            hitman:setPath2(nil)
            if Hitman.IsMoving(hitman) then
                Hitman.SetMoving(hitman, false)
            end
        end

        if task.sound then
            local play = true
            if task.soundDistMax then
                local player = getSpecificPlayer(0)
                local dist = HitmanUtils.DistTo(hitman:getX(), hitman:getY(), player:getX(), player:getY())
                if dist > task.soundDistMax then
                    play = false
                end
            end

            if play then
                local emitter = hitman:getEmitter()
                if not emitter:isPlaying(task.sound) then
                    emitter:playSound(task.sound)
                end
            end
            -- hitman:playSound(task.sound)
        end

        if task.anim then
            hitman:setBumpType(task.anim)
        end

        local done = HitmanZombieActions[task.action].onStart(hitman, task)

        if done then 
            task.state = "WORKING"
            --Hitman.UpdateTask(hitman, task)
        end

    elseif task.state == "WORKING" then

        -- normalize time speed
        local decrement = 1 / ((getAverageFPS() + 0.5) * 0.01666667)
        if task.action == "Smack" and Hitman.HasExpertise(hitman, Hitman.Expertise.Knifemaster) then
            decrement = decrement * Hitman.KnifemasterSpeedMult
        end
        task.time = task.time - decrement

        local done = HitmanZombieActions[task.action].onWorking(hitman, task)
        if done or task.time <= 0 then 
            task.state = "COMPLETED"
        end
        -- Hitman.UpdateTask(hitman, task)

    elseif task.state == "COMPLETED" then

        if task.sound then
            local emitter = hitman:getEmitter()
            if not emitter:isPlaying(task.sound) then
                hitman:playSound(task.sound)
            end
        end
        
        if task.endurance then
            Hitman.UpdateEndurance(hitman, task.endurance)
        end

        local done = HitmanZombieActions[task.action].onComplete(hitman, task)

        if done then 
            Hitman.RemoveTask(hitman)
        end
    end
end

local function GenerateTask(hitman)

    local tasks = {}
    
    -- MANAGE HITMAN ENDURANCE LOSS
    local enduranceTasks = ManageEndurance(hitman)
    if #enduranceTasks > 0 then
        for _, t in pairs(enduranceTasks) do table.insert(tasks, t) end
    end
    
    -- MANAGE BLEEDING AND HEALING
    if #tasks == 0 then
        local healingTasks = ManageHealth(hitman)
        if #healingTasks > 0 then
            for _, t in pairs(healingTasks) do table.insert(tasks, t) end
        end
    end

    -- MANAGE MELEE / SHOOTING TASKS
    if #tasks == 0  then
        local combatTasks = ManageCombat(hitman)
        if #combatTasks > 0 then
            for _, t in pairs(combatTasks) do table.insert(tasks, t) end
        end
    end

    -- MANAGE COLLISION TASKS
    -- (the old "uTick % 2" gate was always truthy in Lua, so collisions were
    -- effectively checked every update; ManageCollisions exits early unless
    -- isCollidedThisFrame(), so keep that behaviour and drop the dead gate)
    if #tasks == 0 then
        local colissionTasks = ManageCollisions(hitman)
        if #colissionTasks > 0 then
            for _, t in pairs(colissionTasks) do table.insert(tasks, t) end
        end
    end
    
    -- CUSTOM PROGRAM 
    if #tasks == 0 and not Hitman.HasTask(hitman) then
        local program = Hitman.GetProgram(hitman)
        if program and program.name and program.stage  then
            -- local ts = getTimestampMs()
            local res = HitmanZombiePrograms[program.name][program.stage](hitman)
            -- print ("AT: " .. program.name .. "." .. program.stage .. " " .. (getTimestampMs() - ts))
            if res.status and res.next then
                Hitman.SetProgramStage(hitman, res.next)
                for _, task in pairs(res.tasks) do
                    table.insert(tasks, task)
                end
            else
                local task = {action="Time", anim="Shrug", time=200}
                table.insert(tasks, task)
            end
        end
    end

    if #tasks > 0 then
        local brain = HitmanBrain.Get(hitman)
        for _, task in pairs(tasks) do
            table.insert(brain.tasks, task)
        end
        -- HitmanBrain.Update(zombie, brain)
    end
end

-- main function to handle hitmans
local function OnHitmanUpdate(zombie)

    local ts = getTimestampMs()
    
    if isServer() then return end

    if not Hitman.Engine then return end

    if HitmanCompatibility.IsReanimatedForGrappleOnly(zombie) then return end

    -- COMPAT: never touch NPCs owned by the Bandits mod. Prevents the two mods
    -- from stealing/overwriting each other's zombies via the shared outfit-id queue.
    if zombie:getVariableBoolean("Bandit") then return end

    local id = HitmanUtils.GetZombieID(zombie)
    local zx = zombie:getX()
    local zy = zombie:getY()
    local zz = zombie:getZ()

    -- local cell = getCell()
    -- local world = getWorld()
    -- local gamemode = world:getGameMode()
    local brain = HitmanBrain.Get(zombie)
    
    -- HITMANIZE ZOMBIES SPAWNED AND ENQUEUED BY SERVER
    -- OR ZOMBIFY IF QUEUE HAS BEEN REMOVED
    local gmd = GetHitmanModData()
    if gmd.Queue then
        if gmd.Queue[id] and id ~= 0 then
            if not zombie:getVariableBoolean("Hitman") and not zombie:getVariableBoolean("Bandit") then
                brain = gmd.Queue[id]
                Hitmanize(zombie, brain)
            end
        else
            if zombie:getVariableBoolean("Hitman") then
                Zombify(zombie)
            end
        end
    end
    
    -- if true then return end 
    -- ZOMBIES VS HITMANS
    -- Using adaptive performance here.
    -- The more zombies in player's cell, the less frequent updates.
    -- Up to 100 zombies, update every tick, 
    -- 800+ zombies, update every 1/16 tick. 
    -- local zcnt = HitmanZombie.GetAllCnt()
    -- if zcnt > 600 then zcnt = 600 end
    -- local skip = math.floor(zcnt / 50) + 1
    -- every 2nd frame per zombie, staggered by id so the load is spread
    -- over both frames instead of all zombies landing on the same one
    if (frameNo + id) % 2 == 0 then
        -- print (skip)
        UpdateZombies(zombie)
    end

    local asn = zombie:getActionStateName()
    if asn == "onground" then
        local h = zombie:getHealth()
        if h <=0 then
            zombie:setAttackedBy(getCell():getFakeZombieForHit())
            zombie:becomeCorpse()
        end
    end

    ------------------------------------------------------------------------------------------------------------------------------------
    -- HITMAN UPDATE AFTER THIS LINE
    ------------------------------------------------------------------------------------------------------------------------------------
    if not zombie:getVariableBoolean("Hitman") then return end
    if not brain then return end
    
    -- distant hitmans are not updated by this mod so they need to be set useless
    -- to prevent game updating them as if they were zombies
    if HitmanZombie.CacheLightB[id] then 
        zombie:setUseless(false)
    else
        zombie:setUseless(true)
        return
    end
    
    local hitman = zombie

    if HitmanCompatibility.GetGameVersion() >= 42 then
        hitman:setAnimatingBackwards(false)
    end

    -- IF TELEPORTING THEN THERE IS NO SENSE IN PROCEEDING
    if hitman:isTeleporting() then
        return
    end

    -- WALKTYPE
    -- we do it this way, if walktype get overwritten by game engine we force our animations
    hitman:setWalkType(hitman:getVariableString("HitmanWalkType"))
    hitman:setSpeedMod(1)

    -- NO ZOMBIE SOUNDS
    Hitman.SurpressZombieSounds(hitman)

    -- COMPAT: the Bandits mod's zombie loop treats hitmen as ordinary zombies
    -- (they have no "Bandit" variable), stripping hand items and re-enabling
    -- teeth every tick (every 2nd tick once a bandit exists). Re-assert our
    -- state each tick, same philosophy as the WALKTYPE force above.
    hitman:setNoTeeth(true)
    if not HitmanBrain.HasTaskTypes(brain, {"Equip", "Unequip"}) then
        local expPrimary = hitman:getVariableString("HitmanPrimary")
        if expPrimary and expPrimary ~= "" and not hitman:getPrimaryHandItem() then
            Hitman.SetHands(hitman, expPrimary)
        end
        local expSecondary = hitman:getVariableString("HitmanSecondary")
        if expSecondary and expSecondary ~= "" and not hitman:getSecondaryHandItem() then
            local secondaryItem = HitmanCompatibility.InstanceItem(expSecondary)
            if secondaryItem then hitman:setSecondaryHandItem(secondaryItem) end
        end
    end

    -- CANNIBALS
    if not brain.eatBody then
        hitman:setEatBodyTarget(nil, false)
    end
    
    -- ADJUST HUMAN VISUALS
    ApplyVisuals(hitman, brain)

    -- MANAGE HITMAN TORCH
    --[[
    if uTick == 1 then
        ManageTorch(hitman)
    end]]

    -- MANAGE HITMAN CHAINSAW
    -- ManageChainsaw(hitman)

    -- MANAGE HITMAN BEING ON FIRE
    -- every 16th frame per hitman (the shared uTick only ever hit one hitman)
    if (frameNo + id) % 16 == 0 then
        ManageOnFire(hitman)
    end

    -- MANAGE HITMAN SPEECH COOLDOWN
    ManageSpeechCooldown(brain)

    -- MANAGE HITMAN SOUND COOLDOWN
    ManageSoundCoolDown(brain)

    -- ACTION STATE TWEAKS
    local continue = ManageActionState(hitman)
    if not continue then return end

    -- PONGDU: airborne trooper still descending or playing the landing motion;
    -- features/airborne.lua drives it until it is on its feet
    if PongDuAirborne and PongDuAirborne.HoldsAI(hitman) then return end
    
    -- COMPANION SOCIAL DISTANCE HACK
    ManageSocialDistance(hitman)

    -- CRAWLERS SCREAM OCASSINALLY
    if hitman:isCrawling() then
        Hitman.Say(hitman, "DEAD")
    end
    
    GenerateTask(hitman)

    local task = Hitman.GetTask(hitman)
    if task then
        ProcessTask(hitman, task)
    end

    local elapsed = getTimestampMs() - ts
    perfStats.hitmanUpd = perfStats.hitmanUpd + 1
    perfStats.hitmanMs = perfStats.hitmanMs + elapsed
    if elapsed > perfStats.hitmanMaxMs then perfStats.hitmanMaxMs = elapsed end
end

local function OnHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if not zombie:getVariableBoolean("Hitman") then return end

    -- PONGDU: players cannot hurt airborne troopers (damage is voided by
    -- shared/PongDuAirborneGuard.lua) -- keep the trooper's tasks untouched too
    if instanceof(attacker, "IsoPlayer") and HitmanUtils.IsAirborneTrooper(zombie) then return end

    local hitman = zombie

    Hitman.AddVisualDamage(hitman, handWeapon)
    Hitman.ClearTasks(hitman)
    Hitman.Say(hitman, "HIT", true)
    if Hitman.IsSleeping(hitman) then
        local task = {action="Time", lock=true, anim="GetUp", time=150}
        Hitman.ClearTasks(hitman)
        Hitman.AddTask(hitman, task)
        Hitman.SetSleeping(hitman, false)
        Hitman.SetProgramStage(hitman, "Prepare")
    end

    HitmanPlayer.CheckFriendlyFire(hitman, attacker)
end

local function OnZombieDead(zombie)

    if zombie:getVariableBoolean("Hitman") then 

        local brain = HitmanBrain.Get(zombie)
        if brain then
            ClearCombatState(brain)
            if PongDuAirborne then PongDuAirborne.Forget(brain) end
        end
        local inventory = zombie:getInventory()
        local items = ArrayList.new()

        local veh = zombie:getVehicle()
        if veh then veh:exit(zombie) end

        inventory:getAllEvalRecurse(predicateRemovable, items)
        for i=0, items:size()-1 do
            local item = items:get(i)
            inventory:Remove(item)
            inventory:setDrawDirty(true)
        end

        -- update stuck weapons
        local stuckLocationList = {"MeatCleaver in Back", "Axe Back", "Knife in Back", "Knife Left Leg", "Knife Right Leg", "Knife Shoulder", "Knife Stomach"}
        for _, stuckLocation in pairs(stuckLocationList) do
            local attachedItem = zombie:getAttachedItem(stuckLocation)
            if attachedItem then
                inventory:AddItem(attachedItem)
                inventory:setDrawDirty(true)
            end
        end

        -- drop extra suitcase item 
        if brain and brain.bag then
            if brain.bag == "Briefcase" then
                local bag = HitmanCompatibility.InstanceItem("Base.Briefcase")
                local bagContainer = bag:getItemContainer()
                if bagContainer then
                    local rn = ZombRand(3)
                    if rn == 0 then
                        for i = 1, 1000 do
                            local money = instanceItem("Base.Money")
                            bagContainer:AddItem(money)
                        end
                    elseif rn == 1 then
                        local c1 = HitmanCompatibility.InstanceItem("Base.Corset_Black")
                        local c2 = HitmanCompatibility.InstanceItem("Base.StockingsBlack")
                        local c3 = HitmanCompatibility.InstanceItem("Base.Hat_PeakedCapArmy")
                        bagContainer:AddItem(c1)
                        bagContainer:AddItem(c2)
                        bagContainer:AddItem(c3)
                    elseif rn == 2 then
                        local c1 = HitmanCompatibility.InstanceItem("Base.Machete")
                        bagContainer:AddItem(c1)
                        if HitmanCompatibility.GetGameVersion() >= 42 then
                            local c2 = HitmanCompatibility.InstanceItem("Base.Hat_HalloweenMaskVampire")
                            local c3 = HitmanCompatibility.InstanceItem("Base.BlackRobe")
                            bagContainer:AddItem(c2)
                            bagContainer:AddItem(c3)
                        end
                    end
                    zombie:getSquare():AddWorldInventoryItem(bag, ZombRandFloat(0.2, 0.8), ZombRandFloat(0.2, 0.8), 0)
                end
            end
        end

        -- add key to inv
        if brain and brain.key and ZombRand(3) == 1 then
            local item = HitmanCompatibility.InstanceItem("Base.Key1")
            item:setKeyId(brain.key)
            item:setName("Building Key")
            zombie:getInventory():AddItem(item)
            Hitman.UpdateItemsToSpawnAtDeath(zombie)
        end

        Hitman.Say(zombie, "DEAD", true)

        -- update player kills
        local player = getSpecificPlayer(0)
        local killer = zombie:getAttackedBy()
        if killer then
            if killer == player then
                local args = {}
                args.id = 0
                sendClientCommand(player, 'Hitman_Commands', 'IncrementHitmanKills', args)
                player:setZombieKills(player:getZombieKills() - 1)
            end
        end

        -- warning: bwo overwrites CheckFriendlyFire
        local attacker = zombie:getAttackedBy()
        HitmanPlayer.CheckFriendlyFire(zombie, attacker)

        -- deprovision
        zombie:setUseless(false)
        zombie:setReanim(false)
        zombie:setVariable("Hitman", false)
        zombie:setPrimaryHandItem(nil)
        zombie:clearAttachedItems()
        zombie:resetEquippedHandsModels()

        if brain then
            args = {}
            args.id = brain.id
            sendClientCommand(player, 'Hitman_Commands', 'HitmanRemove', args)
        end
        HitmanBrain.Remove(zombie)
    end

    -- stale corpse removal hack fro b42, it replaces the dying zombie with a deadbody
    -- and copies most of the properties to look as the original 
    if HitmanCompatibility.GetGameVersion() >= 42 then
        local isSeen = false
        local playerList = HitmanPlayer.GetPlayers()
        for i=0, playerList:size()-1 do
            local player = playerList:get(i)
            if player and player:CanSee(zombie) and zombie:getSquare():isCanSee(0) then
                isSeen = true
            end
        end

        if not isSeen then
            local zombie2 = createZombie(zombie:getX(), zombie:getY(), zombie:getZ(), nil, 0, IsoDirections.S)
            
            local hv = zombie:getHumanVisual()
            local hv2 = zombie2:getHumanVisual()
            local inv = zombie:getInventory()
            local arrItems = ArrayList.new()
            inv:getAllEvalRecurse(predicateAll, arrItems)

            zombie2:setFemale(zombie:isFemale())
            hv2:setSkinTextureName(hv:getSkinTexture())
            hv2:setHairModel(hv:getHairModel())
            hv2:setBeardModel(hv:getHairModel())
            hv2:setHairColor(hv:getHairColor()) 
            hv2:setBeardColor(hv:getBeardColor())

            local wornItems = zombie:getWornItems()
            zombie2:setWornItems(wornItems)
            zombie2:setAttachedItems(zombie:getAttachedItems())

            zombie:removeFromWorld()
            zombie:removeFromSquare()

            local body = IsoDeadBody.new(zombie2, false);
            inv2 = body:getContainer()
            for i = 0, wornItems:size() - 1 do
                local wornItem = wornItems:get(i)
                local item = wornItem:getItem()
                inv2:AddItem(item)
            end

            for i = 0, arrItems:size()-1 do
                local item = arrItems:get(i)
                inv2:AddItem(item)
            end
        end
    end

end

-- frame counter + periodic diagnostics line (only while hitmen are loaded)
local function OnHitmanTick()
    frameNo = frameNo + 1
    if frameNo % 60 ~= 0 then return end

    local now = getTimestampMs()
    if now < perfLogAt then return end
    perfLogAt = now + PERF_LOG_INTERVAL_MS

    -- drop throttle entries that already expired (dead / unloaded zombies)
    local fresh = {}
    for zid, f in pairs(repathTab) do
        if f > frameNo then fresh[zid] = f end
    end
    repathTab = fresh

    local hitmen = 0
    for _ in pairs(HitmanZombie.CacheLightB) do hitmen = hitmen + 1 end
    if hitmen > 0 then
        local avg = 0
        if perfStats.hitmanUpd > 0 then
            avg = math.floor(perfStats.hitmanMs * 100 / perfStats.hitmanUpd) / 100
        end
        print("[PongDu][Hitman] perf " .. (PERF_LOG_INTERVAL_MS / 1000) .. "s:"
            .. " zombiesInCell=" .. tostring(HitmanZombie.LastSize)
            .. " hitmen=" .. hitmen
            .. " repathIssued=" .. perfStats.repath
            .. " repathThrottled=" .. perfStats.repathThrottled
            .. " remoteSkipped=" .. perfStats.remoteSkipped
            .. " hitmanUpdates=" .. perfStats.hitmanUpd
            .. " hitmanAvgMs=" .. avg
            .. " hitmanMaxMs=" .. perfStats.hitmanMaxMs)
    end
    ResetPerfStats()
end

Events.OnTick.Add(OnHitmanTick)
Events.OnZombieUpdate.Add(OnHitmanUpdate)
Events.OnHitZombie.Add(OnHitZombie)
Events.OnZombieDead.Add(OnZombieDead)
