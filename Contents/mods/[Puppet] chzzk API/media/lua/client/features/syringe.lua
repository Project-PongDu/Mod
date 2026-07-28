-- syringe.lua : 전투자극제 / 광범위 항생제 / 모르핀 / 응급 재생 주사기
--
-- AdrenalineSyringe(전투자극제) / DoxycyclineSyringe(광범위 항생제)는
-- FirstAidOverhaul 모드(BB_FAO_ISTimedAction / BB_FAO_ISFillInventoryContextMenu)에서
-- 이식. 원본은 EmptySyringe -> 각종 소재 조합으로 제작하는 레시피 체인이 있었으나,
-- 퐁듀는 후원으로 완성품을 바로 지급하는 구조라 레시피 전체를 제외했다. 그에 따라
-- "사용 후 빈 주사기 반환" 로직도 함께 제외한다(레시피가 없으면 빈 주사기가 아무
-- 데도 못 쓰이는 죽은 아이템이 되므로).
--
-- AdrenalineSyringe(전투자극제) : 피로/지구력 즉시 회복, 배고픔/갈증/패닉 증가.
--                                 빈사(HP<1) 시 소량 회복.
-- DoxycyclineSyringe(광범위 항생제) : 일반 질병(Sickness) + 식중독 + 상처 세균감염 치료.
--                                     좀비 감염(Knox Infection, bitten/IsInfected 계열)은
--                                     건드리지 않는다.
--
-- MorphineSyringe(모르핀) / EmergencyRegenSyringe(응급 재생)은 신규 추가. 둘 다
-- "지속시간" 개념이 있는데, 바닐라 PainEffect/PainReduction(BodyDamage.java)은
-- 프레임 단위로 게임속도 배율에 맞춰 감쇠하는 구조라 "정확히 인게임 N시간"을
-- 보장하려면 상수를 역산해야 하고 게임 패치로 조용히 틀어질 위험이 있다.
-- 대신 만료 시각(인게임 ms)을 player modData에 직접 저장하고 Events.EveryOneMinute /
-- Events.EveryTenMinutes로 매 틱 강제 재적용하는 방식을 쓴다. 바닐라 내부 상수에
-- 의존하지 않아 인게임 시간 계산이 항상 정확하다.
--
-- MorphineSyringe : 즉시 통증 0 + 6인게임시간 동안 매 인게임 1분마다 통증을 0으로 강제.
-- EmergencyRegenSyringe : 즉시 전신 출혈 정지 + 1인게임시간 동안 10분마다
--                         출혈 재정지 + 체력 10% 회복(부상 종류 무관, 바닐라의
--                         "무상처일 때만 자연회복" 제약을 우회).

local SYRINGE_TYPES = {
    ["t3chzzkDonation.AdrenalineSyringe"]       = true,
    ["t3chzzkDonation.DoxycyclineSyringe"]      = true,
    ["t3chzzkDonation.MorphineSyringe"]         = true,
    ["t3chzzkDonation.EmergencyRegenSyringe"]   = true,
}

local MORPHINE_DURATION_HOURS = 6
local REGEN_DURATION_HOURS    = 1
local REGEN_PERCENT_PER_TICK  = 0.10   -- EveryTenMinutes 1회당 체력 회복량

local MORPHINE_EXPIRE_KEY = "PongDu_MorphineExpireMS"
local REGEN_EXPIRE_KEY    = "PongDu_RegenExpireMS"

local function nowMS()
    return getGameTime():getCalender():getTimeInMillis()
end

local function hoursToMS(hours)
    return hours * 3600000
end

local function stopAllBleeding(bodyDamage)
    local bodyParts = bodyDamage:getBodyParts()
    for i = 0, BodyPartType.MAX:index() - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart:bleeding() then
            bodyPart:setBleeding(false)
        end
    end
end

-- ── 인벤토리 우클릭 메뉴: "주사하기" ──────────────────────────────────────────

local function tryInjectSyringe(playerObj, item)
    if not item then return end
    ISInventoryPaneContextMenu.transferIfNeeded(playerObj, item)
    ISTimedActionQueue.add(PongDuSyringeAction:new(playerObj, item))
end

local function onFillInventoryObjectContextMenu(player, context, items)
    local playerObj = getSpecificPlayer(player)
    if not playerObj then return end

    local seen = {}

    for i = 1, #items do
        local entry = items[i]
        local item = instanceof(entry, "InventoryItem") and entry or entry.items[1]
        if item then
            local fullType = item:getFullType()
            if SYRINGE_TYPES[fullType] and not seen[fullType] then
                seen[fullType] = true
                context:addOptionOnTop(getText("ContextMenu_InjectSyringe") .. " " .. item:getName(), playerObj, tryInjectSyringe, item)
            end
        end
    end
end

Events.OnFillInventoryObjectContextMenu.Add(onFillInventoryObjectContextMenu)

-- ── 타임드 액션: 실제 주사 수행 ────────────────────────────────────────────────

require "TimedActions/ISBaseTimedAction"

PongDuSyringeAction = ISBaseTimedAction:derive("PongDuSyringeAction")

