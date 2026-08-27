-- featureId -> IGUI 번역키. 큐박스 라벨(DonationReceiver)과 우클릭 어드민
-- 테스트 메뉴(DonationTestMenu)가 공용으로 쓴다. 원래 DonationReceiver.lua에
-- 로컬로 박혀 있던 걸 두 번째 소비처가 생기면서 여기로 뽑았다.
--
-- Effect labels are resolved via getText() at render time, so the Korean text
-- lives in media/lua/shared/Translate/KO/IG_UI_KO.txt, never as raw/escaped
-- Korean in this file.
-- ※ 예전 주석에 "random_weapon 이하 8개는 번역이 없다"고 돼있었는데 실제로 확인해보니
-- 틀린 얘기였음 -- revive_ticket / secret_passage_kit / horde_night 이 3개만 IG_UI_KO.txt에
-- 없었고 (getText가 키 이름을 그대로 보여주는 중이었음) 나머지는 전부 이미 번역돼있었다.
-- 이 3개는 IG_UI_KO.txt에 추가해서 해결함 (부활 티켓 / 비밀 통로 키트 / 호드 나이트).
return {
    ["debuff_roulette"]      = "IGUI_donation_debuff_roulette",
    ["buff_roulette"]        = "IGUI_donation_buff_roulette",
    ["zombie_roulette"]      = "IGUI_donation_zombie_roulette",
    ["sprinter5"]            = "IGUI_donation_sprinter",
    ["bandit_melee"]         = "IGUI_donation_hitman_melee",
    ["vaccine"]              = "IGUI_donation_vaccine",
    ["bandit_ranged"]        = "IGUI_donation_hitman_ranged",
    ["exile"]                = "IGUI_donation_exile",
    ["random_teleport"]      = "IGUI_donation_random_teleport",
    ["backroom"]             = "IGUI_donation_backroom",
    ["missile"]              = "IGUI_donation_bombard",
    ["random_weapon"]        = "IGUI_donation_random_weapon",
    ["random_skill_potion"]  = "IGUI_donation_random_skill_potion",
    ["vehicle_drop"]         = "IGUI_donation_vehicle_drop",
    ["inv_save_ticket"]      = "IGUI_donation_inv_save_ticket",
    ["revive_ticket"]        = "IGUI_donation_revive_ticket",
    ["mutant_spawn"]         = "IGUI_donation_mutant_spawn",
    ["secret_passage_kit"]   = "IGUI_donation_secret_passage_kit",
    ["horde_night"]          = "IGUI_donation_horde_night",
    ["blood_moon"]           = "IGUI_donation_blood_moon",
    ["medical_box"]          = "IGUI_donation_medical_box",
    ["rise_up_dead_man"]     = "IGUI_donation_rise_up_dead_man",
    ["zombie_rain"]          = "IGUI_donation_zombie_rain",
    ["fire_support"]         = "IGUI_donation_fire_support",
    ["food_supply"]          = "IGUI_donation_food_supply",
    ["instant_heal"]         = "IGUI_donation_instant_heal",
    ["random_injury"]        = "IGUI_donation_random_injury",
}
