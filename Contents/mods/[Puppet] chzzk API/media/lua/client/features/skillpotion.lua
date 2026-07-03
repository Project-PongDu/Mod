-- Serum Supreme (구 CMP V-SZ9000) : random_skill_potion 리워드의 "잭팟" 아이템.
-- 원본: SecretZ_Core (OnEat_LabsTest15) — 효과 로직은 그대로 이식,
-- 단 원본은 AddXP(360000)라 Passive(Str/Fit)는 Lv9에서 멈추는 문제가 있었음.
-- 여기서는 LevelPerk() 반복 호출로 3개 스킬 전부 100% 확정 만렙(10) 처리.
--
-- LevelPerk()는 호출 1회당 정확히 +1레벨이며 이미 만렙이면 그냥 무시됨
-- (엔진 네이티브 메서드, Lua wrapper 없음 — pz41 vanilla 소스 확인됨).
-- 그래서 시작 레벨이 몇이든 10번 호출하면 항상 만렙에 도달한다.
local function maxPerk(player, perk)
    for i = 1, 10 do
        player:LevelPerk(perk)
    end
end

function OnEat_serum_supreme(food, player, percent)
    -- Passive: Strength / Fitness 확정 만렙
    maxPerk(player, Perks.Strength)
    maxPerk(player, Perks.Fitness)

    -- Agility: Sprinting만 확정 만렙 (요청 스펙 — Sprinting 외 다른 Agility 스킬은 건드리지 않음)
    maxPerk(player, Perks.Sprinting)

    -- 나쁜 특성 싹 제거
    player:getTraits():remove("Weak")
    player:getTraits():remove("Asthmatic")
    player:getTraits():remove("SlowHealer")
    player:getTraits():remove("ProneToIllness")
    player:getTraits():remove("HighThirst")
    player:getTraits():remove("HeartyAppetite")
    player:getTraits():remove("Deaf")
    player:getTraits():remove("Thinskinned")
    player:getTraits():remove("NeedsMoreSleep")

    -- 좋은 특성 싹 추가
    if not player:HasTrait("LightEater") then
        player:getTraits():add("LightEater")
    end
    if not player:HasTrait("LowThirst") then
        player:getTraits():add("LowThirst")
    end
    if not player:HasTrait("Resilient") then
        player:getTraits():add("Resilient")
    end
    if not player:HasTrait("FastHealer") then
        player:getTraits():add("FastHealer")
    end
    if not player:HasTrait("Athletic") then
        player:getTraits():add("Athletic")
    end

    -- 사용 후 빈 세럼을 인벤토리에 남긴다.
    -- (원본 시크릿Z는 D 아이템을 루팅/랩머신 재료로만 쓰고 먹은 뒤엔 아무것도 안 남김 —
    --  ReplaceOnEat 류 필드도 미사용. 여기선 Lua에서 직접 지급하는 방식이 B41에서 가장 확실.)
    player:getInventory():AddItem("t3chzzkDonation.serum_used")

    player:Say("Oh my...")   -- 원본 연출 유지
end
