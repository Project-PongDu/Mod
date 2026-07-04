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

-- ── 뮤턴트 소환 (mutant_spawn) ────────────────────────────────────────────────
-- 스크리머/브루트/로치. CDDA 모드 의존 없음 — 서버는 스폰 + modData 마킹만
-- 하고, 스탯·행동(HP/스프린트/괴력/비명/밀치기/3배속 크롤)은 각 클라이언트의
-- 적용기(features/mutantspawn.lua, OnZombieUpdate)가 처리한다 (좀비 클라 권한).
local function spawnSpecialZombie(x, y, z, kind, sender)
    local zeds = addZombiesInOutfit(x, y, z, 1, nil, nil)
    if not zeds or zeds:size() == 0 then return false end
    local zed = zeds:get(0)
    zed:DoZombieStats()
    zed:makeInactive(true)
    zed:makeInactive(false)
    zed:getModData()["PuppetMutant"] = kind
    if sender and sender ~= "" then
        zed:getModData()["_cs"] = sender .. getText("IGUI_donation_zombie_owner")
    end
    zed:transmitModData()
    -- 서버발 zombie transmitModData는 클라에 전달이 안 되므로(스프린터의
    -- SpawnedSprinter 죽은 코드와 같은 함정) 폭격과 동일한 검증된 채널로
    -- 전 클라에 zedId+kind를 브로드캐스트 -> 클라 적용기가 onlineID로 매칭.
    sendServerCommand("PEvents", "MutantMark", {
        ["zedId"] = zed:getOnlineID(),
        ["kind"]  = kind,
    })
    return true
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
    elseif module == "PEvents" and command == "MutantSpawn" then
        local x    = tonumber(data["ZedX"])
        local y    = tonumber(data["ZedY"])
        local z    = tonumber(data["ZedZ"]) or 0
        local kind = tostring(data["kind"] or "roach")
        srvlog("MutantSpawn kind=" .. kind .. " x=" .. tostring(x) .. " y=" .. tostring(y))
        if x and y then
            local ok, err = pcall(function()
                spawnSpecialZombie(x, y, z, kind, data["sender"] or "")
            end)
            if ok then srvlog("MutantSpawn OK")
            else srvlog("MutantSpawn ERROR: " .. tostring(err)) end
        end
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
                        if ZombRand(100) < 50 and sq:isFree(false) then                     -- 바닥 잿더미 확률: 50%
                            local obj = IsoObject.new(sq, "floors_burnt_01_1", "")
                            -- transmitAddObjectToSquare가 로컬 추가(AddTileObject)와 클라 전파를
                            -- 한 번에 처리한다. AddSpecialObject를 먼저 부르면 obj가 이미 Objects에
                            -- 들어가 가드(!Objects.contains)에 걸려 전파가 스킵되므로 호출하지 않는다.
                            -- index=-1 = 리스트 끝에 append (AddTileObject에서 안전 처리).
                            sq:transmitAddObjectToSquare(obj, -1)
                        end
                    end
                end
            end
        end
    end
    -- 좀비 킬은 서버에서 하지 않는다.
    -- B41 멀티에서 좀비는 클라이언트 권한(client-authoritative)이므로 서버사이드
    -- setHealth/becomeCorpse는 소유 클라의 동기화에 덮여 저장에 반영되지 않는다
    -- (재접속 시 일반좀비로 부활하는 원인). 대신 폭발 좌표/반경을 전 클라에
    -- 브로드캐스트하고, 각 클라가 자기 소유 좀비를 정상 킬 시퀀스로 죽인다
    -- (bombard.lua의 killZombiesAround). 도네이터 본인은 이미 로컬에서 처리했으므로 제외.
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            sendServerCommand(p, "Schedule", "NearbyExplosion", {x = cx, y = cy, r = r})
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

-- 라이즈 업 데드 맨: 반경 내 모든 시체(IsoDeadBody)를 좀비로 부활.
-- 시체는 B41 MP에서 서버 권한(청크 데이터 + reanimated.bin 저장, 바닐라 디버그
-- 시체제거도 /removezombies 서버 커맨드 경유)이므로 서버 한 곳에서만 처리해
-- 클라이언트별 중복 부활을 원천 차단한다. reanimateNow()는 바닐라 디버그 메뉴
-- "Reanimate (Zombie)"가 쓰는 강제 부활 API — 샌드박스 Reanimate 설정과 무관하게
-- 즉시 부활시킨다 (DebugContextMenu.OnReanimateCorpse 와 동일).
DOServer["Schedule"]["RiseUp"] = function(player, data)
    local cx = tonumber(data["x"]) or player:getX()
    local cy = tonumber(data["y"]) or player:getY()
    local r  = tonumber(data["r"]) or 55
    local cell = player:getCell()
    local r2 = r * r
    local raised = 0
    for floor = 0, 7 do                    -- 다층 건물 내부 시체까지 포함
        for dy = -r, r do
            for dx = -r, r do
                if dx * dx + dy * dy < r2 then
                    local sq = cell:getGridSquare(cx + dx, cy + dy, floor)
                    if sq then
                        -- reanimateNow()가 시체를 스퀘어에서 제거하므로
                        -- 순회 중 리스트 변형을 피하려고 먼저 수집 후 발동
                        local smo = sq:getStaticMovingObjects()
                        local bodies = nil
                        for i = 0, smo:size() - 1 do
                            local o = smo:get(i)
                            if instanceof(o, "IsoDeadBody") then
                                bodies = bodies or {}
                                bodies[#bodies + 1] = o
                            end
                        end
                        if bodies then
                            for _, b in ipairs(bodies) do
                                b:reanimateNow()
                                raised = raised + 1
                            end
                        end
                    end
                end
            end
        end
    end
    srvlog("RiseUp: " .. raised .. " corpses reanimated around " .. cx .. "," .. cy .. " r=" .. r)
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

