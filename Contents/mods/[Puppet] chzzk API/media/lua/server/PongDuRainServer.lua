-- ── 좀비 레인 (zombie_rain) 서버 ──────────────────────────────────────────────
-- 후원받은 플레이어 기준 반경(샌드박스 Rain_Radius, 기본 55) 안의 "건물이 없는"
-- 야외 스퀘어에 30초 동안 총 500마리를 60ms 간격으로 1마리씩 z=4(4층 높이)에
-- 스폰한다. 낙하는 엔진 물리가 그대로 처리한다 (IsoGameCharacter.updateFalling:
-- z>0 + 발밑 비솔리드면 틱당 z 0.125 감산, ZombieFallingState 애니 자동 발동).
--
-- 낙하 부상(DoLand, fallTime>50 시 체력 감소)은 좀비 체력이 클라 권한이라
-- 서버에서 못 막는다 -> 스폰 직후 체력을 캡처해 RainMark 배치로 전 클라에
-- 브로드캐스트하고, 소유 클라가 착지(z<=0.05) 확인 후 원복한다
-- (client/features/zombierain.lua). MutantMark와 동일한 검증된 채널 패턴.
--
-- 세션은 리스트로 관리 -> 여러 후원이 겹쳐도 각자 독립 진행 (도네큐와 무관).
-- 스프린터 비율은 샌드박스 Rain_SprinterPercent(기본 0)를 클라가 읽어 전달.

local RAIN_DURATION_MS   = 30000                            -- 30초
local RAIN_TOTAL         = 500                              -- 총 마리수
local RAIN_INTERVAL_MS   = RAIN_DURATION_MS / RAIN_TOTAL    -- 60ms/마리
local RAIN_DROP_Z        = 4                                -- 낙하 시작 높이 (4층)
local RAIN_MIN_DIST      = 3                                -- 플레이어 직격 방지 최소 거리
local SPAWN_CAP_PER_TICK = 5                                -- 랙 스파이크 후 몰아치기 상한
local BATCH_MS           = 500                              -- RainMark 브로드캐스트 묶음 주기
local PICK_TRIES         = 20                               -- 스퀘어 후보 탐색 시도 횟수

local _sessions = {}

-- 건물 없는 야외 지상(z=0) 스퀘어 선정.
--  ① sq:isOutside()            : 실외
--  ② sq:getBuilding() == nil   : 맵 건물 스퀘어 제외 (지붕 착지 방지)
--  ③ 물 스퀘어 제외             : 강/호수에 수장되는 낭비 방지
--  ④ 위층(z=1..4) 바닥 없음     : 플레이어 건축물 지붕/2층 바닥에 걸리는 것 방지
-- 20회 안에 못 찾으면 nil (도심 밀집 지역에서 일부 방울이 유실될 수 있으나
-- 페이스 유지를 위해 재시도하지 않는다 -> 최대 500, 밀집 지역은 그 이하).
local function pickRainSquare(cell, px, py, radius)
    for _ = 1, PICK_TRIES do
        local angle = ZombRand(628) / 100.0
        -- sqrt 분포 -> 원판 내 균등 (반경 비례 편중 방지)
        local dist  = RAIN_MIN_DIST
            + math.sqrt(ZombRand(10000) / 10000.0) * (radius - RAIN_MIN_DIST)
        local x  = math.floor(px + math.cos(angle) * dist)
        local y  = math.floor(py + math.sin(angle) * dist)
        local sq = cell:getGridSquare(x, y, 0)
        if sq and sq:isOutside() and sq:getBuilding() == nil
            and not sq:Is(IsoFlagType.water) then
            local blocked = false
            for zz = 1, RAIN_DROP_Z do
                local up = cell:getGridSquare(x, y, zz)
                if up and up:getFloor() ~= nil then
                    blocked = true
                    break
                end
            end
            if not blocked then return sq end
        end
    end
    return nil
end

