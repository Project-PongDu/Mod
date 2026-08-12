local _a = {}
require("ISUI/ISPanel")
local moodleStack = require("utils/moodleStack")
local colorMap    = require("utils/colorMap")
local textOutline = require("utils/textOutline")

-- ── 블러드문 (blood_moon) 클라이언트 ─────────────────────────────────────────
--
-- 서버 후원(PongDu_Server 탭) 계열. 서버장에게 후원이 들어오면 접속자 전원에게
-- 일정 인게임 시간 동안 다음이 걸린다:
--   ① 좀비 가속  : 뮤턴트/퐁듀 소유 좀비를 제외한 모든 일반좀비를 스프린터로
--   ② 핏빛 조명 (shared/PongDuBloodMoonLight.lua) -- 낮/밤 모두 적용
--   ③ 무들 인디케이터로 남은 시간 표시
-- 종료 시 전부 원상복구한다.
--
-- 서버(server/PongDuBloodMoonServer.lua)는 "언제 시작하고 언제 끝나는가"만
-- 관리하고, 좀비 변환은 각 클라가 로컬로 수행한다. ①이 클라 담당인 이유는
-- B41 좀비 소유권 모델 때문이다 -- 서버에서 IsoZombie 스탯을 바꾸면 소유
-- 클라의 sync 패킷에 그대로 덮어써진다.
--
-- 싱글플레이 예외: SP 는 sendClientCommand/sendServerCommand 가 둘 다 동작하지
-- 않으므로(LuaManager.java 의 GameClient.bClient / GameServer.bServer 가드),
-- medicalbox.lua 와 같은 방식으로 서버 왕복 없이 로컬에서 바로 시작한다.

-- ── 좀비 변환 ───────────────────────────────────────────────────────────────
local SPEED_SPRINTER = 1     -- ZombieLore.Speed 값 (1=스프린터 2=속보 3=완보)
local MD_MARK = "PongDuBloodMoon"    -- 이번 이벤트로 변환됨
local MD_ORIG = "PongDuBloodMoonSpd" -- 변환 직전 speedType 백업

local SWEEP_ACTIVE_TICKS = 30    -- 이벤트 중 스윕 주기 (~0.5초)
local SWEEP_IDLE_TICKS   = 150   -- 평시 잔여 마커 회수 주기 (~2.5초)
local CONVERT_PER_PASS   = 40    -- 1회 스윕당 실제 변환/복원 상한 (스파이크 방지)

local function log(msg)
    print("[PongDuBloodMoon] " .. tostring(msg))
end

-- ═══════════════════════════════════════════════════════════════════════════
--  상태
-- ═══════════════════════════════════════════════════════════════════════════
local _active      = false
local _endHours    = nil   -- getWorldAgeHours() 기준 종료 예정 시각
local _totalMin    = 0     -- 이번 이벤트 총 길이 (인게임 분) -- 툴팁 클램프용
local _sweepTick   = 0
local _panel       = nil

-- ═══════════════════════════════════════════════════════════════════════════
--  좀비 변환 / 복원
-- ═══════════════════════════════════════════════════════════════════════════
-- makeInactive(true) -> speedType = 3
-- makeInactive(false) -> speedType = -1 후 DoZombieStats() 가 Lore.Speed 를 읽어
--                        speedType 과 walkType("sprintN"/"slowN")을 재배정
-- (IsoZombie.java:4079-4093, 2611-2655). 그래서 샌드박스 값을 잠깐 바꿔치기하는
-- 것이 개체별 속도를 바꾸는 유일한 정식 경로다 -- server.lua 의 makeSprinter 와
-- RandomZombies 모드가 쓰는 것과 동일한 패턴이다.
--
-- DoZombieStats() 를 따로 한 번 더 부르지 않는다. makeInactive(false) 안에서
-- 이미 호출되며, 중복 호출하면 speedMod/bLunger/walkVariant 가 한 번 더
-- 재굴림되어 좀비 걸음걸이가 불필요하게 흔들린다.

