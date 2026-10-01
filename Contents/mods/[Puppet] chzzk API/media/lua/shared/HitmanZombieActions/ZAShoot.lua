HitmanZombieActions = HitmanZombieActions or {}

local vehicleParts = {
    [1] = {name="HeadlightLeft", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [2] = {name="HeadlightRight", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [3] = {name="HeadlightRearLeft", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [4] = {name="HeadlightRearRight", dmg=18, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [5] = {name="Windshield", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [6] = {name="WindshieldRear", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [7] = {name="WindowFrontRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [8] = {name="WindowFrontLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [9] = {name="WindowRearRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [10] = {name="WindowRearLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [11] = {name="WindowMiddleLeft", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [12] = {name="WindowMiddleRight", dmg=20, sndHit="BreakGlassItem", sndDest="SmashWindow"},
    [13] = {name="DoorFrontRight", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [14] = {name="DoorFrontLeft", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [15] = {name="DoorRearRight", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [16] = {name="DoorRearLeft", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [17] = {name="EngineDoor", dmg=10, sndHit="HitVehiclePartWithWeapon", sndDest="HitVehiclePartWithWeapon"},
    [18] = {name="TireFrontRight", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [19] = {name="TireFrontLeft", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [20] = {name="TireRearLeft", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"},
    [21] = {name="TireRearRight", dmg=8, sndHit="VehicleTireExplode", sndDest="VehicleTireExplode"}
}

local sounds = {
    ["WoodDoor"] = "HitBarricadePlank",
    ["MetalDoor"] = "HitBarricadeMetal",
}

local function getProjectileCount(reloadType)
    local projectiles = 1
    if reloadType == "shotgun" or reloadType == "doublebarrelshotgun" or reloadType == "doublebarrelshotgunsawn" then
        projectiles = 5
    end
    return projectiles
end

local function getBloodBodyParts()
    local bodyParts = {}
    table.insert(bodyParts, {name=BloodBodyPartType.Foot_R})
    table.insert(bodyParts, {name=BloodBodyPartType.Foot_L})
    table.insert(bodyParts, {name=BloodBodyPartType.LowerLeg_R})
    table.insert(bodyParts, {name=BloodBodyPartType.LowerLeg_L})
    table.insert(bodyParts, {name=BloodBodyPartType.UpperLeg_R})
    table.insert(bodyParts, {name=BloodBodyPartType.UpperLeg_L})
    table.insert(bodyParts, {name=BloodBodyPartType.Groin})
    table.insert(bodyParts, {name=BloodBodyPartType.Neck})
    table.insert(bodyParts, {name=BloodBodyPartType.Head})
    table.insert(bodyParts, {name=BloodBodyPartType.Torso_Lower})
    table.insert(bodyParts, {name=BloodBodyPartType.Torso_Upper})
    table.insert(bodyParts, {name=BloodBodyPartType.UpperArm_R})
    table.insert(bodyParts, {name=BloodBodyPartType.UpperArm_L})
    table.insert(bodyParts, {name=BloodBodyPartType.ForeArm_R})
    table.insert(bodyParts, {name=BloodBodyPartType.ForeArm_L})
    table.insert(bodyParts, {name=BloodBodyPartType.Hand_R})
    table.insert(bodyParts, {name=BloodBodyPartType.Hand_L})
    return bodyParts
end

local function addHole (character)
    local bpi = 1 + HitmanRandom.Get() % 17
    local bodyParts = getBloodBodyParts()
    local bodyPart = bodyParts[bpi]

    local visuals = character:getHumanVisual()
    visuals:setBlood(bodyPart.name, 1)

    local itemVisuals = character:getItemVisuals()
    for i = 0, itemVisuals:size() - 1 do
        local item = itemVisuals:get(i)
        if item then
            item:setBlood(bodyPart.name, 1)
            local clothing = item:getInventoryItem()
            if instanceof(clothing, "Clothing") then
                local coveredPartList = clothing:getCoveredParts()
                for i=0, coveredPartList:size()-1 do
                    local coveredPart = coveredPartList:get(i)
                    if coveredPart == bodyPart.name then
                        item:setHole(bodyPart.name)
                    end
                end
            end
        end
    end
    character:resetModelNextFrame()
    character:resetModel()
end

local function addHolePlayer (player)
    local bpi = 1 + HitmanRandom.Get() % 17
    local bodyParts = getBloodBodyParts()
    local bodyPart = bodyParts[bpi]

    local visuals = player:getHumanVisual()
    visuals:setBlood(bodyPart.name, 1)

    local wornItems = player:getWornItems()
    for i = 0, wornItems:size() - 1 do
        local wornItem = wornItems:get(i)
        local item = wornItem:getItem()
        if item then
            item:setBlood(bodyPart.name, 1)
            if instanceof(item, "Clothing") then
                local coveredPartList = item:getCoveredParts()
                for i=0, coveredPartList:size()-1 do
                    local coveredPart = coveredPartList:get(i)
                    if coveredPart == bodyPart.name then
                        -- item:getVisual():setHole(bodyPart.name)
                    end
                end
            end
        end
    end
    player:resetModelNextFrame()
    player:resetModel()
end

-- ── PONGDU: shot model (penetration + damage vs zombies) ─────────────────
-- A hitman round on a zombie (plain zombie or enemy hitman) is resolved like a
-- player firing the same HandWeapon. The hitman counts as a player with Aiming 0,
-- no traits/moodles/pain, standing still and holding the gun in both hands.
--
-- Mode is picked per round:
--   * Improved Projectile active (mod + SandboxVars.ImprovedProjectile):
--       penetration = IPPJ "Penetration" page, damage = IPPJ "Main" page
--   * otherwise: script MaxHitCount + vanilla/Arsenal firearm damage (B41 Java)
--
-- Vanilla (SwipeStatePlayer.java / IsoGameCharacter.processHitDamage / Hit):
--   d  = Min + Rand(int((Max-Min)*1000))/1000, rolled per target
--   d /= hitIdx/2                      (1st target x2, 2nd x1, 3rd x0.67 ...)
--   d *= |1 - def/100|                 def = clothing(part, scratch)/2 + clothing(part, bite), bullet, max 70
--   Hit(): d *= modDelta (2 if RangeFalloff else 1), x1.5 if the victim is not
--          facing the shooter (IsoPlayer wielder only), x1.5 non-player victim,
--          x0.3 weapon level 0, crit x max(2, CritDmgMultiplier), hitTime ramp,
--          Health -= d * 0.7 (aimed firearm)
--   crit%  = CriticalChance + (dist<4 ? (4-dist)*7 : -(dist-4)*7) - shootInARow*10 (Auto)
--            +-6 Lore.Toughness, clamp 10..90; damage roll adds +5 from behind
--            (+30 if the zombie has no target), knockdown re-rolls without it
--   targets per round = script MaxHitCount (a missed target still takes a slot)
--
-- Improved Projectile (ImprovedProjectile_01_main.lua / _02_init.lua):
--   d  = (Min + rand*(Max-Min)), sqrt adjust if IPPJDamageAdjustment, x IPPJDamageMult, min 0.1
--   d *= 1 - IPPJDmgReduction% * dist/range        (range = MaxRange x IPPJRangeMult)
--   zone by IPPJHitBox*Ratio share -> x IPPJHitBox*Mult, crit (CriticalChance%) x1.8
--   Health -= d; each hit: hits left - 1, d *= 1 - IPPJDmgReductionOnPnt
--   hits per round = IPPJPenetrationSetting (1 script MaxHitCount, 2 per-ammo/CustomGun, 3 one),
--   IPPJPntOnKill stops the round on a survivor. Only real hits take a slot.
--   The hitbox zone is aimed geometry in IPPJ; here it is rolled from the ratios.
--
-- Shotguns keep the old pellet logic for how many bodies a shell reaches; each
-- body still takes the damage above. Accuracy (calculateHitChance) is unchanged.
-- All rolls use HitmanRandom so every client resolves the same round.

local function rand01()
    return (HitmanRandom.Get() % 10000) / 10000
end

local function rollPct()
    return HitmanRandom.Get() % 100
end

-- the mod list does not change in a session: resolved on the first round
local ippjActive = nil
local function ippjOn()
    if ippjActive == nil then
        ippjActive = SandboxVars.ImprovedProjectile ~= nil and getActivatedMods():contains("ImprovedProjectile")
        print("[HITMANS] shot model: " .. (ippjActive and "Improved Projectile settings" or "script MaxHitCount + vanilla damage"))
    end
    return ippjActive
end

-- rounds one target slot per round may take (see header)
local maxHitsCache = {}   -- [fullType .. mode] = n
local function maxHitsOf(weaponItem, ippj)
    local ft = weaponItem:getFullType()
    local key = ft .. (ippj and "|ippj" or "|van")
    local n = maxHitsCache[key]
    if n then return n end

    local script = ScriptManager.instance:getItem(ft)
    n = script and script:getMaxHitCount() or weaponItem:getMaxHitCount()
    local src = "script"
    if ippj then
        local sv = SandboxVars.ImprovedProjectile
        if sv.IPPJPenetrationSetting == 2 then
            local ammo = weaponItem:getAmmoType()
            if ammo then
                local opt = getSandboxOptions():getOptionByName("ImprovedProjectile.IPPJ" .. string.sub(ammo, 6))
                if opt and opt:getValue() ~= 0 then n = opt:getValue(); src = "ammo" end
            end
            for _, v in pairs(luautils.split(sv.IPPJCustomGun, ";")) do
                local kv = luautils.split(v, "=")
                if kv[1] == ft and tonumber(kv[2]) then n = tonumber(kv[2]); src = "custom" end
            end
        elseif sv.IPPJPenetrationSetting == 3 then
            n = 1; src = "single"
        end
    end
    n = math.floor(tonumber(n) or 1)
    if n < 1 then n = 1 end
    maxHitsCache[key] = n
    print(string.format("[HITMANS] shot model %s: maxHits=%d (%s, %s) dmg=%.2f-%.2f crit=%.1f",
        tostring(ft), n, src, ippj and "ippj" or "vanilla",
        weaponItem:getMinDamage(), weaponItem:getMaxDamage(), weaponItem:getCriticalChance()))
    return n
end

-- player.shootInARow: Auto fire mode, next round within 600 ms
local SHOOT_IN_ROW_MS = 600
local rowState = {}       -- [shooter brain id] = { last = ms, n = rounds in a row }
local function noteShot(sid, weaponItem)
    local now = getTimestampMs()
    local st = rowState[sid]
    if not st then st = { last = 0, n = 0 }; rowState[sid] = st end
    if weaponItem:getFireMode() == "Auto" and now - st.last < SHOOT_IN_ROW_MS then
        st.n = st.n + 1
    else
        st.n = 0
    end
    st.last = now
    return st.n
end

-- IsoPlayer.calculateCritChance for a ranged weapon, Aiming 0
local function vanillaCritChance(weaponItem, dist, inRow)
    if weaponItem:isAlwaysKnockdown() then return 100 end
    local c = math.floor(weaponItem:getCriticalChance())
    if dist < 4 then
        c = c + math.floor((4 - dist) * 7)
    else
        c = c - math.floor((dist - 4) * 7)
    end
    if weaponItem:getFireMode() == "Auto" then c = c - inRow * 10 end
    local tough = SandboxVars.Lore.Toughness
    if tough == 1 then c = c - 6 elseif tough == 3 then c = c + 6 end
    if c < 10 then c = 10 end
    if c > 90 then c = 90 end
    return c
end

local HAND_L_IDX, NECK_IDX = nil, nil

-- damageSplit / modDelta for victim:Hit(item, fakeZombie, ...) so the result
-- matches a player wielder; plus the two crit rolls
local function vanillaShot(shooter, weaponItem, victim, dist, hitIdx, inRow)
    local mn, mx = weaponItem:getMinDamage(), weaponItem:getMaxDamage()
    local span = math.floor((mx - mn) * 1000)
    local d = mn
    if span > 0 then d = mn + (HitmanRandom.Get() % span) / 1000 end
    d = d / (hitIdx / 2)

    if not HAND_L_IDX then
        HAND_L_IDX = BodyPartType.ToIndex(BodyPartType.Hand_L)
        NECK_IDX = BodyPartType.ToIndex(BodyPartType.Neck)
    end
    local part = HAND_L_IDX + HitmanRandom.Get() % (NECK_IDX - HAND_L_IDX + 1)
    local def = victim:getBodyPartClothingDefense(part, false, true) / 2 + victim:getBodyPartClothingDefense(part, true, true)
    if def > 70 then def = 70 end
    d = d * math.abs(1 - def / 100)

    -- processHitDamage: x1.5 when the victim does not face the shooter (player wielder only)
    local vx, vy = victim:getX() - shooter:getX(), victim:getY() - shooter:getY()
    local len = math.sqrt(vx * vx + vy * vy)
    if len > 0 then
        local a = math.rad(victim:getDirectionAngle())
        if (vx * math.cos(a) + vy * math.sin(a)) / len > -0.3 then d = d * 1.5 end
    end
    -- processHitDamage halves a two-handed gun the wielder does not hold in both
    -- hands; a player does, the fake zombie wielder does not
    if weaponItem:isTwoHandWeapon() then d = d * 2 end

    local modDelta = weaponItem:isRangeFalloff() and 2 or 1

    local c = vanillaCritChance(weaponItem, dist, inRow)
    local cDmg = c
    if shooter:isBehind(victim) then
        cDmg = cDmg + (victim:getTarget() == nil and 30 or 5)
    end
    local critDmg = rollPct() < cDmg
    local knock = rollPct() < c
    return d, modDelta, critDmg, knock
end

local ippjHighReact    = {"HeadLeft", "HeadRight", "Uppercut"}
local ippjMidReact     = {"ShotBelly", "ShotChestL", "ShotChestR"}
local ippjMidReactCrit = {"ShotBellyStep", "ShotChestStepL", "ShotChestStepR"}
local ippjLowReact     = {"ShotLegL", "ShotLegR"}

-- base damage of one IPPJ round (before falloff / zone / crit / penetration)
local function ippjBaseDamage(weaponItem)
    local sv = SandboxVars.ImprovedProjectile
    local mn, mx = weaponItem:getMinDamage(), weaponItem:getMaxDamage()
    local d = mn + rand01() * (mx - mn)
    if sv.IPPJDamageAdjustment then d = 2.64575 * math.sqrt(d) end
    d = d * sv.IPPJDamageMult
    if d < 0.1 then d = 0.1 + rand01() * 0.1 end
    return d
end

-- one IPPJ hit on a zombie: returns damage, critical, zone ratio
local function ippjShot(weaponItem, base, dist)
    local sv = SandboxVars.ImprovedProjectile
    local d = base
    local red = sv.IPPJDmgReduction * 0.01
    if red > 0 then
        local range = HitmanCompatibility.GetMaxRange(weaponItem) * sv.IPPJRangeMult
        if range > 0 then
            local f = dist / range
            if f > 1 then f = 1 end
            d = d * (1 - red * f)
        end
    end

    local hi, mid, lo = sv.IPPJHitBoxHighRatio, sv.IPPJHitBoxMidRatio, sv.IPPJHitBoxLowRatio
    local total = hi + mid + lo
    local r = rand01() * total
    local zone, mult
    if total > 0 and r < hi then
        zone, mult = 1.0, sv.IPPJHitBoxHighMult
    elseif total <= 0 or r < hi + mid then
        zone, mult = 0.6, sv.IPPJHitBoxMidMult
    else
        zone, mult = 0.2, sv.IPPJHitBoxLowMult
    end
    d = d * mult

    local crit = rollPct() <= weaponItem:getCriticalChance()
    if crit then d = d * 1.8 end
    return d, crit, zone
end

-- IPPJ hit reaction on a surviving zombie (ImprovedProjectile_01_main.lua)
local function ippjReact(victim, crit, zone)
    local sv = SandboxVars.ImprovedProjectile
    if not sv.IPPJEnableZombieHitReact then
        victim:addBlood(30)
        return
    end
    local reaction
    local doReaction = true
    if victim:isProne() then
        reaction = "FloorBack"
        victim:addBlood(50)
    elseif zone > 0.8 then
        reaction = ippjHighReact[HitmanRandom.Get() % 3 + 1]
        victim:addBlood(50)
    elseif zone > 0.4 then
        if crit then
            reaction = ippjMidReactCrit[HitmanRandom.Get() % 3 + 1]
            victim:addBlood(50)
        else
            reaction = ippjMidReact[HitmanRandom.Get() % 3 + 1]
            victim:addBlood(25)
        end
        if sv.IPPJZombieHitReactCond == 3 then doReaction = false end
    else
        if crit then victim:setHitFromBehind(true) end
        reaction = ippjLowReact[HitmanRandom.Get() % 2 + 1]
        victim:addBlood(crit and 50 or 25)
        if sv.IPPJZombieHitReactCond >= 2 then doReaction = false end
    end
    if doReaction then victim:setHitReaction(reaction) end
end
-- shot: per-round state from manageLineOfFire
--   { ippj = bool, hits = real hits so far, inRow = shootInARow, base = IPPJ round damage }
-- returns status, survived
--   "hit"   took the round (survived = still alive after it)
--   "miss"  accuracy roll failed (miss sound played)
--   "block" not an enemy of the shooter (friendly / neutral body in the line)
--   "pass"  nothing to resolve (already dying)
local function hit(shooter, item, victim, shot)

    -- Clone the shooter to create a temporary IsoPlayer
    -- local tempShooter = HitmanUtils.CloneIsoPlayer(shooter)
    local fakeZombie = getCell():getFakeZombieForHit()

    -- Calculate the distance between the shooter and the victim
    local dist = HitmanUtils.DistTo(victim:getX(), victim:getY(), shooter:getX(), shooter:getY())

    -- Determine accuracy based on SandboxVars and shooter clan
    local brainShooter = HitmanBrain.Get(shooter)

    -- PONGDU: who the round can hurt is decided before the accuracy roll, so
    -- the caller knows whether a body in the line stops or takes the round
    local isPlayer = instanceof(victim, "IsoPlayer")
    if isPlayer then
        if not (brainShooter.hostile or brainShooter.hostileP) then return "block" end
    elseif instanceof(victim, "IsoZombie") then
        if victim:isOnKillDone() or victim:isDead() then return "pass" end
        if not HitmanUtils.AreEnemies(HitmanBrain.Get(victim), brainShooter) then return "block" end
    else
        return "pass"
    end

    -- Logistic curve
    local function calculateHitChance(distance, accuracy)
        local baseChance = 9000  -- 90% hit chance at point blank
        local d50 = 16 + accuracy -- Distance where hit chance is 50%
        local k = 0.13   -- Steepness of falloff
        local floor = 1200 -- Minimal hit chance
        return floor + (baseChance - floor) / (1 + math.exp(k * (distance - d50)))
        -- return baseChance / (1 + math.exp(k * (distance - d50)))
    end

    -- general sandbox setting for accuracy 
    local sightGeneral = 8 -- will add or substract max 8

    -- accuracy set in hitman creator
    local sightCharacter = brainShooter.accuracyBoost or 0 -- will add or substract max 8

    -- scope boost
    local sightScope = 0
    local scope = item:getWeaponPart("Scope")
    if scope then
        sightScope = HitmanCompatibility.GetScopeRange(scope) -- will add 12, 16 or 22
    end

    local accuracyThreshold = calculateHitChance(dist, sightGeneral + sightCharacter + sightScope)
    --  print ("AT: " .. accuracyThreshold)
    -- if ZombRand(10000) < accuracyThreshold then
    local n = HitmanRandom.Get()
    if n >= accuracyThreshold then
        local missSound = "ZSMiss".. tostring(1 + ZombRand(8))
        victim:getSquare():playSound(missSound)
        return "miss"
    end

    -- print ("HIT N: " .. n)
    if isPlayer then
        HitmanPlayer.WakeEveryone()

        local hitSound = "ZSHit" .. tostring(1 + ZombRand(3))
        victim:playSound(hitSound)

        HitmanCompatibility.PlayerVoiceSound(victim, "PainFromFallHigh")
        victim:setHitFromBehind(shooter:isBehind(victim))
        victim:Hit(item, fakeZombie, 1.4, false, 1, false)

        -- addHolePlayer(victim)
        HitmanCompatibility.Splash(victim, item, fakeZombie)

        local bodyDamage = victim:getBodyDamage()
        if bodyDamage then
            local health = bodyDamage:getOverallBodyHealth()
            health = health + 8
            if health > 100 then health = 100 end
            bodyDamage:setOverallBodyHealth(health)
        end

        if (victim:isSprinting() or victim:isRunning()) and ZombRand(12) == 1 then
            victim:clearVariable("BumpFallType")
            victim:setBumpType("stagger")
            victim:setBumpFall(true)
            victim:setBumpFallType("pushedBehind")
        end

        shot.hits = shot.hits + 1
        return "hit", not victim:isDead()
    end

    -- zombie (plain or enemy hitman): resolved like a player shooting this gun
    shot.hits = shot.hits + 1
    victim:setHitFromBehind(shooter:isBehind(victim))
    victim:setHitAngle(shooter:getForwardDirection())
    victim:setPlayerAttackPosition(victim:testDotSide(shooter))

    if shot.ippj then
        if not shot.base then shot.base = ippjBaseDamage(item) end
        local d, crit, zone = ippjShot(item, shot.base, dist)
        shot.base = shot.base * (1 - SandboxVars.ImprovedProjectile.IPPJDmgReductionOnPnt)

        victim:setAttackedBy(shooter)
        victim:setHealth(victim:getHealth() - d)
        victim:reportEvent("wasHit")
        if victim:isDead() or victim:getHealth() <= 0 then
            victim:setHitReaction("ShotBelly")
            victim:Kill(fakeZombie)
        else
            ippjReact(victim, crit, zone)
        end
    else
        local d, modDelta, critDmg, knock = vanillaShot(shooter, item, victim, dist, shot.hits, shot.inRow)
        victim:setBumpDone(true)
        victim:setHitReaction("ShotBelly")
        -- the fake zombie is the wielder: its crit flag drives processHitDamage
        fakeZombie:setCriticalHit(critDmg)
        local ok, err = pcall(function() victim:Hit(item, fakeZombie, d, false, modDelta, false) end)
        fakeZombie:setCriticalHit(false)
        if not ok then
            print("[HITMANS] shot Hit failed: " .. tostring(err))
        end
        victim:setAttackedBy(shooter)
        -- knockdown: the player's hitConsequences re-rolls the crit (no behind bonus);
        -- in MP it is only applied for a local IsoPlayer wielder, so set it here
        if not victim:isDead() then
            victim:setKnockedDown(knock or victim:isOnFloor())
        end
    end

    addHole(victim)
    HitmanCompatibility.Splash(victim, item, fakeZombie)

    local h = victim:getHealth()
    local id = HitmanUtils.GetCharacterID(victim)
    local args = {id=id, h=h}
    sendClientCommand(getSpecificPlayer(0), 'Hitman_Sync', 'Health', args)

    -- Clean up the temporary player after use
    -- tempShooter:removeFromWorld()
    -- tempShooter = nil

    return "hit", h > 0 and not victim:isDead()
end

local function thump (object, thumper)
    local health = object:getHealth()
    -- print ("thumpable health: " .. object:getHealth())
    health = health - 20
    if health < 0 then health = 0 end
    if health == 0 then
        object:destroy()
    else
        object:setHealth(health)
        object:Thump(thumper)
    end
end

local mat2id = {"Flesh", "Flesh_Hollow", "Concrete", "Plaster", "Stone", "Wood", "Wood_Solid", "Brick", "Metal",
                "Metal_Large", "Metal_Light", "Metal_Solid", "Glass", "Glass_Light", "Glass_Solid", "Cinderblock",
                "Plastic", "Ceramic", "Rubber", "Fabric", "Carpet", "Dirt", "Grass", "Gravel", "Sand", "Snow"}

local function getMatId(matName)
    for k, v in pairs(mat2id) do
        if v == matName then
            return k
        end
    end
    return 0
end

local function manageLineOfFire (shooter, enemy, weaponItem, inRow)

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

    local vp = vehicleParts
    local snds = sounds
    local player = getSpecificPlayer(0)
    local piercing = weaponItem:isPiercingBullets()
    local projectiles = getProjectileCount(weaponItem:getWeaponReloadType())
    local shooterId = HitmanUtils.GetCharacterID(shooter)

    -- PONGDU: how many bodies one round goes through (see shot model header)
    local ippj = ippjOn()
    local shotgun = projectiles > 1
    local maxHits = maxHitsOf(weaponItem, ippj)
    local shot = { ippj = ippj, hits = 0, inRow = inRow or 0, base = nil }
    local slots = 0                 -- vanilla: targets the round reached (hit or miss)
    local pntOnKill = ippj and SandboxVars.ImprovedProjectile.IPPJPntOnKill

    -- characters standing on the square take the bullet
    -- returns true when the round stops here
    local function hitCharacters(square)
        local chrs = square:getMovingObjects()
        local wasHit = false
        for j=0, chrs:size()-1 do
            local chr = chrs:get(j)
            if instanceof(chr, "IsoZombie") or instanceof(chr, "IsoPlayer") then
                if shooterId ~= HitmanUtils.GetCharacterID(chr) then
                    local status, survived = hit(shooter, weaponItem, chr, shot)
                    if shotgun then
                        -- shotgun: old pellet logic (up to `projectiles` bodies, stops unless piercing)
                        wasHit = true
                        if j + 1 >= projectiles then break end
                    elseif status == "block" then
                        -- friendly / neutral body: soaks the round unless the gun pierces (old rule)
                        if not piercing then return true end
                    elseif status == "hit" or (status == "miss" and not ippj) then
                        slots = slots + 1
                        local used = ippj and shot.hits or slots
                        if used >= maxHits then return true end
                        if status == "hit" and survived and pntOnKill then return true end
                    end
                end
            end
        end
        return shotgun and wasHit and not piercing
    end

    -- Bresenham's line of fire to detect what needs to destroyed between shooter and target
    local i = 0
    while true do

        -- last iterations
        local isLast = (cx == x1 and cy == y1)
        local list = {}
        if isLast then
            -- point blank (target reached within the first 2 steps): narrower sweep
            -- so friendlies standing next to the shooter do not soak the bullet
            local r = (i > 1) and 2 or 1
            for x = -r, r do
                for y = -r, r do
                    table.insert(list, {x = cx + x, y = cy + y, z=cz, d = x * x + y * y})
                end
            end
            -- PONGDU: target square first, then outward, so the hit cap is spent on
            -- the bodies nearest the aim point
            table.sort(list, function(a, b) return a.d < b.d end)
        else
            table.insert(list, {x=cx, y=cy, z=cz})
        end

        for _, c in ipairs(list) do
            local square = cell:getGridSquare(c.x, c.y, c.z)
            if i <= 1 and isLast and square then
                -- point blank: the first 2 steps are the shooter's own/adjacent squares
                -- and are skipped by the obstacle sweep below, so resolve characters only
                if hitCharacters(square) then return false end

            elseif i > 1 and square then
                -- manage wall obstacle
                local props = square:getProperties()
                if props then
                    -- square:playSound("BulletImpact")
                    local matName = props:Val("Material")
                    if not matName then
                        matName = props:Val("MaterialType")
                    end
                    if matName then
                        -- print (matName)
                        local emitter = getWorld():getFreeEmitter(c.x, c.y, c.z)
                        local sid = emitter:playSound("BulletImpact")
                        HitmanCompatibility.setParameterValueByName(emitter, sid, "BulletHitSurface", getMatId(matName))
                        -- HitmanProjectile.Stop(brainShooter.id)
                    end
                    -- return false
                end

                -- manage window obstacle
                local window = square:getWindow()
                if window then
                    if (window:getNorth() and (y0 < cy or y1 < cy)) or 
                    (not window:getNorth() and (x0 < cx or x1 < cx)) then
                        local barricade = window:getBarricadeOnSameSquare()
                        if not barricade then
                            barricade = window:getBarricadeOnOppositeSquare()
                        end
                        local smash = false
                        if barricade then
                            if barricade:isMetal() then
                                barricade:Thump(shooter)
                                square:playSound("HitBarricadeMetal")
                                return false
                            else -- wood
                                barricade:Thump(shooter)
                                local p = barricade:getNumPlanks()
                                if p >= 2 then
                                    square:playSound("HitBarricadePlank")
                                    return false
                                end
                            end
                        end
                        if not window:isSmashed() then
                            square:playSound("SmashWindow")
                            window:smashWindow()
                        end
                    end
                end

                -- manage for door obstacle
                local door = square:getIsoDoor()
                if door and not door:IsOpen() then
                    if (door:getNorth() and (y0 < cy or y1 < cy)) or 
                       (not door:getNorth() and (x0 < cx or x1 < cx)) then
                        -- small chance to shoot through a small window in door
                        if ZombRand(10) > 1 then 
                            local sprite = door:getSprite()
                            local props = sprite:getProperties()
                            if props:Is("DoorSound") then
                                doorSound = props:Val("DoorSound")
                                if snds[doorSound] then
                                    square:playSound(snds[doorSound])
                                end
                            end
                            thump(door, shooter)
                            return false
                        end
                    end
                end

                -- manage vehicle obstacle
                local vehicle = square:getVehicleContainer()
                if vehicle then
                    local partRandom = ZombRand(30)
                    local vehiclePart
                    local dmg
                    if vp[partRandom] then
                        vehiclePart = vehicle:getPartById(vp[partRandom].name)
                        if vehiclePart and vehiclePart:getInventoryItem() then

                            local vehiclePartId = vehiclePart:getId()

                            local dmg = vp[partRandom].dmg
                            vehiclePart:damage(dmg)

                            if vehiclePart:getCondition() <= 0 then
                                vehiclePart:setInventoryItem(nil)
                                square:playSound(vp[partRandom].sndDest)
                            else
                                square:playSound(vp[partRandom].sndHit)
                                return false
                            end

                            vehicle:updatePartStats()

                            local args = {x=square:getX(), y=square:getY(), id=vehiclePartId, dmg=dmg}
                            sendClientCommand(player, 'Hitman_Commands', 'VehiclePartDamage', args)

                        end
                    end
                end

                -- manage character "obstacles"
                if hitCharacters(square) then return false end

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

    -- no bullet stop
    return true
end


-- ── PONGDU: gunshot sound ────────────────────────────────────────────────
-- Arsenal(26) GunFighter does not play the script SwingSound for players: its
-- attack hook picks the sound per ammo at shot time with the global
-- getShotSound(weapon, 1) (GunFighter_02Function.lua). Some Arsenal scripts carry
-- a SwingSound that no sound script defines (XM214 "MinigunShot"), so a hitman
-- playing weaponItem:getSwingSound() was silent. Use Arsenal's pick when it is
-- loaded, else the script sound. Cached per weapon type.
local shotSoundCache = {}
local function shotSoundOf(weaponItem)
    local ft = weaponItem:getFullType()
    local snd = shotSoundCache[ft]
    if snd == nil then
        local script = weaponItem:getSwingSound()
        snd = script
        if getShotSound then
            local ok, v = pcall(getShotSound, weaponItem, 1)
            if ok and v then snd = v end
        end
        shotSoundCache[ft] = snd or false
        print("[HITMANS] shot sound " .. tostring(ft) .. " = " .. tostring(snd) .. " (script " .. tostring(script) .. ")")
    end
    return snd or nil
end

-- ── PONGDU: rate fire (HitmanPrograms.Weapon.Shoot rate task) ──────────────
-- One Shoot task = one burst: {rate = rounds/s, left = rounds, window = ticks of
-- firing at the end of task.time}. Rounds are fired frame by frame in onWorking
-- from real elapsed time, so the cadence does not depend on FPS. The owed
-- fraction is carried per shooter across tasks, so back-to-back bursts keep the
-- exact rate; after a pause longer than RATE_RESET_MS and longer than one round
-- interval (1 / rate) the first round goes at once. The second condition keeps a slow
-- gun (semi-auto, rate < 4/s) from firing early when its next task starts quickly.
local RATE_RESET_MS      = 250
local RATE_MAX_PER_FRAME = 4      -- cap after a hitch
local AIMED_TOL          = 5      -- deg: within this the round goes at the target
local BLIND_MIN_R        = 10     -- blind rounds fly at least this far (tiles), at most the gun's range

-- aim point for a blind round (manageLineOfFire only calls getX/getY/getZ on it)
local blindPoint = { x = 0, y = 0, z = 0 }
function blindPoint:getX() return self.x end
function blindPoint:getY() return self.y end
function blindPoint:getZ() return self.z end
local rateState = {}              -- [shooter brain id] = { last = ms, carry = rounds }
local rateWeapon = {}             -- [shooter brain id] = { task = task, item = HandWeapon }

local function rateWeaponItem(brainShooter, weapon, task)
    local c = rateWeapon[brainShooter.id]
    if c and c.task == task then return c.item end
    local item = HitmanCompatibility.InstanceItem(weapon.name)
    if item then item = HitmanUtils.ModifyWeapon(item, brainShooter) end
    rateWeapon[brainShooter.id] = { task = task, item = item }
    return item
end

local function rateFire(zombie, task, enemy)
    local brainShooter = HitmanBrain.Get(zombie)
    if not brainShooter then return end
    local weapon = brainShooter.weapons[task.slot]
    if not weapon or (weapon.bulletsLeft or 0) <= 0 then task.left = 0; return end

    local sx, sy, sz, sd = zombie:getX(), zombie:getY(), zombie:getZ(), zombie:getDirectionAngle()
    local aimed = HitmanUtils.IsFacing(sx, sy, sd, enemy:getX(), enemy:getY(), AIMED_TOL)
    -- turning task (task.turnRate): keep firing while the gun sweeps toward the
    -- target; rounds go where the barrel points (blind) until it is on target
    if not aimed and not task.turnRate then return end

    local now = getTimestampMs()
    local sid = brainShooter.id
    local st = rateState[sid]
    local owed
    local gap = st and (now - st.last) or 0
    if not st or (gap > RATE_RESET_MS and gap * task.rate >= 1000) then
        st = { last = now, carry = 0 }
        rateState[sid] = st
        owed = 1
    else
        owed = (now - st.last) * task.rate / 1000 + st.carry
    end
    local n = math.floor(owed)
    if n > RATE_MAX_PER_FRAME then n = RATE_MAX_PER_FRAME; owed = n end
    if n > task.left then n = task.left end
    if n > weapon.bulletsLeft then n = weapon.bulletsLeft end
    if n <= 0 then return end

    local weaponItem = rateWeaponItem(brainShooter, weapon, task)
    if not weaponItem then task.left = 0; return end

    local projectiles = getProjectileCount(weaponItem:getWeaponReloadType())
    local aimAt, clear = enemy, false
    if aimed then
        clear = HitmanUtils.LineClear(zombie, enemy)
    else
        -- blind: a point straight down the barrel at about the target's range.
        -- manageLineOfFire stops at walls and rolls a hit on anyone in the line
        -- (and around the end point), so zombies swept by the barrel can die.
        local ex, ey = enemy:getX() - sx, enemy:getY() - sy
        local r = math.sqrt(ex * ex + ey * ey)
        task.maxR = task.maxR or HitmanCompatibility.GetMaxRange(weaponItem)
        if r > task.maxR then r = task.maxR end
        if r < BLIND_MIN_R then r = BLIND_MIN_R end
        local rad = math.rad(sd)
        blindPoint.x, blindPoint.y, blindPoint.z = sx + math.cos(rad) * r, sy + math.sin(rad) * r, sz
        aimAt, clear = blindPoint, true
        task.blind = (task.blind or 0) + n
    end
    for _ = 1, n do
        weapon.bulletsLeft = weapon.bulletsLeft - 1
        task.left = task.left - 1
        HitmanProjectile.Add(sid, sx, sy, sz, sd, projectiles)
        local inRow = noteShot(sid, weaponItem)
        if clear then manageLineOfFire(zombie, aimAt, weaponItem, inRow) end
    end
    st.carry = owed - n
    if st.carry > 1 then st.carry = 1 end
    st.last = now

    -- effects once per frame, not per round
    HitmanCompatibility.StartMuzzleFlash(zombie)
    local snd = shotSoundOf(weaponItem)
    if snd then zombie:getEmitter():playSound(snd) end
    if not brainShooter.sound or brainShooter.sound == 0 then
        addSound(getSpecificPlayer(0), sx, sy, sz, 40, 100)
        brainShooter.sound = 1
    end
    if not weaponItem:isManuallyRemoveSpentRounds() then
        zombie:playSound(weaponItem:getShellFallSound())
    end
    if weaponItem:isRackAfterShoot() then
        weapon.racked = false
        task.left = 0
    end
end

HitmanZombieActions.Shoot = {}
HitmanZombieActions.Shoot.onStart = function(zombie, task)
    zombie:setBumpType(task.anim)
    return true
end

HitmanZombieActions.Shoot.onWorking = function(zombie, task)
    local enemy = HitmanZombie.Cache[task.eid] or HitmanPlayer.GetPlayerById(task.eid)
    if not enemy then return true end
    if task.turnRate then
        -- PONGDU: sweep toward the target at turnRate deg/s instead of snapping
        HitmanUtils.TurnToward(zombie, enemy:getX(), enemy:getY(), task.turnRate, task)
    else
        zombie:faceLocationF(enemy:getX(), enemy:getY())
    end

    if task.time <= 0 then
        return true
    end

    local bumpOk = zombie:getBumpType() == task.anim
    if not bumpOk then 
        zombie:setBumpType(task.anim)
    end

    -- PONGDU: rate task fires inside its window (the delay before it is the burst spacing)
    if task.rate then
        if bumpOk and task.time <= task.window and (task.left or 0) > 0 then
            rateFire(zombie, task, enemy)
        end
        if (task.left or 0) <= 0 then return true end
    end

    return false
end

HitmanZombieActions.Shoot.onComplete = function(zombie, task)

    -- PONGDU: rate task rounds were fired in onWorking; refresh the death drop once per burst
    if task.rate then
        local brainShooter = HitmanBrain.Get(zombie)
        if brainShooter then rateWeapon[brainShooter.id] = nil end
        if task.blind and task.blind > 0 then
            print(string.format("[HITMANS] id %s burst done, %d blind rounds while turning (eid=%s)",
                tostring(brainShooter and brainShooter.id), task.blind, tostring(task.eid)))
        end
        Hitman.UpdateItemsToSpawnAtDeath(zombie)
        return true
    end

    local bumpType = zombie:getBumpType()
    if bumpType ~= task.anim then return true end

    local shooter = zombie
    local sx, sy, sz, sd = shooter:getX(), shooter:getY(), shooter:getZ(), shooter:getDirectionAngle()
    local brainShooter = HitmanBrain.Get(shooter)
    local weapon = brainShooter.weapons[task.slot]
    local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
    if not weaponItem then return true end

    weaponItem = HitmanUtils.ModifyWeapon(weaponItem, brainShooter)

    local enemy = HitmanZombie.Cache[task.eid] or HitmanPlayer.GetPlayerById(task.eid)
    if not enemy then return true end

    if not HitmanUtils.IsFacing(sx, sy, sd, enemy:getX(), enemy:getY(), 5) then 
        return true
    end

    -- burst tasks are queued up front and may outlast the magazine: no phantom rounds
    if weapon.bulletsLeft <= 0 then return true end

    -- deplete round
    weapon.bulletsLeft = weapon.bulletsLeft - 1
    Hitman.UpdateItemsToSpawnAtDeath(shooter)

    -- handle flash and projectile
    HitmanCompatibility.StartMuzzleFlash(shooter)
    local reloadType = weaponItem:getWeaponReloadType()
    local projectiles = getProjectileCount(reloadType)
    HitmanProjectile.Add(brainShooter.id, sx, sy, sz, sd, projectiles)
    local inRow = noteShot(brainShooter.id, weaponItem)

    -- handle real and "world" sound 
    -- local emitter = getWorld():getFreeEmitter(sx, sy, sz)
    local emitter = zombie:getEmitter()
    local swingSound = shotSoundOf(weaponItem)
    -- emitter:stopAll()
    if swingSound then emitter:playSound(swingSound) end
    -- emitter:setParameterValueByName(long, "CameraZoom", 1.0)

    if not brainShooter.sound or brainShooter.sound == 0 then
        addSound(getSpecificPlayer(0), sx, sy, sz, 40, 100)
        brainShooter.sound = 1
    end

    -- manage line of fire damage to characters and objects
    if HitmanUtils.LineClear(shooter, enemy) then
        manageLineOfFire(shooter, enemy, weaponItem, inRow)
    end

    -- handle post-shot things
    if not weaponItem:isManuallyRemoveSpentRounds() then
        shooter:playSound(weaponItem:getShellFallSound())
    end

    if weaponItem:isRackAfterShoot() then
        weapon.racked = false
    end

    return true
end