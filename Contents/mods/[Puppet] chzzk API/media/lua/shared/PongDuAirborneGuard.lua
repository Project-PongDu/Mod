-- ═══════════════════════════════════════════════════════════════════════════
--  공수부대원 플레이어 피격 무효화 (fire_support/airborne)
--
--  플레이어는 공수부대원을 공격할 수 없다. 공격 동작 자체는 막을 수 없으므로
--  맞는 순간의 피해를 없앤다:
--   IsoZombie.Hit()은 OnHitZombie 를 먼저 발화한 뒤 IsoGameCharacter.Hit()으로
--   넘어가고, 거기서 m_avoidDamage 가 서 있으면 피해/경직/넉다운을 전부 건너뛰고
--   0 을 반환하며 플래그를 되돌린다(IsoGameCharacter.java 5319, 1회용).
--   -> OnHitZombie 에서 setAvoidDamage(true) 를 세우면 그 1타가 통째로 무효가 된다.
--  밀치기(shove)도 같은 Hit 경로라 함께 막힌다.
--
--  shared 에 두는 이유: 피격 처리는 공격자 클라(로컬 판정), 서버(패킷 처리),
--  대원 소유 클라(패킷 수신) 각각에서 IsoZombie.Hit 이 돈다. client 폴더는 전용
--  서버에서 로드되지 않으므로 서버 쪽 처리를 놓친다.
--
--  (Hook.WeaponHitCharacter 는 쓰지 않는다: LuaHookManager 는 콜백이 하나라도
--   등록돼 있으면 반환값과 무관하게 true 를 돌려줘 모든 무기 피격이 사라진다.)
--  차량 충돌은 다른 경로(VehicleHitZombiePacket)라 막지 않는다.
-- ═══════════════════════════════════════════════════════════════════════════

-- 이번 프레임에 onHitZombie 가 무효화한 대원 (OnWeaponHitCharacter 보정과 겹치지 않게)
local _voidedAt = {}   -- [zombie] = ms

local function onHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if not zombie or not attacker then return end
    if not instanceof(attacker, "IsoPlayer") then return end
    if not HitmanUtils or not HitmanUtils.IsAirborneTrooper(zombie) then return end
    zombie:setAvoidDamage(true)
    _voidedAt[zombie] = getTimestampMs()
end

Events.OnHitZombie.Add(onHitZombie)

-- ═══════════════════════════════════════════════════════════════════════════
--  Improved Projectile(탄도학 모드, id ImprovedProjectile) 대응
--
--  이 모드는 IsoZombie.Hit 을 거치지 않는다. 투사체가 맞으면
--  OnWeaponHitCharacter 를 발화한 직후 zombie:setHealth(getHealth() - 피해) 와
--  Kill() 을 직접 부른다(ImprovedProjectile_01_main.lua projectileOnTick,
--  폭발물은 _05_explosive.lua). 그래서 위의 OnHitZombie 무효화가 안 먹었다.
--   ① 총탄: client/ModPatches/ImprovedProjectile.lua 가 표적 탐색 전역 함수
--      IPPJcheckTarget 을 감싸 대원을 후보에서 뺀다(탄이 대원을 통과).
--   ② 폭발물 등 나머지: 표적 탐색이 로컬 함수라 감쌀 수 없다. OnWeaponHitCharacter
--      에서 피해만큼 체력을 먼저 올려 두면 바로 뒤의 차감과 상쇄된다(쏜 클라 기준).
--      바닐라 Hit 경로도 OnWeaponHitCharacter 를 발화하므로, 방금 onHitZombie 가
--      무효화한 타격은 보정하지 않는다(안 그러면 체력이 오른다).
-- ═══════════════════════════════════════════════════════════════════════════
local VOIDED_WINDOW_MS = 100

local function onWeaponHitCharacter(attacker, target, weapon, damage)
    if not attacker or not target then return end
    if not instanceof(attacker, "IsoPlayer") or not instanceof(target, "IsoZombie") then return end
    if not HitmanUtils or not HitmanUtils.IsAirborneTrooper(target) then return end
    local t = _voidedAt[target]
    if t then
        _voidedAt[target] = nil
        if getTimestampMs() - t <= VOIDED_WINDOW_MS then return end
    end
    local dmg = tonumber(damage) or 0
    if dmg <= 0 then return end
    target:setHealth(target:getHealth() + dmg)
    print(string.format("[PongDu][Airborne] player hit on trooper offset (%.2f) -- non-vanilla damage path", dmg))
end

Events.OnWeaponHitCharacter.Add(onWeaponHitCharacter)
