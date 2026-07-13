require("ISUI/ISPanel")
local config        = require("config")
local rewardManager = require("rewards/rewardManager")
local bandit        = require("features/hitman")
local zombie        = require("features/zombie")
local zone          = require("utils/zone")
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
-- PongDu.Donation_PrepDelay (0..10s) -- see prepDurationMs().
local PANEL_DURATION_MS = 5000

-- 쿨다운 아이콘 슬롯 레이아웃 (우하단 앵커, 옆으로 다다다 늘어남).
-- 슬롯 하나 = 정사각형. 안에 약어 태그 + 큰 카운트다운 숫자 + 쿨다운 오버레이.
local ICON_SIZE     = 80
local BASE_PAD_X    = 20     -- 화면 우측 여백
local BASE_PAD_Y    = 20     -- 화면 상단 여백 (기본 위치 = 우측 최상단일 때)
local BASE_GAP      = 6      -- 슬롯 사이 간격

local function sc(v)
    return math.floor(v * uiSettings.panelScale)
end

-- ── Sandbox options (server-wide) ─────────────────────────────────────────────
-- Read at use time (SandboxVars is not populated at file-load time).
local function showPanelEnabled()
    local sv = SandboxVars and SandboxVars.PongDu
    if sv and sv.Donation_ShowPanel == false then return false end
    return true      -- option missing (old save) -> default: show
end

local function prepDurationMs()
    local sv = SandboxVars and SandboxVars.PongDu
    local s = sv and tonumber(sv.Donation_PrepDelay)
    if s == nil then s = 5 end
    if s < 0 then s = 0 elseif s > 10 then s = 10 end
    return math.floor(s * 1000)
end

-- ── URL decode ────────────────────────────────────────────────────────────────
local function urldecode(s)
    return (s:gsub("%%(%x%x)", function(b) return string.char(tonumber(b, 16)) end))
end

local function urlencode(s)
    return (s:gsub("[^%w%-%.%_%~]", function(c) return string.format("%%%02X", string.byte(c)) end))
end

local activeEntries = {}

-- ── Label / colour tables ─────────────────────────────────────────────────────
-- Effect labels are resolved via getText() at render time (see buildLabel),
-- so the Korean text lives in media/lua/shared/Translate/KO/IG_UI_KO.txt,
-- never as raw/escaped Korean in this file.
-- ※ 예전 주석에 "random_weapon 이하 8개는 번역이 없다"고 돼있었는데 실제로 확인해보니
-- 틀린 얘기였음 -- revive_ticket / secret_passage_kit / horde_night 이 3개만 IG_UI_KO.txt에
-- 없었고 (getText가 키 이름을 그대로 보여주는 중이었음) 나머지는 전부 이미 번역돼있었다.
-- 이 3개는 IG_UI_KO.txt에 추가해서 해결함 (부활 티켓 / 비밀 통로 키트 / 호드 나이트).
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

-- 슬롯 아이콘 이미지 확장 지점. featureId -> 텍스처 경로. 지금은 비어있어서
-- render()가 기존 색상 틴트 + 약어 태그로 폴백함. 나중에 실제 아이콘 이미지를
-- 준비하면 여기에 경로만 채우면 됨 (예: ["missile"] = "media/textures/donation/missile.png").
local iconTexPath = {
    ["debuff_roulette"]      = "media/textures/donation/debuff_roulette.png",
    ["buff_roulette"]        = "media/textures/donation/buff_roulette.png",
    ["zombie_roulette"]      = "media/textures/donation/zombie_roulette.png",
    ["sprinter5"]            = "media/textures/donation/sprinter5.png",
    -- ["bandit_melee"]         = "media/textures/donation/bandit_melee.png",
    ["vaccine"]              = "media/textures/donation/vaccine.png",
    -- ["bandit_ranged"]        = "media/textures/donation/bandit_ranged.png",
    -- ["exile"]                = "media/textures/donation/exile.png",
    -- ["backroom"]             = "media/textures/donation/backroom.png",
    ["missile"]              = "media/textures/donation/missile.png",
    -- ["random_weapon"]        = "media/textures/donation/random_weapon.png",
    -- ["random_skill_potion"]  = "media/textures/donation/random_skill_potion.png",
    ["vehicle_drop"]         = "media/textures/donation/vehicle_drop.png",
    -- ["revive_ticket"]        = "media/textures/donation/revive_ticket.png",
    ["mutant_spawn"]         = "media/textures/donation/mutant_spawn.png",
    -- ["secret_passage_kit"]   = "media/textures/donation/secret_passage_kit.png",
    ["rise_up_dead_man"]     = "media/textures/donation/rise_up_dead_man.png",
    ["horde_night"]          = "media/textures/donation/horde_night.png",
}
local iconTexCache = {}   -- featureId -> Texture 객체 (또는 없으면 false로 캐시)

