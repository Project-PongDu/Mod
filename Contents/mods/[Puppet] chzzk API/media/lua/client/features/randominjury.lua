local _a = {}

-- ── 랜덤 부위 랜덤 부상 (random_injury) 클라이언트 ───────────────────────────
--
-- 후원자 개인 디버프. 머리/목을 제외한 부위 중 하나를 뽑아 부상 1종을 입힌다.
-- 부상 종류는 샌드박스에서 종류별로 개별 on/off 가능하며, 발동 1회당 몇 개를
-- 입힐지는 Injury_Count 로 정한다.
--
-- 머리/목 제외 이유: Neck 은 생성자에서 DamageScaler 가 5배로 잡혀 있고
-- (BodyPart.java:78-80), Head 는 상시 노출 부위라 방어구로 막을 수단이 사실상
-- 없다. 둘 다 후원 한 번에 즉사에 가까운 결과가 나올 수 있어 밸런스상 뺀다.
-- 인덱스를 하드코딩하지 않고 BodyPartType 에서 매번 만들어 쓴다.
--
-- 구현 근거 (B41 41.78.20 BodyPart.java 확인):
--   * setScratched(true, forceNoInfection) / setCut(true, forceNoInfection)
--     -- forceNoInfection=false 일 때만 generateZombieInfection() 이 돌아
--     각각 7% / 25% 확률로 좀비 감염이 붙는다. 기본은 감염 없음(true).
--   * SetBitten(true) 1인자 버전만 biteTime / setInfectedWound(true) /
--     generateBleeding() 을 제대로 채운다. 2인자 버전은 이것들을 건너뛰므로
--     쓰지 않는다. 대신 감염을 뺄 때는 호출 직후 SetInfected/SetFakeInfected 를
--     false 로 되돌린다 (바닐라 ISHealthPanel 의 bite 토글과 동일한 방식).
--     이때 남는 setInfectedWound(true) 는 상처 감염(항생제 대상)이지 좀비
--     감염이 아니므로 물린 상처 연출로 그대로 둔다.
--   * generateDeepShardWound() 는 깊은 상처 + 유리 파편을 같이 만든다.
--   * setBurned() 는 burnTime 50~100 + 화상 세척 필요 플래그를 세운다.
--   * setHaveBullet(true, 0) 은 총알 박힘 + 출혈을 만든다.
--   * 골절은 전용 생성 함수가 없어 setFractureTime() 을 직접 쓴다. 값 범위는
--     BodyDamage.AddRandomDamage() 의 Rand.Next(30, 50) 과 맞춘다.
--     바닐라 골절 자체를 끈 서버(SandboxVars.BoneFracture=false)에서는
--     후보에서 제외한다.
--
-- 전부 로컬 플레이어 자신의 BodyDamage 조작이라 서버 커맨드가 필요 없다.
-- 소리를 내지 않으므로 좀비 어그로도 붙지 않는다.

local global = require("global")

local LOG = "[PongDu][RandomInjury] "

-- id            : 로그용 영문 식별자
-- option        : SandboxVars.PongDu 의 on/off 키
-- key           : Say 표시용 번역 키
-- apply(part, allowInfection)
local INJURY_TYPES = {
    {
        id = "scratch", option = "Injury_Scratch", key = "IGUI_donation_injury_scratch",
        apply = function(part, allowInfection) part:setScratched(true, not allowInfection) end,
    },
    {
        id = "cut", option = "Injury_Cut", key = "IGUI_donation_injury_cut",
        apply = function(part, allowInfection) part:setCut(true, not allowInfection) end,
    },
    {
        id = "deep_wound", option = "Injury_DeepWound", key = "IGUI_donation_injury_deep_wound",
        apply = function(part) part:generateDeepWound() end,
    },
    {
        id = "glass", option = "Injury_Glass", key = "IGUI_donation_injury_glass",
        apply = function(part) part:generateDeepShardWound() end,
    },
    {
        id = "bite", option = "Injury_Bite", key = "IGUI_donation_injury_bite",
        apply = function(part, allowInfection)
            part:SetBitten(true)
            if not allowInfection then
                part:SetInfected(false)
                part:SetFakeInfected(false)
            end
        end,
    },
    {
        id = "burn", option = "Injury_Burn", key = "IGUI_donation_injury_burn",
        apply = function(part) part:setBurned() end,
    },
    {
        id = "bullet", option = "Injury_Bullet", key = "IGUI_donation_injury_bullet",
        apply = function(part) part:setHaveBullet(true, 0) end,
    },
    {
        id = "fracture", option = "Injury_Fracture", key = "IGUI_donation_injury_fracture",
        vanillaGate = function() return SandboxVars.BoneFracture end,
        apply = function(part) part:setFractureTime(ZombRand(30, 51)) end,
    },
}

