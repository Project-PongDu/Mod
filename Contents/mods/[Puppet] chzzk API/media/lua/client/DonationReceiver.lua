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

-- 쿨다운 아이콘 슬롯 레이아웃 (우하단 앵커, 옆으로 다다다 늘어남).
-- 슬롯 하나 = 정사각형. 안에 약어 태그 + 큰 카운트다운 숫자 + 쿨다운 오버레이.
local ICON_SIZE     = 46
local BASE_PAD_X    = 20     -- 화면 우측 여백
local BASE_PAD_Y    = 20     -- 화면 하단 여백
local BASE_GAP      = 6      -- 슬롯 사이 간격
local BASE_CLOSE_W  = 12     -- close ("X") hit area, top-right corner of each slot

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
    ["bandit_melee"]         = "IGUI_donation_hitman_melee",
    ["vaccine"]              = "IGUI_donation_vaccine",
    ["bandit_ranged"]        = "IGUI_donation_hitman_ranged",
    ["exile"]                = "IGUI_donation_exile",
    ["backroom"]             = "IGUI_donation_backroom",
    ["missile"]              = "IGUI_donation_bombard",
    ["random_weapon"]        = "IGUI_donation_random_weapon",
    ["random_skill_potion"]  = "IGUI_donation_random_skill_potion",
    ["vehicle_drop"]         = "IGUI_donation_vehicle_drop",
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
    ["vehicle_drop"]         = {0.6, 0.6, 1.0},
    ["revive_ticket"]        = {1.0, 0.8, 0.8},
    ["mutant_spawn"]         = {0.7, 0.2, 0.2},
    ["secret_passage_kit"]   = {0.6, 0.4, 0.2},
    ["horde_night"]          = {0.9, 0.1, 0.1},
    ["rise_up_dead_man"]     = {0.4, 0.1, 0.5},
}

