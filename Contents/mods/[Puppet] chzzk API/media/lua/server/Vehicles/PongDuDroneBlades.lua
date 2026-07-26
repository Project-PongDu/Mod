-- ═══════════════════════════════════════════════════════════════════════════
--  퐁듀 드론(Base.PongDuDrone) 블레이드 파트 create/init.
--
--  차량 스크립트(pongdu_drone_vehicle.txt)의 part lua 블록이 참조한다.
--  PongDuHeliBlades.lua와 동일 패턴이지만, 드론은 로터가 4개여도 4개 전부가
--  한 메시에 들어 있어(프레임당 pongdu_drone_bladeN.fbx 하나) 파트가 하나뿐
--  이다. 헬기의 big/small 2파트 구조가 필요 없다.
--
--  하는 일: 파트 생성 시 블레이드 모델 8종 중 하나만 보이게 초기화한다.
--  이후의 "회전"(모델 순환 스왑)은 클라이언트 features/firesupport.lua가
--  매 틱 수행한다.
--
--  프레임 규약: blade1..blade8 = 0/22.5/45/.../157.5도.
--  2엽 프로펠러라 주기가 360도가 아니라 180도이므로 8프레임이 한 바퀴다.
-- ═══════════════════════════════════════════════════════════════════════════

PongDuDroneBlades = {}
PongDuDroneBlades.Create = {}
PongDuDroneBlades.Init = {}

local function reset(vehicle)
    local part = vehicle:getPartById("droneblade")
    if not part then
        print("[PongDu] drone blades: part 'droneblade' missing on create/init")
        return nil
    end
    part:setModelVisible("blade1", false)
    part:setModelVisible("blade2", false)
    part:setModelVisible("blade3", false)
    part:setModelVisible("blade4", false)
    part:setModelVisible("blade5", false)
    part:setModelVisible("blade6", false)
    part:setModelVisible("blade7", false)
    part:setModelVisible("blade8", false)
    part:setModelVisible("blade" .. ZombRand(1, 9), true)
    return part
end

function PongDuDroneBlades.Create.rotors(vehicle, part)
    reset(vehicle)
end

function PongDuDroneBlades.Init.rotors(vehicle, part)
    reset(vehicle)
end
