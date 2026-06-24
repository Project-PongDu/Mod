local _a = {}
local _b = require("config")
local _c = require("global")
require("ISUI/ISPanel")

local ReturnTimerDisplay = ISPanel:derive("ReturnTimerDisplay")
local _e  -- tick handler reference

function ReturnTimerDisplay:new(a, b)
    local c = getCore():getScreenWidth()
    local d = getCore():getScreenHeight()
    local e = ISPanel:new(c / 2 - 50, d - 120, 100, 25)
    setmetatable(e, self)
    self.__index = self
    e.player     = a
    e.maxTime    = b
    e.currentTime = b
    e:noBackground()
    return e
end
function ReturnTimerDisplay:render()
    local a = math.floor(self.currentTime / 60)
    local b = math.floor(a / 60)
    local c = a % 60
    self:drawTextCentre(string.format("%02d:%02d", b, c), self.width / 2, 0, 1, 1, 1, 1, UIFont.Small)
end
function ReturnTimerDisplay:update()
    local a = self.player:getModData()
    self.currentTime = a.returnTime or 0
    if self.currentTime <= 0 then
        self:removeFromUIManager()
    end
end

-- Show the return timer UI if there's time remaining.
function _a.a(a)
    local b = a:getModData()
    local c = b.returnTime or 0
    if c > 0 then
        local d = ReturnTimerDisplay:new(a, c)
        d:addToUIManager()
        d:setVisible(true)
    end
end

-- Teleport player to Santa's Land and start the return countdown.
function _a.b(a)
    local b = a:getModData()
    if not b.originalPosition then
        b.originalPosition = {x = a:getX(), y = a:getY(), z = a:getZ()}
    end
    local v = a:getVehicle()
    if v then v:removePassenger(a) end
    a:setX(14298)
    a:setY(786)
    a:setZ(0)
    a:setLx(a:getX())
    a:setLy(a:getY())
    a:setLz(a:getZ())
    getWorld():update()
    local c = _b.SantaLandTime
    if not b.isTimerInitialized then
        b.returnTime = 0
        b.isTimerInitialized = true
    end
    b.returnTime = b.returnTime + c
    b.isDead      = false
    b.hasReturned = false
    b.hasMoved    = true
    if not b.tickHandlerRegistered then
        b.tickHandlerRegistered = false
    end
    if b.tickHandlerRegistered then
        Events.OnTick.Remove(_e)
    end

    local function returnPlayer()
        if not b.isDead and not b.hasReturned then
            getSoundManager():PlaySound("exile_exit", false, 1.0)
            a:setX(b.originalPosition.x)
            a:setY(b.originalPosition.y)
            a:setZ(b.originalPosition.z)
            a:setLx(a:getX())
            a:setLy(a:getY())
            a:setLz(a:getZ())
            getWorld():update()
            b.returnTime        = 0
            b.hasReturned       = true
            b.hasMoved          = false
            b.originalPosition  = nil
            b.isTimerInitialized = false
            Events.OnTick.Remove(_e)
            b.tickHandlerRegistered = false
        end
    end

    local function onDeath()
        b.isDead             = true
        b.returnTime         = 0
        b.hasMoved           = false
        b.originalPosition   = nil
        b.isTimerInitialized = false
        Events.OnTick.Remove(_e)
        b.tickHandlerRegistered = false
    end
    Events.OnPlayerDeath.Add(onDeath)

    _e = function()
        if b.returnTime then
            b.returnTime = b.returnTime - 1
            if b.returnTime <= 0 then
                b.returnTime = 0
                returnPlayer()
                Events.OnTick.Remove(_e)
                b.tickHandlerRegistered = false
            end
        end
    end
    Events.OnTick.Add(_e)
    b.tickHandlerRegistered = true
    _a.a(a)
end
return _a