-- 슬롯 상단에 찍는 짧은 약어 태그. 이미지 에셋 없이 색상+텍스트만으로 효과를
-- 구분하기 위함 (저작권 이슈 없는 순수 텍스트).
local glyphKey = {
    ["debuff_roulette"]      = "디버프",
    ["buff_roulette"]        = "버프",
    ["zombie_roulette"]      = "좀비",
    ["sprinter5"]            = "질주",
    ["bandit_melee"]         = "근접",
    ["vaccine"]              = "백신",
    ["bandit_ranged"]        = "원거리",
    ["exile"]                = "추방",
    ["backroom"]             = "백룸",
    ["missile"]              = "폭격",
    ["random_weapon"]        = "무기",
    ["random_skill_potion"]  = "포션",
    ["vehicle_drop"]         = "공수",
    ["revive_ticket"]        = "부활",
    ["mutant_spawn"]         = "변종",
    ["secret_passage_kit"]   = "통로",
    ["horde_night"]          = "호드",
    ["rise_up_dead_man"]     = "기상",
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
    local sz = sc(ICON_SIZE)
    local b = ISPanel:new(BASE_PAD_X, BASE_PAD_Y, sz, sz)
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
    local isActive = (activeEntries[1] == e)   -- 실제로 카운트다운 중인 건 맨 앞 슬롯뿐
    local rem   = math.max(0, e.remaining_ms)
    local dur   = e.duration_ms or PANEL_DURATION_MS
    if dur <= 0 then dur = 1 end
    local prog  = rem / dur              -- 1 = 방금 시작(쿨다운 꽉 참), 0 = 발동/종료 직전
    local secs  = math.max(0, math.ceil(rem / 1000))
    local col   = colorMap[e.featureId] or {0.5, 0.5, 0.5}
    local w, h  = self.width, self.height

    -- 슬롯 베이스 (바닐라 인벤토리 슬롯 톤) + 효과색 옅은 틴트 (대기 슬롯은 더 흐리게)
    self:drawRect(0, 0, w, h, 0.9, 0.05, 0.05, 0.05)
    self:drawRect(0, 0, w, h, isActive and 0.16 or 0.07, col[1], col[2], col[3])

    -- 상단 약어 태그
    local glyph = glyphKey[e.featureId] or "?"
    self:drawTextCentre(glyph, w / 2, sc(3), col[1], col[2], col[3], isActive and 1 or 0.5, UIFont.Small)

    if isActive then
        -- 쿨다운 오버레이: 남은 비율만큼 위에서 어둡게 덮고, 시간이 지날수록
        -- 아래에서부터 원래 색이 드러난다 (게이지 아이콘처럼 슬롯 자체가 진행바 역할).
        local overlayH = math.floor(h * prog)
        if overlayH > 0 then
            self:drawRect(0, 0, w, overlayH, 0.55, 0, 0, 0)
        end
        self:drawRectBorder(0, 0, w, h, 0.9, col[1], col[2], col[3])
        -- 카운트다운 숫자 (오버레이 위에도 항상 보이도록 마지막에 그림)
        self:drawTextCentre(tostring(secs), w / 2, h / 2 - sc(6), 1, 0.95, 0.35, 1, UIFont.Medium)
    else
        -- 대기 슬롯: 아직 시작 안 함 -- 전체를 어둡게 덮고 "대기중"만 표시,
        -- 카운트다운 숫자는 안 보여준다 (진짜로 안 세고 있으니까).
        self:drawRect(0, 0, w, h, 0.6, 0, 0, 0)
        self:drawRectBorder(0, 0, w, h, 0.5, col[1], col[2], col[3])
        self:drawTextCentre("대기중", w / 2, h / 2 - sc(6), 0.75, 0.75, 0.75, 1, UIFont.Small)
    end

    -- close (우상단 작은 히트영역)
    self:drawText("x", w - sc(11), sc(1), 0.7, 0.7, 0.7, 0.8, UIFont.Small)

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
-- 슬롯 1(가장 오래된 항목)이 앵커에 고정되고, 새 항목이 들어올수록 왼쪽으로
-- 다다다 늘어난다. anchorX/anchorY는 "슬롯 1의 좌상단" 좌표로 취급.
repositionPanels = function()
    local sw  = getCore():getScreenWidth()
    local sh  = getCore():getScreenHeight()
    local sz  = sc(ICON_SIZE)
    local x0, y0
    if uiSettings.anchorX ~= nil then
        x0, y0 = uiSettings.anchorX, uiSettings.anchorY
    else
        x0, y0 = sw - BASE_PAD_X - sz, sh - BASE_PAD_Y - sz
    end
    -- keep the stack on screen (resolution change / bad ini values)
    x0 = math.max(0, math.min(x0, sw - sz))
    y0 = math.max(0, math.min(y0, sh - sz))
    for i, p in ipairs(panelList) do
        p:setX(x0 - (i - 1) * (sz + sc(BASE_GAP)))
        p:setY(y0)
        p:setWidth(sz)
        p:setHeight(sz)
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
    -- Fired by onTick when the prep countdown reaches 0 -- the slot is already
    -- freed by that point (see onTick), so the next queued donation can slide
    -- in immediately. rewardManager.a's own processingEvent flag still governs
    -- its internal safe-zone-wait retries, but no longer gates this file's queue
    -- (see consumeDonationQueue / MAX_QUEUE_SLOTS). If the player is standing in
    -- a safe zone, rewardManager.a's callback below re-shows this same panel
    -- every ~5s as a "still waiting to leave the safe zone" indicator until the
    -- effect actually fires.
    entry.fire = function()
        rewardManager.a(entry.featureId, entry.sender, function()
            removePanel(entry)
            entry.remaining_ms = PANEL_DURATION_MS
            entry.duration_ms  = PANEL_DURATION_MS
            local found = false
            for _, e in ipairs(activeEntries) do if e == entry then found = true break end end
            -- 맨 앞(활성 슬롯)에 다시 꽂는다 -- 이건 새 대기열 항목이 아니라
            -- "안전지대 벗어날 때까지 대기 중"인 기존 항목의 연장이라, 뒤로
            -- 밀리면 다른 대기 항목들에 가려서 재확인이 영영 안 될 수 있음.
            if not found then table.insert(activeEntries, 1, entry) end
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
-- In-memory FIFO queue. Up to MAX_QUEUE_SLOTS donations can be active (counting
-- down / firing) at once -- see consumeDonationQueue below. A burst larger than
-- that just waits its turn in this array; nothing is ever dropped.
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

local MAX_QUEUE_SLOTS = 5   -- 도네큐박스 최대 슬롯 수. 5개는 각자 독립적으로 카운트다운.

-- Drain the queue as long as the queue box has a free slot. Multiple donations
-- can now count down (and fire) concurrently -- a slot frees the instant its
-- own countdown hits 0, and the next waiting donation slides in immediately.
local function consumeDonationQueue()
    while #activeEntries < MAX_QUEUE_SLOTS and #donationQueue > 0 do
        local entry = table.remove(donationQueue, 1)
        applyDonation(entry.amount, entry.featureId, entry.sender, entry.message)
    end
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
    -- 큐박스에서 실제로 카운트다운하는 건 맨 앞(= 화면 우하단 앵커, 가장 먼저
    -- 들어온) 슬롯 하나뿐. 나머지는 자기 차례가 될 때까지 대기 상태로 그대로 있음
    -- (remaining_ms를 안 건드리니 값이 원본 그대로 유지됨).
    local head = activeEntries[1]
    local fired = nil
    if head then
        head.remaining_ms = head.remaining_ms - dt
        if head.remaining_ms <= 0 then
            removePanel(head)
            table.remove(activeEntries, 1)   -- 뒤에 있던 항목들이 한 칸씩 당겨짐
            if not head.applied then
                head.applied = true   -- prep countdown finished: fire the effect now
                fired = head
            end
        end
    end
    -- Fire after touching the list so the reward callback's panel/queue
    -- mutations don't run mid-iteration.
    if fired then fired.fire() end
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
