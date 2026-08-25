------------------------------------------------------------
-- ConnectionChecker.lua
-- Writes the current multiplayer connection state, and the
-- server's reward tier table, for the external Puppet launcher.
------------------------------------------------------------

local function WritePuppetStatus(state)
    local writer = getFileWriter("pz_status.txt", false, false)
    if not writer then
        return
    end
    writer:write(state)
    writer:close()
end

------------------------------------------------------------
-- Reward tier dump
--
-- The amount -> featureId mapping now lives in the server's sandbox
-- options (PongDu.Tier_<featureId>), so every streamer on the same
-- server shares one tier table. On connect we dump it to
-- Zomboid/Lua/pongdu_tiers.txt; the launcher reads that file and
-- builds its reward list from it instead of a local preset.
--
-- Sandbox tables are NOT iterated here: SandboxVars.PongDu is indexed
-- directly with a fixed id list, which avoids relying on Kahlua's
-- partial standard library.
------------------------------------------------------------

-- getFileWriter는 확장자를 ini/cfg/txt/log로만 제한한다 (LuaManager.java의
-- ALLOWED_FILE_EXTENSIONS). .json은 이 목록에 없어서 getFileWriter가 null을
-- 반환하고 "relative paths not allowed" 경고만 남긴 채 조용히 실패한다.
-- 내용은 JSON 문자열 그대로 두고 확장자만 .txt로 맞춘다.
local TIER_FILE = "pongdu_tiers.txt"

-- Must stay in sync with rewardHandlers in client/rewards/rewardManager.lua.
-- Order matters: on a duplicate amount the entry listed first wins.
local FEATURE_IDS = {
    "buff_roulette",
    "debuff_roulette",
    "random_weapon",
    "zombie_roulette",
    "vaccine",
    "medical_box",
    "vehicle_drop",
    "sprinter5",
    "random_teleport",
    "random_skill_potion",
    "mutant_spawn",
    "inv_save_ticket",
    "food_supply",
    "fire_support",
    "missile",
    "zombie_rain",
    "rise_up_dead_man",
    "horde_night",
    "blood_moon",
    "bandit_melee",
    "bandit_ranged",
}

-- Escape a value for embedding in the JSON dump. Only the server name can
-- contain arbitrary characters; feature ids are [a-z_] and amounts are ints.
local function jsonEscape(s)
    s = tostring(s or "")
    s = string.gsub(s, "\\", "\\\\")
    s = string.gsub(s, "\"", "\\\"")
    s = string.gsub(s, "\r", " ")
    s = string.gsub(s, "\n", " ")
    s = string.gsub(s, "\t", " ")
    return s
end

local function WriteTierTable()
    local sv = SandboxVars.PongDu
    if not sv then
        print("[PongDu] tier dump aborted: SandboxVars.PongDu is nil")
        return
    end

    local seen = {}          -- amount -> featureId already claimed
    local pairsOut = {}
    local count = 0

    for i = 1, #FEATURE_IDS do
        local fid = FEATURE_IDS[i]
        local amount = sv["Tier_" .. fid]
        if amount == nil then
            print("[PongDu] tier dump: missing sandbox option Tier_" .. fid)
        elseif amount > 0 then
            if seen[amount] then
                print("[PongDu] tier dump: duplicate amount " .. tostring(amount)
                      .. " on " .. fid .. ", already used by " .. seen[amount] .. " - skipped")
            else
                seen[amount] = fid
                count = count + 1
                pairsOut[count] = "\"" .. tostring(amount) .. "\":\"" .. fid .. "\""
            end
        end
    end

    local body = ""
    for i = 1, count do
        if i > 1 then body = body .. "," end
        body = body .. pairsOut[i]
    end

    local json = "{\"server\":\"" .. jsonEscape(getServerName())
              .. "\",\"ts\":" .. tostring(os.time())
              .. ",\"tiers\":{" .. body .. "}}"

    local writer = getFileWriter(TIER_FILE, true, false)   -- create, overwrite
    if not writer then
        print("[PongDu] tier dump failed: cannot open " .. TIER_FILE)
        return
    end
    writer:write(json)
    writer:close()
    print("[PongDu] tier dump written: " .. tostring(count) .. " tiers -> " .. TIER_FILE)
