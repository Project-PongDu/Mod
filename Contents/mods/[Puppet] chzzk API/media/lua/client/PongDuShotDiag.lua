-- ═══════════════════════════════════════════════════════════════════════════
--  플레이어 사격 진단 (탄도학 모드 사용 시 "총구화염은 나오는데 탄이 안 줄어듦")
--
--  B41 총 한 발의 흐름 (Arsenal(26) 기준):
--   ① ISReloadWeaponAction.attackHook: 발사음 + 총구화염 + DoAttack
--   ② SwipeStatePlayer 진입 -> OnWeaponSwing                              -> swings
--   ③ 사격 애니 이벤트 AttackCollisionCheck -> OnWeaponSwingHitPoint      -> hitpoints
--      여기서 Arsenal onShoot 가 탄을 1발 빼고, Improved Projectile 이 투사체를 만든다
--  사격하는 동안 WINDOW_MS 마다 한 줄씩 남긴다. 화염만 나고 안 나간 발이 있으면
--  swings 가 hitpoints 보다 크고 줄 끝에 LOST 가 붙는다 (③ 사격 애니 이벤트가 안 옴).
--  탄 걸림·미장전 상태의 헛방아(RangedWeaponEmpty)는 원래 ③이 없으므로 dry 로 따로 센다.
--  fps/좀비 수/발사 모드를 같이 적는다. 진단용이라 사격 동작은 아무것도 바꾸지 않는다.
--  (예전엔 ① 을 세려고 attack 훅을 감쌌는데, 밀치기/사격 분기가 도는 경로라 뺐다.
--   손실 판정은 ②>③ 만으로 충분하다.)
-- ═══════════════════════════════════════════════════════════════════════════
local WINDOW_MS = 3000

local st = { at = 0, sw = 0, dry = 0, hp = 0, ammo0 = nil, weapon = nil }

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
    if w and (st.sw > 0 or st.dry > 0) then
        local zl = getCell() and getCell():getZombieList()
        local ammo1 = w:getCurrentAmmoCount()
        print(string.format("[PongDu][ShotDiag] %ds swings=%d hitpoints=%d dry=%d ammo %s->%s fps=%d zombies=%d weapon=%s mode=%s%s",
            math.floor(WINDOW_MS / 1000), st.sw, st.hp, st.dry, tostring(st.ammo0), tostring(ammo1),
            math.floor(getAverageFPS() + 0.5), zl and zl:size() or -1,
            tostring(w:getFullType()), tostring(w:getFireMode()), st.sw > st.hp and " LOST" or ""))
    end
    st.at, st.sw, st.dry, st.hp, st.ammo0, st.weapon = 0, 0, 0, 0, nil, nil
end

Events.OnWeaponSwing.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    begin(weapon)
    if player:isRangedWeaponEmpty() then
        st.dry = st.dry + 1
    else
        st.sw = st.sw + 1
    end
end)

Events.OnWeaponSwingHitPoint.Add(function(player, weapon)
    if not localRanged(player, weapon) then return end
    begin(weapon)
    st.hp = st.hp + 1
end)

Events.OnTick.Add(function()
    if st.at > 0 and getTimestampMs() - st.at >= WINDOW_MS then flush() end
end)
