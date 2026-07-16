local _a = {}
local _b = require("constants")
local _c = require("global")

function _a.a()
    local a = ZombRand(1, #_b.IGUI_moodle_Types + 1)
    _c.chosenRandomText = _b.IGUI_moodle_Types[a]
    _c.player:Say(getText(_c.chosenRandomText))
end
function _a.b()
    local a = ZombRand(1, #_b.IGUI_buff_moodle_Types + 1)
    _c.chosenRandomText = _b.IGUI_buff_moodle_Types[a]
    _c.player:Say(getText(_c.chosenRandomText))
end
-- Zombie roulette: 샌드박스 PongDu.Roulette_MinCount / Roulette_MaxCount
-- (기본 2~6, 균등분포)로 직접 마릿수를 추첨한다. 이전엔 IGUI_zombie1..5
-- 텍스트 키 5종 중 하나를 골라 handler.c가 문자열 비교로 마릿수를
-- 역산했는데, 범위가 가변이 되면서 그 방식이 성립하지 않아 amount를
-- global.chosenZombieCount에 직접 저장하는 방식으로 바꿨다.
-- SandboxVars는 파일 로드 시점엔 비어있을 수 있으므로 사용 시점에 읽는다.
function _a.c()
    local sv = SandboxVars and SandboxVars.PongDu
    local minC = (sv and tonumber(sv.Roulette_MinCount)) or 2
    local maxC = (sv and tonumber(sv.Roulette_MaxCount)) or 6
    if minC < 1 then minC = 1 end
    if maxC < minC then maxC = minC end
    local amount = ZombRand(minC, maxC + 1)
    _c.chosenZombieCount = amount
    _c.player:Say(getText("IGUI_zombie_roulette_say", tostring(amount)))
end
return _a
