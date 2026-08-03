-- syringe.lua : 전투자극제 / 광범위 항생제 / 모르핀 / 응급 재생 주사기
--
-- Syringe_Adrenaline(전투자극제) / Syringe_Doxycycline(광범위 항생제)는
-- FirstAidOverhaul 모드(BB_FAO_ISTimedAction / BB_FAO_ISFillInventoryContextMenu)에서
-- 이식. 원본은 EmptySyringe -> 각종 소재 조합으로 제작하는 레시피 체인이 있었으나,
-- 퐁듀는 후원으로 완성품을 바로 지급하는 구조라 레시피 전체를 제외했다. 그에 따라
-- "사용 후 빈 주사기 반환" 로직도 함께 제외한다(레시피가 없으면 빈 주사기가 아무
-- 데도 못 쓰이는 죽은 아이템이 되므로).
--
-- Syringe_Adrenaline(전투자극제) : 피로/지구력 즉시 회복, 배고픔/갈증/패닉 증가.
--                                  빈사(HP<1) 시 소량 회복.
-- Syringe_Doxycycline(광범위 항생제) : 일반 질병(Sickness) + 식중독 + 상처 세균감염 치료.
--                                      좀비 감염(Knox Infection, bitten/IsInfected 계열)은
--                                      건드리지 않는다.
--
-- Syringe_Morphine(모르핀) / Syringe_Emergency(응급 재생)은 신규 추가. 둘 다
-- "지속시간" 개념이 있는데, 바닐라 PainEffect/PainReduction(BodyDamage.java)은
-- 프레임 단위로 게임속도 배율에 맞춰 감쇠하는 구조라 "정확히 인게임 N시간"을
-- 보장하려면 상수를 역산해야 하고 게임 패치로 조용히 틀어질 위험이 있다.
-- 대신 만료 시각(인게임 ms)을 player modData에 직접 저장하고 Events.EveryOneMinute로
-- 매 틱 강제 재적용하는 방식을 쓴다. 바닐라 내부 상수에 의존하지 않아 인게임 시간
-- 계산이 항상 정확하다.
--
-- Syringe_Morphine  : 즉시 통증 0 + 2인게임시간 동안 통증 억제.
--                     같은 시간 동안 "팔 부상으로 인한 근접 공격속도 감소"도 무시한다.
-- Syringe_Emergency : 즉시 회복은 없다. 주사 시점의 "부위별" 체력을 바닥값으로 잡고,
--                     지속시간 동안 상처 드레인으로 인한 감소만 되돌린다.
--                     자연회복은 그대로 반영(바닥값 동반 상승), 급성 피해도 그대로
--                     들어간다(바닥값 동반 하락). 녹스 감염/저체온 상한은 예외로
--                     두어 그쪽으로는 정상적으로 죽는다.

local SYRINGE_TYPES = {
    ["t3chzzkDonation.Syringe_Adrenaline"]  = true,
    ["t3chzzkDonation.Syringe_Doxycycline"] = true,
    ["t3chzzkDonation.Syringe_Morphine"]    = true,
    ["t3chzzkDonation.Syringe_Emergency"]   = true,
}

local MORPHINE_DURATION_HOURS = 2
local REGEN_DURATION_HOURS    = 0.5    -- 테스트값. 원래 설계는 1

-- 바닐라 진통제(IsoGameCharacter.PainMeds)가 쓰는 값과 동일.
-- painEffect는 "남은 틱 수" 카운터라 인게임 시간과 직결되지 않으므로 지속시간
-- 판정에는 쓰지 않는다. 우리 만료 시각(인게임 ms)이 남아있는 동안 주기적으로
-- 다시 채워 넣기만 한다.
local MORPHINE_PAIN_EFFECT_TICKS = 5400

local MORPHINE_EXPIRE_KEY = "PongDu_MorphineExpireMS"
local MORPHINE_LOGGED_KEY = "PongDu_MorphineSpeedLogged"
local REGEN_EXPIRE_KEY    = "PongDu_RegenExpireMS"

