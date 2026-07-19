-- 차량 드랍 키트("Open Vehicle Drop Kit") 개봉 시 재생되는 RadioTalk 사운드만
-- 볼륨을 절반으로 낮춘다.
--
-- 배경: 레시피 Sound 필드는 ISCraftAction:start()에서 craftSound = character:playSound(...)로
-- 재생되어 Time(200틱) 동안 지속되다 완료/취소 시 stop()에서 정지된다 (PZ-Library
-- ISCraftAction.lua 확인). Recipe 스크립트 자체엔 볼륨 필드가 없어 조절 수단이 없다.
--
-- 시도했던 대안(레시피 Sound 제거 + OnCreate에서 emitter:playSound 직접 재생)은
-- 완료 시점 한 번만 짧게 울려서 원래 있던 "개봉 중 지속되는 라디오 소리"가
-- 사실상 사라진 것처럼 느껴지는 문제가 있어 되돌림.
-- 이 방식은 바닐라 재생 경로(Sound 필드)를 그대로 쓰고, 시작 직후 해당 recipe일
-- 때만 볼륨을 낮추는 방식이라 원래 지속 시간/타이밍이 그대로 유지된다.

local TARGET_RECIPE_NAME = "Open Vehicle Drop Kit"
local TARGET_VOLUME = 0.5

local original_start = ISCraftAction.start
function ISCraftAction:start()
    original_start(self)

    if self.recipe and self.recipe:getName() == TARGET_RECIPE_NAME and self.craftSound then
        local emitter = self.character:getEmitter()
        if emitter then
            emitter:setVolume(self.craftSound, TARGET_VOLUME)
            print("[VehicleDropCraftSound] RadioTalk 볼륨 " .. TARGET_VOLUME .. "로 낮춤")
        else
            print("[VehicleDropCraftSound] emitter 조회 실패, 볼륨 조절 생략")
        end
    end
end
