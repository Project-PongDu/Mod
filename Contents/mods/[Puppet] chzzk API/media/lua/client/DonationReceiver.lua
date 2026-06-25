require("ISUI/ISPanel")
local config        = require("config")
local rewardManager = require("rewards/rewardManager")
local bandit        = require("features/bandit")
local zombie        = require("features/zombie")
local global        = require("global")

-- ── UI settings ───────────────────────────────────────────────────────────────
local uiSettings = { panelScale = 1.0 }

local function saveUISettings()
    local w = getFileWriter("DonationUI.ini", true, false)
    if not w then return end
    w:write("panelScale=" .. tostring(uiSettings.panelScale) .. "\n")
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
        line = r:readLine()
    end
    r:close()
end

-- ── Panel layout ──────────────────────────────────────────────────────────────
local PANEL_DURATION_MS = 5000

local BASE_W       = 320
local BASE_H       = 84
local BASE_PAD_X   = 20
local BASE_PAD_Y   = 20
local BASE_GAP     = 6
local BASE_ICON_W  = 60
local BASE_IMARGIN = 12

local function sc(v)
    return math.floor(v * uiSettings.panelScale)
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
local labelKey = {
    ["1000"]    = "IGUI_donation_debuff_roulette",
    ["2000"]    = "IGUI_donation_buff_roulette",
    ["5000"]    = "IGUI_donation_zombie_roulette",
    ["10000"]   = "IGUI_donation_sprinter",
    ["20000"]   = "IGUI_donation_bandit_melee",
    ["35000"]   = "IGUI_donation_vaccine",
    ["40000"]   = "IGUI_donation_bandit_ranged",
    ["50000"]   = "IGUI_donation_exile",
    ["100000"]  = "IGUI_donation_backroom",
    ["150000"]  = "IGUI_donation_bombard",
}

local colorMap = {
    ["1000"]    = {0.6, 0.3, 0.9},
    ["2000"]    = {0.3, 0.6, 1.0},
    ["3000"]    = {0.3, 0.9, 0.3},
    ["5000"]    = {0.3, 0.9, 0.3},
    ["10000"]   = {0.9, 0.9, 0.3},
    ["20000"]   = {1.0, 0.4, 0.2},
    ["30000"]   = {1.0, 0.4, 0.2},
    ["35000"]   = {0.3, 0.9, 0.9},
    ["40000"]   = {1.0, 0.2, 0.2},
    ["50000"]   = {0.9, 0.7, 0.1},
    ["100000"]  = {0.9, 0.7, 0.1},
    ["150000"]  = {1.0, 0.3, 0.0},
}

local senderPrefix = {
    ["150"]=true, ["200"]=true, ["300"]=true, ["900"]=true,
    ["3000"]=true, ["5000"]=true, ["10000"]=true,
    ["20000"]=true, ["30000"]=true, ["40000"]=true,
}

local function buildLabel(amount, sender, message)
    local key   = labelKey[amount]
    local label = key and getText(key) or ("Effect " .. amount)
    if senderPrefix[amount] then return sender .. ": " .. label end
    if amount == "35000" then
        if message and message ~= "" then return sender .. ": " .. label .. ", " .. message end
        return sender .. ": " .. label
    end
    return label
end

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
    return b
end

function DonationEntryPanel:initialise()
    ISPanel.initialise(self)
end

function DonationEntryPanel:render()
    local e     = self.entry
    local rem   = math.max(0, e.remaining_ms)
    local prog  = rem / PANEL_DURATION_MS
    local secs  = math.max(0, math.ceil(rem / 1000))
    local col   = colorMap[e.amount] or {0.5, 0.5, 0.5}
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
    self:drawText(tostring(secs) .. "s", self.width - sc(38), sc(10), 1, 0.95, 0.35, 1, UIFont.Large)

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

-- ── Panel stack ───────────────────────────────────────────────────────────────
local function repositionPanels()
    local x = getCore():getScreenWidth() - sc(BASE_W) - BASE_PAD_X
    local y = BASE_PAD_Y
    for _, p in ipairs(panelList) do
        p:setX(x)
        p:setY(y)
        p:setWidth(sc(BASE_W))
        p:setHeight(sc(BASE_H))
        y = y + sc(BASE_H) + sc(BASE_GAP)
    end
end

local function addPanel(entry)
    local p = DonationEntryPanel:new(entry)
    p:initialise()
    p:addToUIManager()
    table.insert(panelList, p)
    repositionPanels()
    entry.panel = p
end

local function removePanel(entry)
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
local function applyDonation(amount, sender, message)
    amount = tostring(amount or "")
    local entry = {
        label        = buildLabel(amount, sender, message),
        sender       = sender,
        remaining_ms = PANEL_DURATION_MS,
        amount       = amount,
        applied      = false,   -- false = prep countdown running; true = effect already fired
    }
    -- Fired by onTick when the prep countdown reaches 0. rewardManager.a keeps
    -- processingEvent held through the effect, then its callback re-shows the
    -- panel as an "applied" confirmation for another PANEL_DURATION_MS.
    entry.fire = function()
        rewardManager.a(entry.amount, entry.sender, function()
            removePanel(entry)
            entry.remaining_ms = PANEL_DURATION_MS
            local found = false
            for _, e in ipairs(activeEntries) do if e == entry then found = true break end end
            if not found then table.insert(activeEntries, entry) end
            addPanel(entry)
        end)
    end
    global.processingEvent = true   -- hold the queue through prep countdown + effect
    table.insert(activeEntries, entry)
    addPanel(entry)
end

-- ── Client-side donation file poller (풉키 방식) ──────────────────────────────
-- Each client reads ITS OWN queue file from this machine's Zomboid/Lua folder,
-- so on a dedicated server every streamer's donations affect only themselves.
-- The external donation program writes lines to:  Zomboid/Lua/<config.filePath>
--   line format:  amount,sender,message   (sender & message optional)
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
        local amount, sender, message = raw:match("^([^,]+),?([^,]*),?(.*)$")
        if amount and amount ~= "" then
            amount = tostring(amount)
            -- Stats: forward the raw line to the host for aggregation (ALL donations,
            -- valid or not -- the Python report decides what to count).
            sendClientCommand("DonationStats", "Record", { line = raw })
            -- Effect: only queue valid tiers (invalid amounts do nothing in-game).
            if rewardManager.isValid(amount) then
                table.insert(donationQueue, {
                    amount  = amount,
                    sender  = urldecode(sender or ""),
                    message = urldecode(message or ""),
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
    applyDonation(entry.amount, entry.sender, entry.message)
end

-- Kept as a harmless fallback if a server ever pushes Donation/Apply directly.
local function onServerCommand(module, command, data)
    if module ~= "Donation" or command ~= "Apply" then return end
    applyDonation(
        tostring(data.amount or ""),
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
