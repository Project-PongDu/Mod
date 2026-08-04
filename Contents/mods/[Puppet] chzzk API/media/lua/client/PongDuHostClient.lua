-- ── 서버장 게이트 거부 안내 ──────────────────────────────────────────────────
--
-- 서버 후원(접속자 전원 대상) 기능을 서버장이 아닌 사람이 받았을 때, 서버가
-- 조용히 드롭하면 화면에는 아무 일도 안 일어난다. 시청자 돈은 나갔는데
-- 스트리머는 버그로 오해하게 되므로 사유를 화면에 띄운다.
--
-- 이 파일은 안내 전용이다. 발동 여부는 전적으로 서버가 결정한다
-- (PongDuHost.check -- 클라에서 판정하면 우회 가능하다).
--
-- 서버 후원 기능이 늘어나도 이 파일은 그대로 재사용한다. 각 기능의 서버
-- 핸들러가 거부할 때 sendServerCommand(player, "PongDuHost", "Denied", {why=...})
-- 만 보내면 된다.

local HALO_R, HALO_G, HALO_B = 255, 90, 90   -- 경고용 붉은색
local HALO_TICKS = 200                        -- 약 3초

-- 사유 -> 번역 키. PongDuHost 의 상수 문자열과 일치해야 한다.
local REASON_KEY = {
    ["not_host"]        = "IGUI_donation_host_only",
    ["not_configured"]  = "IGUI_donation_host_unset",
    ["bad_id"]          = "IGUI_donation_host_badid",
    ["wrong_kind"]      = "IGUI_donation_host_wrongkind",
    ["no_steam"]        = "IGUI_donation_host_nosteam",
}

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuHost" then return end
    if command ~= "Denied" then return end

    local why = tostring(args and args["why"] or "not_host")
    local key = REASON_KEY[why] or REASON_KEY["not_host"]
    print("[PongDuHost] server-tier donation denied, reason=" .. why)

    local p = getPlayer()
    if not p then return end
    -- Say 와 달리 setHaloNote 는 사망/미생성 타이밍에 덜 민감하지만
    -- 후원 도착 시점이 리스폰 직후일 수 있어 동일하게 pcall 로 감싼다.
    pcall(function()
        p:setHaloNote(getText(key), HALO_R, HALO_G, HALO_B, HALO_TICKS)
    end)
end)
