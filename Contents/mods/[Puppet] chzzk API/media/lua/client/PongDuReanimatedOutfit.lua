-- PongDuReanimatedOutfit.lua : 좀비화된 플레이어의 '알몸 렌더링' 보정 (MP 클라 전용)
--
-- ── 증상 ────────────────────────────────────────────────────────────────────
-- 플레이어 시체가 좀비로 부활하면 그 좀비가 알몸으로 그려진다. 그 좀비를 다시
-- 죽여서 나온 시체는 원래 복장/아이템을 정상적으로 갖고 있다. 데이터는 멀쩡하고
-- 렌더용 비주얼만 비어 있는 상태다.
--
-- ── 두 가지 원인이 존재한다 ─────────────────────────────────────────────────
--
-- [원인 A] 디스크립터 도착 지연 (이 파일이 고치는 것)
--   IsoDeadBody.reanimate() (IsoDeadBody.java:1309)
--     isFakeDead()==false -> setReanimatedPlayer(true)
--                            + SharedDescriptors.createPlayerZombieDescriptor()
--   -> 옷이 pid로 재구성되지 않고 ZombieDescriptors 패킷으로 따로 push된다
--      (SharedDescriptors.java:82). 좀비 sync와 완전히 다른 채널이다.
--
--   클라가 이 좀비를 처음 렌더 리스트에 올릴 때:
--     ModelManager.dressInRandomOutfit:558 -> dressInPersistentOutfitID(pid)
--     IsoZombie.dressInPersistentOutfitID:3575
--         getHumanVisual().clear()          <- 먼저 벗기고
--         itemVisuals.clear()
--         m_bPersistentOutfitInit = true    <- "처리 완료"로 봉인하고
--         dressInOutfit() -> ApplyReanimatedPlayerOutfit
--     SharedDescriptors.ApplyReanimatedPlayerOutfit:136
--         PlayerZombieDescriptors[slot]이 아직 null이면 조용히 리턴
--
--   descriptor가 좀비보다 늦게 도착하면 HumanVisual이 빈 채로 고착된다.
--   m_bPersistentOutfitInit=true라 엔진이 다시 시도하지도 않는다.
--   -> 이건 곧 도착할 데이터를 기다리는 문제이므로 재시도로 100% 복구된다.
--
-- [원인 B] 클라/서버 outfit 목록 인덱스 불일치 (이 파일로는 못 고친다)
--   pid의 상위 16비트는 PersistentOutfits.m_all의 인덱스다. 이 목록은 세이브에
--   저장되지 않고 게임 로드마다 재조립되며(PersistentOutfits.init:57), 서버와
--   클라가 서로 목록을 맞춰보지 않는다. 번호만 주고받는다.
--   "ReanimatedPlayer"는 목록 맨 끝에 등록되므로(registerCustomOutfits:110)
--   그 앞 항목이 하나만 어긋나도 인덱스가 통째로 밀린다.
--
--   밀리면 클라는 m_all[서버인덱스]에 있는 엉뚱한 일반 outfit의 outfitter를
--   호출한다 -> PersistentOutfits.ApplyOutfit -> IsoZombie.dressInNamedOutfit:3556
--       wornItems.clear()                     <- 렌더가 참조하는 목록을 비우고
--       getHumanVisual().clear()              <- 머리모델/머리색/수염/피부색 소실
--       humanVisual.dressInNamedOutfit(...)   <- itemVisuals에만 옷을 채운다
--       UnderwearDefinition.addRandomUnderwear <- 속옷만 랜덤으로 입힌다
--   reanimated player 좀비는 isUsingWornItems()==true라(IsoZombie.java:3530)
--   렌더 시 wornItems를 참조하는데 그게 비어 있으므로 속옷 차림만 남는다.
--   여기에 ApplyOutfit의 addRandomBloodDirtHolesEtc()가 매 호출마다 혈흔을
--   새로 굴린다.
--
--   즉 원인 B는 "알몸 + 딴사람 얼굴 + 혈흔 깜빡임" 3종 세트로 나타나며,
--   재시도해도 영원히 성공하지 않는다. 클라/서버 모드 구성을 일치시켜
--   목록을 맞추는 것 외에 클라 Lua에서 손댈 방법이 없다
--   (PersistentOutfits는 LuaManager.Exposer에 노출되지 않아 접근 불가).
--
-- ── 재시도 상한을 두는 이유 ─────────────────────────────────────────────────
-- 이전 버전은 "ZombieDescriptors가 RELIABLE 패킷이니 언젠간 반드시 도착한다"는
-- 근거로 타임아웃 없이 무한 재시도했다. 원인 A만 존재한다는 전제에서는 맞지만,
-- 원인 B에 걸린 좀비에게는 250ms마다 위의 clear() + 랜덤 속옷/혈흔 재생성을
-- 영구히 반복하는 꼴이 된다. 가만히 알몸으로 두는 것보다 훨씬 나쁘다.
--
-- 원인 A의 실제 지연은 수백 ms 수준이므로 2초(8회)면 충분하고, 그 안에 안 되면
-- 원인 B로 간주하고 손을 뗀다. 인덱스 불일치는 세션 내내 고정이라 한 마리가
-- 실패하면 나머지도 전부 실패하므로, 첫 포기 시점에 세션 전체를 비활성화해서
-- 두 번째 좀비부터는 아예 건드리지 않는다.
--
-- ── 오래 재시도해도 '남의 옷'을 입을 위험이 없는 이유 ───────────────────────
--   descriptor 슬롯은 releasePlayerZombieDescriptor로만 반납되고, 그 유일한
--   호출 경로는 VirtualZombieManager.RemoveZombie:661 ->
--   ReanimatedPlayers.removeReanimatedPlayerFromWorld:115 다.
--   즉 '그 좀비가 월드에서 제거될 때'만 슬롯이 풀린다.
--
-- 순수 클라 로컬 렌더 보정 -- 서버/네트워크/게임 상태 영향 없음.
--
-- ── SP/서버 제외 이유 ───────────────────────────────────────────────────────
-- createPlayerZombieDescriptor는 GameServer.bServer 전용이라 SP엔 descriptor가
-- 아예 없다. SP에서 이 코드를 돌리면 pid가 '일반 좀비 복장 ID'로 해석돼 부활
-- 좀비에게 엉뚱한 랜덤 옷을 입히는 역효과가 난다. 애초에 SP는 ModelManager:558의
-- GameClient.bClient 게이트에 막혀 이 버그가 발생하지 않는다.

