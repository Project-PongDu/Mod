-- ── 특수좀비 영속 레지스트리 (부활 유지의 핵심) ──────────────────────────────
-- persistentOutfitID는 좀비 외형을 사망->시체(reanimated.bin)->부활 내내
-- 유지시키는 영속 ID다. 단, 원시값은 모자 상태가 16번 비트로 박혀 있어
-- 모자가 벗겨지면 값이 변한다 -> 밴딧과 동일하게 HitmanUtils.GetZombieID로
-- 모자 비트를 마스킹한 정규화 ID를 키로 쓴다 (등록/조회 양쪽 동일 함수).
-- 글로벌 ModData는 서버 세이브에 저장되므로 서버 재시작 후 부활에도 유효.
local function mutantKey(zed)
    if HitmanUtils and HitmanUtils.GetZombieID then
        return tostring(HitmanUtils.GetZombieID(zed))
    end
    return tostring(zed:getPersistentOutfitID())
end

-- 레지스트리 항목: {["k"]=종류, ["s"]=후원자}. 구버전 문자열 항목과의
-- 호환을 위해 읽기는 반드시 regEntry를 거친다.
local function regEntry(v)
    if type(v) == "table" then return v["k"], v["s"] end
    return v, nil
end

local function registerMutant(zed, kind, sender)
    local key = mutantKey(zed)
    if not key then return end
    local reg = ModData.getOrCreate("PuppetMutants")
    reg[key] = { ["k"] = kind, ["s"] = sender }
    ModData.transmit("PuppetMutants")
    print("[PongDu][REG] register key=" .. tostring(key)
        .. " kind=" .. tostring(kind) .. " sender=" .. tostring(sender)
        .. " zid=" .. tostring(zed:getOnlineID()))
end

-- Make a zombie into a sprinter.
local function makeSprinter(a)
    local b = getSandboxOptions():getOptionByName("ZombieLore.Speed"):getValue()
    getSandboxOptions():set("ZombieLore.Speed", 1)
    a:makeInactive(true)
    a:makeInactive(false)
    local c = a.speedType or a:getVariableString("zombieWalkType")
    a:setWalkType("sprint" .. tostring(a.speedType))
    a:DoZombieStats()
    getSandboxOptions():set("ZombieLore.Speed", b)
    a:getModData()["isSprinter"] = true
    registerMutant(a, "sprinter")     -- 부활 유지용 영속 등록
    sendClientCommand("SpawnedSprinter", "isSprinter", {
        ["isSprinter"] = true,
        ["zedId"]      = a:getOnlineID(),
    })
end

-- Spawn zombies at (x,y,z), with optional sprinter/sender settings.
local function spawnZombies(x, y, z, amount, useHighStats, sprint, sender)
    amount       = amount or 1
    useHighStats = useHighStats ~= false
    sprint       = sprint or false

    local highCognition = 4
    local highMemory    = 5
    local highHearing   = 4

    local origCognition = getSandboxOptions():getOptionByName("ZombieLore.Cognition"):getValue()
    local origMemory    = getSandboxOptions():getOptionByName("ZombieLore.Memory"):getValue()
    local origHearing   = getSandboxOptions():getOptionByName("ZombieLore.Hearing"):getValue()
    local lastSpawned   = nil

    for n = 0, amount - 1 do
        if useHighStats then
            getSandboxOptions():set("ZombieLore.Cognition", highCognition)
            getSandboxOptions():set("ZombieLore.Memory",    highMemory)
            getSandboxOptions():set("ZombieLore.Hearing",   highHearing)
        end
        lastSpawned = addZombiesInOutfit(x, y, z, 1, nil, nil)
        if lastSpawned and lastSpawned:size() > 0 then
            lastSpawned:get(0):DoZombieStats()
            lastSpawned:get(0):makeInactive(true)
            lastSpawned:get(0):makeInactive(false)
        end
        if useHighStats then
            getSandboxOptions():set("ZombieLore.Cognition", origCognition)
            getSandboxOptions():set("ZombieLore.Memory",    origMemory)
            getSandboxOptions():set("ZombieLore.Hearing",   origHearing)
        end
        if lastSpawned and lastSpawned:size() > 0 then
            if sprint then
                lastSpawned:get(0):setWalkType("sprint4")
            else
                lastSpawned:get(0):setWalkType("walk")
            end
            if sender and sender ~= "" then
                lastSpawned:get(0):getModData()["_cs"] = sender .. getText("IGUI_donation_zombie_owner")
                lastSpawned:get(0):transmitModData()
            end
        end
    end