-- ── IsoZombie 필드 리플렉션 ─────────────────────────────────────────────────
-- Kahlua 의 LuaJavaClassExposer 는 인스턴스 public 필드를 Lua 에 노출하지
-- 않는다 -- exposeLikeJava() 가 메서드(exposeMethods)와 static 필드
-- (exposeStatics)만 테이블에 얹는다. 즉 zed.speedType / zed.inactive 는
-- 항상 nil 이고, 이걸 그대로 쓰면 조건문이 통째로 죽는다(이번 버그의 절반).
-- PZ 가 전역으로 뚫어둔 리플렉션 API(getNumClassFields / getClassField /
-- getClassFieldVal, LuaManager.java:5597-5766)로 읽어야 한다.
-- RandomZombies 가 같은 이유로 같은 방식을 쓴다.
--
-- Field 객체는 클래스 단위라 한 번만 찾아 캐싱한다. 실패하면 nil 을 캐싱해
-- 매 스윕 재시도하지 않는다(마커 전용 폴백 모드로 내려간다).
local FIELD_SPEED    = "public int zombie.characters.IsoZombie.speedType"
local FIELD_INACTIVE = "public boolean zombie.characters.IsoZombie.inactive"

local _fields      = nil
local _fieldsTried = false

local function fields(zed)
    if _fieldsTried then return _fields end
    _fieldsTried = true

    local found = {}
    local ok, err = pcall(function()
        for i = 0, getNumClassFields(zed) - 1 do
            local f = getClassField(zed, i)
            local n = tostring(f)
            if n == FIELD_SPEED then
                found.speed = f
            elseif n == FIELD_INACTIVE then
                found.inactive = f
            end
        end
    end)

    if not ok then
        log("field reflection failed: " .. tostring(err) .. " (marker-only fallback)")
        return nil
    end
    if not found.speed then
        log("speedType field not found (marker-only fallback)")
        return nil
    end

    _fields = found
    log("field reflection ready (inactive="
        .. tostring(found.inactive ~= nil) .. ")")
    return _fields
end

-- 현재 speedType. 1/2/3 이 정상값이고, 아직 DoZombieStats 를 한 번도 타지
-- 않은 개체는 -1 이다(IsoZombie.java:200). -1 도 그대로 돌려준다 -- "읽지
-- 못함(nil)"과 "아직 미배정(-1)"은 처리가 다르기 때문이다.
local function readSpeed(zed)
    local f = fields(zed)
    if not f then return nil end
    local ok, v = pcall(getClassFieldVal, zed, f.speed)
    if not ok then return nil end
    return tonumber(v)
end

-- 휴면(가상) 좀비 여부. 읽지 못하면 false 로 보수적으로 처리한다.
local function isInactive(zed)
    local f = fields(zed)
    if not f or not f.inactive then return false end
    local ok, v = pcall(getClassFieldVal, zed, f.inactive)
    return ok and v == true
end

local function setZombieSpeed(zed, target)
    local so = getSandboxOptions()
    local prev = so:getOptionByName("ZombieLore.Speed"):getValue()
    so:set("ZombieLore.Speed", target)
    zed:makeInactive(true)
    zed:makeInactive(false)
    so:set("ZombieLore.Speed", prev)
end

-- 변환 제외 대상 판정.
--   PongDuCompat.isSpecialZombie : 뮤턴트 4종(screamer/brute/roach/tracer) +
--     뮤턴트 스프린터(PuppetMutant="sprinter") + 일반 스프린터(isSprinter) +
--     히트맨 NPC. server/PongDuCompatRandomZombies.lua 에 정의돼 있고
--     media/lua/server/ 는 클라에서도 로드되므로 여기서 그대로 쓸 수 있다.
--     블러드문 마커까지 포함하는 isOwnedZombie 가 아님에 주의(아래 주석 참조).
--   inactive : 휴면(가상) 좀비. makeInactive(true) 가 "이미 inactive 면 no-op"
--     이라(IsoZombie.java:4080) 토글하면 깨워버리는 부작용이 있어 건너뛴다.
--     RandomZombies 모드는 이 가드가 없어서 대규모 휴면 무리를 깨운다.
local function isConvertible(zed)
    if not zed then return false end
    if isInactive(zed) then return false end
    -- isOwnedZombie 가 아니라 isSpecialZombie 를 쓴다. 전자는 블러드문 마커까지
    -- 포함하므로(RZ 제외용) 여기서 쓰면 한 번 변환된 좀비가 영구히 재변환
    -- 대상에서 빠진다 -- 스트리밍 아웃/인으로 speedType 이 리셋되면 복구 불가.
    if PongDuCompat and PongDuCompat.isSpecialZombie and PongDuCompat.isSpecialZombie(zed) then
        return false
    end
    return true
