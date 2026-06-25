-- Make a zombie into a sprinter.
local function makeSprinter(a)
    local b = getSandboxOptions():getOptionByName("ZombieLore.Speed"):getValue()
    getSandboxOptions():set("ZombieLore.Speed", 1)
    a:makeInactive(true)
    a:makeInactive(false)
    local c = a.speedType or a:getVariableString("zombieWalkType")
    a:setWalkType("sprint" .. tostring(a.speedType))
    a:DoZombieStats()
    getSandboxOptions():set("ZombieLore.Speed", b)
    a:getModData()["isSprinter"] = true
    sendClientCommand("SpawnedSprinter", "isSprinter", {
        ["isSprinter"] = true,
        ["zedId"]      = a:getOnlineID(),
    })
end

-- Spawn zombies at (x,y,z), with optional sprinter/sender settings.
local function spawnZombies(x, y, z, amount, useHighStats, sprint, sender)
    amount       = amount or 1
    useHighStats = useHighStats ~= false
    sprint       = sprint or false

    local highCognition = 4
    local highMemory    = 5
    local highHearing   = 4

    local origCognition = getSandboxOptions():getOptionByName("ZombieLore.Cognition"):getValue()
    local origMemory    = getSandboxOptions():getOptionByName("ZombieLore.Memory"):getValue()
    local origHearing   = getSandboxOptions():getOptionByName("ZombieLore.Hearing"):getValue()
    local lastSpawned   = nil

    for n = 0, amount - 1 do
        if useHighStats then
            getSandboxOptions():set("ZombieLore.Cognition", highCognition)
            getSandboxOptions():set("ZombieLore.Memory",    highMemory)
            getSandboxOptions():set("ZombieLore.Hearing",   highHearing)
        end
        lastSpawned = addZombiesInOutfit(x, y, z, 1, nil, nil)
        if lastSpawned and lastSpawned:size() > 0 then
            lastSpawned:get(0):DoZombieStats()
            lastSpawned:get(0):makeInactive(true)
            lastSpawned:get(0):makeInactive(false)
        end
        if useHighStats then
            getSandboxOptions():set("ZombieLore.Cognition", origCognition)
            getSandboxOptions():set("ZombieLore.Memory",    origMemory)
            getSandboxOptions():set("ZombieLore.Hearing",   origHearing)
        end
        if lastSpawned and lastSpawned:size() > 0 then
            if sprint then
                lastSpawned:get(0):setWalkType("sprint4")
            else
                lastSpawned:get(0):setWalkType("walk")
            end
            if sender and sender ~= "" then
                lastSpawned:get(0):getModData()["_cs"] = sender .. getText("IGUI_donation_zombie_owner")
                lastSpawned:get(0):transmitModData()
            end
        end
    end
end

-- Handle "PEvents / ZedSpawn" client command.
local function srvlog(msg)
    local w = getFileWriter("server_log.txt", true, true)
    if w then w:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg) .. "\n") w:close() end
end

local function onClientCommand(module, command, player, data)
    if module == "PEvents" and command == "ZedSpawn" then
        srvlog("ZedSpawn RECEIVED on server")
        local offsetX = ZombRand(-4, 4)
        local offsetY = ZombRand(-4, 4)
        local x       = tonumber(data["ZedX"]) + offsetX
        local y       = tonumber(data["ZedY"]) + offsetY
        local z       = tonumber(data["ZedZ"])
        local amount  = tonumber(data["amount"])
        local sprint  = tonumber(data["sprint"])
        srvlog("coords x="..tostring(x).." y="..tostring(y).." z="..tostring(z).." amount="..tostring(amount).." sprint="..tostring(sprint))
        local isSprint = nil
        if sprint == 0 then isSprint = false
        elseif sprint == 1 then isSprint = true end
        local sender = data["sender"] or ""
        local ok, err = pcall(function()
            spawnZombies(x, y, z, amount, true, isSprint, sender)
        end)
        if ok then srvlog("spawnZombies OK")
        else srvlog("spawnZombies ERROR: " .. tostring(err)) end
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- ── DOServer command handlers ─────────────────────────────────────────────────
DOServer = DOServer or {}
DOServer["Schedule"] = DOServer["Schedule"] or {}

