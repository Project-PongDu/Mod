local _a = {moodleMap = {
    ["IGUI_moodle_Type2"]  = {type = MoodleType.Bleeding},
    ["IGUI_moodle_Type6"]  = {type = MoodleType.Drunk},
    ["IGUI_moodle_Type7"]  = {type = MoodleType.Endurance},
    ["IGUI_moodle_Type8"]  = {type = MoodleType.FoodEaten},
    ["IGUI_moodle_Type11"] = {type = MoodleType.Hunger},
    ["IGUI_moodle_Type17"] = {type = MoodleType.Panic},
    ["IGUI_moodle_Type19"] = {type = MoodleType.Stress},
}}
local _b = require("constants")
local _c = require("global")

function _a.a(a, b)
    if not a then return end
    _c.b("applyMoodleEffect FUNCTION START")
    local c = a:getStats()
    local d = {
        [MoodleType.Bleeding] = function()
            local e = a:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
            e:setBleeding(true)
        end,
        [MoodleType.Drunk] = function()
            local e = c:getDrunkenness() + 30
            c:setDrunkenness(e)
        end,
        [MoodleType.Endurance] = function()
            c:setEndurance(c:getEndurance() - 0.3)
        end,
        [MoodleType.FoodEaten] = function()
            c:setHunger(c:getHunger() - 0.3)
        end,
        [MoodleType.Hunger] = function()
            c:setHunger(c:getHunger() + 0.3)
        end,
        [MoodleType.Panic] = function()
            c:setPanic(c:getPanic() + 30)
        end,
        [MoodleType.Stress] = function()
            c:setStress(c:getStress() + 0.3)
        end,
    }
    local e = _a.moodleMap[b]
    if e then
        local f = d[e.type]
        if f then f() end
    end
    _c.b("applyMoodleEffect FUNCTION END")
end

function _a.b(a, b)
    if not a then return end
    _c.b("applyMoodleBuffEffect FUNCTION START")
    local c = {
        ["IGUI_buff_moodle_Type6"]  = {type = MoodleType.Drunk},
        ["IGUI_buff_moodle_Type7"]  = {type = MoodleType.Endurance},
        ["IGUI_buff_moodle_Type8"]  = {type = MoodleType.FoodEaten},
        ["IGUI_buff_moodle_Type11"] = {type = MoodleType.Hunger},
        ["IGUI_buff_moodle_Type17"] = {type = MoodleType.Panic},
        ["IGUI_buff_moodle_Type19"] = {type = MoodleType.Stress},
    }
    local d = a:getStats()
    local e = {
        [MoodleType.Bleeding] = function()
            local f = a:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
            f:setBleeding(true)
        end,
        [MoodleType.Drunk] = function()
            d:setDrunkenness(d:getDrunkenness() - 30)
        end,
        [MoodleType.Endurance] = function()
            d:setEndurance(d:getEndurance() + 0.3)
        end,
        [MoodleType.FoodEaten] = function()
            d:setHunger(d:getHunger() - 0.3)
        end,
        [MoodleType.Panic] = function()
            d:setPanic(d:getPanic() - 30)
        end,
        [MoodleType.Stress] = function()
            d:setStress(d:getStress() - 0.3)
        end,
    }
    local f = c[b]
    if f then
        local g = e[f.type]
        if g then g() end
    end
    _c.b("applyMoodleBuffEffect FUNCTION END")
end
return _a
