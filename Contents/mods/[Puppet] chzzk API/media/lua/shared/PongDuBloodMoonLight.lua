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
--
-- ═══ 안개 / 포화도 저하 ════════════════════════════════════════════════════
-- globalLight 와 같은 곡선을 타고 자연값 -> FOG_PEAK / DESAT_PEAK 로 올라간다.
-- 이쪽은 ClimateFloat 채널(FLOAT_FOG_INTENSITY / FLOAT_DESATURATION)이고
-- 레버 구조는 ClimateColor 와 완전히 동일하다(override / admin / modded).
-- 안개는 finalValue 가 updateFx() 에서 weatherFX 로 흘러가야 실제 안개 스프라이트가
-- 나오므로, finalValue 만 쓰면 안 되고 반드시 override 를 써서 다음 프레임
-- calculate() 를 거치게 해야 한다.
--
-- ═══ 어두움 (DAYLIGHT_STRENGTH) ═══════════════════════════════════════════
-- 관리자 패널 "기후 조절" 의 "어두움" 슬라이더와 같은 채널(FLOAT_DAYLIGHT_STRENGTH,
-- id=11). 위 색/안개/포화도는 전부 "무엇을 섞을지"의 문제라 화면이 얼마나
-- 밝은가와는 별개인데, 이 채널은 RenderSettings.java 에서
-- darkness = 1 - CM_DayLightStrength 로 변환된 뒤 R/G/B 에 곱해지는 실제 밝기
-- 배율이다(rmod/gmod/bmod = Lerp(1.0, 0.7, darkness)). 실내 ambient 최소치와
-- 시야 콘(계산은 LightingJNI.calculateVisionCone)에도 같이 걸려서, 색을
-- 아무리 붉게/어둡게 잡아도 안 나던 "정말 안 보인다"는 체감을 준다.
-- 안개/포화도와 곡선 구조는 같지만 방향이 반대다(자연값 -> peak 로 하강,
-- darkTarget 참조) -- 안개/포화도는 "더한다", 어두움은 "깎는다".
--
-- ═══ 패킷 프레임 1프레임 점멸 ══════════════════════════════════════════════
-- MP 클라에서 기후 패킷이 오는 프레임에 붉은빛이 한 프레임 통째로 빠진다.
-- 원인은 networkLerp 계산의 float 정밀도 버그다(ClimateManager.java:826-834):
--     if ((float)long0 < (float)networkUpdateStamp + networkLerpTime)
-- 밀리초 epoch(~1.79e12)를 float 로 캐스팅하면 ULP 가 131072ms(~131초)라
-- 오른쪽의 +500ms(networkLerpTime)가 반올림으로 통째로 사라진다. 즉 조건은
-- 사실상 항상 false 이고 networkLerp 는 늘 1.0 이다 -- 5초 보간이 죽어 있다.
-- 그래서 패킷이 온 프레임의 순서가 이렇게 된다:
--     ① 패킷 수신    : internalValue = finalValue(핏빛), override = 자연광
--     ② climate update: interpolate = networkLerp = 1.0
--     ③ calculate()  : finalValue = lerp(1.0, internal, override) = 자연광
--     ④ OnTick(우리) : override 를 다시 핏빛으로 되돌림
--     ⑤ 렌더         : finalValue 를 읽음 -> ③의 자연광
-- ④가 ⑤보다 먼저인데 ③이 이미 finalValue 를 갈아엎은 뒤라 한 프레임이 샌다.
-- 조명 변화는 LightingThread 를 통해 사각형 단위로 번져 나갔다 돌아오므로
-- 체감상 0.1~0.3초짜리 점멸로 보인다.
--
-- 해결: override 뿐 아니라 finalValue 에도 같은 값을 직접 써넣는다. 우리 틱은
-- 렌더보다 앞이므로(IngameState.java:1309-1311, IsoWorld.update 이후 OnTick,
-- 그 뒤 render) 그 프레임 렌더가 우리 값을 본다. finalValue 는 다음 프레임
-- calculate() 가 어차피 재계산하므로 부작용이 없다.
-- 다만 updateFx()/SkyBox 는 ClimateManager.update() 안에서 이미 돌아간 뒤라
-- 하늘 색만 한 프레임 튀는 건 엔진 훅 없이는 못 막는다(지상 조명은 해결됨).
--
-- ═══ UI 틴트 텍스쳐 ═════════════════════════════════════════════════════════
-- 위 세 채널(조명/안개/포화도)은 전부 ClimateManager 소관이라 "자연값과 섞기"가
-- 항상 문제였다. 틴트 텍스쳐는 그런 제약이 없다 -- ClimateManager 를 거치지
-- 않고 client/features/bloodmoon.lua 가 OnPreUIDraw 훅에서 UIManager.DrawTexture
-- 로 직접 그리는 이미지라, 여기서는 "지금 알파가 얼마여야 하나" 숫자 하나만
-- 계산해서 _m.getTintAlpha() 로 내주면 끝이다. base 추적도, SP/MP 분기도 없다
-- -- 같은 사다리꼴 곡선(_intensity)만 공유한다.
--
-- (예전엔 ISPanel + addToUIManager() 로 그렸다. 전체화면 크기의 UI 엘리먼트가
-- 마우스 히트테스트 최상단을 차지해서 우클릭 등 월드 입력이 막히는 문제가
-- 있어 순수 렌더 훅 방식으로 교체했다 -- bombard.lua 의 DOTex(kaboom 플래시)와
-- 동일한 패턴. 자세한 배경은 client/features/bloodmoon.lua 의 BloodMoonTint
-- 주석 참조.)

