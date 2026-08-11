local _a = {}
require("ISUI/ISPanel")
local timerStack  = require("utils/timerStack")
local colorMap    = require("utils/colorMap")
local textOutline = require("utils/textOutline")

-- ── 블러드문 (blood_moon) 클라이언트 ─────────────────────────────────────────
--
-- 서버 후원(PongDu_Server 탭) 계열. 서버장에게 후원이 들어오면 접속자 전원에게
-- 일정 인게임 시간 동안 다음 3가지가 동시에 걸린다:
--   ① 핏빛 달빛  : ClimateManager 야간 색상 교체
--   ② 화면 틴트  : 붉은 비네트 오버레이 (낮에 강하게, 밤에 약하게)
--   ③ 좀비 가속  : 뮤턴트/퐁듀 소유 좀비를 제외한 모든 일반좀비를 스프린터로
-- 종료 시 셋 다 원상복구한다.
--
-- 서버(server/PongDuBloodMoonServer.lua)는 "언제 시작하고 언제 끝나는가"만
-- 관리하고, 위 3가지 적용은 전부 이 파일이 각 클라에서 로컬로 수행한다.
-- 특히 ③이 클라 담당인 이유는 B41 좀비 소유권 모델 때문이다 -- 서버에서
-- IsoZombie 스탯을 바꾸면 소유 클라의 sync 패킷에 그대로 덮어써진다.
--
-- 싱글플레이 예외: SP 는 sendClientCommand/sendServerCommand 가 둘 다 동작하지
-- 않으므로(LuaManager.java 의 GameClient.bClient / GameServer.bServer 가드),
-- medicalbox.lua 와 같은 방식으로 서버 왕복 없이 로컬에서 바로 시작한다.

-- ── 조명 ────────────────────────────────────────────────────────────────────
-- ClimateManager.java:1416 에서 매 프레임
--     colNightNoMoon.interp(colNightMoon, moonFloat, colNight)
--     globalLight.interp(colNight, nightStrength, globalLight)
-- 가 돈다. 즉 colNight 는 "입력"이 아니라 매 프레임 재계산되는 "출력"이라
-- setExterior 해봐야 다음 프레임에 덮어써진다 -- 손대지 않는다.
-- 실제로 유효한 레버는 colNightMoon / colNightNoMoon 둘뿐이고, 둘 다 생성자
-- (206~215줄) 이후로는 엔진이 건드리지 않으므로 한 번 세팅하면 유지된다.
--
-- 달 위상(moonFloat)에 따라 결과가 흔들리지 않도록 Moon/NoMoon 을 같은 값으로
-- 맞춘다. 바닐라 기본값은 (0.33, 0.33, 1.0, 0.4) 푸른색이고, 네 번째 성분은
-- RGB 가 아니라 블렌드 강도다(ClimateColorInfo 클래스 주석).
local BLOOD_EXTERIOR = { 0.72, 0.09, 0.11, 0.52 }
local BLOOD_INTERIOR = { 0.42, 0.06, 0.09, 0.30 }

-- ── 화면 틴트 ───────────────────────────────────────────────────────────────
-- 조명은 nightStrength 로 블렌딩되므로 낮(nightStrength≈0)에는 아무 효과가 없다.
-- 그 구간을 화면 오버레이가 메운다. 반대로 밤에는 조명이 이미 화면 전체를
-- 붉게 만들고 있어 틴트까지 겹치면 시야가 죽으므로 강도를 낮춘다.
--     alpha = fade * (NIGHT + (DAY - NIGHT) * (1 - nightStrength)) * 샌박배율
-- 낮/밤 전환 구간에서 자동으로 크로스페이드되므로 별도 분기가 필요 없다.
local TINT_PATH     = "media/textures/donation/bloodmoon_tint.png"
local TINT_DAY      = 1.00   -- nightStrength = 0 (한낮)
local TINT_NIGHT    = 0.28   -- nightStrength = 1 (한밤)
local FADE_SPEED    = 0.012  -- 시작/종료 페이드 (getGameSpeed 배율 적용)

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
local _fade        = 0     -- 틴트 페이드 계수 0..1
local _sweepTick   = 0
local _panel       = nil
local _tintTex     = nil
local _tintTexTried = false

