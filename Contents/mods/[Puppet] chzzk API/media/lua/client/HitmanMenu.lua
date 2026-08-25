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
    sendClientCommand(player, 'Hitman_Commands', 'HitmanFlush', args)
end

function HitmanMenu.SpawnClan(player, square, cid)
    local args = {}
    args.cid = cid
    args.x = square:getX()
    args.y = square:getY()
    args.z = square:getZ()
    sendClientCommand(player, 'Hitman_Spawner', 'Type', args)
end

function HitmanMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    local world = getWorld()
    local player = getSpecificPlayer(playerID)
    local square = HitmanCompatibility.GetClickedSquare()
    -- [PongDu] nil 가드. 원본은 곧바로 square:getZombie() 를 불러서 클릭 지점이
    -- 잡히지 않으면 "attempt to index nil" 이 콘솔로 쏟아진다.
    if not square then return end

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

    -- ── [PongDu] "Spawn Hitman Clan" 컨텍스트 메뉴 제거 ──────────────────────
    -- 원본은 isDebugEnabled() or isAdmin() 조건으로 클랜 목록을 붙이고
    -- Hitman_Spawner/Type 으로 즉시 소환했다. 방송 중 어드민이 우클릭 한 번
    -- 잘못하면 밴딧이 그대로 쏟아지므로 뺐다.
    -- 히트맨 소환은 퐁듀 도네 경로(featureId bandit_melee / bandit_ranged ->
    -- features/hitman.lua -> Hitman_Spawner/Clan)로만 나가고, 수동 테스트는
    -- DonationTestMenu 의 dev 서브메뉴를 쓴다.
    -- 서버측 HitmanServer.Hitman_Spawner.Type 핸들러는 원본 그대로 남겨둔다
    -- (히트맨 모드 상류 코드라 건드리지 않는다).
end

Events.OnPreFillWorldObjectContextMenu.Add(HitmanMenu.WorldContextMenuPre)