end

-- 소유권이 없는 좀비는 건드리지 않는다.
-- B41 MP 에서 IsoZombie 의 권위는 "가까운 클라 1명"에게만 있고, 원격 좀비에
-- 가한 변경은 소유 클라의 sync 패킷에 즉시 덮어써진다. 그대로 두면 매 스윕마다
-- 같은 원격 좀비를 재변환하는 무한 반복이 되고(마커까지 sync 로 날아간다),
-- 정작 효과는 소유 클라가 자기 스윕에서 이미 적용하고 있다.
-- RandomZombies 는 이 검사를 일부러 뺐지만(자기 카운터 정확도 목적) 우리는
-- 카운터가 아니라 상태 변경이 목적이라 반대 판단이 맞다.
-- SP 에서는 항상 false 라 전량 통과한다.
local function isForeign(zed)
    local ok, remote = pcall(function() return zed:isRemoteZombie() end)
    return ok and remote == true
end

-- 복원용 원본 speedType. DoZombieStats 가 만드는 값은 1/2/3 뿐이고, 아직 한
-- 번도 초기화되지 않은 좀비는 -1 이다. 범위를 벗어나면 서버 샌드박스 기본값으로
-- 되돌린다 (좀비 리사이클로 ModData 가 날아간 경우도 여기로 떨어진다).
local function resolveOrigSpeed(md)
    local v = tonumber(md[MD_ORIG])
    if v == 1 or v == 2 or v == 3 then return v end
    return getSandboxOptions():getOptionByName("ZombieLore.Speed"):getValue()
end

-- 마커가 아니라 "지금 실제 speedType 이 뭔가"로 판정한다.
--
-- 마커 기준 1회 변환이 실패하는 이유:
-- 좀비가 스트리밍 아웃되면 makeInactive(true) 로 speedType = 3 이 되고,
-- 다시 들어올 때 makeInactive(false) -> speedType = -1 -> DoZombieStats() 가
-- 서버 샌드박스 Lore.Speed 로 재배정한다(IsoZombie.java:4079-4093). 리사이클
-- 경로(resetForReuse, 3327줄)도 speedType 을 -1 로 되돌린다. 마커는 ModData 라
-- 살아남으므로, 마커만 보면 "이미 변환됨"으로 판단해 영영 다시 안 건드린다.
-- 실제로 겪은 증상이 정확히 이것이다 -- 멀리 갔다 오면 다시 걷는다.
--
-- 그래서 RandomZombies 와 같은 구조를 택한다: 목표 속도와 실제 속도를 매 스윕
-- 비교하고 다르면 덮어쓴다. 마커는 "변환 판정"이 아니라 "종료 시 복원 대상
-- 표시 + RZ 제외 표시" 용도로만 남는다.
local function convertZombie(zed)
    if isForeign(zed) then return false end
    if not isConvertible(zed) then return false end

    local md  = zed:getModData()
    local cur = readSpeed(zed)

    -- 리플렉션 폴백. 실제 속도를 못 읽으면 매 스윕 makeInactive 토글이 무한
    -- 반복되므로(걸음걸이가 계속 재굴림된다) 마커 기준 1회 변환으로 물러선다.
    if cur == nil then
        if md[MD_MARK] then return false end
        md[MD_MARK] = true
        setZombieSpeed(zed, SPEED_SPRINTER)
        return true
    end

    if cur == SPEED_SPRINTER then
        -- 이미 스프린터. 마커만 채워둔다(종료 시 복원 대상 + RZ 제외).
        md[MD_MARK] = true
        return false
    end

    -- 원본 속도는 최초 1회만 기록한다. 두 번째부터는 우리가 넣은 값(1)을
    -- 원본으로 덮어쓸 위험이 있어 조건을 건다. -1(미배정)은 기록하지 않고
    -- 복원 시 서버 기본값으로 떨어지게 둔다(resolveOrigSpeed).
    if md[MD_ORIG] == nil and (cur == 2 or cur == 3) then md[MD_ORIG] = cur end
    md[MD_MARK] = true
    setZombieSpeed(zed, SPEED_SPRINTER)
    return true
