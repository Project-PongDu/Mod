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
--   연사(Auto 계열 / Rotary) 중 실제 스윙 간격을 애니 시간(getTimeDelta 누적)으로 잰다.
--   FPS 가 REF_FPS 이상일 때의 간격 중앙값을 그 총·발사모드·자세의 기준 간격으로 삼고
--   (플레이어 modData 에 저장해 다음 접속에도 씀), FPS 가 COMP_FPS 미만인 동안
--   "기준 간격대로 쐈다면 지금까지 나갔을 발수"보다 실제 발수가 모자라면
--   스윙 사이 프레임에 모자란 만큼 추가 발사한다.
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
--  샌드박스 PongDu.ShotComp 로 끈다.
-- ═══════════════════════════════════════════════════════════════════════════
PongDuShotComp = PongDuShotComp or {}
PongDuShotComp.firingExtra = false   -- 추가 발 이벤트 발생 중 표시 (PongDuShotDiag 가 구분용으로 읽음)

local LOG = "[PongDu][ShotComp] "
local REF_FPS = 55        -- 이 FPS 이상에서 잰 간격만 기준값 표본으로 쓴다
local COMP_FPS = 50       -- 이 FPS 미만일 때만 보충한다
local CONT_GAP = 0.35     -- 스윙 간격(애니 시간, 초)이 이보다 길면 연사가 끊긴 것으로 본다
local SAMPLE_N = 15       -- 기준 간격 표본 개수 (중앙값)
local MIN_SAMPLES = 5     -- 이만큼 모여야 새로 잰 기준값을 쓴다
local MAX_PER_TICK = 2    -- 한 프레임에 추가로 쏘는 최대 발수
local MAX_DEFICIT = 3     -- 긴 끊김 뒤 몰아쏘기 방지: 밀린 발수 상한
local MODDATA_KEY = "PongDuShotCompRef"

local AUTO_MODES = {
    ["Auto"] = true, ["Auto[H]"] = true, ["Auto[L]"] = true,
    ["[6]Rotary"] = true, ["[3]Rotary"] = true,
}

local clk = 0             -- 애니 시간 누적(초). 엔진 애니와 같은 dt(getTimeDelta, 프레임당 상한 83ms)
local refs = {}           -- key -> { s = {표본}, i = 다음 기록 위치, med = 중앙값 }
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

local function refOf(player, key)
    local r = refs[key]
    if r and r.med then return r.med end
    local saved = tonumber(savedRefs(player)[key])
    if saved and saved > 0 then
        refs[key] = refs[key] or { s = {}, i = 1 }
        refs[key].med = saved
        print(string.format(LOG .. "ref loaded key=%s interval=%.3fs (%.1f/s) from player modData", key, saved, 1 / saved))
        return saved
    end
    return nil
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
        print(string.format(LOG .. "ref key=%s interval=%.3fs (%.1f/s) samples=%d", key, med, 1 / med, #tmp))
        savedRefs(player)[key] = med
    end
    r.med = med
end

local function endBurst(reason)
    local b = burst
    burst = nil
    if b and b.extras > 0 then
        print(string.format(LOG .. "burst key=%s real=%d extra=%d dur=%.2fs ref=%.3fs fps=%d end=%s",
            b.key, b.shots - b.extras, b.extras, b.last - b.t0, b.ref or -1,
            math.floor(getAverageFPS() + 0.5), reason))
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

-- 실제 스윙(②). 연사 간격을 재고 보정 여부를 정한다.
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
    local b = burst
    if b and b.key == key and b.weapon == weapon and clk - b.last <= CONT_GAP then
        local iv = clk - b.last
        if fps >= REF_FPS and iv > 0 then addSample(player, key, iv) end
        b.lastIv = iv
        b.last = clk
        b.shots = b.shots + 1
    else
        if b then endBurst("new burst") end
        b = { key = key, weapon = weapon, t0 = clk, last = clk, lastIv = 0, shots = 1, extras = 0 }
        burst = b
    end

    b.ref = refOf(player, key)
    if b.lastIv <= 0 then b.lastIv = b.ref or 0 end
    b.comp = false
    if fps < COMP_FPS and enabled() then
        if not b.ref then
            logOnce("noref|" .. key, "no reference cadence yet for key=" .. key
                .. " (fire it once above " .. REF_FPS .. " fps), no compensation")
        elseif not ippjReady(weapon) then
            logOnce("noippj|" .. key, "Improved Projectile not handling key=" .. key .. ", no compensation")
        else
            b.comp = true
        end
    end
    if not b.comp and b.ref then
        -- 보정하지 않는 동안은 기준 시각을 실제 발수에 맞춰 밀린 발수를 0 으로 유지한다
        b.t0 = b.last - (b.shots - 1) * b.ref
    end
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

print(LOG .. "loaded (ref>=" .. REF_FPS .. "fps, compensate<" .. COMP_FPS .. "fps)")