-- 급성 피해 판정 임계값 (부위 체력 0~100 스케일, 1프레임 기준).
--
-- 아래 enforceHealthFloor는 매 프레임 부위 체력을 바닥값으로 되돌리므로, 관측되는
-- 하락폭은 항상 "정확히 한 프레임분"이다.
--   상처 드레인 최대치: (WoundDamage 3.125 + BiteDamage 2.1875 + BurnDamage 3.75
--     + BulletDamage 3.125 + FractureDamage 3.125) * DamageScaler 0.0057143
--     * multiplier 1.6 = 약 0.14 /프레임
--   좀비 타격 한 방: BodyDamage.DamageFromZombie()에서
--     Rand.Next(1000)/1000 * (Rand.Next(10)+10) = 0~20, 실측 대부분 5 이상
-- 1.0이면 양쪽에서 5~10배 여유가 있다. 드레인은 GameTime multiplier에 선형
-- 비례하므로 임계값도 같이 스케일한다.
local REGEN_HIT_MIN_DROP = 1.0

-- BodyPartType.getDamageModifyer(index) 이식 (41.78.19).
-- BodyDamage.calculateOverallHealth()가
--   overall = 100 - sum((100 - part.Health) * modifier[i])
-- 로 전체 체력을 만들기 때문에, 부위 바닥값 -> 전체 체력 환산에 필요하다.
-- 진단 로그와 엔진 상한 비교에만 쓰고, 복원 자체는 부위 단위로 하므로
-- 이 값이 틀려도 체력 복원 정확도에는 영향이 없다.
local DAMAGE_MOD = {
    [0]  = 0.1,  [1]  = 0.1,  [2]  = 0.2,  [3]  = 0.2,
    [4]  = 0.3,  [5]  = 0.3,  [6]  = 0.35, [7]  = 0.4,
    [8]  = 0.6,  [9]  = 0.7,  [10] = 0.4,  [11] = 0.3,
    [12] = 0.3,  [13] = 0.2,  [14] = 0.2,  [15] = 0.2,
    [16] = 0.2,
}

-- 부위별 바닥값 + 진단 카운터. modData에 넣으면 매 프레임 세이브 대상이 커지므로
-- 런타임 로컬 캐시로만 둔다. 재접속하면 비지만 첫 프레임에 현재 체력으로 다시 잡힌다.
-- regenState[playerNum] = {
--     floor    = { [0..16] = 부위 바닥값 },
--     restored = 지난 진단 로그 이후 되돌린 총량(부위 체력 합산),
--     hits     = 지난 진단 로그 이후 급성 피해 감지 횟수,
--     capped   = 엔진 상한(감염/저체온)에 걸려 복원을 포기한 프레임 수,
-- }
local regenState = {}

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

-- GameTime.getAnimSpeedFix()는 상수 0.8. calculateCombatSpeed()는
--     return float0 * (boolean0 ? GameTime.getAnimSpeedFix() : 1.0F);
-- 로 끝나는데, boolean0은 "Axeman 특성 + 도끼 카테고리 무기로 나무를 베는 중"일
-- 때만 false가 되고 그 외 모든 전투(사실상 전부)에서는 이 0.8이 최종값에
-- 곱해진다. 즉 엔진의 [0.8, 1.6] 클램프는 실제로 관측되는 CombatSpeed 값에서
-- [0.64, 1.28] 구간으로 나타난다(하한이 0.8이 아니라 0.8*0.8=0.64).
-- 이 배율을 몰랐을 땐 클램프 감지 임계값이 어긋나 있었다.
local function getAnimSpeedFixMultiplier(playerObj, weapon)
    if weapon and playerObj:getTraits():contains("Axeman") and weapon:getCategories():contains("Axe") then
        return 1.0
    end
    return 0.8
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
    if mod < 0.05 then mod = 0.05 end      -- 0/음수 방어 (총알+골절+통증이 겹치면 음수 가능)

    local current = playerObj:getVariableFloat("CombatSpeed", 1.0)
    local animFix = getAnimSpeedFixMultiplier(playerObj, weapon)

    -- IsoGameCharacter.calculateCombatSpeed()는 mod를 곱한 직후 [0.8, 1.6]으로
    -- 클램프하고, 그 결과에 animFix(위 참고)를 곱해 반환한다. animFix는 순수
    -- 무기/특성만으로 결정되는 값이라(랜덤 요소 없음) 여기서 그대로 나눠 없애면
    -- "엔진이 클램프한 원래 값"을 정확히 복원할 수 있다.
    --
    -- 부상이 심해 float0이 0.8 밑으로 떨어지면 엔진이 0.8로 깎아버리고, 그
    -- 사실이 CombatSpeed 변수에는 남지 않는다. 이 상태에서 current를 그대로
    -- mod로 나누면 실제보다 훨씬 큰 값이 나온다(예: 관측 0.64, mod=0.3이면
    -- 2.67 -> 1.6으로 재클램프. 즉 미부상 정상 속도보다 더 빠른 "부스트" 발생.
    -- 실제로 이 버그가 제보됐다). 나눗셈으로 정확히 복원 가능한 경우는 엔진
    -- 클램프가 걸리지 않았을 때뿐이다.
    --
    -- animFix를 나눠 없앤 clampedPart는 [0.8, 1.6] 구간의 엔진 클램프 결과와
    -- 정확히 대응하므로, 그 값이 하한/상한 근처인지로 클램프 여부를 정확히
    -- 판정할 수 있다(이전처럼 animFix를 무시한 채 관측값에 임의 임계값을
    -- 대는 방식보다 정확함).
    local clampedPart = current / animFix
    local fixed
    local clamped = clampedPart <= 0.81 or clampedPart >= 1.59
    if clamped then
        -- 클램프가 걸린 프레임은 엔진이 얼마나 깎았는지(혹은 올렸는지) 정보가
        -- 사라져서 정확한 역산이 불가능하다. mod로 나누는 대신 정상 기준값
        -- (미부상 시 흔한 대역인 1.0)을 animFix와 같은 단위로 맞춰 되돌린다.
        fixed = 1.0 * animFix
    else
        -- 클램프가 안 걸렸다면 clampedPart == base * mod 이므로 나눗셈이
        -- 수학적으로 정확하다. base 자체가 [0.8, 1.6]을 벗어나지 않게만
        -- 다시 클램프해서 animFix를 곱한다.
        local base = clampedPart / mod
        if base > 1.6 then base = 1.6 end
        if base < 0.8 then base = 0.8 end
        fixed = base * animFix
    end
    playerObj:setVariable("CombatSpeed", fixed)

    if not md[MORPHINE_LOGGED_KEY] then
        md[MORPHINE_LOGGED_KEY] = true
        print("[PongDu] syringe: morphine combat speed override, injuryMod=" .. tostring(mod)
            .. ", animFix=" .. tostring(animFix)
            .. ", clamped=" .. tostring(clamped)
            .. ", " .. tostring(current) .. " -> " .. tostring(fixed))
    end
