-- ── 블러드문 (blood_moon) 서버 ───────────────────────────────────────────────
--
-- 서버가 하는 일은 두 가지다: ① 언제 시작해서 언제 끝나는가, ② 핏빛 조명.
-- 화면 틴트와 좀비 스프린터화는 각 클라가 로컬로 수행한다
-- (client/features/bloodmoon.lua).
--
-- ── 조명은 왜 서버인가 (좀비와 정반대) ──
-- ClimateColor.calculate() (ClimateManager.java:2762):
--     if (isAdminOverride && !GameClient.bClient) finalValue = adminValue;
--     else { if (isModded && modInterpolate>0) internalValue.interp(moddedValue,...);
--            if (isOverride && interpolate>0)   internalValue.interp(override,...,finalValue);
--            else finalValue = internalValue; }
-- MP 클라이언트는 서버가 보낸 finalValue 를 override 로 받아(1845줄) 그쪽으로
-- lerp 하므로, 클라가 로컬에서 무엇을 설정하든 다음 기후 패킷에 씻겨나간다.
-- 어드민 기후 패널이 먹히는 것도 클라가 transmitClientChangeAdminVars() 로
-- 값을 서버에 보내고, 서버가 계산한 finalValue 가 전원에게 브로드캐스트되기
-- 때문이다(1701줄). 즉 월드 조명은 서버 단독 권위다.
--
-- ── 왜 override 채널인가 ──
--   colNightMoon/NoMoon : nightStrength 로 블렌딩돼 낮에는 효과가 0 이다
--   modded              : internalValue 에 파괴적으로 누적되고, MP 클라에선
--                         서버 패킷이 덮어써서 무의미하다
--   admin               : finalValue 를 통째로 교체해 자연광이 사라지고,
--                         어드민 기후 패널과 정면 충돌한다
--   override            : finalValue = lerp(자연광, 지정색, interpolate).
--                         낮/밤 명암을 유지한 채 붉어진다. resetOverrides() 는
--                         public API 일 뿐 엔진 내부 호출처가 0 건이고(1077줄),
--                         interpolate 를 건드리는 코드도 전부 GameClient.bClient
--                         가드 안이라(825/948줄) 서버에서는 우리 값이 유지된다.
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

-- ═══════════════════════════════════════════════════════════════════════════
--  핏빛 조명 (globalLight override)
-- ═══════════════════════════════════════════════════════════════════════════
local COLOR_GLOBAL_LIGHT = 0   -- ClimateManager.COLOR_GLOBAL_LIGHT (133줄)

-- 네 번째 성분은 RGB 가 아니라 블렌드 강도다(ClimateColorInfo 클래스 주석).
-- 실내는 창문 마스크 경로로 따로 칠해지므로 실외보다 약하게 잡는다.
local BLOOD_EXT = { 0.85, 0.05, 0.06, 0.60 }
local BLOOD_INT = { 0.55, 0.05, 0.07, 0.45 }

local LIGHT_FADE_TICKS = 180   -- 시작/종료 페이드 (약 3초)

local _lightT    = 0     -- 현재 override interpolate (0 = 자연광, 1 = 지정색)
local _lightWant = 0     -- 목표치 (0 또는 1)
local _lightMode = nil   -- "override" | "admin" | nil -- 폴백 확정 후 고정

local function lightScale()
    return SandboxVars.PongDu.BloodMoon_LightStrength / 100
end

-- interpolate 를 세팅할 public setter 가 setOverride(ClimateColorInfo, float)
-- 하나뿐인데 setOverride(ByteBuffer, float) 오버로드가 있어서 Kahlua 의
-- 인자 타입 해석이 어긋날 여지가 있다. 실패하면 어드민 채널로 내려간다 --
-- 그쪽은 바닐라 기후 패널이 실제로 쓰는 경로라 동작이 보장된다.
local function setLight(t)
    local cm = getClimateManager()
    if not cm then return end
    local cc = cm:getClimateColor(COLOR_GLOBAL_LIGHT)
    if not cc then return end

    if t <= 0 then
        pcall(function() cc:setEnableOverride(false) end)
        pcall(function() cc:setEnableAdmin(false) end)
        return
    end

    if _lightMode ~= "admin" then
        -- getOverride() 는 라이브 객체라 새로 만들 필요가 없다.
        -- setOverride 내부의 override.setTo(자기자신) 은 무해하고, 그 뒤에
        -- interpolate 세팅 + isOverride=true 가 목적이다.
        local ok = pcall(function()
            local ov = cc:getOverride()
            ov:setExterior(BLOOD_EXT[1], BLOOD_EXT[2], BLOOD_EXT[3], BLOOD_EXT[4])
            ov:setInterior(BLOOD_INT[1], BLOOD_INT[2], BLOOD_INT[3], BLOOD_INT[4])
            cc:setOverride(ov, t)
        end)
        if ok then
            if _lightMode ~= "override" then
                _lightMode = "override"
                blog("light channel = override (blends with natural light)")
            end
            return
        end
        _lightMode = "admin"
        blog("WARNING: override channel unavailable, falling back to admin channel"
            .. " -- natural day/night contrast will be lost during the event")
    end

    -- 어드민 폴백. finalValue 를 통째로 교체하므로 자연광 블렌드가 없다.
    -- 최소한 페이드는 남기려고 t 를 색 알파에 싣는다.
    cc:setAdminValueExterior(BLOOD_EXT[1], BLOOD_EXT[2], BLOOD_EXT[3], BLOOD_EXT[4] * t)
    cc:setAdminValueInterior(BLOOD_INT[1], BLOOD_INT[2], BLOOD_INT[3], BLOOD_INT[4] * t)
    cc:setEnableAdmin(true)
end

-- 조명 페이드. 서버가 매 틱 갱신하고, 결과 finalValue 가 정기 기후 패킷으로
-- 전원에게 나간다. 패킷 간격이 있어 계단처럼 보일 수 있지만 클라가 패킷 사이를
-- networkLerp 로 보간하므로(825줄) 실제로는 매끄럽다.
local function lightTick()
    if not isAuthority() then return end
    local target = _lightWant * lightScale()
    if _lightT == target then return end

    local step = 1 / LIGHT_FADE_TICKS
    if _lightT < target then
        _lightT = math.min(target, _lightT + step)
    else
        _lightT = math.max(target, _lightT - step)
    end
    setLight(_lightT)
end
Events.OnTick.Add(lightTick)

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

    _lightWant = 1

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
-- 유실돼도 조명이 영구히 남지는 않는다 -- 여기는 정상 경로다.
local function checkExpiry()
    if not isAuthority() then return end
    local endHours = getState()
    if endHours <= 0 then return end
    if gameHours() < endHours then return end

    setState(0, 0)
    _lightWant = 0
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
            _lightWant = 1
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
