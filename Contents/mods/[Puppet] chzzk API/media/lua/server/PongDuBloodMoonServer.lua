-- ── 블러드문 (blood_moon) 서버 ───────────────────────────────────────────────
--
-- 서버가 하는 일은 하나다: 언제 시작해서 언제 끝나는가.
-- 좀비 스프린터화, 핏빛 조명, 인디케이터는 전부 각 클라가 로컬로 수행한다
-- (client/features/bloodmoon.lua, shared/PongDuBloodMoonLight.lua).
--
-- 조명까지 클라 담당인 이유: 서버에서 globalLight 를 물들이면 그 결과가 기후
-- 패킷에 실려 나가는데, 그 패킷은 10 인게임분에 한 번만 나간다
-- (ClimateManager.java:890, tickIsTenMins 가드). 강도 곡선이 그 해상도로
-- 뭉개져 계단처럼 뚝뚝 오른다. 이벤트 타임라인은 어차피 모든 클라가 Start/
-- End/State 커맨드로 들고 있으므로, 각자 매 틱 계산하는 편이 매끄럽고 종료
-- 복구도 즉시 된다.
--
-- 좀비 변환을 서버가 직접 하지 않는 이유:
-- B41 MP 에서 IsoZombie 의 권위는 소유 클라이언트에 있다. 서버에서
-- makeInactive/DoZombieStats 로 speedType 을 바꿔도 소유 클라가 보내는 sync
-- 패킷에 그대로 덮어써진다. 서버는 "블러드문이다"만 알리고, 판정과 실행은
-- 각 클라가 자기 셀의 좀비에 대해 수행해야 한다.
--
-- 상태는 종료 예정 시각(인게임) 하나로 표현하고 ModData 에 얹어 서버 재시작을
-- 넘긴다. 현실 ms 가 아니라 게임 시간을 쓰는 이유는 지속시간 자체가 인게임
-- 기준이기 때문이다 -- DayLength 설정이나 배속(FastForward 류)이 걸리면 함께
-- 빨라져야 한다. getWorldAgeHours() 는 게임 시계에서 직접 파생되므로 둘 다
-- 자동으로 따라간다 (PongDuHordeServer.lua 의 gameHours 주석 참조).
--
-- 중복 후원은 재시작이 아니라 "연장"이다. 진행 중에 또 들어오면 남은 시간에
-- 지속시간을 더한다. 재시작으로 처리하면 두 번째 후원이 오히려 총 시간을
-- 줄일 수 있어(남은 100분 -> 120분이 아니라 120분으로 리셋) 후원자 입장에서
-- 손해가 되는 구간이 생긴다.

local MD_KEY = "PongDuBloodMoon"

local function blog(msg)
    print("[PongDuBloodMoon] " .. tostring(msg))
end

-- MP 클라이언트에서도 media/lua/server/ 는 로드된다. 서버 권위 로직 전부를
-- 이 가드로 막는다 (isClient() == false 인 싱글플레이는 통과시킨다).
local function isAuthority()
    return not isClient()
end

local function gameHours()
    return getGameTime():getWorldAgeHours()
end

-- ── 영속 상태 ────────────────────────────────────────────────────────────────
-- endHours : 종료 예정 인게임 시각 (nil/0 이면 비활성)
-- totalMin : 이번 이벤트 누적 총 길이 (클라 카운트다운 상한 클램프용)
local function getState()
    local reg = ModData.getOrCreate(MD_KEY)
    return tonumber(reg["endHours"]) or 0, tonumber(reg["totalMin"]) or 0
end

local function setState(endHours, totalMin)
    local reg = ModData.getOrCreate(MD_KEY)
    reg["endHours"] = endHours
    reg["totalMin"] = totalMin
    ModData.transmit(MD_KEY)
end

local function isActive()
    local endHours = getState()
    return endHours > 0 and gameHours() < endHours
end

-- 남은 인게임 분. 비활성이면 0.
local function remainGameMin()
    local endHours = getState()
    if endHours <= 0 then return 0 end
    local r = (endHours - gameHours()) * 60
    if r <= 0 then return 0 end
    return r
end

-- ── 브로드캐스트 ─────────────────────────────────────────────────────────────
local function broadcastStart(sender)
    local _, totalMin = getState()
    sendServerCommand("PongDuBloodMoon", "Start", {
        ["remainMin"] = remainGameMin(),
        ["totalMin"]  = totalMin,
        ["sender"]    = sender or "",
    })
end

local function broadcastEnd()
    sendServerCommand("PongDuBloodMoon", "End", { ["dummy"] = 1 })
end

