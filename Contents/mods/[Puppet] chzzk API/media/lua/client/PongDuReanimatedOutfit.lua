-- PongDuReanimatedOutfit.lua : 좀비화된 플레이어의 '알몸 렌더링' 보정 (MP 클라 전용)
--
-- ── 증상 ────────────────────────────────────────────────────────────────────
-- 플레이어 시체가 좀비로 부활하면 그 좀비가 알몸으로 그려진다. 그 좀비를 다시
-- 죽여서 나온 시체는 원래 복장/아이템을 정상적으로 갖고 있다. 데이터는 멀쩡하고
-- 렌더용 비주얼만 비어 있는 상태다.
--
-- ── 왜 강령술(RiseUp)에서 유독 잘 보이는가 ──────────────────────────────────
-- 알파테스트 클라 로그 대조 결과: 플레이어 좀비화 12건 중 10건이 RiseUp 발동
-- 60초 이내, 그중 7건은 25초 이내(최소 0.0초 = 같은 틱)였다. 바닐라 자연 부활
-- (ZombieLore.Reanimate 기본값 3 = 1분 뒤)은 목격 자체가 드문 반면, RiseUp은
-- 반경 55칸의 시체를 즉시, 수십~수백 구 동시에 일으켜 아래 레이스를 대량으로
-- 노출시킨다. 결함 있는 코드 경로 자체는 바닐라 것이지만, 실질 트리거는 강령술이다.
--
-- server.lua의 RiseUp 핸들러는 플레이어 시체를 markFakeDead에서 의도적으로
-- 제외한다(플레이어 옷은 pid가 아닌 실제 wornItems라 pid 재구성이 불가능하므로
-- 디스크립터 경로가 맞다). 그 판단은 옳고, 이 파일은 그 경로의 레이스만 보정한다.
--
-- ── 원인 (바닐라 B41 MP의 패킷 도착 순서 레이스) ────────────────────────────
--   IsoDeadBody.reanimate() (IsoDeadBody.java:1309)
--     isFakeDead()==false -> setReanimatedPlayer(true)
--                            + SharedDescriptors.createPlayerZombieDescriptor()
--   -> 옷이 pid로 재구성되지 않고 ZombieDescriptors 패킷으로 따로 push된다
--      (SharedDescriptors.java:82). 좀비 sync와 완전히 다른 채널이다.
--
-- 클라가 이 좀비를 처음 렌더 리스트에 올릴 때:
--   ModelManager.dressInRandomOutfit:558 -> dressInPersistentOutfitID(pid)
--   IsoZombie.dressInPersistentOutfitID:3575
--       getHumanVisual().clear()          <- 먼저 벗기고
--       itemVisuals.clear()
--       m_bPersistentOutfitInit = true    <- "처리 완료"로 봉인하고
--       dressInOutfit() -> ApplyReanimatedPlayerOutfit
--   SharedDescriptors.ApplyReanimatedPlayerOutfit:136
--       PlayerZombieDescriptors[slot]이 아직 null이면 조용히 리턴 (아무것도 안 입힘)
--
-- 결과: descriptor가 좀비보다 늦게 도착하면 HumanVisual이 빈 채로 고착된다.
-- m_bPersistentOutfitInit=true라 엔진이 다시 시도하지도 않는다 -> 영구 알몸.
-- 반면 wornItems는 건드리지 않으므로(dressInNamedOutfit과 달리 wornItems.clear()가
-- 없다) 죽이면 시체가 옷을 정상적으로 물려받는다 -- 관측된 증상 그대로다.
--
-- ── 수정: 엔진이 딱 한 번 하고 포기한 시도를, 성공할 때까지 대신 눌러준다 ────
-- 성공 판정은 IsoZombie.sharedDesc를 읽는다:
--   · useDescriptor()가 성공했을 때만 세팅됨 (IsoZombie.java:3478)
--   · 풀 반환 시 resetForReuse()가 null로 초기화 (IsoZombie.java:3383,
--     VirtualZombieManager.java:70) -> 재활용 좀비의 잔여값 오탐 없음
-- 즉 "isReanimatedPlayer인데 sharedDesc가 nil" = 레이스에 당한 좀비다.
--
-- ★ 타임아웃을 두지 않는 이유 (이 수정의 핵심)
--   ZombieDescriptors는 RELIABLE 패킷이다(PacketTypes.java:225, reliability=2).
--   유실돼도 RakNet이 재전송하므로 '반드시' 도착한다. 늦을 뿐이다.
--   따라서 좀비가 살아 있는 한 재시도를 포기하지 않으면 복원은 100% 성공한다.
--   타임아웃을 두면 그게 곧 "그 안에 안 오면 알몸 확정"이라는 구멍이 된다.
--
-- ★ 오래 재시도해도 '남의 옷'을 입을 위험이 없는 이유
--   descriptor 슬롯은 releasePlayerZombieDescriptor로만 반납되고, 그 유일한
--   호출 경로는 VirtualZombieManager.RemoveZombie:661 ->
--   ReanimatedPlayers.removeReanimatedPlayerFromWorld:115 다.
--   즉 '그 좀비가 월드에서 제거될 때'만 슬롯이 풀린다. 좀비가 살아 있는 동안은
--   슬롯이 계속 점유 중이라 다른 플레이어 좀비가 같은 슬롯을 가져갈 수 없다.
--   재시도 기간이 길어져도 슬롯이 바뀌지 않는다.
--
-- 재호출 자체도 부작용이 없다: ReanimatedPlayer outfitter는 useDescriptor만 하고,
-- 일반 옷 경로(applyOutfit)의 랜덤 피/먼지/부착무기 추가를 타지 않는다
-- (PersistentOutfits.dressInOutfit:331은 outfitter만 호출).
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
local REPORT_EVERY_MS  = 10000   -- 장기 대기 시 경과 보고 간격 (로그 폭주 방지)
local NO_HAT_BIT       = 32768   -- PersistentOutfits.NO_HAT_BIT

local _done  = {}   -- [onlineID] = true (복원 완료 / 대상 아님)
local _track = {}   -- [onlineID] = { first, tries, lastReport }
local _lastScan = 0

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
    if pid ~= 0 then
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
    end

    -- 포기하지 않는다. descriptor는 RELIABLE이라 결국 도착한다.
    -- 다만 비정상적으로 오래 걸리면 관측 가능하도록 주기적으로만 보고한다.
    if now - rec.lastReport >= REPORT_EVERY_MS then
        rec.lastReport = now
        print("[PongDu][ZOutfit] still waiting for descriptor zid=" .. tostring(zid)
            .. " pid=" .. tostring(pid) .. " tries=" .. tostring(rec.tries)
            .. " elapsed=" .. tostring(now - rec.first) .. "ms")
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
                    rec = { first = now, tries = 0, lastReport = now }
                    _track[zid] = rec
                end
                if tryFix(z, zid, rec, now) then
                    _done[zid]  = true
                    _track[zid] = nil
                end
            end
        end
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
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    local ok, err = pcall(scan)
    if not ok then
        print("[PongDu][ZOutfit] scan error: " .. tostring(err))
    end
end)

end
