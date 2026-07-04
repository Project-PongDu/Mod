local _a = _a or {}
local _b = require("config")
require("ISUI/ISPanel")

local BombardTimerDisplay = ISPanel:derive("BombardTimerDisplay")

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
-- Blast injury applied LOCALLY on each affected client (donee + nearby players
-- in range). Only injures a player who is outside; shared so everyone caught in
-- the blast takes the same damage.
local function applyBlastInjury(p)
    if not p or not p:isOutside() then return end
    p:clearVariable("BumpFallType")
    p:setBumpType("stagger")
    p:setBumpFall(true)
    p:setBumpFallType("pushedBehind")
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
    local bd = p:getBodyDamage()
    local function pickParts(n)
        local out, seen = {}, {}
        while #out < n do
            local name = bodyParts[ZombRand(1, #bodyParts + 1)]
            if not seen[name] then
                seen[name] = true
                out[#out + 1] = name
            end
        end
        return out
    end
    local head = bd:getBodyPart(BodyPartType.Head)
    head:setBurned()
    head:setAdditionalPain(100)
    for _, name in ipairs(pickParts(4)) do
        bd:getBodyPart(BodyPartType[name]):setScratched(true, true)
    end
    for _, name in ipairs(pickParts(1)) do
        bd:getBodyPart(BodyPartType[name]):generateDeepWound()
    end
    for _, name in ipairs(pickParts(1)) do
        bd:getBodyPart(BodyPartType[name]):setCut(true, true)
    end
end

-- 반경 내 좀비 킬 (이 클라이언트가 소유한 좀비만).
-- B41 멀티에서 좀비는 클라이언트 권한이므로, 소유 클라가 정상 킬 시퀀스
-- (setAttackedBy 포함, ZADie와 동일)로 죽여야 서버/저장에 죽음이 영구 반영된다.
-- 서버사이드 setHealth/becomeCorpse는 소유 클라의 동기화 패킷에 덮여 무효.
local function killZombiesAround(cx, cy, radius)
    local cell = getCell()
    if not cell then return end
    local zl = cell:getZombieList()
    if not zl then return end
    for i = zl:size() - 1, 0, -1 do
        local z = zl:get(i)
        if z and not z:isDead() and not z:isRemoteZombie() and z:isOutside() then
            local dist = math.sqrt(math.pow(z:getX() - cx, 2) + math.pow(z:getY() - cy, 2))
            if dist < radius then
                z:setCrawler(true)
                z:setHealth(0)
                z:clearAttachedItems()
                z:changeState(ZombieOnGroundState.instance())
                z:setAttackedBy(cell:getFakeZombieForHit())
                z:becomeCorpse()
            end
        end
    end
end

-- 폭발 처리 공용 함수
local function doExplosion(a, b, handler, afterExplode)
    local e = a:getX()
    local f = a:getY()

    DOTex.tex   = getTexture("media/textures/mask_white.png")
    DOTex.alpha = 2
    getSoundManager():PlaySound("day_one_kaboom", false, 1.0)

    -- 폭격 전용 반경 (Donation_BombardRadius, 5~60, 기본 55). 부활 반경과는 별개 변수.
    -- SandboxVars는 파일 로드 시점엔 비어있을 수 있으므로 사용 시점에 읽는다.
    local sv = SandboxVars and SandboxVars.Hitmans
    local radius = (sv and tonumber(sv.Donation_BombardRadius)) or 55
    sendClientCommand("Schedule", "Kaboom", {r = radius})

    killZombiesAround(e, f, radius)

    applyBlastInjury(a)
    Events.OnTick.Remove(handler)
    b.timeBombActivated = false

    if afterExplode then afterExplode() end
end

_a.b = function(a)
    local b = a:getModData()

    b.bombPending = b.bombPending or 0
    if b.timeBombActivated then
        b.bombPending = b.bombPending + 1
        return
    end

    local function startBomb()
        b.bombTimer         = _b.KaboomTime
        b.timeBombActivated = true

        local handler
        handler = function()
            if b.bombTimer then
                b.bombTimer = b.bombTimer - 1
                if b.bombTimer == 480 then
                    getSoundManager():PlaySound("explosion", false, 1.0)
                    sendClientCommand("Schedule", "PlayExplosion", {})
                end
                if b.bombTimer <= 0 then
                    b.bombTimer = 0
                    doExplosion(a, b, handler, function()
                        if (b.bombPending or 0) > 0 then
                            b.bombPending = b.bombPending - 1
                            startBomb()
                        end
                    end)
                end
            end
        end
        Events.OnTick.Add(handler)
        _a.a(a)
    end

    startBomb()
end

Events.OnServerCommand.Add(function(a, b, c)
    if a == "Schedule" then
        if b == "PlayExplosion" then
            -- 예고음은 타이머 480틱 조건에서 재생됨
        elseif b == "PlayAlert" then
            getSoundManager():PlaySound("alert", false, 1.0)
        elseif b == "NearbyExplosion" then
            -- 서버가 전 클라에 브로드캐스트 (x/y/r 포함).
            -- 각 클라는 자기가 소유한 좀비를 반경 내에서 죽이고,
            -- 자기 캐릭터가 반경 안이면 부상/섬광도 적용한다.
            local cx = tonumber(c and c.x)
            local cy = tonumber(c and c.y)
            local cr = tonumber(c and c.r) or 55
            local me = getPlayer()
            if cx and cy then
                killZombiesAround(cx, cy, cr)
                if me then
                    local dist = math.sqrt(math.pow(me:getX() - cx, 2) + math.pow(me:getY() - cy, 2))
                    if dist < cr then
                        applyBlastInjury(me)
                        DOTex.tex   = getTexture("media/textures/mask_white.png")
                        DOTex.alpha = 2
                    end
                end
            else
                -- 구버전 서버(좌표 미포함) 호환: 기존 동작 유지
                applyBlastInjury(me)
                DOTex.tex   = getTexture("media/textures/mask_white.png")
                DOTex.alpha = 2
            end
        end
    end
end)

-- 재접속 복구: OnTick 안에서 플레이어 로드 확인 후 한 번만 실행
local _recoveryDone = false
local function onTickRecovery()
    if _recoveryDone then
        Events.OnTick.Remove(onTickRecovery)
        return
    end
    local a = getSpecificPlayer(0)
    if not a then return end
    local b = a:getModData()
    if b.bombTimer and b.bombTimer > 0 and b.timeBombActivated then
        _a.a(a)  -- UI 복원

        local handler
        handler = function()
            if b.bombTimer then
                b.bombTimer = b.bombTimer - 1
                if b.bombTimer == 480 then
                    getSoundManager():PlaySound("explosion", false, 1.0)
                    sendClientCommand("Schedule", "PlayExplosion", {})
                end
                if b.bombTimer <= 0 then
                    b.bombTimer = 0
                    doExplosion(a, b, handler, function()
                        if (b.bombPending or 0) > 0 then
                            b.bombPending = b.bombPending - 1
                            _a.b(a)
                        end
                    end)
                end
            end
        end
        Events.OnTick.Add(handler)
    end
    _recoveryDone = true
    Events.OnTick.Remove(onTickRecovery)
end
Events.OnTick.Add(onTickRecovery)

return _a

