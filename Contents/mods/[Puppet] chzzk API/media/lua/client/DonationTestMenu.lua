--
-- ***********************************
-- *** [PongDu] 도네이션 (테스트)  ***
-- ***********************************
-- MutantMenu.lua의 WorldContextMenuPre 패턴 이식. 어드민(또는 디버그)이
-- **플레이어를 우클릭했을 때만** "[PongDu] <대상> 에게 후원효과 발동" 항목이
-- 뜨고, 그 안에서 긍정효과 / 부정효과 / 서버 / dev 서브메뉴로 나뉜다.
-- (구버전은 아무 칸이나 우클릭해도 뜨고 항상 자기 자신에게 발동했다.)
--
-- ── 대상 지정 ──
-- 클릭 지점 ±1칸을 훑어 IsoPlayer를 찾는다. 바닐라 clickedPlayer 전역은
-- "본인 제외"라 싱글/혼자 접속 중엔 메뉴가 통째로 사라지므로 쓰지 않고
-- 직접 훑는다 -- 자기 자신도 정상적인 대상이다(기존 자가 테스트 유지).
--
-- 항목 클릭 시:
--   * 대상 == 본인  -> 로컬에서 바로 PongDuDonationTest.inject()
--   * 대상 == 타인  -> PongDuDonation/Inject 를 서버로 -> 서버가 권한 재확인 후
--                      해당 클라에만 중계 -> 그 클라에서 inject()
-- 어느 쪽이든 실제 도네이션과 완전히 같은 경로(donationQueue -> 큐박스 슬롯 ->
-- 안전지대 락 -> 카운트다운 -> 발동)를 탄다. MutantMenu의 특좀 소환처럼 즉시
-- 발동이 아니라 "가짜 후원 1건"이 대상 클라에 들어온 것과 동일하게 동작하는 게
-- 목적. 통계(PongDuStats)에는 안 잡힘.
--
-- ── 분류 기준 ──
-- 샌드박스 옵션의 PongDu_Buff / PongDu_Debuff / PongDu_Server / PongDu_Dev
-- 4개 탭과 featureId 묶음이 그대로 1:1 대응한다.
--
-- exile(산타마을 유배) / backroom(백룸 탈출)은 rewardManager에서 발동을 완전히
-- 죽인 더미 핸들러지만, featureId 자체는 getFeatureIds()에 남아있어 미분류로
-- 새는 걸 막기 위해 dev에 명시적으로 묶어둔다.
--
-- CATEGORY에 없는데 rewardManager.getFeatureIds()에 새로 나타나는 featureId가
-- 있으면(= 신규 기능 추가하고 여기 분류를 깜빡한 경우) dev로 폴백시키고
-- 콘솔에 경고를 남긴다 -- 조용히 씹어서 메뉴에서 안 보이는 것보다는 낫다.

DonationTestMenu = DonationTestMenu or {}

local rewardManager = require("rewards/rewardManager")
local labelKey       = require("utils/labelKey")

local BUFF = {
    "buff_roulette", "vaccine", "random_skill_potion", "random_weapon",
    "vehicle_drop", "inv_save_ticket", "fire_support",
    "food_supply", "instant_heal",
}

local DEBUFF = {
    "debuff_roulette", "zombie_roulette", "sprinter5", "random_teleport",
    "mutant_spawn", "rise_up_dead_man", "zombie_rain", "random_injury",
}

-- missile(폭격)은 고정 카테고리가 아니다. DonationReceiver.lua의
-- resolveLabelKey()와 같은 기준(SandboxVars.PongDu.Bombard_Injure)으로
-- 큐박스 UI가 "지원 폭격"/"유도 폭격"으로 갈리는 것과 맞춰, 이 메뉴에서도
-- 꺼짐(플레이어 안 맞음) -> buff, 켜짐(플레이어도 맞음) -> debuff로 배치한다.
-- SandboxVars는 파일 로드 시점이 아니라 메뉴를 여는 시점에 읽어야 하므로
-- BUFF/DEBUFF 정적 배열에는 넣지 않고 WorldContextMenuPre에서 직접 꽂는다.

local SERVER = {
    "horde_night", "medical_box", "blood_moon",
}

local DEV = {
    "bandit_melee", "bandit_ranged", "revive_ticket", "secret_passage_kit",
    "exile", "backroom",
}

-- 카테고리 라벨은 전부 getText()로 뽑는다. ContextMenu_KO.txt에 실제 한글이
-- 있고, 이 파일엔 번역키 이름만 남는다 (PZ 번역파일 인코딩 규칙 -- .lua에
-- 한글 원문을 직접 박지 않는다).
local CATEGORY_LIST = {
    { key = "buff",   label = getText("ContextMenu_PongDu_Buff"),   ids = BUFF },
    { key = "debuff", label = getText("ContextMenu_PongDu_Debuff"), ids = DEBUFF },
    { key = "server", label = getText("ContextMenu_PongDu_Server"), ids = SERVER },
    { key = "dev",    label = getText("ContextMenu_PongDu_Dev"),    ids = DEV },
}

