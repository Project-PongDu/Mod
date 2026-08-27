-- t3VehicleDropMarker: 차량보급 투하 지점을 월드맵 심볼로 남기고, 회수 시 지운다.
--
-- [왜 재조정(sync) 방식인가]
-- 심볼 저장소(MapItem.getSingleton()의 WorldMapSymbols)는 미니맵과 큰맵이 공유하는
-- 자바 객체 하나뿐이고, Lua에서는 UIWorldMap 인스턴스를 거쳐야만 건드릴 수 있다.
-- 문제는 이 저장소를 우리만 쓰는 게 아니라는 점이다.
--
-- 예: FactionAnnotations는 ISWorldMap.ShowWorldMap / ISWorldMap:close를 훅해서
--   - 큰맵을 열 때: 저장소를 clear() 하고 자기 ModData 스냅샷으로 통째로 재구축
--   - 큰맵을 닫을 때: 현재 저장소를 그 스냅샷에 덮어씀
-- 을 한다. 우리 마커는 큰맵이 닫힌 상태(차량 소환 / 승차 시점)에서 추가·제거되므로
-- 스냅샷에 반영될 기회가 없고, 다음 오픈에서 스냅샷 기준으로 전부 롤백됐다.
-- "지웠는데 맵을 열면 되살아난다", "찍었는데 맵을 열면 사라진다"가 둘 다 여기서 나온다.
--
-- 그래서 "찍는다/지운다"는 일회성 명령을 버리고, 살아있어야 할 좌표 목록 하나를
-- 권위로 두고 저장소를 거기에 맞추는 방식으로 바꿨다. sync()는 몇 번을 호출해도
-- 결과가 같으므로(멱등), 외부 모드가 저장소를 어떻게 갈아엎든 다음 sync에서 수렴한다.
-- 특정 모드를 이름으로 알고 있을 필요도, 그쪽 내부 함수를 부를 필요도 없다.
--
-- [훅 순서]
-- 우리 훅은 OnGameStart에서 건다. 다른 맵 모드들은 보통 파일 로드 시점에 훅을 걸므로
-- 우리 래퍼가 항상 바깥에 놓이고, sync()는 그들의 재구축이 끝난 뒤에 실행된다.

if isServer() then return end

t3VehicleDropMarker = t3VehicleDropMarker or {}

local POINTS_KEY = "t3VehicleDropMarkerPoints" -- 마커가 있어야 할 좌표 목록 (권위)
local POINT_LIMIT = 32 -- 어떤 이유로든 회수 통보가 유실될 때 modData 무한 증식 방지

-- 구버전 키들. 배치 대기 큐 / 제거 대기 큐 / 인덱스 부기 — 전부 폐기됐다.
local LEGACY_KEYS = {
    "t3VehicleDropMarkerActive",
    "t3VehicleDropMarkerQueue",
    "t3VehicleDropMarkerRemove",
}

local MARKER_SYMBOL = "Boat" -- 바닐라 MapSymbolDefinitions 등록 심볼
local MARKER_R, MARKER_G, MARKER_B = 0.1, 0.3, 0.9
-- 바닐라 심볼 UI가 제공하는 색은 검정(0,0,0) / 회색(0.2,0.2,0.2) / 빨강(1,0,0) /
-- 파랑(0,0,1) 네 가지뿐이라, 위 RGB는 플레이어가 직접 만들 수 없다.
-- 덕분에 "심볼ID + RGB"만으로 우리 마커를 좌표와 무관하게 단정할 수 있다.
local COLOR_EPSILON = 0.01

-- 심볼 스케일은 바닐라 펜 심볼과 동일하게 ISMap.SCALE을 쓴다.
-- 예전에 0으로 줬던 적이 있는데, scale <= 0 이면 WorldMapTextureSymbol.render가
-- getDisplayScale을 안 타고 DrawTextureColor로 텍스처 원본 픽셀 크기 고정 렌더를 해서
-- 줌을 바꿔도 아이콘 크기가 안 변한다. 양수 스케일이면 getLayoutWorldScale()이 곱해져
-- 줌에 맞춰 커지고 작아진다 (대신 바닐라와 똑같이 줌 14.5 미만에서는 렌더에서 빠진다).
-- ISMap이 아직 로드 안 된 상황을 대비해 바닐라 기본값(0.666)으로 폴백.
local function getMarkerScale()
    return (ISMap and ISMap.SCALE) or 0.666
