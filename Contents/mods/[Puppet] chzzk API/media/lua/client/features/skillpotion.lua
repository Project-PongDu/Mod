-- 세럼 계열 아이템(serum_*) OnEat 핸들러 모음.
--   serum_supreme          : "잭팟" — Passive 2종 + Sprinting 확정 만렙, 트레잇 전면 교체
--   serum_strength/fitness/sprinting/lightfoot/nimble/sneak : 미니 세럼 — 해당 스킬만 +2레벨
-- 원본: SecretZ_Core (OnEat_LabsTest15) — Passive/Agility 만렙 로직만 이식, XP 직접주입 대신
-- LevelPerk() 반복 호출 방식 사용 (원본은 AddXP(360000)라 Passive가 Lv9에서 멈추는 문제가 있었음).
--
-- LevelPerk()는 호출 1회당 정확히 +1레벨이며 이미 만렙이면 그냥 무시됨
-- (엔진 네이티브 메서드, Lua wrapper 없음 — pz41 vanilla 소스 확인됨).
local function addLevels(player, perk, levels)
    for i = 1, levels do
        player:LevelPerk(perk)
    end
end

local function grantUsedSerum(player)
    player:getInventory():AddItem("t3chzzkDonation.serum_used")
end

-- ── serum_supreme (잭팟) ──────────────────────────────────────────────────
function OnEat_serum_supreme(food, player, percent)
    -- Passive: Strength / Fitness 확정 만렙
    addLevels(player, Perks.Strength, 10)
    addLevels(player, Perks.Fitness, 10)

    -- Agility: Sprinting만 확정 만렙 (요청 스펙 — 다른 Agility 스킬은 건드리지 않음)
    addLevels(player, Perks.Sprinting, 10)

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

    grantUsedSerum(player)
    player:Say("Oh my...")   -- 원본 연출 유지
end

-- ── 미니 세럼 6종 (Passive 2 + Agility 4, 각 +2레벨) ─────────────────────────
function OnEat_serum_strength(food, player, percent)
    addLevels(player, Perks.Strength, 2)
    grantUsedSerum(player)
    player:Say("...!")
end

function OnEat_serum_fitness(food, player, percent)
    addLevels(player, Perks.Fitness, 2)
    grantUsedSerum(player)
    player:Say("...!")
end

function OnEat_serum_sprinting(food, player, percent)
    addLevels(player, Perks.Sprinting, 2)
    grantUsedSerum(player)
    player:Say("...!")
end

function OnEat_serum_lightfoot(food, player, percent)
    addLevels(player, Perks.Lightfoot, 2)
    grantUsedSerum(player)
    player:Say("...!")
end

function OnEat_serum_nimble(food, player, percent)
    addLevels(player, Perks.Nimble, 2)
    grantUsedSerum(player)
    player:Say("...!")
end

function OnEat_serum_sneak(food, player, percent)
    addLevels(player, Perks.Sneak, 2)
    grantUsedSerum(player)
    player:Say("...!")
end
