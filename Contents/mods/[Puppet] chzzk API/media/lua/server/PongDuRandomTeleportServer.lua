-- ── 랜덤 텔레포트: 랜덤 플레이어 방식 후보 목록 (PongDuRT) ────────────────────
--
-- RT_Mode = 3(랜덤 플레이어에게)일 때 클라(features/randomteleport.lua)가 요청하면
-- 이동 대상 후보 목록을 요청한 클라에게만 돌려준다. 서버가 하는 일은 목록
-- 작성뿐이고, 세이프존 필터 / 추첨 / 이동은 클라가 한다 -- 플레이어 좌표는
-- 소유 클라가 권위라 서버에서 옮기면 sync에 덮어써진다.
--
-- 클라의 getOnlinePlayers()는 GameClient가 아는 플레이어만 돌려줘서 먼 곳의
-- 접속자가 빠질 수 있다. 전체 접속자는 서버의 GameServer.getPlayers()에만 있다.
--
-- 후보 제외 기준:
--   - 요청자 본인 (username 비교)
--   - 스태프: getAccessLevel() ~= "None" (Admin/Moderator/Overseer/GM/Observer)
--     Observer는 투명 상태라 그 위치로 보내면 허공에 떨어진 것처럼 보인다.
--   - 사망자
--
-- 이 파일은 media/lua/server/ 에 있어 MP 클라에서도 로드된다. OnClientCommand
-- 핸들러에 isAuthority() 가드가 반드시 있어야 한다.

local LOG = "[PongDuRT] "

-- isAuthority() 는 B41 바닐라 전역이 아니다. PongDuMedBoxServer 와 동일하게
-- 로컬로 정의한다. SP 는 isClient()/isServer() 둘 다 false 이므로 not isClient().
local function isAuthority()
    return not isClient()
end

Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuRT" then return end
    if not isAuthority() then return end
    if command ~= "Targets" then return end
    if not player then return end

    local req = tonumber(data and data["req"]) or 0
    local me = player:getUsername()
    local list = {}
    local staff, dead = 0, 0

    local players = getOnlinePlayers()
    if players then
        for i = 0, players:size() - 1 do
            local p = players:get(i)
            if p and p:getUsername() ~= me then
                if p:getAccessLevel() ~= "None" then
                    staff = staff + 1
                elseif p:isDead() then
                    dead = dead + 1
                else
                    list[#list + 1] = {
                        ["name"] = p:getUsername(),
                        ["x"] = math.floor(p:getX()),
                        ["y"] = math.floor(p:getY()),
                        ["z"] = math.floor(p:getZ()),
                    }
                end
            end
        end
    end

    print(LOG .. "target list for " .. tostring(me) .. " req=" .. tostring(req)
        .. " candidates=" .. tostring(#list) .. " skippedStaff=" .. tostring(staff)
        .. " skippedDead=" .. tostring(dead))
    sendServerCommand(player, "PongDuRT", "Targets", { ["req"] = req, ["list"] = list })
end)