if isClient() then

local SCAN_INTERVAL_MS = 250     -- 좀비 리스트 스캔 간격 (= 재시도 간격)
local MAX_TRIES        = 8       -- 좀비 1마리당 재시도 상한 (약 2초)
local NO_HAT_BIT       = 32768   -- PersistentOutfits.NO_HAT_BIT

local _done     = {}     -- [onlineID] = true (복원 완료 / 대상 아님)
local _track    = {}     -- [onlineID] = { first, tries }
local _lastScan = 0
local _disabled = false  -- 원인 B 감지 시 세션 전체 비활성화

-- 모자가 벗겨진 좀비는 pid에 NO_HAT_BIT이 켜진다(PersistentOutfits.setFallenHat).
-- 그 pid를 그대로 넘기면 ApplyReanimatedPlayerOutfit의 (short)(pid & 0xFFFF)
-- 슬롯 계산이 오버플로로 음수가 돼(32768|idx) short0 >= 1 검사에서 탈락,
-- 복원이 조용히 실패한다.
-- Kahlua(Lua 5.1)에는 비트 연산자가 없으므로 나머지 연산으로 판정/제거한다.
-- reanimated player 좀비는 isUsingWornItems()가 true라 pid 기반 모자 처리
-- (removeFallenHat)가 어차피 no-op이므로 비트를 떼도 잃는 정보가 없다.
local function stripHatBit(pid)
    if pid % 65536 >= NO_HAT_BIT then return pid - NO_HAT_BIT end
    return pid
