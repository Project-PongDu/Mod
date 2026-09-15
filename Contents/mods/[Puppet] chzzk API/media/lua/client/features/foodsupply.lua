local _a = {}

-- ── 식량 보급 (food_supply) 클라이언트 ───────────────────────────────────────
--
-- 후원자 개인 버프 계열. 후원이 발동하면 샌드박스 FoodSupply_Item 에 적힌
-- 아이템(기본값 Base.Crisps)을 FoodSupply_Count 개수만큼 인벤토리에 넣는다.
--
-- FoodSupply_Item 은 서버 운영자가 직접 입력하는 문자열이라 오타나 애드온 모드
-- 미적용(예: 스트리머 전용 모드의 아이템을 적어놓고 그 모드를 안 켠 경우)이
-- 생길 수 있다. 이건 "값이 nil" 문제가 아니라 "값이 틀림" 문제라서 sandbox
-- default 가 막아주지 못한다. 스크립트 매니저에서 찾을 수 없으면 후원이 증발하지
-- 않도록 바닐라 감자칩으로 대체 지급하고 WARN 로그를 남긴다.
--
-- 표시명은 번역키 IGUI_donation_food_supply_item 이 있을 때만 덮어쓴다.
-- 키가 없으면(번역 파일에서 지웠거나 다른 언어팩에 없는 경우) 아이템 기본
-- 이름을 그대로 둔다 -- getTextOrNull()로 키 존재 여부를 확인하고, nil이면
-- setName() 자체를 호출하지 않는다(호출하면 originalName과 달라져서 무조건
-- "번역 안 된 키 문자열"이 이름이 돼버린다).
--
-- 이름 변경이 저장되는 근거 (B41 41.78.20 InventoryItem.java 확인):
--   save() 가 `name != originalName` 일 때만 이름을 직렬화하므로,
--   setName() 만 호출해도 세이브/로드 후 그대로 유지된다.
--   setCustomName(true) 는 이름 재번역 차단용 별개 플래그라 여기선 불필요하다
--   (기존 giveSupply / medicalbox 도 setName 만 쓴다).
--
-- 지급/각인/보급음 순서는 rewards/rewardManager.lua 의 giveSupply 와 같지만,
-- 그쪽은 local 함수인 데다 "t3chzzkDonation." 모듈 접두사를 강제로 붙이고
-- 1개만 지급하므로 재사용이 안 된다. 여기서 다시 구현한다.
--   * pongdu_supply 는 getSoundManager():PlaySound() 로 재생하는 클라 로컬
--     사운드다. 월드 사운드(addSound)가 아니라 좀비 어그로가 붙지 않는다.
--   * PlaySound 의 maxGain 인자는 SoundManager.java 구현상 무시되므로 반환
--     핸들에 setVolume 을 직접 건다.
--   * 1개도 못 넣었으면 사운드를 재생하지 않는다 -- "소리는 났는데 아이템은
--     없다"가 제일 추적하기 어렵다.

local global = require("global")

local LOG               = "[PongDu][FoodSupply] "
-- FoodSupply_Item 이 잘못 입력됐을 때만 쓰는 대체 아이템 (nil fallback 아님).
local INVALID_ITEM_TYPE = "Base.Crisps"

-- FoodSupply_Item 문자열을 실제 아이템 full type("Module.Type")으로 해석한다.
-- 모듈을 생략하면 ScriptManager.FindItem 이 Base 로 간주한다.
local function resolveItemType()
    local raw     = SandboxVars.PongDu.FoodSupply_Item
    local trimmed = raw:match("^%s*(.-)%s*$")
    if trimmed == "" then
        print(LOG .. "WARN FoodSupply_Item is empty -- using " .. INVALID_ITEM_TYPE)
        return INVALID_ITEM_TYPE
    end

    local script = getScriptManager():FindItem(trimmed)
    if not script then
        print(LOG .. "WARN FoodSupply_Item '" .. trimmed
            .. "' has no item script (typo or addon mod not loaded) -- using " .. INVALID_ITEM_TYPE)
        return INVALID_ITEM_TYPE
    end

    local fullType = script:getFullName()
    if fullType ~= trimmed then
        print(LOG .. "FoodSupply_Item '" .. trimmed .. "' resolved to " .. fullType)
    end
    return fullType
end

function _a.a(sender)
    local player = global.player
    if not player then
        print(LOG .. "supply aborted: player is nil")
        return
    end

    -- 샌드박스는 파일 로드 시점이 아니라 사용 시점에 읽는다.
    local count    = SandboxVars.PongDu.FoodSupply_Count
    local itemType = resolveItemType()

    local inventory = player:getInventory()
    local label     = getTextOrNull("IGUI_donation_food_supply_item")
    -- 키가 존재하되 값이 빈 문자열(또는 공백뿐)인 경우도 "없음"과 동일하게
    -- 취급한다. Lua에서 ""는 truthy라 label만 nil 검사하면 걸러지지 않고,
    -- 그대로 setName에 들어가 "닉네임's " 처럼 이름 없는 라벨이 박혀버린다.
    if label and label:match("^%s*$") then
        label = nil
    end
    local delivered = 0

    for i = 1, count do
        local item = inventory:AddItem(itemType)
        if not item then
            print(LOG .. "AddItem returned nil (item=" .. itemType
                .. ", index=" .. i .. "/" .. tostring(count) .. ")")
            break
        end
        if label then
            item:setName((sender or "") .. "'s " .. label)
        end
        item:getModData().t3Donor = sender or ""
        delivered = delivered + 1
    end

    if not label then
        print(LOG .. "translation key IGUI_donation_food_supply_item not found -- using default item name")
    end

    if delivered <= 0 then
        print(LOG .. "supply FAILED: nothing delivered (sender=" .. tostring(sender) .. ")")
        return
    end

    local audio = getSoundManager():PlaySound("pongdu_supply", false, 1.0)
    if audio then audio:setVolume(0.5) end

    print(LOG .. "delivered " .. delivered .. "/" .. tostring(count)
        .. " (item=" .. itemType .. ", sender=" .. tostring(sender) .. ")")
end

return _a
