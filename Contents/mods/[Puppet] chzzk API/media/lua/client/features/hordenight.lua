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

-- ── 발동/종료 연출 ───────────────────────────────────────────────────────────
-- 원본 모드는 HN_StartHordeNight 에서 IGUI_PlayerText_HNWarning00~09 중 1개를
-- Say() 하고 좀비 신음 계열 사운드를 PlaySound + PlayAsMusic(volume 0.1)로
-- 깔았다. 여기서는 대사를 퐁듀 번역 키로 옮기고(원본 원문은 미이식),
-- 사운드는 GameSound alias 하나로 추상화한다.
--   ※ HORDE_START_SOUND 는 아직 t3_rewards_sounds.txt 에 등록돼 있지 않다.
--     GameSounds.getSound() 가 nil 을 반환하면 playSoundImpl 이 0 을 돌려주고
--     조용히 넘어가므로(FMODSoundEmitter.java) 미등록 상태에서도 크래시는
--     없다. 에셋을 넣고 sound 블록만 추가하면 그대로 살아난다.
local HORDE_START_SOUND = "pongdu_horde_start"
local HORDE_START_GAIN  = 0.8
local WARN_LINE_COUNT   = 10   -- IGUI_donation_horde_night_warn1..10
local OVER_LINE_COUNT   = 5    -- IGUI_donation_horde_night_over1..5
local RESERVE_LINE_COUNT = 5   -- IGUI_donation_horde_night_reserve1..5

-- 로컬 플레이어에게 랜덤 대사 1줄. ZombRand(min,max)는 max 미포함이라 +1 한다.
-- Say 는 사망/미생성 타이밍에 걸릴 수 있어 pcall 로 감싼다(firesupport.lua 와 동일).
local function sayRandomLine(prefix, count)
    local p = getPlayer()
    if not p then return end
    local key = "IGUI_donation_horde_night_" .. prefix .. tostring(ZombRand(1, count + 1))
    pcall(function() p:Say(getText(key)) end)
end

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
        -- 심박음 1회 + 대사 1줄. 발동음이 아니라 "오늘 밤 온다"는 예고라서
        -- Fire(_warn)보다 톤을 낮춘 별도 라인셋(_reserve)을 쓴다. 이 브로드캐스트는
        -- 전 클라에 나가므로(broadcastState 와 동일 경로), 접속자 전원이 동시에
        -- 대사를 친다 -- 원래 심박음도 전원에게 들리던 것과 같은 성격이라
        -- 의도된 동작이다.
        sayRandomLine("reserve", RESERVE_LINE_COUNT)
        -- PlaySound 의 maxGain 인자는 SoundManager.java 구현상
        -- 무시되므로 반환 핸들에 setVolume 을 직접 건다.
        local audio = getSoundManager():PlaySound("pongdu_heartbeat", false, 1.0)
        if audio then audio:setVolume(0.7) end
        print("[PongDuHorde] reserved pending=" .. tostring(args and args["pending"])
            .. " sender=" .. tostring(args and args["sender"]))

    elseif command == "Fire" then
        -- 발동 연출. 심박음(Reserved)이 "오늘 밤 온다"는 예고음이라면 이쪽이
        -- 실제 시작 신호다. 서버가 세션이 열린 플레이어에게만 보낸다.
        print("[PongDuHorde] horde night fired countPerPlayer="
            .. tostring(args and args["cnt"]))
        sayRandomLine("warn", WARN_LINE_COUNT)
        -- PlaySound 의 maxGain 인자는 SoundManager.java 구현상 무시되므로
        -- 반환 핸들에 setVolume 을 직접 건다(Reserved 쪽과 동일한 이유).
        local audio = getSoundManager():PlaySound(HORDE_START_SOUND, false, 1.0)
        if audio then audio:setVolume(HORDE_START_GAIN) end

    elseif command == "End" then
        -- 스폰이 전부 끝난 시점. 좀비가 다 정리됐다는 뜻은 아니라 대사도
        -- "몰려오는 게 멈췄다" 정도의 톤이다.
        print("[PongDuHorde] horde night ended spawned="
            .. tostring(args and args["spawned"])
            .. " hits=" .. tostring(args and args["hits"]))
        sayRandomLine("over", OVER_LINE_COUNT)
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