-- 조명 원본 스냅샷. ClimateColorInfo.getExterior() 는 라이브 Color 객체를
-- 돌려주므로 참조를 들고 있으면 안 된다 -- r/g/b/a 를 값으로 복사한다.
local _lightSaved  = nil

local function screenW() return getCore():getScreenWidth() end
local function screenH() return getCore():getScreenHeight() end

-- PZMath.lerp / PZMath.clampFloat 를 쓰지 않는 이유:
-- clampFloat 는 바닐라 Lua 에서 실사용되지만 lerp 는 단 한 번도 호출되지 않는다.
-- 둘 다 한 줄짜리 산술이라 외부 클래스에 의존할 이유가 없어 로컬로 둔다.
local function clamp01(v)
    if v < 0 then return 0 end
    if v > 1 then return 1 end
    return v
end

local function lerp(from, to, t)
    return from + (to - from) * t
end

-- ═══════════════════════════════════════════════════════════════════════════
--  조명 적용 / 복원
-- ═══════════════════════════════════════════════════════════════════════════
-- 주의: zombie.core.Color 에는 getA() 가 없다. 알파는 getAlpha()(0~255 int)와
-- getAlphaFloat()(0~1 float) 두 가지뿐이라, RGB 도 *Float 계열로 통일해 읽는다.
local function snapColor(colorInfo)
    local ex, inr = colorInfo:getExterior(), colorInfo:getInterior()
    return {
        ex  = { ex:getRedFloat(),  ex:getGreenFloat(),  ex:getBlueFloat(),  ex:getAlphaFloat() },
        inr = { inr:getRedFloat(), inr:getGreenFloat(), inr:getBlueFloat(), inr:getAlphaFloat() },
    }
end

local function restoreColor(colorInfo, snap)
    colorInfo:setExterior(snap.ex[1], snap.ex[2], snap.ex[3], snap.ex[4])
    colorInfo:setInterior(snap.inr[1], snap.inr[2], snap.inr[3], snap.inr[4])
end

local function applyLight()
    if _lightSaved then return end   -- 중복 후원으로 재진입해도 스냅샷은 1회만
    local cm = getClimateManager()
    if not cm then
        log("applyLight aborted: climate manager is nil")
        return
    end

    local moon, noMoon = cm:getColNightMoon(), cm:getColNightNoMoon()
    _lightSaved = { moon = snapColor(moon), noMoon = snapColor(noMoon) }

    for _, ci in ipairs({ moon, noMoon }) do
        ci:setExterior(BLOOD_EXTERIOR[1], BLOOD_EXTERIOR[2], BLOOD_EXTERIOR[3], BLOOD_EXTERIOR[4])
        ci:setInterior(BLOOD_INTERIOR[1], BLOOD_INTERIOR[2], BLOOD_INTERIOR[3], BLOOD_INTERIOR[4])
    end
    log("light applied ext=" .. tostring(BLOOD_EXTERIOR[1]) .. "," .. tostring(BLOOD_EXTERIOR[2])
        .. "," .. tostring(BLOOD_EXTERIOR[3]) .. " a=" .. tostring(BLOOD_EXTERIOR[4]))
end

local function restoreLight()
    if not _lightSaved then return end
    local cm = getClimateManager()
    if cm then
        restoreColor(cm:getColNightMoon(), _lightSaved.moon)
        restoreColor(cm:getColNightNoMoon(), _lightSaved.noMoon)
        log("light restored")
    else
        log("restoreLight skipped: climate manager is nil")
    end
    _lightSaved = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