end

-- ── 뮤턴트 소환 (mutant_spawn) ────────────────────────────────────────────────
-- 스크리머/브루트/로치. CDDA 모드 의존 없음 — 서버는 스폰 + modData 마킹만
-- 하고, 스탯·행동(HP/스프린트/괴력/비명/밀치기/3배속 크롤)은 각 클라이언트의
-- 적용기(features/mutantspawn.lua, OnZombieUpdate)가 처리한다 (좀비 클라 권한).
local function spawnSpecialZombie(x, y, z, kind, sender)
    local zeds = addZombiesInOutfit(x, y, z, 1, nil, nil)
    if not zeds or zeds:size() == 0 then return false end
    local zed = zeds:get(0)
    zed:DoZombieStats()
    zed:makeInactive(true)
    zed:makeInactive(false)
    zed:getModData()["PuppetMutant"] = kind
    -- 서버측 소유 zid 스탬프: B41은 죽은 좀비의 IsoZombie 객체를 풀에 반환 후
    -- 재사용하는데 modData가 안 지워진다. 죽은 특좀 객체가 호드매니저 등으로
    -- 재활용되면 PuppetMutant가 딸려와 그 좀비 시체가 특좀으로 부활한다.
    -- 소유 zid를 박아두면, 살아있는 동안 아래 stale-스윕이 "md의 zid ≠ 현재
    -- zid"로 재활용 좀비를 판별해 md를 지운다 -> 시체가 깨끗해짐.
    zed:getModData()["PuppetMutantZid"] = zed:getOnlineID()
    if sender and sender ~= "" then
        zed:getModData()["_cs"] = sender .. getText("IGUI_donation_zombie_owner")
        -- 원본 sender도 modData에 저장 -> 시체에 계승되어 RiseUp이 부활 시
        -- 좌표 없이도 후원자 이름표를 복원할 수 있다 (이동-무관).
        zed:getModData()["PuppetMutantSender"] = sender
    end
    zed:transmitModData()
    -- 서버발 zombie transmitModData는 클라에 전달이 안 되므로(스프린터의
    -- SpawnedSprinter 죽은 코드와 같은 함정) 폭격과 동일한 검증된 채널로
    -- 전 클라에 zedId+kind를 브로드캐스트 -> 클라 적용기가 onlineID로 매칭.
    sendServerCommand("PEvents", "MutantMark", {
        ["zedId"]  = zed:getOnlineID(),
        ["kind"]   = kind,
        ["sender"] = sender or "",
    })
    registerMutant(zed, kind, sender) -- 부활 유지용 영속 등록 (후원자 포함)
    return true
end

-- 부활 좀비 재등록: 클라 적용기가 부활 좀비에 능력을 입힌 뒤 그놈의 "새" pid를
-- 보고하면 레지스트리에 추가 -> 다음 사망->부활 사이클도 자동 유지된다.
-- 여러 클라가 중복 보고해도 멱등 (값 같으면 transmit 생략).
Events.OnClientCommand.Add(function(module, command, player, data)
    if module == "PEvents" and command == "MutantReregister" then
        local key    = tostring(data and data["key"] or "")
        local kind   = data and data["kind"]
        local sender = data and data["sender"]
        if key ~= "" and key ~= "N/A" and kind then
            local reg = ModData.getOrCreate("PuppetMutants")
            local ck, cs = regEntry(reg[key])
            if ck ~= kind or cs ~= sender then
                reg[key] = { ["k"] = kind, ["s"] = sender }
                ModData.transmit("PuppetMutants")
            end
        end
    end
end)

