HitmanServer = HitmanServer or {}
HitmanServer.Players = {}

HitmanServer.Players.PlayerUpdate = function(player, args)
    local gmd = GetHitmanModDataPlayers()
    local id = args.id
    gmd.OnlinePlayers[id] = args
end

local onClientCommand = function(module, command, player, args)
    if module == "Players" and HitmanServer[module] and HitmanServer[module][command] then
        local argStr = ""
        for k, v in pairs(args) do
            argStr = argStr .. " " .. k .. "=" .. tostring(v)
        end
        -- print ("received " .. module .. "." .. command .. " "  .. argStr)
        HitmanServer[module][command](player, args)

        TransmitHitmanModDataPlayers()
    end
end

Events.OnClientCommand.Add(onClientCommand)
