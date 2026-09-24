-- ═══════════════════════════════════════════════════════════════════════════
--  남은시간 카운터 공통 렌더 (공용 leaf 모듈)
--
--  화면 하단 중앙에 뜨는 카운트다운 패널(폭격/저격·공중·드론 지원/좀비 공습)의
--  텍스트를 한 곳에서 그린다. 예전엔 패널마다 각자 getText(...) .. " " .. 시간
--  을 조립하고 있어서, 번역키에 "남은 시간:" 이 붙은 것(화력지원 3종·폭격)과
--  기능 이름만 있는 것(좀비 공습)이 섞여 표기가 제각각이었다.
--
--  통일 형식 (2줄, 둘 다 패널 가운데 정렬):
--          <기능명>(Large)
--      <남은시간 MM:SS>(Medium)
--    · 기능명 = 각 패널이 넘기는 번역 문자열. 이름만 들어 있어야 한다
--      (번역키에 "남은 시간:" 을 다시 넣지 말 것 -- 여기서 붙인다).
--    · "남은시간" 은 IGUI_donation_timer_remain 하나로 공유한다.
--
--  줄 높이는 getFontHeight(실제 폰트 lineHeight)로 잡는다. MeasureFont 는
--  폰트 크기 옵션과 무관하게 하드코딩 값(Large=24, Medium=20)을 돌려주므로
--  (TextManager.java MeasureFont) 폰트 크기 2x 이상에서 두 줄이 겹친다.
--  getFontHeight 를 파일 로드 시점에 한 번 재는 건 바닐라 ISUI 와 같은 패턴이고,
--  폰트 크기 옵션을 바꾸면 resetLua 로 이 파일도 다시 로드되므로 캐시가 안전하다
--  (MainOptions.lua fontSize apply).
--
--  ※ 이 파일은 의존성이 textOutline 하나뿐이어야 한다. colorMap/textOutline 과
--    같은 이유로 leaf 로 둔다 -- 기능 파일을 require 하면 순환 require 로 nil 이
--    잡히는 사고가 재발한다.
-- ═══════════════════════════════════════════════════════════════════════════
local textOutline = require("utils/textOutline")

local NAME_FONT = UIFont.Large    -- 기능명 (윗줄)
local TIME_FONT = UIFont.Medium   -- "남은시간 MM:SS" (아랫줄)
local LINE_GAP  = 2               -- 두 줄 사이 추가 간격. 아웃라인(2px)끼리 닿지 않게.

local NAME_HGT = getTextManager():getFontHeight(NAME_FONT)
local TIME_HGT = getTextManager():getFontHeight(TIME_FONT)

local _a = {}

-- 패널 규격. 모든 카운터 패널이 이 값을 쓴다(폭이 제각각이면 중앙 정렬이
-- 패널마다 미세하게 어긋난다). noBackground 라 남는 폭은 화면에 아무 영향이
-- 없다. 높이는 두 줄 합계이며, timerStack 이 이 높이 기준으로 패널을 쌓는다.
_a.PANEL_W = 420
_a.PANEL_H = NAME_HGT + LINE_GAP + TIME_HGT

print("[PongDu] timerText: 2-line layout, nameH=" .. tostring(NAME_HGT)
    .. " timeH=" .. tostring(TIME_HGT) .. " panelH=" .. tostring(_a.PANEL_H))

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
    local tail = getText("IGUI_donation_timer_remain") .. " " .. _a.mmss(totalSec)
    local cx   = panel.width / 2

    textOutline.drawCentre(panel, name, cx, 0,
        col[1], col[2], col[3], 1, NAME_FONT)
    textOutline.drawCentre(panel, tail, cx, NAME_HGT + LINE_GAP,
        col[1], col[2], col[3], 1, TIME_FONT)
end

return _a
