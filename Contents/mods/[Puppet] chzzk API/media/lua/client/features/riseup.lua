local _a = {}

-- 라이즈 업 데드 맨: 도네 플레이어 기준 반경 내 모든 시체(IsoDeadBody)를
-- 좀비로 되살린다.
--
-- 반경은 전용 샌드박스 변수 Donation_RiseUpRadius (5~60, 기본 55)를 따른다.
-- 폭격(Donation_BombardRadius)과는 별개 변수 — 기본값만 55로 같을 뿐 서로 독립.
--
-- 권한 구조는 폭격과 정반대다.
--   좀비(IsoZombie)  = 클라이언트 권한 -> 폭격 킬은 클라별 분산 처리 (bombard.lua)
--   시체(IsoDeadBody) = 서버 권한      -> 부활은 서버 핸들러 한 곳에서만 처리
-- 바닐라도 MP 시체 제거를 서버 커맨드(/removezombies)로 우회하고, 시체는
-- 청크 데이터 + reanimated.bin 으로 서버에 저장된다. 클라 브로드캐스트로
-- 각자 reanimateNow() 하면 클라 수만큼 좀비가 중복 생성될 수 있으므로 금지.

-- 도네 발동 진입점. 서버에 좌표/반경만 넘기고 실제 부활은 server.lua 의
-- DOServer["Schedule"]["RiseUp"] 이 수행한다.
-- SandboxVars는 파일 로드 시점엔 비어있을 수 있으므로 사용 시점에 읽는다.
function _a.a(player)
    if not player then return end
    local sv = SandboxVars and SandboxVars.Hitmans
    local radius = (sv and tonumber(sv.Donation_RiseUpRadius)) or 55

    getSoundManager():PlaySound("necromance", false, 1.0)

    sendClientCommand("Schedule", "PlayAlert", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = radius,
    })
    sendClientCommand("Schedule", "RiseUp", {
        ["x"] = player:getX(),
        ["y"] = player:getY(),
        ["r"] = radius,
    })
end

return _a
