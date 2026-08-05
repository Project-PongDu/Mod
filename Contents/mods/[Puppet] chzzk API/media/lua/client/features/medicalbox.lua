local _a = {}

-- ── 의약품 랜덤박스 (medical_box) 클라이언트 ─────────────────────────────────
--
-- 서버 후원(PongDu_Server 탭) 계열. 서버장에게 후원이 들어오면 접속자 전원이
-- 의약품 보급상자를 1개씩 받고, 각자 개봉할 때 주사기 4종 중 1개가 뽑힌다
-- (추첨은 shared/t3MedicalBox.lua, 레시피 OnCreate 에서 실행).
--
-- 역할 2가지:
--  ① 지급 요청: 후원이 처리되면 서버에 Request 를 던진다. 서버장 판정은 전부
--     서버(server/PongDuMedBoxServer.lua)에 있다 -- 클라 판정은 우회 가능하다.
--  ② 수령: 서버 Grant 브로드캐스트를 받아 자기 인벤에 상자를 넣는다.
--
-- 싱글플레이 예외: Lua 의 sendServerCommand 는 GameServer.bServer 일 때만
-- 동작하므로(LuaManager.java:6521) SP 에서는 서버->클라 응답 경로가 아예 없다.
-- SP 는 애초에 "전원"이 자기 자신이라 왕복할 이유도 없으므로 바로 로컬 지급한다.

local BOX_ITEM = "medical_box"

-- 상자 지급. rewardManager 의 giveSupply 와 같은 순서(지급 -> 후원자 각인 ->
-- 보급음)지만, 그쪽은 local 함수라 재사용이 안 돼 여기서 다시 구현한다.
--   * pongdu_supply 는 getSoundManager():PlaySound() 로 재생하는 클라 로컬
--     사운드다. 월드 사운드(addSound)가 아니라 좀비 어그로가 붙지 않는다.
--   * PlaySound 의 maxGain 인자는 SoundManager.java 구현상 무시되므로 반환
--     핸들에 setVolume 을 직접 건다.
--   * AddItem 이 nil 을 돌려주면 사운드를 재생하지 않는다 -- "소리는 났는데
--     아이템은 없다"가 제일 추적하기 어렵다.
local function giveBox(sender)
    local player = getPlayer()
    if not player then
        print("[PongDuMedBox] grant aborted: player is nil")
        return
    end

    local item = player:getInventory():AddItem("t3chzzkDonation." .. BOX_ITEM)
    if not item then
        print("[PongDuMedBox] grant FAILED: AddItem returned nil (item=" .. BOX_ITEM
            .. ", sender=" .. tostring(sender) .. ")")
        return
    end

    item:setName((sender or "") .. "'s " .. item:getDisplayName())
    item:getModData().t3Donor = sender or ""

    local audio = getSoundManager():PlaySound("pongdu_supply", false, 1.0)
    if audio then audio:setVolume(0.5) end

    print("[PongDuMedBox] box delivered sender=" .. tostring(sender))
end

-- ── 서버 커맨드 수신 ─────────────────────────────────────────────────────────
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuMedBox" then return end
    if command ~= "Grant" then return end
    giveBox(tostring(args and args["sender"] or ""))
end)

-- ── 지급 요청 (rewardManager 에서 호출) ──────────────────────────────────────
function _a.a(sender)
    if isClient() then
        sendClientCommand("PongDuMedBox", "Request", { ["sender"] = sender or "" })
        print("[PongDuMedBox] grant requested sender=" .. tostring(sender))
    else
        -- SP / 로컬 호스트: 서버 왕복 없이 바로 지급 (위 주석 참조)
        print("[PongDuMedBox] singleplayer path, granting locally sender=" .. tostring(sender))
        giveBox(sender or "")
    end
end

return _a