end

-- 심볼 API는 UIWorldMap 인스턴스를 거쳐야 얻을 수 있다.
-- 큰맵(ISWorldMap_instance)은 플레이어가 M을 한 번 눌러야 생기지만, 미니맵은 접속
-- 시점부터 살아있고 같은 MapItem.getSingleton() 심볼 저장소를 공유한다
-- (ISMiniMap.lua / ISWorldMap.lua 양쪽 다 mapAPI:setMapItem(MapItem.getSingleton())).
-- 그래서 큰맵이 없으면 미니맵 쪽 API로 대신 쓴다 -- 큰맵을 한 번도 안 연 세션에서도
-- 마커가 바로 뜨고, 샌드박스에서 큰맵만 꺼둔 서버에서도 동작한다.
--
-- 우선순위를 큰맵 > 미니맵으로 고정하는 게 중요하다. WorldMapSymbolsV1은 UI마다 자기
-- 미러 리스트를 따로 들고 있고 removeSymbolByIndex가 공유 리스트와 미러에 같은 인덱스를
-- 쓰기 때문에, 두 API를 섞어 쓰면 인덱스가 어긋나 엉뚱한 심볼이 지워진다.
-- 큰맵이 생긴 뒤로는 계속 큰맵 것만 쓴다. 큰맵 V1은 생성 시 reinit으로 공유 저장소를
-- 스냅샷하므로, 미니맵으로 먼저 찍어둔 심볼도 동기 상태 그대로 인계받는다.
-- 반대로 미니맵을 쓰는 구간에는 큰맵이 아예 없으므로 저장소를 건드릴 주체가 우리뿐이다
-- (바닐라 펜/지우개도, 주석 동기화 모드도 전부 ISWorldMap_instance를 필요로 한다).
--
-- 반환값: 심볼 API, 맵 API, 큰맵을 쓰고 있는지 여부.
local function getSymbolsAPI(player)
    local mapAPI = ISWorldMap_instance and ISWorldMap_instance.mapAPI
    if mapAPI then
        return mapAPI:getSymbolsAPI(), mapAPI, true
    end

    -- 스플릿스크린 대응으로 호출자의 플레이어 번호를 쓴다.
    local playerNum = player and player:getPlayerNum() or 0
    local miniMap = getPlayerMiniMap(playerNum)
    local inner = miniMap and miniMap.inner
    mapAPI = inner and inner.mapAPI
    if not mapAPI then return nil end

    return mapAPI:getSymbolsAPI(), mapAPI, false
end

----------------------------------------------------------------------
-- 좌표 목록 (권위 데이터)
----------------------------------------------------------------------

-- 좌표는 "x,y" 문자열로 저장한다. modData 직렬화에서 중첩 테이블보다 다룰 게 적고,
-- 그대로 비교 키로 쓸 수 있다. 심볼 좌표는 float이라 반올림해서 정수로 정규화한다.
local function coordKey(x, y)
    return tostring(math.floor(x + 0.5)) .. "," .. tostring(math.floor(y + 0.5))
end

local function parseCoord(key)
    local sx, sy = string.match(key, "^(-?%d+),(-?%d+)$")
    if not sx then return nil end
    return tonumber(sx), tonumber(sy)
end

local function getPoints(player)
    local md = player:getModData()
    local list = md[POINTS_KEY]
    if type(list) ~= "table" then
        list = {}
        md[POINTS_KEY] = list
    end
    return list
end

local function indexOf(list, key)
    for i = 1, #list do
        if list[i] == key then return i end
    end
    return nil
end

-- 구버전 잔재 정리. 이제 안 쓰는 키라 남겨두면 세이브만 지저분해진다.
local function dropLegacyData(player)
    local md = player:getModData()
    for i = 1, #LEGACY_KEYS do
        local key = LEGACY_KEYS[i]
        if md[key] ~= nil then
            md[key] = nil
            print("[t3VehicleDrop] Legacy marker data discarded: " .. key)
        end
    end
