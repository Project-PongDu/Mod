local handler = {}

local updateText    = require("utils/updateText")
local config        = require("config")
local moodle        = require("features/moodle")
local zombie        = require("features/zombie")
local global        = require("global")
local zone          = require("utils/zone")

-- Debuff moodle ticker: scrolls random text, then applies the debuff.  [.a]
function handler.a(_)
    global.textUpdateTimer = global.textUpdateTimer + getGameTime():getTimeDelta() * 1000
    if global.textUpdateTimer >= 200 then
        updateText.b()
        global.textUpdateTimer = 0
    end
    global.displayStartTime = global.displayStartTime + getGameTime():getTimeDelta() * 1000
    if global.displayStartTime >= config.textDisplayDuration then
        Events.OnTick.Remove(handler.a)
        local player = getPlayer()
        getSoundManager():PlaySound("ding", false, 1.0)
        moodle.b(player, global.chosenRandomText)
        global.textUpdateTimer = 0
        global.displayStartTime = 0
        global.processingEvent = false
    end
end

-- Buff moodle ticker: scrolls random text, then applies the buff.  [.b]
function handler.b(_)
    global.textUpdateTimer = global.textUpdateTimer + getGameTime():getTimeDelta() * 1000
    if global.textUpdateTimer >= 200 then
        updateText.a()
        global.textUpdateTimer = 0
    end
    global.displayStartTime = global.displayStartTime + getGameTime():getTimeDelta() * 1000
    if global.displayStartTime >= config.textDisplayDuration then
        Events.OnTick.Remove(handler.b)
        local player = getPlayer()
        getSoundManager():PlaySound("ding", false, 1.0)
        moodle.a(player, global.chosenRandomText)
        global.textUpdateTimer = 0
        global.displayStartTime = 0
        global.processingEvent = false
    end
end

-- Zombie roulette: pick a random count, then spawn after a short delay.  [.c]
-- B version: no scrolling display; counts are zombie1->2 ... zombie5->6;
-- added a getPlayer nil-guard and a 500ms delay before spawning.
function handler.c()
    Events.OnTick.Remove(handler.c)
    global.isTextUpdateEventAdded = false

    local player = getPlayer()
    if not player then global.processingEvent = false return end

    updateText.c()
    getSoundManager():PlaySound("ding", false, 1.0)

    local amount = global.chosenRandomText == "IGUI_zombie1" and 2 or
                   global.chosenRandomText == "IGUI_zombie2" and 3 or
                   global.chosenRandomText == "IGUI_zombie3" and 4 or
                   global.chosenRandomText == "IGUI_zombie4" and 5 or
                   global.chosenRandomText == "IGUI_zombie5" and 6 or 0
    local data = { amount = amount, sprint = 0, sender = global.currentSender or "" }
    global.currentSender = ""
    global.textUpdateTimer = 0
    global.displayStartTime = 0

    local elapsed = 0
    local function spawnDelay()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed >= 500 then
            Events.OnTick.Remove(spawnDelay)
            if zone.a(player) then
                table.insert(global.zombieSpawnQueue, data)
            else
                table.insert(global.zombieSpawnQueue, data)
                zombie.a()
            end
            global.processingEvent = false
        end
    end
    Events.OnTick.Add(spawnDelay)
end

return handler