PongDuBloodMoonLight = PongDuBloodMoonLight or {}
local _m = PongDuBloodMoonLight

-- ── 상수 ────────────────────────────────────────────────────────────────────
local COLOR_GLOBAL_LIGHT = 0   -- ClimateManager.COLOR_GLOBAL_LIGHT (133줄)

-- ClimateManager.FLOAT_* (118-131줄)
local FLOAT_DESATURATION      = 0
local FLOAT_FOG_INTENSITY     = 5
-- 관리자 패널 "기후 조절"의 "어두움" 슬라이더가 조작하는 채널이 이거다
-- (ISAdmPanelClimate.lua 의 DarknessSlider, RenderSettings.java:140의
-- darkness = 1 - CM_DayLightStrength). globalLight 색 블렌드와 달리 렌더
-- 단계에서 R/G/B 에 직접 곱해지는 진짜 밝기 배율이다(RenderSettings.java:189-191,
-- Lerp(1.0, 0.7, darkness)) -- 그래서 색을 아무리 어둡게 잡아도 못 주는
-- "정말 안 보인다"는 체감을 준다. 실내에서는 ambient 최소치도 같이 낮춰서
-- (154줄) 실내조차 어두워진다. 시야 콘도 줄인다(LightingJNI.java
-- calculateVisionCone, 458/460줄).
local FLOAT_DAYLIGHT_STRENGTH = 11

-- 네 번째 성분은 RGB 가 아니라 블렌드 강도다(ClimateColorInfo).
-- 실내는 창문 마스크 경로로 따로 칠해지므로 실외보다 약하게 잡는다.
--
-- 색 자체를 "핏빛"에서 "핏빛 도는 일식"으로 옮겼다. 기존값(R=0.85 채도 최대)은
-- 순수 빨강이라 밝기도 높아 낮에는 오히려 화사한 붉은 필터처럼 보였다.
-- R을 크게 낮추고 G/B와의 격차도 줄여서(고채도 빨강 -> 저채도 어두운 적회색)
-- "빛이 줄어든 위에 핏빛이 옅게 얹힌" 인상을 준다. 아래 PEAK 상향과 함께
-- 어두움 쪽에 무게를 싣는 구성이다.
local BLOOD_EXT = { 0.16, 0.09, 0.10, 0.78 }
local BLOOD_INT = { 0.10, 0.06, 0.07, 0.60 }

-- 혼합 최대치. 1.0 이면 자연광이 완전히 사라져 낮/밤 명암 자체가 없어진다.
-- 0.88 이면 자연광이 12% 만 남아 대낮에도 확 어두워진다(일식 컨셉의 핵심).
-- 기존 0.7(자연광 30% 잔존)은 밤은 몰라도 낮에는 어두움이 잘 안 느껴졌다.
local PEAK = 0.88

-- 안개/포화도저하 피크값. 조명의 PEAK 와 달리 "자연광을 남긴다"는 개념이 없어서
-- 그대로 목표치다. 자연값이 이미 피크보다 높으면 낮추지 않는다(아래 clamp 참조).
local FOG_PEAK   = 0.35
local DESAT_PEAK = 1.0

-- 어두움(DAYLIGHT_STRENGTH) 바닥값. 위 둘과 달리 "낮을수록 어두움"이라 방향이
-- 반대다 -- 자연값이 이미 이보다 어두우면(깊은 밤 등) 더 밝히지 않는다
-- (아래 darkTarget 참조). 0.12 면 대낮에도 daylight_strength 가 12% 까지
-- 떨어져 실내외 모두 확 어두워진다. 0 으로 두면 완전 암전이라 시야 자체가
-- 안 나올 수 있어 최소한을 남겼다.
local DARK_PEAK = 0.12

