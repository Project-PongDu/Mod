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
--     상시 표시. 기본 위치/크기/텍스처는 원본 모드(HordeNightIndicator.lua,
--     Moodle_HNzombie.png) 그대로 이식. 예약이 2건 이상이면 개수를 겹쳐 그린다.
--     드래그로 위치 이동 가능(DonationReceiver.lua 큐박스와 동일 UX), 이동한
--     좌표는 HordeIndicatorUI.ini에 영속화된다.
--
-- 스폰/유인 사운드는 전부 서버가 처리한다. 클라가 하는 일은 없다.

-- 원본 무들 기본 위치/크기/텍스처는 그대로다(HordeNightIndicator.lua:
-- screenW-210, 12, 32, 32, Moodle_HNzombie.png). 다만 원본과 달리 이 위치는
-- 드래그로 옮길 수 있고(아래 uiSettings), 옮긴 적 없을 때만 이 기본값을 쓴다.
-- 텍스처 원본 해상도가 도네 큐박스용 horde_night.png(1024x1024)와 다를 수
-- 있어 ISUIElement:drawTextureScaledAspect로 종횡비 유지한 채 IND_SIZE에
-- 맞춰 그린다.
local IND_RIGHT_PAD = 210
local IND_TOP       = 44
local IND_SIZE      = 32
local TEX_PATH      = "media/ui/Moodle_HNzombie.png"

-- 호버 툴팁 레이아웃. 인디케이터가 화면 최상단이라 툴팁은 아래로 깐다.
-- 오른쪽 끝을 아이콘 오른쪽 끝에 맞춰 왼쪽으로 늘린다(화면 밖 잘림 방지).
local TIP_PAD_X   = 7
local TIP_PAD_Y   = 3
local TIP_LINE_H  = 16
local TIP_GAP     = 4

local SYNC_DELAY_TICKS = 300   -- 접속 직후 서버 상태 요청까지 대기 (~5초)

-- ── 인디케이터 위치 (드래그로 이동 가능) ────────────────────────────────────
-- DonationReceiver.lua의 uiSettings/saveUISettings 패턴과 동일. anchorX/anchorY
-- 가 nil이면 기본 위치(screenW - IND_RIGHT_PAD, IND_TOP)를 계속 따라간다.
-- 드래그로 한 번이라도 옮기면 그 좌표가 고정되고 파일로 영속화된다.
local uiSettings = { anchorX = nil, anchorY = nil }

local function saveUISettings()
    local w = getFileWriter("HordeIndicatorUI.ini", true, false)
    if not w then return end
    if uiSettings.anchorX ~= nil then
        w:write("anchorX=" .. tostring(uiSettings.anchorX) .. "\n")
        w:write("anchorY=" .. tostring(uiSettings.anchorY) .. "\n")
    end
    w:close()
end

local function loadUISettings()
    if not fileExists("HordeIndicatorUI.ini") then return end
    local r = getFileReader("HordeIndicatorUI.ini", true)
    if not r then return end
    local line = r:readLine()
    while line do
        local k, v = line:match("^(%w+)=(.+)$")
        if k == "anchorX" then uiSettings.anchorX = tonumber(v) end
        if k == "anchorY" then uiSettings.anchorY = tonumber(v) end
        line = r:readLine()
    end
    r:close()
end

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
-- 스폰 루프가 끝나는 인게임 시각(getWorldAgeHours 기준). 서버가 Fire/State로
-- 잔여 인게임 분을 주면 거기에 현재 게임시각을 더해 보관한다. 서버 시계와
-- 클라 시계를 비교하지 않고 "받은 시점 + 잔여"만 쓰므로 시계 오차 영향이 없다.
-- 현실 ms 가 아니라 게임 시간을 쓰는 이유는 서버 스폰 루프와 같다 -- 배속
-- (FastForward 류)이 걸렸을 때 스폰과 카운트다운이 함께 빨라져야 하기 때문.
local _activeEndHours = nil
-- 클램프용 상한(인게임 분). 클라의 NightsSurvived 는 SyncClock 패킷으로만
-- 갱신되므로(GameClient.java:1563), 7시 경계를 넘는 순간 다음 패킷이 오기 전까지
-- getWorldAgeHours() 가 24시간 뒤로 튈 수 있다. 잔여값을 [0, 총길이]로 조여서
-- 그 찰나에 툴팁이 엉뚱한 숫자를 보이지 않게 한다.
local _activeTotalMin = 0

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

