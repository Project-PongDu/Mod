-- ═══════════════════════════════════════════════════════════════════════════
--  플레이어 사격 진단 (탄도학 모드 사용 시 "총구화염은 나오는데 탄이 안 줄어듦")
--
--  B41 총 한 발의 흐름 (Arsenal(26) 기준):
--   ① ISReloadWeaponAction.attackHook: 발사음 + 총구화염 + DoAttack
--   ② SwipeStatePlayer 진입 -> OnWeaponSwing
--   ③ 사격 애니 이벤트 AttackCollisionCheck -> OnWeaponSwingHitPoint
--      여기서 Arsenal onShoot 가 탄을 1발 빼고, Improved Projectile 이 투사체를 만든다
--  화염은 나오는데 탄이 안 줄면 ③이 안 온 것이다. 이 파일은 ②와 ③을 세어
--  ②만 있고 ③이 빠진 발(= 화염만 나고 안 나간 발)이 있을 때만 1초 요약을 남긴다.
--  같이 적는 fps/좀비 수/발사 모드로 원인(프레임 저하, 고속 연사 애니 재사용 등)을
--  가른다. 탄도학 모드를 끈 상태에서도 lost 가 나오면 탄도학 모드 문제가 아니다.
--  진단용이라 동작은 아무것도 바꾸지 않는다.
-- ═══════════════════════════════════════════════════════════════════════════
local WINDOW_MS = 1000

local st = { at = 0, sw = 0, hp = 0, ammo0 = nil, weapon = nil }

local function localRanged(player, weapon)
    return player ~= nil and weapon ~= nil and instanceof(player, "IsoPlayer") and player:isLocalPlayer()
        and instanceof(weapon, "HandWeapon") and weapon:isRanged()
end

local function reset()
    st.at, st.sw, st.hp, st.ammo0, st.weapon = 0, 0, 0, nil, nil
end

local function flush()
    local w = st.weapon
    if st.sw > st.hp and w then
        local zl = getCell() and getCell():getZombieList()
        print(string.format("[PongDu][ShotDiag] swings=%d hitpoints=%d lost=%d ammo %s->%s fps=%d zombies=%d weapon=%s mode=%s",
            st.sw, st.hp, st.sw - st.hp, tostring(st.ammo0), tostring(w:getCurrentAmmoCount()),
            math.floor(getAverageFPS() + 0.5), zl and zl:size() or -1,
            tostring(w:getFullType()), tostring(w:getFireMode())))
    end
    reset()
end

Events.OnWeaponSwing.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    if st.at == 0 then
        st.at = getTimestampMs()
        st.ammo0 = weapon:getCurrentAmmoCount()
        st.weapon = weapon
    end
    st.sw = st.sw + 1
end)

Events.OnWeaponSwingHitPoint.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    if st.at == 0 then return end
    st.hp = st.hp + 1
end)

Events.OnTick.Add(function()
    if st.at > 0 and getTimestampMs() - st.at >= WINDOW_MS then flush() end
end)
