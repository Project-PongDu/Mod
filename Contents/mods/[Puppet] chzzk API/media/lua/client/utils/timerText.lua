-- ═══════════════════════════════════════════════════════════════════════════
--  남은시간 카운터 공통 렌더 (공용 leaf 모듈)
--
--  화면 하단 중앙에 뜨는 카운트다운 패널(폭격/저격·공중·드론 지원/좀비 공습)의
--  텍스트를 한 곳에서 그린다. 예전엔 패널마다 각자 getText(...) .. " " .. 시간
--  을 조립하고 있어서, 번역키에 "남은 시간:" 이 붙은 것(화력지원 3종·폭격)과
--  기능 이름만 있는 것(좀비 공습)이 섞여 표기가 제각각이었다.
--
--  통일 형식:  <기능명>(Large)  <남은시간 MM:SS>(Medium)
--    · 기능명 = 각 패널이 넘기는 번역 문자열. 이름만 들어 있어야 한다
--      (번역키에 "남은 시간:" 을 다시 넣지 말 것 -- 여기서 붙인다).
--    · "남은시간" 은 IGUI_donation_timer_remain 하나로 공유한다.
--
--  두 덩어리를 폰트를 달리해 그리므로 drawTextCentre 로는 안 되고, 각각의 폭을
--  MeasureStringX 로 재서 합계 기준으로 좌표를 잡는다(바닐라 ISLabel 과 같은
--  방식). 세로는 큰 쪽 폰트 높이(MeasureFont) 기준으로 작은 쪽을 가운데 맞춘다.
--
--  ※ 이 파일은 의존성이 textOutline 하나뿐이어야 한다. colorMap/textOutline 과
--    같은 이유로 leaf 로 둔다 -- 기능 파일을 require 하면 순환 require 로 nil 이
--    잡히는 사고가 재발한다.
-- ═══════════════════════════════════════════════════════════════════════════
local textOutline = require("utils/textOutline")

local NAME_FONT = UIFont.Large    -- 기능명
local TIME_FONT = UIFont.Medium   -- "남은시간 MM:SS"
local GAP_PX    = 8               -- 기능명과 남은시간 사이 간격

local _a = {}

-- 패널 규격. 모든 카운터 패널이 이 값을 쓴다(폭이 제각각이면 중앙 정렬이
-- 패널마다 미세하게 어긋난다). Large 로 커진 만큼 예전 240 에서 넉넉히 잡았다 --
-- noBackground 라 남는 폭은 화면에 아무 영향이 없다.
_a.PANEL_W = 420
_a.PANEL_H = 32

-- 초 -> "MM:SS". 음수는 00:00 으로 접는다.
function _a.mmss(totalSec)
    local s = tonumber(totalSec) or 0
    if s < 0 then s = 0 end
    return string.format("%02d:%02d", math.floor(s / 60), s % 60)
end

-- panel  : ISPanel 인스턴스 (self)
-- name   : 기능 표시명 (이미 getText 를 거친 문자열)
-- totalSec: 남은 시간(초)
-- col    : colorMap.get(...) 이 돌려준 {r,g,b}
function _a.draw(panel, name, totalSec, col)
    local tm   = getTextManager()
    local tail = getText("IGUI_donation_timer_remain") .. " " .. _a.mmss(totalSec)

    local wName = tm:MeasureStringX(NAME_FONT, name)
    local wTail = tm:MeasureStringX(TIME_FONT, tail)
    local x     = (panel.width - (wName + GAP_PX + wTail)) / 2

    -- 작은 쪽을 큰 쪽 높이의 가운데에 맞춰 baseline 어긋남을 없앤다.
    local yTail = (tm:MeasureFont(NAME_FONT) - tm:MeasureFont(TIME_FONT)) / 2
    if yTail < 0 then yTail = 0 end

    textOutline.draw(panel, name, x, 0, col[1], col[2], col[3], 1, NAME_FONT)
    textOutline.draw(panel, tail, x + wName + GAP_PX, yTail,
        col[1], col[2], col[3], 1, TIME_FONT)
end

return _a
