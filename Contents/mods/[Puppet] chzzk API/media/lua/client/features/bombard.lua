local _a = _a or {}
local _b = require("config")
require("ISUI/ISPanel")

local BombardTimerDisplay = ISPanel:derive("BombardTimerDisplay")
local _d  -- bomb tick handler reference

DOTex = DOTex or {}
DOTex.tex = nil
DOTex.alpha = 0
DOTex.speed = 0.05
DOTex.screenWidth  = getCore():getScreenWidth()
DOTex.screenHeight = getCore():getScreenHeight()

DOTex.Blast = function()
    if not isIngameState() then return end
    if DOTex.alpha == 0 then return end
    if not DOTex.tex then return end
    local a = getSpecificPlayer(0)
    if a == nil then return end
    local b = DOTex.speed * getGameSpeed()
    local c = 1
    local d = DOTex.alpha
    if d > 1 then d = 1 end
    UIManager.DrawTexture(DOTex.tex, 0, 0, DOTex.screenWidth * c, DOTex.screenHeight * c, d)
    DOTex.alpha = DOTex.alpha - b
    if DOTex.alpha < 0 then DOTex.alpha = 0 end
end
DOTex.SizeChange = function(a, b, c, d)
    DOTex.screenWidth  = c
    DOTex.screenHeight = d
end
Events.OnPreUIDraw.Add(DOTex.Blast)
Events.OnResolutionChange.Add(DOTex.SizeChange)

function BombardTimerDisplay:new(a, b)
    local c = getCore():getScreenWidth()
    local d = getCore():getScreenHeight()
    local e = ISPanel:new(c / 2 - 50, d - 150, 100, 25)
    setmetatable(e, self)
    self.__index = self
    e.player      = a
    e.maxTime     = b
    e.currentTime = b
    e:noBackground()
    return e
end
function BombardTimerDisplay:render()
    local a = math.floor(self.currentTime / 60)
    local b = math.floor(a / 60)
    local c = a % 60
    self:drawTextCentre(string.format("%02d:%02d", b, c), self.width / 2, 0, 1, 1, 1, 1, UIFont.Small)
end
function BombardTimerDisplay:update()
    local a = self.player:getModData()
    self.currentTime = a.bombTimer or 0
    if self.currentTime <= 0 then
        self:removeFromUIManager()
    end
end

-- Show bomb timer UI if there's time remaining.
function _a.a(a)
    local b = a:getModData()
    local c = b.bombTimer or 0
    if c > 0 then
        local d = BombardTimerDisplay:new(a, c)
        d:addToUIManager()
        d:setVisible(true)
    end
end