-- ── 둥근모서리 슬롯 마스크 텍스처 ──────────────────────────────────────────────
-- PZ 바닐라 drawRect/drawRectBorder는 각진 사각형만 그릴 수 있어서, 둥근 모서리는
-- 미리 만든 알파마스크 PNG(흰색 도형 + 라운드 처리된 알파 채널)를 r,g,b로 틴트해서
-- 그리는 방식으로 구현한다. 텍스처 원본 해상도는 슬롯 크기와 무관하게 128x128 고정.
local SLOT_MASK_SIZE = 128
local slotFillMaskTex, slotBorderMaskTex
local function getSlotMasks()
    if slotFillMaskTex == nil then
        slotFillMaskTex   = getTexture("media/textures/donation/ui/slot_fill_mask.png") or false
        slotBorderMaskTex = getTexture("media/textures/donation/ui/slot_border_mask.png") or false
    end
    if slotFillMaskTex == false then return nil, nil end
    return slotFillMaskTex, slotBorderMaskTex
end

-- 슬롯 테두리는 이제 효과색이 아니라 항상 고정된 검회색 (col과 무관).
local BORDER_COL = {0.13, 0.13, 0.15}

local function getIconTexture(featureId)
    local path = iconTexPath[featureId]
    if not path then return nil end
    local cached = iconTexCache[featureId]
    if cached == nil then
        cached = getTexture(path) or false
        iconTexCache[featureId] = cached
    end
    if cached == false then return nil end
    return cached
end

-- 순수 효과 이름만 (후원 메시지 안 붙임) -- 큐박스 호버 툴팁 전용.
local function effectName(featureId)
    local key = labelKey[featureId]
    return key and getText(key) or ("Effect " .. tostring(featureId))
