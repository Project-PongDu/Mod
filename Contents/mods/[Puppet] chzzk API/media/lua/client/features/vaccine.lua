-- vaccine.lua : Zomboxivir 앰퓰 (좀비 감염 완전 치료)
--
-- zRe Vaccin("They Knew") 모드의 TheyKnew.Zomboxivir 아이템 + OnEat_Zomboxivir
-- (원본: TheyKnew_BreakAmpule.lua)를 퐁듀 전용 아이템으로 이식. vaccine 후원
-- (rewardManager.lua)이 그 모드가 로드돼 있어야만 지급 가능했던 의존성을 제거하는
-- 게 목적이라, 아이템/사운드/이 함수를 통째로 옮겨왔다.
--
-- 원본 아이템 스크립트의 CustomContextMenu = Break_Ampule은 실제로 연결된 Lua
-- 함수가 원본 모드 어디에도 없는 죽은 참조였다(전체 파일 검색으로 확인). 그래서
-- 이식하지 않았고, 순수 OnEat(우클릭 Eat) 소모형 아이템으로만 동작한다.
--
-- 좀비 감염(Knox Infection)을 완전히 치료한다. 물린 부위(bodyPart)의 감염
-- 플래그까지 전부 해제하는 원본 로직 그대로 유지.

function OnEat_Zomboxivir(food, player, percent)
    local bodyDamage = player:getBodyDamage()
    if not bodyDamage then
        print("[PongDu] vaccine: missing bodyDamage, aborting")
        return
    end

    bodyDamage:setInfected(false)
    bodyDamage:setInfectionMortalityDuration(-1)
    bodyDamage:setInfectionTime(-1)
    bodyDamage:setInfectionLevel(0)

    local bodyParts = bodyDamage:getBodyParts()
    for i = bodyParts:size() - 1, 0, -1 do
        local bodyPart = bodyParts:get(i)
        bodyPart:SetInfected(false)
    end

    print("[PongDu] vaccine: Zomboxivir applied, infection cleared")
end
