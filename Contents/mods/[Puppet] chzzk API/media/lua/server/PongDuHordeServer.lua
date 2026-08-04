-- ── 호드 나이트 (horde_night) 서버 ────────────────────────────────────────────
-- 원본 "Horde Night"(WindFly) 모드의 인게임 스펙만 이식하고, 발동 트리거는
-- 날짜/시간 주기가 아니라 후원 예약으로 대체한 버전.
--
-- 예약 모델 (상태 = 정수 하나):
--   후원 1건 = 예약 1건. EveryHours에서 시각이 Horde_Hour(기본 22시)일 때
--   pending 이 남아있으면 1건 소모하고 발동한다. 이 한 줄짜리 규칙만으로
--   요구사항이 전부 성립한다:
--     * 22시 전 후원  -> 그날 22시 발동 (EveryHours가 아직 22시에 안 들어옴)
--     * 22시 지나서 후원 -> 다음날 22시 (그날 22시 진입은 이미 지나감)
--     * 중복 후원     -> 하루 1건씩 소모되어 다음날, 그 다음날로 밀린다
--   pending 은 ModData에 얹어 서버 재시작을 넘긴다.
--
-- 발동 대상: 접속자 전원. 각자 자기 주변에 독립 세션이 열린다 (원본 MP 동작과
-- 동일 — 원본은 각 클라가 자기 getPlayer()로 돌렸고, 여기선 서버가 일괄로 돈다).
--
-- [규칙 예외] 이 기능은 퐁듀의 "addSound() 금지(어그로 0 유지)" 원칙에서
-- 명시적으로 제외된다. 원본 호드 나이트의 실질 메커니즘이 스폰 마리수가 아니라
-- 유인 사운드이기 때문이다. B41 소스 기준:
--   * WorldSoundManager.addSound(6인자)는 doSend=true -> 서버 호출 시
--     GameServer.sendWorldSound 로 반경 relevant 클라 전원에 전파되고, 각 클라가
--     remote=true 로 로컬 재등록 -> 청크 SoundList 에 올라가 좀비 AI(클라 권한)가
--     반응한다. 좀비 조작과 달리 서버 -> 클라 전파가 정상 경로다.
--   * 서버 쪽에서만 ZombiePopulationManager.addWorldSound 가 돌고, radius >= 50
--     이면 오프맵 가상좀비 인구를 소리 쪽으로 이주시킨다(반경 200은 충족).
--     즉 스폰 100마리는 씨앗이고, 실제 호드 규모는 이 이주가 만든다.
-- 따라서 어그로 스코프(PongDuAggro/Window)는 쓰지 않는다. 원본대로 사운드가
-- 유일한 유인 수단이다.

-- ── 원본 기본 스펙 (샌드박스로 빼지 않고 고정) ───────────────────────────────
local HORDE_ZED_HEALTH    = 1.5    -- 원본 addZombiesInOutfit 의 health 인자
local HORDE_FEMALE_CHANCE = 50     -- 원본 femaleChance
local HORDE_SOUND_RADIUS  = 200    -- 원본 addSound radius (바닐라 최대 총성이 100)
local HORDE_SOUND_VOLUME  = 10     -- 원본 addSound volume
-- 원본은 "31틱마다 1마리"(HN_TicksBeforeNextZed=30 이 0까지 내려간 뒤 스폰),
-- 60fps 기준 실측 0.517초/마리였다. 지금은 원본 페이스를 그대로 베끼는 대신
-- "인게임 지속시간(Horde_DurationMin) 동안 Horde_Count마리를 균등 스폰"으로
-- 스펙 자체를 바꿨다. 마리당 간격은 세션 시작 시점에 1회 계산한다(계산식은
-- calcSpawnTiming 참조). 그래서 예전처럼 상수로 고정된 SPAWN_INTERVAL_MS는
-- 없다 -- DayLength 세팅에 따라 마리당 실제 ms 간격이 달라져야 하기 때문.
local PICK_TRIES          = 30     -- 원본은 101회. 전원 대상 대량 스폰이라 축소
local SPAWN_CAP_PER_TICK  = 5      -- 랙 스파이크 후 몰아치기 상한 (레인과 동일)
local SESSION_GRACE_MS    = 30000  -- 세션 강제 종료 여유

