local rewardManager = {}

local bandit     = require("features/hitman")
local teleport   = require("features/teleport")
local backroom   = require("features/backroom")
local bombard    = require("features/bombard")
local eventUtils = require("utils/Event")
local zone       = require("utils/zone")
local zombie     = require("features/zombie")
local riseup     = require("features/riseup")
local mutantspawn = require("features/mutantspawn")
local zombierain = require("features/zombierain")
local randomteleport = require("features/randomteleport")
local global     = require("global")

-- Spawn zombies, queueing the request if the player is still in a safe zone.
local function handleZombieSpawn(amount, sprint, sender)
    global.b(" handleZombieSpawn FUNCTION START")
    local data = { amount = amount, sprint = sprint, sender = sender or "" }
    if zone.a(global.player) then
        table.insert(global.zombieSpawnQueue, data)
        print(string.format("Zombie added to queue: Amount=%d Sprint=%d", amount, sprint))
    else
        table.insert(global.zombieSpawnQueue, data)
        zombie.a()
    end
    global.b(" handleZombieSpawn FUNCTION END")
end

-- 랜덤 스킬 물약(random_skill_potion) 확률 테이블. weight 합계 = 10000 (0.01% 단위).
--   serum_supreme   : 1%   고정 (잭팟)
--   나머지 99% 는 Sprinting/Lightfoot/Nimble/Sneak 가 각 2유닛, Strength/Fitness 가 각 1유닛
--   비율로 분배 -> 10유닛 = 9.9%/유닛 -> Str/Fit 9.9%씩, 나머지 4개 19.8%씩.
local skillPotionTable = {
    { id = "serum_supreme",   weight = 100 },   -- 1.00%
    { id = "serum_strength",  weight = 990 },   -- 9.90%
    { id = "serum_fitness",   weight = 990 },   -- 9.90%
    { id = "serum_sprinting", weight = 1980 },  -- 19.80%
    { id = "serum_lightfoot", weight = 1980 },  -- 19.80%
    { id = "serum_nimble",    weight = 1980 },  -- 19.80%
    { id = "serum_sneak",     weight = 1980 },  -- 19.80%
}

