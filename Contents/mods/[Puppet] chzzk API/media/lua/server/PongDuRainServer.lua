-- ── 좀비 레인 (zombie_rain) 서버 ── [프로토타입: 런타임 스퀘어 생성 방식] ──────
-- B41 MP에서 야외 공중(z>0) 컬럼은 그리드 스퀘어가 존재하지 않아,
--  ① 클라 재생성 관문(NetworkZombieSimulator.parseZombie: getGridSquare(realZ)==null → 스킵)
--  ② 낙하물리(updateFalling: 현재 z 스퀘어 없으면 지상 폴백 → 유령 바닥 착지)
-- 두 지점에서 z 리프트 방식이 전부 막힌다.
--
-- 해결: 스폰 전에 서버+전체 클라가 해당 컬럼에 z=1..4 "빈 스퀘어"를
-- createNewGridSquare로 실제 생성해 둔다 (바닐라 건축 시스템이 쓰는 API,
-- IsoCell.createNewGridSquare -- 멱등: 이미 있으면 그대로 반환).
-- 스퀘어가 실존하면 ①②가 모두 바닐라 경로 그대로 성립한다.
--
-- 플로우:
--  Start 수신 → 컬럼 일괄 선정 → 서버 스퀘어 생성 → Prep 브로드캐스트(클라 생성)
--  → PREP_DELAY 대기 → z=DROP_Z에 직접 스폰(페이스 유지) → RainMark(체력/스프린터)
--
-- 낙하 데미지(DoLand, fallTime>50)는 좀비 체력이 클라 권한이라 서버에서 못 막는다
-- → 스폰 직후 체력을 RainMark로 브로드캐스트, 소유 클라가 착지(z<=0.05) 후 원복
-- (client/features/zombierain.lua). 검증된 기존 채널 그대로.
--
-- [실험 유의] 생성된 빈 스퀘어는 지울 수 있는 API가 없어 월드에 잔류한다.
-- 발동당 최대 Rain_Count x DROP_Z개. 실험 월드에서 세이브 크기/부하 실측 후
-- 본 규모(500) 확장 여부를 결정한다.

-- 지속시간/마리수는 샌드박스(Rain_Duration/Rain_Count)를 클라가 Start에 실어
-- 보내고, 여기 값들은 파라미터 누락(구버전 클라) 시 폴백 + 클램프 한계로 쓴다.
local RAIN_DUR_DEFAULT_S = 30                               -- 지속시간 폴백 (초)
local RAIN_DUR_MIN_S     = 5
local RAIN_DUR_MAX_S     = 120
local RAIN_CNT_DEFAULT   = 100                              -- 마리수 폴백
local RAIN_CNT_MIN       = 10
local RAIN_CNT_MAX       = 500
local RAIN_DROP_Z        = 4                                -- 낙하 시작 높이 (4층)
local RAIN_MIN_DIST      = 3                                -- 플레이어 직격 방지 최소 거리
local SPAWN_CAP_PER_TICK = 5                                -- 랙 스파이크 후 몰아치기 상한
local BATCH_MS           = 500                              -- RainMark 브로드캐스트 묶음 주기
local PICK_TRIES         = 20                               -- 컬럼 후보 탐색 시도 횟수
local PREP_DELAY_MS      = 1000                             -- 클라 스퀘어 생성 대기

local _sessions = {}

-- 건물 없는 야외 지상(z=0) 컬럼 선정.
--  ① sq:isOutside()            : 실외
--  ② sq:getBuilding() == nil   : 맵 건물 스퀘어 제외 (지붕 착지 방지)
--  ③ 물 스퀘어 제외             : 강/호수 수장 방지
--  ④ 위층(z=1..DROP_Z) 바닥 없음: 플레이어 건축물 지붕/2층 바닥 방지.
--     스퀘어가 존재해도 바닥이 없으면 통과 (이전 레인이 만든 빈 스퀘어 재사용)
local function pickRainColumn(cell, px, py, radius)
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
            if not blocked then return x, y end
        end
    end
    return nil
end

