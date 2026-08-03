local _a = {}
require("ISUI/ISPanel")
local colorMap    = require("utils/colorMap")
local textOutline = require("utils/textOutline")

-- ── 호드 나이트 (horde_night) 클라이언트 ─────────────────────────────────────
-- 역할 3가지:
--  ① 예약 요청: 후원이 처리되면 서버에 Reserve 를 던진다. 실제 예약 카운터와
--     발동 판정은 전부 서버(server/PongDuHordeServer.lua)에 있다.
--  ② 심박음: 서버 Reserved 브로드캐스트 수신 시 1회 재생. 발동음이 아니라
--     "오늘 밤 온다"는 예고음이라, 발동 시점(22시)이 아니라 후원 시점에 울린다.
--  ③ 인디케이터: 예약이 하나라도 걸려 있거나 스폰이 진행 중이면 화면 우상단에
--     상시 표시. 원본 모드의 무들 아이콘 자리를 그대로 쓰되, 텍스처는 도네
--     큐박스와 같은 horde_night.png 를 쓴다. 예약이 2건 이상이면 개수를 겹쳐 그린다.
--
-- 스폰/유인 사운드는 전부 서버가 처리한다. 클라가 하는 일은 없다.

-- 원본 무들 위치/크기 유지 (HordeNightIndicator.lua: screenW-210, 12, 32, 32).
-- 텍스처 원본은 1024x1024(큐박스 슬롯용)이라 ISUIElement:drawTextureScaled 로
-- 축소해 그린다.
local IND_RIGHT_PAD = 210
local IND_TOP       = 12
local IND_SIZE      = 32
local TEX_PATH      = "media/textures/donation/horde_night.png"

-- 호버 툴팁 레이아웃. 인디케이터가 화면 최상단이라 툴팁은 아래로 깐다.
-- 오른쪽 끝을 아이콘 오른쪽 끝에 맞춰 왼쪽으로 늘린다(화면 밖 잘림 방지).
local TIP_PAD_X   = 7
local TIP_PAD_Y   = 3
local TIP_LINE_H  = 16
local TIP_GAP     = 4

local SYNC_DELAY_TICKS = 300   -- 접속 직후 서버 상태 요청까지 대기 (~5초)

-- ── 발동/종료 연출 ───────────────────────────────────────────────────────────
-- 원본 모드는 HN_StartHordeNight 에서 IGUI_PlayerText_HNWarning00~09 중 1개를
-- Say() 하고 좀비 신음 계열 사운드를 PlaySound + PlayAsMusic(volume 0.1)로
-- 깔았다. 여기서는 대사를 퐁듀 번역 키로 옮기고(원본 원문은 미이식),
-- 사운드는 GameSound alias 하나로 추상화한다.
--   ※ HORDE_START_SOUND 는 아직 t3_rewards_sounds.txt 에 등록돼 있지 않다.
--     GameSounds.getSound() 가 nil 을 반환하면 playSoundImpl 이 0 을 돌려주고
--     조용히 넘어가므로(FMODSoundEmitter.java) 미등록 상태에서도 크래시는
--     없다. 에셋을 넣고 sound 블록만 추가하면 그대로 살아난다.
local HORDE_START_SOUND = "pongdu_horde_start"
local HORDE_START_GAIN  = 0.8
local WARN_LINE_COUNT   = 10   -- IGUI_donation_horde_night_warn1..10
local OVER_LINE_COUNT   = 5    -- IGUI_donation_horde_night_over1..5
local RESERVE_LINE_COUNT = 5   -- IGUI_donation_horde_night_reserve1..5

-- 로컬 플레이어에게 랜덤 대사 1줄. ZombRand(min,max)는 max 미포함이라 +1 한다.
-- Say 는 사망/미생성 타이밍에 걸릴 수 있어 pcall 로 감싼다(firesupport.lua 와 동일).
local function sayRandomLine(prefix, count)
    local p = getPlayer()
    if not p then return end
    local key = "IGUI_donation_horde_night_" .. prefix .. tostring(ZombRand(1, count + 1))
    pcall(function() p:Say(getText(key)) end)
end

local _pending = 0
local _active  = false
local _panel   = nil
local _syncTicks = -1
-- 스폰 루프가 끝나는 클라 로컬 시각(ms). 서버가 Fire/State로 잔여 ms를 주면
-- 거기에 현재 시각을 더해 보관한다. 서버 시계와 클라 시계를 비교하지 않고
-- "받은 시점 + 잔여"만 쓰므로 시계 오차 영향이 없다.
local _activeEndMs = nil

-- ── 인게임 시간 환산 ─────────────────────────────────────────────────────────
-- GameTime.getMinutesPerDay()는 "인게임 하루당 현실 분"(샌드박스 DayLength).
-- GameTime.java:226 getGameWorldSecondsSinceLastUpdate()가 쓰는 환산과 동일하게
--   인게임 분 = 현실 초 x 1440 / (minutesPerDay x 60) = 현실 초 x 24 / minutesPerDay
-- 스폰 루프는 getTimestampMs() 기준 현실시간 고정이라 이 환산이 필요하다.
local function realMsToGameMinutes(ms)
    local mpd = getGameTime():getMinutesPerDay()
    if not mpd or mpd <= 0 then return 0 end
    return (ms / 1000) * 24 / mpd
