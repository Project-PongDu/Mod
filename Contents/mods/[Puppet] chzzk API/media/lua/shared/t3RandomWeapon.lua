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
-- Ranged box: static weight table (clip/ammo pairing needs manual data).
--
-- Global table (no module return) so recipe OnCreate can resolve
-- "t3RandomWeapon.OpenMeleeBox" / "t3RandomWeapon.OpenRangedBox".

t3RandomWeapon = t3RandomWeapon or {}

local LOG = "[PongDu][RandomWeapon] "

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

-- ── Ranged table (weights sum = 100) ────────────────────────────────────────
-- clip/ammo pairings verified against vanilla ProceduralDistributions
-- (PistolCase1~3, RevolverCase1~3, RifleCase1~3).
t3RandomWeapon.RANGED_TABLE = {
    { item = "Base.AssaultRifle",       weight = 3,  clip = "Base.556Clip",  ammo = "Base.556Box"          },
    { item = "Base.AssaultRifle2",      weight = 4,  clip = "Base.M14Clip",  ammo = "Base.308Box"          },
    { item = "Base.Revolver_Long",      weight = 4,                          ammo = "Base.Bullets44Box"    },
    { item = "Base.Pistol3",            weight = 5,  clip = "Base.44Clip",   ammo = "Base.Bullets44Box"    },
    { item = "Base.Revolver_Short",     weight = 6,                          ammo = "Base.Bullets38Box"    },
    { item = "Base.HuntingRifle",       weight = 8,  clip = "Base.308Clip",  ammo = "Base.308Box"          },
    { item = "Base.DoubleBarrelShotgun", weight = 8,                         ammo = "Base.ShotgunShellsBox" },
    { item = "Base.VarmintRifle",       weight = 10, clip = "Base.223Clip",  ammo = "Base.223Box"          },
    { item = "Base.Revolver",           weight = 10,                         ammo = "Base.Bullets45Box"    },
    { item = "Base.Shotgun",            weight = 12,                         ammo = "Base.ShotgunShellsBox" },
    { item = "Base.Pistol2",            weight = 12, clip = "Base.45Clip",   ammo = "Base.Bullets45Box"    },
    { item = "Base.Pistol",             weight = 18, clip = "Base.9mmClip",  ammo = "Base.Bullets9mmBox"   },
}

-- ── Melee pool cache ────────────────────────────────────────────────────────
-- category name -> array of full item names ("Base.Katana"). Built lazily on
-- first melee box open (script items are fully loaded by then).
local meleePools = nil

local function buildMeleePools()
    meleePools = {}
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        meleePools[entry.category] = {}
    end
    local allItems = getScriptManager():getAllItems()
    for i = 1, allItems:size() do
        local scriptItem = allItems:get(i - 1)
        if scriptItem:getTypeString() == "Weapon" and not scriptItem:getObsolete() then
            local cats = scriptItem:getCategories()
            for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
                if cats:contains(entry.category)
                        and (ALLOW_IMPROVISED[entry.category] or not cats:contains("Improvised")) then
                    table.insert(meleePools[entry.category], scriptItem:getFullName())
                    break -- one pool per item; first matching category wins
                end
            end
        end
    end
    for _, entry in ipairs(t3RandomWeapon.CATEGORY_TABLE) do
        print(LOG .. "pool built: " .. entry.category .. " = " .. #meleePools[entry.category] .. " items")
        if #meleePools[entry.category] == 0 then
            print(LOG .. "WARNING: empty pool for category " .. entry.category)
        end
    end
end

-- Weighted pick. Weights must sum to 100.
local function pickWeighted(tbl)
    local roll = ZombRand(100)
    local acc = 0
    for _, entry in ipairs(tbl) do
        acc = acc + entry.weight
        if roll < acc then return entry end
    end
    return tbl[#tbl] -- safety net
end

-- Roll category by weight, then uniform pick inside the category pool.
local function pickMeleeItem()
    if not meleePools then buildMeleePools() end
    local catEntry = pickWeighted(t3RandomWeapon.CATEGORY_TABLE)
    local pool = meleePools[catEntry.category]
    if not pool or #pool == 0 then
        print(LOG .. "ERROR: no items in category " .. tostring(catEntry.category) .. ", falling back to Base.Hammer")
        return "Base.Hammer", catEntry.category
    end
    local itemName = pool[ZombRand(#pool) + 1]
    print(LOG .. "rolled category=" .. catEntry.category .. " item=" .. itemName .. " (pool size " .. #pool .. ")")
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

local function grant(player, itemName, donor, clip, ammo)
    local inv = player:getInventory()
    local weapon = inv:AddItem(itemName)
    if weapon then
        if donor ~= "" then
            weapon:setName(donor .. "'s " .. weapon:getDisplayName())
        end
        player:Say(weapon:getDisplayName() .. "!")
    else
        print(LOG .. "ERROR: AddItem failed for " .. tostring(itemName))
    end
    if clip then inv:AddItem(clip) end
    if ammo then inv:AddItem(ammo) end
end

-- Recipe OnCreate handlers -------------------------------------------------
function t3RandomWeapon.OpenMeleeBox(items, result, player)
    if not player then return end
    local itemName = pickMeleeItem()
    grant(player, itemName, findDonor(items))
end

function t3RandomWeapon.OpenRangedBox(items, result, player)
    if not player then return end
    local entry = pickWeighted(t3RandomWeapon.RANGED_TABLE)
    print(LOG .. "rolled ranged item=" .. entry.item)
    grant(player, entry.item, findDonor(items), entry.clip, entry.ammo)
end
