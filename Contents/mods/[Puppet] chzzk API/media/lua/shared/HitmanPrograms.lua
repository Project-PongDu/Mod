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

-- ═══════════════════════════════════════════════════════════════════════════
--  PONGDU: 무기 사격 사양 -- 플레이어가 같은 총을 같은 사격 모드로 쏠 때의 박자
--
--  NPC 의 연사 속도 / 점사 탄수 / 다시 쏘기까지의 간격을 총 이름이 아니라 총의
--  스펙(FireMode, 양손 여부, RecoilDelay)에서 뽑는다. 어떤 총을 들려도 이 규칙으로
--  계산되며, 근거는 B41 41.78.20 플레이어 사격 코드다.
--   1) 한 발 = 공격 애니 노드 1회 재생.
--      발당 시간 = 클립 길이 / (노드 SpeedScale x 2D 블렌드 SpeedScale 0.8)
--      클립: 양손총 Bob_AttackRifle(_Small) 3200틱, 권총 Bob_AttackHandgun(_Small) 1600틱
--            (4800틱/초, media/anims_X/Bob). 노드는 AnimSets/player/ranged/<firearm|handgun>/
--            에서 FireMode 조건이 맞는 것. 맞는 노드가 없으면 FireMode 조건이 없는
--            Default 노드(SpeedScale = singleShootSpeed)가 재생된다.
--   2) 다음 발은 캐릭터 RecoilDelay 가 0 이 돼야 나간다. RecoilDelay 는 1배속에서
--      초당 30 씩 준다(IsoGameCharacter: 틱마다 0.625 x GameTime.getMultiplier(),
--      getMultiplier 1초 합 = 0.8 x 60). 값은 무기 RecoilDelay - Aiming x 2 (IsoPlayer).
--      Arsenal(26): 연사 모드(Auto/Auto[H]/Auto[L]/[6]Rotary)는 매 프레임 무기
--      RecoilDelay 를 0 으로 만든다(첫 발 지연 제거) -> 연사는 애니만 박자를 정한다.
--      그 외 모드는 발사 때마다 calcRecoilDelay(탄종/무게/개머리판)로 다시 계산한다.
--   3) Arsenal [N]Burst / [HN]Burst / [LN]Burst 는 N 발을 애니 박자로 쏘고 그 뒤에
--      RecoilDelay 만큼 쉰다.
--  히트맨은 스킬이 없으므로 Aiming 0 인 플레이어 기준이다(NPC_AIMING).
-- ═══════════════════════════════════════════════════════════════════════════
local ANIM_CLIP_S  = { firearm = 3200 / 4800, handgun = 1600 / 4800 }
local BLEND_SPEED  = 0.8
local RECOIL_PER_S = 0.625 * 0.8 * 60
local NPC_AIMING   = 0
local ANIM_SPEED_FIX = 0.8   -- GameTime.getAnimSpeedFix()

