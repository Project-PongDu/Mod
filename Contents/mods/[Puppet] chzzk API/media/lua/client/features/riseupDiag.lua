-- ═══════════════════════════════════════════════════════════════════════════
--  '알몸 부활' 현상 진단 전용 로거 (테스터 배포용, 클라 전용)
--
--  ⚠ 이 파일은 진단만 한다. 아무것도 고치지 않는다.
--  ⚠ 향후 만들 riseupRedress.lua(패치)와 절대 동시에 넣지 말 것 —
--     패치가 증상을 없애버려서 이 로거가 아무것도 못 잡는다. 이번엔 이것만.
--
--  ── 이 버전이 이전(RiseUp 트리거) 버전과 다른 점 ───────────────────────────
--  바닐라 IsoDeadBody.reanimate()는 isFakeDead()==false인 모든 시체를
--  setReanimatedPlayer(true) + createPlayerZombieDescriptor 경로로 보낸다.
--  이 경로는 RiseUp뿐 아니라 '플레이어/NPC가 감염으로 좀비화 사망'할 때도
--  똑같이 탄다. 반면 부상 사망(시체로만 남음)은 이 경로를 안 타서 정상이다.
--  따라서 트리거를 RiseUp(MutantReviveDebug)에 묶으면 좀비화 사망 케이스를
--  놓친다. 이 버전은 트리거 없이 OnTick 상시 스윕으로 세 경로를 다 잡는다.
--
--  ── 무엇을 로깅하나 ─────────────────────────────────────────────────────────
--  isReanimatedPlayer()==true 인 좀비를 상시 감시하다가, 처음으로 worn==0
--  (착의 비주얼 없음)이 관측되면 그 순간을 1회 기록한다. 이때:
--    worn = getWornItems():size()        (착의 슬롯 수 = 비주얼 판정)
--    inv  = getInventory():getItems():size()  (소지품 수)
--  worn==0 인데 inv>0 이면 '비주얼만 알몸, 아이템은 보유' → 순수 렌더 레이스.
--  worn==0 이고 inv==0 이면 '아이템도 없음' → 데이터 자체 유실 가능성(별도 조사).
--  이후 같은 좀비가 worn>0 으로 바뀌면(디스크립터 늦게 도착) 회복 시각을,
--  세션 내내 안 바뀌면 영구 알몸으로 판정해 로그에 남긴다.
--
--  ── 사용법(테스터 안내) ────────────────────────────────────────────────────
--    1) 이 파일만 mods 폴더에 드롭인 (패치 파일은 넣지 말 것)
--    2) 케이스별로 재현:
--       (a) RiseUp 대량 부활 (시체 15구+ 권장)
--       (b) 감염으로 좀비화 사망시켜 보기
--       (c) 부상 사망(대조군, 알몸 안 나야 정상)
--    3) 각 재현 후 최소 25초 그 자리에서 대기 (회복 추적 창)
--    4) console.txt 통째로 전달
--
--  로그 태그: [PongDu][Diag]
-- ═══════════════════════════════════════════════════════════════════════════

-- 추적 중인 알몸 좀비: [onlineID] = { firstMs, worn0, inv0, resolved, lastLogMs }
local _tracked = {}

-- 회복/영구 판정 대기 시간. 이 시간까지 worn>0 안 되면 영구 알몸으로 로깅.
local PERMANENT_AFTER_MS = 20000

-- 상시 스윕은 매 틱 전수 순회하면 비싸므로 폴링 간격을 둔다(250ms).
local SCAN_INTERVAL_MS = 250
local _lastScan = 0

local function who()
    local ok, name = pcall(function() return getSpecificPlayer(0):getUsername() end)
    return (ok and name) or "?"
end

local function envTag()
    -- 호스트 자신인지 원격 클라인지. 해석의 분기점이라 매 로그에 박는다.
    -- (호스트에서도 서버스레드→클라렌더 사이 레이스로 알몸이 날 수 있어 둘 다 관측)
    return (isClient() == false) and "HOST" or "REMOTE"
end

-- 좀비의 착의 슬롯 수 (비주얼 알몸 판정)
local function wornCount(z)
    local n = -1
    pcall(function() n = z:getWornItems():size() end)
    return n
end

-- 좀비의 소지품(인벤토리) 개수 — '아이템 보유 여부' 확정용
local function invCount(z)
    local n = -1
    pcall(function()
        local inv = z:getInventory()
        if inv then n = inv:getItems():size() end
    end)
    return n
end

local function scan()
    local ok, err = pcall(function()
        local player = getSpecificPlayer(0)
        if not player then return end
        local cell = player:getCell()
        if not cell then return end

        local now = getTimestampMs()
        local zlist = cell:getZombieList()
        local seen = {}

        for i = 0, zlist:size() - 1 do
            local z = zlist:get(i)
            if z and z:isReanimatedPlayer() then
                local zid = z:getOnlineID()
                seen[zid] = true
                local worn = wornCount(z)
                local rec = _tracked[zid]

                if worn == 0 then
                    -- 알몸 상태 관측
                    if not rec then
                        -- 최초 감지 → 1회 상세 기록
                        local inv = invCount(z)
                        _tracked[zid] = {
                            firstMs = now, worn0 = worn, inv0 = inv,
                            resolved = false, lastLogMs = now,
                        }
                        print(string.format(
                            "[PongDu][Diag] NAKED-DETECT zid=%s env=%s user=%s worn=%d inv=%d pid=%s pos=%d,%d,%d t=%d",
                            tostring(zid), envTag(), who(), worn, inv,
                            tostring(z:getPersistentOutfitID()),
                            z:getX(), z:getY(), z:getZ(), now
                        ))
                    elseif not rec.resolved
                        and (now - rec.firstMs) >= PERMANENT_AFTER_MS
                        and (now - rec.lastLogMs) >= PERMANENT_AFTER_MS then
                        -- 아직 회복 안 됨 + 판정시간 경과 → 영구 알몸 1회 로깅(중복 억제)
                        local inv = invCount(z)
                        rec.lastLogMs = now
                        rec.resolved = true
                        print(string.format(
                            "[PongDu][Diag] NAKED-PERMANENT zid=%s env=%s worn=0 inv=%d after=%dms",
                            tostring(zid), envTag(), inv, now - rec.firstMs
                        ))
                    end
                elseif worn > 0 and rec and not rec.resolved then
                    -- 알몸이었다가 착의 회복됨(디스크립터 늦게 도착) → 회복 시각 로깅
                    rec.resolved = true
                    print(string.format(
                        "[PongDu][Diag] NAKED-RESOLVED zid=%s env=%s worn=%d after=%dms (디스크립터 지연 도착)",
                        tostring(zid), envTag(), worn, now - rec.firstMs
                    ))
                end
            end
        end

        -- 스트리밍 아웃/사망으로 사라진 추적 항목 정리(메모리 누수 방지)
        for zid, rec in pairs(_tracked) do
            if not seen[zid] and rec.resolved then
                _tracked[zid] = nil
            end
        end
    end)
    if not ok then
        print("[PongDu][Diag] scan error: " .. tostring(err))
    end
end

Events.OnTick.Add(function()
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    scan()
end)

print("[PongDu][Diag] riseupDiag v2 loaded (상시 스윕, 아무것도 고치지 않음) env=" .. envTag())
