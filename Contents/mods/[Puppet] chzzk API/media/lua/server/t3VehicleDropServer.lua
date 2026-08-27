-- t3VehicleDrop MP 릴레이: 크래프팅 클라가 보낸 좌표/차종으로 서버가 실제 소환을 수행.
if not isServer() then return end

Events.OnClientCommand.Add(function(module, command, player, args)
    if module ~= "PongDuVehicleDrop" then return end
    if command == "SpawnVehicleDrop" then
        t3VehicleDrop.spawnVehicle(player, args.x, args.y, args.z, args.vehicleType, args.sender)
    elseif command == "ClearParachutes" then
        t3VehicleDrop.clearParachutes(getVehicleById(args.vehicleId))
    end
end)
