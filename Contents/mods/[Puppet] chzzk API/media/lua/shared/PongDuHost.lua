-- ── 서버장(호스트) 판정 ── 서버 후원(PongDu_Server 탭) 공용 게이트 ───────────
--
-- 서버 후원은 접속자 전원에게 효과가 걸리는 계열이라 아무나 쏠 수 있으면 안 된다.
-- 판정 기준은 두 가지다.
--   ① 서버장: 샌드박스 PongDu.Host_SteamID 에 수동 입력한 Steam ID64 와 일치
--   ② 어드민: accessLevel == "Admin" (Host_SteamID 설정과 무관하게 통과)
--
-- 이 파일은 media/lua/shared/ 에 있어 서버와 클라이언트 양쪽에서 로드된다.
-- require 가 아니라 전역 테이블 패턴(HitmanUtils 와 동일)을 쓴다.
--
-- ── 판정은 반드시 서버에서만 한다 ──
-- 클라에서 check() 를 불러 "발동 여부"를 결정하면 안 된다. 클라 코드와 파일은
-- 전부 사용자 손에 있어 우회 가능하다. 위조 불가능한 값은 서버가 보는
-- player:getSteamID() 뿐이다(GameServer.java:5308 에서 udpConnection.steamID 로
-- 채워지며, 이건 Steam 인증 연결에서 온 값이다).
--
-- ── 왜 username 을 안 쓰나 ──
-- 한글 계정명이면 AllowNonAsciiUsername(기본 false)이 필요하고, 샌드박스 저장
-- 경로(SandboxOptions.java:956 FileWriter)가 플랫폼 기본 charset 을 써서
-- OS/로케일이 바뀌면 저장된 값이 조용히 깨진다.
--
-- ── [중요] 숫자 비교를 문자열 비교로 바꾸지 말 것 ──
-- Kahlua 는 정수 타입이 없고 모든 숫자가 double 이다. Java long 을 Lua 로 넘길 때
-- KahluaNumberConverter.NumberToLuaConverter 가 무조건 new Double(...) 을 만든다.
-- SteamID64(약 7.66e16)는 double 정수 정확도 한계(2^53≈9.0e15)를 넘어서 이 구간의
-- ULP 가 16이다. 즉 76561198321169110 -> 76561198321169104 로 반올림된다.
--   * tostring(player:getSteamID()) 는 지수표기가 나와 입력값과 절대 안 맞는다.
--   * tonumber(샌드박스 문자열) 도 같은 double 로 떨어지므로 숫자 비교는 성립한다.
-- 대가는 서버장 ID ±8 범위의 스팀계정도 통과한다는 것인데, 스팀 ID 는 가입
-- 순서대로 순차 배정되므로 서버장과 몇 초 차이로 가입한 계정이어야 걸린다.
-- 사설 서버에서는 사실상 발생하지 않는다.
--
-- 서버에는 무손실 경로가 없다. String 을 반환하는 Steam 함수는 전부 클라 전용이다
-- (getCurrentUserSteamID: !GameServer.bServer / getSteamIDFromUsername: GameClient.bClient).

PongDuHost = PongDuHost or {}

-- 판정 결과. 클라에 그대로 넘겨 사유별 안내 문구를 띄운다.
-- 17자리 오타는 눈으로 못 잡으므로 "왜 안 되는지"가 반드시 화면에 나와야 한다.
PongDuHost.OK         = "ok"
PongDuHost.NOT_HOST   = "not_host"          -- 후원 받은 사람이 서버장이 아님
PongDuHost.UNSET      = "not_configured"    -- Host_SteamID 미설정
PongDuHost.BAD_ID     = "bad_id"            -- 형식 오류(오타)
PongDuHost.WRONG_KIND = "wrong_kind"        -- 개인 계정 ID가 아님(그룹/게임서버 등)
PongDuHost.NO_STEAM   = "no_steam"          -- 스팀 모드 OFF 서버라 판정 불가

-- 개인 계정 SteamID64 범위.
-- SteamID64 = (universe << 56) | (type << 52) | (instance << 32) | accountID 이고,
-- 플레이어는 universe=Public / type=Individual / instance=Desktop 로 상위 비트가
-- 고정이라 76561197960265728 + accountID(32비트) 의 닫힌 구간이 된다.
--
-- 이 검사는 판정 정확도를 올리지 않는다. 범위 밖 값은 어차피 어떤 접속자의
-- getSteamID() 와도 일치하지 않아 not_host 로 떨어진다. 목적은 진단이다 --
-- 게임서버 ID(예: 90290122427026461)는 개인 계정과 자릿수가 같아 육안 구분이
-- 안 되고, 서버 콘솔 로그에 둘이 나란히 찍히므로 잘못 붙여넣는 실수가 나온다.
-- 그 경우 영구 not_host 로 조용히 실패하는 대신 설정 오류로 즉시 알린다.
local ID_MIN = 76561197960265728
local ID_MAX = 76561202255233023

-- 미설정 센티널. 빈 문자열 default 는 CustomStringSandboxOption.parse 가
-- default 값을 못 찾으면 null 을 반환해 옵션 자체가 등록 안 될 수 있어
-- 명시적 값을 쓴다.
local NONE = "none"

local function rawId()
    local s = SandboxVars.PongDu.Host_SteamID
    if s == nil then return "" end
    return tostring(s)
end

