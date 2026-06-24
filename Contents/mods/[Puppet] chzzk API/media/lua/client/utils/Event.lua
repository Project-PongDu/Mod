local _a = {}
local _b = require("utils/handler")
local _c = require("global")

function _a.a(a)
    _c.b("onMoodleEvent FUNCTION START")
    _c.textUpdateTimer = 0
    _c.displayStartTime = 0
    getSoundManager():PlaySound("slot", false, 1.0)
    if a then
        Events.OnTick.Add(_b.a)
    else
        Events.OnTick.Add(_b.b)
    end
    _c.b("onMoodleEvent FUNCTION END")
end

function _a.b(a)
    _c.b("onZombieEvent FUNCTION START")
    getSoundManager():PlaySound("slot", false, 1.0)
    Events.OnTick.Add(_b.c)
    _c.b("onZombieEvent FUNCTION END")
end
return _a
