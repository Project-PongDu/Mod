local _a = {}
local zone   = require("utils/zone")
local global = require("global")
_a.zombieSpawnQueue = {}

local _tagged = {}   -- [onlineID] = nametag string   (lightweight, persists)
local _cache  = {}   -- [onlineID] = TextDrawObject    (heavy, pruned aggressively)

-- How far above the zombie's feet the tag sits, in world-screen pixels.
-- Divided by zoom at draw time so it stays put when zooming in/out. Tune to taste.
local HEAD_OFFSET = 128

-- Only rebuild the cache / prune every N ticks. The render pass still runs every
-- tick so tags follow zombies smoothly; the expensive bookkeeping does not.
local MAINT_INTERVAL = 30

-- ── Spawn + tag newly spawned zombies near the spawn point ────────────────────
function _a.a()
    local player = getPlayer()
    if zone.a(player) then return end

    for _, req in ipairs(global.zombieSpawnQueue) do
        local x = player:getX() + zone.b()
        local y = player:getY() + zone.b()
        local z = player:getZ()
        sendClientCommand("PEvents", "ZedSpawn", {
            ["Etype"]  = "Spawn",
            ["ZedX"]   = x,
            ["ZedY"]   = y,
            ["ZedZ"]   = z,
            ["amount"] = req.amount,
            ["sprint"] = req.sprint,
            ["sender"] = req.sender,
        })

        if req.sender ~= "" then
            local name = req.sender .. getText("IGUI_donation_zombie_owner")
            -- Snapshot zombies that already existed so we only tag the new ones.
            local snap = {}
            local cell = getCell()
            local zl   = cell and cell:getZombieList()
            if zl then
                for i = 0, zl:size() - 1 do
                    local z2 = zl:get(i)
                    if z2 then snap[z2:getOnlineID()] = true end
                end
            end

            local amount  = req.amount
            local tagged  = 0
            local timeout = 600   -- ~10s safety window to catch spawns
            local function tagNew()
                timeout = timeout - 1
                if timeout <= 0 or tagged >= amount then
                    Events.OnTick.Remove(tagNew)
                    return
                end
                local cl    = getCell()
                local zlist = cl and cl:getZombieList()
                if not zlist then return end
                for i = 0, zlist:size() - 1 do
                    local z2 = zlist:get(i)
                    if z2 then
                        local id = z2:getOnlineID()
                        if id and not snap[id] then
                            local dx = z2:getX() - x
                            local dy = z2:getY() - y
                            if dx * dx + dy * dy < 225 then   -- within 15 tiles
                                snap[id]    = true
                                _tagged[id] = name
                                tagged      = tagged + 1
                            end
                        end
                    end
                end
            end
            Events.OnTick.Add(tagNew)
        end
    end

    global.zombieSpawnQueue = {}
end

--[[
-- ── Maintenance: build missing draw objects, prune stale ones (throttled) ─────
local _maint = 0
Events.OnTick.Add(function()
    _maint = _maint + 1
    if _maint < MAINT_INTERVAL then return end
    _maint = 0

    local cell = getCell()
    if not cell then return end
    local list = cell:getZombieList()
    if not list then return end

    local present = {}
    for n = 0, list:size() - 1 do
        local zed = list:get(n)
        if zed then
            local id = zed:getOnlineID()
            if id then
                if zed:isDead() then
                    -- Dead zombie: forget it entirely (frees the TextDrawObject).
                    _cache[id]  = nil
                    _tagged[id] = nil
                else
                    present[id] = true
                    if not _cache[id] then
                        local name = _tagged[id] or zed:getModData()["_cs"]
                        if name and name ~= "" then
                            local t = TextDrawObject.new()
                            t:ReadString(UIFont.Small, name, -1)
                            _cache[id] = t
                        end
                    end
                end
            end
        end
    end

    -- Drop draw objects for zombies that have left the cell. The name stays in
    -- _tagged, so the tag rebuilds automatically if the zombie wanders back.
    for id in pairs(_cache) do
        if not present[id] then _cache[id] = nil end
    end
end)

-- ── Render: draw each cached tag centred above its zombie's head (every tick) ──
Events.OnTick.Add(function()
    if not next(_cache) then return end
    local cell = getCell()
    if not cell then return end
    local list = cell:getZombieList()
    if not list then return end
    local zoom = getCore():getZoom(0)
    if not zoom or zoom == 0 then return end

    for n = 0, list:size() - 1 do
        local zed = list:get(n)
        if zed and not zed:isDead() then
            local id = zed:getOnlineID()
            local t  = id and _cache[id]
            if t then
                local sx = IsoUtils.XToScreen(zed:getX(), zed:getY(), zed:getZ(), 0)
                local sy = IsoUtils.YToScreen(zed:getX(), zed:getY(), zed:getZ(), 0)
                sx = (sx - IsoCamera.getOffX() - zed:getOffsetX()) / zoom
                sy = (sy - IsoCamera.getOffY() - zed:getOffsetY()) / zoom
                sx = sx - t:getWidth() / 2              -- centre horizontally
                sy = sy - HEAD_OFFSET / zoom - t:getHeight()  -- sit above the head
                t:setDefaultColors(1, 1, 1, 1)
                t:AddBatchedDraw(sx, sy, true)
            end
        end
    end
end)
--]]

return _a
