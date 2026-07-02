local LogLevel = 0

local isGhost = function(player)
    local gmd = GetHitmanModDataPlayers()
    local id = HitmanUtils.GetCharacterID(player)
    if gmd.OnlinePlayers[id] then
        return gmd.OnlinePlayers[id].isGhost
    end
    return false
end

local getPlayers = function()
    local world = getWorld()
    local gamemode = world:getGameMode()

    local playerList = {}
    if gamemode == "Multiplayer" then
        playerList = getOnlinePlayers()
    else
        playerList = IsoPlayer.getPlayers()
    end
    return playerList
end

local function getGroundType(square)
    local groundType = "generic"
    local objects = square:getObjects()
    for i=0, objects:size()-1 do
        local object = objects:get(i)
        if object then
            local sprite = object:getSprite()
            if sprite then
                local spriteName = sprite:getName()
                if spriteName then
                    if spriteName:embodies("street") then
                        groundType = "street"
                    elseif spriteName:embodies("natural") then
                        groundType = "natural"
                    end
                end
            end
        end
    end
    return groundType
end

local function getZone(square)
    local zone = square:getZone()
    if zone then
        local zoneType = zone:getType()
        return zoneType
    end
end

local function generateSpawnPointHere(player, x, y, z, count)
    local ret = {}
    local cell = player:getCell()
    local square = cell:getGridSquare(x, y, z)

    if square then
        local sp = {}
        sp.x = x
        sp.y = y
        sp.z = z
        sp.groundType = getGroundType(square)
        sp.zone = getZone(square)
        sp.outside = square:isOutside()
        
        for i=1, count do
            table.insert(ret, sp)
        end
    end
    return ret
end

