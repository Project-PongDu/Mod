local _a = {}
local _b = require("constants")
local _c = require("global")

function _a.a()
    local a = ZombRand(1, #_b.IGUI_moodle_Types + 1)
    _c.chosenRandomText = _b.IGUI_moodle_Types[a]
    _c.player:Say(getText(_c.chosenRandomText))
end
function _a.b()
    local a = ZombRand(1, #_b.IGUI_buff_moodle_Types + 1)
    _c.chosenRandomText = _b.IGUI_buff_moodle_Types[a]
    _c.player:Say(getText(_c.chosenRandomText))
end
function _a.c()
    local a = ZombRand(1, #_b.IGUI_zombies + 1)
    _c.chosenRandomText = _b.IGUI_zombies[a]
    _c.player:Say(getText(_c.chosenRandomText))
end
return _a
