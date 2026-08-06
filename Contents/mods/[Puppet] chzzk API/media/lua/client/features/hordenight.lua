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
--  ③ 인디케이터: 예약이 하나라도 걸려 있거나 스폰이 진행 중이면 바닐라 무들
--     스택에 실제로 슬롯 하나를 끼워넣는다. 무들박스 전체를 한 칸 아래로
--     밀어서 다른 무들들을 밀어내고, 비워진 최상단 슬롯을 차지한다. 배경/
--     툴팁/슬라이드 애니메이션 전부 바닐라 무들과 동일하게 맞춘다.
--     예약이 2건 이상이면 개수를 겹쳐 그린다.
--
-- 스폰/유인 사운드는 전부 서버가 처리한다. 클라가 하는 일은 없다.

-- ── 바닐라 무들 스택에 슬롯 끼워넣기 (MoodlesUI.java / UIManager.java) ──────
-- MoodlesUI는 Java UIElement고 슬롯이 MoodleType enum으로 고정돼 있어서
-- Lua에서 항목을 추가할 수 없다. 대신 이렇게 한다:
--   1) UIManager.getMoodleUI(0) 으로 무들박스 Java 객체를 잡는다
--      (MoodlesUI/UIManager 둘 다 LuaManager.java:1494,1508 에서 노출됨.
--       setX/setY 는 double 인자, getX/getY 는 Double 반환이라 Kahlua 안전)
--   2) 우리 인디케이터가 떠 있는 동안 무들박스 전체를 MoodleDistY(36)만큼
--      아래로 민다 -> 바닐라 무들 전부가 한 칸씩 밀려난다
--   3) 그렇게 비워진 원래 슬롯 0 자리에 우리 아이콘을 놓는다
--      -> 결과적으로 우리가 항상 최상단 무들이 된다
-- 무들끼리의 압축/슬라이드 애니메이션은 MoodlesUI 내부(MoodleSlotsPos)에서
-- 그대로 돌아가므로 건드릴 필요가 없다.
--
-- 주의: UIManager.resize()는 MoodleUI[0]의 X만 screenW-50으로 덮어쓰고,
-- Y는 스플릿스크린(numPlayers>1)이나 인덱스 2/3일 때만 건드린다. 즉 일반
-- 싱글/멀티 클라에서는 우리가 세팅한 Y가 유지된다. X는 하드코딩하지 말고
-- 매번 getX()로 읽는다(위 -50 때문에 무들 폭 상수와 어긋난다).
local MOODLE_DIST_Y = 36    -- MoodlesUI.MoodleDistY (private 필드라 값만 복제)
local SLIDE_LERP    = 0.15  -- MoodlesUI.update()의 슬롯 보간 계수와 동일
local SLIDE_SNAP    = 0.8   -- 같은 함수의 스냅 임계값
local SLIDE_IN_FROM = 500   -- 신규 무들이 아래에서 올라오는 거리(바닐라와 동일)
-- 심각도가 바뀔 때 아이콘이 좌우로 떨리는 연출. 값은 전부 MoodlesUI.java의
-- Oscilator* 필드에서 그대로 복제했다(private이라 읽을 수 없어 값만 옮김).
--   render(): OscilatorStep += OscilatorRate * (ms/33.3) * 0.5
--             xOffset = sin(OscilatorStep) * OscilatorScalar * OscilationLevel
--   update(): OscilationLevel -= OscilationLevel * (1 - OscilatorDecelerator)
--                                 / (lockFPS / 30);  0.01 미만이면 0으로 스냅
local OSC_RATE        = 0.8
local OSC_SCALAR      = 15.6
local OSC_DECELERATOR = 0.96
local OSC_START_LEVEL = 1.0
local IND_SIZE      = 32
local TEX_PATH      = "media/ui/Moodle_HNzombie.png"
-- 바닐라 무들 배경. 호드나이트는 악재라 Bad 계열을 쓰고, 심각도(1~4)는
-- 예약 수에 맞춰 올린다 -- 바닐라가 MoodleLevel로 Bkg_Bad_1..4를 고르는 것과
-- 같은 방식이다(MoodlesUI.render).
local BKG_PATHS = {
    "media/ui/Moodles/Moodle_Bkg_Bad_1.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_2.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_3.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_4.png",
}

-- 바닐라 무들 툴팁 레이아웃 (MoodlesUI.render의 MouseOver 분기 그대로).
-- 아이콘 왼쪽에 검은 반투명 박스를 깔고, 이름(흰색)/설명(회색) 2줄을
-- 우측 정렬로 그린다. 좌표는 전부 슬롯 좌상단 기준.
local TIP_RIGHT   = -10   -- 텍스트 우측 정렬 기준 x
local TIP_BOX_PAD = 6     -- 박스가 텍스트보다 왼쪽으로 더 나가는 양
local TIP_TOP     = 1     -- Java의 MoodleSlotsPos + 1

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