end

-- 현재 인게임 시각에서 목표 시(hour) 정각까지 남은 인게임 분.
-- getTimeOfDay()는 0~24 실수 시각. 이미 지났으면 다음날로 넘긴다.
local function gameMinutesUntilHour(targetHour)
    local diff = targetHour - getGameTime():getTimeOfDay()
    if diff <= 0 then diff = diff + 24 end
    return diff * 60
end

local function fmtGameMinutes(totalMin)
    local m = math.floor(totalMin + 0.5)
    if m < 1 then m = 1 end
    local h = math.floor(m / 60)
    m = m - h * 60
    if h > 0 then
        return getText("IGUI_donation_horde_night_tip_hm", tostring(h), tostring(m))
    end
    return getText("IGUI_donation_horde_night_tip_m", tostring(m))
end

-- 툴팁 줄 구성. 발동 중이면서 예약도 남아있는 경우 두 줄 다 보여준다.
local function tooltipLines()
    local lines = {}
    if _active and _activeEndMs then
        local remain = _activeEndMs - getTimestampMs()
        if remain < 0 then remain = 0 end
        lines[#lines + 1] = getText("IGUI_donation_horde_night_tip_end",
            fmtGameMinutes(realMsToGameMinutes(remain)))
    end
    if _pending > 0 then
        lines[#lines + 1] = getText("IGUI_donation_horde_night_tip_start",
            fmtGameMinutes(gameMinutesUntilHour(SandboxVars.PongDu.Horde_Hour)))
    end
    return lines
end

local function indicatorEnabled()
    return SandboxVars.PongDu.Horde_ShowIndicator
end

-- ── 인디케이터 패널 ──────────────────────────────────────────────────────────
local HordeIndicator = ISPanel:derive("HordeIndicator")

function HordeIndicator:new()
    local o = ISPanel:new(getCore():getScreenWidth() - IND_RIGHT_PAD, IND_TOP,
        IND_SIZE, IND_SIZE)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    o.tex = getTexture(TEX_PATH)
    return o
end

function HordeIndicator:render()
    if self.tex then
        self:drawTextureScaledAspect(self.tex, 0, 0, IND_SIZE, IND_SIZE, 1, 1, 1, 1)
    end
    -- 예약이 2건 이상이면 우하단에 개수 표시 (큐박스 스택 카운트와 같은 기법)
    if _pending > 1 then
        local col = colorMap.get("horde_night")
        textOutline.draw(self, "x" .. tostring(_pending),
            IND_SIZE - 12, IND_SIZE - 14, col[1], col[2], col[3], 1, UIFont.Small)
    end

    -- 호버 툴팁: 발동까지/종료까지 남은 인게임 시간. isMouseOver()는 UIElement의
    -- 순수 좌표 판정(UIElement.java:1833)이라 마우스 이벤트 등록이 필요 없다.
    if self:isMouseOver() then
        local lines = tooltipLines()
        if #lines > 0 then
            local col = colorMap.get("horde_night")
            -- 테두리/글자는 효과색을 흰쪽으로 밝힌 톤 (큐박스 툴팁과 동일 기법)
            local br = {
                col[1] + (1 - col[1]) * 0.55,
                col[2] + (1 - col[2]) * 0.55,
                col[3] + (1 - col[3]) * 0.55,
            }
            local tw = 0
            for i = 1, #lines do
                local w = getTextManager():MeasureStringX(UIFont.Small, lines[i])
                if w > tw then tw = w end
            end
            local boxW = tw + TIP_PAD_X * 2
            local boxH = #lines * TIP_LINE_H + TIP_PAD_Y * 2
            local tx = IND_SIZE - boxW
            local ty = IND_SIZE + TIP_GAP
            self:drawRect(tx, ty, boxW, boxH, 0.9, 0.05, 0.05, 0.05)
            self:drawRectBorder(tx, ty, boxW, boxH, 0.8, br[1], br[2], br[3])
            for i = 1, #lines do
                self:drawText(lines[i], tx + TIP_PAD_X,
                    ty + TIP_PAD_Y + (i - 1) * TIP_LINE_H,
                    br[1], br[2], br[3], 1, UIFont.Small)
            end
        end
    end
end

local function relayout()
    if _panel then
        _panel:setX(getCore():getScreenWidth() - IND_RIGHT_PAD)
        _panel:setY(IND_TOP)
    end
end
Events.OnResolutionChange.Add(relayout)

local function refreshIndicator()
    local want = indicatorEnabled() and (_pending > 0 or _active)
    if want then
        if not _panel then
            _panel = HordeIndicator:new()
            _panel:addToUIManager()
        end
        _panel:setVisible(true)
    elseif _panel then
        _panel:setVisible(false)
        _panel:removeFromUIManager()
        _panel = nil
    end
