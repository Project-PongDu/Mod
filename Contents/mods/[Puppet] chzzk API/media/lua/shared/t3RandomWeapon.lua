-- t3RandomWeapon: random_weapon donation feature.
-- Donation grants a melee or ranged weapon box (50/50, decided in rewardManager).
--
-- Melee box: rolls one of the 6 vanilla melee skill categories by weight
-- (CATEGORY_TABLE, weights sum to 100), then picks uniformly among ALL script
-- items belonging to that category. Item pools are enumerated at runtime from
-- getScriptManager():getAllItems() and cached on first open, so vanilla
-- weapons never need to be listed by hand.
--   Pool filters: Type == Weapon, not OBSOLETE, and "Improvised" excluded --
--   except for Spear, where Improvised is allowed (nearly every spear is
--   "Improvised;Spear" and they are real weapons, unlike spoons/plungers).
-- Ranged box:
--   * Arsenal Gunfighter present: server-built pool scanned from the loot
--     distribution tables AFTER Arsenal baked its sandbox TYPE/ORIGIN/CALIBER
--     gating into them, so only sandbox-enabled guns appear, weighted by
--     their summed distro weights (see t3RandomWeaponServer).
--   * Vanilla: static weight table below (weights sum to 100).
--   Either way the weapon comes with 2 magazines + 3 ammo boxes resolved
--   from the weapon's own script data (getMagazineType / getAmmoBox), so no
--   per-gun clip/ammo pairing table is needed.
--
-- Global table (no module return) so recipe OnCreate can resolve
-- "t3RandomWeapon.OpenMeleeBox" / "t3RandomWeapon.OpenRangedBox".

t3RandomWeapon = t3RandomWeapon or {}

local LOG = "[PongDu][RandomWeapon] "

local MAG_COUNT = 2
local AMMO_BOX_COUNT = 3
local FALLBACK_LOOSE_ROUNDS = 60 -- when a firearm defines no AmmoBox in its script

-- ── Melee category table (weights sum = 100) ────────────────────────────────
-- Category strings must match vanilla script "Categories" values
-- (see XpUpdate.lua / HandWeapon.java).
t3RandomWeapon.CATEGORY_TABLE = {
    { category = "SmallBlunt", weight = 25 },
    { category = "SmallBlade", weight = 20 },
    { category = "Blunt",      weight = 20 },
    { category = "Spear",      weight = 15 },
    { category = "Axe",        weight = 12 },
    { category = "LongBlade",  weight = 8  },
}

-- Categories where "Improvised" items stay in the pool.
local ALLOW_IMPROVISED = { Spear = true }

-- ── Vanilla ranged table (weights sum = 100) ────────────────────────────────
-- Fallback used only when no Arsenal ranged pool is available. Magazines and
-- ammo are resolved at grant time from the weapon script, not listed here.
t3RandomWeapon.RANGED_TABLE = {
    { item = "Base.AssaultRifle",        weight = 3  },
    { item = "Base.AssaultRifle2",       weight = 4  },
    { item = "Base.Revolver_Long",       weight = 4  },
    { item = "Base.Pistol3",             weight = 5  },
    { item = "Base.Revolver_Short",      weight = 6  },
    { item = "Base.HuntingRifle",        weight = 8  },
    { item = "Base.DoubleBarrelShotgun", weight = 8  },
    { item = "Base.VarmintRifle",        weight = 10 },
    { item = "Base.Revolver",            weight = 10 },
    { item = "Base.Shotgun",             weight = 12 },
    { item = "Base.Pistol2",             weight = 12 },
    { item = "Base.Pistol",              weight = 18 },
}

-- ── Pool caches ─────────────────────────────────────────────────────────────
-- Authoritative pools come from the server (t3RandomWeaponServer), built from
-- the world loot distribution tables so only naturally-spawning weapons enter.
--   * SP / local host: server lua is loaded locally -> direct build calls.
--   * MP client: requested at OnGameStart, received via OnServerCommand.
--   * Melee fallback (sync not yet arrived): local vanilla-only build via
--     getModID(), which cannot see distribution tables but at least blocks
--     modded transform-only items (e.g. bayonet-form rifles).
--   * Ranged fallback: static RANGED_TABLE above (vanilla guns).
local syncedPools = nil   -- melee: server-authoritative (or locally built in SP)
local meleePools = nil    -- melee: fallback cache (vanilla-only)
local syncedRanged = nil  -- ranged: server-authoritative Arsenal pool (or nil)