end

----------------------------------------------------------------------
-- 심볼 저장소 재조정
----------------------------------------------------------------------

local function isOurSymbol(symbol)
    if not symbol then return false end
    if not symbol:isTexture() then return false end
    if symbol:getSymbolID() ~= MARKER_SYMBOL then return false end
    if math.abs(symbol:getRed() - MARKER_R) > COLOR_EPSILON then return false end
    if math.abs(symbol:getGreen() - MARKER_G) > COLOR_EPSILON then return false end
    if math.abs(symbol:getBlue() - MARKER_B) > COLOR_EPSILON then return false end
    return true
end

local function addSymbol(symbolsAPI, x, y)
    local sym = symbolsAPI:addTexture(MARKER_SYMBOL, x, y)
    if not sym then
        print("[t3VehicleDrop] addTexture returned nil for symbol '" .. MARKER_SYMBOL .. "'")
        return false
    end
    sym:setRGBA(MARKER_R, MARKER_G, MARKER_B, 1.0)
    sym:setAnchor(0.5, 0.5)
    sym:setScale(getMarkerScale())
    return true
end

-- 심볼 저장소를 좌표 목록에 맞춘다. 반환값: API 사용 가능 여부.
--
-- 순서가 중요하다. 삭제를 먼저 전부 끝낸 뒤에 추가해야 한다.
-- WorldMapSymbolsV1.removeSymbolByIndex는 공유 리스트와 이 UI 전용 미러 리스트에
-- 같은 인덱스를 쓰는데, 추가와 삭제를 섞으면 스캔 중에 인덱스가 밀린다.
-- 삭제 루프는 역순으로 돌아 뒤쪽이 당겨져도 건너뛰지 않게 한다.
function t3VehicleDropMarker.sync(player)
    if not player then return false end
    dropLegacyData(player)

    local symbolsAPI, mapAPI, isWorldMap = getSymbolsAPI(player)
    if not symbolsAPI then return false end

    local points = getPoints(player)
    local wanted = {}
    for i = 1, #points do
        wanted[points[i]] = true
    end

    -- 1단계: 우리 심볼 중 목록에 없는 것과 중복된 것을 제거
    local present = {}
    local removed = 0
    for i = symbolsAPI:getSymbolCount() - 1, 0, -1 do
        local sym = symbolsAPI:getSymbolByIndex(i)
        if isOurSymbol(sym) then
            local key = coordKey(sym:getWorldX(), sym:getWorldY())
            if not wanted[key] then
                -- 이미 회수된 지점인데 외부 모드가 되살려놨거나, 예전 세이브에 남은 잔재
                symbolsAPI:removeSymbolByIndex(i)
                removed = removed + 1
            elseif present[key] then
                -- 같은 지점에 두 개 이상 쌓인 경우 하나만 남긴다
                symbolsAPI:removeSymbolByIndex(i)
                removed = removed + 1
            else
                present[key] = true
            end
        end
    end

    -- 2단계: 목록에 있는데 심볼이 없는 지점을 추가
    local added = 0
    for i = 1, #points do
        local key = points[i]
        if not present[key] then
            local x, y = parseCoord(key)
            if not x then
                print("[t3VehicleDrop] Malformed marker point, ignoring: " .. tostring(key))
            elseif addSymbol(symbolsAPI, x, y) then
                present[key] = true
                added = added + 1
            end
        end
    end

    if added > 0 or removed > 0 then
        print("[t3VehicleDrop] Map symbols synced (" .. added .. " added, " .. removed
            .. " removed, " .. #points .. " active, via "
            .. (isWorldMap and "world map" or "minimap") .. ")")

        -- 플레이어가 월드맵 옵션에서 심볼 표시를 꺼놨으면 찍어도 화면에 안 나온다.
        -- 임의로 켜주는 건 월권이라 원인 추적용 로그만 남긴다.
        -- 미니맵은 심볼 표시가 기본 꺼짐이라 정상 상태이므로 큰맵일 때만 경고한다.
        if added > 0 and isWorldMap and mapAPI and not mapAPI:getBoolean("Symbols") then
            print("[t3VehicleDrop] World map 'Symbols' option is disabled, markers stay hidden until re-enabled")
        end
    end

    return true
