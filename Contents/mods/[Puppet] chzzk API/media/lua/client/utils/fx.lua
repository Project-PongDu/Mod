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
--  사운드/알림 반경은 기능 효과 반경과 무관하게 FX_RADIUS 고정이다. "근처 사람이
--  듣는다/알아챈다"는 연출이지 효과 판정이 아니고, 레인(기본 20)·강령술(기본 30)처럼
--  효과 반경이 작은 기능은 그대로 쓰면 바로 옆 사람도 못 듣는다.
--
--  마커 색상은 colorMap(도네 큐박스 색상표)을 그대로 쓴다 — 큐박스에서 보던
--  색이 바닥에 그대로 뜬다.
--
--  세 번째 채널로 "머리 위 알림(note)"이 있다. 좀비 소환 계열(좀비룰렛/뛰좀/
--  특수좀비)은 옆 사람이 좀비를 눈으로 보기 전까지 알 방법이 없어서, 발동 순간
--  FX_RADIUS 안의 플레이어 화면에 후원받은 플레이어의 머리 위로 말풍선을 띄운다.
--  반경은 효과음과 같은 값을 공유한다 — 둘 다 "근처 사람이 인지한다"는 같은
--  기준이라 따로 둘 이유가 없다.
--  구현은 target:addLineChatElement() — 캐릭터가 들고 있는 chatElement(머리 위
--  말풍선 렌더러)에 줄을 직접 넣는 경로다. 두 대안은 안 쓴다:
--   · Say()      : ChatManager.showInfoMessage 경유라 채팅 로그에 줄이 쌓인다
--                  (IsoGameCharacter.ProcessSay 디컴파일 확인).
--   · setHaloNote: 렌더 게이트가 playerIsSelf() 라서(IsoGameCharacter:6598)
--                  남의 캐릭터에 걸면 아무것도 안 보인다.
-- ═══════════════════════════════════════════════════════════════════════════

local MODULE        = "PongDuFx"
local FX_RADIUS     = 40    -- 효과음/머리위 알림 공용 반경(타일). missile 알림음이 쓰던 값
local SQ_WAIT_TICKS = 120   -- 마커 부착 대기 한도(약 2초) — 청크 스트리밍 대기용

_fx.FX_RADIUS = FX_RADIUS

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

-- broadcast{ f=featureId, x=, y=, z=, sound=, markerRadius=, markerMs=,
--            noteKey=, noteName=, noteId= }
--   sound        : 효과음 이름(생략 시 소리 없음)
--   markerRadius : 0 또는 생략이면 마커 없음(샌드박스 반경표시 옵션이 꺼진 경우)
--   noteKey      : 머리 위 말풍선 번역키(생략 시 알림 없음). %1 에 noteName 이 들어간다.
-- 발동 클라 본인 몫(로컬 재생/렌더)은 호출부가 따로 처리한다.
-- sr(효과음+알림 공용 반경)은 둘 다 없으면 0으로 나간다 — 그래야 서버가
-- 마커만 있는 발동을 쓸데없이 멀리까지 뿌리지 않는다.
function _fx.broadcast(t)
    if not t or not t.f or not t.x or not t.y then return end
    local snd  = t.sound or ""
    local note = t.noteKey or ""
    sendClientCommand(MODULE, "Play", {
        ["f"]   = t.f,
        ["x"]   = t.x,
        ["y"]   = t.y,
        ["z"]   = math.floor(t.z or 0),
        ["s"]   = snd,
        ["sr"]  = (snd ~= "" or note ~= "") and FX_RADIUS or 0,
        ["mr"]  = t.markerRadius or 0,
        ["ms"]  = t.markerMs or 3000,
        ["nk"]  = note,
        ["nn"]  = t.noteName or "",
        ["nid"] = t.noteId or -1,
    })
end

-- notifyNearby(player, featureId, noteKey, variants)
-- 후원받은 플레이어 머리 위에 말풍선을 띄운다 — 반경 FX_RADIUS 안의 다른
-- 접속자 화면에만. 본인은 큐박스/카운트다운으로 이미 알고 있으므로 제외한다.
--
-- variants(숫자)를 주면 noteKey .. "_" .. 1~variants 중 하나를 여기서 뽑는다.
-- 추첨을 발동 클라에서 하는 게 핵심 — 수신측에서 각자 뽑으면 같은 사건인데
-- 사람마다 다른 문장이 뜬다. 뽑힌 최종 키만 패킷에 실어 보낸다.
-- 번역 키 개수와 variants 값이 어긋나면 getText가 키 문자열을 그대로 뱉으므로
-- IG_UI_KO.txt 항목 수와 반드시 맞출 것.
function _fx.notifyNearby(player, featureId, noteKey, variants)
    if not player or not noteKey then return end
    if variants and variants > 1 then
        noteKey = noteKey .. "_" .. tostring(ZombRand(1, variants + 1))
    end
    local id = -1
    pcall(function() id = player:getOnlineID() end)
    local name = ""
    pcall(function() name = player:getUsername() or "" end)
    _fx.broadcast({
        f = featureId,
        x = player:getX(), y = player:getY(), z = player:getZ(),
        noteKey = noteKey, noteName = name, noteId = id,
    })
end

-- onlineID 우선, 실패 시 username 폴백으로 대상 플레이어 객체를 찾는다.
-- (원격 플레이어의 getOnlineID는 클라에서도 유효 — 바닐라 ISSplint 등이 쓰는 패턴)
local function findPlayer(id, name)
    local ps = getOnlinePlayers()
    if not ps then return nil end
    local byName = nil
    for i = 0, ps:size() - 1 do
        local p = ps:get(i)
        if p then
            if id and id >= 0 and p:getOnlineID() == id then return p end
            if name ~= "" and byName == nil and p:getUsername() == name then byName = p end
        end
    end
    return byName
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
    local sr  = tonumber(args["sr"]) or FX_RADIUS
    local inRange = d2 <= sr * sr
    if snd ~= "" and inRange then
        getSoundManager():PlaySound(snd, false, 1.0)
    end

    local feature = tostring(args["f"] or "")

    local mr = tonumber(args["mr"]) or 0
    if mr > 0 then
        _fx.marker(x, y, tonumber(args["z"]) or 0, feature, mr, tonumber(args["ms"]) or 3000)
    end

    -- 머리 위 알림: 효과음과 같은 sr 반경을 공유한다.
    local nk = tostring(args["nk"] or "")
    if nk ~= "" and inRange then
        local nn = tostring(args["nn"] or "")
        local target = findPlayer(tonumber(args["nid"]), nn)
        if target then
            local col = colorMap.get(feature)
            local ok = pcall(function()
                target:addLineChatElement(getText(nk, nn), col[1], col[2], col[3])
            end)
            if not ok then
                print("[PongDu][Fx] note failed feature=" .. feature .. " key=" .. nk)
            end
        else
            print("[PongDu][Fx] note target not found name=" .. nn
                .. " id=" .. tostring(args["nid"]))
        end
    end
end)

return _fx
