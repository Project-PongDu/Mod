local _a = {}
require("ISUI/ISPanel")
local colorMap    = require("utils/colorMap")
local textOutline = require("utils/textOutline")

-- ── 호드 나이트 (horde_night) 클라이언트 ─────────────────────────────────────
-- 역할 3가지:
--  ① 예약 요청: 후원이 처리되면 서버에 Reserve 를 던진다. 실제 예약 카운터와
--     발동 판정은 전부 서버(server/PongDuHordeServer.lua)에 있다.
--  ② 심박음: 서버 Reserved 브로드캐스트 수신 시 1회 재생. 발동음이 아니라
--     "오늘 밤 온다"는 예고음이라, 발동 시점(22시)이 아니라 후원 시점에 울린다.
--  ③ 인디케이터: 예약이 하나라도 걸려 있거나 스폰이 진행 중이면 화면 우상단에
--     상시 표시. 원본 모드의 무들 아이콘 자리를 그대로 쓰되, 텍스처는 도네
--     큐박스와 같은 horde_night.png 를 쓴다. 예약이 2건 이상이면 개수를 겹쳐 그린다.
--
-- 스폰/유인 사운드는 전부 서버가 처리한다. 클라가 하는 일은 없다.

-- 원본 무들 위치/크기 유지 (HordeNightIndicator.lua: screenW-210, 12, 32, 32).
-- 텍스처 원본은 1024x1024(큐박스 슬롯용)이라 ISUIElement:drawTextureScaled 로
-- 축소해 그린다.
local IND_RIGHT_PAD = 210
local IND_TOP       = 12
local IND_SIZE      = 32
local TEX_PATH      = "media/textures/donation/horde_night.png"

local SYNC_DELAY_TICKS = 300   -- 접속 직후 서버 상태 요청까지 대기 (~5초)

local _pending = 0
local _active  = false
local _panel   = nil
local _syncTicks = -1

local function indicatorEnabled()
    return SandboxVars.PongDu.Horde_ShowIndicator
end

-- ── 인디케이터 패널 ──────────────────────────────────────────────────────────
local HordeIndicator = ISPanel:derive("HordeIndicator")

function HordeIndicator:new()
    local o = ISPanel:new(getCore():getScreenWidth() - IND_RIGHT_PAD, IND_TOP,
        IND_SIZE, IND_SIZE)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    o.tex = getTexture(TEX_PATH)
    return o
end

function HordeIndicator:render()
    if self.tex then
        self:drawTextureScaledAspect(self.tex, 0, 0, IND_SIZE, IND_SIZE, 1, 1, 1, 1)
    end
    -- 예약이 2건 이상이면 우하단에 개수 표시 (큐박스 스택 카운트와 같은 기법)
    if _pending > 1 then
        local col = colorMap.get("horde_night")
        textOutline.draw(self, "x" .. tostring(_pending),
            IND_SIZE - 12, IND_SIZE - 14, col[1], col[2], col[3], 1, UIFont.Small)
    end
end

local function relayout()
    if _panel then
        _panel:setX(getCore():getScreenWidth() - IND_RIGHT_PAD)
        _panel:setY(IND_TOP)
    end
end
Events.OnResolutionChange.Add(relayout)

local function refreshIndicator()
    local want = indicatorEnabled() and (_pending > 0 or _active)
    if want then
        if not _panel then
            _panel = HordeIndicator:new()
            _panel:addToUIManager()
        end
        _panel:setVisible(true)
    elseif _panel then
        _panel:setVisible(false)
        _panel:removeFromUIManager()
        _panel = nil
    end
end

-- ── 서버 커맨드 수신 ─────────────────────────────────────────────────────────
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuHorde" then return end

    if command == "State" then
        _pending = tonumber(args and args["pending"]) or 0
        _active  = (tonumber(args and args["active"]) or 0) == 1
        print("[PongDuHorde] state pending=" .. tostring(_pending)
            .. " active=" .. tostring(_active))
        refreshIndicator()

    elseif command == "Reserved" then
        -- 심박음 1회. PlaySound 의 maxGain 인자는 SoundManager.java 구현상
        -- 무시되므로 반환 핸들에 setVolume 을 직접 건다.
        local audio = getSoundManager():PlaySound("pongdu_heartbeat", false, 1.0)
        if audio then audio:setVolume(0.7) end
        print("[PongDuHorde] reserved pending=" .. tostring(args and args["pending"])
            .. " sender=" .. tostring(args and args["sender"]))

    elseif command == "Fire" then
        print("[PongDuHorde] horde night fired countPerPlayer="
            .. tostring(args and args["cnt"]))
    end
end)

-- ── 접속 직후 상태 동기화 ────────────────────────────────────────────────────
-- 예약 카운터는 서버 ModData에 있으므로, 중간 접속자도 인디케이터를 맞춰야 한다.
Events.OnGameStart.Add(function()
    _syncTicks = SYNC_DELAY_TICKS
end)

Events.OnTick.Add(function()
    if _syncTicks < 0 then return end
    _syncTicks = _syncTicks - 1
    if _syncTicks == 0 then
        _syncTicks = -1
        sendClientCommand("PongDuHorde", "Sync", { ["dummy"] = 1 })
    end
end)

-- ── 예약 요청 (rewardManager에서 호출) ───────────────────────────────────────
function _a.a(sender)
    sendClientCommand("PongDuHorde", "Reserve", { ["sender"] = sender or "" })
    print("[PongDuHorde] reserve requested sender=" .. tostring(sender))
end

return _a
