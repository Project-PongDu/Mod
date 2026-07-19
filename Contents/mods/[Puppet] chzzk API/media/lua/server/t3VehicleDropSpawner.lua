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

    -- 열쇠 지급.
    -- 키의 실체는 "CarKey 아이템 + keyId(int) 일치"가 전부라 (BaseVehicle.createVehicleKey
    -- 디컴파일 확인), 차량 객체 없이도 keyId만 있으면 어디서든 유효한 키를 만들 수 있다.
    -- 예전 방식(클라가 getVehicleById로 차량을 찾아 createVehicleKey)은 드랍 지점이
    -- 50~100타일이라 차량이 클라 스트리밍 범위 밖이면 조회 실패 -> 키 미지급 버그가 있었다.
    -- 이제 서버가 keyId/차종/색상만 뽑아 보내고, 클라(VehicleDropKeyGrant.lua)가
    -- 차량 조회 없이 로컬에서 키를 직접 생성한다.
    if not isClient() and not isServer() then
        -- 솔로: 같은 프로세스이므로 바로 생성+지급해도 동기화 문제 없음
        local key = vehicle:createVehicleKey()
        if key then
            local keyName = (sender and sender ~= "" and (sender .. "의 ") or "") .. key:getDisplayName()
            key:setName(keyName)
            player:getInventory():AddItem(key)
            print("[t3VehicleDrop] 솔로 키 지급 완료: " .. keyName)
        else
            print("[t3VehicleDrop] 솔로 키 생성 실패 (vehicleId " .. tostring(vehicleId) .. ")")
        end
    elseif isServer() then
        -- 서버측 키를 임시 생성해 색상만 추출 (바닐라 키 색 = 차체 색 유지용)
        local colR, colG, colB
        local tmpKey = vehicle:createVehicleKey()
        local col = tmpKey and tmpKey:getColor()
        if col then
            colR, colG, colB = col:getR(), col:getG(), col:getB()
        end

        sendServerCommand(player, "PongDuVehicleDrop", "GrantKey", {
            keyId      = vehicle:getKeyId(),
            scriptName = vehicle:getScript():getName(),
            colR = colR, colG = colG, colB = colB,
            sender = sender,
            vehicleId = vehicleId, -- 로그 추적용
        })
        print("[t3VehicleDrop] GrantKey 전송 (keyId " .. tostring(vehicle:getKeyId()) .. ", vehicleId " .. tostring(vehicleId) .. ")")
    end

    print("[t3VehicleDrop] " .. tostring(vehicleType) .. " 소환 완료 (후원자: " .. tostring(sender) .. ")")
end
