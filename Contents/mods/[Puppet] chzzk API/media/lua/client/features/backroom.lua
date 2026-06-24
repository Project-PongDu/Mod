local _a = {}
local _b = require("config")
local _c = require("global")
local _e  -- tick handler reference

local function saveOriginalPosition(a, b)
    if not b.originalPosition then
        b.originalPosition = {x = a:getX(), y = a:getY(), z = a:getZ()}
        ModData.transmit("originalPosition")
    end
end

local function movePlayer(a, pos)
    a:setX(pos.x)
    a:setY(pos.y)
    a:setZ(pos.z)
    a:setLx(pos.x)
    a:setLy(pos.y)
    a:setLz(pos.z)
    getWorld():update()
end

local function returnFromBackroom(a, b)
    if not b.isDead and not b.hasReturned then
        getSoundManager():PlaySound("glitch_reverse", false, 1.0)
        movePlayer(a, b.originalPosition)
        b.hasReturned           = true
        b.hasMoved              = false
        b.originalPosition      = nil
        Events.OnTick.Remove(_e)
        b.tickHandlerRegistered = false
    end
end

local function checkExit(a, b)
    local c, d, e = a:getX(), a:getY(), a:getZ()
    if c > 42 and c < 45 and d > 260 and d < 267 and e <= 0.5 then
        returnFromBackroom(a, b)
        a:setFallTime(0)
        Events.OnTick.Remove(_e)
        b.tickHandlerRegistered = false
    end
end

_e = function()
    local a = getPlayer()
    local b = a:getModData()
    checkExit(a, b)
end

-- Backroom spawn points
local spawnPoints = {
    {x = 50,  y = 50,  z = 5},
    {x = 106, y = 71,  z = 5},
    {x = 97,  y = 95,  z = 5},
    {x = 74,  y = 73,  z = 5},
    {x = 96,  y = 118, z = 5},
}

function _a.a(a)
    local b = a:getModData()
    saveOriginalPosition(a, b)
    local dest = spawnPoints[ZombRand(#spawnPoints) + 1]
    local v = a:getVehicle()
    if v then v:removePassenger(a) end
    movePlayer(a, dest)
    b.isDead                = false
    b.hasReturned           = false
    b.hasMoved              = true
    if b.tickHandlerRegistered then
        Events.OnTick.Remove(_e)
    end
    Events.OnTick.Add(_e)
    b.tickHandlerRegistered = true
end

local function onDeath()
    local a = getPlayer()
    local b = a:getModData()
    b.isDead                = true
    b.hasMoved              = false
    b.originalPosition      = nil
    Events.OnTick.Remove(_e)
    b.tickHandlerRegistered = false
end
Events.OnPlayerDeath.Add(onDeath)

local function onGameStart()
    local a = getPlayer()
    if a then
        ModData.request("originalPosition")
        local b, c = a:getX(), a:getY()
        if b >= 0 and b <= 300 and c >= 0 and c <= 300 then
            local d = a:getModData()
            Events.OnTick.Add(_e)
            d.tickHandlerRegistered = true
        end
    end
end
Events.OnGameStart.Add(onGameStart)
return _a