--  화면 틴트
-- ═══════════════════════════════════════════════════════════════════════════
-- 텍스처가 없어도(에셋 미배치) 크래시 없이 조용히 스킵된다. getTexture 결과를
-- false 로 캐싱해 매 프레임 파일 조회가 반복되지 않게 한다 (DonationReceiver
-- 의 getIconTexture 와 같은 기법).
local function tintTexture()
    if not _tintTexTried then
        _tintTexTried = true
        _tintTex = getTexture(TINT_PATH) or false
        if _tintTex == false then
            log("tint texture missing: " .. TINT_PATH .. " (overlay disabled)")
        end
    end
    if _tintTex == false then return nil end
    return _tintTex
end

local function tintScale()
    local pct = SandboxVars.PongDu.BloodMoon_TintStrength
    return pct / 100
end

local function drawTint()
    if not isIngameState() then return end
    if _fade <= 0 then return end

    local tex = tintTexture()
    if not tex then return end

    local cm = getClimateManager()
    if not cm then return end

    -- nightStrength: 0(한낮) ~ 1(한밤). ClimateManager.java:454
    local ns = clamp01(cm:getNightStrength())
    local a = _fade * (TINT_NIGHT + (TINT_DAY - TINT_NIGHT) * (1.0 - ns)) * tintScale()
    if a <= 0 then return end
    if a > 1 then a = 1 end

    UIManager.DrawTexture(tex, 0, 0, screenW(), screenH(), a)
end

-- 페이드는 렌더가 아니라 틱에서 진행시킨다 (프레임레이트 독립).
-- getGameSpeed() 배율을 곱해 배속 중에도 연출 길이가 체감상 유지되게 한다.
local function stepFade()
    local target = _active and 1.0 or 0.0
    if _fade == target then return end
    local speed = FADE_SPEED * getGameSpeed()
    _fade = lerp(_fade, target, speed)
    if target == 0 and _fade < 0.002 then _fade = 0 end
    if target == 1 and _fade > 0.998 then _fade = 1 end
end

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
local function setZombieSpeed(zed, target)
    local so = getSandboxOptions()
    local prev = so:getOptionByName("ZombieLore.Speed"):getValue()
    so:set("ZombieLore.Speed", target)
    zed:makeInactive(true)
    zed:makeInactive(false)
    so:set("ZombieLore.Speed", prev)
end

-- 변환 제외 대상 판정.
--   PongDuCompat.isOwnedZombie : 뮤턴트 4종(screamer/brute/roach/tracer) +
--     뮤턴트 스프린터(PuppetMutant="sprinter") + 일반 스프린터(isSprinter) +
--     히트맨 NPC. server/PongDuCompatRandomZombies.lua 에 정의돼 있고
--     media/lua/server/ 는 클라에서도 로드되므로 여기서 그대로 쓸 수 있다.
--   inactive : 휴면(가상) 좀비. makeInactive(true) 가 "이미 inactive 면 no-op"
--     이라(IsoZombie.java:4080) 토글하면 깨워버리는 부작용이 있어 건너뛴다.
--     RandomZombies 모드는 이 가드가 없어서 대규모 휴면 무리를 깨운다.
local function isConvertible(zed)
    if not zed then return false end
    if zed.inactive == true then return false end
    if PongDuCompat and PongDuCompat.isOwnedZombie and PongDuCompat.isOwnedZombie(zed) then
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

local function convertZombie(zed)
    if isForeign(zed) then return false end
    local md = zed:getModData()
    if md[MD_MARK] then return false end
    if not isConvertible(zed) then return false end

    local cur = tonumber(zed.speedType)
    md[MD_ORIG] = (cur == 1 or cur == 2 or cur == 3) and cur or nil
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

    -- 변환 후에 휴면 상태로 넘어간 좀비는 이미 엔진이 speedType 을 3 으로
    -- 강제해둔 상태다(IsoZombie.java:4086). 여기서 makeInactive 를 토글하면
    -- 되돌리는 게 아니라 잠든 좀비를 깨우는 꼴이 된다. 마커만 지우면 되고,
    -- 엔진이 나중에 이 좀비를 깨울 때 speedType 이 -1 로 리셋되며 서버 기본
    -- 속도로 자동 재배정된다(4088-4090).
    if zed.inactive == true then return true end

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
--  카운트다운 패널 (timerStack 공용 배치)
-- ═══════════════════════════════════════════════════════════════════════════
-- 폭/높이는 bombard·zombierain·firesupport 패널과 동일 규격이어야 timerStack
-- 의 ROW_HEIGHT(34) 계산과 맞는다.
local BloodMoonTimer = ISPanel:derive("BloodMoonTimer")

