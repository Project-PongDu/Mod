-- ═══════════════════════════════════════════════════════════════════════════
--  featureId -> 도네 큐박스 색상 (공용 leaf 모듈)
--
--  DonationReceiver의 큐박스와 각 feature의 카운트다운 패널이 같은 색을 쓰도록
--  색상표를 여기 한 곳에만 둔다.
--
--  ※ 이 파일은 의존성이 없어야 한다(require 금지).
--    DonationReceiver -> rewards/rewardManager -> features/* 순으로 로드되므로,
--    features/*가 DonationReceiver를 require하면 순환이 되어 PZ의
--    LuaManager.RunLua()가 "recursive require()" 경고와 함께 nil을 돌려준다.
--    그 nil을 파일 상단 local에 잡아두면 render()에서
--    "attempted index: getColor of non-table: null" 로 매 프레임 크래시한다.
-- ═══════════════════════════════════════════════════════════════════════════

local DEFAULT = {0.5, 0.5, 0.5}

local map = {
    ["debuff_roulette"]      = {0.55, 0.05, 0.95},
    ["buff_roulette"]        = {0.05, 0.45, 1.0},
    ["zombie_roulette"]      = {0.05, 0.85, 0.05},
    ["sprinter5"]            = {0.95, 0.85, 0.0},
    ["bandit_melee"]         = {1.0, 0.25, 0.0},
    ["vaccine"]              = {0.0, 0.85, 0.85},
    ["bandit_ranged"]        = {0.95, 0.0, 0.0},
    ["exile"]                = {0.95, 0.6, 0.0},
    ["random_teleport"]      = {0.1, 0.55, 1.0},
    ["backroom"]             = {0.95, 0.6, 0.0},
    ["missile"]              = {1.0, 0.15, 0.0},
    ["random_weapon"]        = {0.75, 0.75, 0.0},
    ["random_skill_potion"]  = {0.15, 0.85, 0.15},
    ["inv_save_ticket"]      = {0.95, 0.8, 0.0},
    ["vehicle_drop"]         = {0.35, 0.35, 1.0},
    ["revive_ticket"]        = {1.0, 0.35, 0.55},
    ["mutant_spawn"]         = {0.8, 0.05, 0.05},
    ["secret_passage_kit"]   = {0.65, 0.35, 0.05},
    ["horde_night"]          = {0.95, 0.0, 0.0},
    ["blood_moon"]           = {0.85, 0.1, 0.15},
    ["medical_box"]          = {0.0, 0.75, 0.55},
    ["rise_up_dead_man"]     = {0.45, 0.0, 0.6},
    ["zombie_rain"]          = {0.15, 0.4, 0.95},
    ["fire_support"]         = {0.22, 0.52, 0.18},
    ["food_supply"]          = {0.95, 0.65, 0.15},
}

local function get(featureId)
    return map[featureId] or DEFAULT
end

return { map = map, get = get }
