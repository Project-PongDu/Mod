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
-- 발동당 최대 (총 마리수) x DROP_Z개. 실험 월드에서 세이브 크기/부하 실측 후
-- 본 규모(500) 확장 여부를 결정한다.

-- 지속시간/종류별 마리수는 샌드박스(Rain_Duration/Rain_Count_<종류>)를 클라가
-- Start에 실어 보내고, 여기 값들은 파라미터 누락(구버전 클라) 시 폴백 + 클램프
-- 한계로 쓴다.
local RAIN_DUR_DEFAULT_S = 30                               -- 지속시간 폴백 (초)
local RAIN_DUR_MIN_S     = 5
local RAIN_DUR_MAX_S     = 120
local RAIN_CNT_MAX       = 500                              -- 전 종류 합계 상한 (스퀘어 생성 부하)

-- 낙하 종류. "normal" 외에는 특좀 파이프라인(PuppetMutant kind)과 같은 이름이다
-- (sprinter = server.lua spawnZombies 뛰좀, 나머지 = features/mutantspawn.lua KINDS).
-- 순서는 로그 출력 순서일 뿐, 실제 낙하 순서는 셔플된다.
local RAIN_KINDS = { "normal", "sprinter", "screamer", "brute", "roach", "tracer" }
local RAIN_DROP_Z        = 4                                -- 낙하 시작 높이 (4층)
local RAIN_MIN_DIST      = 3                                -- 플레이어 직격 방지 최소 거리
local SPAWN_CAP_PER_TICK = 5                                -- 랙 스파이크 후 몰아치기 상한
local BATCH_MS           = 500                              -- RainMark 브로드캐스트 묶음 주기
local PICK_TRIES         = 20                               -- 컬럼 후보 탐색 시도 횟수
local PREP_DELAY_MS      = 1000                             -- 클라 스퀘어 생성 대기 (클라 zombierain.lua SERVER_PREP_MS 와 동일값 유지)

-- ── 투하 모드 (Rain_AirdropMode) ──
-- 수송기가 플레이어 근처를 직선으로 한 번 지나가며 경로 양옆 띠 안에 떨어뜨린다.
-- 경로 구간 [-r, +r]를 지속시간 동안 등속으로 통과하고, 각 컬럼은 비행기가 그
-- 지점을 지나는 시각에 스폰된다. 그림자 연출은 클라(zombierain.lua)가 같은 비행
-- 정보(Flight)로 그린다.
local AIR_BAND_RATIO     = 0.35                             -- 띠 반폭 = 반경 x 비율
local AIR_BAND_MIN       = 4                                -- 띠 반폭 최소 (타일)
local AIR_PASS_OFFSET    = 0.5                              -- 경로가 플레이어에서 비켜나는 최대 거리 (띠 반폭 대비)

local _sessions = {}

-- 건물 없는 야외 지상(z=0) 컬럼 선정.
--  ① sq:isOutside()            : 실외
--  ② sq:getBuilding() == nil   : 맵 건물 스퀘어 제외 (지붕 착지 방지)
--  ③ 물 스퀘어 제외             : 강/호수 수장 방지
--  ④ 위층(z=1..DROP_Z) 바닥 없음: 플레이어 건축물 지붕/2층 바닥 방지.
--     스퀘어가 존재해도 바닥이 없으면 통과 (이전 레인이 만든 빈 스퀘어 재사용)
local function isRainColumn(cell, x, y)
    local sq = cell:getGridSquare(x, y, 0)
    if not sq or not sq:isOutside() or sq:getBuilding() ~= nil
        or sq:Is(IsoFlagType.water) then
        return false
    end
    for zz = 1, RAIN_DROP_Z do
        local up = cell:getGridSquare(x, y, zz)
        if up and up:getFloor() ~= nil then return false end
    end
    return true
end

local function pickRainColumn(cell, px, py, radius)
    for _ = 1, PICK_TRIES do
        local angle = ZombRand(628) / 100.0
        -- sqrt 분포 -> 원판 내 균등 (반경 비례 편중 방지)
        local dist  = RAIN_MIN_DIST
            + math.sqrt(ZombRand(10000) / 10000.0) * (radius - RAIN_MIN_DIST)
        local x  = math.floor(px + math.cos(angle) * dist)
        local y  = math.floor(py + math.sin(angle) * dist)
        if isRainColumn(cell, x, y) then return x, y end
    end
    return nil
end

-- 투하 모드 컬럼: 경로 위치 s가 [sLo, sHi) 구간, 경로에서 옆으로 ±halfW 안.
-- 시도 절반을 넘기면 띠를 2배로 넓혀 다시 찾는다 (도심/물가 대비).
-- 반환 s는 스폰 시각 계산용 (비행기가 s를 지나는 순간 떨어진다).
local function pickAirdropColumn(cell, px, py, f, sLo, sHi, halfW)
    for try = 1, PICK_TRIES do
        local w = halfW
        if try > PICK_TRIES / 2 then w = halfW * 2 end
        local s   = sLo + (ZombRand(10000) / 10000.0) * (sHi - sLo)
        local off = (ZombRand(20001) / 10000.0 - 1.0) * w
        local x = math.floor(f.cx + f.ux * s - f.uy * off)
        local y = math.floor(f.cy + f.uy * s + f.ux * off)
        local dx, dy = x + 0.5 - px, y + 0.5 - py
        if dx * dx + dy * dy >= RAIN_MIN_DIST * RAIN_MIN_DIST
            and isRainColumn(cell, x, y) then
            return x, y, s
        end
    end
    return nil