end

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
    local rem   = math.max(0, e.remaining_ms)
    local dur   = e.duration_ms or PANEL_DURATION_MS
    if dur <= 0 then dur = 1 end
    local prog  = rem / dur              -- 1 = 방금 시작(쿨다운 꽉 참), 0 = 발동 직전
    local col   = colorMap[e.featureId] or {0.5, 0.5, 0.5}
    local w, h  = self.width, self.height
    local tex   = getIconTexture(e.featureId)
    local fillMask, borderMask = getSlotMasks()

    -- 슬롯 베이스: 효과색으로 꽉 채움 (둥근모서리 마스크 사용, 마스크 없으면 각진 사각형 폴백)
    if fillMask then
        self:drawTextureScaledAspect(fillMask, 0, 0, w, h, 0.9, col[1], col[2], col[3])
    else
        self:drawRect(0, 0, w, h, 0.9, col[1], col[2], col[3])
    end

    if tex then
        -- 실제 아이콘 이미지가 있으면 그걸 슬롯에 맞춰 그림
        self:drawTextureScaledAspect(tex, 0, 0, w, h, 1, 1, 1, 1)
    else
        -- 이미지 없을 때 폴백: 효과색 옅은 틴트만 (텍스트는 호버 시에만, 아래 참고)
        if fillMask then
            self:drawTextureScaledAspect(fillMask, 0, 0, w, h, 0.16, col[1], col[2], col[3])
        else
            self:drawRect(0, 0, w, h, 0.16, col[1], col[2], col[3])
        end
    end

    if e.locked then
        -- 안전지대 락: 진행 오버레이 대신 전체를 어둡게 덮고 자물쇠 아이콘 표시.
        -- 안전지대를 벗어나는 즉시 locked가 풀리며(병렬 레인으로 승격) 진행 오버레이로 전환.
        if fillMask then
            self:drawTextureScaledAspect(fillMask, 0, 0, w, h, 0.6, 0, 0, 0)
        else
            self:drawRect(0, 0, w, h, 0.6, 0, 0, 0)
        end
        local cx    = math.floor(w / 2)
        local bodyW = sc(14)
        local bodyH = sc(10)
        local bodyY = math.floor(h / 2) - sc(1)
        -- 고리 (몸통 위, 테두리만)
        self:drawRectBorder(cx - sc(4), bodyY - sc(7), sc(8), sc(8), 0.95, 0.95, 0.85, 0.4)
        -- 몸통 (채움)
        self:drawRect(cx - math.floor(bodyW / 2), bodyY, bodyW, bodyH, 0.95, 0.95, 0.85, 0.4)
    elseif e.counting then
        -- 쿨다운 오버레이: 남은 비율만큼 위에서 어둡게 덮고, 시간이 지날수록
        -- 아래에서부터 원래 색이 드러난다 (게이지 아이콘처럼 슬롯 자체가 진행바 역할).
        -- 마스크 텍스처의 "위쪽 prog 비율" 영역만 잘라서 그리면, 사각형으로 대충
        -- 덮을 때와 달리 둥근 위쪽 모서리가 깨지지 않는다 (javaObject 직접 호출:
        -- ISUIElement엔 안 감싸져 있지만 Java UIElement의 public 메서드라 호출 가능).
        local overlayH = math.floor(h * prog)
        if overlayH > 0 then
            if fillMask and self.javaObject then
                self.javaObject:DrawSubTextureRGBA(
                    fillMask, 0, 0, SLOT_MASK_SIZE, SLOT_MASK_SIZE * prog,
                    0, 0, w, overlayH, 0, 0, 0, 0.55
                )
            else
                self:drawRect(0, 0, w, overlayH, 0.55, 0, 0, 0)
            end
        end
    else
        -- 대기 슬롯: 직렬 레인에서 자기 차례를 기다리는 중 (카운트다운 정지 상태).
        if fillMask then
            self:drawTextureScaledAspect(fillMask, 0, 0, w, h, 0.6, 0, 0, 0)
        else
            self:drawRect(0, 0, w, h, 0.6, 0, 0, 0)
        end
    end

    -- 테두리: 상태와 무관하게 항상 고정 검회색 (예전엔 효과색 + 상태별 굵기/투명도였음)
    if borderMask then
        self:drawTextureScaledAspect(borderMask, 0, 0, w, h, 0.9, BORDER_COL[1], BORDER_COL[2], BORDER_COL[3])
    else
        self:drawRectBorder(0, 0, w, h, 0.9, BORDER_COL[1], BORDER_COL[2], BORDER_COL[3])
    end

    -- 스택 개수 (좌하단, 참고 이미지 스타일). 진행 상황은 오버레이가 보여주니
    -- 숫자는 "같은 효과가 몇 개 쌓여있는지"에만 씀.
    self:drawText(tostring(e.stack or 1), sc(3), h - sc(16), 1, 0.95, 0.35, 1, UIFont.Medium)

    -- 마우스 호버 중일 때만 이 슬롯이 무슨 효과인지 슬롯 위에 툴팁으로 표시.
    -- 텍스트는 IG_UI_KO.txt 번역 키(labelKey/getText) 기반 순수 효과 이름만 씀
    -- (entry.label은 백신처럼 후원 메시지가 붙을 수 있어서 툴팁엔 안 맞음).
    if self:isMouseOver() then
        local label = effectName(e.featureId)
        local tw = getTextManager():MeasureStringX(UIFont.Medium, label)
        local boxW = tw + sc(14)
        local boxH = sc(25)
        local tx = math.floor(w / 2 - boxW / 2)
        local ty = -boxH - sc(4)
        self:drawRect(tx, ty, boxW, boxH, 0.9, 0.05, 0.05, 0.05)
        self:drawRectBorder(tx, ty, boxW, boxH, 0.8, col[1], col[2], col[3])
        self:drawTextCentre(label, w / 2, ty + sc(4), col[1], col[2], col[3], 1, UIFont.Medium)
    end

    ISPanel.render(self)
end

function DonationEntryPanel:update() end

-- Drag: moving ANY panel moves the whole stack anchor (persisted on release).
-- 큐박스에 들어온 도네는 닫기 불가 -- 드래그로 위치만 옮길 수 있음.
function DonationEntryPanel:onMouseDown(x, y)
    if not self:getIsVisible() then return end
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
-- 드래그로 위치를 옮긴 적 없을 때(anchorX == nil) 쓰는 기본 위치.
-- 좌우는 화면 정중앙, 높이는 아이템 핫바(ISHotbar) 바로 위.
local function getHotbarInstance()
    local pd = getPlayerData(0)
    return pd and pd.playerHotbar
end

