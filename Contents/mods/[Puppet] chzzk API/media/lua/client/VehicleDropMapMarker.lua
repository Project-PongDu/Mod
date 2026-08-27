-- t3VehicleDropMarker: 차량보급 투하 지점을 월드맵 심볼로 남기고, 회수 시 지운다.
--
-- [배치 방식]
-- 심볼 저장소(MapItem.getSingleton()의 WorldMapSymbols)는 Lua에 노출돼 있지 않아
-- UIWorldMap 인스턴스를 거치지 않고는 건드릴 수 없다. 그래서 인스턴스가 없으면
-- 좌표를 플레이어 modData 큐에 쌓아두고, 플레이어가 실제로 월드맵을 여는 순간
-- (ISWorldMap.ShowWorldMap 훅) 밀어넣는다. 큐는 modData라 게임을 껐다 켜도 남는다.
--
-- [제거 방식 - 인덱스 부기를 버린 이유]
-- 예전에는 배치 시점의 심볼 인덱스를 modData에 저장해뒀다가 그 인덱스로 지웠다.
-- 이건 실측에서 깨졌다: 심볼 5개(index 0~4)를 찍은 뒤 3 -> 0 -> 4 순으로 제거를
-- 요청했는데, 앞의 두 번이 실제로 리스트를 줄였다면 세 번째의 getSymbolByIndex(4)는
-- 3칸짜리 리스트를 넘겨 IndexOutOfBounds로 터졌어야 한다. 로그엔 예외가 하나도 없고
-- "removed"만 찍혔다 -- 즉 우리가 들고 있던 인덱스는 살아있는 리스트와 대응하지 않는다.
-- (WorldMapSymbolsV1은 UIWorldMap마다 자기 미러 리스트를 따로 들고 있고, 그 미러와
--  공유 저장소의 인덱스가 어긋날 수 있다.)
--
-- 그래서 바닐라 지우개와 같은 원리로 바꿨다: 지울 때마다 심볼 리스트를 훑어
-- "우리 심볼 ID + 우리 색상 + 좌표 일치"인 놈을 찾아 그 자리에서 지운다.
-- 인덱스를 저장하지 않으므로 드리프트 자체가 성립하지 않는다.

if isServer() then return end

t3VehicleDropMarker = t3VehicleDropMarker or {}

local QUEUE_KEY = "t3VehicleDropMarkerQueue"   -- 아직 못 찍은 배치 대기 좌표
local REMOVE_KEY = "t3VehicleDropMarkerRemove" -- 아직 못 지운 제거 대기 좌표
local LEGACY_ACTIVE_KEY = "t3VehicleDropMarkerActive" -- 구버전 인덱스 부기 (정리 대상)
local QUEUE_LIMIT = 32 -- 훅이 어떤 이유로든 안 돌 때 modData가 무한히 커지는 것 방지

local MARKER_SYMBOL = "Boat" -- 바닐라 MapSymbolDefinitions 등록 심볼
local MARKER_R, MARKER_G, MARKER_B = 0.1, 0.3, 0.9
local COLOR_EPSILON = 0.01 -- 플레이어가 직접 찍은 배 심볼과 구분하기 위한 색상 허용오차
local COORD_EPSILON = 0.5  -- 심볼 좌표는 float이라 정수 비교 대신 근사 비교

-- 심볼 스케일은 바닐라 펜 심볼과 동일하게 ISMap.SCALE을 쓴다.
-- 예전에 0으로 줬던 적이 있는데, scale <= 0 이면 WorldMapTextureSymbol.render가
-- getDisplayScale을 안 타고 DrawTextureColor로 텍스처 원본 픽셀 크기 고정 렌더를 해서
-- 줌을 바꿔도 아이콘 크기가 안 변한다. 양수 스케일이면 getLayoutWorldScale()이 곱해져
-- 줌에 맞춰 커지고 작아진다 (대신 바닐라와 똑같이 줌 14.5 미만에서는 렌더에서 빠진다).
-- ISMap이 아직 로드 안 된 상황을 대비해 바닐라 기본값(0.666)으로 폴백.
local function getMarkerScale()
    return (ISMap and ISMap.SCALE) or 0.666
end

-- 월드맵 인스턴스가 살아있을 때만 심볼 API를 얻을 수 있다.
local function getSymbolsAPI()
    if not ISWorldMap_instance then return nil end
    local mapAPI = ISWorldMap_instance.mapAPI
    if not mapAPI then return nil end
    return mapAPI:getSymbolsAPI(), mapAPI
