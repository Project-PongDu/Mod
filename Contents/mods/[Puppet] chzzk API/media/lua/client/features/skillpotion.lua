-- 강화혈청(Enhancement Serum).
--
-- 아이템은 14스킬 x 3등급 = 42종이 t3_rewards_items.txt 에 전부 정적으로
-- 정의돼 있다. 표시명(ItemName_*)과 툴팁(Tooltip_*)도 번역파일에 박혀 있어서
-- 세이브/네트워크 직렬화를 신경 쓸 필요가 없다.
--
-- 여기가 하는 일은 두 가지뿐이다:
--   1) roll()  - 샌드박스 옵션을 보고 어떤 혈청을 지급할지 추첨
--   2) OnEat_serum - 42종이 공유하는 단일 섭취 핸들러

local serum = {}

-- 등급.
--   levels : 상승 레벨 수
--   weight : 등급 추첨 가중치. 일반:희귀:특급 = 10:3:1
-- 순서가 곧 등급 서열이다. allowedGradeCount() 가 앞에서부터 n개를 잘라 쓴다.
serum.GRADES = {
    { id = "common", levels = 1, weight = 10 },
    { id = "rare",   levels = 2, weight = 3  },
    { id = "epic",   levels = 3, weight = 1  },
}

-- 대상 스킬 14종. id 는 Perks.FromString() 키이자 아이템 타입/번역/샌드박스
-- 옵션의 접미사다. 재장전(Reloading)은 의도적으로 제외했다.
serum.SKILLS = {
    "Fitness", "Strength",
    "Sprinting", "Lightfoot", "Nimble", "Sneak",
    "Axe", "Blunt", "SmallBlunt", "LongBlade", "SmallBlade", "Spear",
    "Maintenance", "Aiming",
}

-- 아이템 타입 -> 효과. OnEat 이 문자열 파싱 없이 바로 찾아 쓴다.
local EFFECT = {}
for _, grade in ipairs(serum.GRADES) do
    for _, perkId in ipairs(serum.SKILLS) do
        EFFECT["serum_" .. grade.id .. "_" .. perkId] = {
            perkId = perkId,
            levels = grade.levels,
        }
    end
end

-- 샌드박스 드롭박스 값 -> 획득 가능한 등급 수.
--   1: 일반+희귀+특급 -> 3 / 2: 일반+희귀 -> 2 / 3: 일반만 -> 1 / 4: 획득 불가 -> 0
-- SandboxVars 는 게임 로드 후 항상 채워지므로 fallback 을 두지 않는다.
local function allowedGradeCount(perkId)
    local v = SandboxVars.PongDu["Serum_" .. perkId]
    if v == 4 then return 0 end
    return 4 - v
end

-- 스킬 1/N 균등 추첨 -> 해당 스킬에 허용된 등급 안에서 가중 추첨.
-- 특급이 막혀 있으면 가중치 합이 13이 되어 자연스럽게 10:3 이 된다.
-- 반환: 아이템 타입 문자열 (모든 스킬이 획득 불가면 nil)
function serum.roll()
    local candidates = {}
    for _, perkId in ipairs(serum.SKILLS) do
        if allowedGradeCount(perkId) > 0 then
            table.insert(candidates, perkId)
        end
    end

    if #candidates == 0 then
        print("[PongDu] Serum roll aborted: every skill is disabled by sandbox")
        return nil
    end

    local perkId = candidates[ZombRand(#candidates) + 1]
    local maxGrade = allowedGradeCount(perkId)

    local total = 0
    for i = 1, maxGrade do
        total = total + serum.GRADES[i].weight
    end

    local roll = ZombRand(total)
    local acc = 0
    for i = 1, maxGrade do
        acc = acc + serum.GRADES[i].weight
        if roll < acc then
            print("[PongDu] Serum rolled: perk=" .. perkId .. ", grade=" .. serum.GRADES[i].id
                .. " (candidates=" .. #candidates .. ", maxGrade=" .. maxGrade
                .. ", roll=" .. roll .. "/" .. total .. ")")
            return "serum_" .. serum.GRADES[i].id .. "_" .. perkId
        end
    end

    -- 안전망. 정수 연산이라 위 루프에서 반드시 반환되지만 방어적으로 둔다.
    return "serum_" .. serum.GRADES[maxGrade].id .. "_" .. perkId
end

-- ── OnEat (42종 공용) ────────────────────────────────────────────────────
-- LevelPerk() 는 호출 1회당 정확히 +1레벨이며 이미 만렙이면 무시된다
-- (엔진 네이티브 메서드, Lua wrapper 없음 -- pz41 vanilla 소스 확인됨).
-- food:getType() 은 모듈 prefix 없는 타입명("serum_epic_Aiming")을 돌려준다.
function OnEat_serum(food, player, percent)
    local itemType = food:getType()
    local effect = EFFECT[itemType]

    if not effect then
        print("[PongDu] Serum consume FAILED: unknown item type=" .. tostring(itemType))
        return
    end

    local perk = Perks.FromString(effect.perkId)
    for i = 1, effect.levels do
        player:LevelPerk(perk)
    end

    print("[PongDu] Serum consumed: type=" .. itemType
        .. ", perk=" .. effect.perkId .. ", levels=+" .. effect.levels)
end

return serum
