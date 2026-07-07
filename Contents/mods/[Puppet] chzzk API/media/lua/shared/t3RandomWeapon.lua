-- t3RandomWeapon: random_weapon donation feature.
-- Donation grants a melee or ranged weapon box (50/50, decided in rewardManager).
-- Opening the box via the "Open Weapon Box" recipe rolls one weapon from the
-- weight table below (weights are integers summing to 100, ZombRand(100)).
-- Global table (no module return) so recipe OnCreate can resolve
-- "t3RandomWeapon.OpenMeleeBox" / "t3RandomWeapon.OpenRangedBox".

t3RandomWeapon = t3RandomWeapon or {}

-- ── Melee table (weights sum = 100) ─────────────────────────────────────────
t3RandomWeapon.MELEE_TABLE = {
    { item = "Base.Katana",           weight = 2  },
    { item = "Base.Sledgehammer",     weight = 3  },
    { item = "Base.MeatCleaver",      weight = 4  },
    { item = "Base.Machete",          weight = 5  },
    { item = "Base.Shovel",           weight = 6  },
    { item = "Base.FireAxe",          weight = 8  },
    { item = "Base.Axe",              weight = 8  },
    { item = "Base.BaseballBatNails", weight = 8  },
    { item = "Base.HandAxe",          weight = 10 },
    { item = "Base.Nightstick",       weight = 10 },
    { item = "Base.BaseballBat",      weight = 12 },
    { item = "Base.Crowbar",          weight = 12 },
    { item = "Base.Hammer",           weight = 12 },
}

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

local function grant(player, entry, donor)
    local inv = player:getInventory()
    local weapon = inv:AddItem(entry.item)
    if weapon then
        if donor ~= "" then
            weapon:setName(donor .. "'s " .. weapon:getDisplayName())
        end
        player:Say(weapon:getDisplayName() .. "!")
    end
    if entry.clip then inv:AddItem(entry.clip) end
    if entry.ammo then inv:AddItem(entry.ammo) end
end

-- Recipe OnCreate handlers -------------------------------------------------
function t3RandomWeapon.OpenMeleeBox(items, result, player)
    if not player then return end
    grant(player, pickWeighted(t3RandomWeapon.MELEE_TABLE), findDonor(items))
end

function t3RandomWeapon.OpenRangedBox(items, result, player)
    if not player then return end
    grant(player, pickWeighted(t3RandomWeapon.RANGED_TABLE), findDonor(items))
end
