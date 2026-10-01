-- ═══════════════════════════════════════════════════════════════════════════
--  저FPS 연사속도 보정 사격 (좀비가 많아 FPS 가 떨어지면 연사 총기 발수가 줄어드는 문제)
--
--  원인 (B41 엔진):
--   총 한 발마다 ranged 상태에 들어갔다 나온다. 사격 애니가 끝나면 다음 프레임에 상태를
--   빠져나가고(ActiveAnimFinishing), 그 프레임의 입력 처리는 이탈보다 먼저 돌아 아직
--   공격 중이라 막히므로 다음 발 입력은 그다음 프레임에 들어간다.
--   한 발 주기 = (애니가 끝나는 데 걸린 프레임 수 + 1) 프레임, 최소 2 프레임.
--     XM214 (x15, 한 발 44ms) : 60fps 4프레임 = 15발/초, 17fps 2프레임 = 8.5발/초
--   액션 상태 전이는 프레임당 한 번(루트 전이 -> 하위 상태 제거 순)이라 Lua 에서
--   같은 프레임에 재진입시킬 방법이 없다.
--
--  보정:
--   연사(Auto 계열 / Rotary) 중 "60fps 에서였다면 나갔을 발수"보다 실제 발수가 모자라면
--   스윙 사이 프레임에 모자란 만큼 추가 발사한다. 시간은 애니 시간(getTimeDelta 누적)으로 잰다.
--   기준 간격(총·발사모드·자세별):
--    1) 실측: FPS 가 REF_FPS 이상일 때 잰 스윙 간격 중앙값 (플레이어 modData 에 저장)
--    2) 모델: 실측이 없으면 실제 발이 나갈 때 재생 중인 사격 클립 트랙을 읽어 계산한다.
--       애니 시간 D = (클립 길이 - 조기 전환 페이드아웃 시간) / 재생 배율
--       반동 R    = 스윙 시점 플레이어 RecoilDelay (60fps 에서 프레임당 0.5 감소)
--       기준 간격 = max(ceil(D*60)+1, ceil(R/0.5)) / 60 초   (위 엔진 주기 공식을 60fps 로 계산)
--       대규모 좀비로 처음부터 고FPS 를 못 보는 상황에서도 바로 동작하게 하려는 것.
--       실측이 생기면 실측을 쓰고, 둘을 같이 로그에 남겨 모델을 검증할 수 있게 한다.
--   추가 발사는 실제 명중 시점과 같은 Lua 이벤트 OnWeaponSwingHitPoint 를 직접 발생시켜
--   Arsenal 탄 차감·약실·탄걸림(onShoot)과 Improved Projectile 투사체 생성이 실제 발과
--   똑같이 돌게 한다. 발사음·총구화염도 Arsenal attackHook 과 같은 조건으로 낸다.
--
--  하지 않는 것 / 한계:
--   - 단발·점사·볼트/펌프(isRackAfterShoot)·화염방사기·활·BB건은 대상 아님
--   - Improved Projectile 이 이 총을 처리 중일 때만 동작한다. 바닐라 히트 판정은 엔진
--     ConnectSwing 안에서만 일어나 Lua 로 재현할 수 없으므로, 탄도학 모드 없이 쏘면
--     탄만 줄고 피해가 없어서 보정하지 않는다
--   - 추가 발에는 엔진 ConnectSwing 이 없다: 지구력 소모·무기 내구도 감소·바닐라 경험치 없음
--   - 고FPS(COMP_FPS 이상)에서는 아무것도 하지 않는다 (바닐라 그대로)
--   - 모델은 60fps 기준이다. 144fps 등에서 실제로 더 빨리 쏘던 사람에게는 실측값이 생기기
--     전까지 그보다 약간 느린 기준이 쓰인다
--   - 사격 클립 이름은 PongDuRangedShotFix 가 애니셋을 고칠 때 모아 둔다(PongDuShotFix.shotClips)
--  샌드박스 PongDu.ShotComp 로 끈다.
-- ═══════════════════════════════════════════════════════════════════════════
PongDuShotComp = PongDuShotComp or {}
PongDuShotComp.firingExtra = false   -- 추가 발 이벤트 발생 중 표시 (PongDuShotDiag 가 구분용으로 읽음)

