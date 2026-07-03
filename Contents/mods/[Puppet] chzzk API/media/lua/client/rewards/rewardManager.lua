local rewardManager = {}

local bandit     = require("features/hitman")
local teleport   = require("features/teleport")
local backroom   = require("features/backroom")
local bombard    = require("features/bombard")
local eventUtils = require("utils/Event")
local zone       = require("utils/zone")
local zombie     = require("features/zombie")
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
-- immediate=true 인 기능은 안전지대 안에서도 즉시 발동 (백신/추방/백룸/미사일 원래 특성 유지).
local rewardHandlers = {
    ["debuff_roulette"] = {
        immediate = false,
        fn = function()
            eventUtils.a(false)                           -- Debuff Roulette
        end,
    },
    ["buff_roulette"] = {
        immediate = false,
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
        immediate = false,
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
        immediate = false,
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
            sendClientCommand("Schedule", "PlayAlert", {
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
        immediate = false,
        fn = function(sender)
            local itemId = pickSerum()
            local item = global.player:getInventory():AddItem("t3chzzkDonation." .. itemId)
            if item then item:setName((sender or "") .. "'s " .. item:getDisplayName()) end
            global.processingEvent = false
        end,
    },


    -- ── 신규 기획 (스텁, 미구현) ──────────────────────────────────────────────
    -- 각 fn은 필요한 로직으로 채우면 됨. processingEvent 해제 잊지 말 것.
    ["random_weapon"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: 랜덤 무기 뽑기
            global.processingEvent = false
        end,
    },
    ["vehicle_kit"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: 차량소환키트
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
    ["cdda_spawn"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: CDDA 스크리머/브루트 소환
            global.processingEvent = false
        end,
    },
    ["secret_passage_kit"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: 비밀통로 공사키트
            global.processingEvent = false
        end,
    },
    ["horde_night"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: 호드나이트
            global.processingEvent = false
        end,
    },
    ["rise_up_dead_man"] = {
        immediate = false,
        fn = function(sender)
            -- TODO: 라이즈 업 데드 맨 (시체 전부 좀비로 부활)
            global.processingEvent = false
        end,
    },
}

-- isValid(featureId) -> true if this featureId maps to a real reward.
function rewardManager.isValid(featureId)
    return rewardHandlers[featureId] ~= nil
end

-- applyReward(featureId, sender, callback)  [public name: .a]
-- immediate=true 기능(백신/추방/백룸/미사일/부활티켓)은 안전지대 안에서도 즉시 발동.
-- 나머지는 플레이어가 안전지대를 벗어날 때까지 대기 (5초마다 재확인).
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


