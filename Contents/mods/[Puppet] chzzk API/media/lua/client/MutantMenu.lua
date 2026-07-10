--
-- ********************************
-- *** 특수좀비 관리자 소환 메뉴  ***
-- ********************************
-- HitmanMenu.lua의 WorldContextMenuPre 패턴을 그대로 이식. 서버 쪽은
-- 기존 server.lua의 PEvents/MutantSpawn 핸들러(spawnSpecialZombie)를
-- 그대로 재사용하므로 서버 코드 추가 없음 - 클릭한 칸 좌표 + kind만
-- 실어서 기존 도네이션 스폰 경로와 동일하게 태운다.
--

MutantMenu = MutantMenu or {}

-- server.lua PEvents/MutantSpawn이 인식하는 kind 목록과 항상 동일하게 유지
local MUTANT_KINDS = {
    { id = "screamer", label = "screamer" },
    { id = "brute",    label = "brute" },
    { id = "roach",    label = "roach" },
    { id = "tracer",   label = "tracer" },
    { id = "sprinter", label = "sprinter" },
}

function MutantMenu.Spawn(player, square, kind)
    sendClientCommand(player, "PEvents", "MutantSpawn", {
        ["ZedX"]   = square:getX(),
        ["ZedY"]   = square:getY(),
        ["ZedZ"]   = square:getZ(),
        ["kind"]   = kind,
        ["sender"] = "Admin",
    })
end

function MutantMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    if not (isAdmin() or isDebugEnabled()) then return end

    local player = getSpecificPlayer(playerID)
    local square = HitmanCompatibility.GetClickedSquare()
    if not square then return end

    local spawnOption = context:addOption("spawn mutant zombie")
    local spawnMenu = context:getNew(context)
    context:addSubMenu(spawnOption, spawnMenu)

    for _, mutant in ipairs(MUTANT_KINDS) do
        spawnMenu:addOption(mutant.label, player, MutantMenu.Spawn, square, mutant.id)
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(MutantMenu.WorldContextMenuPre)
