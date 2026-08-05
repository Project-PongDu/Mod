-- backroom.lua : 백룸 탈출 (backroom)  [비활성]
--
-- 미사용 결정으로 기능 전체를 비활성화한다. rewardManager 쪽 핸들러는
-- featureId "backroom"을 유효하게 남겨두되(퐁듀 런처의 amount->featureId 매핑이
-- 깨지지 않도록) 아무것도 실행하지 않고, 이 파일은 통째로 주석 처리한다.
--
-- 파일 자체를 비워두지 않고 블록 주석으로 보존하는 이유:
--   1) PZ는 media/lua/client 하위 .lua를 전부 자동 로드하므로, 코드를 남겨두면
--      top-level의 Events.OnGameStart.Add(onGameStart) / OnPlayerDeath 등록이
--      계속 살아난다. require 를 지우는 것만으로는 비활성화되지 않는다.
--   2) 재활성화 시 아래 블록 주석만 풀면 그대로 복원된다.
--
-- [주의] 재활성화 전에 반드시 고칠 것: 아래 원본 코드의 v:removePassenger(a) 는
-- B41 BaseVehicle 에 존재하지 않는 메서드다(41.78.19 전체 소스 확인). 차량 탑승
-- 중 발동하면 즉시 런타임 에러로 텔레포트가 중단된다. teleport.lua /
-- randomteleport.lua 와 동일하게 v:exit(a) + PlayAnim("Idle") +
-- triggerEvent("OnExitVehicle", a) 로 교체해야 한다.

--[[
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
]]
