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

-- 인스턴스가 살아있을 때만 성공. 큐로 넘길지 여부를 호출부가 판단할 수 있게
-- 성공 시 심볼 인덱스(0-base)를, 실패 시 nil을 반환한다.
local function addSymbolNow(x, y)
    if not ISWorldMap_instance then return nil end

    local mapAPI = ISWorldMap_instance.mapAPI
    local symbolsAPI = mapAPI and mapAPI:getSymbolsAPI()
    if not symbolsAPI then
        print("[t3VehicleDrop] symbolsAPI unavailable, cannot place map symbol")
        return nil
    end

    local sym = symbolsAPI:addTexture(MARKER_SYMBOL, x, y)
    if not sym then
        print("[t3VehicleDrop] addTexture returned nil for symbol '" .. MARKER_SYMBOL .. "'")
        return nil
    end
    sym:setRGBA(MARKER_R, MARKER_G, MARKER_B, 1.0)
    sym:setAnchor(0.5, 0.5)
    sym:setScale(getMarkerScale())

    -- 플레이어가 월드맵 옵션에서 심볼 표시를 꺼놨으면 찍어도 화면에 안 나온다.
    -- 임의로 켜주는 건 월권이라 원인 추적용 로그만 남긴다.
    if not mapAPI:getBoolean("Symbols") then
        print("[t3VehicleDrop] World map 'Symbols' option is disabled, marker stays hidden until re-enabled")
    end

    local index = symbolsAPI:getSymbolCount() - 1
    print("[t3VehicleDrop] Map symbol placed (" .. tostring(x) .. "," .. tostring(y) .. "), index=" .. tostring(index))
    return index
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

-- 실제로 찍힌(큐 대기중이 아닌) 마커의 "x,y" -> 심볼 인덱스 기록. 낙하산을
-- 회수(차량 탑승)했을 때 어느 인덱스를 지워야 할지 알기 위한 용도.
-- place()/flush() 성공 시 여기 기록하고, remove()가 소비한다.
local ACTIVE_KEY = "t3VehicleDropMarkerActive"

local function activeMarkerKey(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function getActiveMarkers(player)
    local md = player:getModData()
    local active = md[ACTIVE_KEY]
    if type(active) ~= "table" then
        active = {}
        md[ACTIVE_KEY] = active
    end
    return active
end

-- 큐에 쌓인 마커를 월드맵에 반영. 실패한 항목은 큐에 남겨 다음 기회에 재시도한다.
function t3VehicleDropMarker.flush(player)
    if not player then return end

    local queue = getQueue(player)
    local pending = #queue
    if pending == 0 then return end

    local active = getActiveMarkers(player)
    local remaining = {}
    for i = 1, pending do
        local entry = queue[i]
        local sx, sy = string.match(entry, "^(-?%d+),(-?%d+)$")
        if not sx then
            print("[t3VehicleDrop] Dropping malformed queued marker: " .. tostring(entry))
        else
            local index = addSymbolNow(tonumber(sx), tonumber(sy))
            if index then
                active[activeMarkerKey(sx, sy)] = index
            else
                remaining[#remaining + 1] = entry
            end
        end
    end

    player:getModData()[QUEUE_KEY] = remaining
    print("[t3VehicleDrop] Marker queue flushed (" .. (pending - #remaining)
        .. " placed, " .. #remaining .. " still pending)")
end

-- 외부 진입점. 월드맵이 준비돼 있으면 즉시, 아니면 큐에 적재.
function t3VehicleDropMarker.place(player, x, y)
    if not player then return end

    local index = addSymbolNow(x, y)
    if index then
        getActiveMarkers(player)[activeMarkerKey(x, y)] = index
        return
    end

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

-- 낙하산을 회수(차량 최초 탑승)했을 때 대응하는 투하 지점 마커를 지운다.
-- place()/flush()와 대칭 구조: 아직 큐에 대기 중이면(맵을 한 번도 안 열어서
-- 화면에 나온 적조차 없는 상태) 그냥 큐에서 빼기만 하면 끝난다.
function t3VehicleDropMarker.remove(player, x, y)
    if not player then return end
    local key = activeMarkerKey(x, y)
    local coordStr = tostring(x) .. "," .. tostring(y)

    local queue = getQueue(player)
    for i = #queue, 1, -1 do
        if queue[i] == coordStr then
            table.remove(queue, i)
            print("[t3VehicleDrop] Pending marker cancelled before it was ever shown (" .. key .. ")")
            return
        end
    end

    local active = getActiveMarkers(player)
    local index = active[key]
    if index == nil then
        -- 이미 지워졌거나(중복 회수 요청), 애초에 이 플레이어 마커가 아니었음.
        return
    end
    active[key] = nil

    if not ISWorldMap_instance then
        print("[t3VehicleDrop] ISWorldMap_instance unavailable, cannot remove marker (" .. key .. ")")
        return
    end
    local mapAPI = ISWorldMap_instance.mapAPI
    local symbolsAPI = mapAPI and mapAPI:getSymbolsAPI()
    if not symbolsAPI then
        print("[t3VehicleDrop] symbolsAPI unavailable, cannot remove marker (" .. key .. ")")
        return
    end

    -- 그 사이 플레이어가 자기 맵에 심볼을 직접 추가/삭제했으면 인덱스가 밀렸을 수
    -- 있다. 지우기 전에 정말 우리 텍스처 심볼이 맞는지 확인해서, 엉뚱한 심볼을
    -- 대신 지우는 사고를 막는다.
    local symbol = symbolsAPI:getSymbolByIndex(index)
    if symbol and symbol:isTexture() and symbol:getSymbolID() == MARKER_SYMBOL then
        symbolsAPI:removeSymbolByIndex(index)
        print("[t3VehicleDrop] Map symbol removed (" .. key .. ", index=" .. tostring(index) .. ")")
    else
        print("[t3VehicleDrop] Marker index drifted (other symbols added/removed meanwhile),"
            .. " skipping removal to avoid deleting the wrong symbol (" .. key .. ")")
    end
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

-- MP: server/t3VehicleDropSpawner.lua의 clearParachutes가 개봉자 본인 앞으로
-- 보내는 마커 제거 알림. 솔로는 같은 프로세스라 t3VehicleDrop.clearParachutes가
-- t3VehicleDropMarker.remove를 직접 호출하므로 이 핸들러를 안 거친다.
local function onServerCommand(module, command, args)
    if module ~= "PongDuVehicleDrop" then return end
    if command ~= "RemoveMapMarker" then return end

    local player = getPlayer()
    if not player then return end
    if not args or args.x == nil or args.y == nil then
        print("[t3VehicleDrop] RemoveMapMarker: missing x/y")
        return
    end

    t3VehicleDropMarker.remove(player, args.x, args.y)
end

Events.OnServerCommand.Add(onServerCommand)
