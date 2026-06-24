local constants = {
    IGUI_zombies = {},
    IGUI_moodle_Types = {
        "IGUI_moodle_Type2",
        "IGUI_moodle_Type6",
        "IGUI_moodle_Type7",
        "IGUI_moodle_Type8",
        "IGUI_moodle_Type11",
        "IGUI_moodle_Type17",
        "IGUI_moodle_Type19",
    },
    IGUI_buff_moodle_Types = {
        "IGUI_buff_moodle_Type6",
        "IGUI_buff_moodle_Type7",
        "IGUI_buff_moodle_Type8",
        "IGUI_buff_moodle_Type11",
        "IGUI_buff_moodle_Type17",
        "IGUI_buff_moodle_Type19",
    },
}

-- Zombie roulette weights. B version: uniform 20 each.
-- (Original was skewed 43/21/18/13/5 — favoured smaller counts.)
for _ = 1, 20 do table.insert(constants.IGUI_zombies, "IGUI_zombie1") end
for _ = 1, 20 do table.insert(constants.IGUI_zombies, "IGUI_zombie2") end
for _ = 1, 20 do table.insert(constants.IGUI_zombies, "IGUI_zombie3") end
for _ = 1, 20 do table.insert(constants.IGUI_zombies, "IGUI_zombie4") end
for _ = 1, 20 do table.insert(constants.IGUI_zombies, "IGUI_zombie5") end

return constants
