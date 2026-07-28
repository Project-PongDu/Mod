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
-- 대신 만료 시각(인게임 ms)을 player modData에 직접 저장하고 Events.EveryOneMinute로
-- 매 틱 강제 재적용하는 방식을 쓴다. 바닐라 내부 상수에
-- 의존하지 않아 인게임 시간 계산이 항상 정확하다.
--
-- MorphineSyringe : 즉시 통증 0 + 2인게임시간 동안 통증 억제.
--                   같은 시간 동안 "팔 부상으로 인한 근접 공격속도 감소"도 무시한다.
--                   (바닐라 진통제와 차별화되는 지점)
-- EmergencyRegenSyringe : 즉시 회복은 없다. 주사 시점의 체력을 바닥값(floor)으로
--                         잡고, 지속시간 동안 "상처 드레인"으로 인한 체력 감소만
--                         되돌린다. 자연회복은 그대로 반영되고(바닥값도 같이 상승),
--                         새로 입는 급성 피해도 그대로 들어간다(바닥값도 같이 하락).

local SYRINGE_TYPES = {
    ["t3chzzkDonation.Syringe_Adrenaline"]       = true,
    ["t3chzzkDonation.Syringe_Doxycycline"]      = true,
    ["t3chzzkDonation.Syringe_Morphine"]         = true,
    ["t3chzzkDonation.Syringe_Emergency"]        = true,
}

local MORPHINE_DURATION_HOURS = 2
local REGEN_DURATION_HOURS    = 0.5    -- 테스트값. 원래 설계는 1

-- 바닐라 진통제(IsoGameCharacter.PainMeds)가 쓰는 값과 동일.
-- painEffect는 "남은 틱 수" 카운터라 인게임 시간과 직결되지 않으므로 지속시간
-- 판정에는 쓰지 않는다. 우리 만료 시각(인게임 ms)이 남아있는 동안 주기적으로
-- 다시 채워 넣기만 한다. 5400틱이면 인게임 30분 이상 버티므로 인게임 1분마다
-- 갱신하면 끊길 일이 없다.
local MORPHINE_PAIN_EFFECT_TICKS = 5400

local MORPHINE_EXPIRE_KEY   = "PongDu_MorphineExpireMS"
local MORPHINE_LOGGED_KEY   = "PongDu_MorphineSpeedLogged"
local REGEN_EXPIRE_KEY      = "PongDu_RegenExpireMS"
local REGEN_FLOOR_KEY       = "PongDu_RegenFloorHP"
local REGEN_FLOOR_REBASE_KEY = "PongDu_RegenFloorRebase"

-- 급성 피해 판정 임계값 (부위 체력 0~100 스케일, 1프레임 기준).
--
-- BodyPart.DamageUpdate()의 상처 드레인은 부위당 최대치를 다 합쳐도
-- (WoundDamage 3.125 + BiteDamage 2.1875 + BurnDamage 3.75 + BulletDamage 3.125
--  + FractureDamage 3.125) * DamageScaler 0.0057143 * multiplier 1.6 ≒ 0.14 /프레임이다.
-- 반면 좀비 타격 한 방은 BodyDamage.DamageFromZombie()에서
-- Rand.Next(1000)/1000 * (Rand.Next(10)+10) 이라 0~20, 실측 대부분 5 이상이다.
-- 즉 1.0은 양쪽에서 5~10배 여유가 있는 값이다.
-- 드레인은 GameTime multiplier에 선형 비례하므로 임계값도 같이 스케일한다.
local REGEN_HIT_MIN_DROP = 1.0

-- 부위별 체력 스냅샷. modData에 넣으면 매 프레임 세이브 대상이 커지므로
-- 런타임 로컬 캐시로만 둔다. 재접속하면 비지만 첫 프레임에 다시 채워진다.
local partHPSnapshot = {}

local function nowMS()
    return getGameTime():getCalender():getTimeInMillis()
end

local function hoursToMS(hours)
    return hours * 3600000
end