end

local function revertZombie(zed)
    if isForeign(zed) then return false end
    local md = zed:getModData()
    if not md[MD_MARK] then return false end

    -- 지우기 전에 먼저 읽는다.
    local orig = resolveOrigSpeed(md)
    md[MD_MARK] = nil
    md[MD_ORIG] = nil

    -- 휴면 상태로 넘어간 좀비는 이미 엔진이 speedType 을 3 으로 강제해둔
    -- 상태다(IsoZombie.java:4086). 여기서 makeInactive 를 토글하면 되돌리는 게
    -- 아니라 잠든 좀비를 깨우는 꼴이 된다. 마커만 지우면 되고, 엔진이 나중에
    -- 이 좀비를 깨울 때 speedType 이 -1 로 리셋되며 서버 기본 속도로 자동
    -- 재배정된다(4088-4090).
    if isInactive(zed) then return true end

    -- 이미 원래 속도면(스트리밍 재진입으로 엔진이 먼저 되돌려놓은 경우)
    -- 불필요한 DoZombieStats 재굴림을 피한다.
    if readSpeed(zed) == orig then return true end

    setZombieSpeed(zed, orig)
    return true
end

local function convertEnabled()
    return SandboxVars.PongDu.BloodMoon_ConvertZombies
end

-- 셀 전수 스윕. 이벤트 중이면 변환, 아니면 잔여 마커 회수.
--
-- 평시에도 계속 도는 이유: 이벤트 도중 스트리밍 아웃된 좀비는 마커를 단 채
-- 남아 있다가 이벤트가 끝난 뒤에 돌아온다. 종료 시점의 스윕 1회만으로는 그
-- 좀비들이 영구 스프린터로 남는다. 마커 체크 자체는 ModData 조회 한 번이라
-- 비용이 사실상 없고, 평시 주기는 5배로 늘려둔다.
local function sweep()
    local cell = getCell()
    if not cell then return end
    local zl = cell:getZombieList()
    if not zl then return end

    local doConvert = _active and convertEnabled()
    local n, budget = 0, CONVERT_PER_PASS

    for i = 0, zl:size() - 1 do
        if budget <= 0 then break end
        local z = zl:get(i)
        if z then
            local ok, changed
            if doConvert then
                ok, changed = pcall(convertZombie, z)
            else
                ok, changed = pcall(revertZombie, z)
            end
            if not ok then
                log("sweep error: " .. tostring(changed))
            elseif changed then
                n = n + 1
                budget = budget - 1
            end
        end
    end

    if n > 0 then
        log((doConvert and "converted " or "reverted ") .. tostring(n)
            .. " zombies (listSize=" .. tostring(zl:size()) .. ")")
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  무들 인디케이터
-- ═══════════════════════════════════════════════════════════════════════════
-- 호드 나이트와 같은 방식으로 바닐라 무들 스택 위에 슬롯 하나를 끼워넣는다.
-- 밀어내기/슬롯 좌표/등장 슬라이드/해상도 복원은 utils/moodleStack 담당이고,
-- 여기서는 우선순위와 그리기만 정한다.
--
-- 퐁듀 인디케이터 우선순위 (작을수록 화면 위):
--   10 = 호드 나이트      20 = 블러드문
-- 즉 호드 나이트 아래, 바닐라 무들 위에 놓인다.
local SLOT_PRIORITY = 20

local TEX_PATH          = "media/ui/Moodle_BloodMoon.png"
local IND_SIZE_FALLBACK = 32   -- 텍스처 로드 실패 시에만 쓰는 값
local BKG_PATHS         = moodleStack.BKG_BAD

