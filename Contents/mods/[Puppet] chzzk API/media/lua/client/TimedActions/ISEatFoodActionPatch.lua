-- ISEatFoodActionPatch.lua : 독시사이클린(Antibiotics) 복용 시 Sickness(FoodSicknessLevel)도 함께 치료
--
-- 바닐라 Antibiotics는 ReduceInfectionPower로 상처감염(FakeInfectionLevel)만 줄인다.
-- Sick 모들/Stats.Sickness는 getApparentInfectionLevel() = max(FakeInfectionLevel, InfectionLevel, FoodSicknessLevel)
-- 이므로, 식중독성 Sickness(FoodSicknessLevel)가 남아있으면 상처감염을 치료해도 Sick 배지가 안 사라진다.
-- (BodyDamage.java:1467-1469)
--
-- Java BodyDamage.JustAteFood()는 Lua 이벤트를 발화하지 않아(BodyDamage.java:547-548) 훅 지점이 없다.
-- 대신 실제 섭취를 트리거하는 ISEatFoodAction:perform()을 감싸서 처리한다.
--
-- Antibiotics는 HungerChange/BaseHunger가 스크립트에 정의돼 있지 않아(0 취급) ISEatFoodAction:stop()의
-- 조기취소 재적용 분기(applyEat)가 항상 false로 스킵된다 -> perform()만 패치하면 충분하다.

require "TimedActions/ISEatFoodAction"

local ANTIBIOTICS_FULLTYPE = "Base.Antibiotics"

local perform = ISEatFoodAction.perform

function ISEatFoodAction:perform()
    local isAntibiotics = self.item and self.item:getFullType() == ANTIBIOTICS_FULLTYPE

    perform(self)

    if isAntibiotics and self.character then
        self.character:getBodyDamage():setFoodSicknessLevel(0)
        print("[PongDu] Antibiotics consumed: FoodSicknessLevel reset to 0")
    end
end
