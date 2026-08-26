-- t3VehicleDrop: vehicle_drop donation feature (vehicle_kit 스텁 대체).
-- 후원 시 "vehicle_drop_kit" 아이템 지급 -> 플레이어가 우클릭으로 개봉(레시피)
-- -> 이 파일의 OpenKit이 실행되어 플레이어 기준 가장 가까운 실외 타일을 찾고
-- 그 자리에 차량을 무작위로 소환한다.
--
-- 차종 선택 규칙 (pickVehicleType):
--   샌드박스 VehicleDrop_Source(드롭다운)로 기본 풀을 하나 정하고,
--   거기에 VehicleDrop_Pool(수동 입력)을 무조건 합집합으로 얹어 무작위 선택.
--     1 = 바닐라 차량만 / 2 = 모드 차량만 / 3 = 바닐라+모드 / 4 = 군용 차량만
--   수동 입력은 드롭다운 필터를 무시한다(직접 적은 건 무조건 채택).
--   최종 후보가 0개면 소환하지 않고 로그만 남긴다.
--
-- 실제 addVehicleDebug 호출(t3VehicleDrop.spawnVehicle)은
-- server/t3VehicleDropSpawner.lua 에 있다 (솔로/서버에서만 로드됨).
-- 이 파일(shared)은 모든 realm에서 로드되므로 recipe의 OnCreate 대상이 될 수 있다.
--
-- 솔로: OpenKit -> spawnVehicle 직접 호출 (같은 프로세스에 server 파일도 로드돼있음)
-- MP: OpenKit -> sendClientCommand로 서버에 좌표/차종 전달 -> 서버가 spawnVehicle 실행
--    (InsurgentStartLUV의 AirdroppedLUV 구조와 동일한 패턴)

t3VehicleDrop = t3VehicleDrop or {}

-- findDropSquare는 플레이어가 실제로 키트를 크래프팅해야만 호출되므로, 그 시점엔
-- 세이브 로드+샌드박스 파싱이 이미 끝난 뒤다. SandboxVars 자체는 Lua VM 부팅 시점에
-- media/lua/shared/Sandbox/SandboxVars.lua(require "Sandbox/Survival")로 즉시 채워지고,
-- 우리 옵션(PongDu.VehicleDrop_MinDistance/MaxDistance)도 게임 시작 시 병합되므로
-- 이 경로에서는 nil-guard나 별도 기본값 없이 바로 읽어도 안전하다.
-- MaxDistance < MinDistance로 잘못 설정된 경우 addVehicleDebug까지 안 가고
-- 여기서 서로 바꿔 방어한다 (ZombRandFloat(min, max)에 min > max를 넘기면 오동작).
local function getSearchRadius()
    local minR = SandboxVars.PongDu.VehicleDrop_MinDistance
    local maxR = SandboxVars.PongDu.VehicleDrop_MaxDistance
    if maxR < minR then
        print("[t3VehicleDrop] VehicleDrop_MaxDistance(" .. maxR .. ") < MinDistance(" .. minR .. "), swapping")
        minR, maxR = maxR, minR
    end
    return minR, maxR
end

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

local MAX_PLACEMENT_ATTEMPTS = 300 -- 무작위 샘플링 시도 횟수 상한

-- 플레이어 중심 도넛(반경 MIN~MAX) 안에서 완전 무작위 좌표를 샘플링.
-- 예전 링 순차 스캔은 항상 북서쪽부터 훑어서 연속 소환 시 링을 따라
-- 규칙적으로 배치되는 패턴이 눈에 띄는 문제가 있었다 (무작위 각도+거리로 대체).
-- isValidDropArea의 중심 선검사 덕에 미로드/실내 후보는 즉시 탈락하므로
-- 300회 시도해도 비용은 낮다.
local function findDropSquare(player)
    local cell = getCell()
    local pz = 0 -- 항상 지상 기준으로 탐색 (옥상/발코니에서 열어도 차는 지상에 떨어져야 함)
    local px = math.floor(player:getX())
    local py = math.floor(player:getY())
    local minR, maxR = getSearchRadius()

    for attempt = 1, MAX_PLACEMENT_ATTEMPTS do
        local dist  = ZombRandFloat(minR, maxR)
        local angle = ZombRandFloat(0, 6.2831853) -- 2*pi
        local cx = px + math.floor(math.cos(angle) * dist + 0.5)
        local cy = py + math.floor(math.sin(angle) * dist + 0.5)
        if isValidDropArea(cell, cx, cy, pz) then
            print("[t3VehicleDrop] Random placement found (attempt " .. attempt .. ", " .. cx .. "," .. cy .. ")")
            return cell:getGridSquare(cx, cy, pz)
        end
    end

    print("[t3VehicleDrop] Random sampling failed after " .. MAX_PLACEMENT_ATTEMPTS .. " attempts (" .. minR .. "~" .. maxR .. " tiles), forcing spawn at player position")
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

