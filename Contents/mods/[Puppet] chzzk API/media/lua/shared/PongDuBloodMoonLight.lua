-- ── 블러드문 조명 (blood_moon) ───────────────────────────────────────────────
--
-- 월드 전역 조명을 핏빛으로 물들인다. 이벤트 진행률에 따른 사다리꼴 곡선을
-- 그리고, 중복 후원(연장) 시 현재 강도에서 이어서 피크로 올라간다.
--
-- 서버가 아니라 각 클라이언트가 매 틱 자기 화면에 적용한다.
--
-- ═══ 레버: globalLight 의 override 채널 ════════════════════════════════════
-- ClimateColor.calculate() (ClimateManager.java:2765):
--     if (isModded && modInterpolate > 0)
--         internalValue.interp(moddedValue, modInterpolate, internalValue);
--     if (isOverride && interpolate > 0)
--         internalValue.interp(override, interpolate, finalValue);
--     else
--         finalValue.setTo(internalValue);
--
-- override 는 낮색/안개/야간이 전부 합성된 뒤에 걸린다(updateValues 1400-1417).
-- 그래서:
--   · 낮에도 걸린다 (야간색 레버 colNightMoon 과 달리 nightStrength 에 안 묶임)
--   · 비/안개/폭풍/천둥 연출 위에 덮인다
--   · 원상복구가 값 되돌리기 한 번으로 끝난다
--
-- override 오브젝트는 ClimateColorInfo 라 실내/실외 색을 둘 다 들고 간다.
-- 어느 쪽을 쓸지는 렌더 시점에 플레이어 기준으로 갈린다
-- (RenderSettings.java:137-147, player:getCurrentSquare():isInARoom()).
--
-- ═══ SP 와 MP 클라의 적용 방식이 다르다 ════════════════════════════════════
-- [SP] updateValues() 가 로컬에서 돌아 internalValue 가 진짜 자연광이다.
--      그러니 override 색은 핏빛 상수로 박아두고 interpolate 만 0->1->0 으로
--      움직이면 된다. 엔진이 알아서 자연광과 섞어준다.
--
-- [MP 클라] 두 가지가 다르다.
--      ① internalValue 가 자연광이 아니다. 클라는 updateValues() 를 호출하지
--         않고(843줄), 기후 패킷을 받을 때 internalValue = 직전 finalValue 로
--         밀어넣을 뿐이다(1841-1845).
--      ② interpolate 를 우리가 못 정한다. 매 프레임 networkLerp 로 덮어써진다
--         (959-961줄). 패킷 후 5초가 지나면 1.0 으로 고정되므로 결국
--         finalValue = override 그 자체가 된다.
--      즉 MP 클라에서 유일하게 살아남는 레버는 override 의 "색" 뿐이다.
--      그래서 자연광 + 핏빛 보간을 우리가 직접 계산해 override 에 통째로 써넣는다.
--
--      자연광(base)은 서버가 10 인게임분마다 override 에 덮어써주는 값이다.
--      우리가 마지막에 써넣은 값과 달라져 있으면 "서버가 방금 갱신했다"는
--      뜻이므로 그 값을 새 base 로 잡는다. 이 비교가 base 추적의 전부다.
--      (우리가 쓴 float 를 그대로 읽어오므로 평상시엔 정확히 일치한다.
--       서버 값이 8개 성분 모두 우연히 일치할 확률은 사실상 0 이다.)
--
-- ═══ 왜 서버가 아니라 클라인가 ═════════════════════════════════════════════
-- 서버에서 override 를 걸면 결과가 기후 패킷에 실려 나가는데, 그 패킷은
-- 10 인게임분에 한 번만 나간다(890줄, tickIsTenMins 가드). 기본 120분 이벤트면
-- 상승 구간 30분이 3스텝이라 눈에 띄게 계단으로 뚝뚝 오른다.
-- 클라에서 매 틱 계산하면 프레임 단위로 매끄럽고, 종료 복구도 즉시 된다.
-- 이벤트 타임라인(_endHours)은 어차피 모든 클라가 이미 들고 있다.
--
-- 전용서버 프로세스는 렌더링을 하지 않으므로 이 모듈이 아무 일도 하지 않는다.

PongDuBloodMoonLight = PongDuBloodMoonLight or {}
local _m = PongDuBloodMoonLight