local LOG = "[PongDu][ShotComp] "
local REF_FPS = 55        -- 이 FPS 이상에서 잰 간격만 실측 기준값 표본으로 쓴다
local COMP_FPS = 50       -- 이 FPS 미만일 때만 보충한다
local MODEL_FPS = 60      -- 모델 기준 간격을 계산하는 FPS (B41 기본 FPS 상한)
local RECOIL_STEP = 0.5   -- 60fps 한 프레임에 줄어드는 RecoilDelay (0.625 * getMultiplier() 0.8)
local CONT_GAP = 0.35     -- 스윙 간격(애니 시간, 초)이 이보다 길면 연사가 끊긴 것으로 본다
local SAMPLE_N = 15       -- 실측 기준 간격 표본 개수 (중앙값)
local MIN_SAMPLES = 5     -- 이만큼 모여야 새로 잰 기준값을 쓴다
local MAX_PER_TICK = 2    -- 한 프레임에 추가로 쏘는 최대 발수
local MAX_DEFICIT = 3     -- 긴 끊김 뒤 몰아쏘기 방지: 밀린 발수 상한
local MODDATA_KEY = "PongDuShotCompRef"

local AUTO_MODES = {
    ["Auto"] = true, ["Auto[H]"] = true, ["Auto[L]"] = true,
    ["[6]Rotary"] = true, ["[3]Rotary"] = true,
}

local clk = 0             -- 애니 시간 누적(초). 엔진 애니와 같은 dt(getTimeDelta, 프레임당 상한 83ms)
local refs = {}           -- key -> { s = {표본}, i = 다음 기록 위치, med = 실측 중앙값 }
local models = {}         -- key -> { anim = 사격 애니 실시간(초), recoil = RecoilDelay 추정 }
local burst = nil         -- 진행 중인 연사
local logged = {}         -- 한 번만 남길 로그

local function logOnce(tag, msg)
    if logged[tag] then return end
    logged[tag] = true
    print(LOG .. msg)
end

local function enabled()
    return SandboxVars.PongDu.ShotComp == true
end

local function isLocal0(player)
    return player ~= nil and instanceof(player, "IsoPlayer") and player:isLocalPlayer() and player:getPlayerNum() == 0
end

-- 보정 대상 총인가 (연사 모드, 재장전식 아님, Arsenal 특수 화기 제외)
local function eligible(weapon)
    if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isRanged() then return false end
    if not AUTO_MODES[tostring(weapon:getFireMode())] then return false end
    if weapon:isRackAfterShoot() then return false end
    if type(isFlamer) == "function" and isFlamer(weapon) then return false end
    if type(isBow) == "function" and isBow(weapon) then return false end
    if type(isBBGun) == "function" and isBBGun(weapon) then return false end
    return true
end

-- Improved Projectile 이 이 총의 투사체를 만들고 있는가 (_01_main.lua onShootWeapon 조건과 같음)
local function ippjReady(weapon)
    local ip = ImprovedProjectile
    return ip ~= nil and ip.isValid == true and ip.currInfo ~= nil
        and ip.currInfo["weaponName"] == weapon:getFullType()
        and ip.blockVehicleShoot ~= true
end

local function keyOf(player, weapon)
    local stance = "stand"
    if player:getVariableBoolean("isCrawling") then
        stance = "crawl"
    elseif player:getVariableBoolean("IsCrouchAim") then
        stance = "crouch"
    end
    return weapon:getFullType() .. "|" .. tostring(weapon:getFireMode()) .. "|" .. stance
end

local function savedRefs(player)
    local md = player:getModData()
    if type(md[MODDATA_KEY]) ~= "table" then md[MODDATA_KEY] = {} end
    return md[MODDATA_KEY]
end

-- ── 모델 기준 간격 ─────────────────────────────────────────────────────────

local function num(v)
    return tonumber(tostring(v))
end

