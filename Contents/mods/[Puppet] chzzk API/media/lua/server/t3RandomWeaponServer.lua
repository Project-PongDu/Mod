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
-- pool only if it appears in the distribution tables with a positive weight
-- in a REACHABLE distribution (see reachability below), i.e. it can actually
-- spawn in the world. This excludes transform-only items (e.g. Arsenal
-- Gunfighter's Home-key bayonet forms) and items disabled via Arsenal's
-- sandbox gating.
--
-- RANGED pool (built only when Arsenal Gunfighter is present): Arsenal
-- rewrites the distribution tables at OnPreDistributionMerge, baking its
-- sandbox TYPE / ORIGIN / CALIBER gating into the entry weights. The
-- post-init tables therefore ARE the sandbox-filtered spawn list: we sum the
-- positive weights per ranged weapon across all reachable items/junk arrays
-- and use that sum as the donation roll weight. Without Arsenal the ranged
-- pool is nil and the client falls back to the hardcoded vanilla table in
-- t3RandomWeapon.
--
-- REACHABILITY: Arsenal's gating is two-level. Per-caliber gun cases
-- (SuburbsDistributions["Case_Small1"] etc.) hold guns WITHOUT caliber
-- gating on the gun entries themselves; instead the CASE ITEM's own spawn
-- entries ("Base.Case_Small1", weight gated by x22/w22) are what enforce the
-- caliber sandbox. The engine (ItemPickerJava) fills a container item by
-- looking up the distribution keyed by the item's type, so if the case item
-- can never spawn, its contents can never exist in the world. We mirror
-- that: a distribution whose key resolves to a script item is only scanned
-- if that item itself appears somewhere with a positive weight. Computed as
-- a fixpoint (max 5 passes) to handle nested container chains. The scan is
-- monotonically shrinking, so equal set sizes between passes = converged.
-- NOTE: distro weights are per-container relative values; the cross-container
-- sum approximates global rarity, it is not an exact spawn probability.

t3RandomWeaponServer = t3RandomWeaponServer or {}

local LOG = "[PongDu][RandomWeaponServer] "

local cachedPools = nil
local cachedRanged = nil
local rangedBuilt = false -- distinguishes "not built yet" from "built as nil (no Arsenal)"

-- ── Distribution scan ───────────────────────────────────────────────────────
-- Walks the distribution tables. In every "items" / "junk" array (entries
-- alternate name, weight, name, weight ...) it collects:
--   * set of names having at least one positive-weight entry in a reachable
--     distribution (whitelist; stores both raw string and last dot-segment,
--     since names may or may not carry a module prefix)
--   * weightSum map: raw name -> sum of positive weights (ranged pool source)

local function addName(set, name)
    set[name] = true
    local short = string.match(name, "([^%.]+)$")
    if short then set[short] = true end
end

-- Cache for "does this distribution key resolve to a script item?" lookups.
-- Keys that resolve to items are container-type distributions (gun cases,
-- bags, first-aid kits ...); keys that don't (room names, procedural list
-- names, "all") are always traversed.
local itemKeyCache = {}
local function keyIsItem(key)
    local v = itemKeyCache[key]
    if v ~= nil then return v end
    local ok = getScriptManager():FindItem(key) ~= nil
    itemKeyCache[key] = ok
    return ok
end

-- One scan pass. reachable == nil means first pass (traverse everything);
-- otherwise container-item distros are only entered when their key is in
-- the reachable set from the previous pass.
local function scanTable(tbl, set, weightSum, depth, visited, reachable)
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
            local blocked = false
            if type(k) == "string" and reachable and keyIsItem(k) and not reachable[k] then
                blocked = true
            end
            if not blocked then
                scanTable(v, set, weightSum, depth + 1, visited, reachable)
            end
        end
    end
end

local function countSet(s)
    local n = 0
    for _ in pairs(s) do n = n + 1 end
    return n
end

local function scanDistributions()
    local roots = {}
    if ProceduralDistributions and ProceduralDistributions.list then
        table.insert(roots, ProceduralDistributions.list)
    end
    if SuburbsDistributions then
        table.insert(roots, SuburbsDistributions)
    end
    if VehicleDistributions then
        table.insert(roots, VehicleDistributions)
    end
    if #roots == 0 then
        print(LOG .. "WARNING: no distribution tables found; scan empty")
        return {}, {}, 0
    end

    local reachable = nil
    local set, weightSum
    local passes = 0
    for pass = 1, 5 do
        passes = pass
        set, weightSum = {}, {}
        local visited = {}
        for _, root in ipairs(roots) do
            scanTable(root, set, weightSum, 1, visited, reachable)
        end
        -- Monotonically shrinking: converged when the name count stops
        -- changing between passes.
        if reachable and countSet(set) == countSet(reachable) then break end
        reachable = set
    end
    print(LOG .. "distribution scan: " .. countSet(set) .. " reachable spawnable names from "
            .. #roots .. " tables (" .. passes .. " passes)")
    return set, weightSum, #roots
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
    print(LOG .. "rejected " .. rejectedNotDistributed .. " weapon items not reachable in world distributions")
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
        print(LOG .. "ranged pool built: " .. #ranged .. " firearms (distro-weighted, reachability-filtered)")
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
