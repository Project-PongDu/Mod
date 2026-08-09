local _a = {moodleMap = {
    ["IGUI_moodle_Type2"]  = {type = MoodleType.Bleeding},
    ["IGUI_moodle_Type6"]  = {type = MoodleType.Drunk},
    ["IGUI_moodle_Type7"]  = {type = MoodleType.Endurance},
    ["IGUI_moodle_Food"]   = {type = "food"},
    ["IGUI_moodle_Type17"] = {type = MoodleType.Panic},
    ["IGUI_moodle_Type19"] = {type = MoodleType.Stress},
}}
local _b = require("constants")
local _c = require("global")

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
    local fullPct = math.min(bodyDamage:getHealthFromFoodTimer() / FOOD_FULLNESS_BASIS * 100, 100)

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
    _c.b("applyMoodleEffect FUNCTION START")
    local c = a:getStats()
    local d = {
        [MoodleType.Bleeding] = function()
            local e = a:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
            e:setBleeding(true)
        end,
        [MoodleType.Drunk] = function()
            local e = c:getDrunkenness() + 30
            c:setDrunkenness(e)
        end,
        [MoodleType.Endurance] = function()
            c:setEndurance(c:getEndurance() - 0.3)
        end,
        [MoodleType.Panic] = function()
            c:setPanic(c:getPanic() + 30)
        end,
        [MoodleType.Stress] = function()
            c:setStress(c:getStress() + 0.3)
        end,
    }
    local e = _a.moodleMap[b]
    if e then
        if e.type == "food" then
            applyFoodDelta(a, -20)
        else
            local f = d[e.type]
            if f then f() end
        end
    end
    _c.b("applyMoodleEffect FUNCTION END")
end

function _a.b(a, b)
    if not a then return end
    _c.b("applyMoodleBuffEffect FUNCTION START")
    local c = {
        ["IGUI_buff_moodle_Type6"]  = {type = MoodleType.Drunk},
        ["IGUI_buff_moodle_Type7"]  = {type = MoodleType.Endurance},
        ["IGUI_buff_moodle_Food"]   = {type = "food"},
        ["IGUI_buff_moodle_Type17"] = {type = MoodleType.Panic},
        ["IGUI_buff_moodle_Type19"] = {type = MoodleType.Stress},
    }
    local d = a:getStats()
    local e = {
        [MoodleType.Bleeding] = function()
            local f = a:getBodyDamage():getBodyPart(BodyPartType.ForeArm_L)
            f:setBleeding(true)
        end,
        [MoodleType.Drunk] = function()
            d:setDrunkenness(d:getDrunkenness() - 30)
        end,
        [MoodleType.Endurance] = function()
            d:setEndurance(d:getEndurance() + 0.3)
        end,
        [MoodleType.Panic] = function()
            d:setPanic(d:getPanic() - 30)
        end,
        [MoodleType.Stress] = function()
            d:setStress(d:getStress() - 0.3)
        end,
    }
    local f = c[b]
    if f then
        if f.type == "food" then
            applyFoodDelta(a, 20)
        else
            local g = e[f.type]
            if g then g() end
        end
    end
    _c.b("applyMoodleBuffEffect FUNCTION END")
end
return _a