-- 머리/목을 뺀 부위 인덱스 목록을 새로 만들어 반환한다.
local function buildPartPool()
    local pool = {}
    local headIdx = BodyPartType.ToIndex(BodyPartType.Head)
    local neckIdx = BodyPartType.ToIndex(BodyPartType.Neck)
    local maxIdx  = BodyPartType.ToIndex(BodyPartType.MAX)
    for i = 0, maxIdx - 1 do
        if i ~= headIdx and i ~= neckIdx then
            pool[#pool + 1] = i
        end
    end
    return pool
end

-- 샌드박스에서 켜져 있고 바닐라 게이트도 통과한 부상 종류만 모은다.
local function buildTypePool()
    local sv = SandboxVars.PongDu
    local pool = {}
    for i = 1, #INJURY_TYPES do
        local t = INJURY_TYPES[i]
        if sv[t.option] and (t.vanillaGate == nil or t.vanillaGate()) then
            pool[#pool + 1] = t
        end
    end
    return pool
end

function _a.a(sender)
    local player = global.player
    if not player then
        print(LOG .. "injury aborted: player is nil")
        return
    end

    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        print(LOG .. "injury aborted: bodyDamage is nil")
        return
    end

    local sv = SandboxVars.PongDu
    local count          = sv.Injury_Count
    local allowInfection = sv.Injury_Infection

    local typePool = buildTypePool()
    if #typePool == 0 then
        print(LOG .. "injury SKIPPED: every injury type is disabled in sandbox"
            .. " (sender=" .. tostring(sender) .. ")")
        return
    end

    -- 같은 부위에 몰리지 않도록 뽑은 부위는 풀에서 빼고, 풀이 마르면 다시 채운다.
    local partPool = buildPartPool()
    local applied = 0
    local lastPartName, lastInjuryKey

    for _ = 1, count do
        if #partPool == 0 then partPool = buildPartPool() end

        local pick     = ZombRand(1, #partPool + 1)
        local partIdx  = partPool[pick]
        table.remove(partPool, pick)

        local partType = BodyPartType.FromIndex(partIdx)
        local part     = bodyDamage:getBodyPart(partType)
        if not part then
            print(LOG .. "getBodyPart returned nil (index=" .. tostring(partIdx) .. ")")
        else
            local injury = typePool[ZombRand(1, #typePool + 1)]
            injury.apply(part, allowInfection)
            applied = applied + 1
            lastPartName  = BodyPartType.getDisplayName(partType)
            lastInjuryKey = injury.key
            print(LOG .. "applied injury=" .. injury.id
                .. " part=" .. BodyPartType.ToString(partType)
                .. " allowInfection=" .. tostring(allowInfection))
        end
    end

    if applied <= 0 then
        print(LOG .. "injury FAILED: nothing applied (sender=" .. tostring(sender) .. ")")
        return
    end

    -- 여러 개를 한 번에 입힌 경우 마지막 1건만 말풍선에 띄운다. 부위/부상마다
    -- Say 를 반복하면 이전 대사가 즉시 덮여서 어차피 마지막 것만 보인다.
    player:Say(getText("IGUI_donation_injury_say", lastPartName, getText(lastInjuryKey)))

    print(LOG .. "done applied=" .. tostring(applied) .. "/" .. tostring(count)
        .. " typePool=" .. tostring(#typePool)
        .. " sender=" .. tostring(sender))
end

return _a
