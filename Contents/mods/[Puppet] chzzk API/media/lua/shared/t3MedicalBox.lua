-- t3MedicalBox: medical_box donation feature (server-tier).
--
-- The donation itself grants one box to EVERY connected player (see
-- server/PongDuMedBoxServer.lua + client/features/medicalbox.lua). This file
-- only handles what happens when a box is opened: grant every enabled
-- item (4 syringes + Zomboxivir vaccine) from t3_rewards_items.txt at once
-- (no random pick anymore).
--
-- The grant happens per box, on the opening client. The sandbox options
-- (PongDu.MedBox_Allow_*, read at open time, never cached) decide which
-- items are included; toggling one off in-session takes effect on the
-- next box opened.
--
-- Global table (no module return) so the recipe OnCreate can resolve
-- "t3MedicalBox.OpenBox". Same pattern as t3RandomWeapon / t3VehicleDrop.

t3MedicalBox = t3MedicalBox or {}

local LOG = "[PongDu][MedicalBox] "

local MODULE = "t3chzzkDonation."

-- item: script item name (module prefix added at grant time)
-- option: sandbox option suffix under SandboxVars.PongDu (boolean toggle)
--
-- Zomboxivir is the same item the standalone "vaccine" donation grants
-- (rewardManager.lua giveSupply("Zomboxivir", ...)); here it's just another
-- pool entry, gated by its own MedBox_Allow_Vaccine toggle independent of
-- the standalone vaccine donation.
t3MedicalBox.ITEMS = {
    { item = "Syringe_Adrenaline",  option = "MedBox_Allow_Adrenaline"  },
    { item = "Syringe_Doxycycline", option = "MedBox_Allow_Doxycycline" },
    { item = "Syringe_Morphine",    option = "MedBox_Allow_Morphine"    },
    { item = "Syringe_Emergency",   option = "MedBox_Allow_Emergency"   },
    { item = "Zomboxivir",          option = "MedBox_Allow_Vaccine"     },
}

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

-- Every medbox item enabled in the sandbox options. Read here (use time), not
-- at file load, so mid-session changes take effect immediately. Returns a
-- list of bare item names (empty when all five are off).
function t3MedicalBox.rollAll()
    local pool = {}
    for _, entry in ipairs(t3MedicalBox.ITEMS) do
        if SandboxVars.PongDu[entry.option] then
            table.insert(pool, entry.item)
        end
    end

    if #pool == 0 then
        print(LOG .. "open aborted: every medbox item is disabled in sandbox options")
    end

    return pool
end

-- Recipe OnCreate handler --------------------------------------------------
-- Grants every currently-enabled medbox item (syringes + vaccine) at once
-- (no longer a random pick).
function t3MedicalBox.OpenBox(items, result, player)
    if not player then
        print(LOG .. "OpenBox aborted: player is nil")
        return
    end

    local pool = t3MedicalBox.rollAll()
    if #pool == 0 then return end

    local donor = findDonor(items)
    local inv = player:getInventory()
    local grantedNames = {}
    local grantedTypes = {}

    for _, itemType in ipairs(pool) do
        local grantedItem = inv:AddItem(MODULE .. itemType)
        if not grantedItem then
            print(LOG .. "ERROR: AddItem failed for " .. MODULE .. itemType)
        else
            if donor ~= "" then
                grantedItem:setName(donor .. "'s " .. grantedItem:getDisplayName())
            end
            table.insert(grantedNames, grantedItem:getDisplayName())
            table.insert(grantedTypes, itemType)
        end
    end

    -- if #grantedNames > 0 then
    --     player:Say(table.concat(grantedNames, ", ") .. "!")
    -- end

    print(LOG .. "box opened: items=" .. table.concat(grantedTypes, ",") .. ", donor=" .. tostring(donor))
end
