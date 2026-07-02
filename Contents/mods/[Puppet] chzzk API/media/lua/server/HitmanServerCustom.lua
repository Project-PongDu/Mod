HitmanServer = HitmanServer or {}
HitmanServer.Custom = {}

HitmanServer.Custom.SendToClients  = function(player, argsOld)
    HitmanCustom.Load()
    local args = {}
    args.hitmanData = HitmanCustom.hitmanData
    args.clanData = HitmanCustom.clanData
    -- sendServerCommand('Commands', 'SendCustomToClients', args)
end

HitmanServer.Custom.ReceiveFromClient  = function(player, args)
    HitmanCustom.hitmanData = args.hitmanData
    HitmanCustom.clanData = args.clanData
    HitmanCustom.Save()
    -- sendServerCommand('Commands', 'SendCustomToClients', args)
end

local function onClientCommand(module, command, player, args)
    if module == "Custom" and HitmanServer[module] and HitmanServer[module][command] then
        local argStr = ""
        for k, v in pairs(args) do
            argStr = argStr .. " " .. k .. "=" .. tostring(v)
        end
        -- print ("received " .. module .. "." .. command .. " "  .. argStr)
        HitmanServer[module][command](player, args)
    end
end

local function onServerStarted()
    HitmanCustom.Load()
    print "[HITMANS] Custom Hitmans loaded successfully."
end

Events.OnClientCommand.Add(onClientCommand)
Events.OnServerStarted.Add(onServerStarted)