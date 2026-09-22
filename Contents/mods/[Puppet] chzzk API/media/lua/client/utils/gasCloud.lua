local _gas = {}

-- ═══════════════════════════════════════════════════════════════════════════
--  바닥 가스 확산 연출  [leaf 모듈 -- features/ 를 require 하지 않는다]
--
--  강령술(rise_up_dead_man)의 "재활성화 가스 살포" 방식에서 보라색 반경 마커
--  대신 쓰는 연출이다. 발동 지점을 중심으로 황록색 가스가 반경까지 퍼졌다가
--  서서히 걷힌다.
--
--  왜 WorldMarkers 가 아닌 직접 렌더인가:
--   · addGridSquareMarker 는 단색 원 하나가 전부다. 색만 초록으로 바꿔도
--     "시스템 범위표시"로 읽히지 "가스가 퍼졌다"로는 안 읽힌다.
--   · 애니메이션 프레임을 못 먹인다.
--  그래서 좀비 공습의 수송기 그림자(features/zombierain.lua)와 같은 경로를
--  쓴다 -- OnPostFloorLayerDraw(z=0) + renderPoly. 바닥 타일 위, 물체/캐릭터
--  아래에 깔리므로 가스 안에서 일어나는 시체가 가스에 가려지지 않는다.
--
--  왜 IsoObject + setSprite 가 아닌가:
--   스퀘어에 더미 오브젝트를 심는 방식은 청크 언로드/세이브에 얽히고 MP 에서
--   스퀘어 소유권 문제가 생긴다. 순수 렌더는 월드를 전혀 건드리지 않는다.
--
--  이 모듈은 월드 상태를 바꾸지 않는다. 데미지도, 어그로도, addSound 도 없다.
--  순수 시각 연출이며 각 클라가 자기 화면에만 그린다.
-- ═══════════════════════════════════════════════════════════════════════════

local FRAME_COUNT = 16
local FRAME_MS    = 90     -- 프레임당 유지(ms). 16프레임 = 1.44초 루프
-- 퍼프 크기는 고정값이 아니라 반경/개수에서 유도한다(spawn 주석 참조).
local PUFF_SPACE  = 9      -- 퍼프 중심 간 목표 간격(타일). 개수 산정에만 쓴다
local PUFF_COVER  = 0.60   -- 겹침을 감안한 덮기 효율. 낮출수록 퍼프가 커진다
local PUFF_FUZZ   = 1.00   -- 퍼프 크기 미세조정 배율. 성기면 올리고 답답하면 내린다
local SC_MIN      = 0.80   -- 퍼프 크기 지터 하한
local SC_JITTER   = 40     -- 상한 = SC_MIN + SC_JITTER/100
local SC_MAX      = SC_MIN + SC_JITTER / 100
-- 텍스처 알파가 최대의 25% 로 떨어지는 지점(텍스처 반변 대비). 생성된 png 들의
-- 알파 프로파일 실측값이다 -- 퍼프가 중심에서 실제로 얼마나 번져 보이는지를
-- 결정하므로, 텍스처를 다시 만들면 이 값도 같이 재봐야 한다.
local TEX_EDGE    = 0.73
local PUFF_MIN    = 6
local PUFF_MAX    = 40     -- 프레임당 renderPoly 호출 상한. 반경 60에서도 이 값
local PUFF_IN_MS  = 400    -- 퍼프 하나가 나타나는 시간
local SPREAD_CAP  = 1500   -- 중앙 -> 가장자리 확산 시간 상한(ms)
local FADE_CAP    = 2000   -- 소산 시간 상한(ms)
local ALPHA_MAX   = 0.30   -- 퍼프 1장 기준. 겹치면 중심부가 더 진해진다
local SCALE_IN    = 0.55   -- 등장 시작 크기 배율 (1.0 까지 커진다)
local VIEW_MARGIN = 60     -- 반경 + 이 값보다 멀면 그리지 않는다(타일)

-- 텍스처는 회색조다. 색은 renderPoly 의 r,g,b 로 입힌다 -- 틴트를 바꾸고 싶으면
-- 파일이 아니라 아래 세 값만 고치면 된다.
local TINT_R, TINT_G, TINT_B = 0.72, 0.88, 0.18   -- 황록(생화학 경고 톤)

local TEX = {}
local TEX_OK = true
for i = 1, FRAME_COUNT do
    local path = "media/textures/PongDuGas/pongdu_gas_" .. string.format("%02d", i - 1) .. ".png"
    TEX[i] = getTexture(path)
    if not TEX[i] then
        TEX_OK = false
        print("[PongDu][Gas] WARN texture missing: " .. path)
    end
