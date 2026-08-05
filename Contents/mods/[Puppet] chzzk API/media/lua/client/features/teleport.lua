-- teleport.lua : 산타마을 유배 (exile)  [비활성]
--
-- 미사용 결정으로 기능 전체를 비활성화한다. rewardManager 쪽 핸들러는
-- featureId "exile"을 유효하게 남겨두되(퐁듀 런처의 amount->featureId 매핑이
-- 깨지지 않도록) 아무것도 실행하지 않고, 이 파일은 통째로 주석 처리한다.
--
-- 파일 자체를 비워두지 않고 블록 주석으로 보존하는 이유:
--   1) PZ는 media/lua/client 하위 .lua를 전부 자동 로드하므로, 코드를 남겨두면
--      top-level의 Events.OnTick.Add(onTickRecovery) 같은 등록이 계속 살아난다.
--      require 를 지우는 것만으로는 비활성화되지 않는다.
--   2) 재활성화 시 아래 블록 주석만 풀면 그대로 복원된다.
--
-- [주의] 재활성화한다면 forceExitVehicle 에 triggerEvent("OnExitVehicle", p) 를
-- 반드시 추가할 것. 없으면 운전석에서 발동 시 ISVehicleDashboard 가
-- setVehicle(nil) 을 못 받아 대시보드 UI 가 화면에 남는다.

--[[
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
    e.player      = a
    e.maxTime     = b
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

-- 차량 탑승 중이면 강제 하차. B41엔 removePassenger가 없고 exit(chr)가 정석:
-- clearPassenger + setVehicle(nil) + collidable 복구 + MP sendExit 동기화까지 처리
-- (바닐라 ISExitVehicle:perform 참조).
local function forceExitVehicle(p)
    local v = p:getVehicle()
    if not v then return end
    v:exit(p)
    p:PlayAnim("Idle")
    _c.b(" exile: forced exit from vehicle before teleport")
end

-- 복귀 처리
local function doReturn(a, b)
    if b.isDead or b.hasReturned then return end
    forceExitVehicle(a)
    getSoundManager():PlaySound("exile_exit", false, 1.0)
    if b.originalPosition then
        a:setX(b.originalPosition.x)
        a:setY(b.originalPosition.y)
        a:setZ(b.originalPosition.z)
        a:setLx(a:getX())
        a:setLy(a:getY())
        a:setLz(a:getZ())
        getWorld():update()
    end
    b.returnTime        = 0
    b.hasReturned       = true
    b.hasMoved          = false
    b.originalPosition  = nil
end

-- 틱 핸들러 등록 (재접속 복구와 신규 발동 공용)
local function startTickHandler(a, b)
    if b.tickHandlerRegistered then
        Events.OnTick.Remove(_e)
    end
    _e = function()
        if b.returnTime then
            b.returnTime = b.returnTime - 1
            if b.returnTime <= 0 then
                b.returnTime = 0
                doReturn(a, b)
                Events.OnTick.Remove(_e)
                b.tickHandlerRegistered = false
            end
        end
    end
    Events.OnTick.Add(_e)
    b.tickHandlerRegistered = true
end

-- Teleport player to Santa's Land and start the return countdown.
function _a.b(a)
    local b = a:getModData()
    if not b.originalPosition then
        b.originalPosition = {x = a:getX(), y = a:getY(), z = a:getZ()}
    end
    forceExitVehicle(a)
    a:setX(14298)
    a:setY(786)
    a:setZ(0)
    a:setLx(a:getX())
    a:setLy(a:getY())
    a:setLz(a:getZ())
    getWorld():update()

    -- 유배 중 추가 후원 시 시간 누적
    b.returnTime = (b.returnTime or 0) + _b.SantaLandTime
    b.isDead     = false
    b.hasReturned = false
    b.hasMoved   = true

    local function onDeath()
        b.isDead            = true
        b.returnTime        = 0
        b.hasMoved          = false
        b.originalPosition  = nil
        if b.tickHandlerRegistered then
            Events.OnTick.Remove(_e)
            b.tickHandlerRegistered = false
        end
    end
    Events.OnPlayerDeath.Add(onDeath)

    startTickHandler(a, b)
    _a.a(a)
end

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
    if b.returnTime and b.returnTime > 0 and not b.hasReturned and not b.isDead then
        _a.a(a)
        startTickHandler(a, b)
    end
    _recoveryDone = true
    Events.OnTick.Remove(onTickRecovery)
end
Events.OnTick.Add(onTickRecovery)

return _a
]]
