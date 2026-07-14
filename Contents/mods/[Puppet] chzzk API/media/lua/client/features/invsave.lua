-- invsave.lua : 인벤세이브권 (inv_save_ticket)
--
-- 인벤토리에 t3chzzkDonation.inv_save_ticket 이 있는 상태로 사망하면(좀비화 포함)
-- 티켓 1장을 소모하고 그 순간의 인벤토리 전체를 스냅샷으로 저장한 뒤, 캐릭터의
-- 인벤토리를 비운다(시체/좀비에 아무것도 남지 않음 = 이중 지급 원천 차단).
-- 리스폰(OnCreatePlayer) 3초 후 스냅샷을 복원해 새 캐릭터에게 지급하고, 입고
-- 있던 옷은 같은 부위에 자동으로 다시 입힌다.
--
-- 사망 시퀀스 근거 (PZ 41.78.19, IsoPlayer.OnDeath / IsoGameCharacter.dropHandItems):
--   dropHandItems()  ->  OnPlayerDeath 이벤트  ->  (나중에) becomeCorpse() -> 서버 전송
--   1) 양손 아이템은 OnPlayerDeath "직전"에 이미 바닥 square에 떨어진다.
--      -> OnEquipPrimary/Secondary로 "마지막으로 낀 아이템" 레퍼런스를 계속 들고
--         있다가, 사망 시 그 레퍼런스가 아직 월드에 남아있으면(아무도 안 주웠으면,
--         item:getWorldItem() ~= nil) 회수한다. 시간 필터가 아니라 "지금도 바닥에
--         있는가"로만 판정하므로, 피격으로 미리 흘리고 한참 도망치다 죽는 경우도
--         정확히 잡히고, 새 무기로 갈아끼우면 예전 것은 자연히 추적 대상에서
--         빠진다(레퍼런스 교체).
--   2) 시체(IsoDeadBody)는 OnPlayerDeath "이후"에 만들어져 서버로 전송되므로,
--      이벤트 안에서 인벤토리를 비우면 시체/좀비는 어디서나 빈손이 된다.
--   3) 사망 시점에 손(핫바)에 쥐고 있던 무기는 리스폰 시 같은 손에 재장착된다.
--
-- 스냅샷은 클라이언트 로컬 파일(Zomboid/Lua/pongdu_invsave.txt)에 저장한다.
-- 사망~리스폰 사이에 게임이 튕겨도 재접속 후 리스폰 시 정상 복원된다.
--
-- 보존되는 상태: 커스텀 이름 / 내구도(cond, condMax) / 소모품 잔량 / 총기
-- (장전 수, 약실, 탄창 삽입, 부착물) / 음식(부패도, 섭취 잔량) / 의류(오염,
-- 피, 젖음) / 열쇠 keyId / modData(스칼라 값만) / 가방 중첩 구조 전체.
-- 한계: modData 안의 중첩 테이블, 라디오류 DeviceData, 의류 visual(색/구멍/
-- 패치), 지도 필기는 복원되지 않는다.

local invsave = {}

local INVSAVE_FILE = "pongdu_invsave.txt"
local TICKET_TYPE  = "t3chzzkDonation.inv_save_ticket"
local SEP          = "\t"
local HEADER       = "PONGDU_INVSAVE_V1"
local MAX_DEPTH    = 16

-- ── 손 아이템 추적 (v3: 시간창 대신 "마지막으로 낀 아이템 + 월드 잔존 여부") ──
-- v2의 시간창(1초) 방식은 "도망치다 피격으로 스태거 -> 무기 낙하 -> 몇 초 후 사망"
-- 시나리오를 놓쳤다: dropHandItems()는 사망 시점에 "그때 손에 있는 것"만 떨어뜨리는데,
-- 이미 그 전에 낙하한 무기는 사망 시점엔 손이 이미 빈 상태라 onItemFall이 새로 발화하지
-- 않는다. 그래서 시간 필터로는 원천적으로 못 잡는다.
--
-- 대신 "각 손에 마지막으로 낀 아이템 레퍼런스"를 OnEquipPrimary/Secondary로 계속
-- 추적한다(장착 해제로 nil이 들어와도 마지막 값은 덮어쓰지 않음). 사망 시 그 레퍼런스가
-- 여전히 "월드에 아이템으로 존재"하면(item:getWorldItem() ~= nil) 아직 아무도 안 주운
-- 채 바닥에 있다는 뜻이므로 회수한다. 픽업/파괴되면 엔진이 setWorldItem(null)로 정리하는
-- 것을 소스로 확인했으므로 이 판정은 시간과 무관하게 항상 정확하다.
-- 새 무기로 갈아끼우면 레퍼런스가 자연 교체되어, 예전에 흘린 무기까지 딸려오는
-- 오작동도 없다.
local lastPrimary, lastSecondary = nil, nil