-- UI 틴트 텍스쳐 알파 피크값. 화면 전체를 덮는 연출이라 조명/안개보다 훨씬
-- 낮게 잡는다 -- 1.0 이면 텍스쳐가 완전 불투명해져 그 아래 게임 화면이 안 보인다.
--
-- media/ui/BloodMoon_Tint.png 는 좌상단 코너에만 알파가 몰린 그라데이션이었던
-- 걸 화면 네 변 전부에서 번지는 대칭 비네트로 다시 만들었다(중심 35% 반경은
-- 완전 투명 유지, 그 밖은 가장자리로 갈수록 텍스쳐 알파가 최대 255 까지
-- 올라간다). 기존 에셋은 텍스쳐 자체의 알파가 화면 대부분에서 0에 가까워서,
-- 이 상수를 아무리 올려도 코너 밖은 안 보였다 -- "핏빛이 잘 안 보인다"는
-- 증상의 절반은 이 상수가 아니라 에셋의 커버리지 문제였다.
-- 0.35 -> 0.45 로 올린 건 나머지 절반(단순히 낮았던 알파) 보정이다.
local TINT_PEAK = 0.45

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

-- 안개/포화도/어두움 채널. 조명과 구조가 같아 상태만 채널별로 들고 간다.
--   base    : 추적 중인 자연값
--   written : 마지막으로 써넣은 값 (MP 경로의 base 추적용)
--   dir     : "up" 이면 자연값 -> peak 로 상승(안개/포화도), "down" 이면
--             자연값 -> peak 로 하강(어두움). fxTarget/darkTarget 선택에 쓴다.
local _fx = {
    { id = FLOAT_FOG_INTENSITY,     peak = FOG_PEAK,   base = nil, written = nil, dir = "up" },
    { id = FLOAT_DESATURATION,      peak = DESAT_PEAK, base = nil, written = nil, dir = "up" },
    { id = FLOAT_DAYLIGHT_STRENGTH, peak = DARK_PEAK,  base = nil, written = nil, dir = "down" },
}

-- UI 틴트 텍스쳐용 알파. ClimateManager 채널이 아니라 클라이언트가 직접 그리는
-- 값이라 base/written 추적이 필요 없다 -- 자연값이라는 개념 자체가 없다.
local _tintAlpha = 0

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
-- 관리하므로 건드리지 않는다 -- 어차피 매 프레임 덮어써지고, 실제로는 float
-- 정밀도 버그 때문에 늘 1.0 이라 우리가 쓴 색이 그대로 화면에 나온다
-- (파일 상단 "패킷 프레임 1프레임 점멸" 항목 참조).
--
-- finalValue 에도 같은 값을 써넣는다. 패킷이 온 프레임에는 calculate() 가
-- 우리보다 먼저 돌면서 finalValue 를 자연광으로 갈아엎어 놓기 때문에, override
-- 만 되돌려서는 그 프레임 렌더를 못 막는다. 이게 점멸의 원인이었다.
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

    -- 이번 프레임 렌더용. 다음 프레임 calculate() 가 어차피 재계산한다.
    writeBlend(cc:getFinalValue(), _base, t)
end

-- ── 안개 / 포화도 저하 ──────────────────────────────────────────────────────
-- 조명과 같은 곡선(k = 0~1)을 타고 자연값 -> peak 로 올라간다.
-- 자연값이 이미 peak 보다 크면(폭풍 안개 등) 낮추지 않는다 -- 이벤트가 켜졌다고
-- 폭풍 안개가 걷히면 그게 더 이상하다.
local function fxTarget(base, peak, k)
    local v = base + (peak - base) * k
    if v < base then return base end
    return v
end

-- 어두움(DAYLIGHT_STRENGTH) 전용. peak 가 자연값보다 낮은 게 정상이라 fxTarget
-- 과 반대 방향으로 clamp 한다 -- k 가 커질수록 값이 내려가야(더 어두워져야)
-- 한다. 자연값이 이미 peak 보다 어두우면(깊은 밤 등) 억지로 밝히지 않는다.
local function darkTarget(base, peak, k)
    local v = base + (peak - base) * k
    if v > base then return base end
    return v
end

local function fxCompute(dir, base, peak, k)
    if dir == "down" then return darkTarget(base, peak, k) end
    return fxTarget(base, peak, k)
end

local function climateFloat(id)
    local cm = getClimateManager()
    if not cm then return nil end
    return cm:getClimateFloat(id)
end

