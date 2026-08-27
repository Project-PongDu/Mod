-- 보급 차량에 탑승하면 주변에 뿌려둔 연출용 낙하산을 월드에서 치운다.
--
-- 낙하산 좌표는 스폰 시점에 서버가 차량 modData(t3ParachuteSquares)에 심어둔다.
-- 여기서는 "탔다"는 사실만 감지해서 서버에 회수를 요청한다. 월드 아이템 제거는
-- 서버 권위로 처리해야 MP에서 다른 클라이언트에도 반영된다.
--
-- OnEnterVehicle은 ISEnterVehicle:perform()에서 triggerEvent로 발화하는 클라이언트
-- 이벤트라 이 파일은 client/ 아래 둔다.

t3VehicleDropParachute = t3VehicleDropParachute or {}

local function onEnterVehicle(player)
    if not player then return end

    local vehicle = player:getVehicle()
    if not vehicle then return end

    if not isClient() and not isServer() then
        -- 솔로: modData가 같은 프로세스에 있으므로 서버 함수가 직접 판단한다
        t3VehicleDrop.clearParachutes(vehicle)
    elseif isClient() then
        -- MP: 차량 modData가 클라이언트까지 동기화된다는 보장이 없어(IsoObject.transmitModData는
        -- square의 Objects 인덱스를 쓰는데 차량은 거기 등록되지 않는다) 여기서 미리 걸러내지
        -- 않고 판단을 서버에 맡긴다. 낙하산이 없는 차량이면 서버가 즉시 무시하므로
        -- 탑승할 때마다 vehicleId 하나 보내는 비용만 든다.
        sendClientCommand("PongDuVehicleDrop", "ClearParachutes", {
            vehicleId = vehicle:getId(),
        })
    end
end

Events.OnEnterVehicle.Add(onEnterVehicle)