end

local _clouds = {}

local function clamp(v, lo, hi)
    if v < lo then return lo elseif v > hi then return hi end
    return v
end

-- spawn(x, y, z, radius, durationMs)
-- 발동 지점 기준 반경 안에 퍼프를 흩뿌린다. 호출한 클라 화면에만 그려지므로
-- 주변 접속자 몫은 호출부가 utils/fx 브로드캐스트로 따로 보내야 한다.
function _gas.spawn(x, y, z, radius, durationMs)
    if not TEX_OK then
        print("[PongDu][Gas] spawn skipped (textures not loaded)")
        return
    end
    local r = tonumber(radius) or 0
    local dur = tonumber(durationMs) or 0
    if r <= 0 or dur <= 0 then
        print("[PongDu][Gas] spawn skipped bad args r=" .. tostring(radius) .. " dur=" .. tostring(durationMs))
        return
    end

    local spread = clamp(dur * 0.25, 0, SPREAD_CAP)
    local fade   = clamp(dur * 0.30, 0, FADE_CAP)

    -- ── 퍼프 개수와 크기 ──────────────────────────────────────────────────
    -- 두 가지를 동시에 만족시켜야 한다:
    --  (1) 가스의 바깥 가장자리 = 부활 반경 r. 퍼프는 "중심"이 놓이는 자리에서
    --      바깥으로 번지므로, r 까지 중심을 깔면 가스가 r 밖으로 삐져나가
    --      범위표시로서 거짓말을 한다 (r=30 기준 약 +5.5타일).
    --  (2) 안쪽에 구멍이 없을 것. 개수에 상한(PUFF_MAX)이 있으니 반경이 커지면
    --      개수 대신 퍼프를 키워서 덮어야 한다. 크기를 고정하면 r=60 에서
    --      40장으로는 성기게 흩어져 구멍이 숭숭 뚫린다.
    --
    -- v = 퍼프 하나가 중심에서 번져 보이는 거리(가시 반지름, 평균 크기 기준).
    -- (1) 은  place + v*SC_MAX = r      (가장 크게 뽑힌 퍼프도 r 을 안 넘게)
    -- (2) 는  place = v * sqrt(COVER*n) (n 장으로 place 반경을 덮는 조건)
    -- 두 식을 v 에 대해 풀면 아래 한 줄로 떨어진다. 반복 계산이 필요 없다.
    local n = math.floor(3.14159 * r * r / (PUFF_SPACE * PUFF_SPACE))
    n = clamp(n, PUFF_MIN, PUFF_MAX)

    local v = r / (SC_MAX + math.sqrt(PUFF_COVER * n))
    local place = r - v * SC_MAX
    if place < 0 then place = 0 end
    -- 가시 반지름 v 를 내는 데 필요한 텍스처 한 변. 렌더는 이 값을 쓴다.
    local puffSize = v * PUFF_FUZZ / (0.5 * TEX_EDGE)

    -- 황금각 나선 배치. 무작위로 뿌리면 뭉치고 비는 자리가 생기는데, 이건
    -- 원판 위에 고르게 깔리면서도 격자처럼 보이지 않는다.
    -- 반지름에 sqrt 를 씌워야 면적 기준으로 균등해진다(안 씌우면 중심에 몰림).
    local GOLDEN = 2.39996
    -- 가장 안쪽 퍼프의 반지름. 확산 지연을 이 값 기준으로 정규화해야 첫 퍼프가
    -- dly=0 으로 즉시 뜬다(안 하면 반경에 비례해 중앙도 수백 ms 늦게 뜬다).
    local rrMin = place * math.sqrt(0.5 / n)
    local rrSpan = place - rrMin
    local puffs = {}
    for i = 1, n do
        local frac = (i - 0.5) / n
        local rr = place * math.sqrt(frac)
        local ang = i * GOLDEN
        local ux, uy = math.cos(ang), math.sin(ang)
        puffs[i] = {
            x = x + rr * ux,
            y = y + rr * uy,
            -- 중앙이 먼저, 가장자리가 나중에 -- 이게 "퍼진다"로 읽히는 핵심
            -- (rrSpan 이 0 이면 퍼프가 하나뿐인 경우라 전부 즉시 뜬다)
            dly = (rrSpan > 0) and (spread * (rr - rrMin) / rrSpan) or 0,
            ph  = ZombRand(FRAME_COUNT),            -- 프레임 위상(퍼프마다 다르게)
            sc  = SC_MIN + ZombRand(SC_JITTER + 1) / 100,
            rot = ZombRand(628) / 100,              -- 0 ~ 2pi 회전
            sz  = puffSize,
        }
    end

    _clouds[#_clouds + 1] = {
        x = x, y = y,
        r = r,
        t0 = getTimestampMs(),
        dur = dur,
        fade = fade,
        puffs = puffs,
    }
    print("[PongDu][Gas] spawn r=" .. tostring(r) .. " durMs=" .. tostring(math.floor(dur))
        .. " puffs=" .. tostring(n) .. " place=" .. tostring(math.floor(place * 10) / 10)
        .. " puffSize=" .. tostring(math.floor(puffSize * 10) / 10)
        .. " spreadMs=" .. tostring(math.floor(spread)))