-- count: 현재 쌓인 슬롯 개수. x0는 "슬롯1(맨 오른쪽)의 좌상단" 좌표라서,
-- count가 1보다 크면 슬롯1을 그만큼 오른쪽으로 밀어줘야 묶음 전체(슬롯1~N)의
-- 중앙이 화면 정중앙에 오게 된다.
local function defaultAnchor(sz, count)
    local sw = getCore():getScreenWidth()
    local sh = getCore():getScreenHeight()
    count = count or 1
    local groupHalfExtra = (count - 1) * (sz + sc(BASE_GAP)) / 2
    local x0 = math.floor(sw / 2 - sz / 2 + groupHalfExtra)   -- 박스 묶음 전체의 좌우 정중앙

    -- 핫바 인스턴스에서 실제 y좌표를 가져와 그 바로 위에 배치.
    -- 아직 핫바가 준비 안 됐거나(로딩 중 등) 못 구했을 땐 화면 하단 기준 폴백값 사용.
    local hotbarY = sh - sc(90)
    local ok, hotbar = pcall(getHotbarInstance)
    if ok and hotbar and hotbar.getY then
        hotbarY = hotbar:getY()
    end
    local y0 = hotbarY - sz - sc(10)   -- 핫바 바로 위 (여백 10px)
    return x0, y0
end

