local _a = {}

-- ── 소환 좀비 플레이어 어그로 (공용) v4: zid 화이트리스트 스코프 ─────────────
-- v3까지의 문제: 창이 "좌표+반경" 필터라 반경 안에 원래 있던 무관한 좀비까지
--   전부 인계 대상이 됐고, 원거리 유인용 전역 addSound(월드사운드)는 청각
--   범위 내 모든 좀비를 자극했다 → 도네 효과와 무관한 주변 좀비 총출동.
--
-- v4: 창이 "도네이션이 만든 좀비의 onlineID 집합"을 들고 다닌다.
--   * 스캔은 집합에 있는 zid만 처리 — 반경 필터/전역 addSound 완전 삭제.
--   * id 공급 경로 (feature별):
--       좀비소환  : 서버 spawnZombies가 스폰 즉시 id 수집 → Window에 동봉
--       변종좀비  : 서버 spawnSpecialZombie의 zed 1마리 → Window에 동봉
--       좀비비    : 스폰이 배치 분산이라 Window는 빈 채로 열고, 서버
--                   flushBatch가 RainMark와 같은 주기로 AddIds를 쏨
--       강령술    : reanimateNow()는 예약만 하고 실제 부활은 다음 틱이라
--                   서버가 새 zid를 못 본다(RiseUp findFreshZombie NOT FOUND
--                   100/100 확증). 대신 클라 riseup.lua layDown()이 부활
--                   좀비를 정확히 식별하므로 거기서 addLocalIds()로 로컬 등록.
--                   → Window는 src="riseup"으로 빈 채 열린다.
--
-- 원거리 유인 대체 (전역 addSound 삭제분):
--   비강제 spotted는 20타일 하드컷(-10000)이 있고, 강제 spotted(bForced)도
--   확률만 1000000으로 박을 뿐 그 전에 dist > viewDist(주간 ~28 / 야간 ~15)면
--   블록 전체가 스킵된다(IsoZombie.spotted:1410) — 밤 원거리엔 무력.
--   대신 엔진 Hearing 응답 블록(IsoZombie:1095)이 쓰는 per-zombie 3종 세트를
--   그대로 재현한다 (전부 public, Kahlua 노출):
--     setTurnAlertedValues(x,y) + pathToSound(x,y,z) + setLastHeardSound(...)
--   이건 해당 좀비 하나만 도네이터 좌표로 경로를 잡는다 — 주변 영향 0.
--   pathToSound는 리패스 비용이 있으므로 좀비별 LURE_INTERVAL_MS 스로틀.
--
-- 인계 원리는 v3 그대로 — 엔진의 자체 지속 어그로 루프에 태워보낸다:
--   spotted(target, false) 비강제 스팟이 확률 굴림에 성공하면
--     TimeSinceSeenFlesh=0  → target이 memory(기본 800유닛) 동안 유지,
--                             랠리 조건도 2000유닛 봉쇄
--     BonusSpotTime=120     → updateInternal:2137에서 엔진이 매 틱 스스로
--                             spotted(spottedLast,true) 재호출 — 이후 추격
--                             유지는 전부 엔진 몫
--   즉 비강제 스팟 1회 성공 = 영구 인계. 창은 "인계 부트스트랩 기간"이다.
--   인계 판정: 직전 펄스에서 spotted(false)가 성공했다면 250ms 뒤 스캔에서
--   z:getTarget() ~= nil 로 관측된다. target 보유 = 인계 완료로 확정하고
--   그 좀비는 이후 완전히 손을 뗀다.
--
-- 원격 좀비엔 spotted/pathToSound가 소유 클라 권한이라 실효 없음 →
-- 전 클라 브로드캐스트 + 각 클라가 자기 소유 좀비에만 적용하는 구조 그대로.

local SCAN_INTERVAL_MS = 250     -- 부트스트랩 펄스 간격
local LOG_INTERVAL_MS  = 2000    -- 창별 실적 로그 간격 (스팸 방지)
local LURE_INTERVAL_MS = 2000    -- 원거리 유인(pathToSound) 좀비별 재적용 간격
local SIGHT_RANGE      = 18      -- 비강제 스팟 시도 한계 (엔진 하드컷 20에 여유)
local SIGHT_RANGE2     = SIGHT_RANGE * SIGHT_RANGE
local _windows  = {}             -- {ids, nIds, expires, pid, src, lastLog, handoff}
local _handoff  = {}             -- [onlineID] = true : 엔진 인계 완료 (전역)
local _lastLure = {}             -- [onlineID] = 마지막 pathToSound 시각(ms)
local _lastScan = 0

local function pruneWindows()
    local now = getTimestampMs()
    for i = #_windows, 1, -1 do
        if now > _windows[i].expires then
            print("[PongDu][Aggro] window closed src=" .. tostring(_windows[i].src)
                .. " pid=" .. tostring(_windows[i].pid)
                .. " ids=" .. tostring(_windows[i].nIds)
                .. " handoff=" .. tostring(_windows[i].handoff))
            table.remove(_windows, i)
        end
    end
    if #_windows == 0 then
        -- 전 창 종료 시 기록 정리 (Kahlua엔 next 없음 — pairs로 비움)
        for k in pairs(_handoff)  do _handoff[k]  = nil end
        for k in pairs(_lastLure) do _lastLure[k] = nil end
    end
    return #_windows > 0
end

-- id 배열을 창의 집합에 병합. 반환: 새로 추가된 개수.
local function mergeIds(w, ids)
    local added = 0
    if type(ids) ~= "table" then return 0 end
    for i = 1, #ids do
        local zid = tonumber(ids[i])
        if zid and not w.ids[zid] then
            w.ids[zid] = true
            w.nIds = w.nIds + 1
            added = added + 1
        end
    end
    return added