-- ── 상수 ────────────────────────────────────────────────────────────────────
local COLOR_GLOBAL_LIGHT = 0   -- ClimateManager.COLOR_GLOBAL_LIGHT (133줄)

-- 네 번째 성분은 RGB 가 아니라 블렌드 강도다(ClimateColorInfo).
-- 실내는 창문 마스크 경로로 따로 칠해지므로 실외보다 약하게 잡는다.
local BLOOD_EXT = { 0.85, 0.05, 0.06, 0.60 }
local BLOOD_INT = { 0.55, 0.05, 0.07, 0.45 }

-- 혼합 최대치. 1.0 이면 자연광이 완전히 사라져 낮/밤 명암 자체가 없어진다.
-- 0.7 이면 자연광이 30% 남아 낮은 밝은 핏빛, 밤은 어두운 핏빛으로 구분된다.
local PEAK = 0.7

-- ── 강도 곡선 ───────────────────────────────────────────────────────────────
--   0% ~ 25%  : 자연광 -> 블러드문 (상승)
--  25% ~ 75%  : 최대 유지
--  75% ~ 100% : 블러드문 -> 자연광 (하강)
--
--  1.0        ┌────────────────────┐
--             │                    │
--  0.0 ───────┘                    └────────
--        0%  25%                  75%   100%
--
-- 비율은 "arm 시점부터 종료까지 남은 구간" 기준이다. 연장이 들어오면 남은
-- 구간이 새로 잡히고, 상승 구간의 시작값은 0 이 아니라 "지금 강도"가 된다.
local RAMP_UP_FRAC   = 0.25
local RAMP_DOWN_FRAC = 0.25

-- 값이 이보다 덜 움직였으면 세팅을 건너뛴다. 매 틱 도는 코드라 의미가 있다.
local EPSILON = 0.001

local function llog(msg)
    print("[PongDuBloodMoonLight] " .. tostring(msg))
end

-- ── 상태 ────────────────────────────────────────────────────────────────────
-- 이벤트 타이머와 조명 상태는 분리해서 들고 있는다. 조명 쪽은 arm() 이 넘겨준
-- 종료 시각만 알면 되고, 발동 조건이나 서버장 판정 따위는 알 필요가 없다.
local _armed     = false
local _rampStart = 0     -- 현재 상승 구간의 시작 시각 (worldAgeHours)
local _rampFrom  = 0     -- _rampStart 시점의 강도 (0~1 정규화)
local _peakStart = 0
local _fadeStart = 0
local _endHours  = 0
local _intensity = 0     -- 마지막으로 계산한 정규화 강도 (0~1)
local _appliedT  = nil   -- SP 경로에서 마지막으로 세팅한 interpolate
local _base      = nil   -- MP 경로에서 추적 중인 자연광 { ex = {...}, inr = {...} }
local _written   = nil   -- MP 경로에서 마지막으로 써넣은 값 (읽어온 값)
local _mode      = nil   -- "sp" | "mp" | "admin"

local function gameHours()
    return getGameTime():getWorldAgeHours()
end

-- 전용서버 프로세스는 화면이 없으므로 아무것도 하지 않는다.
local function hasScreen()
    return not isServer()
end

-- ── ClimateColorInfo 읽기/쓰기 ──────────────────────────────────────────────
-- getExterior() 는 라이브 Color 객체를 돌려주므로 참조를 들고 있으면 안 된다.
-- zombie.core.Color 에는 getA() 가 없고 getAlpha()(0~255 int) / getAlphaFloat()
-- (0~1) 뿐이라 RGB 도 *Float 계열로 통일해 읽는다.
local function readInfo(info)
    local ex, inr = info:getExterior(), info:getInterior()
    return {
        ex  = { ex:getRedFloat(),  ex:getGreenFloat(),  ex:getBlueFloat(),  ex:getAlphaFloat() },
        inr = { inr:getRedFloat(), inr:getGreenFloat(), inr:getBlueFloat(), inr:getAlphaFloat() },
    }
end

local function sameInfo(a, b)
    if not a or not b then return false end
    for i = 1, 4 do
        if a.ex[i] ~= b.ex[i] then return false end
        if a.inr[i] ~= b.inr[i] then return false end
    end
    return true
end

