local handler = {}

local updateText    = require("utils/updateText")
local moodle        = require("features/moodle")
local zombie        = require("features/zombie")
local global        = require("global")
local zone          = require("utils/zone")

-- Debuff moodle: pick immediately (no scrolling ticker), apply after a short
-- delay -- mirrors zombie roulette (handler.c) instead of the old 6초짜리
-- 슬롯머신 스크롤. 그 스크롤 구간이 길어서 같은 종류가 겹쳐 발동되면
-- global.chosenRandomText/textUpdateTimer를 서로 덮어써 꼬이던 문제도
-- 지연이 500ms로 줄면서 사실상 해소됨.  [.a]
function handler.a(_)
    Events.OnTick.Remove(handler.a)
    updateText.b()
    getSoundManager():PlaySound("ding", false, 1.0)

    local player = getPlayer()
    if not player then global.processingEvent = false return end
    local text = global.chosenRandomText
    global.textUpdateTimer = 0
    global.displayStartTime = 0

    local elapsed = 0
    local function applyDelay()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed >= 500 then
            Events.OnTick.Remove(applyDelay)
            moodle.b(player, text)
            global.processingEvent = false
        end
    end
    Events.OnTick.Add(applyDelay)
end

-- Buff moodle: same treatment as handler.a above.  [.b]
function handler.b(_)
    Events.OnTick.Remove(handler.b)
    updateText.a()
    getSoundManager():PlaySound("ding", false, 1.0)

    local player = getPlayer()
    if not player then global.processingEvent = false return end
    local text = global.chosenRandomText
    global.textUpdateTimer = 0
    global.displayStartTime = 0

    local elapsed = 0
    local function applyDelay()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed >= 500 then
            Events.OnTick.Remove(applyDelay)
            moodle.a(player, text)
            global.processingEvent = false
        end
    end
    Events.OnTick.Add(applyDelay)
end

-- Zombie roulette: pick a random count, then spawn after a short delay.  [.c]
-- B version: no scrolling display; counts are zombie1->2 ... zombie5->6;
-- added a getPlayer nil-guard and a 500ms delay before spawning.
function handler.c()
    Events.OnTick.Remove(handler.c)
    global.isTextUpdateEventAdded = false

    local player = getPlayer()
    if not player then global.processingEvent = false return end

    updateText.c()
    getSoundManager():PlaySound("ding", false, 1.0)

    -- 마릿수는 updateText.c()가 샌드박스 min/max로 이미 추첨해 저장해둔 값
    -- (global.chosenZombieCount)을 그대로 쓴다. 고정 5단계 텍스트 비교 방식은
    -- 범위가 가변이 되면서 제거됨.
    local amount = global.chosenZombieCount or 0
    local data = { amount = amount, sprint = 0, sender = global.currentSender or "" }
    global.currentSender = ""
    global.textUpdateTimer = 0
    global.displayStartTime = 0

    local elapsed = 0
    local function spawnDelay()
        elapsed = elapsed + getGameTime():getTimeDelta() * 1000
        if elapsed >= 500 then
            Events.OnTick.Remove(spawnDelay)
            if zone.a(player) then
                table.insert(global.zombieSpawnQueue, data)
            else
                table.insert(global.zombieSpawnQueue, data)
                zombie.a()
            end
            global.processingEvent = false
        end
    end
    Events.OnTick.Add(spawnDelay)
end

return handler
