local _a = {}

local zone   = require("utils/zone")
local global = require("global")

-- ═══════════════════════════════════════════════════════════════════════════
--  뮤턴트 (mutant_spawn): 스크리머 / 브루트 / 로치 중 1마리 랜덤 소환.
--
--  CDDA Zombies 모드에서 스크리머·브루트의 동작 로직만 떼어 자체 이식했다
--  (밴딧 -> 히트맨 이식과 동일 방식). CDDA 모드 의존성 없음 — 타입 배정도
--  CDDA의 CZList/RequestZombieType 대신 modData["PuppetMutant"] 하나로 처리.
--
--    스크리머 : HP 1, 일반 걸음. 타깃이 생기면 주기적으로 비명
--               (mutant_scream1/2 재생 + 반경 50 월드사운드로 주변 좀비 유인).
--               CDDA_ZombieFunction.Scream 이식.
--    브루트   : HP 3, 스프린터, 괴력(Strength=1), 넉다운 면역(keepstand),
--               공격 중 플레이어를 밀쳐냄(attackFromWindowsLunge).
--               CDDA_ZombieFunction.Push + keepstand 이식.
--    로치     : HP 1, 크롤 전용 + 크롤 속도 3배. 자체 제작 —
--               AnimSets/zombie-crawler/*/roach_*.xml 노드가 PuppetRoach
--               애님 변수 조건으로 3배속 크롤을 재생 (조건 수가 많은 노드가
--               우선 선택되는 PZ 애님 규칙, Hitman 애님 변형과 동일 기법).
--
--  권한 구조: 좀비는 클라이언트 권한이므로 서버는 스폰 + modData 마킹만 하고
--  (server.lua MutantSpawn 핸들러), 실제 스탯/행동은 각 클라이언트의
--  OnZombieUpdate 적용기가 처리한다. 좀비 스트리밍/재사용으로 애님 변수가
--  풀리면 PuppetMutantInit 가드가 리셋되므로 다음 틱에 자동 재적용된다.
-- ═══════════════════════════════════════════════════════════════════════════

local KINDS = { "screamer", "brute", "roach" }

local haloKey = {
    screamer = "IGUI_mutant_name_screamer",
    brute    = "IGUI_mutant_name_brute",
    roach    = "IGUI_mutant_name_roach",
}

-- 소환 외침: 욕(SWEAR) + 종류(mutateType) + 마무리(ENDMENT) 3파트를 랜덤 조합.
-- 예) "시발, 브루트잖아!" / "젠장, 로치 출현!"  (ENDMENT 쪽에 필요한 공백을 미리 포함시켜둠)
local SWEAR_KEYS = {
    "IGUI_mutant_swear_1", "IGUI_mutant_swear_2", "IGUI_mutant_swear_3",
    "IGUI_mutant_swear_4", "IGUI_mutant_swear_5", "IGUI_mutant_swear_6",
}
local ENDMENT_KEYS = {
    "IGUI_mutant_endment_1", "IGUI_mutant_endment_2", "IGUI_mutant_endment_3",
    "IGUI_mutant_endment_4", "IGUI_mutant_endment_5",
}

-- 비명 쿨다운(ms, 실시간). CDDA는 인게임 5분(기본 낮길이 기준 실시간 ~12.5초)
-- 주기였는데, 인게임 분 카운터 동기화 기계장치 대신 실시간 쿨다운으로 단순화.
local SCREAM_COOLDOWN_MS = 15000
local _nextScream = {}   -- [onlineID] = 다음 비명 허용 시각(ms). 클라 로컬.

-- 도네 발동 진입점 (rewardManager가 안전지대 대기까지 끝낸 뒤 호출).
-- 종류를 클라에서 굴리고, 좌표와 함께 서버에 스폰 요청. [public name: .a]
function _a.a(sender)
    local player = getPlayer()
    if not player then return end
    local kind = KINDS[ZombRand(#KINDS) + 1]
    sendClientCommand("PEvents", "MutantSpawn", {
        ["ZedX"]   = player:getX() + zone.b(),
        ["ZedY"]   = player:getY() + zone.b(),
        ["ZedZ"]   = player:getZ(),
        ["kind"]   = kind,
        ["sender"] = sender or "",
    })
    local key = haloKey[kind]
    if key then
        local swear   = getText(SWEAR_KEYS[ZombRand(#SWEAR_KEYS) + 1])
        local endment = getText(ENDMENT_KEYS[ZombRand(#ENDMENT_KEYS) + 1])
        local msg = swear .. ", " .. getText(key) .. endment
        player:setHaloNote(msg, 255, 70, 70, 300)
    end
end

-- ── 1회 초기화 (클라별) ───────────────────────────────────────────────────────
-- 스탯류는 매 틱 재적용하면 안 되는 것들이라 PuppetMutantInit 애님 변수로
-- 가드. 변수는 좀비가 스트림 아웃되면 리셋 -> 다시 로드될 때 자동 재초기화.
local function initMutant(zombie, kind)
    if kind == "brute" then
        -- 괴력: CDDA_UpdateZombie와 동일하게 샌드박스 스왑 + DoZombieStats.
        local origStr = getSandboxOptions():getOptionByName("ZombieLore.Strength"):getValue()
        getSandboxOptions():set("ZombieLore.Strength", 1)   -- 1 = Superhuman
        zombie:DoZombieStats()
        getSandboxOptions():set("ZombieLore.Strength", origStr)
        zombie:setWalkType("sprint" .. tostring(ZombRand(5) + 1))
        zombie:setHealth(3.0)          -- CDDA Brute HP=3. DoZombieStats 뒤에 설정
    elseif kind == "screamer" then
        zombie:setHealth(1.0)          -- CDDA Screamer HP=1. 걸음은 기본값 유지
    elseif kind == "roach" then
        zombie:setHealth(1.0)
        zombie:setVariable("PuppetRoach", true)
    elseif kind == "sprinter" then
        -- 부활한 뛰좀 재적용 경로 (원 스폰은 서버 makeSprinter가 처리)
        zombie:setWalkType("sprint" .. tostring(ZombRand(5) + 1))
    end
    print("[PuppetMutant] init " .. tostring(kind) .. " zid=" .. tostring(zombie:getOnlineID()))
    zombie:setVariable("PuppetMutantInit", true)
end

-- ── 스크리머: 비명 (CDDA_ZombieFunction.Scream 이식) ─────────────────────────
-- playSound는 클라 로컬 렌더링이라 각 클라가 각자 재생 = 전원이 들림.
-- addSound(월드사운드)는 각 클라가 자기 소유 좀비를 유인 -> 폭격(bombard)과
-- 같은 분산 처리 구조라 클라별 실행이 정답.
local function updateScreamer(zombie)
    local target = zombie:getTarget()
    if not target then return end
    local zid = zombie:getOnlineID()
    local now = getTimestampMs()
    if _nextScream[zid] and now < _nextScream[zid] then return end
    _nextScream[zid] = now + SCREAM_COOLDOWN_MS
    local player = getPlayer()
    if player and not player:HasTrait("Deaf") then
        zombie:playSound("mutant_scream" .. tostring(ZombRand(2) + 1))
    end
    -- 소스=좀비: 바닐라 addSound 패턴. 소스 본인은 월드사운드에 반응하지
    -- 않으므로 스크리머가 자기 비명을 쫓아가는 일도 자연 차단된다.
    addSound(zombie, zombie:getX(), zombie:getY(), zombie:getZ(), 50, 50)
end

-- ── 브루트: 넉다운 면역 + 밀치기 (keepstand + Push 이식) ─────────────────────
-- attackFromWindowsLunge는 플레이어 객체를 직접 밀쳐내므로 로컬 플레이어에게만
-- 적용 (CDDA는 이 가드가 없는데, 원격 플레이어 프록시에 걸면 무의미/부정확).
local function updateBrute(zombie)
    zombie:setKnockedDown(false)
    if zombie:isAttacking() then
        local target = zombie:getTarget()
        if target and instanceof(target, "IsoPlayer") and target:isLocalPlayer() then
            target:attackFromWindowsLunge(zombie)
        end
    end
end

-- ── 로치: 크롤 상태 유지 ─────────────────────────────────────────────────────
-- CDDA_UpdateZombie의 walktype 4 처리와 동일 패턴 — 상태가 풀려도 매 틱 복구.
local function updateRoach(zombie)
    if not zombie:isCrawling() then
        zombie:toggleCrawling()
    end
    zombie:setFallOnFront(true)
    zombie:setCanWalk(false)
end

-- ── 적용기 본체 ───────────────────────────────────────────────────────────────
-- 서버발 zombie transmitModData는 클라이언트에 전달되지 않으므로, 서버가
-- sendServerCommand("PEvents","MutantMark")로 쏜 zedId+kind를 받아두고
-- OnZombieUpdate에서 onlineID로 매칭한다 (폭격 NearbyExplosion과 같은 채널).
-- modData 경로는 SP/호스트 겸용 폴백으로 유지.
local _pending = {}   -- [onlineID] = kind

-- 영속 레지스트리: 서버가 특수좀비 탄생 시 글로벌 ModData "PuppetMutants"에
-- 정규화ID -> kind 로 등록해둔다 (server.lua registerMutant 참고). 이 ID는
-- 사망->시체->부활 내내 유지되므로 부활 좀비도 조회에 걸려 자동 재적용된다.
-- 모자 비트 마스킹까지 등록/조회가 같은 함수(HitmanUtils.GetZombieID)를 쓴다.
local _registry = {}  -- [정규화ID 문자열] = kind 또는 {k=종류, s=후원자}

-- 레지스트리/펜딩 항목 겸용 리더 (구버전 문자열 항목 호환)
local function regEntry(v)
    if type(v) == "table" then return v["k"], v["s"] end
    return v, nil
end

local function mutantKey(zombie)
    if HitmanUtils and HitmanUtils.GetZombieID then
        return tostring(HitmanUtils.GetZombieID(zombie))
    end
    return tostring(zombie:getPersistentOutfitID())
end

Events.OnReceiveGlobalModData.Add(function(name, data)
    if name == "PuppetMutants" and type(data) == "table" then
        _registry = data
        print("[PuppetMutant] registry received, entries follow")
        for k, v in pairs(_registry) do
            print("[PuppetMutant]   " .. tostring(k) .. " = " .. tostring(v))
        end
    end
end)
Events.OnGameStart.Add(function()
    ModData.request("PuppetMutants")
end)

-- 부활 마크: 서버 RiseUp이 특수좀비 시체를 판별하면 부활 위치+종류를
-- 브로드캐스트한다. 부활 좀비는 pid가 새로 발급돼 레지스트리 직조회가
-- 불가하므로, 클라가 마크 스퀘어(±1)의 미적용 좀비에게 능력을 재적용한다.
local _reviveMarks = {}   -- { {x,y,z,kind,expire}, ... }
local REVIVE_MARK_MS = 20000

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PEvents" then return end
    if command == "MutantMark" then
        local zid  = args and tonumber(args["zedId"])
        local kind = args and args["kind"]
        if zid and kind then
            _pending[zid] = { ["k"] = kind, ["s"] = args["sender"] }
        end
    elseif command == "MutantRevive" then
        local x, y = tonumber(args and args["x"]), tonumber(args and args["y"])
        local kind = args and args["kind"]
        if x and y and kind then
            _reviveMarks[#_reviveMarks + 1] = {
                x = x, y = y, z = tonumber(args["z"]) or 0,
                kind = kind, sender = args["sender"],
                expire = getTimestampMs() + REVIVE_MARK_MS,
            }
            print("[PuppetMutant] revive mark " .. tostring(kind)
                .. " @" .. tostring(x) .. "," .. tostring(y)
                .. " key=" .. tostring(args["key"]))
        end
    elseif command == "MutantReviveDebug" then
        print("[PuppetMutant] riseup total=" .. tostring(args and args["total"])
            .. " pid-readable=" .. tostring(args and args["readable"])
            .. " special=" .. tostring(args and args["marked"]))
    end
end)

-- 마크 매칭: 마크 스퀘어 ±1 안의 좀비면 소모하고 종류 반환.
-- 같은 스퀘어에 이종 시체가 동시 부활하면 클라별 배정이 어긋날 수 있는
-- 알려진 한계가 있으나(드묾), 재등록으로 이후 사이클부터는 pid로 고정된다.
local function matchReviveMark(zombie)
    if #_reviveMarks == 0 then return nil end
    local zx = math.floor(zombie:getX())
    local zy = math.floor(zombie:getY())
    local zz = math.floor(zombie:getZ())
    local now = getTimestampMs()
    for i = #_reviveMarks, 1, -1 do
        local m = _reviveMarks[i]
        if now > m.expire then
            table.remove(_reviveMarks, i)
        elseif math.abs(m.x - zx) <= 1 and math.abs(m.y - zy) <= 1 and m.z == zz then
            table.remove(_reviveMarks, i)
            return m.kind, m.sender
        end
    end
    return nil
end

local function applyMutant(zombie)
    local md = zombie:getModData()
    local kind, sender = md["PuppetMutant"], md["PuppetMutantSender"]
    if not kind then
        local p = _pending[zombie:getOnlineID()]
        if p then kind, sender = regEntry(p) end
    end
    if not kind then
        kind, sender = regEntry(_registry[mutantKey(zombie)])
    end
    if not kind and zombie:isAlive()
        and not zombie:getVariableBoolean("PuppetMutantInit") then
        kind, sender = matchReviveMark(zombie)
        if kind then
            -- 새 pid를 서버 레지스트리에 재등록 (후원자 포함)
            sendClientCommand("PEvents", "MutantReregister", {
                ["key"] = mutantKey(zombie), ["kind"] = kind,
                ["sender"] = sender,
            })
        end
    end
    if not kind then return end
    -- 클라 로컬 캐시: 이후 조회/네임태그 렌더가 modData만 보면 되게
    if not md["PuppetMutant"] then md["PuppetMutant"] = kind end
    if sender and not md["PuppetMutantSender"] then md["PuppetMutantSender"] = sender end
    if zombie:getVariableBoolean("Hitman") then return end   -- NPC 오염 방지
    if not zombie:getVariableBoolean("PuppetMutantInit") then
        initMutant(zombie, kind)
        _a.pokeTag(zombie)                             -- 소환/부활 직후 잠깐 표기
    end
    _a.pokeTagOnHover(zombie)                          -- 조준+마우스 올림
    if zombie:isAttacking() then                       -- 나를 공격 중일 때
        local t = zombie:getTarget()
        if t and instanceof(t, "IsoPlayer") and t:isLocalPlayer() then
            _a.pokeTag(zombie)
        end
    end
    if kind == "screamer" then
        updateScreamer(zombie)
    elseif kind == "brute" then
        updateBrute(zombie)
    elseif kind == "roach" then
        updateRoach(zombie)
    end
end
Events.OnZombieUpdate.Add(applyMutant)

-- 죽으면 로컬 마크/쿨다운 정리 (+ 진단: 사망 시점 키 로깅 — 등록 키와
-- 비교해서 죽는 과정에서 pid 비트가 변형되는지 판별하기 위함)
Events.OnZombieDead.Add(function(zombie)
    local zid = zombie:getOnlineID()
    local kind = zombie:getModData()["PuppetMutant"]
        or regEntry(_pending[zid])
        or regEntry(_registry[mutantKey(zombie)])
    if kind then
        print("[PuppetMutant] dead " .. tostring(kind)
            .. " key=" .. mutantKey(zombie) .. " zid=" .. tostring(zid))
    end
    _pending[zid] = nil
    _nextScream[zid] = nil
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  네임태그: 특수좀비 머리 위 표기 (CDDA CDDA_ShowZombieType 이식)
--  트리거(각 100프레임 페이드): ① 소환/부활 직후  ② 조준 중 마우스 올림
--  ③ 좀비가 로컬 플레이어 공격  ④ 좀비를 타격
--  표기: 후원자가 있으면 "%1의 %2" ("테스트후원자의 브루트"), 없으면 이름만.
-- ═══════════════════════════════════════════════════════════════════════════
local TAG_TTL = 100

local NAME_KEY = {
    screamer = "IGUI_mutant_name_screamer",
    brute    = "IGUI_mutant_name_brute",
    roach    = "IGUI_mutant_name_roach",
    sprinter = "IGUI_mutant_name_sprinter",
}

local TAG_COLOR = {      -- 스크리머/브루트는 CDDA 원본 색, 로치는 바퀴 갈색
    brute    = {255, 0, 0},
    screamer = {139, 0, 81},
    roach    = {181, 101, 29},
    sprinter = {255, 165, 0},
}

local _showTags = {}     -- [onlineID] = { zombie=, ttl=, tdo=TextDrawObject }

-- 서버 샌드박스 스위치. 기존 Donation_ShowPanel/PrepDelay와 동일하게
-- 사용 시점에 읽는다 (SandboxVars는 파일 로드 시점엔 비어있음).
local function nameTagEnabled()
    local sv = SandboxVars and SandboxVars.Hitmans
    if sv and sv.Donation_MutantNameTag == false then return false end
    return true      -- 옵션 없음(구버전 세이브) -> 기본값: 표시
end

-- CDDA_GetScreenXY 이식: 월드좌표 -> 화면좌표 (줌 보정 포함)
local function screenXY(zombie, offY)
    local sx = IsoUtils.XToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)
    local sy = IsoUtils.YToScreen(zombie:getX(), zombie:getY(), zombie:getZ(), 0)
    sx = sx - IsoCamera.getOffX() - zombie:getOffsetX()
    sy = sy - IsoCamera.getOffY() - zombie:getOffsetY() - offY
    local zoom = getCore():getZoom(0)
    return sx / zoom, sy / zoom
end

local function pokeTag(zombie)
    if not nameTagEnabled() then return end
    local zid = zombie:getOnlineID()
    local t = _showTags[zid]
    if t then
        t.ttl = TAG_TTL
        t.zombie = zombie
    else
        _showTags[zid] = { zombie = zombie, ttl = TAG_TTL }
    end
end
_a.pokeTag = pokeTag

local function tagText(kind, sender)
    local name = getText(NAME_KEY[kind] or NAME_KEY.roach)
    if sender and sender ~= "" then
        return getText("IGUI_mutant_tag_owned", sender, name)
    end
    return name
end

-- 트리거 ②: 조준 중 마우스 올림 (applyMutant에서 특수좀비에 한해 호출)
local function pokeTagOnHover(zombie)
    local player = getPlayer()
    if not player or not player:IsAiming() then return end
    if not zombie:isAlive() or not player:CanSee(zombie) then return end
    local zx, zy = screenXY(zombie, 90)
    local mx, my = getMouseX(), getMouseY()
    if math.abs(zx - mx) < 15 and math.abs(zy - my) < 30 then
        pokeTag(zombie)
    end
end
_a.pokeTagOnHover = pokeTagOnHover

-- 트리거 ④: 타격 시 (CDDA_FuncOnHit과 동일 이벤트)
Events.OnWeaponHitCharacter.Add(function(attacker, target, _weapon, _damage)
    if not instanceof(target, "IsoZombie") then return end
    if not (attacker and instanceof(attacker, "IsoPlayer") and attacker:isLocalPlayer()) then return end
    if target:getModData()["PuppetMutant"] then
        pokeTag(target)
    end
end)

-- 렌더: CDDA와 동일하게 OnTick에서 배치드로우, ttl로 페이드아웃
local function renderTags()
    local player = getPlayer()
    for zid, t in pairs(_showTags) do
        local zombie = t.zombie
        local kind, sender = nil, nil
        if zombie and player and t.ttl > 0
            and zombie:isAlive() and player:CanSee(zombie) then
            kind   = zombie:getModData()["PuppetMutant"]
            sender = zombie:getModData()["PuppetMutantSender"]
        end
        if kind then
            local sx, sy = screenXY(zombie, 190)
            t.tdo = t.tdo or TextDrawObject.new()
            local c = TAG_COLOR[kind] or {255, 255, 255}
            local a = t.ttl / TAG_TTL
            t.tdo:setDefaultColors(c[1] / 255, c[2] / 255, c[3] / 255, a)
            t.tdo:setOutlineColors(0, 0, 0, a)
            t.tdo:ReadString(UIFont.Small, tagText(kind, sender), -1)
            t.tdo:AddBatchedDraw(sx, sy - t.tdo:getHeight(), true)
            t.ttl = t.ttl - 1
        else
            _showTags[zid] = nil
        end
    end
end
Events.OnTick.Add(renderTags)

return _a