local function generateSpawnPointUniform(player, d, count)
    
     -- Function to check if a point is within a basement region (b41!)
    local function isInBasement(x, y, basement)
        return x >= basement.x and x < basement.x + basement.width and
               y >= basement.y and y < basement.y + basement.height
    end

    local function isTooCloseToPlayer(x, y)
        -- Check if the player is in debug mode or admin mode
        if isDebugEnabled() or isAdmin() then
            return false
        end

        local playerList = getPlayers()
        for i=0, playerList:size()-1 do
            local player = playerList:get(i)
            if player and not isGhost(player) then
                local dist = HitmanUtils.DistTo(x, y, player:getX(), player:getY())
                if dist < 35 then
                    return true
                end
            end
        end
        return false
    end

    local cell = player:getCell()
    local px = player:getX()
    local py = player:getY()
    local pz = player:getZ()

    -- Check if BasementAPI exists before using it
    if BasementAPI then
        -- Get the list of basements
        local basements = BasementAPI.GetBasements()

        -- Check if the player is inside any basement region
        for _, basement in ipairs(basements) do
            if isInBasement(px, py, basement) then
                print("[INFO] Player is inside a basement region. Wave will not be spawned.")
                return
            end
        end
    end

    -- Check if RVInterior exists before using it (b41!)
    if RVInterior then
        if RVInterior.playerInsideInterior(player) then
            print("[INFO] Player is inside an RV interior. Wave will not be spawned.")
            return
        end
    end

    local validSpawnPoints = {}
    for i=1, 16 do
        local theta = ZombRandFloat(0, 2 * math.pi)
        local x = px + (d * math.cos(theta))
        local y = py + (d * math.sin(theta))
        local z = pz

        local square = cell:getGridSquare(x, y, z)
        if square then
            local sp = {
                x = x,
                y = y,
                z = z
            }
            if SafeHouse.isSafeHouse(square, nil, true) then
                print("[INFO] Spawn point is inside a safehouse, skipping.")
            elseif not square:isFree(false) then
                print("[INFO] Square is occupied, skipping.")
            elseif isTooCloseToPlayer(x, y) then
                print("[INFO] Spawn is too close to one of the players, skipping.")
            else
                sp.groundType = getGroundType(square)
                sp.zone = getZone(square)
                sp.outside = square:isOutside()
                table.insert(validSpawnPoints, sp)
            end
        end
    end

    if #validSpawnPoints >= 1 then
        local p = 1 + ZombRand(#validSpawnPoints)
        local spawnPoint = validSpawnPoints[p]
        local ret = {}
        for i=1, count do
            table.insert(ret, spawnPoint)
        end
        return ret
    else
        print ("[ERR] No valid spawn points available. Wave will not be spawned.")
    end

    return {}
end

local function hitmanize(zombie, hitman, clan, args)
    local id = zombie:getPersistentOutfitID()
    if LogLevel >= 3 then print ("[HITMANS] hitmanize started id " .. id) end

    local brain = {}

    -- auto-generated properties 
    brain.id = id
    brain.inVehicle = false
    brain.fullname = HitmanNames.GenerateName(hitman.general.female)
    brain.voice = Hitman.PickVoice(zombie)

    brain.born = getGameTime():getWorldAgeHours()
    brain.bornCoords = {}
    brain.bornCoords.x = zombie:getX()
    brain.bornCoords.y = zombie:getY()
    brain.bornCoords.z = zombie:getZ()

    brain.stationary = false
    brain.sleeping = false
    brain.aiming = false
    brain.moving = false
    brain.endurance = 1.00
    brain.speech = 0.00
    brain.sound = 0.00
    brain.infection = 0

    -- properties taken from hitman custom profile
    local general = hitman.general
    brain.clan = general.cid
    brain.cid = general.cid
    brain.bid = general.bid
    brain.female = general.female or false
    brain.skin = general.skin or 1
    brain.hairType = general.hairType or 1
    brain.hairColor = general.hairColor or 1
    brain.beardType = general.beardType or 1
    brain.eatBody = false

    local health = general.health or 5
    brain.health = HitmanUtils.Lerp(health, 1, 9, 1, 2.6)

    local accuracyBoost = general.sight or 5
    brain.accuracyBoost = HitmanUtils.Lerp(accuracyBoost, 1, 9, -8, 8)

    local enduranceBoost = general.endurance or 5
    brain.enduranceBoost = HitmanUtils.Lerp(enduranceBoost, 1, 9, 0.25, 1.75)

    local strengthBoost = general.strength or 5
    brain.strengthBoost = HitmanUtils.Lerp(strengthBoost, 1, 9, 0.25, 1.75)

    brain.exp = {0, 0, 0}
    if general.exp1 and general.exp2 and general.exp3 then
        brain.exp = {general.exp1, general.exp2, general.exp3}
    end

    brain.weapons = {}
    brain.weapons.melee = "Base.BareHands"
    brain.weapons.primary = {["bulletsLeft"] = 0, ["magCount"] = 0}
    brain.weapons.secondary = {["bulletsLeft"] = 0, ["magCount"] = 0}

    if hitman.weapons then
        if hitman.weapons.melee then
            brain.weapons.melee = HitmanCompatibility.GetLegacyItem(hitman.weapons.melee)
        end
        for _, slot in pairs({"primary", "secondary"}) do
            brain.weapons[slot].bulletsLeft = 0
            brain.weapons[slot].magCount = 0
            if hitman.weapons[slot] and hitman.ammo[slot] then
                brain.weapons[slot] = HitmanWeapons.Make(hitman.weapons[slot], hitman.ammo[slot])
            end
        end
    end

    brain.clothing = hitman.clothing or {}
    brain.tint = hitman.tint or {}
    brain.bag = hitman.bag

    brain.loot = {}
    brain.inventory = {}
    brain.tasks = {}

    -- hitman differentiators
    brain.rnd = {ZombRand(2), ZombRand(10), ZombRand(100), ZombRand(1000), ZombRand(10000)}

    brain.personality = {}

    -- addiction and sickness
    brain.personality.alcoholic = (ZombRand(50) == 0)
    brain.personality.smoker = (ZombRand(4) == 0)
    brain.personality.compulsiveCleaner = (ZombRand(90) == 0)

    -- collectors
    brain.personality.comicsCollector = (ZombRand(80) == 0)
    brain.personality.gameCollector = (ZombRand(220) == 0)
    brain.personality.hottieCollector = (ZombRand(100) == 0)
    brain.personality.toyCollector = (ZombRand(220) == 0)
    brain.personality.videoCollector = (ZombRand(220) == 0)
    brain.personality.underwearCollector = (ZombRand(150) == 0)

    -- heritage
    brain.personality.fromPoland = (ZombRand(120) == 0) -- ku chwale ojczyzny!

    -- properties from clan
    local spawn = clan.spawn
    brain.hostile = not spawn.friendly -- global hostility
    brain.hostileP = brain.hostile -- hostility against players

    -- properties taken from args, 
    brain.program = {}
    brain.program.name = args.program
    brain.program.stage = "Prepare"
    brain.programFallback = args.program

    -- bwo uses it
    brain.occupation = args.occupation
    brain.loyal = args.loyal or false

    brain.master = args.pid
    brain.permanent = args.permanent and true or false
    brain.key = args.key

    -- enforcing args
    brain.hostile = args.hostile or brain.hostile
    brain.hostileP = args.hostileP or brain.hostileP

    -- ready!
    local gmd = GetHitmanModData()
    gmd.Queue[id] = brain

    if LogLevel >= 3 then print ("[HITMANS] hitmanize finished id " .. id) end

    -- zombie:getModData().IsHitman = true
end

-- args: pid, waveId or cid, 
local function spawnGroup(spawnPoints, args)
    local knockedDown = false
    local crawler = false
    local fallOnFront = false
    local fakeDead = false
    local invulnerable = false
    local sitting = false
    local groupSize = #spawnPoints

    local cid = args.cid
    if not cid then return end

    local clan = HitmanCustom.ClanGet(cid)
    if not clan then return end

    local hitmanOptions = HitmanCustom.GetFromClan(cid)
    if not hitmanOptions then return end

    local keys = {}
    for key in pairs(hitmanOptions) do
        table.insert(keys, key)
    end

    if LogLevel >= 3 then print ("[HITMANS] spawnGroup has hitman options " .. #keys) end

    for i = #keys, 2, -1 do
        local j = ZombRand(i) + 1
        keys[i], keys[j] = keys[j], keys[i]
    end

    local hitmanSelected = {}
    for i = 1, math.min(groupSize, #keys) do
        local key = keys[i]
        hitmanSelected[key] = hitmanOptions[key]
    end

    local i = 1
    for bid, hitman in pairs(hitmanSelected) do
        hitman.general.bid = bid
        local femaleChance = hitman.general.female and 100 or 0
        local health = 1 -- client needs to update this later

        local sp = spawnPoints[i]

        -- local outfit = HitmanUtils.Choice({"Generic01", "Generic02", "Generic03", "Generic04", "Generic05"})
        local outfit = "Naked" .. (1 + ZombRand(101))
        local zombieList = HitmanCompatibility.AddZombiesInOutfit(sp.x, sp.y, sp.z, outfit, femaleChance, 
                                                                  crawler, fallOnFront, fakeDead, 
                                                                  knockedDown, invulnerable, sitting,
                                                                  health)
        local zombie = zombieList:get(0)
        hitmanize(zombie, hitman, clan, args)

        i = i + 1
    end
    return i - 1
end

local function getIconDataByProgram(program, friendly)

    local icon, color, desc

    if friendly then
        desc = "Friendly"
        color = {r=0.5, g=1, b=0.5} -- green
    else
        desc = "Hostile"
        color = {r=1, g=0.5, b=0.5} -- red
    end

    if program == "Hitman" then 
        icon = "media/ui/raid.png"
        desc = desc .. " " .. "Assault"
    elseif program == "Companion" then
        icon = "media/ui/friend.png"
        desc = desc .. " " .. "Companions"
    elseif program == "Looter" then
        icon = "media/ui/loot.png"
        desc = desc .. " " .. "Wanderers"
    elseif program == "Defend" then
        icon = "media/ui/defend.png"
        desc = desc .. " " .. "Defenders"
    elseif program == "Camper" then
        icon = "media/ui/tent.png"
        desc = desc .. " " .. "Camp"
    elseif program == "Roadblock" then
        icon = "media/ui/roadblock.png"
        desc = desc .. " " .. "Roadblock"
    end
    return icon, color, desc
end


local function spawnType(player, args)

    local pid = HitmanUtils.GetCharacterID(player)
    local cid = args.cid
    if not cid then return end

    if LogLevel >= 3 then print ("[HITMANS] spawnType has cid " .. cid) end
    local clan = HitmanCustom.ClanGet(cid).spawn
    local groupSize = clan.groupMin + ZombRand(clan.groupMax - clan.groupMin + 1)
    groupSize = math.floor(groupSize * SandboxVars.Hitmans.General_SpawnMultiplier + 0.5)
    local spawnPoints = {}

    if LogLevel >= 3 then print ("[HITMANS] groupSize is " .. groupSize) end

    if args.dist then
        spawnPoints = generateSpawnPointUniform(player, args.dist, groupSize)
    elseif args.x and args.y and args.z then
        spawnPoints = generateSpawnPointHere(player, args.x, args.y, args.z, groupSize)
    end

    if #spawnPoints == 0 then return end

    if LogLevel >= 3 then print ("[HITMANS] spawnPoints generated " .. #spawnPoints) end

    local args = {}
    args.pid = pid
    args.cid = cid
    args.permanent = false
    args.program = "Hitman"

    if LogLevel >= 3 then print ("[HITMANS] AI program is " .. args.program) end

    if #spawnPoints > 0 then
        local cnt = spawnGroup(spawnPoints, args)
        if SandboxVars.Hitmans.General_ArrivalIcon and cnt > 0 then
            local icon, color, desc = getIconDataByProgram(args.program, clan.friendly)
            if icon and color and desc then
                local x, y = spawnPoints[1].x, spawnPoints[1].y
                if isServer() then
                    local args = {icon=icon, time=1800, x=x, y=y, color=color, desc=desc}
                    sendServerCommand('t3_Commands', 'SetMarker', args)
                else
                    HitmanEventMarkerHandler.set(getRandomUUID(), icon, 1800, x, y, color, desc)
                end
            end
        end
    end

end
local function onClientCommand(module, command, player, args)
    if module == "t3_Spawner" and HitmanServer[module] and HitmanServer[module][command] then
        local argStr = ""
        for k, v in pairs(args) do
            argStr = argStr .. " " .. k .. "=" .. tostring(v)
        end
        -- print ("received " .. module .. "." .. command .. " "  .. argStr)
        HitmanServer[module][command](player, args)

        if module == "t3_Spawner" then
            TransmitHitmanModData()
        end
    end
end

-- api
HitmanServer = HitmanServer or {}
HitmanServer.t3_Spawner = {}

-- used for dedicated spawning by mods or debug
HitmanServer.t3_Spawner.Type = function(player, args)
    if not args.cid then return end
    
    args.pid = HitmanUtils.GetCharacterID(player)
    spawnType(player, args)
end

-- used for dedicated spawning by mods or debug
HitmanServer.t3_Spawner.Clan = function(player, args)
    if not args.cid then return end
    args.pid = HitmanUtils.GetCharacterID(player)

    if not args.size then args.size = 1 end
    if not args.program then args.program = "Hitman" end
    
    local spawnPoints = args.spawnPoints
    if not spawnPoints then
        if not args.x then args.x = player:getX() end
        if not args.y then args.y = player:getY() end
        if not args.z then args.z = player:getZ() end
        spawnPoints = generateSpawnPointHere(player, args.x, args.y, args.z, args.size)
    end

    if #spawnPoints > 0 then
        spawnGroup(spawnPoints, args)
    end
end

-- used for dedicated spawning of an individual by mods

Events.OnClientCommand.Add(onClientCommand)