-- 1마리 스폰: z=DROP_Z 스퀘어에 직접 생성. 랜덤 아웃핏(outfit=nil),
-- 체력 캡처 후 세션 배치에 적재. 스프린터 롤은 서버에서 하되 walkType 실제
-- 적용은 클라 적용기 담당 (B41 MP 좀비는 클라 권한).
local function spawnRainZombie(session, col)
    local zeds = addZombiesInOutfit(col.x, col.y, RAIN_DROP_Z, 1, nil, nil)
    if not zeds or zeds:size() == 0 then return false end
    local zed = zeds:get(0)
    zed:DoZombieStats()
    local sprint = 0
    if session.sprintPct > 0 and ZombRand(100) < session.sprintPct then
        sprint = 1
    end
    -- 후원받은 플레이어 쪽으로 어그로
    local p = session.player
    pcall(function() zed:setTarget(p) end)
    pcall(function() zed:setTurnAlertedValues(math.floor(p:getX()), math.floor(p:getY())) end)
    session.batch[#session.batch + 1] = {
        ["id"] = zed:getOnlineID(),
        ["h"]  = zed:getHealth(),   -- 착지 후 원복할 낙하 전 체력
        ["s"]  = sprint,
    }
    return true
end

local function flushBatch(session, force)
    if #session.batch == 0 then return end
    local now = getTimestampMs()
    if not force and now - session.lastFlush < BATCH_MS then return end
    session.lastFlush = now
    sendServerCommand("PongDuRain", "RainMark", {
        ["zeds"]   = session.batch,
        ["sender"] = session.sender or "",   -- 스프린터 이름표용 (세션 공통)
    })
    -- 어그로 스코프 공급: 이번 배치의 zid를 열려있는 어그로 창(pid 매칭)에
    -- 추가한다 (features/aggro.lua "AddIds" 수신부). 낙하 좀비는 배치 분산
    -- 스폰이라 창 오픈 시점엔 id가 없다 — 배치마다 증분 공급.
    pcall(function()
        local ids = {}
        for i = 1, #session.batch do ids[i] = session.batch[i]["id"] end
        sendServerCommand("PongDuAggro", "AddIds", {
            ["pid"]  = session.player:getOnlineID(),
            ["zeds"] = ids,
        })
    end)
    session.batch = {}
end

