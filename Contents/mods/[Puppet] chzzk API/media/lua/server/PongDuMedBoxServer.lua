-- ── 의약품 랜덤박스 (medical_box) 서버 ───────────────────────────────────────
--
-- 서버 후원 계열. 서버장에게 후원이 들어오면 접속자 전원에게 의약품 보급상자를
-- 1개씩 지급한다. 서버가 하는 일은 두 가지뿐이다:
--   ① 서버장 게이트 (PongDuHost.check)
--   ② 전 클라 브로드캐스트
--
-- 실제 지급(AddItem)은 각 클라가 한다. 서버에서 다른 플레이어의 인벤토리를
-- 직접 건드리면 소유 클라의 sync 에 덮어써지므로, 아이템 계열은 전부 클라가
-- 자기 인벤에 넣는 구조다(rewardManager 의 giveSupply 와 동일).
--
-- 이 파일은 media/lua/server/ 에 있어 MP 클라에서도 로드된다. OnClientCommand
-- 핸들러에 isAuthority() 가드가 반드시 있어야 한다.

local LOG = "[PongDuMedBox] "

local function mlog(msg)
    print(LOG .. msg)
end

Events.OnClientCommand.Add(function(module, command, player, data)
    if module ~= "PongDuMedBox" then return end
    if not isAuthority() then return end
    if command ~= "Request" then return end

    -- 서버장 게이트. isAuthority() 는 "이 코드가 서버에서 도는가"만 보지 누가
    -- 보냈는지는 안 본다. 접속자 전원에게 아이템이 나가는 효과라 서버장에게
    -- 들어온 후원만 통과시킨다. 클라 쪽 검사는 전부 우회 가능하므로 여기가
    -- 유일한 강제 지점이다.
    local verdict = PongDuHost.check(player)
    if verdict ~= PongDuHost.OK then
        mlog("REQUEST DENIED user=" .. tostring(player and player:getUsername())
            -- Kahlua 는 SteamID64 를 double 로 넘기므로 tostring() 하면 지수표기가
            -- 나와 샌박 값과 육안 대조가 안 된다. %.0f 로 정수 형태를 강제한다.
            .. " steamID=" .. string.format("%.0f", (player and player:getSteamID()) or 0)
            .. " reason=" .. tostring(verdict))
        -- 거부 안내는 공용 클라 핸들러(client/PongDuHostClient.lua)가 처리한다.
        sendServerCommand(player, "PongDuHost", "Denied", { ["why"] = verdict })
        return
    end

    local sender = tostring(data and data["sender"] or "")
    mlog("GRANT broadcast sender=" .. sender)
    sendServerCommand("PongDuMedBox", "Grant", { ["sender"] = sender })
end)