end

-- 강령술 클라 로컬 등록: riseup.lua layDown()이 부활 좀비 확정 시 호출.
-- src="riseup" 창이 없으면 no-op (평시 realState 경로 laydown 오폭 방지).
function _a.addLocalIds(ids)
    local added = 0
    for i = 1, #_windows do
        if _windows[i].src == "riseup" then
            added = added + mergeIds(_windows[i], ids)
        end
    end
    if added > 0 then
        print("[PongDu][Aggro] local ids added=" .. tostring(added) .. " (riseup)")
    end
end

-- 좀비 1마리 인계 시도 (18타일 내, 서있음). 성공 여부가 아니라 "시도 여부"를
-- 반환한다 (성공 판정은 다음 스캔에서 target 보유로 확인).
local function tryHandoff(z, target)
    return pcall(function()
        z:faceThisObject(target)
        z:spotted(target, false)
    end)
end

-- 원거리 유인: 엔진 Hearing 응답과 동일 세트를 이 좀비 하나에만 적용.
local function tryLure(z, tx, ty, tz)
    return pcall(function()
        z:setTurnAlertedValues(tx, ty)
        z:pathToSound(tx, ty, tz)
        z:setLastHeardSound(tx, ty, tz)
    end)
end

local function aggroScan()
    local cell = getCell()
    if not cell then return end
    local zlist = cell:getZombieList()
    if not zlist then return end
    local now = getTimestampMs()

    for wi = 1, #_windows do
        local w = _windows[wi]
        -- 대상 플레이어는 스캔 시점 좌표로 매번 재해석 (창 지속 중 이동 추적)
        local target = getPlayerByOnlineID(w.pid)
        if target and not target:isDead() then
            local tx = math.floor(target:getX())
            local ty = math.floor(target:getY())
            local tz = math.floor(target:getZ())

            local tried, lured = 0, 0
            for i = 0, zlist:size() - 1 do
                local z = zlist:get(i)
                if z and not z:isDead() then
                    local zid = z:getOnlineID()
                    if w.ids[zid] and not _handoff[zid] then
                        local remote = false
                        pcall(function() remote = z:isRemoteZombie() end)
                        if not remote then
                            local tgt
                            pcall(function() tgt = z:getTarget() end)
                            if tgt ~= nil then
                                -- 직전 비강제 스팟(또는 자연 스팟)이 살아남음
                                -- = TimeSinceSeenFlesh=0 확정 = 엔진 인계 완료
                                _handoff[zid] = true
                                w.handoff = w.handoff + 1
                            else
                                local st
                                pcall(function() st = z:getCurrentState() end)
                                local lying = (st == ZombieOnGroundState.instance())
                                    or (st == ZombieGetUpState.instance())
                                if not lying then
                                    local ddx = z:getX() - target:getX()
                                    local ddy = z:getY() - target:getY()
                                    if ddx * ddx + ddy * ddy <= SIGHT_RANGE2 then
                                        if tryHandoff(z, target) then
                                            tried = tried + 1
                                        end
                                    elseif now - (_lastLure[zid] or 0) >= LURE_INTERVAL_MS then
                                        _lastLure[zid] = now
                                        if tryLure(z, tx, ty, tz) then
                                            lured = lured + 1
                                        end
                                    end
                                end
                                -- 누움: updateInternal이 target 블록을 스킵하는
                                -- 상태라 인계 불가 → 일어날 때까지 시도 보류.
                            end
                        end
                    end
                end
            end

            if now - w.lastLog >= LOG_INTERVAL_MS then
                w.lastLog = now
                print("[PongDu][Aggro] pulse tried=" .. tostring(tried)
                    .. " lured=" .. tostring(lured)
                    .. " handoff=" .. tostring(w.handoff)
                    .. "/" .. tostring(w.nIds)
                    .. " src=" .. tostring(w.src)
                    .. " pid=" .. tostring(w.pid))
            end
        elseif now - w.lastLog >= LOG_INTERVAL_MS then
            w.lastLog = now
            print("[PongDu][Aggro] target unresolved pid=" .. tostring(w.pid)
                .. (target and " (dead)" or " (not loaded)"))
        end
    end
end

Events.OnTick.Add(function()
    if not pruneWindows() then return end
    local now = getTimestampMs()
    if now - _lastScan < SCAN_INTERVAL_MS then return end
    _lastScan = now
    local ok, err = pcall(aggroScan)
    if not ok then
        print("[PongDu][Aggro] scan error: " .. tostring(err))
    end
end)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuAggro" then return end
    if command == "Window" then
        local dur = tonumber(args and args["dur"]) or 8000
        local pid = tonumber(args and args["pid"])
        local src = tostring(args and args["src"] or "?")
        if not pid then return end
        local now = getTimestampMs()
        local w = {
            ids = {}, nIds = 0,
            expires = now + dur, pid = pid, src = src,
            lastLog = 0, handoff = 0,
        }
        mergeIds(w, args and args["zeds"])
        _windows[#_windows + 1] = w
        print("[PongDu][Aggro] window open src=" .. src
            .. " ids=" .. tostring(w.nIds)
            .. " dur=" .. tostring(dur)
            .. " pid=" .. tostring(pid))
    elseif command == "AddIds" then
        -- 좀비비 배치 스폰분 추가 공급 (서버 flushBatch 발신)
        local pid = tonumber(args and args["pid"])
        if not pid then return end
        local added = 0
        for i = 1, #_windows do
            if _windows[i].pid == pid then
                added = added + mergeIds(_windows[i], args and args["zeds"])
            end
        end
        if added > 0 then
            print("[PongDu][Aggro] ids added=" .. tostring(added)
                .. " pid=" .. tostring(pid))
        end
    end
end)

return _a
