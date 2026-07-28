-- syringe.lua : 아드레날린 / 독시사이클린 주사기
--
-- FirstAidOverhaul 모드(BB_FAO_ISTimedAction / BB_FAO_ISFillInventoryContextMenu)에서
-- 이식. 원본은 EmptySyringe -> 각종 소재 조합으로 제작하는 레시피 체인이 있었으나,
-- 퐁듀는 후원으로 완성품을 바로 지급하는 구조라 레시피 전체를 제외했다. 그에 따라
-- "사용 후 빈 주사기 반환" 로직도 함께 제외한다(레시피가 없으면 빈 주사기가 아무
-- 데도 못 쓰이는 죽은 아이템이 되므로).
--
-- AdrenalineSyringe : 피로/지구력 즉시 회복, 배고픔/갈증/패닉 증가. 빈사(HP<1) 시 소량 회복.
-- DoxycyclineSyringe : 일반 질병(Sickness) + 식중독 + 상처 세균감염 치료.
--                      좀비 감염(Knox Infection, bitten/IsInfected 계열)은 건드리지 않는다.

local SYRINGE_TYPES = {
    ["t3chzzkDonation.AdrenalineSyringe"]  = true,
    ["t3chzzkDonation.DoxycyclineSyringe"] = true,
}

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
    else
        print("[PongDu] syringe: unknown syringe type " .. tostring(fullType))
    end

    playerObj:getInventory():Remove(self.syringeItem)

    ISBaseTimedAction.perform(self)
end

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