-- base 에서 핏빛까지를 t 로 보간해 써넣는다. t = 0 이면 base 와 정확히 같은
-- 값이 들어가므로 시작/종료 시점에 조명이 튀지 않는다.
local function writeBlend(info, base, t)
    info:setExterior(
        PZMath.lerp(base.ex[1], BLOOD_EXT[1], t),
        PZMath.lerp(base.ex[2], BLOOD_EXT[2], t),
        PZMath.lerp(base.ex[3], BLOOD_EXT[3], t),
        PZMath.lerp(base.ex[4], BLOOD_EXT[4], t))
    info:setInterior(
        PZMath.lerp(base.inr[1], BLOOD_INT[1], t),
        PZMath.lerp(base.inr[2], BLOOD_INT[2], t),
        PZMath.lerp(base.inr[3], BLOOD_INT[3], t),
        PZMath.lerp(base.inr[4], BLOOD_INT[4], t))
end

local function writeInfo(info, snap)
    info:setExterior(snap.ex[1],  snap.ex[2],  snap.ex[3],  snap.ex[4])
    info:setInterior(snap.inr[1], snap.inr[2], snap.inr[3], snap.inr[4])
end

local function globalLightColor()
    local cm = getClimateManager()
    if not cm then return nil end
    return cm:getClimateColor(COLOR_GLOBAL_LIGHT)
end

-- ── SP 적용 ─────────────────────────────────────────────────────────────────
-- interpolate 를 세팅할 public setter 가 setOverride(ClimateColorInfo, float)
-- 하나뿐인데 setOverride(ByteBuffer, float) 오버로드가 있어서 Kahlua 의 인자
-- 타입 해석이 어긋날 여지가 있다. 실패하면 어드민 채널로 내려간다 -- 그쪽은
-- 바닐라 기후 패널이 쓰는 경로라 동작이 보장되지만, finalValue 를 통째로
-- 교체하므로(calculate 2766줄) 자연광 블렌드가 사라진다.
local function applySP(cc, t)
    if _appliedT and math.abs(t - _appliedT) < EPSILON then return end
    _appliedT = t

    if t <= 0 then
        pcall(function() cc:setEnableOverride(false) end)
        pcall(function() cc:setEnableAdmin(false) end)
        return
    end

    if _mode ~= "admin" then
        local ok, err = pcall(function()
            local ov = cc:getOverride()
            ov:setExterior(BLOOD_EXT[1], BLOOD_EXT[2], BLOOD_EXT[3], BLOOD_EXT[4])
            ov:setInterior(BLOOD_INT[1], BLOOD_INT[2], BLOOD_INT[3], BLOOD_INT[4])
            cc:setOverride(ov, t)
        end)
        if ok then return end
        _mode = "admin"
        llog("WARNING: override channel unavailable (" .. tostring(err) .. ")"
            .. " -- falling back to admin channel, natural light blend will be lost")
    end

    cc:setAdminValueExterior(BLOOD_EXT[1], BLOOD_EXT[2], BLOOD_EXT[3], BLOOD_EXT[4] * t)
    cc:setAdminValueInterior(BLOOD_INT[1], BLOOD_INT[2], BLOOD_INT[3], BLOOD_INT[4] * t)
    cc:setEnableAdmin(true)
end

-- ── MP 클라 적용 ────────────────────────────────────────────────────────────
-- override 의 색만 우리가 계산해 덮어쓴다. interpolate 는 엔진이 networkLerp 로
-- 관리하므로 건드리지 않는다 -- 패킷 직후 5초 동안은 그 값이 1 미만이라 직전
-- 프레임 색에서 새 색으로 자연스럽게 흘러가고, 그 뒤로는 1.0 고정이라 우리가
-- 쓴 색이 그대로 화면에 나온다.
local function applyMP(cc, t)
    local ov = cc:getOverride()
    local cur = readInfo(ov)

    -- 우리가 마지막에 쓴 값과 다르다 = 서버가 새 자연광을 밀어넣었다.
    if not sameInfo(cur, _written) then
        _base = cur
    end
    if not _base then _base = cur end

    writeBlend(ov, _base, t)
    _written = readInfo(ov)
end

-- 이벤트 종료 시 복구.
local function clearLight()
    local cc = globalLightColor()
    if cc then
        if _mode == "mp" then
            -- override 를 끄면 finalValue = internalValue 가 되는데, MP 클라의
            -- internalValue 는 우리가 물들여놓은 직전 finalValue 다. 다음 패킷이
            -- 올 때까지(최대 10 인게임분) 핏빛이 얼어붙는다. 그러니 끄지 말고
            -- 추적해둔 자연광을 그대로 써넣는다 -- 즉시 원상복구된다.
            if _base then writeBlend(cc:getOverride(), _base, 0) end
        else
            pcall(function() cc:setEnableOverride(false) end)
            pcall(function() cc:setEnableAdmin(false) end)
        end
    end
    _appliedT  = nil
    _written   = nil
    _base      = nil
    _intensity = 0
    llog("light cleared (natural light restored)")