end

-- ── 응급 재생: 부위별 HP 바닥값 강제 ─────────────────────────────────────────
--
-- 상처는 일절 건드리지 않는다 -- 물림/화상/골절/총알/찢어진 상처/출혈 전부 그대로
-- 남고, 치료는 플레이어가 직접 해야 한다. 막는 건 오직 "상처 드레인"
-- (BodyPart.DamageUpdate()의 프레임당 지속 감소)뿐이다.
--
-- [왜 전체 체력(OverallBodyHealth) 바닥값을 버리고 부위별로 바꿨는가]
--
-- 이전 구현은 전체 체력 하나를 바닥값으로 잡고 부족분을
-- BodyDamage.AddGeneralHealth()로 밀어넣었는데, 두 가지 이유로 바닥값이 뚫렸다.
--
--  1) 복원 게인이 1보다 작다. ReduceGeneralHealth()는 부위별로
--     (Val/17) / damageModifyer 만큼 깎아서 전체 체력이 정확히 Val 감소하지만,
--     AddGeneralHealth()는 modifier로 나누지 않고 손상 부위 n개에 Val/n씩 그냥
--     더한다. 그래서 실제 전체 체력 회복량은 Val * (sum(mod)/n) 이고, 전 부위
--     손상 시 약 0.30배, 손 하나만 다친 상태면 0.10배까지 떨어진다.
--  2) 호출 순서가 불리하다. 이 훅은 OnPlayerUpdate(IsoPlayer.update 1730행)에서
--     도는데, 드레인(BodyDamage.Update -> DamageUpdate, 2286행)과 전체 체력
--     재계산(2289행)은 그보다 뒤다. 즉 "복원하고 나서 한 프레임분 드레인을 다시
--     맞는" 구조다.
--
--  1 + 2 => 게인 g, 프레임당 드레인 D 인 비례제어기가 되어 바닥값이 아니라
--  gap = D/g 에서 평형을 잡는다. 붕대를 감으면 D가 0이나 절반이라 gap이 거의
--  없어 붙어 보이지만, 붕대를 풀면 D가 튀면서 그만큼 아래로 주저앉는다.
--  (실제 제보 증상: 살균붕대 감았다 풀었더니 바닥값이 뚫림)
--
-- 지금 구현은 부위별 바닥값을 들고 BodyPart:SetHealth()로 직접 되돌린다.
-- 희석이 없어 게인이 정확히 1이고, calculateOverallHealth()는 부위 체력의 순수
-- 함수이므로 전체 체력도 자동으로 맞는다.
--
-- 바닥값은 부위 단위로 이렇게 움직인다:
--   (1) 자연회복 등으로 부위 체력이 바닥값 위로 오르면 바닥값도 같이 올린다.
--   (2) 한 프레임에 임계값 이상 급락하면 급성 피해로 보고 바닥값을 내린다.
--   (3) 그 외 하락(= 상처 드레인)은 되돌린다.
--
-- (2)의 감지를 이벤트가 아니라 체력 급락으로 하는 이유: 좀비의 물기/할큄/베임은
-- BodyDamage.DamageFromZombie()가 BodyPart.AddDamage()를 직접 부르고 끝이라 Lua
-- 이벤트가 아예 발생하지 않는다. OnPlayerGetDamage는 WEAPONHIT/FIRE/FALLDOWN/
-- CAR*/BLEEDING 등에만 붙어 있고, LuaEventManager에 등록만 돼 있는
-- OnBeingHitByZombie는 어디서도 트리거되지 않는 죽은 이벤트다.

