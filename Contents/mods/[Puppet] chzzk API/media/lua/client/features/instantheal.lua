local _a = {}

-- ── 즉시 치유 (instant_heal) 클라이언트 ──────────────────────────────────────
--
-- 후원자 개인 버프. 전신 부위의 물리적 부상(긁힘/베임/깊은 상처/물린 상처/
-- 화상/유리 파편/총알/골절/출혈/붕대·봉합 상태)과 부위 체력을 전부 원상복구한다.
-- 좀비 감염(Knox Infection)은 기본적으로 건드리지 않으며, 샌드박스
-- Heal_CureBiteInfection 을 켰을 때만 백신과 동일하게 완전 치료한다.
--
-- 구현 근거 (B41 41.78.20 BodyPart.java / BodyDamage.java 확인):
--   * BodyPart:RestoreToFullHealth() 는 그 부위의 모든 부상 필드와 Health 를
--     한 번에 초기화한다. 개별 setter 를 나열하는 것보다 누락 위험이 없다.
--     바닐라 디버그 메뉴(ISHealthPanel.onCheat "healthFullBody")도 같은 함수를 쓴다.
--   * 다만 이 함수는 그 부위의 IsInfected / IsFakeInfected 플래그까지 같이
--     지운다. 감염을 남겨야 하는 기본 동작에서는 호출 전에 두 플래그를 읽어두고
--     호출 후 되돌려 놓는다.
--   * BodyDamage 레벨의 InfectionLevel / InfectionTime / InfectionMortalityDuration
--     은 BodyPart:RestoreToFullHealth() 의 영향을 받지 않으므로, 감염을 치료할
--     때만 features/vaccine.lua 와 동일한 절차로 따로 지운다.
--   * 뻐근함(stiffness)은 RestoreToFullHealth() 대상이 아니다. 부위 값만 0으로
--     만들면 Fitness 쪽 누적치가 남아 다음 틱에 되돌아오므로,
--     Fitness:removeStiffnessValue() 도 같이 호출한다 (바닐라와 동일).
--   * 전체 체력(OverallBodyHealth)은 BodyDamage.Update() 의
--     calculateOverallHealth() 가 부위 체력에서 매 틱 재계산하므로 직접 쓰지 않는다.
--   * 출혈 연출용 IsoPlayer.bleedingLevel 도 같은 Update() 에서 재계산된다.
--
-- 사운드는 클라 로컬(getSoundManager():PlaySound)이라 좀비 어그로가 붙지 않는다.

local global = require("global")

local LOG = "[PongDu][InstantHeal] "

function _a.a(sender)
    local player = global.player
    if not player then
        print(LOG .. "heal aborted: player is nil")
        return
    end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        print(LOG .. "heal aborted: bodyDamage is nil")
        return
    end

    -- 샌드박스는 파일 로드 시점이 아니라 사용 시점에 읽는다.
    local cureInfection = SandboxVars.PongDu.Heal_CureBiteInfection
    local fitness = player:getFitness()

    local parts = bodyDamage:getBodyParts()
    local healedParts = 0
    local keptInfected = 0
    local clearedStiffness = 0

    for i = 0, parts:size() - 1 do
        local part = parts:get(i)

        local wasInfected = part:IsInfected()
        local wasFake     = part:IsFakeInfected()
        local hadInjury   = part:HasInjury() or part:getHealth() < 100

        part:RestoreToFullHealth()

        if not cureInfection then
            if wasInfected then
                part:SetInfected(true)
                keptInfected = keptInfected + 1
            end
            if wasFake then
                part:SetFakeInfected(true)
            end
        end

        if part:getStiffness() > 0 then
            part:setStiffness(0)
            if fitness then
                fitness:removeStiffnessValue(BodyPartType.ToString(part:getType()))
            end
            clearedStiffness = clearedStiffness + 1
        end

        if hadInjury then
            healedParts = healedParts + 1
        end
    end

    if cureInfection then
        -- features/vaccine.lua 의 Zomboxivir 처리와 동일한 절차.
        -- 부위 플래그는 위 루프의 RestoreToFullHealth() 에서 이미 지워졌다.
        bodyDamage:setInfected(false)
        bodyDamage:setIsFakeInfected(false)
        bodyDamage:setInfectionLevel(0)
        bodyDamage:setFakeInfectionLevel(0)
        bodyDamage:setInfectionTime(-1)
        bodyDamage:setInfectionMortalityDuration(-1)
    end

    local audio = getSoundManager():PlaySound("pongdu_syringe_inject", false, 1.0)
    if audio then audio:setVolume(0.6) end

    player:Say(getText("IGUI_donation_instant_heal_say"))

    print(LOG .. "healed parts=" .. tostring(healedParts)
        .. " stiffnessCleared=" .. tostring(clearedStiffness)
        .. " cureInfection=" .. tostring(cureInfection)
        .. " infectedPartsKept=" .. tostring(keptInfected)
        .. " sender=" .. tostring(sender))
end

return _a