-- Activate the timed bomb on the player.
_a.b = function(a)
    local b = a:getModData()
    local c = _b.KaboomTime
    if not b.bombTimerInitialized then
        b.bombTimer            = 0
        b.bombTimerInitialized = true
    end
    b.bombTimer = b.bombTimer + c
    if not b.timeBombActivated then
        b.timeBombActivated = false
    end

    -- Explosion sequence run when timer reaches zero.
    local function triggerExplosion()
        local e = a:getX()
        local f = a:getY()
        -- Load explosion sprite frames.
        local frames = {}
        for h = 1, 17 do
            frames[h] = getTexture(string.format("media/textures/textures/FX/explobig/%03d.png", h))
        end
        DOTex.speed = 0
        DOTex.tex   = frames[1]
        DOTex.alpha = 1
        local frameIdx, frameDelay = 1, 0
        local function advanceFrame()
            frameDelay = frameDelay + 1
            if frameDelay >= 3 then
                frameDelay = 0
                frameIdx   = frameIdx + 1
                if frameIdx > #frames then
                    Events.OnTick.Remove(advanceFrame)
                    DOTex.alpha = 0
                    DOTex.speed = 0.018
                else
                    DOTex.tex = frames[frameIdx]
                end
            end
        end
        Events.OnTick.Add(advanceFrame)

        local radius = 55
        local payload = {}
        payload.r = radius
        sendClientCommand("Schedule", "Kaboom", payload)

        -- Kill nearby bandits.
        local bandits = BanditZombie and BanditZombie.GetAll and BanditZombie.GetAll() or {}
        for n, o in pairs(bandits) do
            local dist = math.sqrt(math.pow(o.x - e, 2) + math.pow(o.y - f, 2))
            if dist < radius then
                local q = BanditZombie.GetInstanceById(n)
                if q and q:isOutside() then
                    q:setCrawler(true)
                    q:setHealth(0)
                    q:clearAttachedItems()
                    q:changeState(ZombieOnGroundState.instance())
                    q:becomeCorpse()
                end
            end
        end

        -- Damage player if outside.
        if a:isOutside() then
            a:clearVariable("BumpFallType")
            a:setBumpType("stagger")
            a:setBumpFall(true)
            a:setBumpFallType("pushedBehind")
            local bodyParts = {
                "Foot_L", "Foot_R",
                "ForeArm_L", "ForeArm_R",
                "Groin",
                "Hand_L", "Hand_R",
                "LowerLeg_L", "LowerLeg_R",
                "Torso_Lower", "Torso_Upper",
                "UpperArm_L", "UpperArm_R",
                "UpperLeg_L", "UpperLeg_R",
            }
            local head = a:getBodyDamage():getBodyPart(BodyPartType.Head)
            head:setBurned()
            head:setAdditionalPain(100)
            local chosen = {}
            while #chosen < 2 do
                local idx = ZombRand(1, #bodyParts + 1)
                local part = bodyParts[idx]
                if not chosen[part] then
                    table.insert(chosen, part)
                    chosen[part] = true
                end
            end
            for _, partName in ipairs(chosen) do
                local bp = a:getBodyDamage():getBodyPart(BodyPartType[partName])
                bp:setBurned()
                bp:setAdditionalPain(100)
            end
        end
        Events.OnTick.Remove(_d)
    end

    _d = function()
        if b.bombTimer then
            b.bombTimer = b.bombTimer - 1
            if b.bombTimer == 480 then
                getSoundManager():PlaySound("explosion", false, 1.0)
                sendClientCommand("Schedule", "PlayExplosion", {})
            end
            if b.bombTimer <= 0 then
                b.bombTimer         = 0
                Events.OnTick.Remove(_d)
                b.timeBombActivated = false
                triggerExplosion()
            end
        end
    end
    Events.OnTick.Add(_d)
    b.timeBombActivated = true
    _a.a(a)
end

Events.OnServerCommand.Add(function(a, b, c)
    if a == "Schedule" then
        if b == "PlayExplosion" then
            getSoundManager():PlaySound("explosion", false, 1.0)
        elseif b == "PlayAlert" then
            getSoundManager():PlaySound("alert", false, 1.0)
        elseif b == "NearbyExplosion" then
            getSoundManager():PlaySound("explosion", false, 1.0)
            local _p = getPlayer()
            if _p then
                local _bd = _p:getBodyDamage()
                _bd:setOverallBodyHealth(math.max(0, _bd:getOverallBodyHealth() - 40))
                _p:setBumpFall(true)
                _p:setBumpType("stagger")
            end
            local frames = {}
            for h = 1, 17 do
                frames[h] = getTexture(string.format("media/textures/textures/FX/explobig/%03d.png", h))
            end
            DOTex.speed = 0
            DOTex.tex   = frames[1]
            DOTex.alpha = 1
            local frameIdx, frameDelay = 1, 0
            local function advanceFrame()
                frameDelay = frameDelay + 1
                if frameDelay >= 3 then
                    frameDelay = 0
                    frameIdx   = frameIdx + 1
                    if frameIdx > #frames then
                        Events.OnTick.Remove(advanceFrame)
                        DOTex.alpha = 0
                        DOTex.speed = 0.018
                    else
                        DOTex.tex = frames[frameIdx]
                    end
                end
            end
            Events.OnTick.Add(advanceFrame)
        end
    end
end)
return _a
