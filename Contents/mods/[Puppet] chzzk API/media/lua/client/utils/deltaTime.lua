-- utils/deltaTime.lua : 프레임 독립 카운트다운용 델타시간
--
-- 기존 카운터들은 OnTick 1회 = 1/60초로 가정하고 1씩 감산했는데, B41에서
-- OnTick은 렌더 프레임(GameWindow.frameStep)마다 1회 발화하므로 30fps면 2배
-- 느리게, 144fps면 2.4배 빠르게 흘렀다.
--
-- 바닐라 GameTime:getRealworldSecondsSinceLastUpdate()
--   = (1/60) * FPSMultiplier,  FPSMultiplier = 60 / 실제FPS  (FPSTracking.frameStep)
--   -> "이번 프레임에 실제로 흐른 초". 엔진이 OnTick(logic)보다 먼저 프레임마다
--      1회 계산해 두므로 여러 기능이 동시에 읽어도 서로 간섭이 없다.
--   - 게임 배속(싱글 빨리감기/수면)은 곱해지지 않음 (getTimeDelta/getMultiplier와 다름)
--   - 싱글 일시정지 중엔 OnTick 자체가 안 돌아서(IngameState: !Paused) 시간이 안 빠짐
--   - FPSMultiplier 상한 5 -> 12fps 미만에선 프레임당 83ms로 캡 (게임 세계와 같은 감속)
--
-- 남은 시간은 각 기능이 자기 modData/로컬에 ms로 따로 들고, 여기선 dt만 준다.

local _a = {}

-- 이번 프레임 경과 시간(ms). OnTick 핸들러 안에서 호출할 것.
function _a.ms()
    return getGameTime():getRealworldSecondsSinceLastUpdate() * 1000.0
end

return _a