-- Arsenal(26)GunFighter[MOD 2.0] AnimSets/player/ranged/<종류>/*.xml 의 FireMode -> 노드 SpeedScale
local ARSENAL_NODE = {
    firearm = {
        ["Auto"]      = 8,  ["Single"]    = 2, ["Burst"]     = 5,
        ["[2]Burst"]  = 7,  ["[3]Burst"]  = 8, ["[6]Rotary"] = 15,
        ["Auto[H]"]   = 6,  ["Single[H]"] = 1, ["[H2]Burst"] = 5, ["[H3]Burst"] = 6,
        ["Auto[L]"]   = 10, ["Single[L]"] = 3, ["[L2]Burst"] = 10, ["[L3]Burst"] = 10,
    },
    handgun = {
        ["Auto"] = 3, ["Single"] = 1, ["[2]Burst"] = 3, ["[3]Burst"] = 3, ["Single[H]"] = 1,
    },
}
local ARSENAL_AUTO = { ["Auto"] = true, ["Auto[H]"] = true, ["Auto[L]"] = true, ["[6]Rotary"] = true }

-- Arsenal 은 client/GunFighter_02Function.lua 의 전역 calcRecoilDelay 로 판별한다
-- (이 함수가 실제로 플레이어의 단발/점사 RecoilDelay 를 정하므로 그대로 빌려 쓴다)
local function arsenalLoaded()
    return type(calcRecoilDelay) == "function"
end

-- 무기 RecoilDelay (플레이어가 쏠 때 실제로 쓰이는 값)
local function playerRecoilDelay(weaponItem, shooter, kind)
    local rd = weaponItem:getRecoilDelay()
    if kind == "arsenal" and shooter then
        local item = HitmanCompatibility.InstanceItem(weaponItem:getFullType())
        local ok, err = pcall(calcRecoilDelay, shooter, item)
        if ok and item then
            rd = item:getRecoilDelay()
        else
            print("[HITMANS] WARN fire spec: Arsenal calcRecoilDelay failed for "
                .. tostring(weaponItem:getFullType()) .. " (" .. tostring(err) .. "), using script RecoilDelay " .. tostring(rd))
        end
    end
    rd = rd - NPC_AIMING * 2
    if rd < 0 then rd = 0 end
    return rd
end

local fireSpecCache = {}
local fireSpecWarned = {}

HitmanPrograms.Weapon.FireSpec = function(weaponItem, shooter)
    local mode = weaponItem:getFireMode() or ""
    local key = weaponItem:getFullType() .. "|" .. mode
    local spec = fireSpecCache[key]
    if spec then return spec end

    local kind = arsenalLoaded() and "arsenal" or "vanilla"
    local wtype = weaponItem:isTwoHandWeapon() and "firearm" or "handgun"
    local singleSpeed = (0.8 + NPC_AIMING / 10) * ANIM_SPEED_FIX   -- SwipeStatePlayer singleShootSpeed

    local node
    if kind == "arsenal" then
        node = ARSENAL_NODE[wtype][mode]
        if not node and mode ~= "" then
            local wk = wtype .. "|" .. mode
            if not fireSpecWarned[wk] then
                fireSpecWarned[wk] = true
                print("[HITMANS] WARN fire spec: no " .. wtype .. " AnimSet node for FireMode " .. mode
                    .. ", using the Default node like the player does")
            end
        end
    elseif wtype == "firearm" and mode == "Auto" then
        node = 4 * ANIM_SPEED_FIX                                       -- SwipeStatePlayer autoShootSpeed
    end
    node = node or singleSpeed

    local animS = ANIM_CLIP_S[wtype] / (node * BLEND_SPEED)
    local auto = (kind == "arsenal" and ARSENAL_AUTO[mode] == true) or (kind == "vanilla" and mode == "Auto")
    local burstDigit = (kind == "arsenal") and mode:match("^%[[HL]?(%d)%]Burst$") or nil
    local burst = burstDigit and tonumber(burstDigit) or nil

    local recoilDelay = 0
    if not (kind == "arsenal" and auto) then
        recoilDelay = playerRecoilDelay(weaponItem, shooter, kind)
    end
    local recoilS = recoilDelay / RECOIL_PER_S

    spec = { mode = mode, auto = auto, burst = burst, node = node, recoilDelay = recoilDelay }
    if burst then
        spec.rate  = 1 / animS                         -- 점사 안은 애니 박자
        spec.cycle = math.max(animS, recoilS)          -- 점사 끝나고 다음 점사까지
    else
        local shotS = math.max(animS, recoilS)
        spec.rate  = 1 / shotS
        spec.cycle = auto and 0 or shotS               -- 연사는 방아쇠를 놓지 않는다
        if not auto then spec.burst = 1 end
    end
    fireSpecCache[key] = spec
    print(string.format("[HITMANS] fire spec %s mode=%s (%s %s) rate=%.2f/s burst=%s cycle=%.2fs node=%.2f recoilDelay=%.1f",
        tostring(weaponItem:getFullType()), mode ~= "" and mode or "none", kind, wtype, spec.rate,
        tostring(spec.burst or "-"), spec.cycle, node, recoilDelay))
    return spec
end

-- fire (optional, PONGDU: airborne troopers features/airborne.lua FirePlan):
--   {bullets=n, firstTime=ticks, turnRate=deg/s}. The caller sizes bullets from
--   Weapon.FireSpec, so this does not care which gun it is. The whole plan is ONE
--   Shoot task (rate, left, window) that ZAShoot fires at spec.rate frame by frame
--   (the one-round-per-task pipeline costs at least 3 frames a round).
--   firstTime = ticks before the first round (nil = the default aim-and-fire delay).
-- without fire: default hitman rule -- auto 2~7 rounds under 15 tiles, burst modes
--   one burst, others 1 round; rounds are spaced at the weapon's own rate.
HitmanPrograms.Weapon.Shoot = function(hitman, enemyCharacter, slot, fire)
    local tasks = {}

    local brain = HitmanBrain.Get(hitman)
    local weapon = brain.weapons[slot]
    local weaponItem = HitmanCompatibility.InstanceItem(weapon.name)
    local fireTimeIndividual = brain.rnd and brain.rnd[2] or 0
    local spec = HitmanPrograms.Weapon.FireSpec(weaponItem, hitman)

    local dist = HitmanUtils.DistTo(hitman:getX(), hitman:getY(), enemyCharacter:getX(), enemyCharacter:getY())
    local firingtime = weaponItem:getRecoilDelay() + math.floor(dist ^ 1.1) + fireTimeIndividual
    if Hitman.HasExpertise(hitman, Hitman.Expertise.Sharpshooter) then
        firingtime = firingtime / 2
    end

    local bullets = 1
    if fire then
        bullets = fire.bullets or 1
        if fire.firstTime then firingtime = fire.firstTime end
    elseif spec.auto then
        if dist < 15 then bullets = 2 + ZombRand(6) end
    else
        bullets = spec.burst or 1
    end
    -- never plan more rounds than are loaded (no phantom shots past an empty mag)
    local loaded = weapon.bulletsLeft or 0
    if bullets > loaded then bullets = math.max(1, loaded) end

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

    if fire then
        local delay = math.max(0, firingtime)
        local window = math.ceil(bullets / spec.rate * 60) + 6
        table.insert(tasks, {action="Shoot", anim=anim, time=delay + window, window=window, rate=spec.rate, left=bullets,
                             turnRate=fire.turnRate, slot=slot, x=x, y=y, z=z, eid=eid})
        return tasks
    end

    local interval = math.max(1, math.floor(60 / spec.rate + 0.5))
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