-- ── 지속시간 -> 마리당 간격 계산 ─────────────────────────────────────────────
-- 인게임 1일(1440분) = 현실 getMinutesPerDay()분(서버 DayLength 설정)이므로,
--   총 현실 ms = durationGameMin x getMinutesPerDay() / 1440 x 60000
--   마리당 ms  = 총 현실 ms / count
-- 세션 시작 시점에 1회만 계산해서 세션에 고정한다(스냅샷). 도중에 DayLength가
-- 바뀌거나 잠자기로 배속이 튀면(최대 200배) 실제 소요 인게임 시간이 이 값에서
-- 벗어날 수 있지만, 그 경우까지 쫓아가는 재계산은 하지 않는다 -- 잠자기 중
-- 스폰이 재조정되는 것보다야 "시작 시점 기준으로 고정"이 예측 가능하다.
local function calcSpawnTiming(durationGameMin, count)
    local mpd = getGameTime():getMinutesPerDay()
    if not mpd or mpd <= 0 then mpd = 60 end  -- 이론상 도달 불가한 방어 하한
    local totalMs    = durationGameMin * mpd / 1440 * 60000
    local intervalMs = totalMs / count
    return totalMs, intervalMs
end

local MD_KEY = "PongDuHordeNight"

local _sessions = {}

local function hlog(msg)
    print("[PongDuHorde] " .. tostring(msg))
end

-- MP 클라이언트에서도 media/lua/server/ 는 로드된다. 서버 권위 로직 전부를
-- 이 가드로 막는다 (isClient() == false 인 싱글플레이는 통과시킨다).
local function isAuthority()
    return not isClient()
end

-- ── 예약 카운터 (ModData 영속) ───────────────────────────────────────────────
local function getPending()
    local reg = ModData.getOrCreate(MD_KEY)
    return tonumber(reg["pending"]) or 0
end

local function setPending(n)
    local reg = ModData.getOrCreate(MD_KEY)
    reg["pending"] = n
    ModData.transmit(MD_KEY)
end

-- 열려있는 세션 중 가장 늦게 끝나는 것의 잔여 ms. 전원이 동시에 시작하므로
-- 사실상 값이 하나뿐이지만, 중간 접속자가 Sync를 던졌을 때 툴팁에 쓸 기준값이
-- 필요해 최대값으로 통일한다.
local function sessionRemainMs()
    local now  = getTimestampMs()
    local best = 0
    for i = 1, #_sessions do
        local s = _sessions[i]
        local r = (s.startMs + s.total * s.intervalMs) - now
        if r > best then best = r end
    end
    return best
end

-- 클라 인디케이터 동기화. active 는 "지금 스폰이 돌고 있는가".
local function broadcastState(active)
    sendServerCommand("PongDuHorde", "State", {
        ["pending"] = getPending(),
        ["active"]  = active and 1 or 0,
        ["remain"]  = sessionRemainMs(),   -- 호버 툴팁 "종료까지" 계산용
    })
end

local function anySessionAlive()
    return #_sessions > 0
end

-- ── 스폰 지점 선정 (원본 기하 유지) ──────────────────────────────────────────
-- 원본은 원형이 아니라 정사각 링 밴드다:
--   두 축 중 하나를 랜덤으로 "먼 축"으로 잡아 dist-10 ~ dist-1 오프셋(부호 랜덤),
--   나머지 축은 -dist ~ dist-1 균등.
-- dist=75 기준 실거리 65 ~ 약 105타일 (코너 방향이 더 멀다).
-- 유효성은 원본 그대로: 스퀘어 존재 + isSafeToSpawn + isOutside + 세이프하우스 아님.
--   isSafeToSpawn 은 IsoGridSquare.java:954 기준 n/s/e/w 이웃 링크로 depth 5
--   플러드필해서 도달 스퀘어가 8개 초과인지 본다 -> 벽으로 막힌 좁은 구석에
--   좀비가 갇히는 것을 걸러준다.
local function pickHordeSpot(cell, px, py, dist)
    for _ = 1, PICK_TRIES do
        local ox, oy
        if ZombRand(2) == 0 then
            ox = ZombRand(10) - 10 + dist
            oy = ZombRand(dist * 2) - dist
            if ZombRand(2) == 0 then ox = -ox end
        else
            oy = ZombRand(10) - 10 + dist
            ox = ZombRand(dist * 2) - dist
            if ZombRand(2) == 0 then oy = -oy end
        end
        local x  = px + ox
        local y  = py + oy
        local sq = cell:getGridSquare(x, y, 0)
        if sq then
            if sq:isSafeToSpawn() and sq:isOutside()
                and SafeHouse.getSafeHouse(sq) == nil then
                return x, y
            end
        end
    end
    return nil
