-- ═══════════════════════════════════════════════════════════════════════════
--  퐁듀 헬기(Base.PongDuHeli) 블레이드 파트 create/init.
--
--  차량 스크립트(pongdu_heli_vehicle.txt)의 part lua 블록이 참조한다.
--  BetterHelicopterForMP의 BHblader.lua와 동일 로직 -- 전역 네임스페이스만
--  blade.* -> PongDuHeliBlades.* 로 바꿔 원본 모드와 동시 설치 충돌 방지.
--
--  하는 일: 파트 생성 시 블레이드 모델 12종(대8/소4) 중 하나만 보이게
--  초기화한다. 이후의 "회전"(모델 순환 스왑)은 클라이언트
--  features/firesupport.lua가 매 틱 수행한다.
-- ═══════════════════════════════════════════════════════════════════════════

PongDuHeliBlades = {}
PongDuHeliBlades.Create = {}
PongDuHeliBlades.Init = {}

local function resetBig(vehicle)
    local part = vehicle:getPartById("heliblade")
    if not part then
        print("[PongDu] heli blades: part 'heliblade' missing on create/init")
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

local function resetSmall(vehicle)
    local part = vehicle:getPartById("helibladeSmall")
    if not part then
        print("[PongDu] heli blades: part 'helibladeSmall' missing on create/init")
        return nil
    end
    part:setModelVisible("blade1Small", false)
    part:setModelVisible("blade2Small", false)
    part:setModelVisible("blade3Small", false)
    part:setModelVisible("blade4Small", false)
    part:setModelVisible("blade" .. ZombRand(1, 5) .. "Small", true)
    return part
end

function PongDuHeliBlades.Create.big(vehicle, part)
    resetBig(vehicle)
end

function PongDuHeliBlades.Init.big(vehicle, part)
    resetBig(vehicle)
end

function PongDuHeliBlades.Create.small(vehicle, part)
    resetSmall(vehicle)
end

function PongDuHeliBlades.Init.small(vehicle, part)
    resetSmall(vehicle)
end