local function pickSerum()
    local roll = ZombRand(10000)
    local acc = 0
    for _, entry in ipairs(skillPotionTable) do
        acc = acc + entry.weight
        if roll < acc then return entry.id end
    end
    return skillPotionTable[#skillPotionTable].id   -- 안전망
end


-- Donation featureId -> effect. 금액은 GUI(퍼펫 API)에서 유저가 임의로 재배정하고,
-- rewards.txt에 featureId를 실어서 보낸다. 여기는 "이 featureId가 오면 이 효과"만 안다.
-- immediate=true 인 기능은 안전지대 안에서도 즉시 발동. zombie_roulette / sprinter5 /
-- mutant_spawn 은 안전지대 밖으로 나갈 때까지 대기(immediate=false).
-- missile / zombie_rain 은 immediate 가 함수라서 각각 샌드박스 옵션
-- (Bombard_SafeZoneBlock / Rain_SafeZoneBlock)에 따라 런타임에 결정된다.
local rewardHandlers = {
    ["debuff_roulette"] = {
        immediate = true,
        fn = function()
            eventUtils.a(false)                           -- Debuff Roulette
        end,
    },
    ["buff_roulette"] = {
        immediate = true,
        fn = function()
            eventUtils.a(true)                            -- Buff Roulette
        end,
    },
    ["zombie_roulette"] = {
        immediate = false,
        fn = function(sender)
            global.currentSender = sender or ""
            eventUtils.b(global.player)                   -- Zombie Roulette (random count)
        end,
    },
    ["sprinter5"] = {
        immediate = false,
        fn = function(sender)
            global.b(" sprinter5 FUNCTION START")
            -- 마릿수: 샌드박스 Sprinter_Count 고정값 (1~10, 기본 5).
            -- 룰렛과 달리 랜덤 범위가 아니라 설정한 수만큼 정확히 소환.
            -- 옵션 없음(구 세이브) -> 고정 5.
            local sv = SandboxVars and SandboxVars.PongDu
            local amount = (sv and tonumber(sv.Sprinter_Count)) or 5
            if amount < 1 then amount = 1 elseif amount > 10 then amount = 10 end
            handleZombieSpawn(amount, 1, sender)          -- Sprinter xN
            global.processingEvent = false
            global.b(" sprinter5 FUNCTION END")
        end,
    },
    ["bandit_melee"] = {
        immediate = true,
        fn = function(sender)
            bandit.a(11, sender)                          -- Bandit
            global.processingEvent = false
        end,
    },
    ["vaccine"] = {
        immediate = true,
        fn = function(sender)
            local item = global.player:getInventory():AddItem("TheyKnew.Zomboxivir")
            if item then item:setName(sender .. "'s Vaccine") end   -- Vaccine
            global.processingEvent = false
        end,
    },
    ["bandit_ranged"] = {
        immediate = true,
        fn = function(sender)
            bandit.a(15, sender)                          -- Bandit (ranged)
            global.processingEvent = false
        end,
    },
    -- ── 산타마을 유배 (exile): 더미 처리 ──────────────────────────────────────
    -- 현재 실사용 안 함. 코드/샌드박스 옵션(Delay_exile)은 재활성화 대비 보존만
    -- 하고, 실제 텔레포트는 발동하지 않는다. featureId 자체는 유효하게 남겨둬서
    -- (rewardManager.isValid) 퐁듀 런처의 기존 amount->featureId 매핑이 깨지지
    -- 않게 하고, 후원이 들어와도 조용히 소모만 한다.
    -- 원본 로직(features/teleport.lua의 exile 텔레포트, 유배지 좌표 14298,786)은
    -- 재활성화 시 아래 주석을 해제하면 그대로 복원된다.
    ["exile"] = {
        immediate = true,
        fn = function()
            -- global.b(" exile FUNCTION START")
            -- getSoundManager():PlaySound("exile_enter", false, 1.0)
            -- teleport.b(global.player)                     -- Exile Teleport
            -- global.b(" exile FUNCTION END")
            global.processingEvent = false
        end,
    },
    ["random_teleport"] = {
        immediate = true,
        fn = function()
            global.b(" random_teleport FUNCTION START")
            getSoundManager():PlaySound("anomaly", false, 1.0)
            randomteleport.a(global.player)               -- Random Teleport (100~200 tiles)
            global.processingEvent = false
            global.b(" random_teleport FUNCTION END")
        end,
    },
    -- ── 백룸 탈출 (backroom): 더미 처리 ────────────────────────────────────────
    -- 현재 실사용 안 함. exile과 동일 정책 — 코드/샌드박스 옵션은 보존, 발동만
    -- 비활성화. 원본 로직(features/backroom.lua)은 재활성화 시 주석 해제.
    ["backroom"] = {
        immediate = true,
        fn = function()
            -- global.b(" backroom FUNCTION START")
            -- getSoundManager():PlaySound("glitch", false, 1.0)
            -- backroom.a(global.player)                     -- Backroom
            -- global.b(" backroom FUNCTION END")
            global.processingEvent = false
        end,
    },
    ["missile"] = {
        -- 안전지대(세이프하우스 +10타일) 처리는 샌드박스 "세이프존 폭격 방지"
        -- (Bombard_SafeZoneBlock) 옵션을 따른다. SandboxVars는 게임 로드 후에만
        -- 존재하므로 반드시 발동 시점에 읽는다.
        --   옵션 ON(기본)  -> immediate=false. 좀비룰렛/뛰좀과 동일하게 큐박스에서
        --                     락이 걸리고, 안전지대를 벗어날 때까지 폭격이 미뤄진다.
        --   옵션 OFF      -> immediate=true. 기존 동작대로 안전지대에서도 그냥 터진다.
        --   옵션 없음(구 세이브) -> nil이므로 기본값 ON 취급.
        immediate = function()
            local sv = SandboxVars and SandboxVars.PongDu
            return sv ~= nil and sv.Bombard_SafeZoneBlock == false
        end,
        fn = function()
            global.b(" DONATION EXPLOSION START")
            getSoundManager():PlaySound("alert", false, 1.0)
            sendClientCommand("PongDuDonation", "PlayAlert", {
                ["x"] = global.player:getX(),
                ["y"] = global.player:getY(),
                ["r"] = 40,
            })
            bombard.b(global.player)                      -- Missile Strike
            global.processingEvent = false
            global.b(" DONATION EXPLOSION END")
        end,
    },
    ["random_skill_potion"] = {
        immediate = true,
        fn = function(sender)
            local itemId = pickSerum()
            local item = global.player:getInventory():AddItem("t3chzzkDonation." .. itemId)
            if item then item:setName((sender or "") .. "'s " .. item:getDisplayName()) end
            global.processingEvent = false
        end,
    },
    ["rise_up_dead_man"] = {
        immediate = true,
        fn = function(sender)
            riseup.a(global.player)
            global.processingEvent = false
        end,
    },


    -- ── 신규 기획 (스텁, 미구현) ──────────────────────────────────────────────
    -- 각 fn은 필요한 로직으로 채우면 됨. processingEvent 해제 잊지 말 것.
    ["random_weapon"] = {
        immediate = true,
        fn = function(sender)
            -- 50/50: 근접무기상자 / 원거리무기상자. 상자를 열면 t3RandomWeapon 확률표로 무기 1개.
            local boxId = (ZombRand(100) < 50) and "weapon_box_melee" or "weapon_box_ranged"
            local item = global.player:getInventory():AddItem("t3chzzkDonation." .. boxId)
            if item then
                item:setName((sender or "") .. "'s " .. item:getDisplayName())
                item:getModData().t3Donor = sender or ""
            end
            global.processingEvent = false
        end,
    },
    ["vehicle_drop"] = {
        immediate = true,
        fn = function(sender)
            -- 개봉하면 t3VehicleDrop.OpenKit이 실행되어 근처 실외에 차량을 소환한다.
            local item = global.player:getInventory():AddItem("t3chzzkDonation.vehicle_drop_kit")
            if item then
                item:setName((sender or "") .. "'s " .. item:getDisplayName())
                item:getModData().t3Donor = sender or ""
            end
            global.processingEvent = false
        end,
    },
    ["revive_ticket"] = {
        immediate = true,
        fn = function(sender)
            -- TODO: 기절 즉시부활 티켓
            global.processingEvent = false
        end,
    },
    ["inv_save_ticket"] = {
        immediate = true,
        fn = function(sender)
            -- 인벤세이브권: 소지한 채 사망(좀비화 포함)하면 자동 발동/소모되어
            -- 사망 시점 인벤토리 전체를 리스폰 후 돌려받는다 (features/invsave.lua).
            local item = global.player:getInventory():AddItem("t3chzzkDonation.inv_save_ticket")
            if item then
                item:setName((sender or "") .. "'s " .. item:getDisplayName())
                item:getModData().t3Donor = sender or ""
            end
            global.processingEvent = false
        end,
    },
    ["mutant_spawn"] = {
        immediate = false,
        fn = function(sender)
            mutantspawn.a(sender)            -- 스크리머/브루트/로치 중 1마리
            global.processingEvent = false
        end,
    },
    ["secret_passage_kit"] = {
        immediate = true,
        fn = function(sender)
            -- TODO: 비밀통로 공사키트
            global.processingEvent = false
        end,
    },
    ["horde_night"] = {
        immediate = true,
        fn = function(sender)
            -- TODO: 호드나이트
            global.processingEvent = false
        end,
    },
    ["zombie_rain"] = {
        -- 안전지대 처리는 샌드박스 "세이프존 좀비 레인 방지"(Rain_SafeZoneBlock)를
        -- 따른다. missile과 달리 기본값이 꺼짐이라, 옵션이 명시적으로 켜져 있을
        -- 때만 대기(immediate=false)로 넘어간다.
        --   옵션 OFF(기본) / 옵션 없음(구 세이브) -> immediate=true. 안전지대에서도 그대로 발동.
        --   옵션 ON                              -> immediate=false. 벗어날 때까지 큐박스에서 락.
        immediate = function()
            local sv = SandboxVars and SandboxVars.PongDu
            return not (sv ~= nil and sv.Rain_SafeZoneBlock == true)
        end,
        fn = function(sender)
            global.b(" ZOMBIE RAIN START")
            zombierain.b(global.player, sender)           -- Zombie Rain
            global.processingEvent = false
            global.b(" ZOMBIE RAIN END")
        end,
    },
}

-- isValid(featureId) -> true if this featureId maps to a real reward.
function rewardManager.isValid(featureId)
    return rewardHandlers[featureId] ~= nil
end

-- getFeatureIds() -> 등록된 featureId 전체를 알파벳순 배열로 반환.
-- 어드민 테스트 메뉴(DonationTestMenu)가 항목을 동적으로 뽑는 데 쓴다.
-- rewardHandlers에 기능을 추가/삭제하면 메뉴에도 자동 반영됨 (별도 관리 불필요).
function rewardManager.getFeatureIds()
    local ids = {}
    for id, _ in pairs(rewardHandlers) do
        table.insert(ids, id)
    end
    table.sort(ids)
    return ids
end

-- entry.immediate 평가. 값이 함수면 런타임에 호출해서 판정한다.
-- (샌드박스 옵션에 따라 안전지대 정책이 바뀌는 기능용 - 예: missile)
local function isImmediate(entry)
    if entry == nil then return false end
    local im = entry.immediate
    if type(im) == "function" then
        local ok = im()
        return ok == true
    end
    return im == true
end

-- isZoneBlocked(featureId) -> true면 안전지대 안에서는 발동 불가(immediate=false).
-- 도네큐박스가 슬롯에 자물쇠(락) 표시를 할지 판단할 때 쓴다.
function rewardManager.isZoneBlocked(featureId)
    local entry = rewardHandlers[featureId]
    if entry == nil then return false end
    return not isImmediate(entry)
end

-- applyReward(featureId, sender, callback)  [public name: .a]
-- immediate 판정이 false인 기능은 플레이어가 안전지대를 벗어날 때까지 대기(5초마다 재확인).
-- 상시 대기 대상: zombie_roulette / sprinter5 / mutant_spawn
-- 조건부 대기 대상: missile (Bombard_SafeZoneBlock 켜짐, 기본 ON)
--                   zombie_rain (Rain_SafeZoneBlock 켜짐, 기본 OFF)
function rewardManager.a(featureId, sender, callback)
    global.player = getPlayer()
    if not global.player then return end
    global.stats = global.player:getStats()
    global.processingEvent = true

    local entry = rewardHandlers[featureId]
    local skipZoneWait = isImmediate(entry)

    if not skipZoneWait and zone.a(global.player) then
        print("[PongDu] Reward '" .. tostring(featureId) .. "' deferred: player is inside a safe zone.")
        local elapsed = 0
        local function waitAndApply()
            elapsed = elapsed + getGameTime():getTimeDelta() * 1000
            if elapsed >= 5000 then
                elapsed = 0
                global.player = getPlayer()
                if not global.player then
                    Events.OnTick.Remove(waitAndApply)
                    global.processingEvent = false
                    return
                end
                if not zone.a(global.player) then
                    Events.OnTick.Remove(waitAndApply)
                    if entry then
                        entry.fn(sender or "")
                    else
                        global.processingEvent = false
                    end
                else
                    if callback then callback() end
                end
            end
        end
        Events.OnTick.Add(waitAndApply)
    else
        if entry then
            entry.fn(sender or "")
        else
            global.processingEvent = false
        end
    end
end

-- queueReward(reward)  [public name: .b]
function rewardManager.b(reward)
    table.insert(global.rewardQueue, reward)
end

-- processQueue()  [public name: .c]
function rewardManager.c()
    if #global.rewardQueue == 0 or global.processingEvent then return end
    global.processingEvent = true

    local raw = table.remove(global.rewardQueue, 1)
    -- format: "username,amount,optionalmessage"
    local username, amount, message = raw:match("([^,]+),([^,]+),?([^,]*)")

    global.player = getPlayer()
    if not global.player then global.processingEvent = false return end
    global.stats = global.player:getStats()

    if message and message ~= "" then
        global.player:Say(message)
    end

    local entry = rewardHandlers[amount]
    if entry then entry.fn() else global.processingEvent = false end
end

return rewardManager