function PongDuSyringeAction:isValid()
    return self.character:getInventory():contains(self.syringeItem)
end

function PongDuSyringeAction:start()
    self:setActionAnim(CharacterActionAnims.Bandage)
    self:setAnimVariable("BandageType", "LeftArm")
end

function PongDuSyringeAction:stop()
    ISBaseTimedAction.stop(self)
end

local function applyAdrenaline(playerObj, stats)
    stats:setFatigue(stats:getFatigue() - 0.7)
    stats:setEndurance(stats:getEndurance() + 0.85)
    stats:setHunger(stats:getHunger() + 0.3)
    stats:setThirst(stats:getThirst() + 0.5)
    stats:setPanic(stats:getPanic() + 15)

    if playerObj:getHealth() < 1 then
        playerObj:setHealth(playerObj:getHealth() + 0.2)
    end

    print("[PongDu] syringe: AdrenalineSyringe applied")
end

local function applyDoxycycline(playerObj, stats, bodyDamage)
    stats:setSickness(0)
    bodyDamage:setFoodSicknessLevel(0)
    bodyDamage:setInfected(false)
    bodyDamage:setInfectionLevel(0)

    local bodyParts = bodyDamage:getBodyParts()
    for i = 0, BodyPartType.MAX:index() - 1 do
        local bodyPart = bodyParts:get(i)
        if bodyPart:isInfectedWound() then
            bodyPart:setInfectedWound(false)
        end
    end

    print("[PongDu] syringe: DoxycyclineSyringe applied")
end

local function applyMorphine(playerObj, stats)
    stats:setPain(0)
    local expireAt = nowMS() + hoursToMS(MORPHINE_DURATION_HOURS)
    playerObj:getModData()[MORPHINE_EXPIRE_KEY] = expireAt

    print("[PongDu] syringe: MorphineSyringe applied, expire=" .. tostring(expireAt))
end

local function applyEmergencyRegen(playerObj, bodyDamage)
    stopAllBleeding(bodyDamage)
    local expireAt = nowMS() + hoursToMS(REGEN_DURATION_HOURS)
    playerObj:getModData()[REGEN_EXPIRE_KEY] = expireAt

    print("[PongDu] syringe: EmergencyRegenSyringe applied, expire=" .. tostring(expireAt))
end

function PongDuSyringeAction:perform()
    local playerObj = self.character
    local stats = playerObj:getStats()
    local bodyDamage = playerObj:getBodyDamage()

    if not stats or not bodyDamage then
        print("[PongDu] syringe: missing stats/bodyDamage, aborting")
        ISBaseTimedAction.perform(self)
        return
    end

    local fullType = self.syringeItem:getFullType()

    if fullType == "t3chzzkDonation.AdrenalineSyringe" then
        applyAdrenaline(playerObj, stats)
    elseif fullType == "t3chzzkDonation.DoxycyclineSyringe" then
        applyDoxycycline(playerObj, stats, bodyDamage)
    elseif fullType == "t3chzzkDonation.MorphineSyringe" then
        applyMorphine(playerObj, stats)
    elseif fullType == "t3chzzkDonation.EmergencyRegenSyringe" then
        applyEmergencyRegen(playerObj, bodyDamage)
    else
        print("[PongDu] syringe: unknown syringe type " .. tostring(fullType))
    end

    playerObj:getInventory():Remove(self.syringeItem)

    ISBaseTimedAction.perform(self)
end

-- ── 지속 효과 틱 핸들러 ────────────────────────────────────────────────────────

local function onEveryOneMinute()
    local playerObj = getPlayer()
    if not playerObj then return end

    local expireAt = playerObj:getModData()[MORPHINE_EXPIRE_KEY]
    if not expireAt then return end

    if nowMS() < expireAt then
        local stats = playerObj:getStats()
        if stats then stats:setPain(0) end
    else
        playerObj:getModData()[MORPHINE_EXPIRE_KEY] = nil
        print("[PongDu] syringe: Morphine effect ended")
    end
end

local function onEveryTenMinutes()
    local playerObj = getPlayer()
    if not playerObj then return end

    local expireAt = playerObj:getModData()[REGEN_EXPIRE_KEY]
    if not expireAt then return end

    if nowMS() < expireAt then
        local bodyDamage = playerObj:getBodyDamage()
        if bodyDamage then
            stopAllBleeding(bodyDamage)
            local newHealth = math.min(1, playerObj:getHealth() + REGEN_PERCENT_PER_TICK)
            playerObj:setHealth(newHealth)
            print("[PongDu] syringe: regen tick, health=" .. tostring(newHealth))
        end
    else
        playerObj:getModData()[REGEN_EXPIRE_KEY] = nil
        print("[PongDu] syringe: EmergencyRegen effect ended")
    end
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.EveryTenMinutes.Add(onEveryTenMinutes)

function PongDuSyringeAction:new(playerObj, syringeItem)
    local action = ISBaseTimedAction.new(self, playerObj)
    action.character = playerObj
    action.syringeItem = syringeItem
    action.stopOnWalk = true
    action.stopOnRun = true
    action.maxTime = 150
    if action.character:isTimedActionInstant() then action.maxTime = 1 end
    return action
end