-- 툴팁 줄 구성. 한 줄만 보여준다 -- 진행 중인 이벤트가 최우선, 없으면 다음 예약.
-- (스택 예약이 여러 건이어도 "다음 1건까지 남은 시간"만 표시한다. 각 스택별
-- 개별 시각까지 보여주려면 별도 요청 시 확장.)
local function tooltipLines()
    if _active and _activeEndHours then
        local remain = (_activeEndHours - getGameTime():getWorldAgeHours()) * 60
        if remain < 0 then remain = 0 end
        if remain > _activeTotalMin then remain = _activeTotalMin end
        return { getText("IGUI_donation_horde_night_tip_end", fmtGameMinutes(remain)) }
    end
    if _pending > 0 then
        return { getText("IGUI_donation_horde_night_tip_start",
            fmtGameMinutes(gameMinutesUntilHour(SandboxVars.PongDu.Horde_Hour))) }
    end
    return {}
end

local function indicatorEnabled()
    return SandboxVars.PongDu.Horde_ShowIndicator
end

-- ── 인디케이터 패널 ──────────────────────────────────────────────────────────
local HordeIndicator = ISPanel:derive("HordeIndicator")

function HordeIndicator:new()
    local x = uiSettings.anchorX or (getCore():getScreenWidth() - IND_RIGHT_PAD)
    local y = uiSettings.anchorY or IND_TOP
    local o = ISPanel:new(x, y, IND_SIZE, IND_SIZE)
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
    -- 드래그 중엔 안 띄운다 (옮기는 도중 툴팁이 같이 따라다니면 거슬림).
    if self:isMouseOver() and not self.dragging then
        local lines = tooltipLines()
        if #lines > 0 then
            -- 테두리/글자는 흰색 고정 (효과색 틴트 안 함)
            local br = {1.0, 1.0, 1.0}
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

-- 드래그: DonationReceiver.lua의 DonationEntryPanel과 동일 패턴. 놓을 때
-- anchorX/anchorY로 영속화.
function HordeIndicator:onMouseDown(x, y)
    if not self:getIsVisible() then return end
    self.dragging = true
    self:bringToTop()
    return true
end

function HordeIndicator:onMouseMove(dx, dy)
    if not self.dragging then return end
    uiSettings.anchorX = self:getX() + dx
    uiSettings.anchorY = self:getY() + dy
    self:setX(uiSettings.anchorX)
    self:setY(uiSettings.anchorY)
end

HordeIndicator.onMouseMoveOutside = HordeIndicator.onMouseMove

function HordeIndicator:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        saveUISettings()
    end
end

HordeIndicator.onMouseUpOutside = HordeIndicator.onMouseUp

-- 드래그로 옮긴 적 없을 때(anchorX == nil)만 해상도 변화에 맞춰 기본 위치를
-- 다시 잡는다. 커스텀 위치가 있으면 화면 크기가 바뀌어도 그대로 둔다
-- (DonationReceiver.lua의 anchor 취급과 동일).
local function relayout()
    if _panel and uiSettings.anchorX == nil then
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
        local remain = tonumber(args and args["remainMin"]) or 0
        if _active then
            if remain > 0 then
                _activeEndHours = getGameTime():getWorldAgeHours() + remain / 60
                if remain > _activeTotalMin then _activeTotalMin = remain end
            end
        else
            _activeEndHours = nil
            _activeTotalMin = 0
        end
        print("[PongDuHorde] state pending=" .. tostring(_pending)
            .. " active=" .. tostring(_active)
            .. " remainGameMin=" .. tostring(remain))
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
        -- 서버가 준 스폰 루프 총 길이(인게임 분)로 종료 예정시각을 잡는다. State
        -- 브로드캐스트보다 이쪽이 먼저 도착할 수 있어 여기서도 세팅한다.
        local dur = tonumber(args and args["durMin"]) or 0
        _active = true
        if dur > 0 then
            _activeEndHours = getGameTime():getWorldAgeHours() + dur / 60
            _activeTotalMin = dur
        end
        refreshIndicator()
        print("[PongDuHorde] horde night fired countPerPlayer="
            .. tostring(args and args["cnt"])
            .. " durGameMin=" .. tostring(dur))
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
        _activeEndHours = nil
        _activeTotalMin = 0
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
Events.OnGameStart.Add(loadUISettings)

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