-- VehicleDrop_Pool ("Base.A;Base.B;Base.C") 파싱.
-- 스크립트가 실제 존재하는 항목만 채택 (오타로 addVehicleDebug가 터지는 것 방지 + 원인 로그).
local function collectPoolVehicles()
    local pool = SandboxVars.PongDu.VehicleDrop_Pool

    local list = {}
    if pool ~= "" then
        for token in string.gmatch(pool, "[^;]+") do
            local trimmed = token:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                if getVehicleScript(trimmed) then
                    if hasDriverSeat(trimmed) then
                        list[#list + 1] = trimmed
                    else
                        print("[t3VehicleDrop] Pool entry excluded (no driver seat): " .. trimmed)
                    end
                else
                    print("[t3VehicleDrop] Pool entry excluded (no vehicle script): " .. trimmed)
                end
            end
        end
    end
    return list
end

-- 코드 레벨 하드 차단 목록.
-- 지상에 떨어뜨려봐야 못 쓰는 차량(수상 전용 보트), 차량 형태를 빌린 월드 오브젝트
-- (난파선/보급상자), 그리고 우리 모드가 내부 연출용으로 쓰는 차량을 막는다.
-- 샌드박스 옵션 default에 몰아넣으면 설정창이 지저분해지고 운영자가 실수로 지울 수 있어
-- 코드로 고정한다. 운영자가 추가로 막고 싶은 건 VehicleDrop_ExcludePool에 적으면 되고,
-- 그쪽 값은 이 목록에 얹혀서 같이 적용된다 (이 목록을 해제할 수단은 두지 않는다).
--
-- 여기 적힌 게 전부 실제로 풀에 들어올 수 있는 건 아니다. 승객석이 없는 항목
-- (트레일러, 난파선 등)은 hasDriverSeat()에서 이미 걸러지지만, 판정을 스크립트 정의에
-- 의존하고 있어 모드 업데이트로 좌석이 생기면 새어나올 수 있으므로 같이 못박아둔다.
local HARD_EXCLUDED = {
    -- PongDu 자체 화력 지원 차량 (드론/헬기 실체)
    ["Base.PongDuDrone"] = true,
    ["Base.PongDuHeli"] = true,

    -- 헬기 계열 워크샵 차량 (동체/꼬리 파트 포함)
    ["Base.UH60Green"] = true,
    ["Base.UH60GreenFuselage"] = true,
    ["Base.UH60GreenTail"] = true,
    ["Base.UH60Desert"] = true,
    ["Base.UH60DesertFuselage"] = true,
    ["Base.UH60DesertTail"] = true,
    ["Base.UH60Medevac"] = true,
    ["Base.UH60MedevacFuselage"] = true,
    ["Base.Bell206LBMW"] = true,
    ["Base.Bell206LBMWFuselage"] = true,
    ["Base.Bell206LBMWTail"] = true,
    ["Base.Bell206Police"] = true,
    ["Base.Bell206PoliceFuselage"] = true,
    ["Base.Bell206PoliceTail"] = true,
    ["Base.Bell206Survivalist"] = true,
    ["Base.Bell206SurvivalistFuselage"] = true,
    ["Base.Bell206SurvivalistTail"] = true,

    -- 보급상자 오브젝트 (차량 스크립트로 정의돼 있음)
    ["Base.FEMASupplyDrop"] = true,
    ["Base.SurvivorSupplyDrop"] = true,

    -- Autotsar Motorclub: 수상바이크 (AquaConfig.Boats 등록 = 수상 전용)
    ["Base.AMC_Waverunner"] = true,
    ["Base.AMC_Waverunner_Ground"] = true,

    -- Aquatsar Yacht Club: 보트 본체 및 육상 변형체.
    -- _Ground 변형체는 트레일러에서 내려 육지에 둔 상태를 표현하는 것이라
    -- 그 자체로 주행 가능한 차량이 아니다.
    ["Base.BoatMotor"] = true,
    ["Base.BoatMotor_Ground"] = true,
    ["Base.BoatSailingYacht"] = true,
    ["Base.BoatSailingYacht_Ground"] = true,
    ["Base.BoatZeroPatient"] = true,

    -- Aquatsar Yacht Club: 난파선 오브젝트
    ["Base.BoatSailingYacht_shipwreckland"] = true,
    ["Base.BoatSailingYacht_shipwreckwater"] = true,

    -- Aquatsar Yacht Club: 보트 운반용 트레일러
    ["Base.TrailerForBoat"] = true,
    ["Base.TrailerWithBoat"] = true,
    ["Base.TrailerWithBoatMotor"] = true,
    ["Base.TrailerWithBoatSailingYacht"] = true,

    -- Autotsar Motorclub: 수상바이크 운반용 트레일러
    ["Base.TrailerAMCWaverunner"] = true,
    ["Base.TrailerAMCWaverunnerWithBody"] = true,
}

-- 하드 차단 목록 + VehicleDrop_ExcludePool("Base.A;Base.B") 파싱 결과 -> lookup set.
-- 존재하지 않는 fullType을 적어도 에러 없이 무시(오타 방어 목적이 아니라
-- 순수 차단 목록이므로 getVehicleScript/hasDriverSeat 검증은 하지 않는다).
local function collectExcludePool()
    local set = {}
    for fullType, _ in pairs(HARD_EXCLUDED) do
        set[fullType] = true
    end

    local pool = SandboxVars.PongDu.VehicleDrop_ExcludePool
    if pool ~= "" then
        for token in string.gmatch(pool, "[^;]+") do
            local trimmed = token:match("^%s*(.-)%s*$")
            if trimmed ~= "" then
                set[trimmed] = true
            end
        end
    end
    return set
end

-- 바닐라 B41 차량 화이트리스트 (media/scripts/vehicles 전수 기준, burnt/smashed 변형 제외 45종).
-- 모드 차량 판별은 "이 목록에 없으면 모드차"라는 소거법이라 목록이 완전해야 성립한다.
-- VehicleZoneDistribution 기반 수집은 존 미등록 차량(ModernCar_ez 등 3종)을 놓치므로
-- 스크립트 파일 정의를 직접 훑어 만든 목록을 쓴다. B42로 올라가면 재검증 필요.
local VANILLA_VEHICLES = {
    ["Base.CarLights"] = true,
    ["Base.CarLightsPolice"] = true,
    ["Base.CarLuxury"] = true,
    ["Base.CarNormal"] = true,
    ["Base.CarStationWagon"] = true,
    ["Base.CarStationWagon2"] = true,
    ["Base.CarTaxi"] = true,
    ["Base.CarTaxi2"] = true,
    ["Base.ModernCar"] = true,
    ["Base.ModernCar02"] = true,
    ["Base.ModernCar_Martin"] = true,
    ["Base.ModernCar_ez"] = true,
    ["Base.OffRoad"] = true,
    ["Base.PickUpTruck"] = true,
    ["Base.PickUpTruckLights"] = true,
    ["Base.PickUpTruckLightsFire"] = true,
    ["Base.PickUpTruckMccoy"] = true,
    ["Base.PickUpVan"] = true,
    ["Base.PickUpVanLights"] = true,
    ["Base.PickUpVanLightsFire"] = true,
    ["Base.PickUpVanLightsPolice"] = true,
    ["Base.PickUpVanMccoy"] = true,
    ["Base.SUV"] = true,
    ["Base.SmallCar"] = true,
    ["Base.SmallCar02"] = true,
    ["Base.SportsCar"] = true,
    ["Base.SportsCar_ez"] = true,
    ["Base.StepVan"] = true,
    ["Base.StepVanMail"] = true,
    ["Base.StepVan_Heralds"] = true,
    ["Base.StepVan_Scarlet"] = true,
    ["Base.Trailer"] = true,
    ["Base.TrailerAdvert"] = true,
    ["Base.TrailerCover"] = true,
    ["Base.Van"] = true,
    ["Base.VanAmbulance"] = true,
    ["Base.VanRadio"] = true,
    ["Base.VanRadio_3N"] = true,
    ["Base.VanSeats"] = true,
    ["Base.VanSpecial"] = true,
    ["Base.VanSpiffo"] = true,
    ["Base.Van_KnoxDisti"] = true,
    ["Base.Van_LectroMax"] = true,
    ["Base.Van_MassGenFac"] = true,
    ["Base.Van_Transit"] = true,
}

-- 설치된 모든 차량 스크립트의 풀네임 수집.
-- ScriptManager:getAllVehicleScripts()는 내부 공유 임시 리스트(vehicleScriptTempList)를
-- clear() 후 재사용해 반환하므로, 반환값을 들고 있지 말고 즉시 문자열만 복사해야 한다.
local function collectAllVehicles()
    local sm = getScriptManager and getScriptManager()
    if not sm then return {} end
    local scripts = sm:getAllVehicleScripts()
    local list = {}
    if not scripts then return list end
    for i = 0, scripts:size() - 1 do
        local sc = scripts:get(i)
        local fullType = sc and sc:getFullName()
        if fullType and fullType ~= "" then
            list[#list + 1] = fullType
        end
    end
    return list
end

-- 파손/전소 변형 제외. 이름 접미사 규칙(Burnt / Smashed*)에 의존하므로
-- 같은 규칙을 안 따르는 모드 차량은 걸러지지 않는다(알려진 한계).
-- 바닐라 쪽은 VANILLA_VEHICLES가 애초에 정상 차량만 담고 있어 영향 없음.
local function isWreckVariant(fullType)
    local lower = string.lower(fullType)
    if string.find(lower, "burnt", 1, true) then return true end
    if string.find(lower, "smashed", 1, true) then return true end
    return false
end

local SOURCE_VANILLA  = 1
local SOURCE_MOD      = 2
local SOURCE_BOTH     = 3
local SOURCE_MILITARY = 4

-- 드롭다운 값에 해당하는 기본 풀 구성.
local function buildSourcePool(source)
    if source == SOURCE_MILITARY then
        return collectMilitaryVehicles()
    end

    local list = {}
    for _, fullType in ipairs(collectAllVehicles()) do
        if not isWreckVariant(fullType) then
            local isVanilla = VANILLA_VEHICLES[fullType] == true
            local accept = (source == SOURCE_BOTH)
                or (source == SOURCE_VANILLA and isVanilla)
                or (source == SOURCE_MOD and not isVanilla)
            if accept and hasDriverSeat(fullType) then
                list[#list + 1] = fullType
            end
        end
    end
    return list
end

-- 차종 선택: 드롭다운 풀 + 수동 입력 풀의 합집합에서, 제외 목록을 뺀 뒤 무작위.
-- 수동 입력(VehicleDrop_Pool)은 드롭다운 필터를 타지 않는다 -- "큰 범위는 드롭다운으로
-- 정하고, 거기 없는 특정 차를 손으로 더 얹는다"가 이 옵션의 용도이기 때문.
-- 제외 목록(VehicleDrop_ExcludePool)은 반대로 드롭다운/수동 입력 둘 다보다 우선한다 --
-- 화력 지원용 드론/헬기, 수상 전용 보트처럼 "모드 차량만"에 걸려도 절대 일반 소환
-- 풀에 섞이면 안 되는 항목은 HARD_EXCLUDED로 코드에서 못박아뒀고, 운영자가 적은
-- VehicleDrop_ExcludePool은 거기에 얹혀서 함께 적용된다.
-- 후보가 0개면 nil을 반환하고, 호출부(OpenKit)가 소환을 취소한다.
local function pickVehicleType()
    local source = SandboxVars.PongDu.VehicleDrop_Source

    local merged, seen = {}, {}
    for _, fullType in ipairs(buildSourcePool(source)) do
        if not seen[fullType] then seen[fullType] = true; merged[#merged + 1] = fullType end
    end
    for _, fullType in ipairs(collectPoolVehicles()) do
        if not seen[fullType] then seen[fullType] = true; merged[#merged + 1] = fullType end
    end

    local exclude = collectExcludePool()
    local filtered = {}
    for _, fullType in ipairs(merged) do
        if exclude[fullType] then
            print("[t3VehicleDrop] Candidate excluded (ExcludePool): " .. fullType)
        else
            filtered[#filtered + 1] = fullType
        end
    end

    if #filtered == 0 then
        print("[t3VehicleDrop] No candidate vehicles for source=" .. tostring(source)
            .. " (manual pool empty too, or all excluded), spawn cancelled")
        return nil
    end

    print("[t3VehicleDrop] Candidate pool size=" .. #filtered
        .. " (source=" .. tostring(source) .. ", excluded=" .. (#merged - #filtered) .. ")")
    return filtered[ZombRand(#filtered) + 1]
end

-- 월드맵(M키)에 투하 지점 심볼을 그린다.
-- 심볼은 개봉한 플레이어 본인의 맵에만 표시되고, 바닐라 맵 심볼 저장 체계에 따라 영구 보존된다.
--
-- 실제 구현은 client/VehicleDropMapMarker.lua 로 옮겼다. 심볼 저장소를 건드리려면
-- UIWorldMap 인스턴스가 필요한데, 플레이어가 월드맵을 아직 안 열었으면 인스턴스가 없어
-- 마커가 통째로 유실됐기 때문(세션당 첫 개봉에서만 발생). 이제 인스턴스가 없으면
-- 좌표를 큐에 쌓아두고 플레이어가 맵을 여는 시점에 반영한다.
--
-- 이 파일은 shared라 데디 서버에서도 로드되지만 client 파일은 서버에 없으므로,
-- isServer() 가드와 네임스페이스 존재 확인을 둘 다 둔다.
local function drawDropMarker(player, x, y)
    if isServer() then return end
    if not t3VehicleDropMarker then
        print("[t3VehicleDrop] t3VehicleDropMarker not loaded, skipping map symbol")
        return
    end
    t3VehicleDropMarker.place(player, x, y)
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
    if not vehicleType then
        -- OnCreate는 크래프팅이 끝난 뒤에 호출되므로 이 시점엔 키트가 이미 소모돼 있다.
        -- 여기서 그냥 return하면 후원자는 아이템만 잃고 아무것도 못 받으므로 키트를 돌려준다.
        -- 후원자 표기(이름 + modData.t3Donor)도 rewardManager의 최초 지급 시점과
        -- 동일하게 복원해야 재개봉 시 키 이름에 후원자가 붙는다.
        local kit = player:getInventory():AddItem("t3chzzkDonation.vehicle_drop_kit")
        if kit then
            if donor ~= "" then
                kit:setName(donor .. "'s " .. kit:getDisplayName())
            end
            kit:getModData().t3Donor = donor
            print("[t3VehicleDrop] Kit refunded (donor: " .. tostring(donor) .. ")")
        else
            print("[t3VehicleDrop] Kit refund FAILED (donor: " .. tostring(donor) .. ")")
        end
        player:Say(getText("IGUI_donation_vehicle_drop_nopool"))
        return
    end
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

    -- 개봉 라디오 사운드(RadioTalk)는 레시피 Sound 필드로 재생됨.
    -- 볼륨 절반 처리는 client/VehicleDropCraftSound.lua 에서 ISCraftAction:start 훅으로 처리.

    local sx, sy = sq:getX(), sq:getY()
    player:Say(getText("IGUI_donation_vehicle_drop_location",
        string.format("%d", sx), string.format("%d", sy)))
    drawDropMarker(player, sx, sy)
end