-- 로컬 플레이어 순회 (분할화면 대응). getPlayer()는 0번 플레이어만 돌려주므로
-- 코옵에서 2P 이후의 효과가 통째로 죽는다.
local function forEachLocalPlayer(fn)
    for i = 0, 3 do
        local p = getSpecificPlayer(i)
        if p and not p:isDead() then fn(p) end
    end
end

-- ── 모르핀: 팔 부상 공격속도 페널티 무시 ──────────────────────────────────────
--
-- IsoGameCharacter.calculateCombatSpeed()는 마지막에
--     float0 *= this.combatSpeedModifier;
--     float0 *= this.getArmsInjurySpeedModifier();
--     float0 = clamp(float0, 0.8, 1.6);
-- 를 거쳐 IsoPlayer.combatSpeed(= 애님 변수 "CombatSpeed")에 들어간다.
-- getArmsInjurySpeedModifier()와 calculateInjurySpeed()는 전부 private라
-- Lua에서 갈아끼울 수 없다. 대신 그 두 함수가 읽는 입력(BodyPart의 상처 시간과
-- 속도 모디파이어)은 전부 public getter로 노출돼 있으므로, 같은 계산을 Lua에서
-- 재현해 배율을 구한 뒤 CombatSpeed를 나눠서 되돌린다.
--
-- 한계 두 가지 (의도적으로 감수한다):
--  1) 바닐라가 이미 [0.8, 1.6]으로 클램프한 뒤라, 부상이 하한을 때린 경우
--     원래 값을 정확히 복원할 수는 없다. 상한 1.6은 그대로 지킨다.
--  2) 이식한 계산식은 41.78.19 기준이다. 바닐라가 공식을 바꾸면 같이 손봐야 한다.
--     (그래서 배율이 1 이상이면 아무것도 건드리지 않고 조용히 빠진다)

local function calcFractureInjurySpeed(bp)
    local v = 0.4
    if bp:getFractureTime() > 10.0 then v = 0.7 end
    if bp:getFractureTime() > 20.0 then v = 1.0 end
    if bp:getSplintFactor() > 0.0 then
        v = v - 0.2
        v = v - math.min(bp:getSplintFactor() / 10.0, 0.8)
    end
    if v < 0.0 then v = 0.0 end
    return v
end

-- IsoGameCharacter.calculateInjurySpeed(bodyPart, true) 의 팔(arm) 경로 이식.
-- 발(Foot_L/R) 전용 분기는 팔에서 절대 타지 않으므로 제외했다.
local function calcArmInjurySpeed(bp)
    if bp:haveBullet() then return 1.0 end

    local v = 0.0
    if bp:getScratchTime() > 2.0
        or bp:getCutTime() > 5.0
        or bp:getBurnTime() > 0.0
        or bp:getDeepWoundTime() > 0.0
        or bp:isSplint()
        or bp:getFractureTime() > 0.0
        or bp:getBiteTime() > 0.0 then

        v = v + bp:getScratchTime()   / bp:getScratchSpeedModifier()
              + bp:getCutTime()       / bp:getCutSpeedModifier()
              + bp:getBurnTime()      / bp:getBurnSpeedModifier()
              + bp:getDeepWoundTime() / bp:getDeepWoundSpeedModifier()
        v = v + bp:getBiteTime() / 20.0

        if bp:bandaged() then v = v / 2.0 end
        if bp:getFractureTime() > 0.0 then v = calcFractureInjurySpeed(bp) end
    end

    -- boolean0(= 팔 판정)일 때만 붙는 항. 여기서 쓰는 pain은 부위 통증이라
    -- painEffect(모르핀의 전체 통증 억제)로는 절대 0이 되지 않는다.
    if bp:getPain() > 20.0 then
        v = v + bp:getPain() / 10.0
    end

    return v
end

local ARM_PARTS = { BodyPartType.Hand_R, BodyPartType.ForeArm_R, BodyPartType.UpperArm_R }