-- 남은 인게임 분. 서버 시계와 클라 시계를 비교하지 않고 "받은 시점 + 잔여"만
-- 쓰므로 시계 오차 영향이 없다. 현실 ms 가 아니라 게임 시간을 쓰는 이유는
-- 지속시간 자체가 인게임 기준이기 때문 -- 배속이 걸리면 같이 빨라져야 한다.
local function remainGameMin()
    if not _endHours then return 0 end
    local r = (_endHours - getGameTime():getWorldAgeHours()) * 60
    if r < 0 then r = 0 end
    -- NightsSurvived 는 SyncClock 패킷으로만 갱신되므로 7시 경계에서 잠깐
    -- getWorldAgeHours() 가 튈 수 있다. 총 길이로 상한을 물려 표시를 안정화한다.
    if _totalMin > 0 and r > _totalMin then r = _totalMin end
    return r
end

-- 배경 심각도 1~4. 호드나이트는 예약이 쌓일수록 올라가지만(고조형), 블러드문은
-- 지속형 이벤트라 "얼마나 남았나"를 그대로 단계로 쓴다 -- 남을수록 높고,
-- 끝나갈수록 낮아진다.
--   잔여 <= 1/4 -> 1    1/4~2/4 -> 2    2/4~3/4 -> 3    3/4 초과 -> 4
-- 분모는 누적 총량이 아니라 샌드박스 기본 지속시간이다. 중복 후원으로 연장돼
-- 기본값을 넘어가면 그냥 4 에서 포화된다(비율로 잡으면 연장 직후 단계가 도로
-- 내려가 표시가 거꾸로 움직인다).
local function bkgLevel()
    local dur = SandboxVars.PongDu.BloodMoon_DurationMin
    if dur <= 0 then return 4 end
    local n = math.ceil(remainGameMin() / dur * 4)
    if n < 1 then n = 1 end
    if n > 4 then n = 4 end
    return n
end

local _osc = moodleStack.newOscillator()

local BloodMoonIndicator = ISPanel:derive("BloodMoonIndicator")

-- 위치는 생성 시점에 정하지 않는다. moodleStack.sync() 가 매 틱 갱신한다.
function BloodMoonIndicator:new()
    local o = ISPanel:new(0, 0, IND_SIZE_FALLBACK, IND_SIZE_FALLBACK)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    o.tex = getTexture(TEX_PATH)
    o.bkg = {}
    for i = 1, #BKG_PATHS do
        o.bkg[i] = getTexture(BKG_PATHS[i])
    end
    return o
end

-- 현재 프레임에 쓸 아이콘 크기. 바닐라 MoodlesUI 는 UIElement.DrawTexture 로
-- "텍스처 네이티브 크기"에 그리므로(UIElement.java:282) 상수로 박지 않고 매
-- 프레임 텍스처에서 읽는다. 텍스처팩 모드가 무들 아트를 바꿔도 자동 추종.
function BloodMoonIndicator:iconSize()
    local t = (self.bkg and self.bkg[bkgLevel()]) or self.tex
    if t then
        local w, h = t:getWidth(), t:getHeight()
        if w and h and w > 0 and h > 0 then return w, h end
    end
    return IND_SIZE_FALLBACK, IND_SIZE_FALLBACK
end

local function fmtGameMinutes(totalMin)
    local m = math.floor(totalMin + 0.5)
    if m < 1 then m = 1 end
    local h = math.floor(m / 60)
    m = m - h * 60
    if h > 0 then
        return getText("IGUI_donation_blood_moon_tip_hm", tostring(h), tostring(m))
    end
    return getText("IGUI_donation_blood_moon_tip_m", tostring(m))
end

function BloodMoonIndicator:render()
    -- 바닐라와 동일하게 흔들림은 요소 위치가 아니라 "그리는 좌표"에만 먹인다
    -- (MoodlesUI.render 의 float1 과 같은 역할). 툴팁은 흔들지 않는다.
    local ox = _osc:offset()

    local bkg = self.bkg and self.bkg[bkgLevel()]
    if bkg then
        self:drawTexture(bkg, ox, 0, 1)
    end
    if self.tex then
        self:drawTexture(self.tex, ox, 0, 1)
    else
        -- 아이콘 에셋 미배치 폴백. 배경만 뜨면 무슨 무들인지 알 수 없으므로
        -- 최소한 식별 가능한 글자를 얹는다.
        local w, h = self:iconSize()
        local col = colorMap.get("blood_moon")
        textOutline.drawCentre(self, "BM", w / 2 + ox, h / 2 - 8,
            col[1], col[2], col[3], 1, UIFont.Small)
    end

    -- 호버 툴팁: 바닐라 무들 툴팁과 동일한 형태/좌표(MoodlesUI.render).
    -- isMouseOver() 는 UIElement 의 순수 좌표 판정(UIElement.java:1833)이라
    -- 마우스 이벤트 등록이 필요 없다.
    if self:isMouseOver() then
        moodleStack.drawTooltip(self,
            getText("IGUI_donation_blood_moon"),
            getText("IGUI_donation_blood_moon_tip_end", fmtGameMinutes(remainGameMin())))
    end
