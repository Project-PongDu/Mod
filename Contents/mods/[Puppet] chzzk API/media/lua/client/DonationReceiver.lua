require("ISUI/ISPanel")
local config        = require("config")
local rewardManager = require("rewards/rewardManager")
local bandit        = require("features/hitman")
local zombie        = require("features/zombie")
local global        = require("global")

-- ── UI settings ───────────────────────────────────────────────────────────────
-- anchorX/anchorY: nil = default top-right. Set by dragging any panel; persisted.
local uiSettings = { panelScale = 1.0, anchorX = nil, anchorY = nil }

local function saveUISettings()
    local w = getFileWriter("DonationUI.ini", true, false)
    if not w then return end
    w:write("panelScale=" .. tostring(uiSettings.panelScale) .. "\n")
    if uiSettings.anchorX ~= nil then
        w:write("anchorX=" .. tostring(uiSettings.anchorX) .. "\n")
        w:write("anchorY=" .. tostring(uiSettings.anchorY) .. "\n")
    end
    w:close()
end

local function loadUISettings()
    if not fileExists("DonationUI.ini") then return end
    local r = getFileReader("DonationUI.ini", true)
    if not r then return end
    local line = r:readLine()
    while line do
        local k, v = line:match("^(%w+)=(.+)$")
        if k == "panelScale" then uiSettings.panelScale = tonumber(v) or 1.0 end
        if k == "anchorX" then uiSettings.anchorX = tonumber(v) end
        if k == "anchorY" then uiSettings.anchorY = tonumber(v) end
        line = r:readLine()
    end
    r:close()
end

-- ── Panel layout ──────────────────────────────────────────────────────────────
-- PANEL_DURATION_MS is now ONLY the "applied" confirmation duration (fixed 5s).
-- The prep countdown before the effect fires comes from the sandbox option
-- Hitmans.Donation_PrepDelay (0..10s) -- see prepDurationMs().
local PANEL_DURATION_MS = 5000

local BASE_W       = 320
local BASE_H       = 84
local BASE_PAD_X   = 20
local BASE_PAD_Y   = 80
local BASE_GAP     = 6
local BASE_ICON_W  = 60
local BASE_IMARGIN = 12
local BASE_CLOSE_W = 20      -- close ("X") hit area, top-right corner of each panel

local function sc(v)
    return math.floor(v * uiSettings.panelScale)
end

-- ── Sandbox options (server-wide) ─────────────────────────────────────────────
-- Read at use time (SandboxVars is not populated at file-load time).
local function showPanelEnabled()
    local sv = SandboxVars and SandboxVars.Hitmans
    if sv and sv.Donation_ShowPanel == false then return false end
    return true      -- option missing (old save) -> default: show
end

local function prepDurationMs()
    local sv = SandboxVars and SandboxVars.Hitmans
    local s = sv and tonumber(sv.Donation_PrepDelay)
    if s == nil then s = 5 end
    if s < 0 then s = 0 elseif s > 10 then s = 10 end
    return math.floor(s * 1000)
end

-- ── URL decode ────────────────────────────────────────────────────────────────
local function urldecode(s)
    return (s:gsub("%%(%x%x)", function(b) return string.char(tonumber(b, 16)) end))
end

local activeEntries = {}

-- ── Label / colour tables ─────────────────────────────────────────────────────
-- Effect labels are resolved via getText() at render time (see buildLabel),
-- so the Korean text lives in media/lua/shared/Translate/KO/IG_UI_KO.txt,
-- never as raw/escaped Korean in this file.
-- ※ featureId 키. random_weapon 이하 8개는 번역 문자열이 아직 없어서 getText가
-- 키 이름을 그대로 보여줌 -- 기능 구현할 때 KO 번역 파일에 같이 추가할 것.
local labelKey = {
    ["debuff_roulette"]      = "IGUI_donation_debuff_roulette",
    ["buff_roulette"]        = "IGUI_donation_buff_roulette",
    ["zombie_roulette"]      = "IGUI_donation_zombie_roulette",
    ["sprinter5"]            = "IGUI_donation_sprinter",
    ["bandit_melee"]         = "IGUI_donation_bandit_melee",
    ["vaccine"]              = "IGUI_donation_vaccine",
    ["bandit_ranged"]        = "IGUI_donation_bandit_ranged",
    ["exile"]                = "IGUI_donation_exile",
    ["backroom"]             = "IGUI_donation_backroom",
    ["missile"]              = "IGUI_donation_bombard",
    ["random_weapon"]        = "IGUI_donation_random_weapon",
    ["random_skill_potion"]  = "IGUI_donation_random_skill_potion",
    ["vehicle_kit"]          = "IGUI_donation_vehicle_kit",
    ["revive_ticket"]        = "IGUI_donation_revive_ticket",
    ["mutant_spawn"]         = "IGUI_donation_mutant_spawn",
    ["secret_passage_kit"]   = "IGUI_donation_secret_passage_kit",
    ["horde_night"]          = "IGUI_donation_horde_night",
    ["rise_up_dead_man"]     = "IGUI_donation_rise_up_dead_man",
}