DOServer["Schedule"]["Kaboom"] = function(player, data)
    local cx = player:getX()
    local cy = player:getY()
    local e  = player:getCell()
    local r  = tonumber(data["r"]) or 80
    -- Burn walls and floors in radius.
    for floor = 0, 1 do
        for dy = -r, r do
            for dx = -r, r do
                local wx = cx + dx
                local wy = cy + dy
                local dist = math.sqrt(math.pow(wx - cx, 2) + math.pow(wy - cy, 2))
                if dist < r then
                    local sq = e:getGridSquare(wx, wy, floor)
                    if sq then
                        if floor == 0 and ZombRand(100) < 80 then sq:BurnWalls(false) end   -- 바닥 탈 확률: 80%
                        if ZombRand(100) < 30 and sq:isFree(false) then                     -- 바닥 잿더미 확률: 10%
                            local obj = IsoObject.new(sq, "floors_burnt_01_1", "")
                            sq:AddSpecialObject(obj)
                        end
                    end
                end
            end
        end
    end
    -- Kill zombies in radius.
    local zl = e:getZombieList()
    if zl then
        for i = 0, zl:size() - 1 do
            local z = zl:get(i)
            if z and not z:isDead() then
                local dist = math.sqrt(math.pow(z:getX() - cx, 2) + math.pow(z:getY() - cy, 2))
                if dist < r then
                    z:setHealth(0)
                end
            end
        end
    end
    -- Notify nearby players.
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            local dist = math.sqrt(math.pow(p:getX() - cx, 2) + math.pow(p:getY() - cy, 2))
            if dist < r then
                sendServerCommand(p, "Schedule", "NearbyExplosion", {})
            end
        end
    end
end

DOServer["Schedule"]["PlayExplosion"] = function(player, data)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            sendServerCommand(p, "Schedule", "PlayExplosion", {})
        end
    end
end

DOServer["Schedule"]["PlayAlert"] = function(player, data)
    local cx = tonumber(data["x"]) or player:getX()
    local cy = tonumber(data["y"]) or player:getY()
    local r  = tonumber(data["r"]) or 40
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            local dist = math.sqrt(math.pow(p:getX() - cx, 2) + math.pow(p:getY() - cy, 2))
            if dist < r then
                sendServerCommand(p, "Schedule", "PlayAlert", {})
            end
        end
    end
end

local function onClientCommandDOServer(module, command, player, data)
    if DOServer[module] and DOServer[module][command] then
        DOServer[module][command](player, data)
    end
end
Events.OnClientCommand.Add(onClientCommandDOServer)

-- ── Donation queue reader: REMOVED ───────────────────────────────────────────
-- Donation polling now happens CLIENT-SIDE (see DonationReceiver.lua). Each streamer's
-- client reads its own rewards.txt and applies the effect to itself, so the
-- server no longer reads donation_queue.txt or pushes Donation/Apply.
-- Zombie spawning (PEvents/ZedSpawn) and DOServer Schedule handlers above stay.

-- ── Donation stats collector ─────────────────────────────────────────────────
-- Each client forwards the raw donation lines it reads (DonationStats/Record).
-- The host labels them with the sender's account name and appends to a single
-- file on the SERVER machine:  Zomboid/Lua/profits.txt
--   line format (tab-separated):  <streamer username>\t<raw rewards.txt line>
-- Aggregation (per-streamer / per-viewer totals, Excel export) is done later by
-- an external Python script that reads profits.txt.
local PROFITS_FILE = "profits.txt"

local function onDonationStats(module, command, player, data)
    if module ~= "DonationStats" or command ~= "Record" then return end
    if not player or not data or not data.line then return end
    local streamer = player:getUsername() or "unknown"
    local w = getFileWriter(PROFITS_FILE, true, true)   -- create, append
    if w then
        w:write(streamer .. "\t" .. tostring(data.line) .. "\r\n")
        w:close()
    end
end
Events.OnClientCommand.Add(onDonationStats)