end

local function indicatorEnabled()
    return SandboxVars.PongDu.BloodMoon_ShowIndicator
end

local function showTimer()
    if _panel then return end
    if not indicatorEnabled() then return end
    _panel = BloodMoonIndicator:new()
    _panel:addToUIManager()
    _panel:setVisible(true)
    moodleStack.register(_panel, SLOT_PRIORITY)
    moodleStack.sync()
end

local function hideTimer()
    if not _panel then return end
    moodleStack.unregister(_panel)
    _panel:setVisible(false)
    _panel:removeFromUIManager()
    _panel = nil
    moodleStack.sync()
end

-- ═══════════════════════════════════════════════════════════════════════════
--  시작 / 종료
-- ═══════════════════════════════════════════════════════════════════════════
local START_LINE_COUNT = 5   -- IGUI_donation_blood_moon_start1..5
local END_LINE_COUNT   = 5   -- IGUI_donation_blood_moon_end1..5

-- 발동음. scripts/t3_rewards_sounds.txt 에 정의돼 있다.
-- 호드 나이트 예약음(pongdu_heartbeat)과 공유하다가 늑대 울음으로 분리했다.
local START_SOUND = "pongdu_howling"

-- Say 는 사망/미생성 타이밍에 걸릴 수 있어 pcall 로 감싼다(hordenight 과 동일).
local function sayRandomLine(prefix, count)
    local p = getPlayer()
    if not p then return end
    local key = "IGUI_donation_blood_moon_" .. prefix .. tostring(ZombRand(1, count + 1))
    pcall(function() p:Say(getText(key)) end)
end

-- ── 연출 훅 ─────────────────────────────────────────────────────────────────
-- 조명은 shared/PongDuBloodMoonLight.lua 가 담당하고, 서버가 아니라 각 클라가
-- 자기 화면에 매 틱 적용한다. SP/MP 구분 없이 여기가 유일한 진입점이다
-- (전용서버 프로세스에서는 모듈이 스스로 no-op 이 된다).
local function fxSync()
    PongDuBloodMoonLight.arm(_endHours)
end

-- 서버 End 브로드캐스트 / 클라 자체 타임아웃 / OnDisconnect 세 경로에서
-- 들어오므로 멱등이어야 한다. disarm 은 _armed 가드로 멱등이다.
local function fxStop()
    PongDuBloodMoonLight.disarm()
end

-- remainMin: 지금부터 남은 인게임 분. totalMin: 이벤트 전체 길이(툴팁 클램프용).
-- 이미 진행 중이면 종료 시각만 갱신한다(중복 후원 = 연장).
function _a.startLocal(remainMin, totalMin, sender)
    remainMin = tonumber(remainMin) or 0
    if remainMin <= 0 then
        log("startLocal ignored: remainMin=" .. tostring(remainMin))
        return
    end

    local wasActive = _active

    _totalMin = math.max(tonumber(totalMin) or remainMin, remainMin)
    _active   = true
    _endHours = getGameTime():getWorldAgeHours() + remainMin / 60

    -- 연장 시에도 불러야 한다(현재 강도에서 이어서 다시 피크로 올라간다).
    fxSync()

    if wasActive then
        log("EXTENDED remainGameMin=" .. tostring(remainMin)
            .. " sender=" .. tostring(sender))
        return
    end

    showTimer()
    sayRandomLine("start", START_LINE_COUNT)

    local audio = getSoundManager():PlaySound(START_SOUND, false, 1.0)
    if audio then audio:setVolume(0.7) end

    log("START remainGameMin=" .. tostring(remainMin)
        .. " totalGameMin=" .. tostring(_totalMin)
        .. " convertZombies=" .. tostring(convertEnabled())
        .. " sender=" .. tostring(sender))

    -- 첫 스윕을 다음 틱에 바로 돌린다 (주기를 기다리지 않음).
    _sweepTick = 0
