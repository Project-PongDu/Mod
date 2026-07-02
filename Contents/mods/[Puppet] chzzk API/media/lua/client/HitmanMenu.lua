--
-- ********************************
-- *** Zombie Hitmans           ***
-- ********************************
-- *** Coded by: Slayer         ***
-- ********************************
--

HitmanMenu = HitmanMenu or {}

function HitmanMenu.TestAction (player, square, zombie)

    local task = {action="Time", anim="TEST", time=400}
    Hitman.AddTask(zombie, task)
end

function HitmanMenu.ShowBrain (player, square, zombie)
    local gmd = GetHitmanModData()

    local bcnt = 0
    for k, v in pairs(gmd.Queue) do
        bcnt = bcnt + 1
    end

    -- add breakpoint below to see data
    local brain = HitmanBrain.Get(zombie)
    local moddata = zombie:getModData()
    local id = HitmanUtils.GetCharacterID(zombie)
    local isUseless = zombie:isUseless()
    local isHitman = zombie:getVariableBoolean("Hitman")
    local walktype = zombie:getVariableString("zombieWalkType")
    local walktype2 = zombie:getVariableString("HitmanWalkType")
    local isHitmanTarget = zombie:getVariableString("HitmanTarget")
    local primary = zombie:getVariableString("HitmanPrimary")
    local primaryType = zombie:getVariableString("HitmanPrimaryType")
    local secondary = zombie:getVariableString("HitmanSecondary")
    local outfit = zombie:getOutfitName()
    local ans = zombie:getActionStateName()
    local under = zombie:isUnderVehicle()
    local veh = zombie:getVehicle()
    local health = zombie:getHealth()
    local zx = zombie:getX()
    local zy = zombie:getY()
    local hv = zombie:getHumanVisual()
    local bv = hv:getBodyVisuals()
    local moddata = zombie:getModData()
    local target = zombie:getTarget()
    local animator = zombie:getAdvancedAnimator()
    local inventory = zombie:getInventory()
    -- local astate = zombie:getAnimationDebug()
    local baseData = HitmanPlayerBase.data

end

function HitmanMenu.SwitchProgram(player, hitman, program)
    local brain = HitmanBrain.Get(hitman)
    if brain then
        local pid = HitmanUtils.GetCharacterID(player)

        brain.master = pid
        brain.program = {}
        brain.program.name = program
        brain.program.stage = "Prepare"
        HitmanBrain.Update(hitman, brain)

        local syncData = {}
        syncData.id = brain.id
        syncData.master = brain.master
        syncData.program = brain.program
        Hitman.ForceSyncPart(hitman, syncData)
    end
end

function HitmanMenu.HitmanFlush(player)
    local args = {a=1}
    sendClientCommand(player, 't3_Commands', 'HitmanFlush', args)
end

function HitmanMenu.SpawnClan(player, square, cid)
    local args = {}
    args.cid = cid
    args.x = square:getX()
    args.y = square:getY()
    args.z = square:getZ()
    sendClientCommand(player, 't3_Spawner', 'Type', args)
end

function HitmanMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    local world = getWorld()
    local player = getSpecificPlayer(playerID)
    local square = HitmanCompatibility.GetClickedSquare()

    local zombie = square:getZombie()
    if not zombie then
        local squareS = square:getS()
        if squareS then
            zombie = squareS:getZombie()
            if not zombie then
                local squareW = square:getW()
                if squareW then
                    zombie = squareW:getZombie()
                end
            end
        end
    end

    -- Player options
    if zombie and zombie:getVariableBoolean("Hitman") then
        local brain = HitmanBrain.Get(zombie)
        if not (brain.hostile or brain.hostileP) then
            local hitmanOption = context:addOption(brain.fullname)
            local hitmanMenu = context:getNew(context)

            if brain.program.name == "Looter" then
                context:addSubMenu(hitmanOption, hitmanMenu)
                hitmanMenu:addOption("Join Me!", player, HitmanMenu.SwitchProgram, zombie, "Companion")
            elseif brain.program.name == "Companion" or brain.program.name == "CompanionGuard" then
                context:addSubMenu(hitmanOption, hitmanMenu)
                hitmanMenu:addOption("Leave Me!", player, HitmanMenu.SwitchProgram, zombie, "Looter")
            end
        end
        context:addOption("[DGB] Test action", player, HitmanMenu.TestAction, square, zombie)
    end

    -- Debug options
    if isDebugEnabled() then
        context:addOption("[DGB] Remove All Hitmans", player, HitmanMenu.HitmanFlush, square)

        if zombie then
            context:addOption("[DGB] Show Brain", player, HitmanMenu.ShowBrain, square, zombie)
        end
    end

    if isDebugEnabled() or isAdmin() then
        HitmanCustom.Load()
        local clanData  = HitmanCustom.ClanGetAllSorted()
        local clanSpawnOption = context:addOption("Spawn Hitman Clan")
        local clanSpawnMenu = context:getNew(context)
        context:addSubMenu(clanSpawnOption, clanSpawnMenu)
        for cid, clan in pairs(clanData) do
            clanSpawnMenu:addOption("Clan " .. clan.general.name, player, HitmanMenu.SpawnClan, square, cid)
        end
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(HitmanMenu.WorldContextMenuPre)
