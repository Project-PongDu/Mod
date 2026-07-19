-- t3VehicleDrop: vehicle_drop donation feature (vehicle_kit 스텁 대체).
-- 후원 시 "vehicle_drop_kit" 아이템 지급 -> 플레이어가 우클릭으로 개봉(레시피)
-- -> 이 파일의 OpenKit이 실행되어 플레이어 기준 가장 가까운 실외 타일을 찾고
-- 그 자리에 차량을 무작위로 소환한다.
--
-- 차종 선택 규칙 (pickVehicleType):
--   1) military 존에 모드가 등록한 차량이 하나라도 있으면 그 목록에서만 선택.
--      (바닐라 B41에는 military 존 자체가 없으므로, 여기 든 차량은 전부 모드 추가 군용차.)
--   2) military 존에 등록된 차량이 하나도 없으면 샌드박스 VehicleDrop_Pool에서 선택.
--
-- 실제 addVehicleDebug 호출(t3VehicleDrop.spawnVehicle)은
-- server/t3VehicleDropSpawner.lua 에 있다 (솔로/서버에서만 로드됨).
-- 이 파일(shared)은 모든 realm에서 로드되므로 recipe의 OnCreate 대상이 될 수 있다.
--
-- 솔로: OpenKit -> spawnVehicle 직접 호출 (같은 프로세스에 server 파일도 로드돼있음)
-- MP: OpenKit -> sendClientCommand로 서버에 좌표/차종 전달 -> 서버가 spawnVehicle 실행
--    (InsurgentStartLUV의 AirdroppedLUV 구조와 동일한 패턴)

t3VehicleDrop = t3VehicleDrop or {}

local MIN_SEARCH_RADIUS = 50 -- 플레이어로부터 최소 이 거리(타일) 이상 떨어진 곳에만 소환
local MAX_SEARCH_RADIUS = 100 -- 이 반경 안에서 자리를 못 찾으면 최후 수단으로 플레이어 발밑에 소환

-- 실외 + 차량 없음 + 물 아님 + 장애물 없음(플레이어/좀비 제외)
local function isValidDropSquare(sq)
    if not sq then return false end
    if not sq:isOutside() then return false end
    if sq:getVehicleContainer() then return false end
    if not sq:isFree(false) then return false end
    local floor = sq:getFloor()
    if floor and floor:getSprite() and floor:getSprite():getProperties():Is(IsoFlagType.water) then
        return false
    end
    return true
end

local AREA_RADIUS = 7 -- 5x5 = 중심 기준 -2~+2

-- (cx,cy) 중심 5x5 타일이 전부 유효한 실외공간인지 확인
local function isValidDropArea(cell, cx, cy, pz)
    -- 중심 스퀘어부터 검사: 미로드 지역(nil)이나 실내면 전체 스캔 없이 즉시 탈락
    if not isValidDropSquare(cell:getGridSquare(cx, cy, pz)) then
        return false
    end
    for dx = -AREA_RADIUS, AREA_RADIUS do
        for dy = -AREA_RADIUS, AREA_RADIUS do
            local sq = cell:getGridSquare(cx + dx, cy + dy, pz)
            if not isValidDropSquare(sq) then
                return false
            end
        end
    end
    return true
end

-- 플레이어 좌표를 중심으로 링 단위(체비셰프 거리)로 확장 탐색.
-- 5x5 타일이 전부 유효해야 통과하므로 InsurgentStartLUV의 무검증 배치보다 훨씬 안전하다.
local function findDropSquare(player)
    local cell = getCell()
    local pz = 0 -- 항상 지상 기준으로 탐색 (옥상/발코니에서 열어도 차는 지상에 떨어져야 함)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())

    for r = MIN_SEARCH_RADIUS, MAX_SEARCH_RADIUS do
        for dx = -r, r do
            for dy = -r, r do
                if math.max(math.abs(dx), math.abs(dy)) == r then
                    local cx, cy = px + dx, py + dy
                    if isValidDropArea(cell, cx, cy, pz) then
                        return cell:getGridSquare(cx, cy, pz)
                    end
                end
            end
        end
    end

    print("[t3VehicleDrop] " .. MIN_SEARCH_RADIUS .. "~" .. MAX_SEARCH_RADIUS .. " 타일 범위 내 실외 자리를 못 찾음, 발밑에 강제 소환")
    return player:getCurrentSquare()
end

-- fullType의 스크립트 조회.
-- ScriptManager:getVehicle는 내부에서 getModule+getItemName으로 "Module.Type"을
-- 알아서 분해하므로("Base.67commando" -> Base 모듈의 "67commando"),
-- military 존 등록 키(풀네임)를 그대로 넘기면 된다.
local function getVehicleScript(fullType)
    local sm = getScriptManager and getScriptManager()
    if not sm then return nil end
    return sm:getVehicle(fullType)
end

-- 운전석(좌석 인덱스 0) 보유 여부 확인.
-- BaseVehicle:isDriver(chr)가 getSeat(chr) == 0 으로 정의돼 있으므로,
-- 스크립트에 0번 Passenger 슬롯이 정의돼 있어야 실제로 운전 가능한 차량이다.
-- RV트레일러처럼 탑승은 가능해도 0번 슬롯(운전석)이 없으면 여기서 걸러진다.
-- 스크립트 조회 자체가 안 되면 "확인 불가"로 보고 배제하지 않는다(과잉 제외 방지).
local function hasDriverSeat(fullType)
    local script = getVehicleScript(fullType)
    if not script then return true end

    local count = script:getPassengerCount()
    if not count or count <= 0 then return false end

    return script:getPassenger(0) ~= nil