-- Handle "PEvents / ZedSpawn" client command.
local function srvlog(msg)
    local w = getFileWriter("server_log.txt", true, true)
    if w then w:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg) .. "\n") w:close() end
end

local function onClientCommand(module, command, player, data)
    if module == "PEvents" and command == "ZedSpawn" then
        srvlog("ZedSpawn RECEIVED on server")
        local offsetX = ZombRand(-4, 4)
        local offsetY = ZombRand(-4, 4)
        local x       = tonumber(data["ZedX"]) + offsetX
        local y       = tonumber(data["ZedY"]) + offsetY
        local z       = tonumber(data["ZedZ"])
        local amount  = tonumber(data["amount"])
        local sprint  = tonumber(data["sprint"])
        srvlog("coords x="..tostring(x).." y="..tostring(y).." z="..tostring(z).." amount="..tostring(amount).." sprint="..tostring(sprint))
        local isSprint = nil
        if sprint == 0 then isSprint = false
        elseif sprint == 1 then isSprint = true end
        local sender = data["sender"] or ""
        local ok, err = pcall(function()
            spawnZombies(x, y, z, amount, true, isSprint, sender)
        end)
        if ok then srvlog("spawnZombies OK")
        else srvlog("spawnZombies ERROR: " .. tostring(err)) end
    elseif module == "PEvents" and command == "MutantSpawn" then
        local x    = tonumber(data["ZedX"])
        local y    = tonumber(data["ZedY"])
        local z    = tonumber(data["ZedZ"]) or 0
        local kind = tostring(data["kind"] or "roach")
        srvlog("MutantSpawn kind=" .. kind .. " x=" .. tostring(x) .. " y=" .. tostring(y))
        if x and y then
            local ok, err = pcall(function()
                spawnSpecialZombie(x, y, z, kind, data["sender"] or "")
            end)
            if ok then srvlog("MutantSpawn OK")
            else srvlog("MutantSpawn ERROR: " .. tostring(err)) end
        end
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- ── DOServer command handlers ─────────────────────────────────────────────────
DOServer = DOServer or {}
DOServer["Schedule"] = DOServer["Schedule"] or {}

DOServer["Schedule"]["Kaboom"] = function(player, data)
    local cx = player:getX()
    local cy = player:getY()
    local e  = player:getCell()
    local r  = tonumber(data["r"]) or 80
    -- Burn walls and floors in radius.
    for floor = 0, 1 do
        for dy = -r, r do
            for dx = -r, r do
                local wx = cx + dx
                local wy = cy + dy
                local dist = math.sqrt(math.pow(wx - cx, 2) + math.pow(wy - cy, 2))
                if dist < r then
                    local sq = e:getGridSquare(wx, wy, floor)
                    if sq then
                        if floor == 0 and ZombRand(100) < 80 then sq:BurnWalls(false) end   -- 바닥 탈 확률: 80%
                        if ZombRand(100) < 50 and sq:isFree(false) then                     -- 바닥 잿더미 확률: 50%
                            local obj = IsoObject.new(sq, "floors_burnt_01_1", "")
                            -- transmitAddObjectToSquare가 로컬 추가(AddTileObject)와 클라 전파를
                            -- 한 번에 처리한다. AddSpecialObject를 먼저 부르면 obj가 이미 Objects에
                            -- 들어가 가드(!Objects.contains)에 걸려 전파가 스킵되므로 호출하지 않는다.
                            -- index=-1 = 리스트 끝에 append (AddTileObject에서 안전 처리).
                            sq:transmitAddObjectToSquare(obj, -1)
                        end
                    end
                end
            end
        end
    end
    -- 좀비 킬은 서버에서 하지 않는다.
    -- B41 멀티에서 좀비는 클라이언트 권한(client-authoritative)이므로 서버사이드
    -- setHealth/becomeCorpse는 소유 클라의 동기화에 덮여 저장에 반영되지 않는다
    -- (재접속 시 일반좀비로 부활하는 원인). 대신 폭발 좌표/반경을 전 클라에
    -- 브로드캐스트하고, 각 클라가 자기 소유 좀비를 정상 킬 시퀀스로 죽인다
    -- (bombard.lua의 killZombiesAround). 도네이터 본인은 이미 로컬에서 처리했으므로 제외.
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            sendServerCommand(p, "Schedule", "NearbyExplosion", {x = cx, y = cy, r = r})
        end
    end