-- 엔진이 전체 체력에 거는 상한을 계산한다. 상한이 걸린 동안은 복원을 포기하고
-- 바닥값을 현재 체력에 맞춰 내린다 -- 안 그러면 매 프레임 서로 밀고 당기면서
-- 녹스 감염으로 죽지 않는 사실상 무적 상태가 된다.
--
--  - 녹스 감염 (BodyDamage.Update 2276행)
--        float7 = (1 - p^4) * 100,  p = InfectionLevel/100
--        if overall > float7 and float7 <= 99 then ReduceGeneralHealth(overall - float7)
--    p == 1 이면 ReduceGeneralHealth(110)으로 즉사시킨다.
--  - 저체온 (BodyDamage.UpdateTemperatureState 2393행)
--        float1 = 100 - ColdDamageStage * 100
--        if overall > float1 then ReduceGeneralHealth(overall - float1)
--
-- 둘 다 이 훅보다 뒤에 돌기 때문에 우리가 복원해도 같은 프레임에 다시 깎인다.
local function getEngineHealthCap(bodyDamage)
    local cap = 100.0

    if bodyDamage:isInfected() then
        local p = bodyDamage:getInfectionLevel() / 100.0
        local p4 = p * p
        p4 = p4 * p4
        local c = (1.0 - p4) * 100.0
        if c <= 99.0 and c < cap then cap = c end
    end

    local cold = bodyDamage:getColdDamageStage()
    if cold > 0.0 then
        local c = 100.0 - cold * 100.0
        if c < cap then cap = c end
    end

    return cap
end

-- 부위 바닥값 -> 전체 체력 환산 (calculateOverallHealth 이식). 진단 로그와
-- 엔진 상한 비교에만 쓴다.
local function floorToOverall(floor)
    local deficit = 0.0
    for i = 0, 16 do
        deficit = deficit + (100.0 - floor[i]) * DAMAGE_MOD[i]
    end
    if deficit > 100.0 then deficit = 100.0 end
    return 100.0 - deficit
end

local function seedFloor(bodyDamage)
    local parts = bodyDamage:getBodyParts()
    local floor = {}
    for i = 0, 16 do
        floor[i] = parts:get(i):getHealth()
    end
    return floor
end

