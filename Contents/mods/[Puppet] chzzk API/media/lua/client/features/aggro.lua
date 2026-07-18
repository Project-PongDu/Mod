local _a = {}

-- ── 소환 좀비 플레이어 어그로 창 (공용) v2 ──────────────────────────────────
-- 문제: 서버 스폰/부활 좀비는 target=nil로 시작 -> ZombieGroupManager(랠리)가
-- 채가서 가짜 '들은 소리'(setLastHeardSound)를 쫓아 방사형으로 흩어진다.
--
-- v1 실패 원인 (1회성 spotted):
--   * spotted(_, bForced=true)는 target은 박지만 TimeSinceSeenFlesh를 리셋하지
--     않는다 (IsoZombie.spotted: if(!bForced) TimeSinceSeenFlesh=0). 신규 좀비
--     초기값은 100000이고 매 틱 "TimeSinceSeenFlesh > memory -> setTarget(nil)"
--     체크에 걸려 다음 틱에 target이 즉시 드랍 -> 잠깐 걷다 멈춰서 멀뚱멀뚱.
--   * TimeSinceSeenFlesh는 public 인스턴스 필드지만 Kahlua exposer는 static
--     필드만 노출하므로 Lua에서 리셋 불가.
--   * setLastHeardSound는 idle 상태(비 PathFind/WalkToward) 좀비에겐 매 틱
--     (-1,-1,-1)로 소거돼 1회 심기로는 무효.
--
-- v2 대응 (창 지속 중 반복 펄스):
--   1) addSound(도네이터, 좌표, r, vol) — 월드사운드 청각 반응. RespondToSound
--      발동 조건이 "TimeSinceSeenFlesh > 240"이라 타이머 문제와 반대로 맞물려
--      확실히 걷게 만든다. mutantspawn 비명에서 실증된 패턴. 소스 본인은
--      반응하지 않으므로 소스=도네이터로 안전. 스캔당 창별 1회 (저비용).
--   2) spotted(도네이터, true) 반복 재적용 — target이 틱마다 드랍돼도 250ms
--      마다 다시 박아 경로를 갱신. spotted 내부 "AllowRepathDelay > 0 이면
--      target 재설정 후 리턴" 가드가 경로탐색 폭주를 자체 차단한다 (재경로는
--      약 8초 주기). 플레이어가 실제 시야에 들어오면 자연 스팟(비강제)이
--      TimeSinceSeenFlesh=0으로 리셋 -> 진짜 지속 추격으로 전환.
--   3) setLastHeardSound(도네이터 좌표) — WalkToward/PathFind 중인 좀비의
--      이동 목적지를 플레이어 쪽으로 계속 당겨줌 (idle 좀비 것은 엔진이
--      소거하지만 1)이 커버).
--   * target 보유 중엔 ZombieGroupManager.shouldBeInGroup에서 제외 -> 랠리
--     편입 차단은 v1과 동일하게 유지된다.
--
-- 원격 좀비엔 spotted가 자체 no-op(소유 클라 권한)이므로 전 클라 브로드캐스트
-- + 각 클라 로컬 적용 구조 그대로. 서버/네트워크 부하 없음.

local SCAN_INTERVAL_MS = 250     -- 펄스 간격
local LOG_INTERVAL_MS  = 2000    -- 창별 실적 로그 간격 (스팸 방지)
local _windows  = {}             -- {x, y, r, r2, expires, pid, lastLog, pulsed}
local _lastScan = 0

local function pruneWindows()
    local now = getTimestampMs()
    for i = #_windows, 1, -1 do
        if now > _windows[i].expires then
            print("[PongDu][Aggro] window closed pid=" .. tostring(_windows[i].pid)
                .. " pulses=" .. tostring(_windows[i].pulsed))
            table.remove(_windows, i)
        end
    end
    return #_windows > 0
end

-- 좀비 1마리에 어그로 펄스. 성공 여부 반환.
local function applyAggro(z, target, tx, ty, tz)
    return pcall(function()
        z:spotted(target, true)
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

            -- 1) 월드사운드 펄스: 반경 내 전 좀비 청각 유인 (스캔당 1회)
            pcall(function()
                addSound(target, tx, ty, tz, w.r + 10, w.r + 10)
            end)

            -- 2) + 3) 반경 내 자기 소유 좀비에 spotted/들은소리 재적용
            local hit = 0
            for i = 0, zlist:size() - 1 do
                local z = zlist:get(i)
                if z and not z:isDead() then
                    local dx = z:getX() - w.x
                    local dy = z:getY() - w.y
                    if dx * dx + dy * dy <= w.r2 then
                        local remote = false
                        pcall(function() remote = z:isRemoteZombie() end)
                        if not remote and applyAggro(z, target, tx, ty, tz) then
                            hit = hit + 1
                        end
                    end
                end
            end
            w.pulsed = w.pulsed + 1

            if hit > 0 and now - w.lastLog >= LOG_INTERVAL_MS then
                w.lastLog = now
                print("[PongDu][Aggro] pulse zeds=" .. tostring(hit)
                    .. " pid=" .. tostring(w.pid)
                    .. " @" .. tostring(tx) .. "," .. tostring(ty))
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
    if module ~= "PongDuAggro" or command ~= "Window" then return end
    local x   = tonumber(args and args["x"])
    local y   = tonumber(args and args["y"])
    local r   = tonumber(args and args["r"]) or 15
    local dur = tonumber(args and args["dur"]) or 8000
    local pid = tonumber(args and args["pid"])
    if not x or not y or not pid then return end
    local now = getTimestampMs()
    _windows[#_windows + 1] = {
        x = x, y = y, r = r, r2 = r * r,
        expires = now + dur, pid = pid,
        lastLog = 0, pulsed = 0,
    }
    print("[PongDu][Aggro] window open @" .. tostring(x) .. "," .. tostring(y)
        .. " r=" .. tostring(r) .. " dur=" .. tostring(dur)
        .. " pid=" .. tostring(pid))
end)

return _a