end

function _a.stopLocal()
    if not _active then return end
    _active   = false
    _endHours = nil
    _totalMin = 0
    fxStop()
    hideTimer()
    sayRandomLine("end", END_LINE_COUNT)
    log("END -- reverting zombies")
    -- 좀비 복원은 아래 스윕이 이어서 처리한다(다음 틱부터 즉시 시작).
    _sweepTick = 0
end

-- ═══════════════════════════════════════════════════════════════════════════
--  틱
-- ═══════════════════════════════════════════════════════════════════════════
-- 종료 판정을 클라도 자체적으로 한다. 서버 End 브로드캐스트가 유실되거나
-- 서버가 죽어도 좀비가 영구히 스프린터로 남지 않게 하기 위한 안전망이다.
local function onTick()
    -- 무들박스 밀림/복귀와 아이콘 슬라이드는 패널이 없어도 계속 돌아야 한다
    -- (사라진 뒤 다른 무들들이 스르륵 올라오는 구간). 호드나이트가 같은 틱에
    -- 또 호출해도 멱등이다.
    moodleStack.sync()
    if _panel then _osc:update(bkgLevel()) end

    if _active and _endHours and getGameTime():getWorldAgeHours() >= _endHours then
        log("local timeout reached, ending")
        _a.stopLocal()
    end

    _sweepTick = _sweepTick - 1
    if _sweepTick > 0 then return end
    _sweepTick = _active and SWEEP_ACTIVE_TICKS or SWEEP_IDLE_TICKS
    sweep()
end
Events.OnTick.Add(onTick)

-- 게임 종료/캐릭터 사망으로 세션이 끝날 때 연출이 남지 않게 정리한다.
Events.OnDisconnect.Add(function()
    fxStop()
    hideTimer()
    _active   = false
    _endHours = nil
    _totalMin = 0
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  서버 커맨드 수신
-- ═══════════════════════════════════════════════════════════════════════════
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuBloodMoon" then return end

    if command == "Start" then
        _a.startLocal(args and args["remainMin"], args and args["totalMin"],
            args and args["sender"])

    elseif command == "End" then
        _a.stopLocal()

    elseif command == "State" then
        -- 중간 접속자 동기화. 진행 중이면 남은 시간만큼 시작, 아니면 정리.
        local remain = tonumber(args and args["remainMin"]) or 0
        if remain > 0 then
            _a.startLocal(remain, args and args["totalMin"], args and args["sender"])
        else
            _a.stopLocal()
        end
    end
end)

-- ── 접속 직후 상태 동기화 ────────────────────────────────────────────────────
local SYNC_DELAY_TICKS = 300   -- ~5초
local _syncTicks = -1

Events.OnGameStart.Add(function()
    _syncTicks = SYNC_DELAY_TICKS
end)

Events.OnTick.Add(function()
    if _syncTicks < 0 then return end
    _syncTicks = _syncTicks - 1
    if _syncTicks == 0 then
        _syncTicks = -1
        if isClient() then
            sendClientCommand("PongDuBloodMoon", "Sync", { ["dummy"] = 1 })
        end
    end
end)

-- ── 발동 요청 (rewardManager 에서 호출) ──────────────────────────────────────
function _a.a(sender)
    if isClient() then
        sendClientCommand("PongDuBloodMoon", "Request", { ["sender"] = sender or "" })
        log("request sent sender=" .. tostring(sender))
    else
        -- SP / 로컬 호스트: 서버 왕복 경로가 없다 (파일 상단 주석 참조).
        local dur = SandboxVars.PongDu.BloodMoon_DurationMin
        log("singleplayer path, starting locally durGameMin=" .. tostring(dur))
        _a.startLocal(dur, dur, sender or "")
    end
end

return _a
