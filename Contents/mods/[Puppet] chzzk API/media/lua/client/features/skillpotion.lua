-- 강화혈청(Enhancement Serum).
--
-- 아이템 정의는 등급 3종(serum_common / serum_rare / serum_epic)뿐이고,
-- "어떤 스킬을 올리는가"는 지급 시점에 modData(t3SerumPerk)로 심는다.
-- 14스킬 x 3등급 = 42개 아이템을 정의하지 않기 위한 구조이며, 표시 이름과
-- 툴팁도 런타임에 조립한다.
--
-- [주의] InventoryItem.tooltip 필드는 세이브에 직렬화되지 않는다.
--        InventoryItem.save()는 name 만 기록하고 tooltip 은 건드리지 않으므로
--        재접속하면 툴팁이 사라진다. 그래서 ISToolTipInv:render 를 훅해
--        modData 기준으로 지연 복구한다(installTooltipHook 참조).

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

-- 대상 스킬 14종.
--   id  : Perks.FromString() 키이자 샌드박스 옵션/번역 키의 접미사
--   cat : 카테고리 (body=신체능력 / agility=운동능력 / combat=전투능력)
-- 재장전(Reloading)은 의도적으로 제외했다.
serum.SKILLS = {
    { id = "Fitness",     cat = "body"    },
    { id = "Strength",    cat = "body"    },
    { id = "Sprinting",   cat = "agility" },
    { id = "Lightfoot",   cat = "agility" },
    { id = "Nimble",      cat = "agility" },
    { id = "Sneak",       cat = "agility" },
    { id = "Axe",         cat = "combat"  },
    { id = "Blunt",       cat = "combat"  },
    { id = "SmallBlunt",  cat = "combat"  },
    { id = "LongBlade",   cat = "combat"  },
    { id = "SmallBlade",  cat = "combat"  },
    { id = "Spear",       cat = "combat"  },
    { id = "Maintenance", cat = "combat"  },
    { id = "Aiming",      cat = "combat"  },
}

local GRADE_BY_ID = {}
for _, g in ipairs(serum.GRADES) do
    GRADE_BY_ID[g.id] = g
end

local SKILL_BY_ID = {}
for _, s in ipairs(serum.SKILLS) do
    SKILL_BY_ID[s.id] = s
end

-- 샌드박스 드롭박스 값 -> 획득 가능한 등급 수.
--   1: 일반+희귀+특급 -> 3 / 2: 일반+희귀 -> 2 / 3: 일반만 -> 1 / 4: 획득 불가 -> 0
-- SandboxVars 는 게임 로드 후 항상 채워지므로 fallback 을 두지 않는다.
local function allowedGradeCount(skillId)
    local v = SandboxVars.PongDu["Serum_" .. skillId]
    if v == 4 then return 0 end
    return 4 - v
end