local function onTick()
    if #_sessions == 0 then return end
    local now = getTimestampMs()
    for i = #_sessions, 1, -1 do
        local s = _sessions[i]
        -- 플레이어 접속 종료 등으로 무효화되면 세션 폐기
        local alive = s.player and pcall(function() return s.player:getX() end)
        if not alive then
            print("[PongDuRain] session dropped (player gone) spawned=" .. tostring(s.spawned))
            table.remove(_sessions, i)
        elseif now >= s.readyAt then
            if not s.startMs then s.startMs = now end
            local elapsed = now - s.startMs
            -- 경과시간 기준 목표 마리수와의 차분만큼 스폰 (틱당 상한으로 폭주 방지)
            local target = math.floor(elapsed / s.intervalMs)
            if target > #s.cols then target = #s.cols end
            local n = target - s.spawned
            if n > SPAWN_CAP_PER_TICK then n = SPAWN_CAP_PER_TICK end
            for _ = 1, n do
                s.spawned = s.spawned + 1
                local ok, res = pcall(spawnRainZombie, s, s.cols[s.spawned])
                if not ok then
                    print("[PongDuRain] spawn error: " .. tostring(res))
                elseif res then
                    s.hits = s.hits + 1
                end
            end
            flushBatch(s, false)
            if s.spawned >= #s.cols or elapsed > s.durMs + 5000 then
                flushBatch(s, true)
                print("[PongDuRain] session done player=" .. tostring(s.player:getUsername())
                    .. " spawned=" .. tostring(s.spawned) .. " hits=" .. tostring(s.hits)
                    .. " cols=" .. tostring(#s.cols))
                table.remove(_sessions, i)
            end
        end
    end
end
Events.OnTick.Add(onTick)

Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuRain" or command ~= "Start" then return end
    if not player then return end
    local cell = getCell()
    if not cell then return end
    local r      = tonumber(data and data["r"]) or 55
    local pct    = tonumber(data and data["pct"]) or 0
    local durS   = tonumber(data and data["dur"]) or RAIN_DUR_DEFAULT_S
    local cnt    = tonumber(data and data["cnt"]) or RAIN_CNT_DEFAULT
    local sender = tostring(data and data["sender"] or "")
    if r < 10 then r = 10 elseif r > 100 then r = 100 end
    if pct < 0 then pct = 0 elseif pct > 100 then pct = 100 end
    if durS < RAIN_DUR_MIN_S then durS = RAIN_DUR_MIN_S
    elseif durS > RAIN_DUR_MAX_S then durS = RAIN_DUR_MAX_S end
    cnt = math.floor(cnt)
    if cnt < RAIN_CNT_MIN then cnt = RAIN_CNT_MIN
    elseif cnt > RAIN_CNT_MAX then cnt = RAIN_CNT_MAX end
    local durMs = durS * 1000

    -- 컬럼 일괄 선정 + 서버 스퀘어 생성 + 클라 브로드캐스트 페이로드 구성
    -- [계측] 시작 틱 스파이크 실측용: 선정/생성 각 단계 소요시간을 분리 측정
    local tPick0 = getTimestampMs()
    local px, py = player:getX(), player:getY()
    local cols, payload = {}, {}
    local missedPick = 0
    for _ = 1, cnt do
        local x, y = pickRainColumn(cell, px, py, r)
        if x then
            cols[#cols + 1]       = { x = x, y = y }
            payload[#payload + 1] = { ["x"] = x, ["y"] = y }
        else
            missedPick = missedPick + 1
        end
    end
    local tPick1 = getTimestampMs()
    if #cols == 0 then
        print("[PongDuRain] session aborted (no columns) player=" .. tostring(player:getUsername()))
        return
    end

    local createdSq, reusedSq = 0, 0
    for _, c in ipairs(cols) do
        for zz = 1, RAIN_DROP_Z do
            if cell:getGridSquare(c.x, c.y, zz) then
                reusedSq = reusedSq + 1
            else
                cell:createNewGridSquare(c.x, c.y, zz, true)
                createdSq = createdSq + 1
            end
        end
    end
    local tSquares1 = getTimestampMs()

    sendServerCommand("PongDuRain", "Prep", { ["cols"] = payload, ["z"] = RAIN_DROP_Z })

    -- 낙하 좀비 플레이어 어그로 창 (클라 features/aggro.lua 수신).
    -- 아래 spawnRainZombie의 서버측 setTarget은 좀비 클라 권한 구조상 소유
    -- 클라 동기화에 덮여 실효가 없다 — 실제 어그로는 이 브로드캐스트를 받은
    -- 각 클라가 자기 소유 좀비에 건다. 좀비가 지속시간 내내 낙하하므로 창은
    -- 준비지연 + 지속시간 + 착지 여유(8초)까지 연다.
    -- v4: 반경 필터 폐지 — zid는 위 flushBatch가 배치마다 AddIds로 공급하므로
    -- 여기선 빈 창만 연다. 주변 기존 좀비는 더 이상 어그로 대상이 아니다.
    sendServerCommand("PongDuAggro", "Window", {
        ["dur"] = PREP_DELAY_MS + durMs + 8000,
        ["pid"] = player:getOnlineID(),
        ["src"] = "rain",
    })

    print("[PongDuRain] prep pickMs=" .. tostring(tPick1 - tPick0)
        .. " squareMs=" .. tostring(tSquares1 - tPick1)
        .. " cols=" .. tostring(#cols) .. " missedPick=" .. tostring(missedPick)
        .. " sqCreated=" .. tostring(createdSq) .. " sqReused=" .. tostring(reusedSq))

    _sessions[#_sessions + 1] = {
        player     = player,
        cols       = cols,
        sprintPct  = pct,
        durMs      = durMs,
        intervalMs = durMs / cnt,
        sender     = sender,
        readyAt   = getTimestampMs() + PREP_DELAY_MS,
        startMs   = nil,
        spawned   = 0,
        hits      = 0,
        batch     = {},
        lastFlush = 0,
    }
    print("[PongDuRain] session start player=" .. tostring(player:getUsername())
        .. " r=" .. tostring(r) .. " sprint%=" .. tostring(pct)
        .. " dur=" .. tostring(durS) .. "s cnt=" .. tostring(cnt)
        .. " cols=" .. tostring(#cols))
end)
