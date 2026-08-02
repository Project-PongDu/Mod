-- ═══════════════════════════════════════════════════════════════════════════
--  drawText/drawTextCentre 아웃라인 흉내 (공용 leaf 모듈)
--
--  PZ ISUIElement엔 텍스트 아웃라인 인자가 없어서, 8방향 오프셋으로 검정
--  텍스트를 먼저 깔고 그 위에 원래 색 텍스트를 그리는 방식으로 흉내낸다.
--  (DonationReceiver.lua의 스택 카운트(1회, 2회) 표시와 동일한 기법)
--
--  ※ 이 파일은 의존성이 없어야 한다(require 금지). colorMap.lua와 같은 이유로
--    leaf로 둔다 -- DonationReceiver를 require해서 이 로직을 가져다 쓰면
--    순환 require로 nil이 잡히는 사고가 재발한다.
-- ═══════════════════════════════════════════════════════════════════════════

local OFFSET_PX = 2  -- 포토샵 stroke 2px 상당. 필요하면 이 값만 조절.

local function drawOutlined(uiElement, text, x, y, r, g, b, a, font)
    for dx = -OFFSET_PX, OFFSET_PX, OFFSET_PX do
        for dy = -OFFSET_PX, OFFSET_PX, OFFSET_PX do
            if dx ~= 0 or dy ~= 0 then
                uiElement:drawText(text, x + dx, y + dy, 0, 0, 0, a, font)
            end
        end
    end
    uiElement:drawText(text, x, y, r, g, b, a, font)
end

local function drawCentreOutlined(uiElement, text, x, y, r, g, b, a, font)
    for dx = -OFFSET_PX, OFFSET_PX, OFFSET_PX do
        for dy = -OFFSET_PX, OFFSET_PX, OFFSET_PX do
            if dx ~= 0 or dy ~= 0 then
                uiElement:drawTextCentre(text, x + dx, y + dy, 0, 0, 0, a, font)
            end
        end
    end
    uiElement:drawTextCentre(text, x, y, r, g, b, a, font)
end

return { draw = drawOutlined, drawCentre = drawCentreOutlined }