end

------------------------------------------------------------
-- Runtime tier refresh
--
-- 샌드박스 옵션은 어드민 패널(ISServerSandboxOptionsUI)로 세션 도중에도
-- 바뀐다. 엔진은 바뀐 값을 전 클라의 SandboxVars 에 즉시 반영하지만
-- (GameClient.receiveSandboxOptions -> SandboxOptions.toLua, 41.78.20
-- GameClient.java:5925), 그 과정에서 Lua 이벤트를 하나도 쏘지 않는다.
-- 즉 "값이 바뀌었다"를 알려주는 공식 훅이 없어서, 그냥 두면 접속 시점에
-- 뜬 pongdu_tiers.txt 가 계속 남는다.
--
-- 대신 패널의 Apply 버튼이 Lua 라 훅이 가능하다
-- (ISServerSandboxOptionsUI.lua:686). 단 이 버튼은 어드민 본인 클라에서만
-- 돌고, 파일은 스트리머 각자의 Zomboid/Lua/ 에 있어야 하므로 훅은 서버에
-- 핑만 보내고 서버가 전 클라로 되쏜다.
--
-- 지연 보정은 필요 없다. SandboxOptions(패킷 31)와 ClientCommand(패킷 57,
-- sendServerCommand 도 이걸 쓴다)는 둘 다 priority 1 / reliability 2 /
-- ordering channel 0 이라 같은 채널의 reliable-ordered 다
-- (PacketTypes.java:181,220). 어드민의 옵션 패킷이 우리 핑보다 먼저 서버에
-- 닿고, 서버의 옵션 재브로드캐스트가 Refresh 보다 먼저 각 클라에 닿는다.
------------------------------------------------------------

local TIER_MODULE = "PongDuTier"

-- 어드민 패널이 열릴 수 있는 시점보다 앞이면 언제 걸든 상관없다. 파일
-- 로드시점은 바닐라 ISUI 로드 순서에 의존하므로 OnGameStart 에서 건다.
local function HookAdminApply()
    if not ISServerSandboxOptionsUI then
        print("[PongDu] tier refresh hook skipped: ISServerSandboxOptionsUI is nil")
        return
    end
    if ISServerSandboxOptionsUI.pongduTierHooked then
        return
    end
    ISServerSandboxOptionsUI.pongduTierHooked = true

    local original = ISServerSandboxOptionsUI.onButtonApply
    if not original then
        print("[PongDu] tier refresh hook skipped: onButtonApply is nil")
        return
    end

    -- 원본이 self:destroy() 까지 하므로 먼저 돌리고 뒤에 핑을 붙인다.
    ISServerSandboxOptionsUI.onButtonApply = function(self, button)
        original(self, button)
        sendClientCommand(TIER_MODULE, "Changed", {})
        print("[PongDu] admin applied sandbox options - tier refresh requested")
    end

    print("[PongDu] tier refresh hook installed on ISServerSandboxOptionsUI")
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= TIER_MODULE then return end
    if command ~= "Refresh" then return end
    print("[PongDu] tier refresh received - rewriting dump")
    WriteTierTable()
end)

local _tickCount = 0
local TICK_INTERVAL = 150  -- OnTick 약 150회 ≈ 5초

-- 게임 시작 시: 멀티/싱글 모두 인게임이면 CONNECTED + 타임스탬프
Events.OnGameStart.Add(function()
    WritePuppetStatus("CONNECTED|" .. tostring(os.time()))
    WriteTierTable()
    HookAdminApply()
end)

-- 5초마다 타임스탬프 갱신 (Python이 heartbeat로 생존 확인)
Events.OnTick.Add(function()
    _tickCount = _tickCount + 1
    if _tickCount >= TICK_INTERVAL then
        _tickCount = 0
        if isClient() or not isServer() then
            WritePuppetStatus("CONNECTED|" .. tostring(os.time()))
        end
    end
end)

-- 메인메뉴 복귀 시 명시적으로 DISCONNECTED
Events.OnMainMenuEnter.Add(function()
    WritePuppetStatus("DISCONNECTED")
end)