Events.OnEquipPrimary.Add(function(chr, item)
    if chr == getPlayer() and item then lastPrimary = item end
end)
Events.OnEquipSecondary.Add(function(chr, item)
    if chr == getPlayer() and item then lastSecondary = item end
end)
-- 새 캐릭터(리스폰)로 넘어가면 이전 삶의 레퍼런스는 버린다.
Events.OnCreatePlayer.Add(function(index, player)
    lastPrimary, lastSecondary = nil, nil
end)

-- ── 문자열 인코딩 (rewards.txt와 동일하게 URL 인코딩 계열) ───────────────────────
-- 주의: Kahlua string.byte는 UTF-16 코드포인트를 반환하므로 (한글이면 >255)
-- 전체 URL 인코딩은 %02X 포맷이 4자리로 넘쳐 복호화가 깨진다.
-- 구분자로 쓰이는 구조 문자(전부 ASCII)만 이스케이프하고 나머지는 원문 유지.
local function enc(s)
    s = tostring(s or "")
    return (s:gsub("[%%\t\r\n,=]", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function dec(s)
    s = tostring(s or "")
    return (s:gsub("%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end))
end

-- 탭 분리 (빈 필드 보존)
local function splitTab(line)
    local f = {}
    for token in string.gmatch(line .. SEP, "([^\t]*)\t") do
        f[#f + 1] = token
    end
    return f
end

-- ── 직렬화 ────────────────────────────────────────────────────────────────────
-- 필드 순서(20개, 해당 없으면 "-"):
--  1 depth  2 fullType  3 wornLocation  4 name  5 cond  6 condMax  7 usedDelta
--  8 ammo  9 chambered  10 containsClip  11 age  12 hungChange  13 thirstChange
-- 14 dirtyness  15 bloodLevel  16 wetness  17 keyId  18 parts(콤마)  19 modData(콤마 k=t:v)
-- 20 handSlot(P/S/B/-)

local function serializeItem(item, depth, wornLoc, out, handSlot)
    local f = {}
    f[1] = tostring(depth)
    f[2] = enc(item:getFullType())
    f[3] = wornLoc and enc(wornLoc) or "-"
    f[4] = enc(item:getName() or "")
    f[5] = tostring(item:getCondition())
    f[6] = tostring(item:getConditionMax())

    if instanceof(item, "DrainableComboItem") then
        f[7] = tostring(item:getUsedDelta())
    else
        f[7] = "-"
    end

    local parts = "-"
    if instanceof(item, "HandWeapon") and item:isRanged() then
        f[8]  = tostring(item:getCurrentAmmoCount())
        f[9]  = item:isRoundChambered() and "1" or "0"
        f[10] = item:isContainsClip() and "1" or "0"
        local pl = {}
        local getters = { item:getScope(), item:getClip(), item:getCanon(),
                          item:getStock(), item:getSling(), item:getRecoilpad() }
        for _, p in ipairs(getters) do
            if p then pl[#pl + 1] = enc(p:getFullType()) end
        end
        if #pl > 0 then parts = table.concat(pl, ",") end
    else
        f[8], f[9], f[10] = "-", "-", "-"
    end

    if instanceof(item, "Food") then
        f[11] = tostring(item:getAge())
        f[12] = tostring(item:getHungChange())
        f[13] = tostring(item:getThirstChange())
    else
        f[11], f[12], f[13] = "-", "-", "-"
    end

    if instanceof(item, "Clothing") then
        f[14] = tostring(item:getDirtyness())
        f[15] = tostring(item:getBloodlevel())
        f[16] = tostring(item:getWetness())
    else
        f[14], f[15], f[16] = "-", "-", "-"
    end

    local keyId = item:getKeyId()
    f[17] = (keyId and keyId ~= -1) and tostring(keyId) or "-"

    f[18] = parts

    local mdl = {}
    local md = item:getModData()
    if md then
        for k, v in pairs(md) do
            local t = type(v)
            if t == "string" then
                mdl[#mdl + 1] = enc(k) .. "=s:" .. enc(v)
            elseif t == "number" then
                mdl[#mdl + 1] = enc(k) .. "=n:" .. enc(tostring(v))
            elseif t == "boolean" then
                mdl[#mdl + 1] = enc(k) .. "=b:" .. tostring(v)
            end
            -- 테이블 등 나머지는 스킵 (한계로 명시)
        end
    end
    f[19] = (#mdl > 0) and table.concat(mdl, ",") or "-"

    -- 20: 사망 시점 손 장착 슬롯 (P=주무기 S=보조무기 B=양손무기 -=해당없음)
    f[20] = handSlot or "-"

    out[#out + 1] = table.concat(f, SEP)
end

local function serializeContainer(container, depth, player, out)
    if depth > MAX_DEPTH then return end
    local items = container:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        local worn = nil
        if depth == 0 then
            worn = player:getWornItems():getLocation(it)
        end
        serializeItem(it, depth, worn, out)
        if instanceof(it, "InventoryContainer") then
            serializeContainer(it:getInventory(), depth + 1, player, out)
        end
    end
end

-- ── 사망: 스냅샷 저장 + 인벤토리 비우기 ─────────────────────────────────────────
local function onPlayerDeath(player)
    if not player then return end
    -- OnPlayerDeath는 소유 클라이언트에서만 발화하지만 방어적으로 한 번 더 확인
    if player.isLocalPlayer and not player:isLocalPlayer() then return end

    local inv = player:getInventory()
    if not inv then return end

    local ticket = inv:getFirstTypeRecurse(TICKET_TYPE)
    if not ticket then return end

    -- 티켓 1장 소모 (여러 장이면 나머지는 일반 아이템처럼 스냅샷에 포함되어 유지됨)
    local tc = ticket:getContainer()
    if tc then tc:Remove(ticket) end

    local out = {}

    -- 1) 마지막으로 낀 주/보조무기가 아직 바닥에 남아있으면(아무도 안 주웠으면) 회수.
    --    dropHandItems()가 OnPlayerDeath 직전에 이미 실행되어, 사망 시점에 손에
    --    쥐고 있던 무기라면 이 시점엔 이미 월드 아이템으로 존재한다.
    local hand = {}
    if lastPrimary then
        hand[#hand + 1] = { item = lastPrimary, slot = (lastSecondary == lastPrimary) and "B" or "P" }
    end
    if lastSecondary and lastSecondary ~= lastPrimary then
        hand[#hand + 1] = { item = lastSecondary, slot = "S" }
    end

    for _, h in ipairs(hand) do
        local wi = h.item:getWorldItem()
        if wi then   -- 아직 아무도 안 주운 채 바닥에 남아있음
            serializeItem(h.item, 0, nil, out, h.slot)
            if instanceof(h.item, "InventoryContainer") then
                serializeContainer(h.item:getInventory(), 1, player, out)
            end
            local sq = wi:getSquare()
            if sq then sq:transmitRemoveItemFromSquare(wi) end
        end
    end
    lastPrimary, lastSecondary = nil, nil

    -- 2) 본체 인벤토리 전체 스냅샷 (착용 부위 포함)
    serializeContainer(inv, 0, player, out)

    -- 3) 로컬 파일로 저장 (Zomboid/Lua/pongdu_invsave.txt)
    local w = getFileWriter(INVSAVE_FILE, true, false)   -- overwrite
    if w then
        w:write(HEADER .. SEP .. enc(player:getUsername() or "") .. "\r\n")
        for _, line in ipairs(out) do w:write(line .. "\r\n") end
        w:close()
    end

    -- 4) 캐릭터를 빈손으로 만든다. 이 시점은 becomeCorpse()/서버 전송 전이므로
    --    시체(또는 좀비화된 본인)는 어느 클라/서버에서도 빈 인벤토리가 된다.
    player:clearWornItems()
    local attached = player:getAttachedItems()
    if attached then attached:clear() end
    inv:clear()

    print("[PongDu] invsave: snapshot saved (" .. tostring(#out) .. " items), inventory cleared")
end
Events.OnPlayerDeath.Add(onPlayerDeath)

-- ── 리스폰: 스냅샷 복원 ─────────────────────────────────────────────────────────
local function readSnapshot()
    local reader = getFileReader(INVSAVE_FILE, false)
    if not reader then return nil end
    local lines = {}
    local line = reader:readLine()
    while line ~= nil do
        if line ~= "" then lines[#lines + 1] = line end
        line = reader:readLine()
    end
    reader:close()
    if #lines < 2 then return nil end
    local head = splitTab(lines[1])
    if head[1] ~= HEADER then return nil end
    table.remove(lines, 1)
    return lines
end

local function clearSnapshotFile()
    local w = getFileWriter(INVSAVE_FILE, true, false)
    if w then w:close() end
end

local function restoreLine(f, player, stack)
    local depth = tonumber(f[1]) or 0
    local parent = stack[depth]
    if not parent then parent = stack[0]; depth = 0 end

    local item = InventoryItemFactory.CreateItem(dec(f[2]))
    if not item then return 0 end   -- 모드 제거 등으로 타입이 사라진 경우 스킵

    local nm = dec(f[4] or "")
    if nm ~= "" then item:setName(nm) end

    local cmax = tonumber(f[6])
    if cmax then item:setConditionMax(cmax) end
    local cond = tonumber(f[5])
    if cond then item:setCondition(cond) end

    if f[7] ~= "-" and instanceof(item, "DrainableComboItem") then
        item:setUsedDelta(tonumber(f[7]) or 0)
    end

    if instanceof(item, "HandWeapon") and item:isRanged() then
        if f[8]  ~= "-" then item:setCurrentAmmoCount(tonumber(f[8]) or 0) end
        if f[9]  ~= "-" then item:setRoundChambered(f[9] == "1") end
        if f[10] ~= "-" then item:setContainsClip(f[10] == "1") end
        if f[18] and f[18] ~= "-" and f[18] ~= "" then
            for pt in string.gmatch(f[18], "([^,]+)") do
                local part = InventoryItemFactory.CreateItem(dec(pt))
                if part and instanceof(part, "WeaponPart") then
                    item:attachWeaponPart(part)
                end
            end
        end
    end

    if instanceof(item, "Food") then
        if f[11] ~= "-" then item:setAge(tonumber(f[11]) or 0) end
        if f[12] ~= "-" then item:setHungChange(tonumber(f[12]) or 0) end
        if f[13] ~= "-" then item:setThirstChange(tonumber(f[13]) or 0) end
    end

    if instanceof(item, "Clothing") then
        if f[14] ~= "-" then item:setDirtyness(tonumber(f[14]) or 0) end
        if f[15] ~= "-" then item:setBloodLevel(tonumber(f[15]) or 0) end
        if f[16] ~= "-" then item:setWetness(tonumber(f[16]) or 0) end
    end

    if f[17] and f[17] ~= "-" then
        item:setKeyId(tonumber(f[17]) or -1)
    end

    if f[19] and f[19] ~= "-" and f[19] ~= "" then
        local md = item:getModData()
        for pair in string.gmatch(f[19], "([^,]+)") do
            local k, t, v = string.match(pair, "^(.-)=(%a):(.*)$")
            if k and k ~= "" then
                k = dec(k)
                if t == "n" then
                    md[k] = tonumber(dec(v))
                elseif t == "b" then
                    md[k] = (v == "true")
                else
                    md[k] = dec(v)
                end
            end
        end
    end

    parent:AddItem(item)

    -- 착용 복원 (최상위 아이템만 worn 정보를 가짐)
    if depth == 0 and f[3] and f[3] ~= "-" then
        player:setWornItem(dec(f[3]), item)
    end

    -- 손 장착 복원 (사망 시점에 들고 있던/핫바 장착 무기를 그대로 재장착)
    if depth == 0 and f[20] and f[20] ~= "-" then
        if f[20] == "P" or f[20] == "B" then player:setPrimaryHandItem(item) end
        if f[20] == "S" or f[20] == "B" then player:setSecondaryHandItem(item) end
    end

    -- 컨테이너면 다음 depth의 부모로 등록
    if instanceof(item, "InventoryContainer") then
        stack[depth + 1] = item:getInventory()
        for d = depth + 2, MAX_DEPTH do stack[d] = nil end
    end
    return 1
end

local function restoreSnapshot(lines)
    local player = getPlayer()
    if not player then return end

    -- 새 캐릭터가 갖고 태어난 직업/기본 지급품을 전부 비운 뒤 복원한다.
    -- (스폰 의류가 부위를 선점해 인벤에 잡동사니로 남는 문제 방지)
    player:clearWornItems()
    local attached = player:getAttachedItems()
    if attached then attached:clear() end
    player:getInventory():clear()

    local stack = {}
    stack[0] = player:getInventory()
    local restored = 0
    for _, line in ipairs(lines) do
        local ok, n = pcall(restoreLine, splitTab(line), player, stack)
        if ok then restored = restored + (n or 0)
        else print("[PongDu] invsave: restore error: " .. tostring(n)) end
    end
    clearSnapshotFile()
    player:Say(getText("IGUI_invsave_restored"))
    print("[PongDu] invsave: restored " .. tostring(restored) .. " items")
end

-- OnCreatePlayer는 접속/리스폰 모두에서 발화한다. 파일은 티켓 소모 사망 때만
-- 생기고 복원 즉시 비우므로, 평소 접속에서는 아무 일도 일어나지 않는다.
-- 스폰 직후 초기화와의 충돌을 피하려고 3초 지연 후 지급한다.
Events.OnCreatePlayer.Add(function(index, player)
    local lines = readSnapshot()
    if not lines then return end

    local elapsed = 0
    local function waitAndRestore()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed >= 3000 then
            Events.OnTick.Remove(waitAndRestore)
            local ok, err = pcall(restoreSnapshot, lines)
            if not ok then
                print("[PongDu] invsave: restore failed: " .. tostring(err))
            end
        end
    end
    Events.OnTick.Add(waitAndRestore)
end)

return invsave
