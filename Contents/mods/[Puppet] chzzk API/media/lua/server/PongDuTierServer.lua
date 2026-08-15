-- ── 리워드 티어 런타임 갱신 릴레이 (PongDuTier) ────────────────────────────
--
-- 어드민이 게임 도중 샌드박스 옵션을 적용하면, 엔진이 전 클라의 SandboxVars
-- 를 갱신하지만 Lua 이벤트는 안 쏜다. 그래서 어드민 클라가 패널 Apply 버튼
-- 훅(client/ConnectionChecker.lua)에서 이 모듈로 핑을 보내고, 서버는 그걸
-- 전 클라로 되쏜다. 각 클라는 Refresh 를 받고 자기 Zomboid/Lua/
-- pongdu_tiers.txt 를 다시 쓴다.
--
-- 서버가 하는 일은 브로드캐스트뿐이다. 값 자체는 엔진이 이미 동기화해뒀다.
--
-- 이 파일은 media/lua/server/ 에 있어 MP 클라에서도 로드된다.
-- OnClientCommand 핸들러에 isAuthority() 가드가 반드시 있어야 한다.

local LOG = "[PongDuTier] "

-- isAuthority() 는 B41 바닐라 전역이 아니다. PongDuMedBoxServer 와 동일하게
-- 로컬로 정의한다. SP 는 isClient()/isServer() 둘 다 false 이므로 not isClient().
local function isAuthority()
    return not isClient()
end

Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuTier" then return end
    if not isAuthority() then return end
    if command ~= "Changed" then return end

    -- 클라 훅은 어드민 패널에서만 발화하지만, 커맨드 자체는 아무 클라나
    -- 위조해서 보낼 수 있다. 효과가 "전 클라가 파일 1개 재기록"이라 피해는
    -- 없지만 스팸은 막는다. 샌드박스 패널 자체가 admin/moderator 권한이라
    -- 같은 기준을 쓴다.
    local level = player and player:getAccessLevel() or "None"
    if level == "None" then
        print(LOG .. "REFRESH DENIED user=" .. tostring(player and player:getUsername())
            .. " accessLevel=" .. tostring(level))
        return
    end

    print(LOG .. "sandbox options applied by " .. tostring(player and player:getUsername())
        .. " (" .. tostring(level) .. ") - broadcasting tier refresh")
    sendServerCommand("PongDuTier", "Refresh", {})
end)
