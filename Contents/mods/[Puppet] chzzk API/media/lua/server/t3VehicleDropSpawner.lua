-- t3VehicleDrop.spawnVehicle: 실제 addVehicleDebug 호출부.
-- 이 파일은 media/lua/server/ 아래 있으므로 "솔로"와 "진짜 서버"에서만 로드된다.
-- 진짜 MP 클라이언트에서는 로드되지 않으므로, 반드시
-- shared/t3VehicleDrop.lua 의 OpenKit(solo면 직접호출 / MP면 sendClientCommand)을
-- 거쳐서만 호출되어야 한다 (InsurgentStartLUV AirdroppedLUVSpawnVehicle.lua와 동일 구조).

t3VehicleDrop = t3VehicleDrop or {}

local TARGET_CONDITION_MIN = 90 -- 기증 차량 컨디션 하한 (0~100)
local TARGET_CONDITION_MAX = 100 -- 기증 차량 컨디션 상한 (0~100)

-- 차량 주변에 펼쳐진 낙하산 데코를 몇 개 뿌린다 (순수 연출용, 실패해도 무시).
-- 실제로 놓인 타일 좌표를 "x,y,z" 문자열 배열로 돌려주고, 호출부가 차량 modData에
-- 심어둔다. 플레이어가 그 차량에 타는 순간 회수하기 위한 것.
local PARACHUTE_OFFSETS = { {-2, 0}, {2, 0}, {0, 2} }
local PARACHUTE_TYPE = "t3chzzkDonation.t3DeployedParachute"