end

-- 성공 시 true. 실패하면 호출부가 큐로 넘긴다.
local function addSymbolNow(x, y)
    local symbolsAPI, mapAPI = getSymbolsAPI()
    if not symbolsAPI then return false end

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

-- 이 심볼이 우리가 찍은 투하 지점 마커인지 판정한다.
-- 심볼 ID / 색상 / 좌표 셋 다 맞아야 우리 것으로 본다. 플레이어가 우연히 같은 자리에
-- 파란 배 심볼을 직접 찍어놨을 때 대신 지워버리는 사고를 막기 위함.
local function isOurMarker(symbol, x, y)
    if not symbol then return false end
    if not symbol:isTexture() then return false end
    if symbol:getSymbolID() ~= MARKER_SYMBOL then return false end
    if math.abs(symbol:getWorldX() - x) > COORD_EPSILON then return false end
    if math.abs(symbol:getWorldY() - y) > COORD_EPSILON then return false end
    if math.abs(symbol:getRed() - MARKER_R) > COLOR_EPSILON then return false end
    if math.abs(symbol:getGreen() - MARKER_G) > COLOR_EPSILON then return false end
    if math.abs(symbol:getBlue() - MARKER_B) > COLOR_EPSILON then return false end
    return true
end

-- 해당 좌표의 우리 마커를 전부 지운다. 반환값: 지운 개수, API 사용 가능 여부.
-- 바닐라 지우개(ISWorldMapSymbolTool_RemoveAnnotation)가 hitTest로 매번 인덱스를
-- 새로 구하는 것과 같은 원리로, 저장해둔 인덱스를 믿지 않고 그때그때 찾는다.
-- 역순 순회: 지우면 뒤쪽 인덱스가 당겨지므로 앞으로 진행하면 건너뛴다.
local function removeSymbolsAt(x, y)
    local symbolsAPI = getSymbolsAPI()
    if not symbolsAPI then return 0, false end

    local removed = 0
    for i = symbolsAPI:getSymbolCount() - 1, 0, -1 do
        if isOurMarker(symbolsAPI:getSymbolByIndex(i), x, y) then
            symbolsAPI:removeSymbolByIndex(i)
            removed = removed + 1
        end
    end
    return removed, true
end

-- 좌표는 "x,y" 문자열로 저장한다. modData 직렬화에서 중첩 테이블보다 다룰 게 적다.
local function coordStr(x, y)
    return tostring(x) .. "," .. tostring(y)
end

local function parseCoord(entry)
    local sx, sy = string.match(entry, "^(-?%d+),(-?%d+)$")
    if not sx then return nil end
    return tonumber(sx), tonumber(sy)
end

local function getList(player, key)
    local md = player:getModData()
    local list = md[key]
    if type(list) ~= "table" then
        list = {}
        md[key] = list
    end
    return list
end