end

DOServer["Schedule"]["PlayExplosion"] = function(player, data)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            sendServerCommand(p, "Schedule", "PlayExplosion", {})
        end
    end
end

DOServer["Schedule"]["PlayAlert"] = function(player, data)
    local cx = tonumber(data["x"]) or player:getX()
    local cy = tonumber(data["y"]) or player:getY()
    local r  = tonumber(data["r"]) or 40
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            local dist = math.sqrt(math.pow(p:getX() - cx, 2) + math.pow(p:getY() - cy, 2))
            if dist < r then
                sendServerCommand(p, "Schedule", "PlayAlert", {})
            end
        end
    end
end

-- ── 사망 좌표 마크 (버그① 근본 수정) ──────────────────────────────────────────
-- HitmanUtils.GetZombieID(corpse)는 IsoDeadBody에 getPersistentOutfitID가
-- 아예 없어서 100% 예외를 던진다(Object tried to call nil in GetZombieID —
-- 서버 로그로 확증, readable=0/marked=0 항상). 즉 "시체가 특수좀비였는지"를
-- pid로 판별하는 건 구조적으로 불가능. kind를 아는 유일한 시점은 클라의
-- OnZombieDead뿐이므로, 죽는 순간 좌표+kind+sender를 서버가 받아 저장해두고
-- RiseUp이 시체의 좌표로 조회한다 (pid 대신 좌표가 진짜 키).
local _deathMarks = {}
local DEATHMARK_MS = 600000   -- 10분. 그 안에 강령술 안 하면 자연 소멸.

Events.OnClientCommand.Add(function(module, command, player, data)
    if module == "PEvents" and command == "MutantDeathMark" then
        local x, y = tonumber(data and data["x"]), tonumber(data and data["y"])
        local kind = data and data["kind"]
        if x and y and kind then
            _deathMarks[#_deathMarks + 1] = {
                x = x, y = y, z = tonumber(data["z"]) or 0,
                kind = kind, sender = data["sender"],
                expire = getTimestampMs() + DEATHMARK_MS,
            }
            print("[PongDu][DeathMark] stored kind=" .. tostring(kind)
                .. " @" .. tostring(x) .. "," .. tostring(y))
        end
    end
end)

-- 시체 스퀘어 좌표(±1)로 사망 마크 매칭·소모. 여러 시체가 겹치면 먼저
-- 등록된 순서로 하나씩 소모 (드문 동시사망 케이스의 알려진 한계).
local function matchDeathMark(sq, floor)
    local sx, sy = sq:getX(), sq:getY()
    local now = getTimestampMs()
    for i = #_deathMarks, 1, -1 do
        local m = _deathMarks[i]
        if now > m.expire then
            table.remove(_deathMarks, i)
        elseif math.abs(m.x - sx) <= 1 and math.abs(m.y - sy) <= 1 and m.z == floor then
            table.remove(_deathMarks, i)
            return m.kind, m.sender
        end
    end
    return nil
end


-- 시체는 B41 MP에서 서버 권한(청크 데이터 + reanimated.bin 저장, 바닐라 디버그
-- 시체제거도 /removezombies 서버 커맨드 경유)이므로 서버 한 곳에서만 처리해
-- 클라이언트별 중복 부활을 원천 차단한다. reanimateNow()는 바닐라 디버그 메뉴
-- "Reanimate (Zombie)"가 쓰는 강제 부활 API — 샌드박스 Reanimate 설정과 무관하게
-- 즉시 부활시킨다 (DebugContextMenu.OnReanimateCorpse 와 동일).
-- 라이즈 업 후처리 스윕 대상 목록 (아래 EveryOneMinute 스윕에서 소비)
local _riseSweeps = {}