repositionPanels = function()
    local sw  = getCore():getScreenWidth()
    local sh  = getCore():getScreenHeight()
    local sz  = sc(ICON_SIZE)
    local x0, y0
    if uiSettings.anchorX ~= nil then
        x0, y0 = uiSettings.anchorX, uiSettings.anchorY
    else
        x0, y0 = defaultAnchor(sz, #panelList)
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

-- 도네이션 "도착 순서" 전역 카운터. 슬롯(activeEntries)은 featureId별로 병합되므로
-- 슬롯 배열 순서 = 해당 featureId가 "처음 등장한" 순서일 뿐, 실제 도착 순서와 다르다.
-- 버프-디버프-버프-디버프-버프처럼 번갈아 들어와도 발동은 도착한 순서대로 나가야
-- 하므로, 유닛(스택 1개) 단위로 이 카운터 값을 매겨 직렬 헤드 선정에 사용한다.
local donationSeq = 0

-- ── Apply one donation locally (panel + reward) ──────────────────────────────
-- amount는 통계/로그용, featureId가 실제 디스패치 키 (퍼펫 API가 amount->featureId
-- 매핑을 보고 rewards.txt에 같이 실어 보낸다).
-- Prep countdown duration = sandbox PongDu.Donation_PrepDelay (0..10s).
-- 0초면 준비 패널을 아예 안 띄우고 즉시 발동 (확인 패널은 그대로 5초).
-- ── Apply one donation locally (slot + reward) ────────────────────────────────
-- amount는 통계/로그용, featureId가 실제 디스패치 키 (퍼펫 API가 amount->featureId
-- 매핑을 보고 rewards.txt에 같이 실어 보낸다).
-- 여기서는 큐박스 슬롯 등록만 한다. 카운트다운 / 안전지대 락 / 실제 발동은 전부
-- onTick이 처리 (슬롯별로 독립 진행되므로 슬롯 생성 시점엔 아무것도 발동 안 함).
-- Prep countdown duration = sandbox PongDu.Donation_PrepDelay (0..10s).
local function applyDonation(amount, featureId, sender, message)
    amount    = tostring(amount or "")
    featureId = tostring(featureId or "")
    local prepMs = prepDurationMs()
    donationSeq = donationSeq + 1
    local entry = {
        label        = buildLabel(featureId, sender, message),
        sender       = sender,
        senders      = { sender },   -- 같은 featureId가 뒤이어 들어오면 여기 계속 쌓임 (스택)
        arrivalSeq   = { donationSeq },   -- senders와 1:1 대응, 유닛별 도착 순번 (발동 순서 결정용)
        stack        = 1,
        remaining_ms = prepMs,
        duration_ms  = prepMs,   -- 유닛 1개 발동 간격 (스택 소모 주기로도 재사용)
        amount       = amount,
        featureId    = featureId,
        message      = message or "",   -- 재접속 복원(직렬화) 시 필요
        locked       = false,    -- onTick이 매 틱 갱신 (안전지대 && zone-blocked 타입)
        parallel     = false,    -- 락에서 풀려나면 true로 승격 -> 직렬 순서 무시하고 병렬 소모
        counting     = false,    -- onTick이 갱신: 지금 실제로 카운트다운 중인지 (render 표시용)
    }
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

-- ── Pending queue persistence ─────────────────────────────────────────────────
-- 접속 종료/튕김으로 아직 처리 안 된 도네이션이 날아가지 않도록, 대기 중인
-- 유닛 전부(donationQueue + 큐박스 슬롯의 남은 스택)를 rewards.txt와 같은
-- 줄 형식(amount,featureId,sender,message / sender·message는 URL 인코딩)으로
-- 클라이언트 로컬 파일에 저장해두고, 게임 시작 시 다시 읽어 큐에 복원한다.
-- (플레이어 modData는 캐릭터 사망/재생성 시 같이 날아가므로 파일 방식을 씀.)
local PENDING_FILE = "PongDuPendingQueue.txt"
local queueDirty = false
local function markQueueDirty() queueDirty = true end

local function savePendingQueue()
    local w = getFileWriter(PENDING_FILE, true, false)
    if not w then return end
    -- 큐박스 슬롯에 올라가 있지만 아직 발동 안 된 유닛들 (스택 전체)
    for _, e in ipairs(activeEntries) do
        for i = 1, e.stack do
            local sender = e.senders[i] or e.sender or ""
            w:write(tostring(e.amount or "") .. "," .. tostring(e.featureId or "") .. ","
                .. urlencode(tostring(sender)) .. "," .. urlencode(tostring(e.message or "")) .. "\n")
        end
    end
    -- 아직 큐박스에 못 올라간 대기열
    for _, item in ipairs(donationQueue) do
        w:write(tostring(item.amount or "") .. "," .. tostring(item.featureId or "") .. ","
            .. urlencode(tostring(item.sender or "")) .. "," .. urlencode(tostring(item.message or "")) .. "\n")
    end
    w:close()
end

local function loadPendingQueue()
    local reader = getFileReader(PENDING_FILE, true)
    if not reader then return end
    local line = reader:readLine()
    while line do
        if line ~= "" then
            local amount, featureId, sender, message = line:match("^([^,]*),?([^,]*),?([^,]*),?(.*)$")
            if amount and amount ~= "" and rewardManager.isValid(featureId or "") then
                table.insert(donationQueue, {
                    amount    = tostring(amount),
                    featureId = featureId,
                    sender    = urldecode(sender or ""),
                    message   = urldecode(message or ""),
                })
            end
        end
        line = reader:readLine()
    end
    reader:close()
    markQueueDirty()   -- 복원 후 현재 상태 기준으로 파일 다시 씀
end

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
            sendClientCommand("PongDuStats", "Record", { line = raw })
            -- Effect: only queue valid featureIds (unmapped amounts do nothing in-game).
            if rewardManager.isValid(featureId) then
                table.insert(donationQueue, {
                    amount    = amount,
                    featureId = featureId,
                    sender    = urldecode(sender or ""),
                    message   = urldecode(message or ""),
                })
                markQueueDirty()
            end
        end
    end
end

local MAX_QUEUE_SLOTS = 5   -- 도네큐박스 최대 슬롯 수. 슬롯들은 서로 병렬로 진행된다.

-- 같은 featureId 슬롯이 이미 큐박스에 있으면 새 슬롯을 만들지 않고 그 스택에
-- 합친다 -- 같은 효과가 몇 개가 들어오든 슬롯 1칸에 숫자만 쌓임 (뛰좀 6개 -> x6).
local function tryMergeIntoSlot(item)
    for _, e in ipairs(activeEntries) do
        if e.featureId == item.featureId then
            e.stack = e.stack + 1
            donationSeq = donationSeq + 1
            table.insert(e.senders, item.sender)
            table.insert(e.arrivalSeq, donationSeq)
            return true
        end
    end
    return false
end

-- 큐박스에 빈 슬롯이 있는 동안 계속 채운다. 이미 슬롯이 있는 타입은 슬롯을
-- 새로 안 쓰고 병합되므로, 큐박스가 꽉 찼어도 기존 타입은 계속 흡수된다.
local function consumeDonationQueue()
    while #donationQueue > 0 do
        local item = donationQueue[1]
        if tryMergeIntoSlot(item) then
            table.remove(donationQueue, 1)
        elseif #activeEntries < MAX_QUEUE_SLOTS then
            table.remove(donationQueue, 1)
            applyDonation(item.amount, item.featureId, item.sender, item.message)
        else
            break   -- 큐박스 꽉 참, 새 타입은 자리 날 때까지 대기
        end
    end
end

-- PongDuDonation module receiver:
--  * PlayAlert -- server relays a donation alert sound to nearby clients
--    (sent by rewardManager missile / features/riseup; relay in server.lua).
--  * Apply -- harmless fallback if a server ever pushes a donation directly.
local function onServerCommand(module, command, data)
    if module ~= "PongDuDonation" then return end
    if command == "PlayAlert" then
        getSoundManager():PlaySound("alert", false, 1.0)
        return
    end
    if command ~= "Apply" then return end
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
    -- 기본은 원래대로 직렬: 큐박스에서 실제로 카운트다운하는 건 "직렬 헤드"
    -- (락도 아니고 병렬도 아닌 슬롯 중 가장 앞) 하나뿐이고, 나머지는 자기
    -- 차례를 기다린다.
    -- 예외는 안전지대 락에서 풀려난 슬롯들: 락이 해제되는 순간 병렬 레인으로
    -- 넘어가서 서로(그리고 직렬 헤드와도) 동시에 카운트다운/발동된다.
    -- (특좀 x3 + 뛰좀 x2 락 해제 -> 첫 주기에 특좀1+뛰좀1 동시 발동, 특좀 x2/뛰좀 x1 잔류.
    --  같은 타입 스택은 병렬이어도 슬롯 안에서 duration_ms 간격으로 하나씩만 소모.)
    local player = getPlayer()
    local inSafeZone = player ~= nil and zone.a(player)

    -- 1) 락 상태 갱신 + 락 해제 감지 (락이었다가 풀린 슬롯만 병렬로 승격)
    for _, e in ipairs(activeEntries) do
        local nowLocked = inSafeZone and rewardManager.isZoneBlocked(e.featureId)
        if e.locked and not nowLocked then
            e.parallel = true   -- 안전지대에서 쌓여있다 풀려난 슬롯: 병렬 소모
        end
        e.locked = nowLocked
    end

    -- 2) 직렬 헤드 선정: 락/병렬이 아닌 슬롯들 중, 다음에 발동할 유닛의 도착 순번
    --    (arrivalSeq[1])이 가장 오래된(가장 작은) 슬롯. 슬롯 배열 순서(=featureId가
    --    처음 등장한 순서)가 아니라 실제 도네이션 도착 순서를 기준으로 삼아야
    --    버프-디버프-버프-디버프-버프처럼 번갈아 들어와도 그 순서대로 발동된다.
    local serialHead = nil
    for _, e in ipairs(activeEntries) do
        if not e.locked and not e.parallel then
            if serialHead == nil or (e.arrivalSeq[1] or 0) < (serialHead.arrivalSeq[1] or 0) then
                serialHead = e
            end
        end
    end

    -- 3) 카운트다운/발동. counting 플래그는 render()가 진행/대기 표시 구분에 씀.
    for i = #activeEntries, 1, -1 do
        local e = activeEntries[i]
        e.counting = (not e.locked) and (e.parallel or e == serialHead)
        if e.counting then
            e.remaining_ms = e.remaining_ms - dt
            if e.remaining_ms <= 0 then
                -- 유닛 1개 발동. 방금 락 아님을 확인했으므로 rewardManager.a는
                -- 내부 안전지대 대기 없이 즉시 경로를 탄다 (같은 틱에 재진입하는
                -- 극단적 레이스는 rewardManager.a 자체 재확인 루프가 흡수).
                local unitSender = table.remove(e.senders, 1) or e.sender
                table.remove(e.arrivalSeq, 1)
                rewardManager.a(e.featureId, unitSender, nil)
                e.stack = e.stack - 1
                markQueueDirty()   -- 유닛 하나 소모됨 -> 저장 파일 갱신 필요
                if e.stack <= 0 then
                    removePanel(e)
                    table.remove(activeEntries, i)
                else
                    e.remaining_ms = e.duration_ms   -- 다음 유닛까지 대기시간 재시작
                end
            end
        end
    end
    -- 드래그로 위치를 커스텀한 적 없으면(anchorX == nil) 미니맵을 계속 따라가도록
    -- 매 틱 재배치 (인벤토리 열림/미니맵 토글 등으로 미니맵이 움직일 수 있음).
    if uiSettings.anchorX == nil and #panelList > 0 then
        repositionPanels()
    end
    if bandit then bandit.b() end
    if zombie then zombie.a() end
    pollDonationFile()
    consumeDonationQueue()
    -- 대기 유닛 구성이 바뀌었으면 저장 -- 접속 종료/튕김이 언제 나도 파일엔
    -- 항상 최신 대기열이 남아있게.
    if queueDirty then
        queueDirty = false
        savePendingQueue()
    end
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
Events.OnGameStart.Add(loadPendingQueue)