local function getArmsInjurySpeedModifier(bodyDamage)
    local mod = 1.0
    for i = 1, 3 do
        local v = calcArmInjurySpeed(bodyDamage:getBodyPart(ARM_PARTS[i]))
        if v > 0.0 then mod = mod - v end
    end
    return mod
end

local function onWeaponSwing(playerObj, weapon)
    if not playerObj then return end
    if not instanceof(playerObj, "IsoPlayer") then return end
    if not playerObj:isLocalPlayer() then return end

    local md = playerObj:getModData()
    if not md[MORPHINE_EXPIRE_KEY] then return end

    local bodyDamage = playerObj:getBodyDamage()
    if not bodyDamage then return end

    local mod = getArmsInjurySpeedModifier(bodyDamage)
    if mod >= 1.0 then return end          -- 부상 페널티 없음. 손댈 이유가 없다
    if mod < 0.05 then mod = 0.05 end      -- 0/음수 방어 (총알+골절+통증이 겹치면 음수가 될 수 있다)

    local current = playerObj:getVariableFloat("CombatSpeed", 1.0)
    local fixed = current / mod
    if fixed > 1.6 then fixed = 1.6 end    -- 바닐라 상한은 지킨다
    playerObj:setVariable("CombatSpeed", fixed)

    if not md[MORPHINE_LOGGED_KEY] then
        md[MORPHINE_LOGGED_KEY] = true
        print("[PongDu] syringe: morphine combat speed override, injuryMod=" .. tostring(mod)
            .. ", " .. tostring(current) .. " -> " .. tostring(fixed))
    end
end

-- ── 응급 재생: HP 바닥값 강제 ─────────────────────────────────────────────────
--
-- 상처는 일절 건드리지 않는다 -- 물림/화상/골절/총알/찢어진 상처/출혈 전부
-- 그대로 남고, 치료는 플레이어가 직접 해야 한다. 막는 건 오직 "상처 드레인"
-- (BodyPart.DamageUpdate()의 프레임당 지속 감소)뿐이다.
--
-- 왜 상처 타이머를 지우지 않는가: 드레인은 전부 타이머 필드(deepWoundTime /
-- bleedingTime / biteTime / burnTime / fractureTime / haveBullet)로 굴러가는데,
-- 이걸 0으로 만드는 건 곧 "상처를 치료해버리는 것"과 같다. 상처를 남기면서
-- 드레인만 끄는 엔진 플래그는 없다(BodyPart.DamageScaler가 그 역할이지만
-- private에 setter가 없어 Lua에서 접근 불가. isGodMod은 RestoreToFullHealth()로
-- 상처를 지우고, isInvincible은 체력을 100으로 못박아 둘 다 부적합).
--
-- 바닥값은 아래 세 가지로 움직인다:
--   (1) 자연회복 등으로 체력이 바닥값 위로 올라가면 바닥값도 같이 올린다.
--   (2) 급성 피해(좀비 타격/화재/낙상/차량)로 체력이 떨어지면 그만큼 바닥값을 내린다.
--   (3) 그 외 하락(= 상처 드레인)은 되돌린다.
--
-- (2)의 판정이 까다롭다. 좀비의 물기/할큄/베임은 BodyDamage.DamageFromZombie()가
-- BodyPart.AddDamage()를 직접 부르고 끝이라 Lua 이벤트가 아예 발생하지 않는다
-- (OnPlayerGetDamage는 WEAPONHIT/FIRE/FALLDOWN/CAR*/BLEEDING 등에만 붙어 있고,
--  LuaEventManager에 등록만 돼 있는 OnBeingHitByZombie는 어디서도 트리거되지 않는다).
-- 그래서 이벤트에만 의존하지 않고, 부위별 체력의 "프레임당 급락"으로 직접 감지한다.
-- 급성 피해는 계단식이고 드레인은 연속적이라 크기 차이가 한 자릿수 이상 난다.