-- 설정된 서버장 SteamID 문자열. 미설정이면 nil, 형식 오류면 false.
-- (nil 과 false 를 구분해야 "미설정"과 "오타"를 다르게 안내할 수 있다)
function PongDuHost.getId()
    local s = rawId()
    if s == "" or s == NONE then return nil end
    -- isValidSteamID 는 SteamUtils 에서 BigInteger 로 파싱하며 서버/클라 어디서나
    -- 동작한다(LuaManager.java:6910, 가드 없음). double 을 안 거치는 유일한 검증 경로.
    if not isValidSteamID(s) then return false end
    return s
end

-- ── 어드민 판정 ──────────────────────────────────────────────────────────────
-- 서버장 1명만 서버 후원을 쏠 수 있으면 운영이 안 된다. 서버장이 자리를 비운
-- 사이 스탭이 테스트를 돌리거나, Host_SteamID 를 아직 안 넣은 상태에서 확인할
-- 일이 있어 어드민도 통과시킨다.
--
-- 기준은 accessLevel == "Admin" 하나다. moderator / gm / overseer / observer 는
-- 포함하지 않는다 -- 컨텍스트 메뉴 노출 조건인 isAdmin() 이 accessLevel == 32
-- (admin) 단일 값이라(LuaManager.java:6612), 여기서 범위를 넓히면 "메뉴는 안
-- 보이는데 서버는 허용" 같은 비대칭이 생긴다.
--
-- 서버측 판정은 위조 불가능하다. IsoPlayer.accessLevel 을 채우는 곳이
-- GameServer.java:5366 의 udpConnection0.accessLevel 하나뿐이고, 이건 로그온
-- 시점에 ServerWorldDatabase 가 준 값이다.
--
-- 클라측에서도 같은 함수를 쓸 수 있다. GameServer.sendPlayerExtraInfo 가
-- accessLevel 을 전 접속자에게 브로드캐스트하고(GameServer.java:1274~1288)
-- GameClient.receiveExtraInfo 가 원격 플레이어 객체에 대입하므로
-- (GameClient.java:3086), 클라에서 남의 어드민 여부도 볼 수 있다.
-- 물론 표시용일 뿐이고 실제 권한은 서버가 다시 본다.
function PongDuHost.isAdminLevel(player)
    if not player then return false end
    -- getAccessLevel() 은 내부 소문자값을 "Admin"/"Moderator"/.../"None" 으로
    -- 정규화해 돌려준다(IsoPlayer.java:6614). 미설정이면 "None".
    return player:getAccessLevel() == "Admin"
end

-- 서버 판정. 반환값은 위 상수 중 하나.
function PongDuHost.check(player)
    -- 싱글플레이: 플레이어가 곧 서버장. setSteamID 호출처가
    -- GameClient.java:3265 / GameServer.java:5308 두 곳뿐이라 SP 에서는
    -- steamID 가 long 기본값 0 으로 남는다. ID 비교 자체가 성립하지 않는다.
    if not isClient() and not isServer() then return PongDuHost.OK end
    if not player then return PongDuHost.NOT_HOST end

    -- 어드민 우회. Host_SteamID 설정/스팀 모드와 완전히 무관하게 통과시킨다.
    -- 스팀 ID 게이트보다 먼저 두는 게 의도적이다 -- Host_SteamID 가 미설정이거나
    -- 오타여도, 스팀 모드가 꺼진 서버여도 어드민은 서버 후원을 쏠 수 있어야
    -- 운영/테스트가 막히지 않는다.
    if PongDuHost.isAdminLevel(player) then return PongDuHost.OK end

    -- 스팀 모드가 꺼진 서버(직접 IP 접속 전용)에서는 setSteamID 가 호출되지 않아
    -- 전원 0 이다. 통과시키면 접속자 전원이 서버장이 되므로 기능을 막는다.
    if not getSteamModeActive() then return PongDuHost.NO_STEAM end

    local want = PongDuHost.getId()
    if want == nil then return PongDuHost.UNSET end
    if want == false then return PongDuHost.BAD_ID end

    local wantNum = tonumber(want)
    if not wantNum then return PongDuHost.BAD_ID end
    -- 경계값도 double 로 반올림되지만 오차가 16 수준이라 범위 판정에는 영향이 없다.
    if wantNum < ID_MIN or wantNum > ID_MAX then return PongDuHost.WRONG_KIND end

    local got = player:getSteamID()
    if not got or got == 0 then return PongDuHost.NOT_HOST end
    if wantNum ~= got then return PongDuHost.NOT_HOST end
    return PongDuHost.OK
end

function PongDuHost.isHost(player)
    return PongDuHost.check(player) == PongDuHost.OK
end

-- 서버 부팅 시 설정 검증 로그. 17자리 오타는 방송 시작 전에 잡혀야 한다.
function PongDuHost.logConfig()
    local s = rawId()
    if s == "" or s == NONE then
        print("[PongDuHost] Host_SteamID not set -- server-tier donations are limited to admins")
        return
    end
    if not isValidSteamID(s) then
        print("[PongDuHost] WARNING: Host_SteamID is malformed, server-tier donations DISABLED: '"
            .. s .. "'")
        return
    end
    local n = tonumber(s)
    if not n or n < ID_MIN or n > ID_MAX then
        print("[PongDuHost] WARNING: Host_SteamID is not an individual account ID (expected "
            .. string.format("%.0f", ID_MIN) .. "~" .. string.format("%.0f", ID_MAX)
            .. "), got: " .. s .. " -- did you paste a group or game server ID?")
        return
    end
    if not getSteamModeActive() then
        print("[PongDuHost] WARNING: Steam mode is OFF -- getSteamID() returns 0 for every"
            .. " player, so Host_SteamID can never match")
        return
    end
    print("[PongDuHost] host configured steamID=" .. s
        .. " (admins are also allowed to trigger server-tier donations)")
end
