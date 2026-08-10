local _a = {moodleMap = {
    ["IGUI_moodle_Drunk"]     = {type = MoodleType.Drunk},
    ["IGUI_moodle_Endurance"] = {type = MoodleType.Endurance},
    ["IGUI_moodle_Food"]      = {type = "food"},
    ["IGUI_moodle_Panic"]     = {type = MoodleType.Panic},
    ["IGUI_moodle_Stress"]    = {type = MoodleType.Stress},
    ["IGUI_moodle_Tired"]     = {type = MoodleType.Tired},
    ["IGUI_moodle_Unhappy"]   = {type = MoodleType.Unhappy},
}}
local _b = require("constants")
local _c = require("global")

-- 모든 버프/디버프의 증감폭은 "해당 스탯 전체 범위의 20%"로 통일한다.
local DELTA_PERCENT = 20

-- 스탯별 실제 스케일. 바닐라 소스 기준이며 스케일이 제각각이라 상수로 못 박아둔다.
--   Stress / Endurance / Fatigue : 0~1   (IsoGameCharacter.java:9138-9141 에서 엔진이 clamp)
--   Panic / Drunkenness         : 0~100 (엔진의 중앙 clamp 대상이 아님 -> 아래 shiftStat이 직접 처리)
--   Unhappyness (BodyDamage)    : 0~100 (UpdateBoredom() 조건부 clamp라 매 틱 보장 안 됨 -> 동일하게 shiftStat이 처리)
local SCALE_UNIT    = 1
local SCALE_PERCENT = 100

-- Panic/Drunkenness는 calculateStats()의 clamp 목록에 없다. 바닐라는 값을 바꾸는
-- 지점마다 개별적으로 0~100 경계를 강제하는 방식이라(BodyDamage.java:374-376,
-- 429-431, 474-475, 2055-2057 / IsoGameCharacter.java:8212-8214), Lua의
-- setPanic()/setDrunkenness()로 직접 쓰면 그 경계가 통째로 우회된다.
-- 그래서 여기서 직접 clamp한다. Stress/Endurance는 엔진이 다음 tick에 잘라주지만,
-- 그 사이 한 tick 동안 범위 밖 값이 노출되므로 동일하게 처리한다.
local function shiftStat(current, deltaPercent, scaleMax)
    local v = current + (deltaPercent / 100) * scaleMax
    if v < 0 then return 0 end
    if v > scaleMax then return scaleMax end
    return v
end

-- Stats.getStress()는 순수 stress가 아니라 stress + stressFromCigarettes 합산을
-- 돌려주는데(Stats.java:309-311), setStress()는 stress 본체만 쓴다(Stats.java:317-319).
-- 그래서 setStress(getStress() - d)를 그대로 하면 골초(Smoker) 캐릭터의 담배
-- 스트레스분이 매번 stress 본체로 복사되어 누적된다. 담배분(최대 0.51,
-- Stats.java:329-331)이 감소폭보다 크면 "스트레스 감소 버프인데 오히려 증가"하는
-- 현상이 나온다. 순수 stress = getStress() - getStressFromCigarettes()로 역산해서
-- 그 값에만 증감을 적용한다.
local function getPureStress(stats)
    return stats:getStress() - stats:getStressFromCigarettes()
end

-- 배고픔/포만감처럼 "1차 풀부터 먼저 소진하고, 남은 만큼 2차 풀을 소진"하는 패턴.
-- amount만큼 줄여야 할 때, primary를 0이 될 때까지 먼저 깎고, 그러고도 남는
-- 양만큼만 secondary를 깎는다. 두 풀 다 0 밑으로는 안 내려간다.
local function drainSequential(primaryBefore, secondaryBefore, amount)
    local primaryAfter = primaryBefore - amount
    if primaryAfter < 0 then primaryAfter = 0 end
    local consumed = primaryBefore - primaryAfter
    local secondaryAfter = secondaryBefore - (amount - consumed)
    if secondaryAfter < 0 then secondaryAfter = 0 end
    return primaryAfter, secondaryAfter
end

