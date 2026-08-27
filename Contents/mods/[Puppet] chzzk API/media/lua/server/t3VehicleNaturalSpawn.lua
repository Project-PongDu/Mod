-- t3VehicleNaturalSpawn: 모드 차량의 "월드 자연 생성"을 막는 샌드박스 토글.
--
-- 목적: 좋은 모드 차량을 vehicle_drop 후원으로만 얻을 수 있게 만들고 싶은 서버를 위한 옵션.
-- 기본값은 꺼짐(false)이라, 켜지 않으면 바닐라/모드 어떤 차량의 자연 생성에도 관여하지 않는다.
--
-- 동작 원리 (B41 디컴파일 기준):
--   차량 자연 생성 풀은 Lua 전역 테이블 VehicleZoneDistribution에 들어 있고,
--   zombie.vehicles.VehicleType.init()이 이 테이블을 읽어 자바 캐시(VehicleType.vehicles)로
--   한 번 굳힌 뒤 그 캐시만 쓴다. init()은 IsoChunk가 처음 차량 존을 처리할 때 lazy로 딱 1회
--   호출되므로, "첫 청크 로드 전에 Lua 테이블에서 모드 차량 엔트리를 지우면" 그대로 차단된다.
--   반대로 청크가 이미 로드된 뒤(OnGameStart 등)에 지워봐야 캐시가 이미 만들어져 있어 소용없다.
--
--   존의 vehicles가 통째로 비어도 안전하다 -- IsoChunk.RandomizeModel()이
--   vehiclesDefinition.isEmpty()를 먼저 확인하고 false를 반환하고,
--   VehicleType.getRandomVehicleType()이 nil을 돌려주는 경로에도 호출부 null 체크가 있다.
--
-- 이 파일은 media/lua/server/ 아래 있으므로 솔로와 진짜 서버에서만 로드된다.
-- 차량 자연 생성은 서버(호스트) 권위이므로 MP 클라이언트에서 돌 필요가 없다.

t3VehicleNaturalSpawn = t3VehicleNaturalSpawn or {}

local LOG = "[t3VehicleNaturalSpawn] "

-- 바닐라 B41이 VehicleZoneDistribution에 실제로 등록하는 차량 전체(58종).
-- media/lua/shared/VehicleZoneDefinition.lua 전수 추출 기준이며, burnt 변형까지 포함한다.
--
-- t3VehicleDrop.lua의 VANILLA_VEHICLES(45종)를 재사용하지 않는 이유:
--   그쪽은 "보급으로 줄 만한 정상 차량" 목록이라 burnt/smashed 변형이 빠져 있다.
--   그걸 소거법 기준으로 쓰면 Base.CarNormalBurnt 같은 바닐라 전소차까지 모드차로 오판해
--   trailerpark/junkyard의 전소차 자연 생성이 통째로 사라진다. 용도가 다르므로 목록도 따로 둔다.
--
-- B42로 올라가면 재검증 필요.
local VANILLA_ZONE_VEHICLES = {
    ["Base.AmbulanceBurnt"] = true,
    ["Base.CarLights"] = true,
    ["Base.CarLightsPolice"] = true,
    ["Base.CarLuxury"] = true,
    ["Base.CarNormal"] = true,
    ["Base.CarNormalBurnt"] = true,
    ["Base.CarStationWagon"] = true,
    ["Base.CarStationWagon2"] = true,
    ["Base.CarTaxi"] = true,
    ["Base.CarTaxi2"] = true,
    ["Base.LuxuryCarBurnt"] = true,
    ["Base.ModernCar"] = true,
    ["Base.ModernCar02"] = true,
    ["Base.ModernCar02Burnt"] = true,
    ["Base.ModernCarBurnt"] = true,
    ["Base.NormalCarBurntPolice"] = true,
    ["Base.OffRoad"] = true,
    ["Base.OffRoadBurnt"] = true,
    ["Base.PickUpTruck"] = true,
    ["Base.PickUpTruckLights"] = true,
    ["Base.PickUpTruckLightsFire"] = true,
    ["Base.PickUpTruckMccoy"] = true,
    ["Base.PickUpVan"] = true,
    ["Base.PickUpVanBurnt"] = true,
    ["Base.PickUpVanLights"] = true,
    ["Base.PickUpVanLightsBurnt"] = true,
    ["Base.PickUpVanLightsFire"] = true,
    ["Base.PickUpVanLightsPolice"] = true,
    ["Base.PickUpVanMccoy"] = true,
    ["Base.PickupBurnt"] = true,
    ["Base.PickupSpecialBurnt"] = true,
    ["Base.SUV"] = true,
    ["Base.SUVBurnt"] = true,
    ["Base.SmallCar"] = true,
    ["Base.SmallCar02"] = true,
    ["Base.SmallCar02Burnt"] = true,
    ["Base.SmallCarBurnt"] = true,
    ["Base.SportsCar"] = true,
    ["Base.SportsCarBurnt"] = true,
    ["Base.StepVan"] = true,
    ["Base.StepVanMail"] = true,
    ["Base.StepVan_Heralds"] = true,
    ["Base.StepVan_Scarlet"] = true,
    ["Base.TaxiBurnt"] = true,
    ["Base.Van"] = true,
    ["Base.VanAmbulance"] = true,
    ["Base.VanBurnt"] = true,
    ["Base.VanRadio"] = true,
    ["Base.VanRadioBurnt"] = true,
    ["Base.VanRadio_3N"] = true,
    ["Base.VanSeats"] = true,
    ["Base.VanSeatsBurnt"] = true,
    ["Base.VanSpecial"] = true,
    ["Base.VanSpiffo"] = true,
    ["Base.Van_KnoxDisti"] = true,
    ["Base.Van_LectroMax"] = true,
    ["Base.Van_MassGenFac"] = true,
    ["Base.Van_Transit"] = true,
}