local function enforceHealthFloor(playerObj)
    local md = playerObj:getModData()
    if not md[REGEN_EXPIRE_KEY] then return end

    local bodyDamage = playerObj:getBodyDamage()
    if not bodyDamage then return end

    local num = playerObj:getPlayerNum()
    local st = regenState[num]
    if not st then
        st = { floor = seedFloor(bodyDamage), restored = 0.0, hits = 0, capped = 0 }
        regenState[num] = st
        print("[PongDu] syringe: regen floor seeded (no state), player=" .. tostring(num)
            .. ", overall=" .. tostring(floorToOverall(st.floor)))
        return
    end

    local floor = st.floor
    local parts = bodyDamage:getBodyParts()

    -- 엔진 상한이 우리 목표보다 낮으면 복원을 포기한다.
    local cap = getEngineHealthCap(bodyDamage)
    local target = floorToOverall(floor)
    if cap < target then
        for i = 0, 16 do
            floor[i] = parts:get(i):getHealth()
        end
        st.capped = st.capped + 1
        return
    end

    local threshold = REGEN_HIT_MIN_DROP * (getGameTime():getMultiplier() / 1.6)

    for i = 0, 16 do
        local bp = parts:get(i)
        local h = bp:getHealth()
        local f = floor[i]

        if h > f then
            -- (1) 자연회복. 바닥값 동반 상승
            floor[i] = h
        elseif h < f then
            local drop = f - h
            if drop > threshold then
                -- (2) 급성 피해. 바닥값을 내리고 되돌리지 않는다
                floor[i] = h
                st.hits = st.hits + 1
                print("[PongDu] syringe: regen floor lowered by damage, part="
                    .. BodyPartType.ToString(BodyPartType.FromIndex(i))
                    .. ", drop=" .. tostring(drop)
                    .. ", floor=" .. tostring(h))
            else
                -- (3) 상처 드레인. 되돌린다
                bp:SetHealth(f)
                st.restored = st.restored + drop
            end
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
                context:addOptionOnTop(getText("ContextMenu_InjectSyringe"))
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
    -- 4종 공통 주사음. 23a2cddc59fe561bba91dd21a3759f1ee96207c0에서 추가된
    -- SFX_Inject.wav를 t3_rewards_sounds.txt에 pongdu_syringe_inject로 등록해 재생한다.
    -- 실패(성공/실패 판정)와 무관하게 "주사 행위" 자체에 붙는 소리라 start()에서 1회 재생.
    self.character:getEmitter():playSound("pongdu_syringe_inject")
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

    print("[PongDu] syringe: Syringe_Adrenaline applied")
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

    print("[PongDu] syringe: Syringe_Doxycycline applied")
end

-- 모르핀: 통증 억제는 바닐라 진통제와 같은 painEffect 메커니즘을 쓴다.
--
-- BodyDamage.Update()는 painEffect > 0 이면 통증을 매 틱 자동으로 깎고, 부위별
-- 통증에서 다시 계산하는 경로 자체를 건너뛴다. 즉 통증 억제를 자바가 대신
-- 굴려주므로 Lua는 매 틱 아무것도 안 해도 된다.
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

    print("[PongDu] syringe: Syringe_Morphine applied, expire=" .. tostring(expireAt))
end