-- 1마리 스폰: 랜덤 아웃핏(outfit=nil), 후원자 이름표 없음, 체력 캡처 후
-- 세션 배치에 적재. 스프린터 롤은 서버에서 하되 walkType 실제 적용은
-- 클라 적용기가 담당한다 (B41 MP 좀비는 클라 권한 -- 서버 setWalkType은
-- 소유 클라 동기화에 덮일 수 있어 MutantMark식 클라 적용이 신뢰 경로).
local function spawnRainZombie(session, cell)
    local p = session.player
    local sq = pickRainSquare(cell, p:getX(), p:getY(), session.radius)
    if not sq then return end
    local zeds = addZombiesInOutfit(sq:getX(), sq:getY(), 0, 1, nil, nil)
    if not zeds or zeds:size() == 0 then return end
    local zed = zeds:get(0)
    zed:DoZombieStats()
    zed:makeInactive(true)
    zed:makeInactive(false)
    local sprint = 0
    if session.sprintPct > 0 and ZombRand(100) < session.sprintPct then
        sprint = 1
    end
    -- 4층 높이로 리프트 -> 다음 틱부터 엔진 updateFalling이 낙하 처리
    pcall(function() zed:setZ(RAIN_DROP_Z + 0.0) end)
    -- 후원받은 플레이어 쪽으로 어그로 (원본 ChaosMod 플로우 동일)
    pcall(function() zed:setTarget(p) end)
    pcall(function() zed:setTurnAlertedValues(math.floor(p:getX()), math.floor(p:getY())) end)
    session.batch[#session.batch + 1] = {
        ["id"] = zed:getOnlineID(),
        ["h"]  = zed:getHealth(),   -- 착지 후 원복할 낙하 전 체력
        ["s"]  = sprint,
    }
end

local function flushBatch(session, force)
    if #session.batch == 0 then return end
    local now = getTimestampMs()
    if not force and now - session.lastFlush < BATCH_MS then return end
    session.lastFlush = now
    sendServerCommand("PongDuRain", "RainMark", { ["zeds"] = session.batch })
    session.batch = {}
end

local function onTick()
    if #_sessions == 0 then return end
    local cell = getCell()
    if not cell then return end
    local now = getTimestampMs()
    for i = #_sessions, 1, -1 do
        local s = _sessions[i]
        -- 플레이어 접속 종료 등으로 무효화되면 세션 폐기
        local alive = s.player and pcall(function() return s.player:getX() end)
        if not alive then
            print("[PongDuRain] session dropped (player gone) spawned=" .. tostring(s.spawned))
            table.remove(_sessions, i)
        else
            local elapsed = now - s.startMs
            -- 경과시간 기준 목표 마리수와의 차분만큼 스폰 (틱당 상한으로 폭주 방지)
            local target = math.floor(elapsed / RAIN_INTERVAL_MS)
            if target > RAIN_TOTAL then target = RAIN_TOTAL end
            local n = target - s.spawned
            if n > SPAWN_CAP_PER_TICK then n = SPAWN_CAP_PER_TICK end
            for _ = 1, n do
                local ok, err = pcall(spawnRainZombie, s, cell)
                if not ok then
                    print("[PongDuRain] spawn error: " .. tostring(err))
                end
                -- 유실(후보 스퀘어 없음)도 카운트에 포함해 페이스를 고정한다
                s.spawned = s.spawned + 1
            end
            flushBatch(s, false)
            if s.spawned >= RAIN_TOTAL or elapsed > RAIN_DURATION_MS + 5000 then
                flushBatch(s, true)
                print("[PongDuRain] session done player=" .. tostring(s.player:getUsername())
                    .. " spawned=" .. tostring(s.spawned))
                table.remove(_sessions, i)
            end
        end
    end
end
Events.OnTick.Add(onTick)

Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuRain" or command ~= "Start" then return end
    if not player then return end
    local r   = tonumber(data and data["r"]) or 55
    local pct = tonumber(data and data["pct"]) or 0
    if r < 10 then r = 10 elseif r > 100 then r = 100 end
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    _sessions[#_sessions + 1] = {
        player    = player,
        radius    = r,
        sprintPct = pct,
        startMs   = getTimestampMs(),
        spawned   = 0,
        batch     = {},
        lastFlush = 0,
    }
    print("[PongDuRain] session start player=" .. tostring(player:getUsername())
        .. " r=" .. tostring(r) .. " sprint%=" .. tostring(pct))
end)
