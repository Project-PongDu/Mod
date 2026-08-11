local _a = {}
require("ISUI/ISPanel")
local colorMap    = require("utils/colorMap")
local textOutline = require("utils/textOutline")
local moodleStack = require("utils/moodleStack")

-- ── 호드 나이트 (horde_night) 클라이언트 ─────────────────────────────────────
-- 역할 3가지:
--  ① 예약 요청: 후원이 처리되면 서버에 Reserve 를 던진다. 실제 예약 카운터와
--     발동 판정은 전부 서버(server/PongDuHordeServer.lua)에 있다.
--  ② 심박음: 서버 Reserved 브로드캐스트 수신 시 1회 재생. 발동음이 아니라
--     "오늘 밤 온다"는 예고음이라, 발동 시점(22시)이 아니라 후원 시점에 울린다.
--  ③ 인디케이터: 예약이 하나라도 걸려 있거나 스폰이 진행 중이면 바닐라 무들
--     스택에 실제로 슬롯 하나를 끼워넣는다. 무들박스 전체를 한 칸 아래로
--     밀어서 다른 무들들을 밀어내고, 비워진 최상단 슬롯을 차지한다. 배경/
--     툴팁/슬라이드 애니메이션 전부 바닐라 무들과 동일하게 맞춘다.
--     예약이 2건 이상이면 개수를 겹쳐 그린다.
--
-- 스폰/유인 사운드는 전부 서버가 처리한다. 클라가 하는 일은 없다.

-- ── 무들 스택 슬롯 ──────────────────────────────────────────────────────────
-- 무들박스를 밀어내고 그 위 슬롯을 차지하는 로직은 utils/moodleStack 으로
-- 옮겼다(블러드문이 두 번째 소비처가 되면서 슬롯 인덱스 배정이 필요해졌다).
-- 여기서는 슬롯 우선순위와 그리기만 담당한다.
--
-- 퐁듀 인디케이터 우선순위 (작을수록 화면 위):
--   10 = 호드 나이트      20 = 블러드문
local SLOT_PRIORITY = 10
-- 아이콘 크기는 상수로 박지 않는다. 바닐라 MoodlesUI는
-- UIElement.DrawTexture(tex, x, y, alpha)로 그리는데, 이 메서드가
-- tex.getWidth()/getHeight() 즉 "텍스처 네이티브 크기"로 렌더한다
-- (UIElement.java:282). 그래서 B41엔 무들 크기 옵션이 따로 없고(Core.java에
-- getOptionClockSize 같은 대응물이 없음), 크기는 전적으로 텍스처 해상도가
-- 정한다. 텍스처팩 모드가 무들 아트를 교체하면 바닐라가 자동으로 그 크기를
-- 따르므로, 우리도 매 프레임 텍스처에서 크기를 읽어 그대로 맞춘다.
local IND_SIZE_FALLBACK = 32  -- 텍스처 로드 실패 시에만 쓰는 값
local TEX_PATH      = "media/ui/Moodle_HNzombie.png"
-- 배경(Bkg_Bad_1..4)과 툴팁 레이아웃은 moodleStack 이 공용으로 들고 있다.
-- 호드나이트는 악재라 Bad 계열을 쓰고, 심각도(1~4)는 예약 수에 맞춰 올린다 --
-- 바닐라가 MoodleLevel로 Bkg_Bad_1..4를 고르는 것과 같은 방식이다.
local BKG_PATHS = moodleStack.BKG_BAD

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

-- 툴팁 내용. 바닐라 무들과 같은 2줄 구조 -- 1줄은 무들 이름, 2줄은 설명.
-- 설명은 진행 중인 이벤트가 최우선, 없으면 다음 예약까지 남은 시간.
-- (스택 예약이 여러 건이어도 "다음 1건까지 남은 시간"만 표시한다. 각 스택별
-- 개별 시각까지 보여주려면 별도 요청 시 확장.)
local function tooltipTitle()
    return getText("IGUI_donation_horde_night")
end

local function tooltipDesc()
    if _active and _activeEndHours then
        local remain = (_activeEndHours - getGameTime():getWorldAgeHours()) * 60
        if remain < 0 then remain = 0 end
        if remain > _activeTotalMin then remain = _activeTotalMin end
        return getText("IGUI_donation_horde_night_tip_end", fmtGameMinutes(remain))
    end
    if _pending > 0 then
        return getText("IGUI_donation_horde_night_tip_start",
            fmtGameMinutes(gameMinutesUntilHour(SandboxVars.PongDu.Horde_Hour)))
    end
    return nil
end

local function indicatorEnabled()
    return SandboxVars.PongDu.Horde_ShowIndicator
end

-- 배경 심각도. 진행 중이면 최대(4), 아니면 예약 수를 1~4로 클램프.
local function bkgLevel()
    if _active then return 4 end
    local n = _pending
    if n < 1 then n = 1 end
    if n > 4 then n = 4 end
    return n