local function pushCapped(list, entry, label)
    list[#list + 1] = entry
    -- 오래된 것부터 버린다 (최근 항목이 더 쓸모 있으므로)
    while #list > QUEUE_LIMIT do
        print("[t3VehicleDrop] " .. label .. " over limit, dropping oldest entry: " .. tostring(list[1]))
        table.remove(list, 1)
    end
end

local function dropEntry(list, entry)
    for i = #list, 1, -1 do
        if list[i] == entry then
            table.remove(list, i)
            return true
        end
    end
    return false
end

-- 구버전(인덱스 부기) 잔재 정리. 이제 안 쓰는 키라 남겨두면 세이브만 지저분해진다.
local function dropLegacyData(player)
    local md = player:getModData()
    if md[LEGACY_ACTIVE_KEY] ~= nil then
        md[LEGACY_ACTIVE_KEY] = nil
        print("[t3VehicleDrop] Legacy marker index table discarded")
    end
end

-- 배치 대기 좌표를 월드맵에 반영. 실패한 항목은 큐에 남겨 다음 기회에 재시도한다.
function t3VehicleDropMarker.flush(player)
    if not player then return end
    dropLegacyData(player)

    local queue = getList(player, QUEUE_KEY)
    local pending = #queue
    if pending == 0 then return end

    local removeQueue = getList(player, REMOVE_KEY)
    local remaining = {}
    local cancelled = 0
    for i = 1, pending do
        local entry = queue[i]
        local x, y = parseCoord(entry)
        if not x then
            print("[t3VehicleDrop] Dropping malformed queued marker: " .. tostring(entry))
        elseif dropEntry(removeQueue, entry) then
            -- 찍기도 전에 회수된 지점. 찍지 않고 양쪽 큐에서 같이 버린다.
            cancelled = cancelled + 1
        elseif not addSymbolNow(x, y) then
            remaining[#remaining + 1] = entry
        end
    end

    player:getModData()[QUEUE_KEY] = remaining
    print("[t3VehicleDrop] Marker queue flushed (" .. (pending - #remaining - cancelled)
        .. " placed, " .. cancelled .. " cancelled, " .. #remaining .. " still pending)")
end

-- 제거 대기 좌표를 처리한다. 월드맵을 열 때마다 돈다.
function t3VehicleDropMarker.sweepRemovals(player)
    if not player then return end

    local removeQueue = getList(player, REMOVE_KEY)
    local pending = #removeQueue
    if pending == 0 then return end

    local remaining = {}
    local cleared = 0
    for i = 1, pending do
        local entry = removeQueue[i]
        local x, y = parseCoord(entry)
        if not x then
            print("[t3VehicleDrop] Dropping malformed pending removal: " .. tostring(entry))
        else
            local removed, ok = removeSymbolsAt(x, y)
            if not ok then
                remaining[#remaining + 1] = entry
            elseif removed > 0 then
                cleared = cleared + 1
                print("[t3VehicleDrop] Deferred map symbol removed (" .. entry .. ", count=" .. removed .. ")")
            else
                -- API는 정상인데 대상이 없음 = 이미 없어졌거나 플레이어가 직접 지웠음.
                -- 계속 들고 있어봐야 매번 헛스캔이라 여기서 버린다.
                print("[t3VehicleDrop] Pending removal target no longer exists, discarding (" .. entry .. ")")
            end
        end
    end

    player:getModData()[REMOVE_KEY] = remaining
    if cleared > 0 or #remaining > 0 then
        print("[t3VehicleDrop] Removal sweep done (" .. cleared .. " cleared, " .. #remaining .. " still pending)")
    end
end

-- 외부 진입점. 월드맵이 준비돼 있으면 즉시, 아니면 큐에 적재.
function t3VehicleDropMarker.place(player, x, y)
    if not player then return end
    dropLegacyData(player)

    if addSymbolNow(x, y) then return end

    local queue = getList(player, QUEUE_KEY)
    pushCapped(queue, coordStr(x, y), "Marker queue")

    print("[t3VehicleDrop] World map not ready, marker queued ("
        .. tostring(x) .. "," .. tostring(y) .. "), pending=" .. #queue)
end

-- 낙하산을 회수(차량 최초 탑승)했을 때 대응하는 투하 지점 마커를 지운다.
function t3VehicleDropMarker.remove(player, x, y)
    if not player then return end
    dropLegacyData(player)

    local entry = coordStr(x, y)

    -- 아직 큐에 대기 중이면(맵을 한 번도 안 열어서 화면에 나온 적조차 없음) 큐에서만 빼면 끝.
    if dropEntry(getList(player, QUEUE_KEY), entry) then
        print("[t3VehicleDrop] Pending marker cancelled before it was ever shown (" .. entry .. ")")
        return
    end

    local removed, ok = removeSymbolsAt(x, y)
    if not ok then
        -- 월드맵 인스턴스가 없어 지금은 못 지운다. 다음에 맵을 열 때 처리한다.
        pushCapped(getList(player, REMOVE_KEY), entry, "Removal queue")
        print("[t3VehicleDrop] World map not ready, marker removal deferred (" .. entry .. ")")
        return
    end

    if removed > 0 then
        print("[t3VehicleDrop] Map symbol removed (" .. entry .. ", count=" .. removed .. ")")
    else
        print("[t3VehicleDrop] No matching map symbol found (" .. entry
            .. ") -- already removed, erased by the player, or moved with the map tool")
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
        -- 인스턴스 생성 실패(IsAllowed false 등)까지 감안해 각 함수에서 다시 검사한다.
        local player = getSpecificPlayer(playerNum)
        if player then
            -- 제거를 먼저 돌려야, 배치 대기와 제거 대기가 같은 좌표로 겹쳤을 때
            -- 찍었다 지우는 헛일을 안 한다 (flush 쪽에서 cancelled로 처리됨).
            t3VehicleDropMarker.sweepRemovals(player)
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
