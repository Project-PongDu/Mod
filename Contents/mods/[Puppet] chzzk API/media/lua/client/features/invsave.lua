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
-- ── 복원 경로는 두 갈래이고 서로 배타적이다 ────────────────────────────────────
--
-- [1차 · 객체 보존]  사망 시 아이템 객체 자체를 Lua 테이블(pending)에 붙잡아 두고,
--   리스폰 때 그 객체를 새 캐릭터 인벤에 그대로 다시 넣는다. 직렬화가 개입하지
--   않으므로 아이템의 모든 상태가 무손실 보존된다. 근거는 onPlayerDeath 위쪽
--   주석 참고. 정상 상황에서는 항상 이 경로를 탄다.
--
-- [2차 · 파일 폴백]  사망~리스폰 사이에 게임이 튕겨 메모리 객체가 날아간 경우에만
--   쓰인다. 사망 시 함께 기록해 둔 로컬 파일(Zomboid/Lua/pongdu_invsave.txt)에서
--   아이템을 재구성한다. 직렬화를 거치므로 아래 "폴백 한계"가 적용되는 열화 복원.
--
-- 이중 지급 방지: pending이 있으면 파일은 읽지도 않고, 어느 경로든 지급 루프
--   직전에 파일을 먼저 지운다. 같은 스냅샷이 두 번 지급되는 경로가 없다.
--   리스폰 대기(3초) 중 재사망 시에는 타이머를 취소하되 pending은 유지해,
--   다음 리스폰에서 정확히 한 번만 지급되도록 한다.
--
-- 폴백 경로가 보존하는 상태: 커스텀 이름(의류 제외 -- 아래 참고) /
-- 내구도(cond, condMax) / 소모품 잔량 / 총기(장전 수, 약실, 탄창 삽입, 부착물,
-- 동적 MaxAmmo) / 독립 탄창 잔탄 / 음식(부패도, 섭취 잔량) / 의류(오염, 피, 젖음) /
-- 외형(tint 색상, hue, 베이스 텍스처, 텍스처 초이스, 데칼) / 열쇠 keyId /
-- modData(스칼라 값만) / 가방 중첩 구조 전체 / 손 장착(주무기·보조무기) /
-- 핫바 부착 슬롯(벨트/등/홀스터 등).
--
-- 핫바 부착 복원은 반드시 정규 경로(getPlayerHotbar():attachItem)로만 한다.
-- AttachedItems에 직접 setItem 하면 하단 핫바 UI가 인식하지 못해 "몸에만 붙어
-- 보이는 유령 비주얼"이 되므로 금지. attachItem은 아이템의 attached 슬롯 상태를
-- 세팅하고 reloadIcons로 UI를 갱신해 양쪽을 일치시킨다.
--
-- 의류 이름은 일부러 복원하지 않는다: Clothing.getName()이 "더러움/해짐/젖음"을
-- 매번 새로 계산해 접두어로 붙이는 표시용 문자열이라, 그걸 그대로 caputre해서
-- setName()으로 박아버리면 부활할 때마다 접두어가 계속 누적된다. 오염도/내구도/
-- 젖음만 복원하면 게임이 알아서 매번 정확히 새로 계산해준다.
--
-- 폴백 한계(2차 경로에서만 해당. 1차 객체 경로는 전부 그대로 보존된다):
-- modData 안의 중첩 테이블, 라디오류 DeviceData, 의류 구멍/패치 상태, 지도 필기,
-- 총기 부착물의 내구도, 비-의류 아이템의 "부서짐/오염수" 등 이름에 얹히는 기타
-- 동적 표시(예: isBroken())는 복원되지 않는다.

local invsave = {}

local INVSAVE_FILE = "pongdu_invsave.txt"
local TICKET_TYPE  = "t3chzzkDonation.inv_save_ticket"
local SEP          = "\t"
local HEADER       = "PONGDU_INVSAVE_V1"
local MAX_DEPTH    = 16

-- 총기 부착물 슬롯 타입 (HandWeapon.getWeaponPart/setWeaponPart가 받는 문자열).
-- 게터를 테이블 생성자에 모으는 방식은 미장착 슬롯이 nil hole을 만들어 쓸 수 없다
-- (아래 serializeItem 주석 참고). 문자열 배열은 hole이 없으므로 안전하다.
local PART_TYPES   = { "Scope", "Clip", "Canon", "Stock", "Sling", "RecoilPad" }

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