local function detectDiscreteDamage(playerObj, bodyDamage)
    local num = playerObj:getPlayerNum()
    local snap = partHPSnapshot[num]
    if not snap then
        snap = {}
        partHPSnapshot[num] = snap
    end

    local threshold = REGEN_HIT_MIN_DROP * (getGameTime():getMultiplier() / 1.6)
    local parts = bodyDamage:getBodyParts()
    local hit = false

    for i = 0, BodyPartType.MAX:index() - 1 do
        local h = parts:get(i):getHealth()
        local prev = snap[i]
        if prev and (prev - h) > threshold then
            hit = true
        end
        snap[i] = h
    end

    return hit
end

local function enforceHealthFloor(playerObj)
    local md = playerObj:getModData()
    if not md[REGEN_EXPIRE_KEY] then return end

    local bodyDamage = playerObj:getBodyDamage()
    if not bodyDamage then return end

    -- 스냅샷 갱신은 매 프레임 무조건 돌아야 한다(건너뛰면 다음 비교가 두 프레임
    -- 치 하락을 한 번에 보고 오탐한다).
    local hit = detectDiscreteDamage(playerObj, bodyDamage)
    local current = bodyDamage:getOverallBodyHealth()

    local floorHP = md[REGEN_FLOOR_KEY]
    if not floorHP then
        md[REGEN_FLOOR_KEY] = current
        return
    end

    -- (1) 자연회복 등으로 올라간 만큼 바닥값도 올린다.
    if current >= floorHP then
        if current > floorHP then
            md[REGEN_FLOOR_KEY] = current
        end
        md[REGEN_FLOOR_REBASE_KEY] = nil
        return
    end

    -- (2) 급성 피해면 되돌리지 않고 바닥값을 현재 체력으로 내린다.
    --
    -- 이벤트 플래그(REGEN_FLOOR_REBASE_KEY)는 "체력 하락이 실제로 관측된 시점"에서만
    -- 소비한다. OnPlayerGetDamage는 한 프레임 안에서 BodyDamage.Update()보다 먼저
    -- 오는 경우가 있어, 도착 즉시 소비하면 아직 반영 안 된 피해를 다음 프레임에
    -- 복원해버려 사실상 무적이 된다.
    if hit or md[REGEN_FLOOR_REBASE_KEY] then
        md[REGEN_FLOOR_REBASE_KEY] = nil
        md[REGEN_FLOOR_KEY] = current
        print("[PongDu] syringe: regen floor lowered by new damage, floor=" .. tostring(current))
        return
    end

    -- (3) 나머지 하락 = 상처 드레인. 되돌린다.
    --
    -- AddGeneralHealth(V)는 전체 체력을 V만큼 올려주지 않는다. 손상 부위 n개에
    -- V/n씩 나눠주는데 각 부위의 전체 체력 기여도가 damage modifier(0.1~0.7)라
    -- 평균 0.3배 수준으로 희석되고, 99.9짜리 부위도 몫을 받아 100에서 잘려 버려진다.
    -- 그래서 "정확히 N 회복"을 한 번에 달성하려 하지 않고, 매 프레임 부족분을
    -- 계속 밀어넣어 수렴시킨다. 오버슈트가 없어(모든 modifier < 1) 단조 수렴한다.
    bodyDamage:AddGeneralHealth(floorHP - current)
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

-- FAO 원본 로직 그대로 유지.
-- 참고: 아래 getHealth()/setHealth()는 IsoGameCharacter의 레거시 Health 필드(0~1)로,
-- 플레이어 체력바(BodyDamage.OverallBodyHealth, 0~100)와는 별개이고 플레이어에서는
-- 사실상 항상 1이다. 즉 이 체력 회복 분기는 실제로는 거의 발동하지 않는다.
-- 원본 동작을 그대로 두기로 한 결정이므로 손대지 않는다.
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

