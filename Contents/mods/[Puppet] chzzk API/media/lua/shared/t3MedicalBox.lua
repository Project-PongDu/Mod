-- t3MedicalBox: medical_box donation feature (server-tier).
--
-- The donation itself grants one box to EVERY connected player (see
-- server/PongDuMedBoxServer.lua + client/features/medicalbox.lua). This file
-- only handles what happens when a box is opened: roll one of the four
-- syringes defined in t3_rewards_items.txt.
--
-- The roll happens per box, on the opening client, so two players who open
-- their boxes do not necessarily get the same syringe. All enabled syringes
-- have the same chance; the sandbox options (PongDu.MedBox_Allow_*, read at
-- roll time, never cached) only decide which ones are in the pool at all.
--
-- Global table (no module return) so the recipe OnCreate can resolve
-- "t3MedicalBox.OpenBox". Same pattern as t3RandomWeapon / t3VehicleDrop.

t3MedicalBox = t3MedicalBox or {}

local LOG = "[PongDu][MedicalBox] "

local MODULE = "t3chzzkDonation."

-- item: script item name (module prefix added at grant time)
-- option: sandbox option suffix under SandboxVars.PongDu (boolean toggle)
t3MedicalBox.SYRINGES = {
    { item = "Syringe_Adrenaline",  option = "MedBox_Allow_Adrenaline"  },
    { item = "Syringe_Doxycycline", option = "MedBox_Allow_Doxycycline" },
    { item = "Syringe_Morphine",    option = "MedBox_Allow_Morphine"    },
    { item = "Syringe_Emergency",   option = "MedBox_Allow_Emergency"   },
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

-- Uniform roll over the syringes enabled in the sandbox options. The options
-- are read here (use time), not at file load, so mid-session changes take
-- effect immediately. Returns the bare item name, or nil when all four are off.
function t3MedicalBox.roll()
    local pool = {}
    for _, entry in ipairs(t3MedicalBox.SYRINGES) do
        if SandboxVars.PongDu[entry.option] then
            table.insert(pool, entry.item)
        end
    end

    if #pool == 0 then
        print(LOG .. "roll aborted: every syringe is disabled in sandbox options")
        return nil
    end

    local itemType = pool[ZombRand(#pool) + 1]
    print(LOG .. "rolled item=" .. itemType .. " (pool=" .. tostring(#pool) .. ")")
    return itemType
end

-- Recipe OnCreate handler --------------------------------------------------
function t3MedicalBox.OpenBox(items, result, player)
    if not player then
        print(LOG .. "OpenBox aborted: player is nil")
        return
    end

    local itemType = t3MedicalBox.roll()
    if not itemType then return end

    local syringe = player:getInventory():AddItem(MODULE .. itemType)
    if not syringe then
        print(LOG .. "ERROR: AddItem failed for " .. MODULE .. itemType)
        return
    end

    local donor = findDonor(items)
    if donor ~= "" then
        syringe:setName(donor .. "'s " .. syringe:getDisplayName())
    end
    player:Say(syringe:getDisplayName() .. "!")

    print(LOG .. "box opened: item=" .. itemType .. ", donor=" .. tostring(donor))
end