end

-- ── 인디케이터 패널 ──────────────────────────────────────────────────────────
local HordeIndicator = ISPanel:derive("HordeIndicator")

-- 위치는 생성 시점에 정하지 않는다. 무들박스(MoodlesUI) 좌표를 매 틱 읽어서
-- moodleStack.sync()가 갱신한다.
function HordeIndicator:new()
    local o = ISPanel:new(0, 0, IND_SIZE_FALLBACK, IND_SIZE_FALLBACK)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    o.tex = getTexture(TEX_PATH)
    o.bkg = {}
    for i = 1, #BKG_PATHS do
        o.bkg[i] = getTexture(BKG_PATHS[i])
    end
    return o
end

-- 현재 프레임에 쓸 아이콘 크기. 배경 텍스처 기준으로 잡고(바닐라도 배경과
-- 아이콘을 같은 좌표에 겹쳐 그린다), 없으면 아이콘 텍스처, 그것도 없으면 폴백.
function HordeIndicator:iconSize()
    local t = (self.bkg and self.bkg[bkgLevel()]) or self.tex
    if t then
        local w, h = t:getWidth(), t:getHeight()
        if w and h and w > 0 and h > 0 then return w, h end
    end
    return IND_SIZE_FALLBACK, IND_SIZE_FALLBACK
end

-- ── 심각도 변화 진동 ────────────────────────────────────────────────────────
-- 바닐라는 MoodleLevel이 바뀔 때 wiggle()로 아이콘을 좌우로 흔든다. 여기서도
-- 배경 심각도(bkgLevel)가 바뀌는 순간을 그 트리거로 삼는다. 구현은
-- moodleStack.newOscillator() (바닐라 Oscilator* 상수 이식본).
local _osc = moodleStack.newOscillator()

function HordeIndicator:render()
    -- 바닐라와 동일하게 흔들림은 요소 위치가 아니라 "그리는 좌표"에만 먹인다
    -- (MoodlesUI.render의 float1과 같은 역할). 툴팁은 흔들지 않는다.
    local ox = _osc:offset()
    local w, h = self:iconSize()

    -- drawTexture는 바닐라 MoodlesUI와 같은 UIElement.DrawTexture 경로라
    -- 텍스처 네이티브 크기 + tex.offsetX/Y 보정까지 동일하게 적용된다.
    -- 스케일링(drawTextureScaledAspect)을 쓰면 바닐라 무들과 크기가 어긋난다.
    local bkg = self.bkg and self.bkg[bkgLevel()]
    if bkg then
        self:drawTexture(bkg, ox, 0, 1)
    end
    if self.tex then
        self:drawTexture(self.tex, ox, 0, 1)
    end
    -- 예약이 2건 이상이면 우하단에 개수 표시 (큐박스 스택 카운트와 같은 기법).
    -- 배경 심각도는 4에서 포화되므로 그 이상은 이 숫자로만 구분된다.
    if _pending > 1 then
        local col = colorMap.get("horde_night")
        textOutline.draw(self, "x" .. tostring(_pending),
            ox + w - 12, h - 14, col[1], col[2], col[3], 1, UIFont.Small)
    end

    -- 호버 툴팁: 바닐라 무들 툴팁과 동일한 형태/좌표(MoodlesUI.render).
    -- isMouseOver()는 UIElement의 순수 좌표 판정(UIElement.java:1833)이라
    -- 마우스 이벤트 등록이 필요 없다.
    if self:isMouseOver() then
        moodleStack.drawTooltip(self, tooltipTitle(), tooltipDesc())
    end
end

-- ── 슬롯 등록/해제 ──────────────────────────────────────────────────────────
-- 무들박스 밀어내기, 슬롯 좌표 배정, 등장 슬라이드, 해상도 변경 시 복원은
-- 전부 moodleStack 이 처리한다. 여기는 "언제 뜨고 언제 사라지는가"만 정한다.
local function refreshIndicator()
    local want = indicatorEnabled() and (_pending > 0 or _active)
    if want then
        if not _panel then
            _panel = HordeIndicator:new()
            _panel:addToUIManager()
            moodleStack.register(_panel, SLOT_PRIORITY)
        end
        _panel:setVisible(true)
    elseif _panel then
        moodleStack.unregister(_panel)
        _panel:setVisible(false)
        _panel:removeFromUIManager()
        _panel = nil
    end
    -- 패널 유무가 바뀌면 밀림 목표도 바뀌므로 곧바로 한 번 돌려준다.
    moodleStack.sync()
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

Events.OnTick.Add(function()
    -- 무들박스 밀림/복귀와 우리 아이콘 슬라이드는 패널이 없어도 계속 돌아야
    -- 한다(사라진 뒤 다른 무들들이 스르륵 올라오는 구간). 인디케이터가 여럿일
    -- 때 중복 호출돼도 멱등이다.
    moodleStack.sync()
    _osc:update(bkgLevel())

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