-- 모르핀: 통증 억제는 바닐라 진통제와 같은 painEffect 메커니즘을 쓴다.
--
-- BodyDamage.Update()는 painEffect > 0 이면 통증을 매 틱 자동으로 깎고,
-- 부위별 통증에서 다시 계산하는 경로 자체를 건너뛴다. 즉 통증 억제를 자바가
-- 대신 굴려주므로 Lua는 매 틱 아무것도 안 해도 된다.
--
-- 다만 painEffect는 인게임 시간이 아니라 "남은 틱 수"라서 지속시간을 이걸로
-- 재면 게임 속도/프레임에 휘둘린다. 그래서 지속시간은 우리 만료 시각(인게임 ms)이
-- 관리하고, painEffect는 인게임 1분마다 다시 채우기만 한다.
--
-- 공격속도 페널티 무시는 onWeaponSwing 쪽에서 처리한다. painEffect는 Stats.Pain만
-- 누르고 BodyPart.getPain()(부위 통증)은 그대로 두는데, 공격속도 계산은 후자를
-- 보기 때문에 통증 억제만으로는 전혀 해결되지 않는다.
local function applyMorphine(playerObj, stats)
    stats:setPain(0)                                          -- 즉시 제거
    playerObj:setPainEffect(MORPHINE_PAIN_EFFECT_TICKS)       -- 이후 억제는 바닐라가 담당

    local md = playerObj:getModData()
    local expireAt = nowMS() + hoursToMS(MORPHINE_DURATION_HOURS)
    md[MORPHINE_EXPIRE_KEY] = expireAt
    md[MORPHINE_LOGGED_KEY] = nil

    print("[PongDu] syringe: MorphineSyringe applied, expire=" .. tostring(expireAt))
end

-- 응급 재생: 즉시 회복도, 지속 회복도 없다. 지금 체력을 그대로 바닥값으로 잡는다.
local function applyEmergencyRegen(playerObj)
    local md = playerObj:getModData()
    local bodyDamage = playerObj:getBodyDamage()

    local expireAt = nowMS() + hoursToMS(REGEN_DURATION_HOURS)
    md[REGEN_EXPIRE_KEY]       = expireAt
    md[REGEN_FLOOR_KEY]        = bodyDamage:getOverallBodyHealth()
    md[REGEN_FLOOR_REBASE_KEY] = nil
    partHPSnapshot[playerObj:getPlayerNum()] = nil

    print("[PongDu] syringe: EmergencyRegenSyringe applied, floor=" .. tostring(md[REGEN_FLOOR_KEY])
        .. ", expire=" .. tostring(expireAt))
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

    if fullType == "t3chzzkDonation.Syringe_Adrenaline" then
        applyAdrenaline(playerObj, stats)
    elseif fullType == "t3chzzkDonation.Syringe_Doxycycline" then
        applyDoxycycline(playerObj, stats, bodyDamage)
    elseif fullType == "t3chzzkDonation.Syringe_Morphine" then
        applyMorphine(playerObj, stats)
    elseif fullType == "t3chzzkDonation.Syringe_Emergency" then
        applyEmergencyRegen(playerObj)
    else
        print("[PongDu] syringe: unknown syringe type " .. tostring(fullType))
    end

    playerObj:getInventory():Remove(self.syringeItem)

    ISBaseTimedAction.perform(self)
end

-- ── 지속 효과 틱 핸들러 (인게임 1분) ──────────────────────────────────────────
-- 여기서 하는 일은 만료 판정과 painEffect 갱신뿐이다. 실제 억제/복원은
-- 각각 바닐라(painEffect)와 프레임 훅(enforceHealthFloor)이 담당한다.

local function tickMorphine(playerObj)
    local md = playerObj:getModData()
    local expireAt = md[MORPHINE_EXPIRE_KEY]
    if not expireAt then return end

    if nowMS() < expireAt then
        -- painEffect는 틱마다 소모되므로 주기적으로 다시 채운다.
        playerObj:setPainEffect(MORPHINE_PAIN_EFFECT_TICKS)
    else
        md[MORPHINE_EXPIRE_KEY] = nil
        md[MORPHINE_LOGGED_KEY] = nil
        playerObj:setPainEffect(0)   -- 남은 잔량을 끊어 즉시 종료시킨다
        print("[PongDu] syringe: Morphine effect ended")
    end