local function buildMeleePools()
    meleePools = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        meleePools[entry.category] = {}
    end
    local rejectedModded = 0
    local allItems = getScriptManager():getAllItems()
    for i = 1, allItems:size() do
        local scriptItem = allItems:get(i - 1)
        -- Vanilla-only filter. NOTE: matching the "Base." module prefix on
        -- getFullName() is NOT enough -- mods (e.g. Arsenal Gunfighter's
        -- Home-key bayonet-form weapons) can register items directly under
        -- module Base instead of their own namespace, so fullName alone lies
        -- about origin. getModID() tracks the actual source mod.info the item
        -- was loaded from; vanilla items report "pz-vanilla" regardless of
        -- which module they declare. Confirmed via Item.java: modID =
        -- ScriptManager.getCurrentLoadFileMod(), independent of module name.
        if scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete()
                and scriptItem:getModID() == "pz-vanilla" then
            local cats = scriptItem:getCategories()
            for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
                if cats:contains(entry.category)
                        and (ALLOW_IMPROVISED[entry.category] or not cats:contains("Improvised")) then
                    table.insert(meleePools[entry.category], scriptItem:getFullName())
                    break -- one pool per item; first matching category wins
                end
            end
        elseif scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete() then
            rejectedModded = rejectedModded + 1
        end
    end
    print(LOG .. "rejected " .. rejectedModded .. " non-vanilla weapon items (modID check)")
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        print(LOG .. "pool built: " .. entry.category .. " = " .. #meleePools[entry.category] .. " items")
        if #meleePools[entry.category] == 0 then
            print(LOG .. "WARNING: empty pool for category " .. entry.category)
        end
    end
end

-- Weighted pick over entries carrying a .weight field. Total is computed per
-- call so both the 100-sum static tables and the server-built ranged pool
-- (arbitrary total) work with the same function.
local function pickWeighted(tbl)
    local total = 0
    for _, entry in ipairs(tbl) do
        total = total + entry.weight
    end
    if total <= 0 then return tbl[1] end
    local roll = ZombRand(total)
    local acc = 0
    for _, entry in ipairs(tbl) do
        acc = acc + entry.weight
        if roll < acc then return entry end
    end
    return tbl[#tbl] -- safety net
end

-- Resolve the melee pools to draw from, best source first.
local function resolvePools()
    if syncedPools then return syncedPools, "synced" end
    if not isClient() and t3RandomWeaponServer then
        -- SP (or any context where server lua is loaded): build directly from
        -- the distribution tables, no network round trip needed.
        syncedPools = t3RandomWeaponServer.BuildPools()
        return syncedPools, "local-server"
    end
    if not meleePools then buildMeleePools() end
    return meleePools, "fallback"
end

-- Resolve the ranged pool: Arsenal distro pool when available, vanilla static
-- table otherwise.
local function resolveRangedPool()
    if syncedRanged then return syncedRanged, "synced-arsenal" end
    if not isClient() and t3RandomWeaponServer then
        syncedRanged = t3RandomWeaponServer.BuildRangedPool()
        if syncedRanged then return syncedRanged, "local-server-arsenal" end
    end
    return t3RandomWeapon.RANGED_TABLE, "vanilla-static"
end

-- Roll category by weight, then uniform pick inside the category pool.
local function pickMeleeItem()
    local pools, source = resolvePools()
    local catEntry = pickWeighted(t3RandomWeapon.CATEGORY_TABLE)
    local pool = pools[catEntry.category]
    if not pool or #pool == 0 then
        print(LOG .. "ERROR: no items in category " .. tostring(catEntry.category) .. " (source=" .. source .. "), falling back to Base.Hammer")
        return "Base.Hammer", catEntry.category
    end
    local itemName = pool[ZombRand(#pool) + 1]
    print(LOG .. "rolled category=" .. catEntry.category .. " item=" .. itemName .. " (pool size " .. #pool .. ", source=" .. source .. ")")
    return itemName, catEntry.category
end

-- Read the donor name stashed on the box item's modData at grant time.
-- OnCreate(items, result, player): items = source items consumed by the recipe.
local function findDonor(items)
    if not items then return "" end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getModData then
            local donor = it:getModData().t3Donor
            if donor and donor ~= "" then return donor end
        end
    end
    return ""
end

-- Prefix a bare item name with a module. Weapon scripts store AmmoBox WITHOUT
-- a module prefix (confirmed: Item.java resolves magazineType only;
-- ItemPickerJava.java adds getAmmoBox() verbatim), so we qualify it with the
-- weapon's own module before AddItem.
local function qualifyItemName(name, moduleHint)
    if not name or name == "" then return nil end
    if string.match(name, "%.") then return name end
    return (moduleHint or "Base") .. "." .. name
end

local function grant(player, itemName, donor)
    local inv = player:getInventory()
    local weapon = inv:AddItem(itemName)
    if not weapon then
        print(LOG .. "ERROR: AddItem failed for " .. tostring(itemName))
        return
    end
    if donor ~= "" then
        weapon:setName(donor .. "'s " .. weapon:getDisplayName())
    end
    player:Say(weapon:getDisplayName() .. "!")

    -- Ammunition package: 2 magazines + 3 ammo boxes, resolved from the
    -- weapon's own script data. Melee weapons return nil for both getters,
    -- so this block is a no-op for the melee box. Firearms without a
    -- magazine (revolvers, shotguns) just skip the magazine part.
    local moduleHint = string.match(itemName, "^([^%.]+)") or "Base"
    local magType = weapon.getMagazineType and weapon:getMagazineType()
    if magType and magType ~= "" then
        for _ = 1, MAG_COUNT do
            if not inv:AddItem(magType) then
                print(LOG .. "WARNING: AddItem failed for magazine " .. tostring(magType))
                break
            end
        end
    end
    local rawBox = weapon.getAmmoBox and weapon:getAmmoBox()
    local boxName = qualifyItemName(rawBox, moduleHint)
    if boxName then
        for _ = 1, AMMO_BOX_COUNT do
            if not inv:AddItem(boxName) then
                print(LOG .. "WARNING: AddItem failed for ammo box " .. tostring(boxName))
                break
            end
        end
    else
        local ammoType = weapon.getAmmoType and weapon:getAmmoType()
        if ammoType and ammoType ~= "" then
            inv:AddItems(ammoType, FALLBACK_LOOSE_ROUNDS)
            print(LOG .. "no AmmoBox on " .. itemName .. ", granted " .. FALLBACK_LOOSE_ROUNDS .. " loose rounds of " .. ammoType)
        end
    end
end

-- Recipe OnCreate handlers -------------------------------------------------
-- Easter egg: 1% chance the melee box contains John Wick's Pencil instead of
-- a category roll. Item defined in t3_rewards_items.txt (Improvised category +
-- non-Base module keeps it out of the normal pools).
local EASTER_EGG_CHANCE = 1 -- percent
local EASTER_EGG_ITEM = "t3chzzkDonation.JohnWickPencil"

function t3RandomWeapon.OpenMeleeBox(items, result, player)
    if not player then return end
    local itemName
    if ZombRand(100) < EASTER_EGG_CHANCE then
        itemName = EASTER_EGG_ITEM
        print(LOG .. "EASTER EGG rolled: " .. itemName)
    else
        itemName = pickMeleeItem()
    end
    grant(player, itemName, findDonor(items))
end

function t3RandomWeapon.OpenRangedBox(items, result, player)
    if not player then return end
    local pool, source = resolveRangedPool()
    local entry = pickWeighted(pool)
    print(LOG .. "rolled ranged item=" .. entry.item .. " (pool size " .. #pool .. ", source=" .. source .. ")")
    grant(player, entry.item, findDonor(items))
end

-- ── MP pool sync ────────────────────────────────────────────────────────────
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuRandomWeapon" or command ~= "Pools" then return end
    if not args or not args.pools then
        print(LOG .. "WARNING: Pools command received without payload")
        return
    end
    syncedPools = args.pools
    local summary = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        local pool = syncedPools[entry.category]
        table.insert(summary, entry.category .. "=" .. tostring(pool and #pool or 0))
    end
    print(LOG .. "melee pools synced from server: " .. table.concat(summary, " "))
    if args.ranged then
        syncedRanged = args.ranged
        print(LOG .. "ranged pool synced from server: " .. #syncedRanged .. " firearms")
    else
        print(LOG .. "no ranged pool from server (no Arsenal); using vanilla table")
    end
end)

Events.OnGameStart.Add(function()
    if isClient() then
        print(LOG .. "requesting weapon pools from server")
        sendClientCommand("PongDuRandomWeapon", "RequestPools", {})
    end
end)
