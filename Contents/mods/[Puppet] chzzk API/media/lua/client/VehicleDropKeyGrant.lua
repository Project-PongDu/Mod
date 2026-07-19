-- VehicleDropKeyGrant: MP에서 t3VehicleDrop이 스폰한 차량의 열쇠를
-- "요청한 본인"의 클라이언트가 직접 생성해서 자기 인벤토리에 넣는 리시버.
--
-- 서버(t3VehicleDropSpawner.lua)가 남의 인벤토리를 직접 AddItem하면
-- owning client에 반영이 안 되는 문제가 있어(검증된 동기화 API 부재),
-- 서버는 키 재료(keyId/차종/색상)만 sendServerCommand로 전달하고
-- 실제 키 생성+지급은 여기서 owning client가 직접 수행한다.
--
-- [중요] 차량 객체(getVehicleById)는 절대 참조하지 않는다.
-- 드랍 지점이 50~100타일이라 차량이 클라 스트리밍 범위 밖이면 조회가 실패하는데,
-- BaseVehicle.createVehicleKey 디컴파일 확인 결과 키의 실체는
-- "CarKey 아이템 + setKeyId(차량 keyId)"가 전부라 차량 없이도 유효한 키를 만들 수 있다.

local function onServerCommand(module, command, args)
    if module ~= "PongDuVehicleDrop" then return end
    if command ~= "GrantKey" then return end

    local keyId = args and args.keyId
    if not keyId then
        print("[VehicleDropKeyGrant] keyId 누락, 키 지급 취소 (vehicleId " .. tostring(args and args.vehicleId) .. ")")
        return
    end

    local player = getPlayer()
    if not player then
        print("[VehicleDropKeyGrant] 로컬 플레이어 없음, 키 지급 취소")
        return
    end

    -- 차량 조회 없이 로컬에서 키 생성 (BaseVehicle.createVehicleKey와 동일 구성)
    local key = InventoryItemFactory.CreateItem("Base.CarKey")
    if not key then
        print("[VehicleDropKeyGrant] CarKey 아이템 생성 실패")
        return
    end
    key:setKeyId(keyId)

    -- 키 색상: 서버가 보낸 차체 색 그대로 (바닐라 키와 동일한 색 구분 유지)
    if args.colR and args.colG and args.colB and Color and Color.new then
        key:setColor(Color.new(args.colR, args.colG, args.colB))
        key:setCustomColor(true)
    end

    -- 키 이름: "{후원자}의 {차종별 키 이름}" (차종 번역은 클라 로케일 기준)
    local baseName = key:getDisplayName()
    local scriptName = args.scriptName
    if scriptName and scriptName ~= "" then
        local vehName = getTextOrNull("IGUI_VehicleName" .. scriptName)
        if vehName then
            baseName = getText("IGUI_CarKey", vehName)
        end
    end
    local sender = args.sender
    local keyName = (sender and sender ~= "" and (sender .. "'s '") or "") .. baseName
    key:setName(keyName)

    player:getInventory():AddItem(key)
    print("[VehicleDropKeyGrant] 키 지급 완료: " .. keyName .. " (keyId " .. tostring(keyId) .. ")")
end

Events.OnServerCommand.Add(onServerCommand)