function BloodMoonTimer:new()
    local o = ISPanel:new(getCore():getScreenWidth() / 2 - 120, 0, 240, 30)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

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

function BloodMoonTimer:render()
    local m = math.floor(remainGameMin() + 0.5)
    local h = math.floor(m / 60)
    m = m - h * 60
    local col = colorMap.get("blood_moon")
    textOutline.drawCentre(self,
        getText("IGUI_donation_blood_moon_timer") .. " "
            .. string.format("%02d:%02d", h, m),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
end

local function showTimer()
    if _panel then return end
    if not SandboxVars.PongDu.BloodMoon_ShowTimer then return end
    _panel = BloodMoonTimer:new()
    _panel:addToUIManager()
    _panel:setVisible(true)
    timerStack.register(_panel)
end

local function hideTimer()
    if not _panel then return end
    timerStack.unregister(_panel)
    _panel:removeFromUIManager()
    _panel = nil
end

-- ═══════════════════════════════════════════════════════════════════════════
--  시작 / 종료
-- ═══════════════════════════════════════════════════════════════════════════
local START_LINE_COUNT = 5   -- IGUI_donation_blood_moon_start1..5
local END_LINE_COUNT   = 5   -- IGUI_donation_blood_moon_end1..5

-- Say 는 사망/미생성 타이밍에 걸릴 수 있어 pcall 로 감싼다(hordenight 과 동일).
local function sayRandomLine(prefix, count)
    local p = getPlayer()
    if not p then return end
    local key = "IGUI_donation_blood_moon_" .. prefix .. tostring(ZombRand(1, count + 1))
    pcall(function() p:Say(getText(key)) end)
end

-- remainMin: 지금부터 남은 인게임 분. totalMin: 이벤트 전체 길이(툴팁 클램프용).
-- 이미 진행 중이면 종료 시각만 갱신한다(중복 후원 = 연장). 조명/좀비는 이미
-- 걸려 있으므로 재적용하지 않는다.
function _a.startLocal(remainMin, totalMin, sender)
    remainMin = tonumber(remainMin) or 0
    if remainMin <= 0 then
        log("startLocal ignored: remainMin=" .. tostring(remainMin))
        return
    end

    local wasActive = _active
    _endHours = getGameTime():getWorldAgeHours() + remainMin / 60
    _totalMin = math.max(tonumber(totalMin) or remainMin, remainMin)

    if wasActive then
        log("EXTENDED remainGameMin=" .. tostring(remainMin)
            .. " sender=" .. tostring(sender))
        return
    end

    _active = true
    applyLight()
    showTimer()
    sayRandomLine("start", START_LINE_COUNT)

    local audio = getSoundManager():PlaySound("pongdu_heartbeat", false, 1.0)
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
    restoreLight()
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
-- 서버가 죽어도 조명/좀비가 영구히 남지 않게 하기 위한 안전망이다.
local function onTick()
    stepFade()

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
Events.OnPreUIDraw.Add(drawTint)

-- 게임 종료/캐릭터 사망으로 세션이 끝날 때 조명이 남지 않게 되돌린다.
-- (ClimateManager 는 월드 단위라 재접속 시 초기화되지만, 로컬 호스트에서
--  같은 프로세스로 재접속하는 경우가 있어 명시적으로 정리한다)
Events.OnDisconnect.Add(function()
    restoreLight()
    hideTimer()
    _active = false
    _fade   = 0
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