-- 지금 재생 중인 사격 클립 트랙에서 "사격 상태를 빠져나가기까지의 실제 시간"(초)을 읽는다.
-- 이전 발의 같은 클립이 페이드아웃 중일 수 있고 2D 블렌드는 트랙이 여럿이라, 가장 긴 값을 쓴다
-- (짧게 잡으면 바닐라보다 빨리 쏘게 되므로 보수적으로).
local function shotAnimTime(player)
    local fx = PongDuShotFix
    if not fx or not fx.fieldVal or not fx.shotClips then return nil, "PongDuRangedShotFix not loaded" end
    local fv = fx.fieldVal
    local ap = player:getAnimationPlayer()
    local mt = ap and fv(ap, "aplayer", "m_multiTrack")
    local tracks = mt and fv(mt, "multitrack", "m_tracks")
    if not tracks then return nil, "animation tracks unreadable" end
    local best, seen = nil, {}
    for i = 0, tracks:size() - 1 do
        local tr = tracks:get(i)
        local name = tostring(fv(tr, "track", "name"))
        seen[#seen + 1] = name
        if fx.shotClips[string.lower(name)] then
            local clip = fv(tr, "track", "CurrentClip")
            local dur = clip and num(fv(clip, "clip", "Duration"))
            local spd = num(fv(tr, "track", "SpeedDelta"))
            if dur and spd and spd > 0 then
                local cut = 0
                if tostring(fv(tr, "track", "triggerOnNonLoopedAnimFadeOutEvent")) == "true" then
                    cut = num(fv(tr, "track", "earlyBlendOutTime")) or 0
                end
                local d = (dur - cut) / spd
                if d > 0 and (not best or d > best) then best = d end
            end
        end
    end
    if not best then return nil, "no shot clip track playing [" .. table.concat(seen, ",") .. "]" end
    return best
end

-- 스윙 시점의 반동 대기값을 기록한다. 스윙 이벤트 전에 이번 프레임 감소분(0.625 * getMultiplier)이
-- 이미 빠졌으므로 되돌리면 공격 때 설정된 값이 나온다. 0 까지 빠졌으면 "감소분 이하"라는 것만
-- 알 수 있어 무기 값과 감소분 중 작은 쪽을 상한으로 두고, 상한들 중 가장 작은 것을 쓴다.
-- 정확한 값을 한 번이라도 얻으면 그쪽을 쓴다.
local function noteRecoil(player, weapon, m)
    local step = 0.625 * getGameTime():getMultiplier()
    local r = player:getRecoilDelay()
    if r > 0 then
        m.recoilExact = r + step
    else
        local bound = math.min(math.max(weapon:getRecoilDelay(), 0), step)
        if not m.recoilBound or bound < m.recoilBound then m.recoilBound = bound end
    end
    m.recoil = m.recoilExact or m.recoilBound or 0
end

-- 모델 기준 간격(초), 애니 프레임 수, 반동 프레임 수 (60fps 기준)
local function modelOf(m)
    local animFrames = math.max(1, math.ceil(m.anim * MODEL_FPS - 1e-4)) + 1
    local recoilFrames = math.ceil((m.recoil or 0) / RECOIL_STEP - 1e-3)
    return math.max(animFrames, recoilFrames) / MODEL_FPS, animFrames, recoilFrames
end

local function logModel(key, m)
    local ref, af, rf = modelOf(m)
    local r = refs[key]
    print(string.format(LOG .. "model key=%s anim=%.3fs frames=%d recoil=%.2f frames=%d interval=%.3fs (%.1f/s)%s",
        key, m.anim, af, m.recoil or 0, rf, ref, 1 / ref,
        (r and r.med) and string.format(" measured=%.3fs", r.med) or ""))
end

-- ── 실측 기준 간격 ─────────────────────────────────────────────────────────

local function measuredOf(player, key)
    local r = refs[key]
    if r and r.med then return r.med end
    if r and r.noSaved then return nil end
    local saved = tonumber(savedRefs(player)[key])
    refs[key] = r or { s = {}, i = 1 }
    if saved and saved > 0 then
        refs[key].med = saved
        print(string.format(LOG .. "ref loaded key=%s interval=%.3fs (%.1f/s) from player modData", key, saved, 1 / saved))
        return saved
    end
    refs[key].noSaved = true
    return nil
end

-- 기준 간격과 출처 (실측 우선, 없으면 모델)
local function refOf(player, key)
    local med = measuredOf(player, key)
    if med then return med, "measured" end
    local m = models[key]
    if m and m.anim then
        local ref = modelOf(m)
        return ref, "model"
    end
    return nil, nil
end

local function addSample(player, key, iv)
    local r = refs[key]
    if not r then
        r = { s = {}, i = 1 }
        refs[key] = r
    end
    r.s[r.i] = iv
    r.i = r.i % SAMPLE_N + 1
    if #r.s < MIN_SAMPLES then return end
    local tmp = {}
    for k = 1, #r.s do tmp[k] = r.s[k] end
    table.sort(tmp)
    local med = tmp[math.floor((#tmp + 1) / 2)]
    if not r.med or math.abs(med - r.med) > r.med * 0.05 then
        local m = models[key]
        local mref = m and m.anim and modelOf(m)
        print(string.format(LOG .. "ref key=%s interval=%.3fs (%.1f/s) samples=%d%s", key, med, 1 / med, #tmp,
            mref and string.format(" model=%.3fs", mref) or ""))
        savedRefs(player)[key] = med
    end
    r.med = med
end

-- ── 연사 추적 / 보정 ───────────────────────────────────────────────────────

local function endBurst(reason)
    local b = burst
    burst = nil
    if b and b.extras > 0 then
        print(string.format(LOG .. "burst key=%s real=%d extra=%d dur=%.2fs ref=%.3fs(%s) fps=%d end=%s",
            b.key, b.shots - b.extras, b.extras, b.last - b.t0, b.ref or -1, tostring(b.src),
            math.floor(getAverageFPS() + 0.5), reason))
    end
end

-- 기준 간격을 다시 읽고 이번 연사를 보정할지 정한다 (스윙마다, 그리고 모델이 처음 생겼을 때)
local function evalComp(player, b)
    local ref, src = refOf(player, b.key)
    b.ref, b.src = ref, src
    if b.lastIv <= 0 then b.lastIv = ref or 0 end
    b.comp = false
    if getAverageFPS() < COMP_FPS and enabled() then
        if not ref then
            -- 아직 기준이 없다: 첫 발 명중 시점에 사격 애니를 읽으면 다시 평가한다
            -- (못 읽으면 그쪽에서 이유를 로그로 남긴다)
        elseif not ippjReady(b.weapon) then
            logOnce("noippj|" .. b.key, "Improved Projectile not handling key=" .. b.key .. ", no compensation")
        else
            b.comp = true
        end
    end
    if not b.comp and ref then
        -- 보정하지 않는 동안은 기준 시각을 실제 발수에 맞춰 밀린 발수를 0 으로 유지한다
        b.t0 = b.last - (b.shots - 1) * ref
    end
end

-- 추가 1발. 실제 명중 시점과 같은 Lua 이벤트를 발생시킨다.
local function fireExtra(player, weapon)
    if not ISReloadWeaponAction or not ISReloadWeaponAction.canShoot(weapon) then return false end
    if not ippjReady(weapon) then return false end
    PongDuShotComp.firingExtra = true
    local ok, err = pcall(function() triggerEvent("OnWeaponSwingHitPoint", player, weapon) end)
    PongDuShotComp.firingExtra = false
    if not ok then
        print(LOG .. "extra shot failed: " .. tostring(err))
        return false
    end
    local snd = weapon:getSwingSound()
    if snd and snd ~= "" then player:playSound(snd) end
    if not (type(isSuppressed) == "function" and isSuppressed(weapon)) then
        player:startMuzzleFlash()
    end
    return true
end

-- 실제 스윙(②). 연사 간격을 재고 반동값을 기록하고 보정 여부를 정한다.
Events.OnWeaponSwing.Add(function(player, weapon)
    if not isLocal0(player) then return end
    if not weapon or not instanceof(weapon, "HandWeapon") or not weapon:isRanged()
        or player:isRangedWeaponEmpty() or not eligible(weapon) then
        -- 밀치기(맨손)·헛방아·대상 아닌 총은 연사를 끊는다
        if burst then endBurst("other swing") end
        return
    end

    local key = keyOf(player, weapon)
    local fps = getAverageFPS()

    local m = models[key]
    if not m then
        m = {}
        models[key] = m
    end
    local oldRef = m.anim and modelOf(m)
    noteRecoil(player, weapon, m)
    if oldRef then
        local newRef = modelOf(m)
        if newRef ~= oldRef then logModel(key, m) end
    end

    local b = burst
    if b and b.key == key and b.weapon == weapon and clk - b.last <= CONT_GAP then
        local iv = clk - b.last
        if fps >= REF_FPS and iv > 0 then addSample(player, key, iv) end
        b.lastIv = iv
        b.last = clk
        b.shots = b.shots + 1
    else
        if b then endBurst("new burst") end
        b = { key = key, weapon = weapon, t0 = clk, last = clk, lastIv = 0, shots = 1, extras = 0, read = false }
        burst = b
    end
    evalComp(player, b)
end)

-- 실제 명중 시점(③). 연사마다 첫 발에서 사격 애니를 읽어 모델 기준 간격을 갱신한다.
Events.OnWeaponSwingHitPoint.Add(function(player, weapon)
    if PongDuShotComp.firingExtra or not isLocal0(player) or not eligible(weapon) then return end
    local b = burst
    if not b or b.read or b.weapon ~= weapon then return end
    b.read = true
    local key = b.key
    local ok, anim, why = pcall(shotAnimTime, player)
    if not ok then
        logOnce("animerr|" .. key, "shot animation read failed for key=" .. key .. ": " .. tostring(anim))
        return
    end
    if not anim then
        logOnce("noanim|" .. key, "no model cadence for key=" .. key .. ": " .. tostring(why))
        return
    end
    local m = models[key]
    if not m.anim or math.abs(anim - m.anim) > m.anim * 0.02 then
        m.anim = anim
        logModel(key, m)
    end
    evalComp(player, b)
end)

-- 매 프레임: 시계를 진행하고, 보정 중이면 모자란 발수만큼 쏜다.
Events.OnPlayerUpdate.Add(function(player)
    if not isLocal0(player) then return end
    local dt = getGameTime():getTimeDelta()
    clk = clk + dt
    local b = burst
    if not b then return end
    if player:isDead() or player:getPrimaryHandItem() ~= b.weapon or not player:isAiming() or player:isDoShove() then
        endBurst("cancel")
        return
    end
    if clk - b.last > math.max(CONT_GAP, b.lastIv * 1.5) then
        endBurst("release")
        return
    end
    if not b.comp then return end

    -- 발사 시각이 이번 프레임에 가장 가까운 발까지 쏜다(반 프레임 앞당김). 그래야 추가 발이
    -- 실제 스윙 프레임에 몰리지 않고 스윙 사이 프레임에 들어간다.
    -- 다음 실제 스윙 예상 시각을 넘어서는 쏘지 않는다 (방아쇠를 놓으면 최대 한 간격 분량만 더 나감).
    local tcap = math.min(clk + dt * 0.5, b.last + b.lastIv)
    local due = math.floor((tcap - b.t0) / b.ref + 1e-6) + 1
    local owed = due - b.shots
    if owed > MAX_DEFICIT then
        b.shots = due - MAX_DEFICIT
        owed = MAX_DEFICIT
    end
    for _ = 1, math.min(owed, MAX_PER_TICK) do
        if not fireExtra(player, b.weapon) then
            b.comp = false
            break
        end
        b.shots = b.shots + 1
        b.extras = b.extras + 1
    end
end)

print(LOG .. "loaded (measured ref>=" .. REF_FPS .. "fps or " .. MODEL_FPS .. "fps animation model, compensate<" .. COMP_FPS .. "fps)")