-- reanimateNow() 직후 방금 부활한 좀비를 스퀘어에서 찾는다.
-- 바닐라 디버그(doDebugZombieMenu)와 동일 패턴: getMovingObjects + IsoZombie.
-- 한 스퀘어에서 여러 시체가 부활할 수 있으므로 이미 잡은 onlineID는 handled로 스킵.
local function findFreshZombie(sq, handled)
    local mo = sq:getMovingObjects()
    if not mo then return nil end
    for i = 0, mo:size() - 1 do
        local o = mo:get(i)
        if instanceof(o, "IsoZombie") and o:isAlive()
            and not handled[o:getOnlineID()] then
            handled[o:getOnlineID()] = true
            return o
        end
    end
    return nil
end

DOServer["Schedule"]["RiseUp"] = function(player, data)
    local cx = tonumber(data["x"]) or player:getX()
    local cy = tonumber(data["y"]) or player:getY()
    local r  = tonumber(data["r"]) or 55
    local cell = player:getCell()
    local r2 = r * r
    local raised = 0
    local readable = 0
    local marked = 0
    local handled = {}                     -- 이번 RiseUp에서 이미 잡은 부활 좀비 onlineID
    print("[PongDu][RiseUp] START x=" .. tostring(cx) .. " y=" .. tostring(cy) .. " r=" .. tostring(r))
    for floor = 0, 7 do                    -- 다층 건물 내부 시체까지 포함
        for dy = -r, r do
            for dx = -r, r do
                if dx * dx + dy * dy < r2 then
                    local sq = cell:getGridSquare(cx + dx, cy + dy, floor)
                    if sq then
                        -- reanimateNow()가 시체를 스퀘어에서 제거하므로
                        -- 순회 중 리스트 변형을 피하려고 먼저 수집 후 발동
                        local smo = sq:getStaticMovingObjects()
                        local bodies = nil
                        for i = 0, smo:size() - 1 do
                            local o = smo:get(i)
                            if instanceof(o, "IsoDeadBody") then
                                bodies = bodies or {}
                                bodies[#bodies + 1] = o
                            end
                        end
                        if bodies then
                            for _, b in ipairs(bodies) do
                                -- ★이동-무관 판별: 시체(IsoDeadBody) 자신의 modData를
                                -- 직독한다. 소환 때 서버가 박은 PuppetMutant/Sender가
                                -- 좀비->시체 전환에 자동 계승됨(프로브로 확증:
                                -- getOK=true, PuppetMutant=brute/roach). modData는
                                -- 객체를 따라가므로 시체를 어디로 옮겨도 정확히 판별.
                                local cmd = b:getModData()
                                local kind = cmd and cmd["PuppetMutant"]
                                local sender = cmd and (cmd["PuppetMutantSender"] or "")
                                -- 좌표 death-mark 폴백 제거: 일반좀비 시체는 modData가
                                -- 없어 폴백으로 넘어갔고, 그 자리에 남은 특좀 마크에 걸려
                                -- 일반좀비가 특좀으로 부활하는 역방향 오탐이 났다(로그:
                                -- kind=... from fallback). 시체 modData는 진짜 특좀이면
                                -- 100% 계승되므로(from modData 검증됨) 폴백은 순수
                                -- 오탐원이라 삭제. 일반좀비 시체 -> kind=nil -> 일반 부활.
                                print("[PongDu][RiseUp] corpse @" .. tostring(sq:getX())
                                    .. "," .. tostring(sq:getY())
                                    .. " kind=" .. tostring(kind))
                                if kind then readable = readable + 1 end
                                b:reanimateNow()
                                raised = raised + 1
                                -- ── 핵심 수정 ────────────────────────────────
                                -- 방금 부활한 좀비를 서버에서 직접 잡아서:
                                --  ① setReanimateTimer(0) : 부활 예약 상태를 이 자리에서
                                --     즉시 제거 -> 다음 사망 시 시체에 reanimateTime이
                                --     안 박힌다. RiseSweep(반경·시간 제한)의 사각을
                                --     원천 제거 (버그②: 재부팅 후 재부활).
                                --  ② registerMutant(nz,...) : 서버 권위 pid로 즉시 재등록.
                                --     기존엔 클라가 MutantReregister로 재등록했는데, 클라가
                                --     본 부활좀비 pid와 서버가 다음 사이클에 시체에서 읽는
                                --     pid가 어긋나면(동기화 레이스) 다음 부활이 일반좀비가
                                --     됐다. 등록·조회를 둘 다 서버 pid(mutantKey)로 통일해
                                --     구조적으로 일치시킨다 (버그①: 2회차 부활 일반화).
                                local nz = findFreshZombie(sq, handled)
                                if nz then
                                    -- ★확증①: reanimateNow 후 좀비가 같은 sq에 즉시 올라오는가.
                                    --   NOT FOUND가 계속 찍히면 서버 재등록/타이머클리어가
                                    --   안 걸린다는 뜻 -> reanimateNow 반환값 경로로 전환 필요.
                                    local before = -1
                                    pcall(function() before = nz:getReanimateTimer() end)
                                    pcall(function() nz:setReanimateTimer(0) end)
                                    local after = -1
                                    pcall(function() after = nz:getReanimateTimer() end)
                                    print("[PongDu][RiseUp] fresh zombie zid=" .. tostring(nz:getOnlineID())
                                        .. " newKey=" .. tostring(mutantKey(nz))
                                        .. " timer " .. tostring(before) .. "->" .. tostring(after))
                                    if kind then registerMutant(nz, kind, sender) end
                                else
                                    print("[PongDu][RiseUp] fresh zombie NOT FOUND on sq "
                                        .. tostring(sq:getX()) .. "," .. tostring(sq:getY()))
                                end
                                if kind then
                                    marked = marked + 1
                                    sendServerCommand("PEvents", "MutantRevive", {
                                        ["x"]      = sq:getX(),
                                        ["y"]      = sq:getY(),
                                        ["z"]      = floor,
                                        ["kind"]   = kind,
                                        ["sender"] = sender or "",
                                        ["key"]    = nz and mutantKey(nz) or "N/A",
                                    })
                                    srvlog("RiseUp revive-mark " .. kind .. " @" .. sq:getX() .. "," .. sq:getY())
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    srvlog("RiseUp: " .. raised .. " corpses, " .. readable .. " death-mark hits, " .. marked .. " special marks, around " .. cx .. "," .. cy .. " r=" .. r)
    print("[PongDu][RiseUp] DONE raised=" .. raised .. " readable=" .. readable .. " marked=" .. marked)
    -- 요약을 클라에도 쏴서 client console.txt만으로 전 과정 관측 가능하게
    sendServerCommand("PEvents", "MutantReviveDebug", {
        ["total"] = raised, ["readable"] = readable, ["marked"] = marked,
    })
    -- 부활 예약 청소 스윕 예약 (아래 RiseSweep 참고). 부활 좀비들이 물고 있는
    -- ReanimateTimer를 지워서 다음 사망 시 시체에 reanimateTime이 예약되는
    -- 것을 원천 차단한다. 추적 반경은 1분 사이 이동 여유분(+60)을 더한다.
    if raised > 0 then
        _riseSweeps[#_riseSweeps + 1] = {
            x = cx, y = cy, r = r + 60,
            left = 3,                      -- EveryOneMinute 3회 스윕 후 소멸
        }
    end
end

-- ── 라이즈 업 후처리: 부활 예약 상태 청소 ────────────────────────────────────
-- 문제: reanimateNow()로 부활한 좀비는 엔진의 ReanimateTimer(>0)를 물고 있고,
-- 이 상태로 다시 죽으면 새 IsoDeadBody에 reanimateTime(부활 예약 시각)이
-- 박힌다. reanimateTime은 청크 세이브에 직렬화되므로 서버 재부팅 후 로드되면
-- 예약 시각이 이미 지나 있어 시체가 다시 일어난다 ("한 번 되살렸던 애들만
-- 재부팅 후 부활" 증상). 2중 방어로 차단:
--   ① RiseSweep  : 부활 직후 주변 좀비의 ReanimateTimer를 0으로 — 원천 차단
--   ② LoadGridsquare : 로드되는 좀비 시체의 reanimateTime을 0으로 —
--                      이미 세이브에 예약이 박힌 기존 오염 시체까지 소급 무효화

-- ── stale md 정리 (서버 풀 재활용 방어) ──────────────────────────────────────
-- B41은 죽은 좀비의 IsoZombie 객체를 풀에 반환 후 재사용하는데 modData를
-- 안 지운다. 죽은 특좀 객체가 호드매니저 등으로 재활용되면 PuppetMutant가
-- 딸려와 그 좀비 시체가 특좀으로 부활한다.
--
-- 왜 폴링인가(설계 근거): 바닐라엔 좀비/시체 '생성 순간' 훅이 없고
-- (OnZombieCreate 부재, OnObjectAdded는 플레이어 설치물 전용), OnZombieUpdate는
-- MP에서 '클라 권한' 좀비(플레이어 근처)엔 서버측 발화를 안 한다(로그로 확인:
-- 스트리머 근처 재활용 5마리가 새어나감). getCell():getZombieList()만이 권한과
-- 무관하게 셀의 전 좀비를 포함하므로, 이 리스트를 촘촘히 순회하는 것이 서버가
-- 재활용 좀비를 잡을 수 있는 유일한 신뢰 경로다. 좀비가 죽기 전에 정리되면
-- 시체가 깨끗해져 RiseUp이 일반좀비로 판정한다.
local _lastStaleSweep = 0
local STALE_SWEEP_MS = 500       -- 0.5초. 스폰~사살 사이에 1회 이상 걸리게.
local function staleSweep()
    local now = getTimestampMs()
    if now - _lastStaleSweep < STALE_SWEEP_MS then return end
    _lastStaleSweep = now
    local cell = getCell()
    if not cell then return end
    local zeds = cell:getZombieList()
    if not zeds then return end
    local wiped = 0
    for i = 0, zeds:size() - 1 do
        local z = zeds:get(i)
        local md = z:getModData()
        if md["PuppetMutant"] and md["PuppetMutantZid"] ~= z:getOnlineID() then
            md["PuppetMutant"] = nil
            md["PuppetMutantSender"] = nil
            md["PuppetMutantZid"] = nil
            md["_cs"] = nil
            wiped = wiped + 1
        end
    end
    if wiped > 0 then
        print("[PongDu][StaleSweep] wiped stale PuppetMutant from " .. wiped .. " recycled zombies")
    end
end
Events.OnTick.Add(staleSweep)

Events.EveryOneMinute.Add(function()
    if #_riseSweeps == 0 then return end
    local cell = getCell()
    if not cell then return end
    local zeds = cell:getZombieList()
    if not zeds then return end
    local cleared = 0
    for i = 0, zeds:size() - 1 do
        local z = zeds:get(i)
        local ok, timer = pcall(function() return z:getReanimateTimer() end)
        if ok and timer and timer > 0 then
            local zx, zy = z:getX(), z:getY()
            for _, m in ipairs(_riseSweeps) do
                if math.abs(zx - m.x) <= m.r and math.abs(zy - m.y) <= m.r then
                    z:setReanimateTimer(0)
                    cleared = cleared + 1
                    break
                end
            end
        end
    end
    if cleared > 0 then
        srvlog("RiseSweep: cleared ReanimateTimer on " .. cleared .. " zombies")
        print("[PongDu][RiseSweep] cleared ReanimateTimer on " .. cleared .. " zombies (backstop)")
    end
    for i = #_riseSweeps, 1, -1 do
        _riseSweeps[i].left = _riseSweeps[i].left - 1
        if _riseSweeps[i].left <= 0 then
            table.remove(_riseSweeps, i)
        end
    end
end)

-- ② 시체 로드 시 부활 예약 무효화. 플레이어 시체(감염 사망 -> 좀비화)는
--    바닐라의 정상 부활 경로이므로 건드리지 않는다. 좀비 시체는 바닐라에서
--    부활 예약이 걸릴 일이 없으므로 0으로 밀어도 부작용 없음.
Events.LoadGridsquare.Add(function(sq)
    local smo = sq and sq:getStaticMovingObjects()
    if not smo then return end
    for i = 0, smo:size() - 1 do
        local o = smo:get(i)
        if instanceof(o, "IsoDeadBody") and not o:isPlayer() then
            pcall(function()
                -- ★버그2 확증: 로드되는 좀비 시체가 실제로 부활 예약(reanimateTime>0)
                --   또는 fakeDead=true를 물고 있는지 정리 '전에' 찍는다. 오염된
                --   좀비 시체만 골라 로그 -> 재부팅 재부활의 직접 증거.
                local rt = -1
                pcall(function() rt = o:getReanimateTime() end)   -- 게터 없으면 -1 유지
                local fd = o:isFakeDead()
                if (rt and rt > 0) or fd then
                    print("[PongDu][LoadGrid] tainted corpse @"
                        .. tostring(sq:getX()) .. "," .. tostring(sq:getY())
                        .. " reanimateTime=" .. tostring(rt) .. " fakeDead=" .. tostring(fd)
                        .. " -> sanitizing")
                end
                o:setReanimateTime(0)
                -- reanimateTime(0)의 엔진 해석이 '비활성'인지 '즉시'인지 확실치 않아
                -- 결정적 플래그로 이중 차단: fakeDead=false면 그 시체는 '진짜 시체'가
                -- 되어 자발적 재부활 대상에서 빠진다(디버그 메뉴의 Reanimate(Player)
                -- 경로). 의도적 강령술(reanimateNow)은 fakeDead와 무관하게 계속 작동.
                o:setFakeDead(false)
            end)
        end
    end
end)

local function onClientCommandDOServer(module, command, player, data)
    if DOServer[module] and DOServer[module][command] then
        DOServer[module][command](player, data)
    end
end
Events.OnClientCommand.Add(onClientCommandDOServer)

-- ── Donation queue reader: REMOVED ───────────────────────────────────────────
-- Donation polling now happens CLIENT-SIDE (see DonationReceiver.lua). Each streamer's
-- client reads its own rewards.txt and applies the effect to itself, so the
-- server no longer reads donation_queue.txt or pushes Donation/Apply.
-- Zombie spawning (PEvents/ZedSpawn) and DOServer Schedule handlers above stay.

-- ── Donation stats collector ─────────────────────────────────────────────────
-- Each client forwards the raw donation lines it reads (DonationStats/Record).
-- The host labels them with the sender's account name and appends to a single
-- file on the SERVER machine:  Zomboid/Lua/profits.txt
--   line format (tab-separated):  <streamer username>\t<raw rewards.txt line>
-- Aggregation (per-streamer / per-viewer totals, Excel export) is done later by
-- an external Python script that reads profits.txt.
local PROFITS_FILE = "profits.txt"

local function onDonationStats(module, command, player, data)
    if module ~= "DonationStats" or command ~= "Record" then return end
    if not player or not data or not data.line then return end
    local streamer = player:getUsername() or "unknown"
    local w = getFileWriter(PROFITS_FILE, true, true)   -- create, append
    if w then
        w:write(streamer .. "\t" .. tostring(data.line) .. "\r\n")
        w:close()
    end
end
Events.OnClientCommand.Add(onDonationStats)

