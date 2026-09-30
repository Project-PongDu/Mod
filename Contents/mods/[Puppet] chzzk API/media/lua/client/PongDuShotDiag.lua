-- ═══════════════════════════════════════════════════════════════════════════
--  플레이어 사격 진단 (탄도학 모드 사용 시 "총구화염은 나오는데 탄이 안 줄어듦")
--
--  B41 총 한 발의 흐름 (Arsenal(26) 기준):
--   ① ISReloadWeaponAction.attackHook: 발사음 + 총구화염 + DoAttack      -> attempts
--   ② SwipeStatePlayer 진입 -> OnWeaponSwing                              -> swings
--   ③ 사격 애니 이벤트 AttackCollisionCheck -> OnWeaponSwingHitPoint      -> hitpoints
--      여기서 Arsenal onShoot 가 탄을 1발 빼고, Improved Projectile 이 투사체를 만든다
--  사격하는 동안 WINDOW_MS 마다 한 줄씩 남긴다. 화염만 나고 안 나간 발이 있으면
--  attempts 또는 swings 가 hitpoints 보다 크고 줄 끝에 LOST 가 붙는다.
--   attempts > swings = hitpoints : ①에서 DoAttack 이 상태 진입을 못 함
--   attempts = swings > hitpoints : ③ 사격 애니 이벤트가 안 옴 (애니/프레임 문제)
--  fps/좀비 수/발사 모드를 같이 적는다. 탄도학 모드를 끈 상태에서도 LOST 가 나오면
--  탄도학 모드 문제가 아니다. 진단용이라 사격 동작은 아무것도 바꾸지 않는다
--  (① 은 기존 attack 훅을 감싸 세기만 하고 그대로 넘긴다).
-- ═══════════════════════════════════════════════════════════════════════════
local WINDOW_MS = 3000

local st = { at = 0, att = 0, sw = 0, hp = 0, ammo0 = nil, weapon = nil }

local function localRanged(player, weapon)
    return player ~= nil and weapon ~= nil and instanceof(player, "IsoPlayer") and player:isLocalPlayer()
        and instanceof(weapon, "HandWeapon") and weapon:isRanged()
end

local function begin(weapon)
    if st.at == 0 then
        st.at = getTimestampMs()
        st.ammo0 = weapon:getCurrentAmmoCount()
        st.weapon = weapon
    end
end

local function flush()
    local w = st.weapon
    if w and (st.att > 0 or st.sw > 0) then
        local zl = getCell() and getCell():getZombieList()
        local ammo1 = w:getCurrentAmmoCount()
        local lost = (st.att > st.hp) or (st.sw > st.hp)
        print(string.format("[PongDu][ShotDiag] %ds attempts=%d swings=%d hitpoints=%d ammo %s->%s fps=%d zombies=%d weapon=%s mode=%s%s",
            math.floor(WINDOW_MS / 1000), st.att, st.sw, st.hp, tostring(st.ammo0), tostring(ammo1),
            math.floor(getAverageFPS() + 0.5), zl and zl:size() or -1,
            tostring(w:getFullType()), tostring(w:getFireMode()), lost and " LOST" or ""))
    end
    st.at, st.att, st.sw, st.hp, st.ammo0, st.weapon = 0, 0, 0, 0, nil, nil
end

Events.OnWeaponSwing.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    begin(weapon)
    st.sw = st.sw + 1
end)

Events.OnWeaponSwingHitPoint.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    begin(weapon)
    st.hp = st.hp + 1
end)

Events.OnTick.Add(function()
    if st.at > 0 and getTimestampMs() - st.at >= WINDOW_MS then flush() end
end)

-- ① 를 세기 위해 attack 훅을 감싼다. Improved Projectile 도 같은 방식으로 감싸므로
-- (ImprovedProjectile_01_main.lua 끝) 모든 Lua 로드가 끝난 OnGameStart 에서 현재
-- 등록된 함수를 떼고 감싼 함수를 다시 붙인다. 세는 부분은 pcall 로 격리.
local attackWrapped = false
local function countAttempt(character, weapon)
    if not localRanged(character, weapon) then return end
    if character:isDoShove() or character:isAttackStarted() then return end
    if not ISReloadWeaponAction.canShoot(weapon) then return end
    begin(weapon)
    st.att = st.att + 1
end

Events.OnGameStart.Add(function()
    if attackWrapped or not ISReloadWeaponAction or type(ISReloadWeaponAction.attackHook) ~= "function" then return end
    attackWrapped = true
    local orig = ISReloadWeaponAction.attackHook
    Hook.Attack.Remove(orig)
    ISReloadWeaponAction.attackHook = function(character, chargeDelta, weapon, ...)
        pcall(countAttempt, character, weapon)
        return orig(character, chargeDelta, weapon, ...)
    end
    Hook.Attack.Add(ISReloadWeaponAction.attackHook)
    print("[PongDu][ShotDiag] attack hook wrapped for shot counting")
end)