local colorMap = {
    ["debuff_roulette"]      = {0.6, 0.3, 0.9},
    ["buff_roulette"]        = {0.3, 0.6, 1.0},
    ["zombie_roulette"]      = {0.3, 0.9, 0.3},
    ["sprinter5"]            = {0.9, 0.9, 0.3},
    ["bandit_melee"]         = {1.0, 0.4, 0.2},
    ["vaccine"]              = {0.3, 0.9, 0.9},
    ["bandit_ranged"]        = {1.0, 0.2, 0.2},
    ["exile"]                = {0.9, 0.7, 0.1},
    ["backroom"]             = {0.9, 0.7, 0.1},
    ["missile"]              = {1.0, 0.3, 0.0},
    ["random_weapon"]        = {0.8, 0.8, 0.2},
    ["random_skill_potion"]  = {0.5, 0.9, 0.5},
    ["vehicle_kit"]          = {0.6, 0.6, 1.0},
    ["revive_ticket"]        = {1.0, 0.8, 0.8},
    ["mutant_spawn"]         = {0.7, 0.2, 0.2},
    ["secret_passage_kit"]   = {0.6, 0.4, 0.2},
    ["horde_night"]          = {0.9, 0.1, 0.1},
    ["rise_up_dead_man"]     = {0.4, 0.1, 0.5},
}

local function buildLabel(featureId, sender, message)
    local key   = labelKey[featureId]
    local label = key and getText(key) or ("Effect " .. tostring(featureId))
    if featureId == "vaccine" and message and message ~= "" then
        return label .. ", " .. message
    end
    return label
end

-- forward declarations (mouse handlers on the panel need these)
local repositionPanels
local removePanel

-- ── Donation entry panel ──────────────────────────────────────────────────────
local DonationEntryPanel = ISPanel:derive("DonationEntryPanel")
local panelList = {}

function DonationEntryPanel:new(entry)
    local b = ISPanel:new(BASE_PAD_X, BASE_PAD_Y, sc(BASE_W), sc(BASE_H))
    setmetatable(b, self)
    self.__index = self
    b.background  = false
    b.borderColor = {r=0, g=0, b=0, a=0}
    b.entry = entry
    b.dragging = false
    return b
end

function DonationEntryPanel:initialise()
    ISPanel.initialise(self)
end

function DonationEntryPanel:render()
    local e     = self.entry
    local rem   = math.max(0, e.remaining_ms)
    local dur   = e.duration_ms or PANEL_DURATION_MS
    if dur <= 0 then dur = 1 end
    local prog  = rem / dur
    local secs  = math.max(0, math.ceil(rem / 1000))
    local col   = colorMap[e.featureId] or {0.5, 0.5, 0.5}
    local icon  = sc(BASE_ICON_W)
    local im    = sc(BASE_IMARGIN)
    local textX = im + icon + im

    self:drawRect(0, 0, self.width, self.height, 0.85, 0.06, 0.06, 0.08)
    self:drawRect(0, 0, 4, self.height, 1, col[1], col[2], col[3])

    local iconY = math.floor((self.height - icon) / 2) - sc(6)
    self:drawRect(im, iconY, icon, icon, 1, col[1], col[2], col[3])
    self:drawRectBorder(im, iconY, icon, icon, 0.6, 1, 1, 1)

    self:drawText(e.label or "?", textX, sc(12), 1, 1, 1, 1, UIFont.Medium)
    if e.sender and e.sender ~= "" then
        self:drawText("from " .. e.sender, textX, sc(34), 0.7, 0.7, 0.7, 1, UIFont.Small)
    end
    self:drawText(tostring(secs) .. "s", self.width - sc(56), sc(10), 1, 0.95, 0.35, 1, UIFont.Large)

    -- close button (top-right corner)
    self:drawText("X", self.width - sc(15), sc(2), 0.6, 0.6, 0.6, 1, UIFont.Small)

    local barX = textX
    local barY = self.height - sc(16)
    local barW = self.width - barX - sc(12)
    local barH = math.max(1, sc(6))
    self:drawRect(barX, barY, barW, barH, 1, 0.15, 0.15, 0.15)
    self:drawRect(barX, barY, math.floor(barW * prog), barH, 1, col[1], col[2], col[3])
    self:drawRectBorder(barX, barY, barW, barH, 0.4, 1, 1, 1)
    ISPanel.render(self)