end

-- 좀비 1마리 판정/보정. 반환 true = 추적 종료(더 안 건드림).
local function tryFix(z, zid, rec, now)
    if not z:isReanimatedPlayer() then return true end      -- 대상 아님 (대부분 여기서 탈출)
    if z:getSharedDescriptor() then return true end          -- 옷 이미 정상 적용됨

    local pid = z:getPersistentOutfitID()
    if pid == 0 then return false end

    rec.tries = rec.tries + 1
    if rec.tries == 1 then
        print("[PongDu][ZOutfit] naked reanimated player zid=" .. tostring(zid)
            .. " pid=" .. tostring(pid) .. " -> reapplying outfit")
    end

    z:dressInPersistentOutfitID(stripHatBit(pid))
    if z:getSharedDescriptor() then
        z:resetModelNextFrame()
        print("[PongDu][ZOutfit] outfit restored zid=" .. tostring(zid)
            .. " tries=" .. tostring(rec.tries)
            .. " after=" .. tostring(now - rec.first) .. "ms")
        return true
    end

    if rec.tries >= MAX_TRIES then
        -- 디스크립터 도착 지연(원인 A)이라면 이 안에 무조건 성공했어야 한다.
        -- 여기 도달했다는 건 클라/서버 outfit 인덱스 불일치(원인 B)라는 뜻이므로
        -- 재시도를 멈추고 세션 전체를 비활성화한다.
        -- 아래 outfitIndex(서버 기준 ReanimatedPlayer 위치)와 slot을 로그로 남긴다.
        -- 클라에서 실제 인덱스를 읽을 방법은 없지만, 서버 값 자체가 원인 추적의
        -- 출발점이 된다.
        local stripped   = stripHatBit(pid)
        local outfitIdx  = math.floor(stripped / 65536)
        local slot       = stripped % 65536
        print("[PongDu][ZOutfit] GIVE UP zid=" .. tostring(zid)
            .. " pid=" .. tostring(pid)
            .. " outfitIndex=" .. tostring(outfitIdx)
            .. " slot=" .. tostring(slot)
            .. " tries=" .. tostring(rec.tries)
            .. " after=" .. tostring(now - rec.first) .. "ms")
        print("[PongDu][ZOutfit] descriptor arrived but ApplyReanimatedPlayerOutfit"
            .. " was never reached -- client/server PersistentOutfits index mismatch"
            .. " suspected. disabling for this session.")
        _disabled = true
        return true
    end

    return false
end

local function scan()
    local player = getSpecificPlayer(0)
    if not player then return end
    local cell = player:getCell()
    if not cell then return end
    local zlist = cell:getZombieList()
    if not zlist then return end

    local now = getTimestampMs()
    local alive = {}

    for i = 0, zlist:size() - 1 do
        local z = zlist:get(i)
        if z then
            local zid = z:getOnlineID()
            alive[zid] = true
            if not _done[zid] then
                local rec = _track[zid]
                if not rec then
                    rec = { first = now, tries = 0 }
                    _track[zid] = rec
                end
                if tryFix(z, zid, rec, now) then
                    _done[zid]  = true
                    _track[zid] = nil
                end
            end
        end
        if _disabled then break end
    end

    -- 셀에서 사라진 좀비 북키핑 정리. 청크 리로드로 좀비 객체가 새로 만들어지면
    -- _done도 함께 비워져 자동으로 재평가된다.
    for zid in pairs(_done) do
        if not alive[zid] then _done[zid] = nil end
    end
    for zid in pairs(_track) do
        if not alive[zid] then _track[zid] = nil end
    end
end

Events.OnTick.Add(function()
    if _disabled then return end
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    local ok, err = pcall(scan)
    if not ok then
        print("[PongDu][ZOutfit] scan error: " .. tostring(err))
    end
end)

end