end

-- military 존에 모드가 등록한 차량 풀네임("Base.67commando" 등) 목록 수집.
-- 바닐라 B41에는 military 존이 없으므로, 여기 값이 있으면 전부 모드가 추가한 군용차.
-- 운전석이 없는 항목(트레일러/피견인체 등)은 보급 리워드로 부적합하므로 제외한다.
local function collectMilitaryVehicles()
    local list = {}
    local vzd = VehicleZoneDistribution
    local mil = vzd and vzd.military
    local vehicles = mil and mil.vehicles
    if vehicles then
        for fullType, _ in pairs(vehicles) do
            if hasDriverSeat(fullType) then
                list[#list + 1] = fullType
            end
        end
    end
    return list
end

-- VehicleDrop_Pool ("Base.A;Base.B;Base.C") 파싱 후 무작위 선택.
local function pickFromSandboxPool()
    local sv = SandboxVars and SandboxVars.PongDu
    local pool = sv and sv.VehicleDrop_Pool

    local list = {}
    if pool and pool ~= "" then
        for token in string.gmatch(pool, "[^;]+") do
            local trimmed = token:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                list[#list + 1] = trimmed
            end
        end
    end

    if #list == 0 then
        return "Base.PickupTruck" -- 샌드박스 값이 비어있을 때의 최후 fallback
    end
    return list[ZombRand(#list) + 1]
end

-- 차종 선택: military 존 군용차가 있으면 그 목록에서만, 없으면 샌드박스 풀에서.
local function pickVehicleType()
    local military = collectMilitaryVehicles()
    if #military > 0 then
        return military[ZombRand(#military) + 1]
    end
    return pickFromSandboxPool()
end

-- 월드맵(M키)에 투하 지점 심볼을 그린다. (BATMAN_EHE_MILITARY_DROP의 drawSymbol 패턴)
-- 심볼은 개봉한 플레이어 본인의 맵에만 표시되고, 바닐라 맵 심볼 저장 체계에 따라 영구 보존된다.
-- 이 파일은 shared라 데디 서버에서도 로드되지만, OpenKit 자체가 클라이언트에서만
-- 실행되므로 (레시피 OnCreate) ISWorldMap이 없는 환경 방어만 해두면 된다.
local MARKER_SYMBOL = "Boat" -- 바닐라 MapSymbolDefinitions 등록 심볼
local MARKER_R, MARKER_G, MARKER_B = 0.1, 0.3, 0.9

local function drawDropMarker(player, x, y)
    if isServer() then return end
    if not ISWorldMap or not ISWorldMap.ShowWorldMap then
        print("[t3VehicleDrop] ISWorldMap 없음, 맵 심볼 표시 생략")
        return
    end

    local playerNum = player:getPlayerNum()
    if not ISWorldMap_instance then
        -- 최초 1회 인스턴스 강제 생성 트릭 (참고 모드와 동일 패턴)
        ISWorldMap.ShowWorldMap(playerNum)
        ISWorldMap.HideWorldMap(playerNum)
    end
    if not ISWorldMap_instance then
        print("[t3VehicleDrop] ISWorldMap_instance 생성 실패, 맵 심볼 표시 생략")
        return
    end

    local symbolsAPI = ISWorldMap_instance.mapAPI and ISWorldMap_instance.mapAPI:getSymbolsAPI()
    if not symbolsAPI then
        print("[t3VehicleDrop] symbolsAPI 조회 실패, 맵 심볼 표시 생략")
        return
    end

    local sym = symbolsAPI:addTexture(MARKER_SYMBOL, x, y)
    sym:setRGBA(MARKER_R, MARKER_G, MARKER_B, 1.0)
    sym:setAnchor(0.5, 0.5)
    sym:setScale((ISMap and ISMap.SCALE) or 0.666)
    print("[t3VehicleDrop] 맵 심볼 표시 완료 (" .. tostring(x) .. "," .. tostring(y) .. ")")
end

-- 소모된 kit 아이템의 modData에 심어둔 후원자 이름을 읽는다 (t3RandomWeapon.lua와 동일 패턴).
local function findDonor(items)
    if not items then return "" end
    for i = 0, items:size() - 1 do
        local it = items:get(i)
        if it and it.getModData then
            local donor = it:getModData().t3Donor
            if donor and donor ~= "" then return donor end
        end
    end
    return ""
end

-- Recipe OnCreate handler: OnCreate:t3VehicleDrop.OpenKit
function t3VehicleDrop.OpenKit(items, result, player)
    if not player then return end

    local donor       = findDonor(items)
    local vehicleType = pickVehicleType()
    local sq          = findDropSquare(player)

    if not isClient() and not isServer() then
        -- 솔로: server/t3VehicleDropSpawner.lua 도 같은 프로세스에 로드되어 있음
        t3VehicleDrop.spawnVehicle(player, sq:getX(), sq:getY(), sq:getZ(), vehicleType, donor)
    elseif isClient() then
        -- MP: 실제 소환은 서버 권한으로 처리
        sendClientCommand("PongDuVehicleDrop", "SpawnVehicleDrop", {
            x = sq:getX(), y = sq:getY(), z = sq:getZ(),
            vehicleType = vehicleType,
            sender = donor,
        })
    end

    local sx, sy = sq:getX(), sq:getY()
    player:Say(getText("IGUI_donation_vehicle_drop_location",
        string.format("%d", sx), string.format("%d", sy)))
    drawDropMarker(player, sx, sy)
end
