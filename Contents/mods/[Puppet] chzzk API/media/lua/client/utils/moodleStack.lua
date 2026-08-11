-- ═══════════════════════════════════════════════════════════════════════════
--  바닐라 무들 스택 위에 퐁듀 인디케이터 슬롯을 끼워넣는 공용 매니저
--
--  MoodlesUI 는 Java UIElement 고 슬롯이 MoodleType enum 으로 고정돼 있어서
--  Lua 에서 항목을 추가할 수 없다. 대신 이렇게 한다:
--    1) UIManager.getMoodleUI(0) 으로 무들박스 Java 객체를 잡는다
--       (MoodlesUI/UIManager 둘 다 LuaManager.java:1494,1508 에서 노출됨.
--        setX/setY 는 double 인자, getX/getY 는 Double 반환이라 Kahlua 안전)
--    2) 등록된 인디케이터 수 x MoodleDistY(36) 만큼 무들박스 전체를 아래로
--       민다 -> 바닐라 무들 전부가 그만큼 밀려난다
--    3) 그렇게 비워진 위쪽 슬롯들을 우선순위 순으로 나눠 갖는다
--       -> 결과적으로 퐁듀 인디케이터가 항상 바닐라 무들보다 위에 온다
--  무들끼리의 압축/슬라이드 애니메이션은 MoodlesUI 내부(MoodleSlotsPos)에서
--  그대로 돌아가므로 건드릴 필요가 없다.
--
--  ── 왜 각 feature 가 직접 하지 않고 여기로 모았나 ──
--  원래 이 로직은 hordenight.lua 안에 사유 코드로 있었다. 그 구현은 밀림량은
--  정상 누적되지만 아이콘 좌표가 항상 base 고정이라, 인디케이터가 둘 이상이면
--  전부 같은 자리에 겹쳐 그려진다(슬롯 인덱스 개념 자체가 없음). 블러드문이
--  두 번째 소비처가 되면서 슬롯 배정을 이 모듈로 옮겼다.
--
--  ── 절대 좌표를 캐시하지 않는다 ──
--  무들박스의 절대 Y 를 기억해두면, 박스를 함께 건드리는 다른 모드가 있을 때
--  우리가 그 모드의 이동을 매 틱 되돌려버린다(서로 싸움). 그래서 매 틱
--  "현재 Y 에서 우리가 지난 틱에 넣은 밀림량을 뺀 값"을 기준으로 다시 잡는다.
--  이러면 우리는 남이 정한 Y 위에 얹히는 순수 가산 오프셋이 되고, 다른 모드가
--  박스를 어디로 옮기든 그대로 따라간다.
--
--  ※ 이 파일은 의존성이 없어야 한다(require 금지). colorMap/textOutline 과
--    같은 이유로 leaf 로 둔다 -- features/* 가 서로를 require 하면 순환이 된다.
-- ═══════════════════════════════════════════════════════════════════════════

local _a = {}

local MOODLE_DIST_Y = 36    -- MoodlesUI.MoodleDistY (private 필드라 값만 복제)
local SLIDE_LERP    = 0.15  -- MoodlesUI.update() 의 슬롯 보간 계수와 동일
local SLIDE_SNAP    = 0.8   -- 같은 함수의 스냅 임계값
local SLIDE_IN_FROM = 500   -- 신규 무들이 아래에서 올라오는 거리(바닐라와 동일)

_a.DIST_Y = MOODLE_DIST_Y

-- 등록 엔트리: { panel, priority, offset }
--   priority : 작을수록 위(화면 상단). 같은 값이면 등록 순서.
--   offset   : 슬롯 기준선으로부터의 현재 Y 오프셋. 목표는 (슬롯인덱스 * 36).
--              등장 시 목표 + SLIDE_IN_FROM 에서 시작해 보간으로 올라온다.
local _slots = {}
local _shift = 0   -- 무들박스에 현재 우리가 넣고 있는 총 밀림량

-- 스플릿스크린은 대상 아님 -- 항상 인덱스 0. UIManager 가 아직 초기화되기
-- 전이거나 배열이 비어 있을 수 있어 pcall 로 감싼다. 매 틱 호출되므로
-- 클로저를 새로 만들지 않도록 함수를 밖으로 뺀다.
local function fetchMoodleUI()
    return UIManager.getMoodleUI(0)
end

local function moodleUI()
    local ok, ui = pcall(fetchMoodleUI)
    if ok and ui then return ui end
    return nil
end

-- 바닐라 MoodlesUI.update() 의 슬롯 보간과 동일: 차이가 임계값보다 크면
-- 비율 보간, 아니면 스냅.
local function approach(cur, target)
    local d = target - cur
    if d < 0 then d = -d end
    if d > SLIDE_SNAP then
        return cur + (target - cur) * SLIDE_LERP
    end
    return target
end

-- priority 오름차순 정렬. Kahlua 에 table.sort 는 있지만(stdlib.lua 구현)
-- 원소가 2~3개뿐이라 삽입 정렬이 더 싸고, 동일 priority 의 등록 순서도
-- 안정적으로 보존된다.
local function insertSorted(entry)
    local i = #_slots + 1
    while i > 1 and _slots[i - 1].priority > entry.priority do
        _slots[i] = _slots[i - 1]
        i = i - 1
    end
    _slots[i] = entry
end

-- panel   : ISPanel 인스턴스. addToUIManager() 는 호출부에서 미리 해둘 것.
--           panel:iconSize() 를 구현해두면 매 틱 그 크기로 히트박스를 맞춘다.
-- priority: 작을수록 화면 위쪽. 퐁듀 배정은 features/ 각 파일 상단 참조.
function _a.register(panel, priority)
    if not panel then return end
    for i = 1, #_slots do
        if _slots[i].panel == panel then return end
    end
    insertSorted({ panel = panel, priority = priority or 100, offset = nil })
end

function _a.unregister(panel)
    for i = #_slots, 1, -1 do
        if _slots[i].panel == panel then
            table.remove(_slots, i)
            break
        end
    end
end

-- 매 틱 호출. 등록된 패널이 없어도 계속 불러야 한다 -- 마지막 인디케이터가
-- 사라진 뒤 다른 무들들이 스르륵 제자리로 올라오는 구간이 여기서 돈다.
function _a.sync()
    local mui = moodleUI()
    if not mui then return end

    local base = mui:getY() - _shift

    _shift = approach(_shift, #_slots * MOODLE_DIST_Y)
    mui:setY(base + _shift)

    local x       = mui:getX()   -- UIManager.resize() 가 screenW-50 으로 덮어쓰므로 매번 읽는다
    local visible = (mui:isVisible() == true)

    for i = 1, #_slots do
        local e      = _slots[i]
        local panel  = e.panel
        local target = (i - 1) * MOODLE_DIST_Y

        if e.offset == nil then
            -- 바닐라 신규 무들과 동일하게 아래에서 슬라이드해 올라온다.
            e.offset = target + SLIDE_IN_FROM
        else
            -- 위 슬롯이 비면 목표가 바뀌므로, 등장 애니메이션과 슬롯 이동을
            -- 같은 보간 하나로 처리한다.
            e.offset = approach(e.offset, target)
        end

        -- 히트박스(마우스오버 판정)도 텍스처 크기를 따라가야 툴팁이 정확히
        -- 아이콘 위에서만 뜬다. 텍스처팩 모드로 크기가 바뀌어도 자동 추종.
        if panel.iconSize then
            local w, h = panel:iconSize()
            if panel:getWidth() ~= w then panel:setWidth(w) end
            if panel:getHeight() ~= h then panel:setHeight(h) end
        end
        panel:setX(x)
        panel:setY(base + e.offset)
        -- 무들박스가 숨겨져 있으면(VisibleAllUI off) 우리도 같이 숨는다.
        panel:setVisible(visible)
    end
end

-- 우리가 넣은 밀림량만 즉시 빼서 무들박스를 남에게 온전히 돌려준다.
-- 절대 좌표를 복원하는 게 아니라 우리 기여분만 반납하는 것이라, 그 사이
-- 다른 모드가 박스를 옮겨놨어도 그 위치를 망가뜨리지 않는다.
local function restore()
    local mui = moodleUI()
    if mui and _shift ~= 0 then
        mui:setY(mui:getY() - _shift)
    end
    _shift = 0
end

Events.OnResolutionChange.Add(restore)

-- ── 바닐라 무들 배경/진동 상수 (소비처 공용) ────────────────────────────────
-- 심각도가 바뀔 때 아이콘이 좌우로 떨리는 연출. 값은 전부 MoodlesUI.java 의
-- Oscilator* 필드에서 그대로 복제했다(private 이라 읽을 수 없어 값만 옮김).
--   render(): OscilatorStep += OscilatorRate * (ms/33.3) * 0.5
--             xOffset = sin(OscilatorStep) * OscilatorScalar * OscilationLevel
--   update(): OscilationLevel -= OscilationLevel * (1 - OscilatorDecelerator)
--                                 / (lockFPS / 30);  0.01 미만이면 0으로 스냅
local OSC_RATE        = 0.8
local OSC_SCALAR      = 15.6
local OSC_DECELERATOR = 0.96

-- 심각도 진동 상태 하나를 만든다. 인디케이터마다 독립 인스턴스를 갖는다.
--   :update(level) -- 매 틱. level 이 직전과 다르면 진동을 다시 튕긴다.
--   :offset()      -- 렌더 시점. 이번 프레임의 X 흔들림 픽셀.
function _a.newOscillator()
    local o = { level = 0, step = 0, last = nil }

    function o:update(lvl)
        if self.last ~= nil and lvl ~= self.last then
            self.level = 1.0
        end
        self.last = lvl
        if self.level <= 0 then return end
        -- 감쇠는 바닐라 update() 와 동일하게 프레임레이트로 정규화한다.
        local fps = PerformanceSettings.getLockFPS() / 30.0
        if fps <= 0 then fps = 1 end
        self.level = self.level - self.level * (1.0 - OSC_DECELERATOR) / fps
        if self.level < 0.01 then self.level = 0 end
    end

    function o:offset()
        if self.level <= 0 then return 0 end
        -- 바닐라와 동일하게 렌더 시점의 경과 ms 로 위상을 진행시킨다
        -- (고정 틱이 아니라 실제 렌더 간격 기준).
        self.step = self.step + OSC_RATE * (UIManager.getMillisSinceLastRender() / 33.3) * 0.5
        return math.sin(self.step) * OSC_SCALAR * self.level
    end

    return o
end

-- 바닐라 무들 배경. 악재 계열은 Bad, 심각도 1~4.
-- (MoodlesUI.render 가 MoodleLevel 로 Bkg_Bad_1..4 를 고르는 것과 같은 방식)
_a.BKG_BAD = {
    "media/ui/Moodles/Moodle_Bkg_Bad_1.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_2.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_3.png",
    "media/ui/Moodles/Moodle_Bkg_Bad_4.png",
}

-- 바닐라 무들 툴팁 레이아웃 (MoodlesUI.render 의 MouseOver 분기 그대로).
-- 아이콘 왼쪽에 검은 반투명 박스를 깔고, 이름(흰색)/설명(회색) 2줄을
-- 우측 정렬로 그린다. 좌표는 전부 슬롯 좌상단 기준.
local TIP_RIGHT   = -10   -- 텍스트 우측 정렬 기준 x
local TIP_BOX_PAD = 6     -- 박스가 텍스트보다 왼쪽으로 더 나가는 양
local TIP_TOP     = 1     -- Java 의 MoodleSlotsPos + 1

function _a.drawTooltip(panel, title, desc)
    if not desc then return end
    local lineH = getTextManager():getFontHeight(UIFont.Small)
    local w  = getTextManager():MeasureStringX(UIFont.Small, title)
    local w2 = getTextManager():MeasureStringX(UIFont.Small, desc)
    if w2 > w then w = w2 end
    panel:drawRect(TIP_RIGHT - w - TIP_BOX_PAD, TIP_TOP - 2,
        w + 12, (2 + lineH) * 2, 0.6, 0.0, 0.0, 0.0)
    panel:drawTextRight(title, TIP_RIGHT, TIP_TOP,
        1.0, 1.0, 1.0, 1.0, UIFont.Small)
    panel:drawTextRight(desc, TIP_RIGHT, TIP_TOP + lineH,
        0.8, 0.8, 0.8, 1.0, UIFont.Small)
end

return _a