end

-- ── 서버 커맨드 수신 ─────────────────────────────────────────────────────────
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuHorde" then return end

    if command == "State" then
        _pending = tonumber(args and args["pending"]) or 0
        _active  = (tonumber(args and args["active"]) or 0) == 1
        -- 중간 접속자/Sync 응답용 잔여 스폰 시간(ms). 세션이 여러 개면 서버가
        -- 최대값을 보낸다 -- 전원 동시 시작이라 사실상 동일하다.
        local remain = tonumber(args and args["remain"]) or 0
        if _active then
            if remain > 0 then _activeEndMs = getTimestampMs() + remain end
        else
            _activeEndMs = nil
        end
        print("[PongDuHorde] state pending=" .. tostring(_pending)
            .. " active=" .. tostring(_active)
            .. " remainMs=" .. tostring(remain))
        refreshIndicator()

    elseif command == "Reserved" then
        -- 심박음 1회 + 대사 1줄. 발동음이 아니라 "오늘 밤 온다"는 예고라서
        -- Fire(_warn)보다 톤을 낮춘 별도 라인셋(_reserve)을 쓴다. 이 브로드캐스트는
        -- 전 클라에 나가므로(broadcastState 와 동일 경로), 접속자 전원이 동시에
        -- 대사를 친다 -- 원래 심박음도 전원에게 들리던 것과 같은 성격이라
        -- 의도된 동작이다.
        sayRandomLine("reserve", RESERVE_LINE_COUNT)
        -- PlaySound 의 maxGain 인자는 SoundManager.java 구현상
        -- 무시되므로 반환 핸들에 setVolume 을 직접 건다.
        local audio = getSoundManager():PlaySound("pongdu_heartbeat", false, 1.0)
        if audio then audio:setVolume(0.7) end
        print("[PongDuHorde] reserved pending=" .. tostring(args and args["pending"])
            .. " sender=" .. tostring(args and args["sender"]))

    elseif command == "Fire" then
        -- 발동 연출. 심박음(Reserved)이 "오늘 밤 온다"는 예고음이라면 이쪽이
        -- 실제 시작 신호다. 서버가 세션이 열린 플레이어에게만 보낸다.
        -- 서버가 준 스폰 루프 총 길이(ms)로 종료 예정시각을 잡는다. State
        -- 브로드캐스트보다 이쪽이 먼저 도착할 수 있어 여기서도 세팅한다.
        local dur = tonumber(args and args["dur"]) or 0
        _active = true
        if dur > 0 then _activeEndMs = getTimestampMs() + dur end
        refreshIndicator()
        print("[PongDuHorde] horde night fired countPerPlayer="
            .. tostring(args and args["cnt"])
            .. " durMs=" .. tostring(dur))
        sayRandomLine("warn", WARN_LINE_COUNT)
        -- PlaySound 의 maxGain 인자는 SoundManager.java 구현상 무시되므로
        -- 반환 핸들에 setVolume 을 직접 건다(Reserved 쪽과 동일한 이유).
        local audio = getSoundManager():PlaySound(HORDE_START_SOUND, false, 1.0)
        if audio then audio:setVolume(HORDE_START_GAIN) end

    elseif command == "End" then
        -- 스폰이 전부 끝난 시점. 좀비가 다 정리됐다는 뜻은 아니라 대사도
        -- "몰려오는 게 멈췄다" 정도의 톤이다.
        -- 이 클라의 세션이 끝났다. active/인디케이터 자체는 전 세션 종료 시점에
        -- 서버 State가 내려 정리하지만, 툴팁이 "0분"으로 굳어 보이지 않도록
        -- 종료 예정시각은 여기서 즉시 지운다.
        _activeEndMs = nil
        print("[PongDuHorde] horde night ended spawned="
            .. tostring(args and args["spawned"])
            .. " hits=" .. tostring(args and args["hits"]))
        sayRandomLine("over", OVER_LINE_COUNT)
    end
end)

-- ── 접속 직후 상태 동기화 ────────────────────────────────────────────────────
-- 예약 카운터는 서버 ModData에 있으므로, 중간 접속자도 인디케이터를 맞춰야 한다.
Events.OnGameStart.Add(function()
    _syncTicks = SYNC_DELAY_TICKS
end)

Events.OnTick.Add(function()
    if _syncTicks < 0 then return end
    _syncTicks = _syncTicks - 1
    if _syncTicks == 0 then
        _syncTicks = -1
        sendClientCommand("PongDuHorde", "Sync", { ["dummy"] = 1 })
    end
end)

-- ── 예약 요청 (rewardManager에서 호출) ───────────────────────────────────────
function _a.a(sender)
    sendClientCommand("PongDuHorde", "Reserve", { ["sender"] = sender or "" })
    print("[PongDuHorde] reserve requested sender=" .. tostring(sender))
end

return _a