-- MP 클라: 색 채널과 완전히 같은 패턴이다. override 를 읽어 base 를 추적하고,
-- override + finalValue 양쪽에 써넣는다.
--
-- 안개는 finalValue 만 써서는 안 된다. 실제 안개 스프라이트는
-- updateFx() -> weatherFX.setFogIntensity(finalValue) 로 나가는데 이건
-- ClimateManager.update() 안에서 우리보다 먼저 돌기 때문에, override 를 써서
-- 다음 프레임 calculate() 를 거치게 해야 한 프레임 뒤에 반영된다.
local function applyFxMP(k)
    for i = 1, #_fx do
        local st = _fx[i]
        local cf = climateFloat(st.id)
        if cf then
            local cur = cf:getOverride()
            if st.written == nil or cur ~= st.written then
                st.base = cur
            end
            local target = fxCompute(st.dir, st.base, st.peak, k)
            cf:setOverride(target, cf:getOverrideInterpolate())
            st.written = cf:getOverride()
            cf:setFinalValue(target)
        end
    end
end

-- SP: internalValue 가 진짜 자연값이므로 base 추적이 필요 없다.
-- interpolate = 1 로 두면 finalValue = override 라 우리가 계산한 값이 그대로 간다.
--
-- 한계: 이벤트 중에는 바닐라 WeatherPeriod 가 거는 안개/포화도 override 를
-- 덮어쓴다(WeatherPeriod.java:948, 1117). 종료 시 override 를 끄면 다음 기후
-- 틱(인게임 1분 이내)에 WeatherPeriod 가 다시 걸어주므로 영구 손상은 없다.
local function applyFxSP(k)
    for i = 1, #_fx do
        local cf = climateFloat(_fx[i].id)
        if cf then
            if k <= 0 then
                cf:setEnableOverride(false)
            else
                cf:setOverride(fxCompute(_fx[i].dir, cf:getInternalValue(), _fx[i].peak, k), 1.0)
            end
        end
    end
end

local function clearFx()
    for i = 1, #_fx do
        local st = _fx[i]
        local cf = climateFloat(st.id)
        if cf then
            if _mode == "mp" then
                -- 색 채널과 같은 이유로 끄지 않고 자연값을 그대로 써넣는다.
                if st.base then
                    cf:setOverride(st.base, cf:getOverrideInterpolate())
                    cf:setFinalValue(st.base)
                end
            else
                pcall(function() cf:setEnableOverride(false) end)
            end
        end
        st.base    = nil
        st.written = nil
    end
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
            if _base then
                writeBlend(cc:getOverride(), _base, 0)
                writeBlend(cc:getFinalValue(), _base, 0)
            end
        else
            pcall(function() cc:setEnableOverride(false) end)
            pcall(function() cc:setEnableAdmin(false) end)
        end
    end
    clearFx()
    _appliedT  = nil
    _written   = nil
    _base      = nil
    _intensity = 0
    _tintAlpha = 0
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

-- 안개/포화도용 계수. 조명과 달리 "자연광을 얼마나 남길지"의 개념이 없어서
-- PEAK 를 곱하지 않는다. 서버가 조명 세기를 낮추면 같이 낮아지는 게 맞으므로
-- 샌드박스 스케일은 공유한다.
local function toFx(p)
    return p * (SandboxVars.PongDu.BloodMoon_LightStrength / 100)
end

-- UI 틴트용 계수. 조명과 같은 스케일(LightStrength)을 공유하되 자체 피크를 곱한다.
local function toTint(p)
    return p * TINT_PEAK * (SandboxVars.PongDu.BloodMoon_LightStrength / 100)
end

local function applyNow()
    local cc = globalLightColor()
    if not cc then return end
    local t = toBlend(_intensity)
    local k = toFx(_intensity)
    if _mode == "mp" then
        applyMP(cc, t)
        applyFxMP(k)
    else
        applySP(cc, t)
        applyFxSP(k)
    end
    -- UI 틴트는 ClimateManager 채널이 아니라 값 하나만 있으면 되므로
    -- MP/SP 분기 없이 여기서 바로 계산한다.
    _tintAlpha = toTint(_intensity)
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
        .. " peakBlend=" .. tostring(toBlend(1))
        .. " peakFog=" .. tostring(fxTarget(0, FOG_PEAK, toFx(1)))
        .. " peakDesat=" .. tostring(fxTarget(0, DESAT_PEAK, toFx(1)))
        -- 어두움은 자연값(base)이 시각마다 달라 fxTarget 처럼 0 기준 예시값을
        -- 못 낸다. DARK_PEAK 는 "자연값이 이보다 밝을 때 내려가는 바닥"이므로
        -- 그대로 로그에 남긴다 -- 실제 적용치는 자연값에 따라 다를 수 있다.
        .. " peakDarkFloor=" .. tostring(DARK_PEAK)
        .. " peakTint=" .. tostring(toTint(1)))

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

-- UI 틴트 텍스쳐 알파. client/features/bloodmoon.lua 의 BloodMoonTint 패널이
-- 매 렌더 프레임 이 값을 읽어 drawTextureScaled 의 알파로 그대로 넘긴다.
function _m.getTintAlpha()
    return _tintAlpha
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
