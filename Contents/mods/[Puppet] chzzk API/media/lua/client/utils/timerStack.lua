require("ISUI/ISPanel")

-- 봄바드/화력지원(헬기·드론)/좀비레인 등 화면 하단-중앙에 뜨는 카운트다운
-- 패널들을, 도네 큐박스 호버 툴팁과 겹치지 않게 쌓아주는 공용 매니저.
--
-- 규칙:
--   1) 바닥선 = 큐박스 툴팁 상단에서 3px 위. 큐박스가 비어있으면(패널 없음)
--      화면 하단 기준 폴백값 사용.
--   2) 먼저 register()된 패널일수록 바닥선에 가깝게(맨 아래) 깔린다.
--   3) 중간 패널이 끝나서 unregister()되면, 그 위에 있던 패널들이 순서를
--      당겨받아 한 칸씩 내려온다(빈 자리 없이 재정렬).
local _a = {}

local ROW_HEIGHT   = 34   -- 슬롯 높이(패널 30) + 슬롯 간 여백(4)
local TOOLTIP_GAP  = 3    -- 큐박스 툴팁과의 최소 간격
local FALLBACK_PAD = 210  -- DonationReceiver 미로드 등 극단적 상황에서만 쓰이는 안전망.
                           -- 큐박스 기본 앵커(핫바 바로 위) 위치를 대략 근사한 값.

local stack = {}   -- 순서대로: stack[1] = 가장 먼저 register()된 패널(=최하단)

local function baseY()
    local ok, receiver = pcall(require, "DonationReceiver")
    local top = ok and receiver and receiver.getTooltipTopY and receiver.getTooltipTopY()
    if top then
        return top - TOOLTIP_GAP
    end
    -- 큐박스가 비어있거나 아직 로드되지 않음 -> 화면 하단 기준 폴백.
    return getCore():getScreenHeight() - FALLBACK_PAD
end

local function relayout()
    local y0 = baseY()
    for i, entry in ipairs(stack) do
        entry.panel:setY(y0 - i * ROW_HEIGHT)
    end
end

-- panel: ISPanel 인스턴스. 호출 순서대로 최하단부터 쌓인다.
function _a.register(panel)
    table.insert(stack, { panel = panel })
    relayout()
end

-- 타이머가 끝나 패널을 없앨 때 removeFromUIManager() 전에 반드시 호출할 것.
-- (그래야 위에 쌓여있던 패널들이 빈 자리를 채우며 내려온다)
function _a.unregister(panel)
    for i = #stack, 1, -1 do
        if stack[i].panel == panel then
            table.remove(stack, i)
            break
        end
    end
    relayout()
end

Events.OnResolutionChange.Add(relayout)

return _a