end

function DonationEntryPanel:update() end

-- Drag: moving ANY panel moves the whole stack anchor (persisted on release).
-- Close: X in the top-right corner hides THIS panel only -- the countdown keeps
-- running invisibly, so the donation effect still fires on schedule.
function DonationEntryPanel:onMouseDown(x, y)
    if not self:getIsVisible() then return end
    if x >= self.width - sc(BASE_CLOSE_W) and y <= sc(BASE_CLOSE_W) then
        removePanel(self.entry)
        return true
    end
    self.dragging = true
    self:bringToTop()
    return true
end

function DonationEntryPanel:onMouseMove(dx, dy)
    if not self.dragging then return end
    if uiSettings.anchorX == nil then          -- first drag: seed anchor from current pos
        local first = panelList[1] or self
        uiSettings.anchorX = first:getX()
        uiSettings.anchorY = first:getY()
    end
    uiSettings.anchorX = uiSettings.anchorX + dx
    uiSettings.anchorY = uiSettings.anchorY + dy
    repositionPanels()
end

DonationEntryPanel.onMouseMoveOutside = DonationEntryPanel.onMouseMove

function DonationEntryPanel:onMouseUp(x, y)
    if self.dragging then
        self.dragging = false
        saveUISettings()
    end
end

DonationEntryPanel.onMouseUpOutside = DonationEntryPanel.onMouseUp

-- ── Panel stack ───────────────────────────────────────────────────────────────
repositionPanels = function()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local x, y
    if uiSettings.anchorX ~= nil then
        x, y = uiSettings.anchorX, uiSettings.anchorY or BASE_PAD_Y
    else
        x, y = sw - sc(BASE_W) - BASE_PAD_X, BASE_PAD_Y
    end
    -- keep the stack on screen (resolution change / bad ini values)
    x = math.max(0, math.min(x, sw - sc(BASE_W)))
    y = math.max(0, math.min(y, sh - sc(BASE_H)))
    for _, p in ipairs(panelList) do
        p:setX(x)
        p:setY(y)
        p:setWidth(sc(BASE_W))
        p:setHeight(sc(BASE_H))
        y = y + sc(BASE_H) + sc(BASE_GAP)
    end
end

local function addPanel(entry)
    if not showPanelEnabled() then return end   -- sandbox: UI off -> no panel, effect unaffected
    local p = DonationEntryPanel:new(entry)
    p:initialise()
    p:addToUIManager()
    table.insert(panelList, p)
    repositionPanels()
    entry.panel = p
end

removePanel = function(entry)
    if not entry.panel then return end
    entry.panel:removeFromUIManager()
    for i = #panelList, 1, -1 do
        if panelList[i] == entry.panel then table.remove(panelList, i) break end
    end
    entry.panel = nil
    repositionPanels()
end

-- ── Settings panel ────────────────────────────────────────────────────────────
local DonationSettingsPanel = ISPanel:derive("DonationSettingsPanel")

function DonationSettingsPanel:new()
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    local w, h = 240, 100
    local o = ISPanel:new(sw / 2 - w / 2, sh / 2 - h / 2, w, h)
    setmetatable(o, self)
    self.__index = self
    o.backgroundColor = {r=0.07, g=0.07, b=0.09, a=0.96}
    o.borderColor     = {r=0.45, g=0.45, b=0.45, a=1.0}
    return o
end

function DonationSettingsPanel:createChildren()
    local title = ISLabel:new(10, 8, 20, "Donation UI Scale", 1, 1, 1, 1, UIFont.Medium, true)
    self:addChild(title)

    local btnMinus = ISButton:new(10, 36, 28, 24, "-", self, DonationSettingsPanel.scaleDown)
    btnMinus:initialise()
    btnMinus:instantiate()
    self:addChild(btnMinus)

    local btnPlus = ISButton:new(44, 36, 28, 24, "+", self, DonationSettingsPanel.scaleUp)
    btnPlus:initialise()
    btnPlus:instantiate()
    self:addChild(btnPlus)

    local btnResetPos = ISButton:new(158, 36, 72, 24, "Reset Pos", self, DonationSettingsPanel.resetPos)
    btnResetPos:initialise()
    btnResetPos:instantiate()
    self:addChild(btnResetPos)

    local btnSave = ISButton:new(10, 66, 100, 24, "Save & Close", self, DonationSettingsPanel.saveAndClose)
    btnSave:initialise()
    btnSave:instantiate()
    self:addChild(btnSave)

    local btnClose = ISButton:new(118, 66, 60, 24, "Close", self, DonationSettingsPanel.onClose)
    btnClose:initialise()
    btnClose:instantiate()
    self:addChild(btnClose)