-- 중간 접속자 동기화용. remainMin 이 0 이면 클라는 정리 쪽으로 분기한다.
local function broadcastState(player)
    local _, totalMin = getState()
    local args = {
        ["remainMin"] = remainGameMin(),
        ["totalMin"]  = totalMin,
        ["sender"]    = "",
    }
    if player then
        sendServerCommand(player, "PongDuBloodMoon", "State", args)
    else
        sendServerCommand("PongDuBloodMoon", "State", args)
    end
end

-- ── 발동 ─────────────────────────────────────────────────────────────────────
local function fire(sender)
    local durMin = SandboxVars.PongDu.BloodMoon_DurationMin
    local wasActive = isActive()

    local endHours, totalMin
    if wasActive then
        -- 연장: 남은 시간에 지속시간을 더한다 (파일 상단 주석 참조).
        local curEnd, curTotal = getState()
        endHours = curEnd + durMin / 60
        totalMin = curTotal + durMin
    else
        endHours = gameHours() + durMin / 60
        totalMin = durMin
    end
    setState(endHours, totalMin)

    blog((wasActive and "EXTEND" or "START")
        .. " durGameMin=" .. tostring(durMin)
        .. " remainGameMin=" .. tostring(remainGameMin())
        .. " totalGameMin=" .. tostring(totalMin)
        .. " sender=" .. tostring(sender))

    broadcastStart(sender)
end

-- ── 종료 감시 ────────────────────────────────────────────────────────────────
-- EveryOneMinute 는 인게임 1분마다 발화하므로 종료 판정 해상도로 충분하고,
-- OnTick 과 달리 전수 루프가 없어 비용이 사실상 0 이다. 클라도 자체 타임아웃
-- 판정을 갖고 있어(client/features/bloodmoon.lua onTick) 이 브로드캐스트가
-- 유실돼도 효과가 영구히 남지는 않는다 -- 여기는 정상 경로다.
local function checkExpiry()
    if not isAuthority() then return end
    local endHours = getState()
    if endHours <= 0 then return end
    if gameHours() < endHours then return end

    setState(0, 0)
    blog("END (duration elapsed)")
    broadcastEnd()
end
Events.EveryOneMinute.Add(checkExpiry)

-- ── 서버 시작 시 ─────────────────────────────────────────────────────────────
-- 서버가 꺼져 있는 동안 게임 시계는 멈추므로, 재시작 시점에 진행 중이던
-- 블러드문은 그대로 남아 있는 게 정상이다. 다만 세이브가 오래 방치돼
-- endHours 가 이미 지난 경우가 있으므로 여기서 한 번 정리한다.
Events.OnServerStarted.Add(function()
    if not isAuthority() then return end
    PongDuHost.logConfig()

    local endHours, totalMin = getState()
    if endHours > 0 then
        if gameHours() >= endHours then
            setState(0, 0)
            blog("stale state cleared on boot (endHours=" .. tostring(endHours) .. ")")
        else
            blog("resumed on boot remainGameMin=" .. tostring(remainGameMin())
                .. " totalGameMin=" .. tostring(totalMin))
        end
    end
end)

-- ── 클라 커맨드 ──────────────────────────────────────────────────────────────
Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuBloodMoon" then return end
    if not isAuthority() then return end

    if command == "Request" then
        -- 서버장 게이트. isAuthority() 는 "이 코드가 서버에서 도는가"만 보지
        -- 누가 보냈는지는 안 본다. 블러드문은 접속자 전원에게 걸리는 효과라
        -- 서버장에게 들어온 후원만 통과시킨다. 클라 쪽 검사는 전부 우회
        -- 가능하므로 여기가 유일한 강제 지점이다 (PongDuHordeServer 와 동일).
        local verdict = PongDuHost.check(player)
        if verdict ~= PongDuHost.OK then
            blog("REQUEST DENIED user=" .. tostring(player and player:getUsername())
                -- Kahlua 는 SteamID64 를 double 로 넘겨 tostring() 하면 지수표기가
                -- 나오므로 %.0f 로 정수 형태를 강제한다.
                .. " steamID=" .. string.format("%.0f", (player and player:getSteamID()) or 0)
                .. " reason=" .. tostring(verdict))
            sendServerCommand(player, "PongDuHost", "Denied", { ["why"] = verdict })
            return
        end

        fire(tostring(data and data["sender"] or ""))

    elseif command == "Sync" then
        -- 접속 직후 상태 요청. 요청한 클라에게만 보낸다 -- 전체 브로드캐스트로
        -- 하면 이미 진행 중인 클라들이 startLocal 을 다시 받아 연장 로그가
        -- 불필요하게 쌓인다(동작 자체는 멱등이지만 로그가 지저분해진다).
        blog("SYNC user=" .. tostring(player and player:getUsername())
            .. " remainGameMin=" .. tostring(remainGameMin()))
        broadcastState(player)
    end
end)
