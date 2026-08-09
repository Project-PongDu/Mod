local constants = {
    IGUI_moodle_Types = {
        "IGUI_moodle_Drunk",
        "IGUI_moodle_Endurance",
        "IGUI_moodle_Food",
        "IGUI_moodle_Panic",
        "IGUI_moodle_Stress",
        "IGUI_moodle_Tired",
        "IGUI_moodle_Unhappy",
    },
    IGUI_buff_moodle_Types = {
        "IGUI_buff_moodle_Drunk",
        "IGUI_buff_moodle_Endurance",
        "IGUI_buff_moodle_Food",
        "IGUI_buff_moodle_Panic",
        "IGUI_buff_moodle_Stress",
        "IGUI_buff_moodle_Tired",
        "IGUI_buff_moodle_Unhappy",
    },
}

-- Zombie roulette: 이전엔 고정 5단계(2~6마리, 균등 20가중치) 텍스트 키
-- (IGUI_zombie1..5)를 뽑는 방식이었으나, 샌드박스 PongDu.Roulette_MinCount /
-- Roulette_MaxCount로 범위를 직접 설정하도록 바뀌면서 이 테이블은 더 이상
-- 쓰이지 않는다. 실제 마릿수 추첨은 utils/updateText.lua의 _a.c()가
-- ZombRand(min, max+1)로 직접 처리한다.

return constants