end

function DonationSettingsPanel:render()
    ISPanel.render(self)
    self:drawText(
        string.format("Scale: %.1fx", uiSettings.panelScale),
        80, 40, 1, 1, 0.6, 1, UIFont.Small
    )
end

function DonationSettingsPanel:scaleDown()
    local v = math.floor((uiSettings.panelScale - 0.1) * 10 + 0.5) / 10
    uiSettings.panelScale = math.max(0.5, v)
    repositionPanels()
end

function DonationSettingsPanel:scaleUp()
    local v = math.floor((uiSettings.panelScale + 0.1) * 10 + 0.5) / 10
    uiSettings.panelScale = math.min(2.0, v)
    repositionPanels()
end

function DonationSettingsPanel:resetPos()
    uiSettings.anchorX = nil
    uiSettings.anchorY = nil
    saveUISettings()
    repositionPanels()
end

function DonationSettingsPanel:saveAndClose()
    saveUISettings()
    self:removeFromUIManager()
end

function DonationSettingsPanel:onClose()
    self:removeFromUIManager()
end

local function openSettingsPanel()
    local p = DonationSettingsPanel:new()
    p:initialise()
    p:createChildren()
    p:addToUIManager()
end

-- ── ESC pause menu hook ───────────────────────────────────────────────────────
if ISPauseMenu then
    local _origCreate = ISPauseMenu.createChildren
    function ISPauseMenu:createChildren()
        _origCreate(self)
        local btn = ISButton:new(
            self.width / 2 - 90, self.height - 32,
            180, 22, "Donation UI Scale", self,
            function() openSettingsPanel() end
        )
        btn:initialise()
        btn:instantiate()
        self:addChild(btn)
        self:setHeight(self.height + 30)
    end
end

-- ── Apply one donation locally (panel + reward) ──────────────────────────────
-- amount는 통계/로그용, featureId가 실제 디스패치 키 (퍼펫 API가 amount->featureId
-- 매핑을 보고 rewards.txt에 같이 실어 보낸다).
-- Prep countdown duration = sandbox Hitmans.Donation_PrepDelay (0..10s).
-- 0초면 준비 패널을 아예 안 띄우고 즉시 발동 (확인 패널은 그대로 5초).
local function applyDonation(amount, featureId, sender, message)
    amount    = tostring(amount or "")
    featureId = tostring(featureId or "")
    local prepMs = prepDurationMs()
    local entry = {
        label        = buildLabel(featureId, sender, message),
        sender       = sender,
        remaining_ms = prepMs,
        duration_ms  = prepMs,   -- render progress bar denominator (prep phase)
        amount       = amount,
        featureId    = featureId,
        applied      = false,   -- false = prep countdown running; true = effect already fired
    }
    -- Fired by onTick when the prep countdown reaches 0. rewardManager.a keeps
    -- processingEvent held through the effect, then its callback re-shows the
    -- panel as an "applied" confirmation for another PANEL_DURATION_MS.
    entry.fire = function()
        rewardManager.a(entry.featureId, entry.sender, function()
            removePanel(entry)
            entry.remaining_ms = PANEL_DURATION_MS
            entry.duration_ms  = PANEL_DURATION_MS
            local found = false
            for _, e in ipairs(activeEntries) do if e == entry then found = true break end end
            if not found then table.insert(activeEntries, entry) end
            addPanel(entry)
        end)
    end
    global.processingEvent = true   -- hold the queue through prep countdown + effect
    if prepMs <= 0 then
        entry.applied = true        -- 대기 0초: 준비 카운트다운/패널 생략, 즉시 발동
        entry.fire()                -- 콜백이 activeEntries 등록 + 확인 패널 표시까지 처리
        return
    end
    table.insert(activeEntries, entry)
    addPanel(entry)
end