-- 실제로 차단을 수행했는지 여부. 아래 두 이벤트 중 한쪽에서만 처리하면 되므로 중복 실행을 막는다.
-- "옵션이 꺼져 있어서 아무것도 안 한 경우"에는 세우지 않는다 -- 이유는 registerHooks 주석 참조.
local applied = false

local function stripModVehicles()
    local dist = VehicleZoneDistribution
    if type(dist) ~= "table" then
        print(LOG .. "VehicleZoneDistribution not found, nothing to do")
        return false
    end

    local totalRemoved, totalKept = 0, 0
    local removedTypes, seen = {}, {}

    for zoneName, zoneDef in pairs(dist) do
        local vehicles = type(zoneDef) == "table" and zoneDef.vehicles or nil
        if type(vehicles) == "table" then
            -- pairs 순회 도중 원소를 지우지 않고 목록부터 모은다.
            -- (Lua 5.1 표준상 기존 키 삭제는 허용되지만, Kahlua 구현에 기대지 않는다)
            local doomed = {}
            for fullType, _ in pairs(vehicles) do
                if VANILLA_ZONE_VEHICLES[fullType] then
                    totalKept = totalKept + 1
                else
                    doomed[#doomed + 1] = fullType
                end
            end

            for i = 1, #doomed do
                local fullType = doomed[i]
                vehicles[fullType] = nil
                totalRemoved = totalRemoved + 1
                if not seen[fullType] then
                    seen[fullType] = true
                    removedTypes[#removedTypes + 1] = fullType
                end
            end

            if #doomed > 0 then
                print(LOG .. "zone '" .. tostring(zoneName) .. "': removed " .. #doomed .. " mod vehicle entries")
            end
        end
    end

    print(LOG .. "blocking done: entries removed=" .. totalRemoved
        .. ", vanilla kept=" .. totalKept
        .. ", unique types=" .. #removedTypes)
    if #removedTypes > 0 then
        print(LOG .. "blocked types: " .. table.concat(removedTypes, ";"))
    end
    return true
end

function t3VehicleNaturalSpawn.apply(originEvent)
    if applied then return end

    if not SandboxVars.PongDu.VehicleDrop_BlockModNaturalSpawn then
        print(LOG .. "option off at " .. tostring(originEvent) .. ", mod vehicles spawn normally")
        return
    end

    print(LOG .. "option on at " .. tostring(originEvent) .. ", stripping mod vehicles from world spawn pools")
    if stripModVehicles() then
        applied = true
    end
end

-- 이벤트를 둘 다 거는 이유 (SandboxVars가 세이브 값으로 채워지는 시점이 realm마다 다름):
--
--   데디 서버: GameServer가 Lua 로드 -> SandboxOptions.toLua() -> OnGameBoot 순서라
--             OnGameBoot 시점에 SandboxVars가 이미 세이브 값이다 (디컴파일로 확인).
--   솔로:     OnGameBoot이 세이브 로드 전(GameWindow/IngameState)에 발화하므로 그 시점 값은
--             세이브 값이 아니다. 월드 로딩 중에 발화하는 OnInitGlobalModData가 필요하다.
--             (솔로 쪽 정확한 순서는 디컴파일에서 끝까지 못 짚어서 추정이 섞여 있다.
--              로그의 "option on/off at <event>" 문구로 어느 쪽이 잡혔는지 확인할 수 있다.)
--
-- applied 플래그를 "실제로 차단한 경우"에만 세우는 게 핵심이다. 옵션이 꺼진 것으로 읽혔을 때도
-- 플래그를 세워버리면, 솔로에서 OnGameBoot의 미로드 기본값(false)을 보고 조기 종료해
-- OnInitGlobalModData에서 재시도할 기회가 사라진다.
Events.OnGameBoot.Add(function() t3VehicleNaturalSpawn.apply("OnGameBoot") end)
Events.OnInitGlobalModData.Add(function() t3VehicleNaturalSpawn.apply("OnInitGlobalModData") end)