-- 접속/재접속 로드 대응: IsoGameCharacter.load()(41.78.19)는 leftHandItem/
-- rightHandItem을 setter를 거치지 않고 필드에 직접 대입하므로 OnEquipPrimary/
-- Secondary가 발화하지 않는다. 즉 무기를 든 채로 접속한 뒤 한 번도 재장착하지
-- 않으면 위 추적 레퍼런스가 nil인 채로 남아, 낙하 무기 회수(및 사망 시
-- dropHandItems로 떨어진 손 무기 회수)가 전부 실패한다. 그래서 현재 손 아이템을
-- 직접 읽어 시드한다. (비어있으면 건드리지 않음 -> 리스폰 리셋과 충돌 없음)
local function seedHandRefs(player)
    player = player or getPlayer()
    if not player then return end
    local p = player:getPrimaryHandItem()
    local s = player:getSecondaryHandItem()
    if p then lastPrimary = p end
    if s then lastSecondary = s end
end

Events.OnCreatePlayer.Add(function(index, player)
    -- 새 캐릭터(리스폰)로 넘어가면 이전 삶의 레퍼런스는 버린다.
    lastPrimary, lastSecondary = nil, nil
    -- 재접속 로드라면 이 시점에 손 아이템이 이미 있으므로 즉시 시드.
    seedHandRefs(player)
end)
-- 클라이언트 로드 순서에 따라 OnCreatePlayer 시점에 손이 아직 비어 보일 수
-- 있으므로, 게임 진입 완료 후 한 번 더 시드한다(같은 참조라 중복 무해).
Events.OnGameStart.Add(function() seedHandRefs(nil) end)

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
-- 필드 순서(22개, 해당 없으면 "-"):
--  1 depth  2 fullType  3 wornLocation  4 name  5 cond  6 condMax  7 usedDelta
--  8 ammo  9 chambered  10 containsClip  11 age  12 hungChange  13 thirstChange
-- 14 dirtyness  15 bloodLevel  16 wetness  17 keyId  18 parts(콤마)  19 modData(콤마 k=t:v)
-- 20 handSlot(P/S/B/-)  21 hotbarSlotType  22 hotbarModelAttach
-- 23 maxAmmo (MaxAmmo>0인 아이템만; GunFighter류가 드럼/확장 탄창 장착 시
--    총기 MaxAmmo를 동적으로 바꾸므로 기본값 복원으로 인한 불일치 방지)
-- 24 visual(콤마: tintR,tintG,tintB,hue,decal,baseTex,texChoice) — 미복원 시
--    ItemVisual 게터가 랜덤 재추첨(OutfitRNG)해 색/무늬가 바뀌는 문제 방지
-- 25 magazineType  26 fireMode (원거리 총기만) — GunFighter류가 드럼/확장 탄창
--    삽입이나 트리거 그룹 변경 시 총기 필드를 동적으로 바꾸는데, 팩토리 재생성은
--    스크립트 기본값으로 롤백돼 배출 탄창 타입이 어긋나는 문제 방지
-- 27 jammed(0/1)  28 spentRoundChambered(0/1)  29 spentRoundCount (원거리 총기만)
--    — 잼/탄피 배출 상태. 하드코어 리로딩류의 racking 정합 유지