end

-- ── 1마리 스폰 + 유인 사운드 ─────────────────────────────────────────────────
-- 아웃핏은 outfit=nil 로 넘긴다. addZombiesInOutfit 내부에서
-- bDressInRandomOutfit=true 로 떨어져 엔진 랜덤 아웃핏이 되며, 원본이 들고
-- 있던 139종 하드코딩 테이블과 결과가 같다.
-- 후원자 이름표(_cs)는 붙이지 않는다 -- 인당 100마리 x 접속자 수라 화면이 덮인다.
local function spawnHordeZombie(s)
    local cell = getCell()
    if not cell then return false end
    local sq = s.player:getCurrentSquare()
    if not sq then return false end
    local px, py, pz = sq:getX(), sq:getY(), sq:getZ()

    local x, y = pickHordeSpot(cell, px, py, s.dist)
    if not x then
        s.missed = s.missed + 1
        return false
    end

    local zeds = addZombiesInOutfit(x, y, 0, 1, nil, HORDE_FEMALE_CHANCE,
        false, false, false, false, HORDE_ZED_HEALTH)
    if not zeds or zeds:size() == 0 then return false end
    zeds:get(0):DoZombieStats()   -- 체력은 건드리지 않는다(강도/기억/시야만 설정)

    -- 원본과 동일하게 "스폰 1마리당 사운드 1회", 원점은 스폰 지점이 아니라
    -- 플레이어 위치다. 그래서 신규 좀비뿐 아니라 반경 내 기존 좀비까지 끌려온다.
    getWorldSoundManager():addSound(s.player, px, py, pz,
        HORDE_SOUND_RADIUS, HORDE_SOUND_VOLUME)
    return true
end

-- ── 발동 ─────────────────────────────────────────────────────────────────────
local function playerList()
    if isServer() then return getOnlinePlayers() end
    return IsoPlayer.getPlayers()
end

local function startHordeNight()
    local cnt    = SandboxVars.PongDu.Horde_Count
    local dist   = SandboxVars.PongDu.Horde_Distance
    local durMin = SandboxVars.PongDu.Horde_DurationMin
    local totalMs, intervalMs = calcSpawnTiming(durMin, cnt)
    local list = playerList()
    if not list or list:size() == 0 then
        hlog("start aborted: no players online")
        return false
    end

    local now     = getTimestampMs()
    local opened  = 0
    for i = 0, list:size() - 1 do
        local p = list:get(i)
        if p then
            _sessions[#_sessions + 1] = {
                player     = p,
                total      = cnt,
                dist       = dist,
                spawned    = 0,
                hits       = 0,
                missed     = 0,
                startMs    = now,
                intervalMs = intervalMs,
            }
            opened = opened + 1
            -- 시작 연출(대사 + 효과음)은 세션이 실제로 열린 플레이어에게만 보낸다.
            -- 전체 브로드캐스트를 쓰면 세션이 없는 접속자도 대사를 치게 된다.
            -- dur: 스폰 루프 총 길이(ms). 클라 호버 툴팁의 "종료까지" 기준값.
            sendServerCommand(p, "PongDuHorde", "Fire", {
                ["cnt"] = cnt,
                ["dur"] = math.floor(totalMs),
            })
        end
    end
    hlog("START sessions=" .. tostring(opened)
        .. " countPerPlayer=" .. tostring(cnt)
        .. " dist=" .. tostring(dist)
        .. " durationGameMin=" .. tostring(durMin)
        .. " intervalMs=" .. tostring(intervalMs))
    return opened > 0
end

-- ── 매시 정각 체크 ───────────────────────────────────────────────────────────
local function onEveryHours()
    if not isAuthority() then return end
    local hour = getGameTime():getHour()
    if hour ~= SandboxVars.PongDu.Horde_Hour then return end
    local pending = getPending()
    if pending <= 0 then return end
    hlog("hour=" .. tostring(hour) .. " pending=" .. tostring(pending) .. " -> firing")
    setPending(pending - 1)
    if not startHordeNight() then
        -- 접속자가 아무도 없어 발동에 실패하면 예약을 되돌린다.
        setPending(pending)
        hlog("fire failed, reservation restored pending=" .. tostring(pending))
    end
    broadcastState(anySessionAlive())
