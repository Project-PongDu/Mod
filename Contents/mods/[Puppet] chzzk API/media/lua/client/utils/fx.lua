local _fx = {}

local colorMap = require("utils/colorMap")

-- ═══════════════════════════════════════════════════════════════════════════
--  후원 이펙트 브로드캐스트 (사운드 + 바닥 반경 마커)  [module: PongDuFx]
--
--  문제:
--   · getSoundManager():PlaySound() 는 클라 로컬 재생이라 발동한 본인만 듣는다.
--   · getWorldMarkers():addGridSquareMarker() 도 로컬 렌더라 본인 화면에만 보인다.
--     (WorldMarkers.addGridSquareMarker 는 GameServer.bServer 면 아예 null 반환 —
--      서버에서 마커를 만드는 경로 자체가 없다. 클라마다 각자 그려야 한다.)
--   그래서 강령술/좀비레인의 반경 표시와 효과음이 후원받은 클라에만 국한됐다.
--
--  구조: 발동 클라 -> 서버(거리컷) -> 주변 클라. 발동 클라 본인은 서버 왕복
--  지연 없이 즉시 반응하도록 기존대로 로컬에서 직접 재생/렌더하고, 서버는
--  본인을 제외한 나머지에게만 보낸다 (기존 PongDuDonation/PlayAlert 와 동일 정책).
--
--  사운드 반경은 기능 효과 반경과 무관하게 SOUND_RADIUS 고정이다. "근처 사람이
--  듣는다"는 연출이지 효과 판정이 아니고, 레인(기본 20)·강령술(기본 30)처럼
--  효과 반경이 작은 기능은 그대로 쓰면 바로 옆 사람도 못 듣는다.
--
--  마커 색상은 colorMap(도네 큐박스 색상표)을 그대로 쓴다 — 큐박스에서 보던
--  색이 바닥에 그대로 뜬다.
-- ═══════════════════════════════════════════════════════════════════════════

local MODULE        = "PongDuFx"
local SOUND_RADIUS  = 40    -- 효과음 가청 반경(타일). missile 알림음이 쓰던 값과 동일
local SQ_WAIT_TICKS = 120   -- 마커 부착 대기 한도(약 2초) — 청크 스트리밍 대기용

_fx.SOUND_RADIUS = SOUND_RADIUS

-- ── 로컬 반경 마커 ────────────────────────────────────────────────────────
-- addGridSquareMarker(square, r, g, b, doAlpha, radius) -> marker 객체.
-- ISSpawnHordeUI(바닐라 좀비떼 스폰 UI)가 쓰는 것과 동일한 API.
local function attachMarker(square, radius, col, durationMs)
    local marker = getWorldMarkers():addGridSquareMarker(square, col[1], col[2], col[3], true, radius)
    if not marker then return end
    marker:setScaleCircleTexture(true)

    local start = getTimestampMs()
    local function tick()
        if getTimestampMs() - start >= durationMs then
            marker:remove()
            Events.OnTick.Remove(tick)
        end
    end
    Events.OnTick.Add(tick)
end

-- marker(x, y, z, featureId, radius, durationMs)
-- 마커는 IsoGridSquare 를 요구하는데(모든 오버로드 공통), 원격 클라는 해당
-- 좌표 청크가 아직 스트리밍 전일 수 있다. 그 경우 로드될 때까지 잠깐 기다렸다
-- 붙인다 (한도 초과 시 포기 — 어차피 화면 밖).
function _fx.marker(x, y, z, featureId, radius, durationMs)
    local gx = math.floor(x)
    local gy = math.floor(y)
    local gz = math.floor(z or 0)
    local col = colorMap.get(featureId)

    local cell = getCell()
    local sq = cell and cell:getGridSquare(gx, gy, gz)
    if sq then
        attachMarker(sq, radius, col, durationMs)
        return
    end

    local waited = 0
    local function wait()
        waited = waited + 1
        local c = getCell()
        local s = c and c:getGridSquare(gx, gy, gz)
        if s then
            Events.OnTick.Remove(wait)
            attachMarker(s, radius, col, durationMs)
        elseif waited >= SQ_WAIT_TICKS then
            Events.OnTick.Remove(wait)
            print("[PongDu][Fx] marker skipped (square not loaded) feature=" .. tostring(featureId)
                .. " @" .. tostring(gx) .. "," .. tostring(gy))
        end
    end
    Events.OnTick.Add(wait)
end

-- broadcast{ f=featureId, x=, y=, z=, sound=, markerRadius=, markerMs= }
--   sound        : 효과음 이름(생략 시 소리 없음)
--   markerRadius : 0 또는 생략이면 마커 없음(샌드박스 반경표시 옵션이 꺼진 경우)
-- 발동 클라 본인 몫(로컬 재생/렌더)은 호출부가 따로 처리한다.
function _fx.broadcast(t)
    if not t or not t.f or not t.x or not t.y then return end
    sendClientCommand(MODULE, "Play", {
        ["f"]  = t.f,
        ["x"]  = t.x,
        ["y"]  = t.y,
        ["z"]  = math.floor(t.z or 0),
        ["s"]  = t.sound or "",
        ["sr"] = SOUND_RADIUS,
        ["mr"] = t.markerRadius or 0,
        ["ms"] = t.markerMs or 3000,
    })
end

-- ── 수신: 서버가 거리컷해서 보낸 것만 온다 ────────────────────────────────
-- 사운드는 여기서 한 번 더 정확히 판정한다 — 서버 컷 반경은 마커 가시거리까지
-- 포함한 넉넉한 값이라 그것만 믿으면 화면 밖 발동음이 들린다.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= MODULE or command ~= "Play" then return end
    if not args then return end

    local player = getPlayer()
    if not player then return end

    local x = tonumber(args["x"])
    local y = tonumber(args["y"])
    if not x or not y then return end

    local dx = player:getX() - x
    local dy = player:getY() - y
    local d2 = dx * dx + dy * dy

    local snd = tostring(args["s"] or "")
    local sr  = tonumber(args["sr"]) or SOUND_RADIUS
    if snd ~= "" and d2 <= sr * sr then
        getSoundManager():PlaySound(snd, false, 1.0)
    end

    local mr = tonumber(args["mr"]) or 0
    if mr > 0 then
        _fx.marker(x, y, tonumber(args["z"]) or 0, tostring(args["f"] or ""),
            mr, tonumber(args["ms"]) or 3000)
    end
end)

return _fx
