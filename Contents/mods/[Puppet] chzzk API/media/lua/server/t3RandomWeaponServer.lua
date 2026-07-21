-- t3RandomWeaponServer: builds the weapon-box pools on the SERVER from the
-- actual world loot distribution tables, then syncs them to clients.
--
-- Why server-side: ProceduralDistributions / SuburbsDistributions /
-- VehicleDistributions live in media/lua/server, which MP clients never load.
-- The box-opening recipe OnCreate runs on the client, so the server scans the
-- tables once, builds the pools, and pushes them down via sendServerCommand.
-- In singleplayer this file is loaded locally, so t3RandomWeapon (shared)
-- calls the build functions directly with no round trip.
--
-- MELEE pools (6 skill categories): whitelist rule -- an item may enter a
-- pool only if it appears in the distribution tables with a positive weight,
-- i.e. it can naturally spawn in the world. This excludes transform-only
-- items (e.g. Arsenal Gunfighter's Home-key bayonet forms) and items whose
-- distro weights were driven negative by Arsenal's sandbox gating.
--
-- RANGED pool (built only when Arsenal Gunfighter is present): Arsenal
-- rewrites the distribution tables at OnPreDistributionMerge, baking its
-- sandbox TYPE / ORIGIN / CALIBER gating into each entry's final weight
-- (disabled guns end up <= 0). The post-init tables therefore ARE the
-- sandbox-filtered spawn list: we sum the positive weights per ranged weapon
-- across all items/junk arrays and use that sum as the donation roll weight.
-- Without Arsenal the ranged pool is nil and the client falls back to the
-- hardcoded vanilla table in t3RandomWeapon.
-- NOTE: distro weights are per-container relative values; the cross-container
-- sum approximates global rarity, it is not an exact spawn probability.

t3RandomWeaponServer = t3RandomWeaponServer or {}

local LOG = "[PongDu][RandomWeaponServer] "

local cachedPools = nil
local cachedRanged = nil
local rangedBuilt = false -- distinguishes "not built yet" from "built as nil (no Arsenal)"

-- ── Distribution scan ───────────────────────────────────────────────────────
-- Walks the distribution tables once. In every "items" / "junk" array
-- (entries alternate name, weight, name, weight ...) it collects:
--   * whitelist set of names having at least one positive-weight entry
--   * weightSum map: raw name -> sum of positive weights (ranged pool source)
-- Names may or may not carry a module prefix ("Axe" vs "Base.Axe"), so the
-- whitelist stores both the raw string and its last dot-segment.

local function addName(set, name)
    set[name] = true
    local short = string.match(name, "([^%.]+)$")
    if short then set[short] = true end
end

local function scanTable(tbl, set, weightSum, depth, visited)
    if type(tbl) ~= "table" or depth > 8 or visited[tbl] then return end
    visited[tbl] = true
    for k, v in pairs(tbl) do
        if (k == "items" or k == "junk") and type(v) == "table" then
            for i = 1, #v, 2 do
                local name, weight = v[i], v[i + 1]
                if type(name) == "string" and type(weight) == "number" and weight > 0 then
                    addName(set, name)
                    weightSum[name] = (weightSum[name] or 0) + weight
                end
            end
        elseif type(v) == "table" then
            scanTable(v, set, weightSum, depth + 1, visited)
        end
    end
end

local function scanDistributions()
    local set, weightSum = {}, {}
    local visited = {}
    local sources = 0
    if ProceduralDistributions and ProceduralDistributions.list then
        scanTable(ProceduralDistributions.list, set, weightSum, 1, visited)
        sources = sources + 1
    end
    if SuburbsDistributions then
        scanTable(SuburbsDistributions, set, weightSum, 1, visited)
        sources = sources + 1
    end
    if VehicleDistributions then
        scanTable(VehicleDistributions, set, weightSum, 1, visited)
        sources = sources + 1
    end
    local count = 0
    for _ in pairs(set) do count = count + 1 end
    print(LOG .. "distribution scan: " .. count .. " spawnable names from " .. sources .. " tables")
    if sources == 0 then
        print(LOG .. "WARNING: no distribution tables found; scan empty")
    end
    return set, weightSum, sources
end

-- ── Arsenal Gunfighter detection ────────────────────────────────────────────
-- Primary: the GUNFIGHTER global set by GunFighter_01Option.lua (shared).
-- Fallback: a stable Arsenal script item, in case the global ever moves.
local function detectArsenal()
    if type(GUNFIGHTER) == "table" then return true, "GUNFIGHTER global" end
    local sm = getScriptManager()
    if sm and sm:FindItem("Base.Ruger_MK4") then return true, "script item Base.Ruger_MK4" end
    return false, "not detected"
end

-- ── Pool build ──────────────────────────────────────────────────────────────
-- Melee category rules mirror t3RandomWeapon (shared): 6 skill categories,
-- Improvised excluded except for Spear.

local ALLOW_IMPROVISED = { Spear = true }

-- Builds both pools in one distribution scan. Returns pools, ranged.
function t3RandomWeaponServer.BuildAll()
    local whitelist, weightSum, sources = scanDistributions()

    -- Melee pools --
    local pools = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        pools[entry.category] = {}
    end
    local rejectedNotDistributed = 0
    local allItems = getScriptManager():getAllItems()
    for i = 1, allItems:size() do
        local scriptItem = allItems:get(i - 1)
        if scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete() then
            local inWorld = whitelist[scriptItem:getFullName()] or whitelist[scriptItem:getName()]
            if inWorld then
                local cats = scriptItem:getCategories()
                for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
                    if cats:contains(entry.category)
                            and (ALLOW_IMPROVISED[entry.category] or not cats:contains("Improvised")) then
                        table.insert(pools[entry.category], scriptItem:getFullName())
                        break
                    end
                end
            else
                rejectedNotDistributed = rejectedNotDistributed + 1
            end
        end
    end
    print(LOG .. "rejected " .. rejectedNotDistributed .. " weapon items not present in world distributions")
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        print(LOG .. "melee pool built: " .. entry.category .. " = " .. #pools[entry.category] .. " items")
        if #pools[entry.category] == 0 then
            print(LOG .. "WARNING: empty melee pool for category " .. entry.category)
        end
    end

    -- Ranged pool (Arsenal only) --
    local arsenal, how = detectArsenal()
    print(LOG .. "Arsenal Gunfighter detection: " .. tostring(arsenal) .. " (" .. how .. ")")
    local ranged = nil
    if arsenal then
        local sm = getScriptManager()
        -- Dedupe by full name: "Pistol" and "Base.Pistol" resolve to the same
        -- script item, so their distro weights are merged here.
        local byFullName = {}
        for name, wsum in pairs(weightSum) do
            local si = sm:FindItem(name)
            if si and si:getTypeString() == "Weapon" and not si:getObsolete() and si:isRanged() then
                local full = si:getFullName()
                byFullName[full] = (byFullName[full] or 0) + wsum
            end
        end
        ranged = {}
        for full, wsum in pairs(byFullName) do
            local w = math.floor(wsum + 0.5)
            if w < 1 then w = 1 end
            table.insert(ranged, { item = full, weight = w })
        end
        print(LOG .. "ranged pool built: " .. #ranged .. " firearms (distro-weighted)")
        if #ranged == 0 then
            print(LOG .. "WARNING: Arsenal detected but ranged pool empty; client falls back to vanilla table")
            ranged = nil
        end
    else
        print(LOG .. "ranged pool skipped (no Arsenal); client uses vanilla table")
    end

    -- Only cache a meaningful result; if the distribution tables were missing
    -- entirely, retry on the next request instead of freezing empty pools.
    if sources > 0 then
        cachedPools = pools
        cachedRanged = ranged
        rangedBuilt = true
    end
    return pools, ranged
end

function t3RandomWeaponServer.BuildPools()
    if cachedPools then return cachedPools end
    local pools = t3RandomWeaponServer.BuildAll()
    return pools
end

function t3RandomWeaponServer.BuildRangedPool()
    if rangedBuilt then return cachedRanged end
    local _, ranged = t3RandomWeaponServer.BuildAll()
    return ranged
end

-- ── Client sync ─────────────────────────────────────────────────────────────
Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PongDuRandomWeapon" then return end
    if command == "RequestPools" then
        print(LOG .. "pool request from " .. tostring(player and player:getUsername()))
        sendServerCommand(player, "PongDuRandomWeapon", "Pools", {
            pools = t3RandomWeaponServer.BuildPools(),
            ranged = t3RandomWeaponServer.BuildRangedPool(),
        })
    end
end)
