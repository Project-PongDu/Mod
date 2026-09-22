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
--
-- ※ 반환 형태가 평평한 테이블에서 { map, resolve } 로 바뀌었다(utils/colorMap 과 동일).
--   labelKey[featureId] 로 직접 인덱싱하던 코드는 labelKey.resolve(featureId) 를 쓴다.
--   샌드박스 설정에 따라 표시 이름이 갈리는 기능이 셋으로 늘면서, 같은 분기가
--   DonationReceiver 와 DonationTestMenu 양쪽에 복사돼 있던 걸 여기로 합쳤다.
local map = {
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

-- ── 샌드박스 설정에 따라 표시 이름이 갈리는 기능 ──────────────────────────
-- 위 map 은 "기능 하나 = 이름 하나"지만, 아래 셋은 설정에 따라 실제로 벌어지는
-- 일이 달라져서 큐박스/호버툴팁에 뜨는 이름도 같이 갈려야 한다.
--   missile          : Bombard_Injure  켜짐 -> 유도 폭격 / 꺼짐 -> 지원 폭격
--   zombie_rain      : Rain_Style      1 -> 좀비 레인 / 2 -> 좀비 공중투하
--   rise_up_dead_man : RiseUp_Style    1 -> 강령술 / 2 -> 재활성화 가스 살포
-- zombie_rain 은 map 의 키가 카테고리 이름("좀비 공습")이라 방식별 키를 둘 다
-- 새로 만들었다 -- 카테고리 이름은 낙하 타이머 패널(features/zombierain.lua)이
-- 계속 쓰므로 그대로 둬야 한다.
-- rise_up_dead_man 은 map 의 키가 이미 방식 1 의 이름("강령술")이라 그대로 쓴다.
--
-- SandboxVars 는 게임 로드 후에만 존재하므로 파일 로드 시점이 아니라
-- 호출 시점에 읽는다. 등록된 옵션은 로드 후 항상 값이 있으므로 폴백은 두지 않고,
-- 범위를 벗어난 값만 1번으로 접는다.
local function resolve(featureId)
    if featureId == "missile" then
        if SandboxVars.PongDu.Bombard_Injure then
            return "IGUI_donation_bombard_guided"
        end
        return "IGUI_donation_bombard_support"
    end
    if featureId == "zombie_rain" then
        if SandboxVars.PongDu.Rain_Style == 2 then
            return "IGUI_donation_zombie_rain_airdrop"
        end
        return "IGUI_donation_zombie_rain_fall"
    end
    if featureId == "rise_up_dead_man" then
        if SandboxVars.PongDu.RiseUp_Style == 2 then
            return "IGUI_donation_rise_up_gas"
        end
        return "IGUI_donation_rise_up_dead_man"
    end
    return map[featureId]
end

return { map = map, resolve = resolve }