-- 모든 스탯 핸들러가 "라벨 이전값 -> 이후값" 형태로 통일해서 찍도록 하는 헬퍼.
-- Stress는 순수값 외에 담배로 인한 스트레스분과 실제 체감(getStress) 합산도 같이
-- 남겨서, 다음에 비슷한 문제가 생겨도 콘솔 로그만으로 원인 판정이 가능하게 한다.
local function logShift(label, before, after)
    _c.b(label .. " " .. tostring(before) .. " -> " .. tostring(after))
end

-- 배고픔(Stats.hunger, 0~1)과 포만감(BodyDamage.HealthFromFoodTimer, 0~11000)은
-- 원래 서로 별개인 값이라 하나만 조작하면 "배고픈데 포만감은 맥스" 같은 모순이
-- 생길 수 있었다. 여기서는 둘을 백분율(-100~100)의 한 축으로 합쳐서 다룬다:
-- 음수 방향은 배고픔, 양수 방향은 포만감이고 0이 중립(안 배고프고 안 배부름).
-- percent 인자가 양수면 포만 방향(버프), 음수면 배고픔 방향(디버프)으로 이동시킨다.
-- 예: 배고픔 10%인 상태(net=-10)에서 +20 적용 -> net=10 -> 배고픔 0, 포만감 10%.
--
-- FOOD_FULLNESS_BASIS: BodyDamage.HealthFromFoodTimer의 게임 내 절대 상한.
-- 근거: PZ-Library "PZ 41.78.19 Java decompiled/source/zombie/characters/BodyDamage/BodyDamage.java:572-573"
--   if (getHealthFromFoodTimer() > 11000.0F) setHealthFromFoodTimer(11000.0F);
local FOOD_FULLNESS_BASIS = 11000

local function applyFoodDelta(character, percent)
    if not character then return end
    local stats = character:getStats()
    local bodyDamage = character:getBodyDamage()

    local hungerPct = stats:getHunger() * 100
    local fullPct = bodyDamage:getHealthFromFoodTimer() / FOOD_FULLNESS_BASIS * 100
    if fullPct < 0 then fullPct = 0 end
    if fullPct > 100 then fullPct = 100 end

    local net = fullPct - hungerPct + percent
    if net > 100 then net = 100 end
    if net < -100 then net = -100 end

    if net >= 0 then
        stats:setHunger(0)
        bodyDamage:setHealthFromFoodTimer((net / 100) * FOOD_FULLNESS_BASIS)
    else
        stats:setHunger((-net) / 100)
        bodyDamage:setHealthFromFoodTimer(0)
    end

    _c.b("applyFoodDelta percent=" .. tostring(percent) .. " hungerPct=" .. tostring(hungerPct)
        .. " fullPct=" .. tostring(fullPct) .. " net=" .. tostring(net))
end

function _a.a(a, b)
    if not a then return end
    _c.b("applyMoodleEffect FUNCTION START key=" .. tostring(b))
    local c = a:getStats()
    local d = {
        [MoodleType.Drunk] = function()
            local before = c:getDrunkenness()
            local after = shiftStat(before, DELTA_PERCENT, SCALE_PERCENT)
            c:setDrunkenness(after)
            logShift("Drunk", before, after)
        end,
        [MoodleType.Endurance] = function()
            local before = c:getEndurance()
            local after = shiftStat(before, -DELTA_PERCENT, SCALE_UNIT)
            c:setEndurance(after)
            logShift("Endurance", before, after)
        end,
        [MoodleType.Panic] = function()
            local before = c:getPanic()
            local after = shiftStat(before, DELTA_PERCENT, SCALE_PERCENT)
            c:setPanic(after)
            logShift("Panic", before, after)
        end,
        [MoodleType.Stress] = function()
            local before = getPureStress(c)
            local after = shiftStat(before, DELTA_PERCENT, SCALE_UNIT)
            c:setStress(after)
            logShift("Stress(pure)", before, after)
            local cig = c:getStressFromCigarettes()
            _c.b("Stress cigarettes " .. tostring(cig) .. " -> " .. tostring(cig)
                .. " feltBefore=" .. tostring(before + cig)
                .. " feltAfter=" .. tostring(after + cig))
        end,
        [MoodleType.Tired] = function()
            local before = c:getFatigue()
            local after = shiftStat(before, DELTA_PERCENT, SCALE_UNIT)
            c:setFatigue(after)
            logShift("Fatigue", before, after)
        end,
        [MoodleType.Unhappy] = function()
            local bd = a:getBodyDamage()
            local before = bd:getUnhappynessLevel()
            local after = shiftStat(before, DELTA_PERCENT, SCALE_PERCENT)
            bd:setUnhappynessLevel(after)
            logShift("Unhappy", before, after)
        end,
    }
    local e = _a.moodleMap[b]
    if e then
        if e.type == "food" then
            applyFoodDelta(a, -DELTA_PERCENT)
        else
            local f = d[e.type]
            if f then f() end
        end
    end
    _c.b("applyMoodleEffect FUNCTION END")