-- 스킬 1/N 균등 추첨 -> 해당 스킬에 허용된 등급 안에서 가중 추첨.
-- 특급이 막혀 있으면 가중치 합이 13이 되어 자연스럽게 10:3 이 된다.
-- 반환: skill, grade (모든 스킬이 획득 불가면 nil, nil)
function serum.roll()
    local candidates = {}
    for _, s in ipairs(serum.SKILLS) do
        if allowedGradeCount(s.id) > 0 then
            table.insert(candidates, s)
        end
    end

    if #candidates == 0 then
        print("[PongDu] Serum roll aborted: every skill is disabled by sandbox")
        return nil, nil
    end

    local skill = candidates[ZombRand(#candidates) + 1]
    local maxGrade = allowedGradeCount(skill.id)

    local total = 0
    for i = 1, maxGrade do
        total = total + serum.GRADES[i].weight
    end

    local roll = ZombRand(total)
    local acc = 0
    for i = 1, maxGrade do
        acc = acc + serum.GRADES[i].weight
        if roll < acc then
            print("[PongDu] Serum rolled: perk=" .. skill.id .. ", grade=" .. serum.GRADES[i].id
                .. " (candidates=" .. #candidates .. ", maxGrade=" .. maxGrade
                .. ", roll=" .. roll .. "/" .. total .. ")")
            return skill, serum.GRADES[i]
        end
    end

    -- 안전망. 위 루프에서 반드시 반환되지만 부동 없이 정수 연산이라 도달할 일은 없다.
    return skill, serum.GRADES[maxGrade]
end

-- 인벤토리 표시명 뒷부분. "{등급} {카테고리} 강화혈청 ({스킬명})"
-- 후원자 각인("{sender}'s ")은 rewardManager 의 giveSupply() 가 앞에 붙인다.
-- 스킬명은 바닐라 번역을 그대로 재사용한다(Perk:getName() -> IGUI_perks_*).
function serum.buildLabel(skill, grade)
    return getText("IGUI_serum_grade_" .. grade.id) .. " "
        .. getText("IGUI_serum_cat_" .. skill.cat)
        .. " (" .. Perks.FromString(skill.id):getName() .. ")"
end

local function tooltipKey(gradeId, perkId)
    return "Tooltip_serum_" .. gradeId .. "_" .. perkId
end

-- 지급 직후 아이템에 스킬/등급을 각인하고 툴팁을 붙인다.
function serum.stamp(item, skill, grade)
    local md = item:getModData()
    md.t3SerumPerk  = skill.id
    md.t3SerumGrade = grade.id
    item:setTooltip(tooltipKey(grade.id, skill.id))
    print("[PongDu] Serum stamped: perk=" .. skill.id .. ", grade=" .. grade.id)
end

-- ── OnEat ────────────────────────────────────────────────────────────────
-- LevelPerk() 는 호출 1회당 정확히 +1레벨이며 이미 만렙이면 무시된다
-- (엔진 네이티브 메서드, Lua wrapper 없음 -- pz41 vanilla 소스 확인됨).
local function consume(food, player, gradeId)
    local grade = GRADE_BY_ID[gradeId]
    local perkId = food:getModData().t3SerumPerk

    if not perkId or not SKILL_BY_ID[perkId] then
        print("[PongDu] Serum consume FAILED: bad or missing perk in modData (perk="
            .. tostring(perkId) .. ", grade=" .. tostring(gradeId) .. ")")
        return
    end

    local perk = Perks.FromString(perkId)
    for i = 1, grade.levels do
        player:LevelPerk(perk)
    end

    print("[PongDu] Serum consumed: perk=" .. perkId .. ", grade=" .. gradeId
        .. ", levels=+" .. grade.levels)
end

function OnEat_serum_common(food, player, percent)
    consume(food, player, "common")
end

function OnEat_serum_rare(food, player, percent)
    consume(food, player, "rare")
end

function OnEat_serum_epic(food, player, percent)
    consume(food, player, "epic")
end

-- ── 툴팁 지연 복구 ────────────────────────────────────────────────────────
-- setItem() 은 같은 아이템을 다시 호버하면 호출되지 않는 경로가 있어서
-- (ISInventoryPane 이 item == toolRender.item 이면 early return),
-- 매 프레임 도는 render() 를 훅한다. getTooltip() 이 nil 일 때만 일하므로
-- 최초 1회 이후에는 사실상 비용이 없다.
local hookInstalled = false

local function installTooltipHook()
    if hookInstalled then return end
    if not ISToolTipInv then
        -- 로드 순서 문제로 여기 걸리면 재접속 후 툴팁이 영영 안 뜬다.
        -- OnGameStart 에도 걸어뒀으니 그쪽에서 다시 시도된다.
        print("[PongDu] Serum tooltip hook deferred: ISToolTipInv not loaded yet")
        return
    end
    hookInstalled = true

    local origRender = ISToolTipInv.render
    function ISToolTipInv:render()
        local it = self.item
        if it and it:getTooltip() == nil then
            local md = it:getModData()
            if md.t3SerumGrade and md.t3SerumPerk then
                it:setTooltip(tooltipKey(md.t3SerumGrade, md.t3SerumPerk))
            end
        end
        origRender(self)
    end

    print("[PongDu] Serum tooltip hook installed")
end

-- 둘 중 먼저 도는 쪽에서 설치되고, 나머지는 hookInstalled 로 무시된다.
Events.OnGameBoot.Add(installTooltipHook)
Events.OnGameStart.Add(installTooltipHook)

return serum
