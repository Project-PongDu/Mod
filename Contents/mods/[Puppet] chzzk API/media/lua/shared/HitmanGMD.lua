HitmanGlobalData = {}
HitmanGlobalDataPlayers = {}

function InitHitmanModData(isNewGame)

    -- HITMAN GLOBAL MODDATA
    local globalData = ModData.getOrCreate("Hitman")
    if isClient() then
        ModData.request("Hitman")
    end

    if not globalData.Queue then globalData.Queue = {} end
    
    -- uncomment these to reset all hitmans on server restart
    -- if isServer() then
    --    globalData.Queue = {}
    -- end
    
    if not globalData.Scenes then globalData.Scenes = {} end
    if not globalData.Hitmans then globalData.Hitmans = {} end
    if not globalData.Posts then globalData.Posts = {} end
    if not globalData.Bases then globalData.Bases = {} end
    if not globalData.Kills then globalData.Kills = {} end
    if not globalData.VisitedBuildings then globalData.VisitedBuildings = {} end
    HitmanGlobalData = globalData

    -- HITMAN PLAYERS GLOBAL MODDATA
    local globalDataPlayers = ModData.getOrCreate("HitmanPlayers")
    if isClient() then
        ModData.request("HitmanPlayers")
    end
   
    globalDataPlayers.OnlinePlayers = {}
    HitmanGlobalDataPlayers = globalDataPlayers
end

function LoadHitmanModData(key, globalData)
    if isClient() then
        if key and globalData then
            if key == "Hitman" then
                HitmanGlobalData = globalData
            elseif key == "HitmanPlayers" then
                HitmanGlobalDataPlayers = globalData
            end
        end
    end
end

function GetHitmanModData()
    return HitmanGlobalData
end

function GetHitmanModDataPlayers()
    return HitmanGlobalDataPlayers
end

function TransmitHitmanModData()
    ModData.transmit("Hitman")
end

function TransmitHitmanModDataPlayers()
    ModData.transmit("HitmanPlayers")
end

Events.OnInitGlobalModData.Add(InitHitmanModData)
Events.OnReceiveGlobalModData.Add(LoadHitmanModData)