end

function _a.b(a, b)
    if not a then return end
    _c.b("applyMoodleBuffEffect FUNCTION START key=" .. tostring(b))
    local c = {
        ["IGUI_buff_moodle_Drunk"]     = {type = MoodleType.Drunk},
        ["IGUI_buff_moodle_Endurance"] = {type = MoodleType.Endurance},
        ["IGUI_buff_moodle_Food"]      = {type = "food"},
        ["IGUI_buff_moodle_Panic"]     = {type = MoodleType.Panic},
        ["IGUI_buff_moodle_Stress"]    = {type = MoodleType.Stress},
        ["IGUI_buff_moodle_Tired"]     = {type = MoodleType.Tired},
        ["IGUI_buff_moodle_Unhappy"]   = {type = MoodleType.Unhappy},
    }
    local d = a:getStats()
    local e = {
        [MoodleType.Drunk] = function()
            local before = d:getDrunkenness()
            local after = shiftStat(before, -DELTA_PERCENT, SCALE_PERCENT)
            d:setDrunkenness(after)
            logShift("Drunk", before, after)
        end,
        [MoodleType.Endurance] = function()
            local before = d:getEndurance()
            local after = shiftStat(before, DELTA_PERCENT, SCALE_UNIT)
            d:setEndurance(after)
            logShift("Endurance", before, after)
        end,
        [MoodleType.Panic] = function()
            local before = d:getPanic()
            local after = shiftStat(before, -DELTA_PERCENT, SCALE_PERCENT)
            d:setPanic(after)
            logShift("Panic", before, after)
        end,
        [MoodleType.Stress] = function()
            -- 담배 스트레스분(stressFromCigarettes, 최대 0.51, Stats.java:329)을
            -- 먼저 깎고, 그러고도 남는 감소량만 순수 stress에서 마저 깎는다.
            -- 포만감/배고픔을 하나의 축으로 순차 소진하는 것과 같은 패턴이다.
            -- 순수 stress부터 깎으면 담배분이 남아있는 동안은 체감 스트레스
            -- (getStress 합산)가 거의 안 줄어드는 문제가 있었다.
            local amount = (DELTA_PERCENT / 100) * SCALE_UNIT
            local cigBefore = d:getStressFromCigarettes()
            local pureBefore = getPureStress(d)

            local cigAfter, pureAfter = drainSequential(cigBefore, pureBefore, amount)
            d:setStressFromCigarettes(cigAfter)
            d:setStress(pureAfter)

            logShift("Stress(cig)", cigBefore, cigAfter)
            logShift("Stress(pure)", pureBefore, pureAfter)
            _c.b("Stress feltBefore=" .. tostring(pureBefore + cigBefore)
                .. " feltAfter=" .. tostring(pureAfter + cigAfter))
        end,
        [MoodleType.Tired] = function()
            local before = d:getFatigue()
            local after = shiftStat(before, -DELTA_PERCENT, SCALE_UNIT)
            d:setFatigue(after)
            logShift("Fatigue", before, after)
        end,
        [MoodleType.Unhappy] = function()
            local bd = a:getBodyDamage()
            local before = bd:getUnhappynessLevel()
            local after = shiftStat(before, -DELTA_PERCENT, SCALE_PERCENT)
            bd:setUnhappynessLevel(after)
            logShift("Unhappy", before, after)
        end,
    }
    local f = c[b]
    if f then
        if f.type == "food" then
            applyFoodDelta(a, DELTA_PERCENT)
        else
            local g = e[f.type]
            if g then g() end
        end
    end
    _c.b("applyMoodleBuffEffect FUNCTION END")
end
return _a