end
Events.EveryHours.Add(onEveryHours)

-- ── 스폰 루프 ────────────────────────────────────────────────────────────────
local function onTick()
    if #_sessions == 0 then return end
    local now = getTimestampMs()
    for i = #_sessions, 1, -1 do
        local s = _sessions[i]
        local alive = s.player and pcall(function() return s.player:getX() end)
        if not alive then
            hlog("session dropped (player gone) spawned=" .. tostring(s.spawned))
            table.remove(_sessions, i)
        else
            local elapsed = now - s.startMs
            local target  = math.floor(elapsed / s.intervalMs)
            if target > s.total then target = s.total end
            local n = target - s.spawned
            if n > SPAWN_CAP_PER_TICK then n = SPAWN_CAP_PER_TICK end
            for _ = 1, n do
                s.spawned = s.spawned + 1
                local ok, res = pcall(spawnHordeZombie, s)
                if not ok then
                    hlog("spawn error: " .. tostring(res))
                elseif res then
                    s.hits = s.hits + 1
                end
            end
            if s.spawned >= s.total
                or elapsed > s.total * s.intervalMs + SESSION_GRACE_MS then
                hlog("session done player=" .. tostring(s.player:getUsername())
                    .. " spawned=" .. tostring(s.spawned)
                    .. " hits=" .. tostring(s.hits)
                    .. " missedPick=" .. tostring(s.missed))
                -- 종료 연출(대사)도 해당 세션 소유 플레이어에게만. 세션 종료 시점은
                -- 인당 스폰 완료/유예 만료 기준이라 플레이어마다 다를 수 있다.
                sendServerCommand(s.player, "PongDuHorde", "End", {
                    ["spawned"] = s.spawned,
                    ["hits"]    = s.hits,
                })
                table.remove(_sessions, i)
                if #_sessions == 0 then
                    hlog("ALL SESSIONS DONE")
                    broadcastState(false)
                end
            end
        end
    end
end
Events.OnTick.Add(onTick)

-- ── 서버 시작 시 서버장 설정 검증 ────────────────────────────────────────────
-- 17자리 오타나 미설정은 실제로 후원이 들어오기 전까지 드러나지 않는다.
-- 방송 시작 전에 로그로 잡히게 한다.
Events.OnServerStarted.Add(function()
    if not isAuthority() then return end
    PongDuHost.logConfig()
end)

-- ── 클라 커맨드 ──────────────────────────────────────────────────────────────
Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuHorde" then return end
    if not isAuthority() then return end

    if command == "Reserve" then
        -- 서버장 게이트. isAuthority() 는 "이 코드가 서버에서 도는가"만 보지
        -- 누가 보냈는지는 안 본다. 호드나이트는 접속자 전원에게 걸리는 효과라
        -- 서버장에게 들어온 후원만 통과시킨다. 클라 쪽 검사는 전부 우회 가능하므로
        -- 여기가 유일한 강제 지점이다.
        local verdict = PongDuHost.check(player)
        if verdict ~= PongDuHost.OK then
            hlog("RESERVE DENIED user=" .. tostring(player and player:getUsername())
                .. " steamID=" .. tostring(player and player:getSteamID())
                .. " reason=" .. tostring(verdict))
            sendServerCommand(player, "PongDuHost", "Denied", { ["why"] = verdict })
            return
        end

        local n = getPending() + 1
        setPending(n)
        local sender = tostring(data and data["sender"] or "")
        hlog("RESERVE pending=" .. tostring(n)
            .. " hour=" .. tostring(SandboxVars.PongDu.Horde_Hour)
            .. " sender=" .. sender)
        -- 심박음 + 인디케이터 갱신 (전 클라). 1회 알림음이다.
        sendServerCommand("PongDuHorde", "Reserved", {
            ["pending"] = n,
            ["sender"]  = sender,
        })
        broadcastState(anySessionAlive())

    elseif command == "Sync" then
        -- 접속 직후 클라 인디케이터 초기화 요청. 전체 브로드캐스트지만 멱등.
        hlog("SYNC requested pending=" .. tostring(getPending()))
        broadcastState(anySessionAlive())
    end
end)