end

-- 응급 재생은 지속 회복이 없다. 만료 정리만 한다.
local function tickRegen(playerObj)
    local md = playerObj:getModData()
    local expireAt = md[REGEN_EXPIRE_KEY]
    if not expireAt then return end

    if nowMS() >= expireAt then
        md[REGEN_EXPIRE_KEY]       = nil
        md[REGEN_FLOOR_KEY]        = nil
        md[REGEN_FLOOR_REBASE_KEY] = nil
        partHPSnapshot[playerObj:getPlayerNum()] = nil
        print("[PongDu] syringe: EmergencyRegen effect ended")
    end
end

local function onEveryOneMinute()
    forEachLocalPlayer(function(playerObj)
        tickMorphine(playerObj)
        tickRegen(playerObj)
    end)
end

-- 바닥값 강제만 프레임 단위로 돌린다. 분 단위로는 그 사이 드레인이 눈에 보이게
-- 깎였다가 되돌아오는 톱니가 생긴다. 조기 return이 대부분이라 비용은 무시할 수준
-- (효과가 없으면 modData 조회 한 번에서 끝난다).
local function onPlayerUpdate(playerObj)
    if not playerObj then return end
    enforceHealthFloor(playerObj)
end

-- 급성 피해 보조 신호.
--
-- 부위 체력 급락 감지가 주 판정이고, 이 이벤트는 그걸 놓쳤을 때를 위한 보조다
-- (예: 여러 부위에 얕게 퍼진 피해). 피격 데미지값(damageSplit)은 무기 데미지
-- 단위라 체력 델타로 환산할 수 없으므로, 값을 쓰지 않고 리베이스만 예약한다.
-- BLEEDING/POISON/HUNGRY/SICK/THIRST/HEAVYLOAD/INFECTION 계열은 지속 드레인이라
-- 일부러 제외했다.
local REBASELINE_DAMAGE_TYPES = {
    WEAPONHIT       = true,
    FIRE            = true,
    FALLDOWN        = true,
    CARHITDAMAGE    = true,
    CARCRASHDAMAGE  = true,
}

local function onPlayerGetDamage(character, damageType, amount)
    if not character or not REBASELINE_DAMAGE_TYPES[damageType] then return end

    -- IsoGameCharacter.Hit()은 *맞은 대상*으로 이벤트를 쏜다. 플레이어가 좀비를
    -- 때리면 좀비로 들어오므로 걸러낸다.
    if not instanceof(character, "IsoPlayer") then return end

    local md = character:getModData()
    if md[REGEN_FLOOR_KEY] then
        md[REGEN_FLOOR_REBASE_KEY] = true
    end
end

Events.EveryOneMinute.Add(onEveryOneMinute)
Events.OnPlayerUpdate.Add(onPlayerUpdate)
Events.OnPlayerGetDamage.Add(onPlayerGetDamage)
Events.OnWeaponSwing.Add(onWeaponSwing)

function PongDuSyringeAction:new(playerObj, syringeItem)
    local action = ISBaseTimedAction.new(self, playerObj)
    action.character = playerObj
    action.syringeItem = syringeItem
    action.stopOnWalk = true
    action.stopOnRun = true
    -- ISBaseTimedAction:adjustMaxTime()은 ignoreHandsWounds가 꺼져 있으면
    -- Hand_L ~ ForeArm_R 4부위의 getPain()을 maxTime에 그대로 더한다(부위당 최대
    -- 100, 합쳐서 최대 +400). 그래서 maxTime을 아무리 줄여도 팔을 다치면
    -- 시전시간이 수백으로 뛴다. 응급용 주사기라 이 가산을 받지 않게 한다.
    -- (바닐라도 ISEatFoodAction, ISDrinkFromBottle, ISEquipWeaponAction 등에서
    --  같은 플래그를 쓴다)
    action.ignoreHandsWounds = true
    action.maxTime = 10
    if action.character:isTimedActionInstant() then action.maxTime = 1 end
    return action
end
