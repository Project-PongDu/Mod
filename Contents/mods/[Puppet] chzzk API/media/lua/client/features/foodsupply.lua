local _a = {}

-- ── 식량 보급 (food_supply) 클라이언트 ───────────────────────────────────────
--
-- 후원자 개인 버프 계열. 후원이 발동하면 바닐라 감자칩(Base.Crisps)을
-- 샌드박스 FoodSupply_Count 개수만큼 인벤토리에 넣고, 표시명을 번역키
-- IGUI_donation_food_supply_item 으로 갈아끼운다.
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

local LOG       = "[PongDu][FoodSupply] "
local ITEM_TYPE = "Base.Crisps"

function _a.a(sender)
    local player = global.player
    if not player then
        print(LOG .. "supply aborted: player is nil")
        return
    end

    -- 샌드박스는 파일 로드 시점이 아니라 사용 시점에 읽는다.
    local count = SandboxVars.PongDu.FoodSupply_Count

    local inventory = player:getInventory()
    local label     = getText("IGUI_donation_food_supply_item")
    local delivered = 0

    for i = 1, count do
        local item = inventory:AddItem(ITEM_TYPE)
        if not item then
            print(LOG .. "AddItem returned nil (item=" .. ITEM_TYPE
                .. ", index=" .. i .. "/" .. tostring(count) .. ")")
            break
        end
        item:setName((sender or "") .. "'s " .. label)
        item:getModData().t3Donor = sender or ""
        delivered = delivered + 1
    end

    if delivered <= 0 then
        print(LOG .. "supply FAILED: nothing delivered (sender=" .. tostring(sender) .. ")")
        return
    end

    local audio = getSoundManager():PlaySound("pongdu_supply", false, 1.0)
    if audio then audio:setVolume(0.5) end

    print(LOG .. "delivered " .. delivered .. "/" .. tostring(count)
        .. " (item=" .. ITEM_TYPE .. ", sender=" .. tostring(sender) .. ")")
end

return _a