-- ── 대상 플레이어 탐색 ────────────────────────────────────────────────────────
-- 표시용 이름. MP에선 계정명(getUsername)이 우리가 원하는 값이고, SP에선 그게
-- 비어 있을 수 있어 캐릭터 표시명으로 떨어진다.
local function playerLabel(p)
    local name = p:getUsername()
    if name and name ~= "" then return name end
    return p:getDisplayName()
end

-- 클릭 지점 ±1칸(바닐라 ISWorldObjectContextMenu.fetch와 동일 범위)을 훑어
-- 대상 플레이어 1명을 고른다. 후보가 여럿이면 클릭한 칸 중심에 가장 가까운 쪽.
-- 사망한 플레이어는 제외 -- 큐에 꽂아봐야 소모되지 않는다.
local SEARCH_RANGE = 1

local function findClickedPlayer()
    local square = HitmanCompatibility.GetClickedSquare()
    if not square then return nil end

    local cx, cy, cz = square:getX(), square:getY(), square:getZ()
    local cell = getCell()
    local best, bestDist = nil, nil

    for x = cx - SEARCH_RANGE, cx + SEARCH_RANGE do
        for y = cy - SEARCH_RANGE, cy + SEARCH_RANGE do
            local sq = cell:getGridSquare(x, y, cz)
            if sq then
                local movers = sq:getMovingObjects()
                for i = 0, movers:size() - 1 do
                    local o = movers:get(i)
                    if instanceof(o, "IsoPlayer") and not o:isDead() then
                        local dx = o:getX() - (cx + 0.5)
                        local dy = o:getY() - (cy + 0.5)
                        local d  = dx * dx + dy * dy
                        if bestDist == nil or d < bestDist then
                            best, bestDist = o, d
                        end
                    end
                end
            end
        end
    end
    return best
end

-- ── 서버 티어 표시 게이트 ────────────────────────────────────────────────────
-- PongDu_Server 계열(호드나이트/블러드문/의약품박스)은 서버측 핸들러
-- (PongDuHordeServer / PongDuBloodMoonServer / PongDuMedBoxServer)가 요청자를
-- PongDuHost.check 로 게이트한다. 서버장이 아닌 대상에게 꽂아봐야 대상 화면에
-- 거부 안내만 뜨고 아무 일도 안 일어난다.
--
-- 여기 판정은 **표시용**이다. 실제 발동 권한은 서버가 player:getSteamID() 로
-- 다시 보므로 이 체크를 우회해도 얻는 게 없다.
-- 클라에서도 판정이 가능한 건 원격 플레이어의 steamID 가 스팀 모드 서버에서
-- 클라까지 동기화되기 때문이다(GameClient.java:3264 setSteamID).
--
-- NOT_HOST(대상이 확실히 서버장이 아님)일 때만 숨긴다. 설정 자체가 잘못된
-- 경우(UNSET / BAD_ID / WRONG_KIND / NO_STEAM)는 그대로 노출한다 -- 눌러서
-- 사유 안내를 받는 편이 메뉴가 조용히 사라지는 것보다 진단에 낫다.
local function serverTierVisible(target)
    local verdict = PongDuHost.check(target)
    if verdict == PongDuHost.NOT_HOST then
        print("[PongDuTestMenu] server-tier hidden: target is not the host ("
            .. playerLabel(target) .. ")")
        return false
    end
    return true
end

-- ── 발동 ──────────────────────────────────────────────────────────────────────
-- target은 메뉴를 연 시점의 IsoPlayer 참조다. 메뉴 오픈~클릭 사이에 대상이
-- 나가버릴 수 있으므로, 원격 경로에선 onlineID만 실어보내고 실제 존재 확인은
-- 서버가 getPlayerByOnlineID로 다시 한다.
function DonationTestMenu.Fire(player, featureId, target)
    if not target then
        print("[PongDuTestMenu] Fire aborted: target is nil (feature=" .. tostring(featureId) .. ")")
        return
    end

    if target == player then
        if PongDuDonationTest and PongDuDonationTest.inject then
            PongDuDonationTest.inject(featureId, "Admin", "0", "")
            print("[PongDuTestMenu] inject LOCAL feature=" .. tostring(featureId)
                .. " target=" .. playerLabel(target))
        else
            print("[PongDuTestMenu] inject FAILED: PongDuDonationTest.inject missing")
        end
        return
    end

    sendClientCommand(player, "PongDuDonation", "Inject", {
        ["target"]    = target:getOnlineID(),
        ["featureId"] = featureId,
        ["sender"]    = "Admin",
    })
    print("[PongDuTestMenu] inject REMOTE feature=" .. tostring(featureId)
        .. " target=" .. playerLabel(target)
        .. " onlineID=" .. tostring(target:getOnlineID()))