end

-- ── 강도 계산 ───────────────────────────────────────────────────────────────
-- 상태(_rampStart/_rampFrom/_peakStart/_fadeStart/_endHours)만 보고 계산하는
-- 순수 함수다. 어느 시점에 불러도 같은 값이 나오므로, 연장 시 "지금 값"을
-- 그대로 새 상승 구간의 시작점으로 물려받을 수 있다.
local function intensityNow()
    if not _armed or _endHours <= 0 then return 0 end

    local now = gameHours()
    if now >= _endHours then return 0 end
    if now <= _rampStart then return _rampFrom end

    if now < _peakStart then
        local span = _peakStart - _rampStart
        if span <= 0 then return 1 end
        return _rampFrom + (1 - _rampFrom) * ((now - _rampStart) / span)
    end

    if now < _fadeStart then return 1 end

    local span = _endHours - _fadeStart
    if span <= 0 then return 0 end
    return (_endHours - now) / span
end

-- 정규화 강도(0~1) -> 실제 혼합 계수.
local function toBlend(p)
    return p * PEAK * (SandboxVars.PongDu.BloodMoon_LightStrength / 100)
end

local function applyNow()
    local cc = globalLightColor()
    if not cc then return end
    local t = toBlend(_intensity)
    if _mode == "mp" then
        applyMP(cc, t)
    else
        applySP(cc, t)
    end
end

-- ── 공개 API ────────────────────────────────────────────────────────────────
-- endHours: 종료 예정 인게임 시각(getWorldAgeHours 기준).
-- 시작이든 연장이든 같은 경로를 탄다 -- 시작은 그냥 _rampFrom = 0 인 연장이다.
function _m.arm(endHours)
    if not hasScreen() then return end

    endHours = tonumber(endHours) or 0
    local now = gameHours()
    if endHours <= now then
        llog("arm ignored: endHours=" .. tostring(endHours) .. " now=" .. tostring(now))
        return
    end

    if not _armed then
        _intensity = 0
        if _mode ~= "admin" then
            _mode = isClient() and "mp" or "sp"
        end
        llog("channel = " .. tostring(_mode))
    else
        -- 연장. _intensity 는 틱에서만 갱신되므로 여기서 다시 계산해
        -- "지금 이 순간의 강도"를 정확히 물려받는다.
        _intensity = intensityNow()
    end

    local span = endHours - now
    _rampFrom  = _intensity
    _rampStart = now
    _endHours  = endHours
    _peakStart = now + span * RAMP_UP_FRAC
    _fadeStart = now + span * (1.0 - RAMP_DOWN_FRAC)
    _armed     = true

    llog((_rampFrom > 0 and "REARM" or "ARM")
        .. " spanGameMin=" .. tostring(span * 60)
        .. " resumeFrom=" .. tostring(_rampFrom)
        .. " peakBlend=" .. tostring(toBlend(1)))

    applyNow()
end

function _m.disarm()
    if not hasScreen() then return end
    if not _armed then return end
    _armed    = false
    _endHours = 0
    _rampFrom = 0
    clearLight()
end

function _m.isArmed()
    return _armed
end

function _m.getIntensity()
    return _intensity
end

-- ── 틱 ──────────────────────────────────────────────────────────────────────
-- 매 프레임 돈다. 하는 일은 float 8개 읽기 / 비교 / 쓰기라 비용이 사실상 없고,
-- 이 주기가 곧 곡선의 해상도다.
local function lightTick()
    if not _armed then return end
    if not hasScreen() then return end

    _intensity = intensityNow()
    applyNow()

    -- 종료 판정은 이벤트 쪽(클라 타임아웃 / 서버 End 브로드캐스트)이 하지만,
    -- 그게 유실돼도 조명이 영구히 남지 않게 여기서도 걷어낸다.
    if gameHours() >= _endHours then
        llog("timeline elapsed, disarming")
        _m.disarm()
    end
end
Events.OnTick.Add(lightTick)

return _m