end

-- 종류별 마리수 -> 셔플된 종류 목록. 지속시간 동안 종류가 고르게 섞여 떨어지게
-- 한다 (셔플 없이 이어붙이면 특좀이 마지막에 몰린다). 합계가 상한을 넘으면
-- 셔플 후 앞에서부터 잘라 설정 비율을 대략 유지한다.
local function buildKindList(kinds)
    local list = {}
    for _, k in ipairs(RAIN_KINDS) do
        local n = math.floor(tonumber(kinds and kinds[k]) or 0)
        if n < 0 then n = 0 elseif n > RAIN_CNT_MAX then n = RAIN_CNT_MAX end
        for _ = 1, n do list[#list + 1] = k end
    end
    local requested = #list
    -- Fisher-Yates
    for i = #list, 2, -1 do
        local j = ZombRand(i) + 1
        list[i], list[j] = list[j], list[i]
    end
    if #list > RAIN_CNT_MAX then
        for i = #list, RAIN_CNT_MAX + 1, -1 do list[i] = nil end
    end
    return list, requested
end

-- 1마리 스폰: z=DROP_Z 스퀘어에 직접 생성. 랜덤 아웃핏(outfit=nil),
-- 체력 캡처 후 세션 배치에 적재. 특좀 종류는 서버 modData에 마킹만 하고
-- 스탯/행동 적용은 RainMark를 받은 클라가 특좀 적용기(mutantspawn)에 넘겨
-- 처리한다 (B41 MP 좀비는 클라 권한).
local function spawnRainZombie(session, col, kind)
    local zeds = addZombiesInOutfit(col.x, col.y, RAIN_DROP_Z, 1, nil, nil)
    if not zeds or zeds:size() == 0 then return false end
    local zed = zeds:get(0)
    zed:DoZombieStats()
    -- 후원받은 플레이어 쪽으로 어그로
    local p = session.player
    pcall(function() zed:setTarget(p) end)
    pcall(function() zed:setTurnAlertedValues(math.floor(p:getX()), math.floor(p:getY())) end)
    -- 서버측 특좀 마킹: 이게 있어야 시체(IsoDeadBody)에 계승되어 강령술
    -- (RiseUp)이 b:getModData()["PuppetMutant"]를 읽고 같은 종류로 부활시킨다.
    -- PuppetMutantZid 스탬프 필수 -- 없으면 staleSweep이 풀 재활용으로 오인해 즉시 지운다.
    local mutant = kind ~= nil and kind ~= "normal"
    if mutant then
        local md = zed:getModData()
        md["PuppetMutant"]    = kind
        md["PuppetMutantZid"] = zed:getOnlineID()
        if session.sender and session.sender ~= "" then
            md["PuppetMutantSender"] = session.sender
        end
    end
    session.batch[#session.batch + 1] = {
        ["id"] = zed:getOnlineID(),
        ["h"]  = zed:getHealth(),   -- 착지 후 원복할 낙하 전 체력 (일반좀비 폴백용)
        ["k"]  = mutant and kind or nil,
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
            -- 컬럼별 스폰 시각(t)이 지난 만큼 스폰 (틱당 상한으로 폭주 방지).
            -- 일반 모드는 t = i x 간격(균등), 투하 모드는 비행기 통과 시각.
            local n = 0
            while s.spawned + n < #s.cols and s.cols[s.spawned + n + 1].t <= elapsed do
                n = n + 1
            end
            if n > SPAWN_CAP_PER_TICK then n = SPAWN_CAP_PER_TICK end
            for _ = 1, n do
                s.spawned = s.spawned + 1
                local ok, res = pcall(spawnRainZombie, s, s.cols[s.spawned], s.kinds[s.spawned])
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
    local durS   = tonumber(data and data["dur"]) or RAIN_DUR_DEFAULT_S
    local sender = tostring(data and data["sender"] or "")
    local air    = data and data["air"] == true
    if r < 10 then r = 10 elseif r > 100 then r = 100 end
    if durS < RAIN_DUR_MIN_S then durS = RAIN_DUR_MIN_S
    elseif durS > RAIN_DUR_MAX_S then durS = RAIN_DUR_MAX_S end
    local durMs = durS * 1000

    local kinds  = type(data and data["kinds"]) == "table" and data["kinds"] or nil
    local kindList, requested = buildKindList(kinds)
    local cntLog = ""
    for _, k in ipairs(RAIN_KINDS) do
        cntLog = cntLog .. " " .. k .. "=" .. tostring(kinds and kinds[k] or 0)
    end
    print("[PongDuRain] request" .. cntLog .. " total=" .. tostring(requested)
        .. " used=" .. tostring(#kindList))
    if not kinds then
        print("[PongDuRain] WARN no kinds table in Start (client/server version mismatch?)")
    end
    if #kindList == 0 then
        print("[PongDuRain] session aborted (total count 0) player=" .. tostring(player:getUsername()))
        return
    end
    local cnt = #kindList

    -- 컬럼 일괄 선정 + 서버 스퀘어 생성 + 클라 브로드캐스트 페이로드 구성
    -- [계측] 시작 틱 스파이크 실측용: 선정/생성 각 단계 소요시간을 분리 측정
    local tPick0 = getTimestampMs()
    local px, py = player:getX(), player:getY()
    local cols, payload = {}, {}
    local missedPick = 0
    local flight = nil
    if air then
        -- 비행 경로: 방향 무작위 직선, 플레이어 옆으로 살짝 비켜 지나간다.
        local halfW = math.max(AIR_BAND_MIN, r * AIR_BAND_RATIO)
        local ang   = ZombRand(628) / 100.0
        local ux, uy = math.cos(ang), math.sin(ang)
        local pass  = (ZombRand(20001) / 10000.0 - 1.0) * halfW * AIR_PASS_OFFSET
        flight = {
            cx = px - uy * pass, cy = py + ux * pass,
            ux = ux, uy = uy, halfW = halfW,
        }
        -- 층화 추출: 경로 [-r, r]를 cnt 칸으로 나눠 칸마다 1마리. s가 이미 오름차순이라
        -- 정렬 없이 스폰 시각이 단조 증가한다 (투하가 경로를 따라 순서대로 진행).
        local span = 2 * r
        for i = 1, cnt do
            local sLo = -r + span * (i - 1) / cnt
            local sHi = -r + span * i / cnt
            local x, y, sv = pickAirdropColumn(cell, px, py, flight, sLo, sHi, halfW)
            if x then
                cols[#cols + 1]       = { x = x, y = y, t = (sv + r) / span * durMs }
                payload[#payload + 1] = { ["x"] = x, ["y"] = y }
            else
                missedPick = missedPick + 1
            end
        end
    else
        for _ = 1, cnt do
            local x, y = pickRainColumn(cell, px, py, r)
            if x then
                cols[#cols + 1]       = { x = x, y = y }
                payload[#payload + 1] = { ["x"] = x, ["y"] = y }
            else
                missedPick = missedPick + 1
            end
        end
        -- 균등 간격. 간격은 요청 마리수(cnt)가 아니라 실제 확보된 컬럼 수 기준 --
        -- cnt 기준이면 missedPick 발생 시 지속시간보다 일찍 끝난다.
        if #cols > 0 then
            local intervalMs = durMs / #cols
            for i = 1, #cols do cols[i].t = i * intervalMs end
        end
    end
    local tPick1 = getTimestampMs()
    if #cols == 0 then
        print("[PongDuRain] session aborted (no columns) player=" .. tostring(player:getUsername()))
        return
    end
    -- 컬럼이 모자라면 종류 목록도 같은 길이로 자른다 (이미 셔플돼 있어 무작위 탈락)
    for i = #kindList, #cols + 1, -1 do kindList[i] = nil end

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

    -- 투하 모드: 그림자 연출용 비행 정보. 비행기는 PREP_DELAY_MS 뒤에 경로 -r 지점을
    -- 지나 durMs 동안 +r까지 등속 비행한다 (서버 첫 스폰 시각과 같은 기준).
    if flight then
        sendServerCommand("PongDuRain", "Flight", {
            ["cx"] = flight.cx, ["cy"] = flight.cy,
            ["ux"] = flight.ux, ["uy"] = flight.uy,
            ["r"] = r, ["prep"] = PREP_DELAY_MS, ["dur"] = durMs,
        })
        print(string.format("[PongDuRain] airdrop flight c=(%.1f,%.1f) dir=(%.2f,%.2f) halfW=%.1f speed=%.2f tiles/s",
            flight.cx, flight.cy, flight.ux, flight.uy, flight.halfW, 2 * r / durS))
    end

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
        kinds      = kindList,   -- cols[i] 에 떨어질 종류
        durMs      = durMs,
        sender     = sender,
        readyAt   = getTimestampMs() + PREP_DELAY_MS,
        startMs   = nil,
        spawned   = 0,
        hits      = 0,
        batch     = {},
        lastFlush = 0,
    }
    print("[PongDuRain] session start player=" .. tostring(player:getUsername())
        .. " mode=" .. (air and "airdrop" or "rain") .. " r=" .. tostring(r)
        .. " dur=" .. tostring(durS) .. "s cnt=" .. tostring(cnt)
        .. " cols=" .. tostring(#cols) .. " intervalMs=" .. tostring(math.floor(durMs / #cols)))
end)
