-- t3VehicleDropMarker: 차량보급 투하 지점을 월드맵 심볼로 남긴다.
--
-- [기존 방식과 그 문제]
-- 예전에는 shared/t3VehicleDrop.lua 안에서 ISWorldMap_instance가 없으면
-- ShowWorldMap -> HideWorldMap을 연달아 호출해 인스턴스를 강제로 만들어냈다.
-- 이 트릭은 플레이어가 접속 후 월드맵(M키)을 한 번도 안 연 상태에서 실패해서,
-- "차량은 떨어졌는데 맵에 마커가 없다"가 됐다. 세션당 첫 개봉만 실패하고
-- 그 뒤로는 인스턴스가 살아있어 정상 동작했기 때문에 간헐적으로 보였던 것.
--
-- [현재 방식]
-- 심볼 저장소(MapItem.getSingleton()의 WorldMapSymbols)는 Lua에 노출돼 있지 않아
-- UIWorldMap 인스턴스를 거치지 않고는 건드릴 수 없다. 그래서 인스턴스가 없으면
-- 좌표를 플레이어 modData 큐에 쌓아두고, 플레이어가 실제로 월드맵을 여는 순간
-- (ISWorldMap.ShowWorldMap 훅) 밀어넣는다. 큐는 modData라 게임을 껐다 켜도 남는다.
-- 결과적으로 플레이어 입장에서는 "맵을 열면 마커가 있다"로 동일하다.

if isServer() then return end

t3VehicleDropMarker = t3VehicleDropMarker or {}

local QUEUE_KEY = "t3VehicleDropMarkerQueue"
local QUEUE_LIMIT = 32 -- 훅이 어떤 이유로든 안 돌 때 modData가 무한히 커지는 것 방지

local MARKER_SYMBOL = "Boat" -- 바닐라 MapSymbolDefinitions 등록 심볼
local MARKER_R, MARKER_G, MARKER_B = 0.1, 0.3, 0.9

-- 심볼 스케일은 바닐라 펜 심볼과 동일하게 ISMap.SCALE을 쓴다.
-- 예전에 0으로 줬던 적이 있는데, scale <= 0 이면 WorldMapTextureSymbol.render가
-- getDisplayScale을 안 타고 DrawTextureColor로 텍스처 원본 픽셀 크기 고정 렌더를 해서
-- 줌을 바꿔도 아이콘 크기가 안 변한다. 양수 스케일이면 getLayoutWorldScale()이 곱해져
-- 줌에 맞춰 커지고 작아진다 (대신 바닐라와 똑같이 줌 14.5 미만에서는 렌더에서 빠진다).
-- ISMap이 아직 로드 안 된 상황을 대비해 바닐라 기본값(0.666)으로 폴백.
local function getMarkerScale()
    return (ISMap and ISMap.SCALE) or 0.666
end

-- 인스턴스가 살아있을 때만 성공. 큐로 넘길지 여부를 호출부가 판단할 수 있게 boolean 반환.
local function addSymbolNow(x, y)
    if not ISWorldMap_instance then return false end

    local mapAPI = ISWorldMap_instance.mapAPI
    local symbolsAPI = mapAPI and mapAPI:getSymbolsAPI()
    if not symbolsAPI then
        print("[t3VehicleDrop] symbolsAPI unavailable, cannot place map symbol")
        return false
    end

    local sym = symbolsAPI:addTexture(MARKER_SYMBOL, x, y)
    if not sym then
        print("[t3VehicleDrop] addTexture returned nil for symbol '" .. MARKER_SYMBOL .. "'")
        return false
    end
    sym:setRGBA(MARKER_R, MARKER_G, MARKER_B, 1.0)
    sym:setAnchor(0.5, 0.5)
    sym:setScale(getMarkerScale())

    -- 플레이어가 월드맵 옵션에서 심볼 표시를 꺼놨으면 찍어도 화면에 안 나온다.
    -- 임의로 켜주는 건 월권이라 원인 추적용 로그만 남긴다.
    if not mapAPI:getBoolean("Symbols") then
        print("[t3VehicleDrop] World map 'Symbols' option is disabled, marker stays hidden until re-enabled")
    end

    print("[t3VehicleDrop] Map symbol placed (" .. tostring(x) .. "," .. tostring(y) .. ")")
    return true
end

-- 좌표는 "x,y" 문자열로 저장한다. modData 직렬화에서 중첩 테이블보다 다룰 게 적다.
local function getQueue(player)
    local md = player:getModData()
    local queue = md[QUEUE_KEY]
    if type(queue) ~= "table" then
        queue = {}
        md[QUEUE_KEY] = queue
    end
    return queue
end

-- 큐에 쌓인 마커를 월드맵에 반영. 실패한 항목은 큐에 남겨 다음 기회에 재시도한다.
function t3VehicleDropMarker.flush(player)
    if not player then return end

    local queue = getQueue(player)
    local pending = #queue
    if pending == 0 then return end

    local remaining = {}
    for i = 1, pending do
        local entry = queue[i]
        local sx, sy = string.match(entry, "^(-?%d+),(-?%d+)$")
        if not sx then
            print("[t3VehicleDrop] Dropping malformed queued marker: " .. tostring(entry))
        elseif not addSymbolNow(tonumber(sx), tonumber(sy)) then
            remaining[#remaining + 1] = entry
        end
    end

    player:getModData()[QUEUE_KEY] = remaining
    print("[t3VehicleDrop] Marker queue flushed (" .. (pending - #remaining)
        .. " placed, " .. #remaining .. " still pending)")
end

-- 외부 진입점. 월드맵이 준비돼 있으면 즉시, 아니면 큐에 적재.
function t3VehicleDropMarker.place(player, x, y)
    if not player then return end

    if addSymbolNow(x, y) then return end

    local queue = getQueue(player)
    queue[#queue + 1] = tostring(x) .. "," .. tostring(y)

    -- 오래된 것부터 버린다 (최근 투하 지점이 더 쓸모 있으므로)
    while #queue > QUEUE_LIMIT do
        print("[t3VehicleDrop] Marker queue over limit, dropping oldest entry: " .. tostring(queue[1]))
        for i = 1, #queue - 1 do
            queue[i] = queue[i + 1]
        end
        queue[#queue] = nil
    end

    print("[t3VehicleDrop] World map not ready, marker queued ("
        .. tostring(x) .. "," .. tostring(y) .. "), pending=" .. #queue)
end

-- ISWorldMap.ShowWorldMap 훅.
-- 파일 로드 시점이 아니라 OnGameStart에서 거는 이유: 모드 client 파일이
-- 바닐라 ISWorldMap.lua보다 먼저 평가될 여지를 없애기 위함.
local function installHook()
    if t3VehicleDropMarker.hookInstalled then return end

    if not ISWorldMap or not ISWorldMap.ShowWorldMap then
        print("[t3VehicleDrop] ISWorldMap unavailable, marker queue hook not installed")
        return
    end

    local originalShowWorldMap = ISWorldMap.ShowWorldMap
    ISWorldMap.ShowWorldMap = function(playerNum)
        originalShowWorldMap(playerNum)
        -- 인스턴스 생성 실패(IsAllowed false 등)까지 감안해 flush 쪽에서 다시 검사한다.
        local player = getSpecificPlayer(playerNum)
        if player then
            t3VehicleDropMarker.flush(player)
        end
    end

    t3VehicleDropMarker.hookInstalled = true
    print("[t3VehicleDrop] Map marker queue hook installed")
end

Events.OnGameStart.Add(installHook)