local function serializeItem(item, depth, wornLoc, out, handSlot)
    -- (핫바 부착 정보는 아이템 자신이 들고 있으므로 인자 추가 없이 여기서 직접 읽는다)
    local f = {}
    f[1] = tostring(depth)
    f[2] = enc(item:getFullType())
    f[3] = wornLoc and enc(wornLoc) or "-"
    -- 의류는 getName()이 매번 새로 계산되는 "더러움/해짐/젖음" 표시용 문자열이라
    -- 그대로 caputre-restore하면 부활 때마다 접두어가 누적된다. 의류는 이름을
    -- 아예 건드리지 않고(빈 값), 내구도/오염도/피/젖음만 복원해 게임이 매번
    -- 새로 정확히 계산하게 둔다.
    if instanceof(item, "Clothing") then
        f[4] = ""
    else
        f[4] = enc(item:getName() or "")
    end
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
        -- [FIX] 기존 코드는 게터 반환값을 테이블 생성자에 그대로 모아 ipairs로 돌렸는데,
        -- 미장착 슬롯이 nil이면 배열에 hole이 생긴다. Kahlua의 ipairs도 표준과 동일하게
        -- 첫 nil에서 즉시 순회를 끝내므로(stdlib.lua ipairs_iterator), 스코프 없는 총기는
        -- getters[1]==nil -> 부착물이 단 하나도 저장되지 않았다. 대부분의 총기가
        -- 스코프를 안 달기 때문에 사실상 전 부착물 유실.
        local pl = {}
        for _, pt in ipairs(PART_TYPES) do
            local p = item:getWeaponPart(pt)
            if p then pl[#pl + 1] = enc(p:getFullType()) end
        end
        if #pl > 0 then parts = table.concat(pl, ",") end
    else
        -- 독립 탄창(바닐라 9mmClip 등, 모드 탄창 포함): HandWeapon이 아니라
        -- 베이스 InventoryItem이 잔탄(currentAmmoCount)을 들고 있으므로
        -- MaxAmmo>0 이면 잔탄을 저장한다. (미저장 시 복원 후 0발이 되는 버그)
        if item:getMaxAmmo() > 0 then
            f[8] = tostring(item:getCurrentAmmoCount())
        else
            f[8] = "-"
        end
        f[9], f[10] = "-", "-"
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

    -- 21: 핫바 부착 슬롯 타입 (예 "SmallBeltLeft", "Back"). -1이면 미부착.
    -- 22: 핫바 부착 모델 부착점 (예 "Belt Left").
    -- ISHotbar는 아이템의 getAttachedSlot()>-1 를 보고 슬롯을 채우므로, 복원 시
    -- 이 두 값으로 슬롯을 되찾아 정규 부착 경로(attachItem)를 태운다.
    if depth == 0 and item:getAttachedSlot() and item:getAttachedSlot() > -1 then
        f[21] = enc(item:getAttachedSlotType() or "-")
        f[22] = enc(item:getAttachedToModel() or "-")
    else
        f[21], f[22] = "-", "-"
    end

    -- 23: MaxAmmo (총기+탄창 공통). GunFighter류 모드가 드럼/확장 탄창 장착 시
    -- setMaxAmmo로 총기 값을 바꾸는데, 팩토리 생성 복원은 스크립트 기본값으로
    -- 돌아가 modData(ClipType 등)와 어긋나므로 실제 값을 저장해 되돌린다.
    f[23] = (item:getMaxAmmo() > 0) and tostring(item:getMaxAmmo()) or "-"

    -- 24: 외형. tint는 no-arg 게터(미설정이면 nil), hue/decal 게터는 ClothingItem
    -- 인자가 필요하다(호출 시점에 미설정이면 그 자리에서 확정되는데, 이미 착용/
    -- 렌더된 아이템은 확정돼 있고 가방 속 미렌더 아이템은 어차피 플레이어가 본 적
    -- 없는 색이라 여기서 확정해도 무방). 복원 없이 두면 OutfitRNG가 랜덤 재추첨해
    -- 색/무늬/데칼이 전부 바뀐다.
    local vis = item:getVisual()
    if vis then
        local v = { "-", "-", "-", "-", "-", "-", "-" }
        local ci = vis:getClothingItem()
        local tint = vis:getTint()
        if not tint and ci then tint = vis:getTint(ci) end
        if tint then
            v[1] = tostring(tint:getRedFloat())
            v[2] = tostring(tint:getGreenFloat())
            v[3] = tostring(tint:getBlueFloat())
        end
        if ci then
            v[4] = tostring(vis:getHue(ci))
            local dcl = vis:getDecal(ci)
            if dcl then v[5] = enc(dcl) end
        end
        v[6] = tostring(vis:getBaseTexture())
        v[7] = tostring(vis:getTextureChoice())
        f[24] = table.concat(v, ",")
    else
        f[24] = "-"
    end

    -- 25/26: 총기 동적 필드. GunFighter류가 드럼/확장 탄창 삽입 시 setMagazineType,
    -- 트리거 그룹 변경 시 setFireMode로 필드를 바꾸는데, 배출 탄창 생성이
    -- gun:getMagazineType() 기준이라 이걸 복원 안 하면 기본 탄창(예: SPASClip)에
    -- 드럼 잔탄이 담겨 나오는 버그가 생긴다.
    if instanceof(item, "HandWeapon") and item:isRanged() then
        local mt = item:getMagazineType()
        f[25] = (mt and mt ~= "") and enc(mt) or "-"
        local fm = item:getFireMode()
        f[26] = (fm and fm ~= "") and enc(fm) or "-"
        f[27] = item:isJammed() and "1" or "0"
        f[28] = item:isSpentRoundChambered() and "1" or "0"
        f[29] = tostring(item:getSpentRoundCount())
    else
        f[25], f[26], f[27], f[28], f[29] = "-", "-", "-", "-", "-"
    end

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

-- ── 사망: 객체 보존 + 파일 스냅샷(폴백) + 인벤토리 비우기 ────────────────────────
--
-- 1차 경로는 "아이템 객체 자체를 Lua 테이블에 붙잡아 두는 것"이다. 근거:
--   * ItemContainer.clear()는 Items.clear()만 한다. 아이템 객체는 파괴되지 않고,
--     Lua가 참조를 잡고 있으면 GC 대상도 아니다.
--   * IsoGameCharacter.clearWornItems() / AttachedItems.clear()도 각각 리스트만
--     비운다. 아이템의 attachedSlot / attachedSlotType / attachedToModel 필드는
--     그대로 남으므로 핫바 정보도 아이템 안에 살아있다.
--   * ItemContainer.AddItem()은 순수 로컬 조작이라 네트워크 패킷을 보내지 않는다.
--     플레이어 인벤은 클라 권위이므로 새 캐릭터 인벤에 기존 객체를 그대로 꽂아도
--     서버와 충돌하지 않는다. item.id도 팩토리에서 21억 범위 난수로 뽑히고
--     containsID 체크는 동일 컨테이너 내부만 보므로 충돌 위험이 없다.
--   * 컨테이너 아이템은 자기 ItemContainer를 필드로 들고 있어서, 최상위 객체만
--     잡으면 중첩 가방 내용물이 통째로 따라온다.
--   * 사망~리스폰 사이 아이템은 container == null 상태로 IsoCell.ProcessItems
--     목록에 남을 수 있으나, update()/finishupdate() 및 오버라이드 7종
--     (Clothing/Food/DrainableComboItem/Literature/AlarmClock/Radio 등)이 전부
--     null-safe하다. 게다가 finishupdate()가 !isWet()이면 true라 다음 틱에
--     목록에서 자동 제거된다.
--
-- 객체 경로는 직렬화가 개입하지 않으므로 아이템의 모든 상태가 무손실 보존된다
-- (부착물 내구도, modData 중첩 테이블, 라디오 DeviceData, 의류 구멍/패치,
--  지도 필기, 아이콘 tint/텍스처 등 파일 경로의 한계가 전부 사라진다).
--
-- 파일 스냅샷은 "사망~리스폰 사이에 게임이 튕겼을 때"만 쓰이는 열화 폴백으로
-- 격하됐다. 정상 경로에서는 절대 읽지 않는다.

-- ── 파일 스냅샷 I/O (폴백 경로 전용) ───────────────────────────────────────────
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

-- 아직 지급되지 않은 보존 아이템. { {item=, worn=, hand=} , ... }
local pending = nil
-- 3초 대기 타이머 함수 레퍼런스 (재사망 시 취소해야 하므로 파일 스코프에 보관)
local restoreTickFn = nil

local function cancelPendingRestore()
    if restoreTickFn then
        Events.OnTick.Remove(restoreTickFn)
        restoreTickFn = nil
    end
end

local function onPlayerDeath(player)
    if not player then return end
    -- OnPlayerDeath는 소유 클라이언트에서만 발화하지만 방어적으로 한 번 더 확인
    if player.isLocalPlayer and not player:isLocalPlayer() then return end

    -- 리스폰 대기(3초) 도중에 다시 죽은 경우: 타이머를 반드시 죽인다.
    -- pending 자체는 건드리지 않는다. 아직 지급되지 않은 아이템이므로 다음
    -- OnCreatePlayer에서 그대로 복원되는 게 맞다. (이때 새 캐릭터 인벤엔 티켓이
    -- 없으므로 아래에서 early return되고, 파일 스냅샷도 덮어쓰이지 않아
    -- pending과 파일 내용이 계속 일치한다.)
    cancelPendingRestore()

    local inv = player:getInventory()
    if not inv then return end

    local ticket = inv:getFirstTypeRecurse(TICKET_TYPE)
    if not ticket then return end

    -- 티켓 1장 소모 (여러 장이면 나머지는 일반 아이템처럼 그대로 보존됨)
    local tc = ticket:getContainer()
    if tc then tc:Remove(ticket) end

    -- [재사망 병합] 아직 지급되지 않은 pending이 남아있는 상태에서, 또 티켓을
    -- 소모하며 죽은 경우(리스폰 대기 3초 중 다른 플레이어에게 티켓을 받아 쥐는 등).
    -- 그냥 pending = entries로 덮어쓰면 이전 사망분이 통째로 소실되므로 앞에
    -- 이어붙인다. 파일 폴백도 같은 순서로 병합해 두 경로의 내용을 일치시킨다.
    -- (착용 부위나 손 슬롯이 겹치면 나중 것이 이기고 이전 것은 인벤에 남는다.)
    local entries = {}   -- 객체 경로
    local out     = {}   -- 파일 폴백 경로
    local carryLines = nil
    if pending then
        for _, e in ipairs(pending) do entries[#entries + 1] = e end
        carryLines = readSnapshot()
    end

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
            entries[#entries + 1] = { item = h.item, worn = nil, hand = h.slot }
            serializeItem(h.item, 0, nil, out, h.slot)
            if instanceof(h.item, "InventoryContainer") then
                serializeContainer(h.item:getInventory(), 1, player, out)
            end
            local sq = wi:getSquare()
            if sq then sq:transmitRemoveItemFromSquare(wi) end
            -- 월드 아이템 레퍼런스를 끊어둔다. 그대로 두면 리스폰 후에도
            -- getWorldItem()이 살아있어 "바닥에도 있는 것처럼" 보일 수 있다.
            h.item:setWorldItem(nil)
        end
    end
    lastPrimary, lastSecondary = nil, nil

    -- 2) 본체 인벤토리. 착용 부위는 clearWornItems() 전에 읽어야 하므로 여기서 수집.
    --    최상위 아이템만 잡으면 되고, 중첩 가방 내용물은 컨테이너 객체를 따라온다.
    local items = inv:getItems()
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        entries[#entries + 1] = { item = it, worn = player:getWornItems():getLocation(it) }
    end

    -- 3) 파일 폴백 스냅샷 (크래시 대비. 정상 경로에서는 읽히지 않는다)
    serializeContainer(inv, 0, player, out)
    local w = getFileWriter(INVSAVE_FILE, true, false)   -- overwrite
    if w then
        w:write(HEADER .. SEP .. enc(player:getUsername() or "") .. "\r\n")
        if carryLines then
            for _, line in ipairs(carryLines) do w:write(line .. "\r\n") end
        end
        for _, line in ipairs(out) do w:write(line .. "\r\n") end
        w:close()
    end

    -- 4) 캐릭터를 빈손으로 만든다. 이 시점은 becomeCorpse()/서버 전송 전이므로
    --    시체(또는 좀비화된 본인)는 어느 클라/서버에서도 빈 인벤토리가 된다.
    --    위 3종 clear는 전부 리스트만 비우므로 entries가 잡은 객체는 무사하다.
    player:clearWornItems()
    local attached = player:getAttachedItems()
    if attached then attached:clear() end
    inv:clear()

    pending = entries

    print("[PongDu] invsave: held " .. tostring(#entries) .. " top-level items in memory, "
          .. tostring(#out) .. " lines written as crash fallback, inventory cleared")
end
Events.OnPlayerDeath.Add(onPlayerDeath)

-- ── 리스폰: 스냅샷 복원 ─────────────────────────────────────────────────────────
local function restoreLine(f, player, stack, pendingHotbar)
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

    -- MaxAmmo 복원(잔탄보다 먼저). 구버전 스냅샷엔 f[23]이 없으므로 nil 가드.
    if f[23] and f[23] ~= "-" then item:setMaxAmmo(tonumber(f[23]) or item:getMaxAmmo()) end
    -- 잔탄: 총기뿐 아니라 독립 탄창도 베이스 InventoryItem의 currentAmmoCount를
    -- 쓰므로 클래스 구분 없이 복원한다.
    if f[8] ~= "-" then item:setCurrentAmmoCount(tonumber(f[8]) or 0) end

    if instanceof(item, "HandWeapon") and item:isRanged() then
        -- 동적 탄창 타입/발사 모드 복원 (잔탄·MaxAmmo와 정합 유지).
        -- 구버전 스냅샷엔 f[25]/f[26]이 없으므로 nil 가드.
        if f[25] and f[25] ~= "-" then item:setMagazineType(dec(f[25])) end
        if f[26] and f[26] ~= "-" then item:setFireMode(dec(f[26])) end
        if f[27] and f[27] ~= "-" then item:setJammed(f[27] == "1") end
        if f[28] and f[28] ~= "-" then item:setSpentRoundChambered(f[28] == "1") end
        if f[29] and f[29] ~= "-" then item:setSpentRoundCount(tonumber(f[29]) or 0) end
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

    -- 외형 복원 (AddItem/착용 전에 세팅해야 첫 렌더부터 저장된 외형이 적용됨).
    -- 구버전 스냅샷엔 f[24]가 없으므로 nil 가드.
    if f[24] and f[24] ~= "-" and f[24] ~= "" then
        local vis = item:getVisual()
        if vis then
            local v = {}
            for tok in string.gmatch(f[24] .. ",", "([^,]*),") do v[#v + 1] = tok end
            if v[1] and v[1] ~= "-" then
                vis:setTint(ImmutableColor.new(
                    tonumber(v[1]) or 1, tonumber(v[2]) or 1, tonumber(v[3]) or 1, 1))
            end
            if v[4] and v[4] ~= "-" then vis:setHue(tonumber(v[4]) or 0) end
            if v[5] and v[5] ~= "-" then vis:setDecal(dec(v[5])) end
            if v[6] and v[6] ~= "-" then vis:setBaseTexture(tonumber(v[6]) or -1) end
            if v[7] and v[7] ~= "-" then vis:setTextureChoice(tonumber(v[7]) or -1) end
        end
    end

    -- [FIX] 아이콘 동기화.
    -- 인벤토리 UI 아이콘은 ItemVisual이 아니라 아이템 자신의 col(getR/getG/getB)과
    -- texture(getTex)를 쓴다(ISInventoryPane.lua: drawTextureScaledAspect(item:getTex(),
    -- ..., item:getR(), item:getG(), item:getB())). 이 두 필드는 엔진에서
    -- InventoryItem.synchWithVisual()이 ItemVisual 기준으로 갱신해주는데, 그 호출은
    -- Clothing.load()/InventoryContainer.load() 안에만 있다. 즉 세이브 로드 경로 전용이라
    -- InventoryItemFactory.CreateItem()으로 만든 아이템에는 절대 호출되지 않는다.
    -- 그래서 위에서 tint/baseTexture/textureChoice를 아무리 복원해도 3D 모델만 맞고
    -- 아이콘은 흰색 + 스크립트 기본 텍스처로 남았다(= TINT류 아이콘 미복구).
    -- Clothing / InventoryContainer가 아니면 내부에서 즉시 no-op이므로 무조건 호출해도 안전.
    pcall(function() item:synchWithVisual() end)

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

    -- 핫바 부착은 지금 바로 하지 않고 모은다. availableSlot이 배낭/벨트 등 착용
    -- 아이템에 따라 달라지므로 모든 착용/복원이 끝난 뒤 정규 경로로 부착한다.
    if depth == 0 and f[21] and f[21] ~= "-" then
        pendingHotbar[#pendingHotbar + 1] = {
            item      = item,
            slotType  = dec(f[21]),
            modelAtt  = (f[22] and f[22] ~= "-") and dec(f[22]) or nil,
        }
    end

    -- 컨테이너면 다음 depth의 부모로 등록
    if instanceof(item, "InventoryContainer") then
        stack[depth + 1] = item:getInventory()
        for d = depth + 2, MAX_DEPTH do stack[d] = nil end
    end
    return 1
end

-- ── 복원 공통 루틴 (객체 경로 / 파일 폴백 경로가 공유) ─────────────────────────

-- 핫바 부착: 정규 경로(getPlayerHotbar -> attachItem)로 넣어야 하단 UI와
-- 몸 모델이 함께 반영된다. AttachedItems에 직접 꽂으면 UI가 인식 못 해
-- "몸에만 붙은 유령 비주얼"이 되므로 절대 그렇게 하지 않는다.
local function applyHotbar(player, list)
    if #list == 0 then return end
    local hotbar = getPlayerHotbar(player:getPlayerNum())
    if not hotbar then return end

    hotbar:refresh()   -- 착용 배낭/벨트 기준으로 availableSlot 재계산
    for _, ph in ipairs(list) do
        pcall(function()
            -- slotType으로 현재 availableSlot에서 해당 슬롯을 찾는다.
            -- (저장된 slotIndex를 그대로 쓰지 않는 이유: availableSlot 구성은
            --  착용 중인 배낭/벨트에 따라 달라져 인덱스가 어긋날 수 있다.)
            local slotIndex, slotDef
            for idx, slot in pairs(hotbar.availableSlot) do
                if slot.slotType == ph.slotType then
                    slotIndex = idx
                    slotDef   = slot.def
                    break
                end
            end
            if slotIndex and slotDef then
                -- 모델 부착점(slot 인자)은 저장값 우선, 없으면 slotDef에서
                -- 아이템 attachmentType으로 역산
                local slotArg = ph.modelAtt
                if not slotArg and slotDef.attachments then
                    slotArg = slotDef.attachments[ph.item:getAttachmentType()]
                end
                if slotArg then
                    hotbar:attachItem(ph.item, slotArg, slotIndex, slotDef, false)
                end
            end
        end)
    end
    hotbar:reloadIcons()
end

-- 복원 직후 아이콘/가방 탭이 갱신 안 된 채 남는 것 방지.
-- 바닐라 정규 패턴(refreshBackpacks + dirtyUI)만 사용.
local function refreshInventoryUI(player)
    local pn = player:getPlayerNum()
    if getPlayerInventory(pn) then getPlayerInventory(pn):refreshBackpacks() end
    if getPlayerLoot(pn) then getPlayerLoot(pn):refreshBackpacks() end
    if ISInventoryPage and ISInventoryPage.dirtyUI then ISInventoryPage.dirtyUI() end
end

-- 새 캐릭터가 갖고 태어난 직업/기본 지급품을 전부 비운다.
-- (스폰 의류가 부위를 선점해 인벤에 잡동사니로 남는 문제 방지)
local function stripSpawnLoadout(player)
    player:clearWornItems()
    local attached = player:getAttachedItems()
    if attached then attached:clear() end
    player:getInventory():clear()
end

-- ── 복원 1차 경로: 메모리에 붙잡아 둔 아이템 객체를 그대로 지급 ─────────────────
local function restorePending(entries)
    local player = getPlayer()
    if not player then return end

    -- [이중 지급 방지] 객체 경로로 들어온 이상 파일 폴백은 절대 쓰이면 안 된다.
    -- 지급 루프보다 먼저 지운다. 이 사이에는 파일 I/O도 파싱도 없어 실패 지점이
    -- AddItem 호출뿐이라, 먼저 지워도 실질적으로 안전하다. 반대로 지급 후에
    -- 지우면 그 틈에 튕겼을 때 서버엔 이미 아이템이 저장된 채 파일도 남아
    -- 재접속 시 통째로 한 벌 더 지급된다.
    clearSnapshotFile()

    stripSpawnLoadout(player)

    local inv = player:getInventory()
    local hotbarList = {}
    local restored = 0

    for _, e in ipairs(entries) do
        local ok, err = pcall(function()
            local it = e.item

            -- 핫바 정보는 아이템 자신의 필드에 그대로 남아있다.
            -- (AttachedItems.clear()는 리스트만 비우고 attachedSlot /
            --  attachedSlotType / attachedToModel은 건드리지 않는다.)
            -- AddItem 전에 읽어둔다.
            local slotType = nil
            if it:getAttachedSlot() > -1 then
                slotType = it:getAttachedSlotType()
            end

            inv:AddItem(it)

            if e.worn then player:setWornItem(e.worn, it) end
            if e.hand == "P" or e.hand == "B" then player:setPrimaryHandItem(it) end
            if e.hand == "S" or e.hand == "B" then player:setSecondaryHandItem(it) end

            if slotType then
                hotbarList[#hotbarList + 1] = {
                    item     = it,
                    slotType = slotType,
                    modelAtt = it:getAttachedToModel(),
                }
            end
        end)
        if ok then restored = restored + 1
        else print("[PongDu] invsave: pending restore error: " .. tostring(err)) end
    end

    applyHotbar(player, hotbarList)
    refreshInventoryUI(player)

    player:Say(getText("IGUI_invsave_restored"))
    print("[PongDu] invsave: restored " .. tostring(restored) .. " top-level items from memory")
end

-- ── 복원 2차 경로(폴백): 파일 스냅샷에서 재구성 ─────────────────────────────────
-- 사망~리스폰 사이에 게임이 튕겨 메모리 객체가 날아간 경우에만 쓰인다.
-- 직렬화를 거치므로 부착물 내구도, modData 중첩 테이블, 라디오 DeviceData,
-- 의류 구멍/패치 등은 복원되지 않는 열화 복원이다.
local function restoreSnapshot(lines)
    local player = getPlayer()
    if not player then return end

    -- [이중 지급 방지] 객체 경로와 동일한 이유로 지급 전에 먼저 지운다.
    -- lines는 이미 메모리에 올라와 있으므로 파일을 지워도 이번 복원에는 지장 없다.
    clearSnapshotFile()

    stripSpawnLoadout(player)

    local stack = {}
    stack[0] = player:getInventory()
    local pendingHotbar = {}
    local restored = 0
    for _, line in ipairs(lines) do
        local ok, n = pcall(restoreLine, splitTab(line), player, stack, pendingHotbar)
        if ok then restored = restored + (n or 0)
        else print("[PongDu] invsave: restore error: " .. tostring(n)) end
    end

    applyHotbar(player, pendingHotbar)
    refreshInventoryUI(player)

    player:Say(getText("IGUI_invsave_restored"))
    print("[PongDu] invsave: restored " .. tostring(restored) .. " items (file fallback)")
end

-- OnCreatePlayer는 접속/리스폰 모두에서 발화한다.
--
-- [이중 지급 방지] 두 복원 경로는 상호 배타다. pending(메모리 객체)이 있으면
-- 그 경로로만 가고 파일은 읽지도 않는다. pending이 없을 때만 = 사망 후 리스폰
-- 전에 게임이 종료된 경우에만 파일을 읽는다. 어느 쪽이든 지급 직전에 파일을
-- 먼저 지우므로, 같은 스냅샷이 두 번 지급되는 경로가 존재하지 않는다.
--
-- 스폰 직후 초기화와의 충돌을 피하려고 3초 지연 후 지급한다.
Events.OnCreatePlayer.Add(function(index, player)
    -- 리스폰 대기 중 재사망 -> 재리스폰이면 이전 타이머가 아직 살아있을 수 있다.
    -- 여기서 정리해야 타이머가 중복 등록되어 두 번 지급되는 일이 없다.
    cancelPendingRestore()

    local entries, lines = pending, nil
    if not entries then
        lines = readSnapshot()
        if not lines then return end
    end

    local elapsed = 0
    local function waitAndRestore()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed < 3000 then return end

        Events.OnTick.Remove(waitAndRestore)
        restoreTickFn = nil

        local ok, err
        if entries then
            -- pending을 먼저 비운다. 복원 중 예외가 나더라도 같은 객체 목록으로
            -- 다시 지급 시도되는 일이 없도록 한다.
            pending = nil
            ok, err = pcall(restorePending, entries)
        else
            ok, err = pcall(restoreSnapshot, lines)
        end
        if not ok then
            print("[PongDu] invsave: restore failed: " .. tostring(err))
        end
    end
    restoreTickFn = waitAndRestore
    Events.OnTick.Add(waitAndRestore)
end)

return invsave
