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

local function onHitZombie(zombie, attacker, bodyPartType, handWeapon)
    if not zombie or not attacker then return end
    if not instanceof(attacker, "IsoPlayer") then return end
    if not HitmanUtils or not HitmanUtils.IsAirborneTrooper(zombie) then return end
    zombie:setAvoidDamage(true)
end

Events.OnHitZombie.Add(onHitZombie)