-- ── Client-side donation file poller (풉키 방식) ──────────────────────────────
-- Each client reads ITS OWN queue file from this machine's Zomboid/Lua folder,
-- so on a dedicated server every streamer's donations affect only themselves.
-- The external donation program writes lines to:  Zomboid/Lua/<config.filePath>
--   line format:  amount,featureId,sender,message   (featureId/sender/message optional)
--   featureId는 퍼펫 API(GUI)가 유저의 amount->featureId 매핑을 보고 채워 넣는다.
--   매핑에 없는 금액이면 featureId가 빈 문자열로 오고, 통계에만 잡힌다 (게임 효과 없음).
-- In-memory FIFO queue. Donations are applied ONE AT A TIME, gated by
-- global.processingEvent, so a burst of simultaneous donations is never
-- dropped -- they queue up and fire strictly in order (oldest first).
local donationQueue = {}   -- index 1 = oldest

local pollTimer = 0
local function pollDonationFile()
    pollTimer = pollTimer + getGameTime():getTimeDelta()
    if pollTimer < config.targetTime then return end
    pollTimer = 0

    local reader = getFileReader(config.filePath, true)
    if not reader then return end
    local lines = {}
    local line = reader:readLine()
    while line do
        if line ~= "" then table.insert(lines, line) end
        line = reader:readLine()
    end
    reader:close()
    if #lines == 0 then return end

    -- Consume the file immediately; the lines are now safe in the queue.
    local w = getFileWriter(config.filePath, false, false)
    if w then w:write("") w:close() end

    for _, raw in ipairs(lines) do
        local amount, featureId, sender, message = raw:match("^([^,]*),?([^,]*),?([^,]*),?(.*)$")
        if amount and amount ~= "" then
            amount    = tostring(amount)
            featureId = featureId or ""
            -- Stats: forward the raw line to the host for aggregation (ALL donations,
            -- valid or not -- the Python report decides what to count).
            sendClientCommand("DonationStats", "Record", { line = raw })
            -- Effect: only queue valid featureIds (unmapped amounts do nothing in-game).
            if rewardManager.isValid(featureId) then
                table.insert(donationQueue, {
                    amount    = amount,
                    featureId = featureId,
                    sender    = urldecode(sender or ""),
                    message   = urldecode(message or ""),
                })
            end
        end
    end
end

-- Drain the queue one donation at a time, only while nothing is processing.
-- FIFO: the oldest queued donation fires first, none are ever skipped.
-- applyDonation sets processingEvent, so the next donation waits through this
-- one's prep countdown + effect.
local function consumeDonationQueue()
    if global.processingEvent then return end
    if #donationQueue == 0 then return end
    local entry = table.remove(donationQueue, 1)
    applyDonation(entry.amount, entry.featureId, entry.sender, entry.message)
end

-- Kept as a harmless fallback if a server ever pushes Donation/Apply directly.
local function onServerCommand(module, command, data)
    if module ~= "Donation" or command ~= "Apply" then return end
    applyDonation(
        tostring(data.amount or ""),
        tostring(data.featureId or ""),
        urldecode(tostring(data.sender  or "")),
        urldecode(tostring(data.message or ""))
    )
end
Events.OnServerCommand.Add(onServerCommand)

-- ── OnTick: countdown + queues ────────────────────────────────────────────────
local function onTick()
    local dt = getGameTime():getTimeDelta() * 1000
    local toFire = nil
    for _, entry in ipairs(activeEntries) do
        entry.remaining_ms = entry.remaining_ms - dt
        if entry.remaining_ms <= 0 then
            removePanel(entry)
            if not entry.applied then
                entry.applied = true   -- prep countdown finished: fire the effect now
                toFire = toFire or {}
                toFire[#toFire + 1] = entry
            end
        end
    end
    for i = #activeEntries, 1, -1 do
        if activeEntries[i].remaining_ms <= 0 then table.remove(activeEntries, i) end
    end
    -- Fire after the loops so the reward callback's panel/queue mutations don't
    -- run mid-iteration over activeEntries.
    if toFire then
        for _, e in ipairs(toFire) do e.fire() end
    end
    if bandit then bandit.b() end
    if zombie then zombie.a() end
    pollDonationFile()
    consumeDonationQueue()
end
Events.OnTick.Add(onTick)

-- ── Keys ──────────────────────────────────────────────────────────────────────
Events.OnKeyPressed.Add(function(key)
    if key == 67 then           -- F9: reset stuck processingEvent (emergency unstick)
        global.processingEvent = false
    elseif key == 68 then       -- F10: open UI scale settings
        openSettingsPanel()
    end
end)

-- ── Init ──────────────────────────────────────────────────────────────────────
Events.OnGameStart.Add(loadUISettings)