-- 응급 재생: 즉시 회복도, 지속 회복도 없다. 지금 부위별 체력을 그대로 바닥값으로 잡는다.
local function applyEmergencyRegen(playerObj)
    local md = playerObj:getModData()
    local bodyDamage = playerObj:getBodyDamage()
    local num = playerObj:getPlayerNum()

    local expireAt = nowMS() + hoursToMS(REGEN_DURATION_HOURS)
    md[REGEN_EXPIRE_KEY] = expireAt

    local floor = seedFloor(bodyDamage)
    regenState[num] = { floor = floor, restored = 0.0, hits = 0, capped = 0 }

    print("[PongDu] syringe: Syringe_Emergency applied, player=" .. tostring(num)
        .. ", overall=" .. tostring(bodyDamage:getOverallBodyHealth())
        .. ", floorOverall=" .. tostring(floorToOverall(floor))
        .. ", cap=" .. tostring(getEngineHealthCap(bodyDamage))
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
-- 만료 판정, painEffect 갱신, 그리고 응급 재생 진단 로그.

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

-- 진단 로그. 바닥값이 또 뚫리면 이 로그만 보고 원인을 좁힐 수 있어야 한다.
--   overall  : 실제 전체 체력
--   target   : 부위 바닥값에서 환산한 목표 전체 체력 (overall과 벌어지면 복원 실패)
--   cap      : 엔진 상한. target보다 낮으면 그 프레임은 복원을 포기한 상태
--   restored : 지난 1분간 되돌린 부위 체력 총합 (드레인 강도)
--   hits     : 지난 1분간 급성 피해로 바닥값을 내린 횟수
--   capped   : 지난 1분간 엔진 상한 때문에 복원을 포기한 프레임 수
--   inf/cold : 상한을 만든 원인값
--   held     : 바닥값이 100 미만인 부위 수 (복원 대상 부위 수)
local function logRegenDiag(playerObj, bodyDamage, st)
    local floor = st.floor
    local held = 0
    for i = 0, 16 do
        if floor[i] < 100.0 then held = held + 1 end
    end

    print("[PongDu] syringe: regen diag player=" .. tostring(playerObj:getPlayerNum())
        .. " overall=" .. tostring(bodyDamage:getOverallBodyHealth())
        .. " target=" .. tostring(floorToOverall(floor))
        .. " cap=" .. tostring(getEngineHealthCap(bodyDamage))
        .. " restored=" .. tostring(st.restored)
        .. " hits=" .. tostring(st.hits)
        .. " capped=" .. tostring(st.capped)
        .. " inf=" .. tostring(bodyDamage:getInfectionLevel())
        .. " cold=" .. tostring(bodyDamage:getColdDamageStage())
        .. " held=" .. tostring(held))

    st.restored = 0.0
    st.hits = 0
    st.capped = 0
end

local function tickRegen(playerObj)
    local md = playerObj:getModData()
    local expireAt = md[REGEN_EXPIRE_KEY]
    if not expireAt then return end

    local num = playerObj:getPlayerNum()
    local bodyDamage = playerObj:getBodyDamage()

    if nowMS() < expireAt then
        local st = regenState[num]
        if st and bodyDamage then
            logRegenDiag(playerObj, bodyDamage, st)
        end
    else
        local st = regenState[num]
        if st and bodyDamage then
            print("[PongDu] syringe: EmergencyRegen effect ended, overall="
                .. tostring(bodyDamage:getOverallBodyHealth())
                .. ", target=" .. tostring(floorToOverall(st.floor))
                .. ", hits=" .. tostring(st.hits)
                .. ", capped=" .. tostring(st.capped))
        else
            print("[PongDu] syringe: EmergencyRegen effect ended (no state)")
        end
        md[REGEN_EXPIRE_KEY] = nil
        regenState[num] = nil
    end
end

local function onEveryOneMinute()
    forEachLocalPlayer(function(playerObj)
        tickMorphine(playerObj)
        tickRegen(playerObj)
    end)
end

-- 바닥값 강제는 프레임 단위로 돌린다. 분 단위로는 그 사이 드레인이 눈에 보이게
-- 깎였다가 되돌아오는 톱니가 생긴다. 조기 return이 대부분이라 비용은 무시할 수준
-- (효과가 없으면 modData 조회 한 번에서 끝난다).
local function onPlayerUpdate(playerObj)
    if not playerObj then return end
    enforceHealthFloor(playerObj)
end

-- 급성 피해 보조 신호.
--
-- 주 판정은 부위 체력 급락이다. 이 이벤트는 그게 놓칠 수 있는 경우(여러 부위에
-- 임계값 미만으로 얕게 퍼진 피해)를 위한 보조로, 해당 프레임의 임계값을 0으로
-- 낮춰 어떤 하락이든 급성 피해로 처리하게 만든다.
-- 피격 데미지값은 무기 데미지 단위라 부위 체력 델타로 환산할 수 없으므로 쓰지 않는다.
-- BLEEDING/POISON/HUNGRY/SICK/THIRST/HEAVYLOAD/INFECTION 계열은 지속 드레인이라
-- 일부러 제외했다.
local REBASELINE_DAMAGE_TYPES = {
    WEAPONHIT      = true,
    FIRE           = true,
    FALLDOWN       = true,
    CARHITDAMAGE   = true,
    CARCRASHDAMAGE = true,
}

local function onPlayerGetDamage(character, damageType, amount)
    if not character or not REBASELINE_DAMAGE_TYPES[damageType] then return end

    -- IsoGameCharacter.Hit()은 *맞은 대상*으로 이벤트를 쏜다. 플레이어가 좀비를
    -- 때리면 좀비로 들어오므로 걸러낸다.
    if not instanceof(character, "IsoPlayer") then return end
    if not character:isLocalPlayer() then return end

    local st = regenState[character:getPlayerNum()]
    if not st then return end

    -- 이 이벤트는 한 프레임 안에서 BodyDamage.Update()보다 먼저 도착할 수 있어
    -- 즉시 바닥값을 내리면 아직 반영 안 된 피해까지 같이 잘라먹는다. 대신
    -- 부위 바닥값을 현재 체력으로 동기화해두면, 다음 프레임에 들어오는 피해분이
    -- 그대로 남는다.
    local bodyDamage = character:getBodyDamage()
    if not bodyDamage then return end
    local parts = bodyDamage:getBodyParts()
    for i = 0, 16 do
        local h = parts:get(i):getHealth()
        if h < st.floor[i] then st.floor[i] = h end
    end

    print("[PongDu] syringe: regen floor synced by event, type=" .. tostring(damageType)
        .. ", amount=" .. tostring(amount))
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
