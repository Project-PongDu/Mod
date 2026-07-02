local rewardManager = {}

local bandit     = require("features/hitman")
local teleport   = require("features/teleport")
local backroom   = require("features/backroom")
local bombard    = require("features/bombard")
local eventUtils = require("utils/Event")
local zone       = require("utils/zone")
local zombie     = require("features/zombie")
local global     = require("global")

-- Spawn zombies, queueing the request if the player is still in a safe zone.
local function handleZombieSpawn(amount, sprint, sender)
    global.b(" handleZombieSpawn FUNCTION START")
    local data = { amount = amount, sprint = sprint, sender = sender or "" }
    if zone.a(global.player) then
        table.insert(global.zombieSpawnQueue, data)
        print(string.format("Zombie added to queue: Amount=%d Sprint=%d", amount, sprint))
    else
        table.insert(global.zombieSpawnQueue, data)
        zombie.a()
    end
    global.b(" handleZombieSpawn FUNCTION END")
end

-- Donation amount -> effect. (B tier layout: no 3000; 5000 = zombie roulette;
-- 10000 = 5 sprinters.)
local rewardHandlers = {
    ["1000"] = function()
        eventUtils.a(false)                           -- Debuff Roulette
    end,
    ["2000"] = function()
        eventUtils.a(true)                            -- Buff Roulette
    end,
    ["5000"] = function(sender)
        global.currentSender = sender or ""
        eventUtils.b(global.player)                   -- Zombie Roulette (random count)
    end,
    ["10000"] = function(sender)
        global.b(" 10000 FUNCTION START")
        handleZombieSpawn(5, 1, sender)               -- Sprinter x5
        global.processingEvent = false
        global.b(" 10000 FUNCTION END")
    end,
    ["20000"] = function(sender)
        bandit.a(11, sender)                          -- Bandit
        global.processingEvent = false
    end,
    ["35000"] = function(sender)
        local item = global.player:getInventory():AddItem("TheyKnew.Zomboxivir")
        if item then item:setName(sender .. "'s Vaccine") end   -- Vaccine
        global.processingEvent = false
    end,
    ["40000"] = function(sender)
        bandit.a(15, sender)                          -- Bandit (ranged)
        global.processingEvent = false
    end,
    ["50000"] = function()
        global.b(" 50000 FUNCTION START")
        getSoundManager():PlaySound("exile_enter", false, 1.0)
        teleport.b(global.player)                     -- Exile Teleport
        global.processingEvent = false
        global.b(" 50000 FUNCTION END")
    end,
    ["100000"] = function()
        global.b(" 100000 FUNCTION START")
        getSoundManager():PlaySound("glitch", false, 1.0)
        backroom.a(global.player)                     -- Backroom
        global.processingEvent = false
        global.b(" 100000 FUNCTION END")
    end,
    ["150000"] = function()
        global.b(" DONATION EXPLOSION START")
        getSoundManager():PlaySound("alert", false, 1.0)
        sendClientCommand("Schedule", "PlayAlert", {
            ["x"] = global.player:getX(),
            ["y"] = global.player:getY(),
            ["r"] = 40,
        })
        bombard.b(global.player)                      -- Missile Strike
        global.processingEvent = false
        global.b(" DONATION EXPLOSION END")
    end,
}

-- isValid(amount) -> true if this amount maps to a real reward tier.
function rewardManager.isValid(amount)
    return rewardHandlers[tostring(amount)] ~= nil
end

-- applyReward(amount, sender, callback)  [public name: .a]
-- 35000/50000/100000/150000 fire immediately even inside a safe zone
-- (vaccine, teleport, backroom, missile strike). Everything else waits until
-- the player leaves any safe zone, re-checking every 5 seconds.
function rewardManager.a(amount, sender, callback)
    global.player = getPlayer()
    if not global.player then return end
    global.stats = global.player:getStats()
    global.processingEvent = true

    -- These fire immediately even inside a safe zone:
    --   35000 Vaccine, 50000 Exile Teleport, 100000 Backroom, 150000 Missile Strike
    local skipZoneWait = (amount == "35000" or amount == "50000"
                       or amount == "100000" or amount == "150000")

    if not skipZoneWait and zone.a(global.player) then
        local elapsed = 0
        local function waitAndApply()
            elapsed = elapsed + getGameTime():getTimeDelta() * 1000
            if elapsed >= 5000 then
                elapsed = 0
                global.player = getPlayer()
                if not global.player then
                    Events.OnTick.Remove(waitAndApply)
                    global.processingEvent = false
                    return
                end
                if not zone.a(global.player) then
                    Events.OnTick.Remove(waitAndApply)
                    local handler = rewardHandlers[amount]
                    if handler then
                        handler(sender or "")
                    else
                        global.processingEvent = false
                    end
                else
                    if callback then callback() end
                end
            end
        end
        Events.OnTick.Add(waitAndApply)
    else
        local handler = rewardHandlers[amount]
        if handler then
            handler(sender or "")
        else
            global.processingEvent = false
        end
    end
end

-- queueReward(reward)  [public name: .b]
function rewardManager.b(reward)
    table.insert(global.rewardQueue, reward)
end

-- processQueue()  [public name: .c]
function rewardManager.c()
    if #global.rewardQueue == 0 or global.processingEvent then return end
    global.processingEvent = true

    local raw = table.remove(global.rewardQueue, 1)
    -- format: "username,amount,optionalmessage"
    local username, amount, message = raw:match("([^,]+),([^,]+),?([^,]*)")

    global.player = getPlayer()
    if not global.player then global.processingEvent = false return end
    global.stats = global.player:getStats()

    if message and message ~= "" then
        global.player:Say(message)
    end

    local handler = rewardHandlers[amount]
    if handler then handler() else global.processingEvent = false end
end

return rewardManager