-- ── 인디케이터 패널 ──────────────────────────────────────────────────────────
local HordeIndicator = ISPanel:derive("HordeIndicator")

-- 위치는 생성 시점에 정하지 않는다. 무들박스(MoodlesUI) 좌표를 매 틱 읽어서
-- syncMoodleStack()이 갱신한다.
function HordeIndicator:new()
    local o = ISPanel:new(0, 0, IND_SIZE, IND_SIZE)
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

-- 배경 심각도. 진행 중이면 최대(4), 아니면 예약 수를 1~4로 클램프.
local function bkgLevel()
    if _active then return 4 end
    local n = _pending
    if n < 1 then n = 1 end
    if n > 4 then n = 4 end
    return n
end

-- ── 심각도 변화 진동 (바닐라 MoodlesUI의 Oscilator 이식) ────────────────────
-- 바닐라는 MoodleLevel이 바뀔 때 wiggle()로 OscilationLevel을 1.0으로 올리고,
-- 매 프레임 감쇠시키면서 sin 파형만큼 아이콘을 좌우로 흔든다. 여기서도 배경
-- 심각도(bkgLevel)가 바뀌는 순간을 그 트리거로 삼는다.
local _oscLevel = 0
local _oscStep  = 0
local _lastLevel = nil

local function updateOscillation()
    local lvl = bkgLevel()
    if _lastLevel ~= nil and lvl ~= _lastLevel then
        _oscLevel = OSC_START_LEVEL
    end
    _lastLevel = lvl

    if _oscLevel <= 0 then return end
    -- 감쇠는 바닐라 update()와 동일하게 프레임레이트로 정규화한다.
    local fps = PerformanceSettings.getLockFPS() / 30.0
    if fps <= 0 then fps = 1 end
    _oscLevel = _oscLevel - _oscLevel * (1.0 - OSC_DECELERATOR) / fps
    if _oscLevel < 0.01 then _oscLevel = 0 end
end

-- 현재 프레임의 X 흔들림 오프셋. 바닐라와 동일하게 렌더 시점의 경과 ms로
-- 위상을 진행시킨다(고정 틱이 아니라 실제 렌더 간격 기준).
local function oscOffset()
    if _oscLevel <= 0 then return 0 end
    _oscStep = _oscStep + OSC_RATE * (UIManager.getMillisSinceLastRender() / 33.3) * 0.5
    return math.sin(_oscStep) * OSC_SCALAR * _oscLevel
end

function HordeIndicator:render()
    -- 바닐라와 동일하게 흔들림은 요소 위치가 아니라 "그리는 좌표"에만 먹인다
    -- (MoodlesUI.render의 float1과 같은 역할). 툴팁은 흔들지 않는다.
    local ox = oscOffset()
    -- 배경 -> 아이콘 순으로 겹쳐 그린다(MoodlesUI.render).
    local bkg = self.bkg and self.bkg[bkgLevel()]
    if bkg then
        self:drawTextureScaledAspect(bkg, ox, 0, IND_SIZE, IND_SIZE, 1, 1, 1, 1)
    end
    if self.tex then
        self:drawTextureScaledAspect(self.tex, ox, 0, IND_SIZE, IND_SIZE, 1, 1, 1, 1)
    end
    -- 예약이 2건 이상이면 우하단에 개수 표시 (큐박스 스택 카운트와 같은 기법).
    -- 배경 심각도는 4에서 포화되므로 그 이상은 이 숫자로만 구분된다.
    if _pending > 1 then
        local col = colorMap.get("horde_night")
        textOutline.draw(self, "x" .. tostring(_pending),
            ox + IND_SIZE - 12, IND_SIZE - 14, col[1], col[2], col[3], 1, UIFont.Small)
    end

    -- 호버 툴팁: 바닐라 무들 툴팁과 동일한 형태/좌표(MoodlesUI.render).
    -- isMouseOver()는 UIElement의 순수 좌표 판정(UIElement.java:1833)이라
    -- 마우스 이벤트 등록이 필요 없다.
    if self:isMouseOver() then
        local desc = tooltipDesc()
        if desc then
            local title = tooltipTitle()
            local lineH = getTextManager():getFontHeight(UIFont.Small)
            local w = getTextManager():MeasureStringX(UIFont.Small, title)
            local w2 = getTextManager():MeasureStringX(UIFont.Small, desc)
            if w2 > w then w = w2 end
            -- 박스: 텍스트 우측 기준선(-10)에서 왼쪽으로 폭 + 여백만큼.
            self:drawRect(TIP_RIGHT - w - TIP_BOX_PAD, TIP_TOP - 2,
                w + 12, (2 + lineH) * 2, 0.6, 0.0, 0.0, 0.0)
            self:drawTextRight(title, TIP_RIGHT, TIP_TOP,
                1.0, 1.0, 1.0, 1.0, UIFont.Small)
            self:drawTextRight(desc, TIP_RIGHT, TIP_TOP + lineH,
                0.8, 0.8, 0.8, 1.0, UIFont.Small)
        end
    end
