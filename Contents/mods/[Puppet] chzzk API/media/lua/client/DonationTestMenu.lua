--
-- ***********************************
-- *** [PongDu] 도네이션 (테스트)  ***
-- ***********************************
-- MutantMenu.lua의 WorldContextMenuPre 패턴 이식. 어드민(또는 디버그)일 때만
-- 우클릭 컨텍스트메뉴에 "[PongDu] 도네이션" 항목이 뜨고, 그 안에서
-- 긍정효과 / 부정효과 / dev 세 서브메뉴로 나뉜다.
--
-- 항목 클릭 = PongDuDonationTest.inject() 호출 -> 실제 도네이션과 완전히 같은
-- 경로(donationQueue -> 큐박스 슬롯 -> 안전지대 락 -> 카운트다운 -> 발동)를
-- 태운다. MutantMenu의 특좀 소환처럼 즉시 발동이 아니라 "가짜 후원 1건"이
-- 들어온 것과 동일하게 동작하는 게 목적. 통계(PongDuStats)에는 안 잡힘.
--
-- ── 분류 기준 ──
-- 샌드박스 옵션의 PongDu_Buff / PongDu_Debuff / PongDu_Server / PongDu_Dev
-- 4개 탭과 featureId 묶음이 그대로 1:1 대응한다.
--
-- exile(산타마을 유배) / backroom(백룸 탈출)은 rewardManager에서 발동을 완전히
-- 죽인 더미 핸들러지만, featureId 자체는 getFeatureIds()에 남아있어 미분류로
-- 새는 걸 막기 위해 dev에 명시적으로 묶어둔다.
--
-- CATEGORY에 없는데 rewardManager.getFeatureIds()에 새로 나타나는 featureId가
-- 있으면(= 신규 기능 추가하고 여기 분류를 깜빡한 경우) dev로 폴백시키고
-- 콘솔에 경고를 남긴다 -- 조용히 씹어서 메뉴에서 안 보이는 것보다는 낫다.

DonationTestMenu = DonationTestMenu or {}

local rewardManager = require("rewards/rewardManager")
local labelKey       = require("utils/labelKey")

local BUFF = {
    "buff_roulette", "vaccine", "random_skill_potion", "random_weapon",
    "vehicle_drop", "inv_save_ticket", "fire_support",
}

local DEBUFF = {
    "debuff_roulette", "zombie_roulette", "sprinter5", "random_teleport",
    "missile", "mutant_spawn", "rise_up_dead_man", "zombie_rain",
}

local SERVER = {
    "horde_night", "medical_box",
}

local DEV = {
    "bandit_melee", "bandit_ranged", "revive_ticket", "secret_passage_kit",
    "exile", "backroom",
}

-- 카테고리 라벨은 전부 getText()로 뽑는다. ContextMenu_KO.txt에 실제 한글이
-- 있고, 이 파일엔 번역키 이름만 남는다 (PZ 번역파일 인코딩 규칙 -- .lua에
-- 한글 원문을 직접 박지 않는다).
local CATEGORY_LIST = {
    { key = "buff",   label = getText("ContextMenu_PongDu_Buff"),   ids = BUFF },
    { key = "debuff", label = getText("ContextMenu_PongDu_Debuff"), ids = DEBUFF },
    { key = "server", label = getText("ContextMenu_PongDu_Server"), ids = SERVER },
    { key = "dev",    label = getText("ContextMenu_PongDu_Dev"),    ids = DEV },
}

function DonationTestMenu.Fire(player, featureId)
    if PongDuDonationTest and PongDuDonationTest.inject then
        PongDuDonationTest.inject(featureId, "Admin", "0", "")
    end
end

-- featureId의 한글 표시 라벨. IG_UI_KO.txt에 번역이 있으면 그걸 쓰고, 없으면
-- (아직 번역이 안 붙은 신규 기능) featureId 원문을 그대로 보여준다 -- 메뉴
-- 항목이 통째로 사라지는 것보다 영문 featureId가 보이는 편이 디버깅에 낫다.
local function displayLabel(featureId)
    local key = labelKey[featureId]
    if key then return getText(key) end
    return featureId
end

function DonationTestMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    if not (isAdmin() or isDebugEnabled()) then return end

    local player = getSpecificPlayer(playerID)
    if not player then return end

    -- 분류표에 없는 featureId 추적용. CATEGORY_LIST를 훑어 뺀 나머지가
    -- getFeatureIds() 결과에 남으면 분류를 깜빡한 신규 기능이다.
    local uncategorized = {}
    for _, id in ipairs(rewardManager.getFeatureIds()) do
        uncategorized[id] = true
    end

    local rootOption = context:addOption(getText("ContextMenu_PongDu_Root"))
    local rootMenu = context:getNew(context)
    context:addSubMenu(rootOption, rootMenu)

    for _, category in ipairs(CATEGORY_LIST) do
        local catOption = rootMenu:addOption(category.label)
        local catMenu = rootMenu:getNew(rootMenu)
        rootMenu:addSubMenu(catOption, catMenu)

        for _, featureId in ipairs(category.ids) do
            if uncategorized[featureId] then
                catMenu:addOption(displayLabel(featureId), player, DonationTestMenu.Fire, featureId)
                uncategorized[featureId] = nil
            end
        end
    end

    -- 분류를 깜빡한 신규 featureId는 dev 서브메뉴에 있던 catMenu 참조가
    -- 루프 밖이라 못 넣으니, 별도 "(미분류)" 서브메뉴로 따로 묶어 눈에 띄게 한다.
    local leftover = {}
    for id, _ in pairs(uncategorized) do table.insert(leftover, id) end
    if #leftover > 0 then
        table.sort(leftover)
        print("[PongDuTestMenu] WARNING: uncategorized featureId(s) in DonationTestMenu.lua: "
            .. table.concat(leftover, ", ") .. " (falling back to misc submenu)")

        local miscOption = rootMenu:addOption(getText("ContextMenu_PongDu_Misc"))
        local miscMenu = rootMenu:getNew(rootMenu)
        rootMenu:addSubMenu(miscOption, miscMenu)
        for _, featureId in ipairs(leftover) do
            miscMenu:addOption(displayLabel(featureId), player, DonationTestMenu.Fire, featureId)
        end
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(DonationTestMenu.WorldContextMenuPre)