local function scatterParachutes(square)
    local cell = getCell()
    local sx, sy, sz = square:getX(), square:getY(), square:getZ()
    local placed = {}
    for _, offset in ipairs(PARACHUTE_OFFSETS) do
        local sq = cell:getGridSquare(sx + offset[1], sy + offset[2], sz)
        if sq and sq:isOutside() then
            sq:AddWorldInventoryItem(PARACHUTE_TYPE, 0.5, 0.5, 0)
            placed[#placed + 1] = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
        end
    end
    return placed
end

-- 보급 차량에 처음 탑승했을 때 연출용 낙하산을 월드에서 지운다.
-- 좌표는 스폰 시점에 차량 modData에 심어둔 값을 쓴다 (차량이 이동한 뒤여도 무관).
-- 낙하산은 AddWorldInventoryItem으로 놓은 월드 인벤토리 아이템이라, 오브젝트용
-- transmitRemoveItemFromSquare만으로는 부족하고 removeWorldObject까지 같이 불러야 한다
-- (바닐라 ISMoveableSpriteProps가 월드아이템을 치울 때 쓰는 조합).
function t3VehicleDrop.clearParachutes(vehicle)
    if not vehicle then return end

    -- 모든 차량 탑승에서 호출되므로, 우리 보급차가 아니면 조용히 빠진다 (로그 스팸 방지)
    local modData = vehicle:getModData()
    local coords = modData.t3ParachuteSquares
    if type(coords) ~= "table" or #coords == 0 then return end

    local cell = getCell()
    local removed = 0
    for i = 1, #coords do
        local sx, sy, sz = string.match(coords[i], "^(-?%d+),(-?%d+),(-?%d+)$")
        if sx then
            local sq = cell:getGridSquare(tonumber(sx), tonumber(sy), tonumber(sz))
            if sq then
                local worldObjects = sq:getWorldObjects()
                -- 역순 순회: 제거하면 리스트 인덱스가 당겨진다
                for j = worldObjects:size() - 1, 0, -1 do
                    local worldObject = worldObjects:get(j)
                    local item = worldObject:getItem()
                    if item and item:getFullType() == PARACHUTE_TYPE then
                        sq:transmitRemoveItemFromSquare(worldObject)
                        sq:removeWorldObject(worldObject)
                        removed = removed + 1
                    end
                end
            end
        else
            print("[t3VehicleDrop] Malformed parachute coord: " .. tostring(coords[i]))
        end
    end

    -- 한 번 치웠으면 재진입 때 다시 훑지 않도록 마킹을 지운다
    modData.t3ParachuteSquares = nil

    print("[t3VehicleDrop] Parachutes cleared on vehicle entry: " .. removed)
end

-- 바닐라 trySpawnKey가 addToWorld 시점에 자동으로 뿌리는 키를 회수한다.
-- (BaseVehicle 디컴파일 기준 자동 키의 행선지: 점화구/도어, 글로브박스,
--  차량 기준 ±10타일 z0~2의 counter/officedrawers/shelves/desk 컨테이너,
--  같은 범위 바닥 월드아이템, 그리고 ±10타일 내 좀비의 사망드랍.)
-- 좀비 사망드랍(addItemToSpawnAtDeath)만은 제거 API가 없어 회수 불가 — 드물게
-- 근처 좀비 시체에서 여분 키가 나올 수 있는 알려진 한계.
local KEY_CLEANUP_RADIUS = 10 -- addKeyToSquare의 탐색 반경과 동일

local function isAutoKey(item, keyId)
    return item and item:getType() == "CarKey" and item:getKeyId() == keyId
end

local function removeKeysFromContainer(container, keyId)
    if not container then return 0 end
    local removed = 0
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if isAutoKey(item, keyId) then
            container:Remove(item)
            removed = removed + 1
        end
    end
    return removed
end

local function removeAutoSpawnedKeys(vehicle)
    local keyId = vehicle:getKeyId()
    local removed = 0

    -- 점화구/도어에 꽂힌 키
    if vehicle:isKeysInIgnition() then vehicle:setKeysInIgnition(false) end
    if vehicle:isKeyIsOnDoor() then vehicle:setKeyIsOnDoor(false) end
    if vehicle:getCurrentKey() then
        vehicle:setCurrentKey(nil)
        removed = removed + 1
    end

    -- 글로브박스 (VehicleEasyUse=true면 여기로 확정 스폰됨)
    local gloveBox = vehicle:getPartById("GloveBox")
    if gloveBox then
        removed = removed + removeKeysFromContainer(gloveBox:getItemContainer(), keyId)
    end

    -- 차량 기준 ±10타일, z 0~2: 바닥 월드아이템 + 가구 컨테이너
    local cell = getCell()
    local vx = math.floor(vehicle:getX())
    local vy = math.floor(vehicle:getY())
    for sx = vx - KEY_CLEANUP_RADIUS, vx + KEY_CLEANUP_RADIUS do
        for sy = vy - KEY_CLEANUP_RADIUS, vy + KEY_CLEANUP_RADIUS do
            for sz = 0, 2 do
                local sq = cell:getGridSquare(sx, sy, sz)
                if sq then
                    -- 바닥 월드아이템
                    local wobjs = sq:getWorldObjects()
                    for i = wobjs:size() - 1, 0, -1 do
                        local wobj = wobjs:get(i)
                        local item = wobj and wobj:getItem()
                        if isAutoKey(item, keyId) then
                            sq:transmitRemoveItemFromSquare(wobj)
                            removed = removed + 1
                        end
                    end
                    -- 가구 컨테이너 (trySpawnKey가 노리는 4종만)
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        local cont = obj and obj:getContainer()
                        if cont then
                            local ctype = cont:getType()
                            if ctype == "counter" or ctype == "officedrawers"
                                or ctype == "shelves" or ctype == "desk" then
                                removed = removed + removeKeysFromContainer(cont, keyId)
                            end
                        end
                    end
                end
            end
        end
    end

    print("[t3VehicleDrop] Auto-spawned keys removed: " .. removed .. " (keyId " .. tostring(keyId) .. ")")
end

function t3VehicleDrop.spawnVehicle(player, x, y, z, vehicleType, sender)
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        print("[t3VehicleDrop] Square not found at (" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. "), spawn cancelled")
        return
    end

    local vehicle = addVehicleDebug(vehicleType, IsoDirections.S, nil, square)
    if not vehicle then
        print("[t3VehicleDrop] Vehicle spawn failed: " .. tostring(vehicleType))
        return
    end

    local parachuteSquares = scatterParachutes(square)

    -- addVehicleDebug 직후 반환값이 완전하지 않을 수 있어 재조회 (AirdroppedLUV와 동일 관례)
    local vehicleId = vehicle:getId()
    vehicle = getVehicleById(vehicleId)
    if not vehicle then
        print("[t3VehicleDrop] Failed to re-acquire vehicle after spawn: " .. tostring(vehicleType))
        return
    end

    -- 탑승 시 회수할 수 있도록 낙하산 위치를 차량에 심어둔다.
    -- 재조회 이후에 세팅해야 modData가 실제 차량 인스턴스에 붙는다.
    -- transmitModData는 부르지 않는다 -- IsoObject 구현이 square의 Objects 인덱스를
    -- 전제하는데 차량은 거기 등록되지 않아 신뢰할 수 없다. 이 값은 서버에서만 읽으면 되고,
    -- 차량 세이브에 함께 저장되므로 서버 재시작 후에도 남는다.
    if #parachuteSquares > 0 then
        vehicle:getModData().t3ParachuteSquares = parachuteSquares
    end

    -- 바닐라가 자동으로 뿌린 키 회수 (우리 키만 유일한 키가 되도록)
    removeAutoSpawnedKeys(vehicle)

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
            print("[t3VehicleDrop] Solo key granted: " .. keyName)
        else
            print("[t3VehicleDrop] Solo key creation failed (vehicleId " .. tostring(vehicleId) .. ")")
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
        print("[t3VehicleDrop] GrantKey sent (keyId " .. tostring(vehicle:getKeyId()) .. ", vehicleId " .. tostring(vehicleId) .. ")")
    end

    print("[t3VehicleDrop] " .. tostring(vehicleType) .. " spawned (donor: " .. tostring(sender) .. ")")
end
