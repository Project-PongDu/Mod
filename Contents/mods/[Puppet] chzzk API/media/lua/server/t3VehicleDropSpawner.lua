-- t3VehicleDrop.spawnVehicle: 실제 addVehicleDebug 호출부.
-- 이 파일은 media/lua/server/ 아래 있으므로 "솔로"와 "진짜 서버"에서만 로드된다.
-- 진짜 MP 클라이언트에서는 로드되지 않으므로, 반드시
-- shared/t3VehicleDrop.lua 의 OpenKit(solo면 직접호출 / MP면 sendClientCommand)을
-- 거쳐서만 호출되어야 한다 (InsurgentStartLUV AirdroppedLUVSpawnVehicle.lua와 동일 구조).

t3VehicleDrop = t3VehicleDrop or {}

local TARGET_CONDITION_MIN = 90 -- 기증 차량 컨디션 하한 (0~100)
local TARGET_CONDITION_MAX = 100 -- 기증 차량 컨디션 상한 (0~100)

-- 차량 주변에 펼쳐진 낙하산 데코를 몇 개 뿌린다 (순수 연출용, 실패해도 무시).
local PARACHUTE_OFFSETS = { {-2, 0}, {2, 0}, {0, 2} }

local function scatterParachutes(square)
    local cell = getCell()
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    for _, offset in ipairs(PARACHUTE_OFFSETS) do
        local sq = cell:getGridSquare(sx + offset[1], sy + offset[2], sz)
        if sq and sq:isOutside() then
            sq:AddWorldInventoryItem("t3chzzkDonation.t3DeployedParachute", 0.5, 0.5, 0)
        end
    end
end

function t3VehicleDrop.spawnVehicle(player, x, y, z, vehicleType, sender)
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        print("[t3VehicleDrop] 좌표(" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. ") 스퀘어를 찾을 수 없음, 소환 취소")
        return
    end

    local vehicle = addVehicleDebug(vehicleType, IsoDirections.S, nil, square)
    if not vehicle then
        print("[t3VehicleDrop] 차량 소환 실패: " .. tostring(vehicleType))
        return
    end

    scatterParachutes(square)

    -- addVehicleDebug 직후 반환값이 완전하지 않을 수 있어 재조회 (AirdroppedLUV와 동일 관례)
    local vehicleId = vehicle:getId()
    vehicle = getVehicleById(vehicleId)
    if not vehicle then
        print("[t3VehicleDrop] 소환 후 차량 재조회 실패: " .. tostring(vehicleType))
        return
    end

    -- 연료 풀
    local gasTank = vehicle:getPartById("GasTank")
    if gasTank then
        gasTank:setContainerContentAmount(gasTank:getContainerCapacity() * 100)
        vehicle:transmitPartModData(gasTank)
    end

    -- 배터리 정상화
    local battery = vehicle:getBattery()
    if battery then
        battery:setDelta(1)
        vehicle:transmitPartUsedDelta(battery)
        vehicle:transmitPartModData(battery)
    end

    -- 부품 상태를 90~100 사이 값(차량당 1회 결정)으로 강제 세팅.
    -- cond가 0(완파)이어도 반드시 세팅해야 하므로 하한 조건(cond >= 1)은 두지 않음.
    local targetCondition = ZombRand(TARGET_CONDITION_MIN, TARGET_CONDITION_MAX + 1)
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part:getCategory() ~= "nodisplay" then
            local cond = part:getCondition()
            if cond and cond < targetCondition then
                part:setCondition(targetCondition)
                vehicle:transmitPartCondition(part)
            end
        end
    end

    local engineLoudness = vehicle:getScript():getEngineLoudness() or 40
    local engineForce    = vehicle:getScript():getEngineForce()
    vehicle:setEngineFeature(100, engineLoudness, engineForce)
    vehicle:transmitEngine()

    -- 열쇠 생성 + 후원자 이름 표기
    local key = vehicle:createVehicleKey()
    if key then
        local keyName = (sender and sender ~= "" and (sender .. "의 ") or "") .. key:getDisplayName()
        key:setName(keyName)
    end

    if key then
        local inv = player:getInventory()
        if inv:getCapacityWeight() + key:getActualWeight() <= inv:getCapacity() then
            inv:AddItem(key)
        else
            -- 무게 초과로 못 넣으면 기존처럼 발밑에 떨궈서 유실 방지
            local playerSquare = player:getCurrentSquare()
            if playerSquare then
                playerSquare:AddWorldInventoryItem(key, 0.5, 0.5, 0)
            end
        end
        if isServer() then
            player:transmitInventory()
        end
    end

    print("[t3VehicleDrop] " .. tostring(vehicleType) .. " 소환 완료 (후원자: " .. tostring(sender) .. ")")
end