end

-- featureId의 한글 표시 라벨. IG_UI_KO.txt에 번역이 있으면 그걸 쓰고, 없으면
-- (아직 번역이 안 붙은 신규 기능) featureId 원문을 그대로 보여준다 -- 메뉴
-- 항목이 통째로 사라지는 것보다 영문 featureId가 보이는 편이 디버깅에 낫다.
--
-- missile은 DonationReceiver.lua의 resolveLabelKey()와 동일 기준
-- (SandboxVars.PongDu.Bombard_Injure)으로 큐박스 UI와 같은 문구
-- ("지원 폭격"/"유도 폭격")를 쓴다.
local function displayLabel(featureId)
    if featureId == "missile" then
        if SandboxVars.PongDu.Bombard_Injure then
            return getText("IGUI_donation_bombard_guided")
        end
        return getText("IGUI_donation_bombard_support")
    end
    local key = labelKey[featureId]
    if key then return getText(key) end
    return featureId
end

function DonationTestMenu.WorldContextMenuPre(playerID, context, worldobjects, test)
    if not (isAdmin() or isDebugEnabled()) then return end

    local player = getSpecificPlayer(playerID)
    if not player then return end

    -- 플레이어를 우클릭한 게 아니면 메뉴 자체를 만들지 않는다.
    local target = findClickedPlayer()
    if not target then return end

    -- 분류표에 없는 featureId 추적용. CATEGORY_LIST를 훑어 뺀 나머지가
    -- getFeatureIds() 결과에 남으면 분류를 깜빡한 신규 기능이다.
    local uncategorized = {}
    for _, id in ipairs(rewardManager.getFeatureIds()) do
        uncategorized[id] = true
    end

    local rootOption = context:addOption(getText("ContextMenu_PongDu_Root", playerLabel(target)))
    local rootMenu = context:getNew(context)
    context:addSubMenu(rootOption, rootMenu)

    -- buff/debuff catMenu 참조를 key로 잡아둔다. missile을 루프 밖에서
    -- 동적으로 꽂아넣어야 해서(아래 참조).
    local catMenusByKey = {}
    local showServerTier = serverTierVisible(target)

    for _, category in ipairs(CATEGORY_LIST) do
        if category.key == "server" and not showServerTier then
            -- 숨기더라도 uncategorized 소진은 해줘야 한다. 안 그러면 아래
            -- "(미분류)" 폴백으로 새어나가 그대로 다시 노출된다.
            for _, featureId in ipairs(category.ids) do
                uncategorized[featureId] = nil
            end
        else
            local catOption = rootMenu:addOption(category.label)
            local catMenu = rootMenu:getNew(rootMenu)
            rootMenu:addSubMenu(catOption, catMenu)
            catMenusByKey[category.key] = catMenu

            for _, featureId in ipairs(category.ids) do
                if uncategorized[featureId] then
                    catMenu:addOption(displayLabel(featureId), player, DonationTestMenu.Fire, featureId, target)
                    uncategorized[featureId] = nil
                end
            end
        end
    end

    -- missile: 큐박스 UI(DonationReceiver.resolveLabelKey)와 동일 기준으로
    -- 사용 시점에 SandboxVars를 읽어 buff/debuff 중 하나에 꽂는다.
    if uncategorized["missile"] then
        local missileCatMenu = SandboxVars.PongDu.Bombard_Injure
            and catMenusByKey["debuff"] or catMenusByKey["buff"]
        missileCatMenu:addOption(displayLabel("missile"), player, DonationTestMenu.Fire, "missile", target)
        uncategorized["missile"] = nil
    end

    -- 분류를 깜빡한 신규 featureId는 dev 서브메뉴에 있던 catMenu 참조가
    -- 루프 밖이라 못 넣으니, 별도 "(미분류)" 서브메뉴로 따로 묶어 눈에 띄게 한다.
    local leftover = {}
    for id, _ in pairs(uncategorized) do table.insert(leftover, id) end
    if #leftover > 0 then
        table.sort(leftover)
        print("[PongDuTestMenu] WARNING: uncategorized featureId(s) in DonationTestMenu.lua: "
            .. table.concat(leftover, ", ") .. " (falling back to misc submenu)")

        local miscOption = rootMenu:addOption(getText("ContextMenu_PongDu_Misc"))
        local miscMenu = rootMenu:getNew(rootMenu)
        rootMenu:addSubMenu(miscOption, miscMenu)
        for _, featureId in ipairs(leftover) do
            miscMenu:addOption(displayLabel(featureId), player, DonationTestMenu.Fire, featureId, target)
        end
    end
end

Events.OnPreFillWorldObjectContextMenu.Add(DonationTestMenu.WorldContextMenuPre)