end

-- ── 무들 스택 동기화 ────────────────────────────────────────────────────────
-- _shift   : 무들박스에 현재 우리가 넣고 있는 밀림량. 목표는 인디케이터가
--            떠 있으면 MOODLE_DIST_Y, 아니면 0. 바닐라와 같은 계수로 보간해서
--            다른 무들들이 스르륵 밀려나고 스르륵 돌아오게 한다. 절대 좌표를
--            기억하지 않고 "가산 오프셋"으로만 다루는 게 핵심 -- 무들박스를
--            같이 건드리는 다른 모드와 싸우지 않기 위해서다(syncMoodleStack 참조).
-- _ownSlide: 우리 아이콘이 등장할 때 아래에서 올라오는 오프셋. 바닐라 신규
--            무들이 desired+500 에서 시작하는 것과 같은 연출.
local _shift    = 0
local _ownSlide = 0

-- 스플릿스크린은 대상 아님 -- 항상 인덱스 0. UIManager가 아직 초기화되기
-- 전이거나 배열이 비어 있을 수 있어 pcall로 감싼다. 매 틱 호출되므로
-- 클로저를 새로 만들지 않도록 함수를 밖으로 뺀다.
local function fetchMoodleUI()
    return UIManager.getMoodleUI(0)
end

local function moodleUI()
    local ok, ui = pcall(fetchMoodleUI)
    if ok and ui then return ui end
    return nil
end

-- 바닐라 MoodlesUI.update()의 슬롯 보간과 동일: 차이가 임계값보다 크면
-- 비율 보간, 아니면 스냅.
local function approach(cur, target)
    local d = target - cur
    if d < 0 then d = -d end
    if d > SLIDE_SNAP then
        return cur + (target - cur) * SLIDE_LERP
    end
    return target
end

local function syncMoodleStack()
    updateOscillation()

    local mui = moodleUI()
    if not mui then return end

    -- 무들박스의 절대 Y를 한 번 캐시해두면, 박스를 함께 건드리는 다른 모드가
    -- 있을 때 우리가 그 모드의 이동을 매 틱 되돌려버린다(서로 싸움).
    -- 그래서 캐시하지 않고, 매 틱 "현재 Y에서 우리가 지난 틱에 넣은 밀림량을
    -- 뺀 값"을 기준으로 다시 잡는다. 이러면 우리는 남이 정한 Y 위에 얹히는
    -- 순수 가산 오프셋이 되고, 다른 모드가 박스를 어디로 옮기든 그대로 따라간다.
    local base = mui:getY() - _shift

    local want = (_panel ~= nil) and MOODLE_DIST_Y or 0
    _shift = approach(_shift, want)
    mui:setY(base + _shift)

    if _panel then
        _ownSlide = approach(_ownSlide, 0)
        -- X는 UIManager.resize()가 screenW-50으로 덮어쓰므로 매번 읽어온다.
        _panel:setX(mui:getX())
        _panel:setY(base + _ownSlide)
        -- 무들박스가 숨겨져 있으면(VisibleAllUI off) 우리도 같이 숨는다.
        _panel:setVisible(mui:isVisible() == true)
    end
end

-- 우리가 넣은 밀림량만 즉시 빼서 무들박스를 남에게 온전히 돌려준다.
-- 절대 좌표를 복원하는 게 아니라 우리 기여분만 반납하는 것이라, 그 사이
-- 다른 모드가 박스를 옮겨놨어도 그 위치를 망가뜨리지 않는다.
local function restoreMoodleStack()
    local mui = moodleUI()
    if mui and _shift ~= 0 then
        mui:setY(mui:getY() - _shift)
    end
    _shift = 0
end

Events.OnResolutionChange.Add(restoreMoodleStack)

local function refreshIndicator()
    local want = indicatorEnabled() and (_pending > 0 or _active)
    if want then
        if not _panel then
            _panel = HordeIndicator:new()
            _panel:addToUIManager()
            -- 바닐라 신규 무들과 동일하게 아래에서 슬라이드해 올라온다.
            _ownSlide = SLIDE_IN_FROM
        end
        _panel:setVisible(true)
    elseif _panel then
        _panel:setVisible(false)
        _panel:removeFromUIManager()
        _panel = nil
    end
    -- 패널 유무가 바뀌면 밀림 목표도 바뀌므로 곧바로 한 번 돌려준다.
    syncMoodleStack()
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
    -- 한다(사라진 뒤 다른 무들들이 스르륵 올라오는 구간).
    syncMoodleStack()

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
