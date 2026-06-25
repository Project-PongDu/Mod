local _a = _a or {}
local _b = require("config")
require("ISUI/ISPanel")

local BombardTimerDisplay = ISPanel:derive("BombardTimerDisplay")
local _d  -- bomb tick handler reference

DOTex = DOTex or {}
DOTex.tex = nil
DOTex.alpha = 0
DOTex.speed = 0.018
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

        DOTex.tex   = getTexture("media/textures/mask_white.png") -- 원하는 텍스처
        DOTex.alpha = 2
        getSoundManager():PlaySound("day_one_kaboom", false, 1.0)

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
            -- 여기서는 사운드 제거 (예고음은 이미 타이머 480틱 조건에서 재생됨)
        elseif b == "PlayAlert" then
            -- 발동 시 알람은 그대로 유지
            getSoundManager():PlaySound("alert", false, 1.0)
        elseif b == "NearbyExplosion" then
            -- 근처 폭발 시 섬광 이펙트만 적용, 사운드는 제거
            local _p = getPlayer()
            if _p then
                local _bd = _p:getBodyDamage()
                _bd:setOverallBodyHealth(math.max(0, _bd:getOverallBodyHealth() - 40))
                _p:setBumpFall(true)
                _p:setBumpType("stagger")
            end

            DOTex.tex   = getTexture("media/textures/mask_white.png")
            DOTex.alpha = 2
            -- 사운드 제거, 실제 폭발은 triggerExplosion()에서만 day_one_kaboom 재생
        elseif b == "RefreshMap" then
            -- 폭격으로 서버가 추가한 그을린 바닥/잿더미 타일이 즉시 보이도록,
            -- 잠깐 기다렸다(서버가 추가한 오브젝트가 클라에 도착할 시간 확보) 반경 내 모든 칸의
            -- 렌더 슬라이스를 더럽혀 강제로 다시 그리게 한다. (DirtySlice = 해당 칸 렌더 캐시 무효화)
            local cx = tonumber(c.x)
            local cy = tonumber(c.y)
            local r  = tonumber(c.r) or 55
            if cx and cy then
                local delay = 15   -- í±: ìë²ê° ì¶ê°í ì¤ë¸ì í¸ê° í´ë¼ì ëì°©í  ìê° íë³´
                local sweep
                sweep = function()
                    delay = delay - 1
                    if delay > 0 then return end
                    Events.OnTick.Remove(sweep)
                    local cell = getCell()
                    if not cell then return end
                    local r2 = r * r
                    for floor = 0, 1 do
                        for dy = -r, r do
                            for dx = -r, r do
                                if dx * dx + dy * dy < r2 then
                                    local sq = cell:getGridSquare(cx + dx, cy + dy, floor)
                                    if sq then sq:DirtySlice() end
                                end
                            end
                        end
                    end
                end
                Events.OnTick.Add(sweep)
            end
        end
    end
end)

return _a