end

----------------------------------------------------------------------
-- 외부 진입점
----------------------------------------------------------------------

-- 투하 지점 마커를 등록한다.
function t3VehicleDropMarker.place(player, x, y)
    if not player then return end
    dropLegacyData(player)

    local key = coordKey(x, y)
    local points = getPoints(player)

    if indexOf(points, key) then
        print("[t3VehicleDrop] Marker point already registered (" .. key .. ")")
    else
        points[#points + 1] = key
        -- 오래된 것부터 버린다 (최근 지점이 더 쓸모 있으므로)
        while #points > POINT_LIMIT do
            print("[t3VehicleDrop] Marker points over limit, dropping oldest: " .. tostring(points[1]))
            table.remove(points, 1)
        end
    end

    if not t3VehicleDropMarker.sync(player) then
        print("[t3VehicleDrop] Marker point registered but no map UI available, will appear once one exists ("
            .. key .. ", " .. #points .. " active)")
    end
end

-- 낙하산을 회수(차량 최초 탑승)했을 때 대응하는 투하 지점 마커를 지운다.
function t3VehicleDropMarker.remove(player, x, y)
    if not player then return end
    dropLegacyData(player)

    local key = coordKey(x, y)
    local points = getPoints(player)
    local at = indexOf(points, key)

    if at then
        table.remove(points, at)
    else
        -- 목록에 없어도 sync는 돌린다. 외부 모드가 되살려놓은 심볼이 있으면
        -- 이번 sync에서 같이 정리되기 때문.
        print("[t3VehicleDrop] Marker point was not registered (" .. key
            .. ") -- already collected, or registered before this save was migrated")
    end

    if not t3VehicleDropMarker.sync(player) then
        print("[t3VehicleDrop] Marker point cleared but no map UI available, will apply once one exists ("
            .. key .. ", " .. #points .. " active)")
    end
end

----------------------------------------------------------------------
-- 훅
----------------------------------------------------------------------

-- 파일 로드 시점이 아니라 OnGameStart에서 거는 이유: 맵 관련 모드들은 보통 파일 로드
-- 시점에 훅을 걸므로, 우리가 늦게 걸어야 래퍼가 바깥에 놓이고 그들의 심볼 재구축이
-- 끝난 뒤에 sync가 돈다.
local function installHooks()
    if t3VehicleDropMarker.hooksInstalled then return end

    if not ISWorldMap or not ISWorldMap.ShowWorldMap then
        print("[t3VehicleDrop] ISWorldMap unavailable, marker sync hook not installed")
        return
    end

    local originalShowWorldMap = ISWorldMap.ShowWorldMap
    ISWorldMap.ShowWorldMap = function(playerNum)
        originalShowWorldMap(playerNum)
        -- 인스턴스 생성 실패(IsAllowed false 등)까지 감안해 sync 안에서 다시 검사한다.
        local player = getSpecificPlayer(playerNum)
        if player then
            t3VehicleDropMarker.sync(player)
        end
    end

    -- 맵 주석을 서버와 동기화하는 모드는 큰맵이 열려 있는 중에도 글로벌 ModData 수신을
    -- 계기로 심볼을 통째로 갈아끼운다. 그 뒤에도 우리 마커가 살아남도록 여기서도 맞춘다.
    -- 이 핸들러도 OnGameStart에서 등록되므로 그쪽 핸들러보다 뒤에 실행된다.
    Events.OnReceiveGlobalModData.Add(function(module, packet)
        if not ISWorldMap_instance then return end
        local player = getPlayer()
        if player then
            t3VehicleDropMarker.sync(player)
        end
    end)

    t3VehicleDropMarker.hooksInstalled = true
    print("[t3VehicleDrop] Map marker sync hooks installed")
end

Events.OnGameStart.Add(installHooks)

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