end

-- ── 렌더 ──────────────────────────────────────────────────────────────────
-- 아이소 투영은 (x,y)에 대해 정확히 선형이다 (IsoUtils.java:75,104 확인):
--   XToScreen(x,y,0,0) = (x - y) * 32 * TileScale
--   YToScreen(x,y,0,0) = (x + y) * 16 * TileScale
-- 그래서 기저 두 개만 프레임당 한 번 구해두면 나머지 꼭짓점은 순수 Lua 산술로
-- 뽑을 수 있다. 퍼프마다 네 번씩 IsoUtils 를 부르면 (퍼프 40개 = 320 호출/프레임)
-- Kahlua Java 호출 오버헤드가 그대로 프레임에 실린다.
-- renderPoly UV: 1=좌상, 2=우상, 3=우하, 4=좌하 (수송기 그림자와 동일).
local function drawClouds(z)
    if z ~= 0 or #_clouds == 0 then return end

    local now = getTimestampMs()
    local renderer = getRenderer()
    local offX, offY = IsoCamera.getOffX(), IsoCamera.getOffY()
    local bx = IsoUtils.XToScreen(1, 0, 0, 0)   -- = 32 * TileScale
    local by = IsoUtils.YToScreen(1, 0, 0, 0)   -- = 16 * TileScale

    local pl = getSpecificPlayer(0)
    local plx, ply = 0, 0
    if pl then plx, ply = pl:getX(), pl:getY() end

    for ci = #_clouds, 1, -1 do
        local c = _clouds[ci]
        local age = now - c.t0
        if age >= c.dur then
            table.remove(_clouds, ci)
        else
            -- 화면 밖이면 좌표 계산 자체를 건너뛴다
            local ddx, ddy = plx - c.x, ply - c.y
            local lim = c.r + VIEW_MARGIN
            if ddx * ddx + ddy * ddy <= lim * lim then
                -- 구름 전체 소산 계수
                local gk = 1
                local left = c.dur - age
                if left < c.fade then gk = left / c.fade end

                for pi = 1, #c.puffs do
                    local p = c.puffs[pi]
                    local pa = age - p.dly
                    if pa > 0 then
                        local ik = pa / PUFF_IN_MS
                        if ik > 1 then ik = 1 end
                        local a = ALPHA_MAX * ik * gk
                        if a > 0.004 then
                            local h = p.sz * p.sc * (SCALE_IN + (1 - SCALE_IN) * ik) / 2
                            local ux, uy = math.cos(p.rot), math.sin(p.rot)
                            local ax, ay = ux * h, uy * h        -- 퍼프 로컬 +Y
                            local rx, ry = -uy * h, ux * h       -- 퍼프 로컬 +X
                            -- 네 꼭짓점의 월드 좌표
                            local wx1, wy1 = p.x + ax - rx, p.y + ay - ry
                            local wx2, wy2 = p.x + ax + rx, p.y + ay + ry
                            local wx3, wy3 = p.x - ax + rx, p.y - ay + ry
                            local wx4, wy4 = p.x - ax - rx, p.y - ay - ry
                            local fi = math.floor(pa / FRAME_MS) + p.ph
                            local tex = TEX[fi % FRAME_COUNT + 1]
                            renderer:renderPoly(tex,
                                (wx1 - wy1) * bx - offX, (wx1 + wy1) * by - offY,
                                (wx2 - wy2) * bx - offX, (wx2 + wy2) * by - offY,
                                (wx3 - wy3) * bx - offX, (wx3 + wy3) * by - offY,
                                (wx4 - wy4) * bx - offX, (wx4 + wy4) * by - offY,
                                TINT_R, TINT_G, TINT_B, a)
                        end
                    end
                end
            end
        end
    end
end
Events.OnPostFloorLayerDraw.Add(drawClouds)

return _gas
