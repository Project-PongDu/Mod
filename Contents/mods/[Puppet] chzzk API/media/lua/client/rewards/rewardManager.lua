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
-- mutant_spawn 이 셋만 예외로 안전지대 밖으로 나갈 때까지 대기(immediate=false).
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
            handleZombieSpawn(5, 1, sender)               -- Sprinter x5
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
    ["exile"] = {
        immediate = true,
        fn = function()
            global.b(" exile FUNCTION START")
            getSoundManager():PlaySound("exile_enter", false, 1.0)
            teleport.b(global.player)                     -- Exile Teleport
            global.processingEvent = false
            global.b(" exile FUNCTION END")
        end,
    },
    ["random_teleport"] = {
        immediate = true,
        fn = function()
            global.b(" random_teleport FUNCTION START")
            getSoundManager():PlaySound("exile_enter", false, 1.0)
            randomteleport.a(global.player)               -- Random Teleport (100~200 tiles)
            global.processingEvent = false
            global.b(" random_teleport FUNCTION END")
        end,
    },
    ["backroom"] = {
        immediate = true,
        fn = function()
            global.b(" backroom FUNCTION START")
            getSoundManager():PlaySound("glitch", false, 1.0)
            backroom.a(global.player)                     -- Backroom
            global.processingEvent = false
            global.b(" backroom FUNCTION END")
        end,
    },
    ["missile"] = {
        immediate = true,
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
}

-- isValid(featureId) -> true if this featureId maps to a real reward.
function rewardManager.isValid(featureId)
    return rewardHandlers[featureId] ~= nil
end

-- isZoneBlocked(featureId) -> true면 안전지대 안에서는 발동 불가(immediate=false).
-- 도네큐박스가 슬롯에 자물쇠(락) 표시를 할지 판단할 때 쓴다.
function rewardManager.isZoneBlocked(featureId)
    local entry = rewardHandlers[featureId]
    return entry ~= nil and entry.immediate ~= true
end

-- applyReward(featureId, sender, callback)  [public name: .a]
-- immediate=true 기능은 안전지대 안에서도 즉시 발동 (zombie_roulette / sprinter5 /
-- mutant_spawn 제외 전부). 이 3개만 플레이어가 안전지대를 벗어날 때까지 대기 (5초마다 재확인).
function rewardManager.a(featureId, sender, callback)
    global.player = getPlayer()
    if not global.player then return end
    global.stats = global.player:getStats()
    global.processingEvent = true

    local entry = rewardHandlers[featureId]
    local skipZoneWait = entry and entry.immediate

    if not skipZoneWait and zone.a(global.player) then
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


