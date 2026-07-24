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
    -- (구 "SpawnedSprinter" 송신은 수신처가 없는 죽은 코드라 제거.
    --  이름표/스탯 적용은 아래 PongDuMutant/MutantMark 브로드캐스트가 담당.)
end

-- Spawn zombies at (x,y,z), with optional sprinter/sender settings.
local function spawnZombies(x, y, z, amount, useHighStats, sprint, sender)
    amount       = amount or 1
    useHighStats = useHighStats ~= false
    sprint       = sprint or false
    local spawnedIds = {}   -- 어그로 스코프용: 이번 도네가 만든 좀비 onlineID

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
            spawnedIds[#spawnedIds + 1] = lastSpawned:get(0):getOnlineID()
            if sprint then
                lastSpawned:get(0):setWalkType("sprint4")
                -- 뛰좀도 특좀 파이프라인에 태워 부활 시 뜀을 복원한다.
                -- sprint는 walkType(비영속)이라 reanimateNow 후 일반 걸음이 되는데,
                -- PuppetMutant="sprinter"를 시체에 계승시키면 RiseUp이 이를 읽어
                -- MutantRevive를 브로드캐스트하고, 클라 initMutant의 sprinter 분기가
                -- 부활 좀비에 sprint walkType을 재적용한다. zid 스탬프 필수 —
                -- 안 하면 staleSweep이 즉시 지운다.
                local zsp = lastSpawned:get(0)
                zsp:getModData()["PuppetMutant"] = "sprinter"
                zsp:getModData()["PuppetMutantZid"] = zsp:getOnlineID()
                if sender and sender ~= "" then
                    zsp:getModData()["PuppetMutantSender"] = sender
                end
                -- 특좀과 동일하게 MutantMark 브로드캐스트 -> 소환 즉시 클라가
                -- "누구의 스프린터" 이름표를 표시(부활 때만 뜨던 것을 스폰부터).
                sendServerCommand("PongDuMutant", "MutantMark", {
                    ["zedId"]  = zsp:getOnlineID(),
                    ["kind"]   = "sprinter",
                    ["sender"] = sender or "",
                })
            else
                lastSpawned:get(0):setWalkType("walk")
            end
            if sender and sender ~= "" then
                lastSpawned:get(0):getModData()["_cs"] = sender .. getText("IGUI_donation_zombie_owner")
                lastSpawned:get(0):transmitModData()
            end
        end
    end
    return spawnedIds
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
    -- 구 SpawnedSprinter 죽은 코드와 같은 함정 -- 해당 송신은 제거됨) 폭격과 동일한 검증된 채널로
    -- 전 클라에 zedId+kind를 브로드캐스트 -> 클라 적용기가 onlineID로 매칭.
    sendServerCommand("PongDuMutant", "MutantMark", {
        ["zedId"]  = zed:getOnlineID(),
        ["kind"]   = kind,
        ["sender"] = sender or "",
    })
    registerMutant(zed, kind, sender) -- 부활 유지용 영속 등록 (후원자 포함)
    return zed:getOnlineID()   -- 어그로 스코프용 (실패 경로는 위에서 false)
end

-- 부활 좀비 재등록: 클라 적용기가 부활 좀비에 능력을 입힌 뒤 그놈의 "새" pid를
-- 보고하면 레지스트리에 추가 -> 다음 사망->부활 사이클도 자동 유지된다.
-- 여러 클라가 중복 보고해도 멱등 (값 같으면 transmit 생략).
Events.OnClientCommand.Add(function(module, command, player, data)
    if module == "PongDuMutant" and command == "MutantReregister" then
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

-- Handle "PongDuZombie / ZedSpawn" client command.
local function srvlog(msg)
    local w = getFileWriter("server_log.txt", true, true)
    if w then w:write(os.date("%Y-%m-%d %H:%M:%S") .. " - " .. tostring(msg) .. "\n") w:close() end
end

-- 소환 좀비 플레이어 어그로 창 브로드캐스트 (v4: zid 화이트리스트 스코프).
-- 클라 features/aggro.lua가 수신 -> 창 유지시간(dur) 동안 zeds 목록에 있는
-- 자기 소유 좀비에게만 비강제 spotted 인계(근거리) / per-zombie 사운드응답
-- 유인(원거리)을 건다. 반경 필터가 아니라 id 필터이므로 도네 효과와 무관한
-- 주변 좀비는 건드리지 않는다.
-- target이 박히면 ZombieGroupManager(랠리 무리배회)가 못 채가므로, 대량 스폰
-- 좀비가 랠리 척력 벡터를 쫓아 방사형으로 흩어지는 현상을 차단한다.
-- 좀비는 클라 권한이라 서버측 setTarget은 소유 클라 동기화에 덮인다 — 반드시
-- 이 브로드캐스트 -> 클라 적용 경로여야 한다.
-- ids=nil 허용: 강령술은 서버가 부활 좀비 zid를 모르므로(reanimate가 다음
-- 틱) 빈 창만 열고, 클라 riseup.lua가 addLocalIds()로 채운다. src로 구분.
local function broadcastAggro(player, ids, durMs, src)
    if not player then return end
    sendServerCommand("PongDuAggro", "Window", {
        ["zeds"] = ids,
        ["dur"]  = durMs,
        ["pid"]  = player:getOnlineID(),
        ["src"]  = src or "?",
    })
end

local function onClientCommand(module, command, player, data)
    if module == "PongDuZombie" and command == "ZedSpawn" then
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
        local spawnedIds
        local ok, err = pcall(function()
            spawnedIds = spawnZombies(x, y, z, amount, true, isSprint, sender)
        end)
        if ok then
            srvlog("spawnZombies OK ids=" .. tostring(spawnedIds and #spawnedIds or 0))
            broadcastAggro(player, spawnedIds, 8000, "spawn")
        else srvlog("spawnZombies ERROR: " .. tostring(err)) end
    elseif module == "PongDuMutant" and command == "MutantSpawn" then
        local x    = tonumber(data["ZedX"])
        local y    = tonumber(data["ZedY"])
        local z    = tonumber(data["ZedZ"]) or 0
        local kind = tostring(data["kind"] or "roach")
        srvlog("MutantSpawn kind=" .. kind .. " x=" .. tostring(x) .. " y=" .. tostring(y))
        if x and y then
            local zid
            local ok, err = pcall(function()
                zid = spawnSpecialZombie(x, y, z, kind, data["sender"] or "")
            end)
            if ok then
                srvlog("MutantSpawn OK zid=" .. tostring(zid))
                if zid then broadcastAggro(player, { zid }, 8000, "mutant") end
            else srvlog("MutantSpawn ERROR: " .. tostring(err)) end
        end
    end
end
Events.OnClientCommand.Add(onClientCommand)

-- ── DOServer command handlers ─────────────────────────────────────────────────
DOServer = DOServer or {}
DOServer["PongDuBombard"]  = DOServer["PongDuBombard"]  or {}
DOServer["PongDuRiseUp"]   = DOServer["PongDuRiseUp"]   or {}
DOServer["PongDuDonation"] = DOServer["PongDuDonation"] or {}
DOServer["PongDuFireSupport"] = DOServer["PongDuFireSupport"] or {}

-- ── 폭격 반경 내 차량 파괴 ────────────────────────────────────────────────────
-- setScript()로 불탄 차량 스크립트를 씌우는 방식은 바닐라에 Burnt 변형이
-- 19종밖에 없어 전 차종을 커버하지 못하므로, 파츠 단위로 처리한다.
-- 차량은 좀비와 달리 서버 권위이므로 서버에서 변경 후 transmit*()으로 전파.
local BOMBARD_DOOR_STRIP_CHANCE = 50   -- 문짝(후드/트렁크 포함)이 뜯겨나갈 확률(%)

-- 파츠 하나를 바닐라 uninstall 경로 그대로 뜯어낸다.
-- (VehicleCommands.uninstallPart / VehicleUtils.RemoveTire와 동일한 순서)
--   setInventoryItem(nil) -> uninstall.complete 콜백 -> transmitPartItem
-- setInventoryItem(nil)은 itemContainer를 건드리지 않으므로 트렁크/시트/
-- 글로브박스 내용물은 영향 없음(VehiclePart.java 134번 라인 확인).
local function stripVehiclePart(v, part)
    local item = part:getInventoryItem()
    if not item then return false end
    part:setInventoryItem(nil)
    local tbl = part:getTable("uninstall")
    if tbl and tbl.complete and VehicleUtils and VehicleUtils.callLua then
        VehicleUtils.callLua(tbl.complete, v, part, item)
    end
    v:transmitPartItem(part)
    return true
end

local function wreckVehiclesAround(cell, cx, cy, r)
    if not cell then return end
    local vehicles = cell:getVehicles()
    if not vehicles then return end
    local wrecked, damaged, glass, doors = 0, 0, 0, 0
    for i = 0, vehicles:size() - 1 do
        local v = vehicles:get(i)
        if v and not v:isRemovedFromWorld() then
            local dist = math.sqrt(math.pow(v:getX() - cx, 2) + math.pow(v:getY() - cy, 2))
            if dist < r then
                for pi = 0, v:getPartCount() - 1 do
                    local part = v:getPartByIndex(pi)
                    if part then
                        local ok, err = pcall(function()
                            local window = part:getWindow()
                            local door   = part:getDoor()

                            -- 문짝(승하차문 + 후드 EngineDoor + 트렁크문 TrunkDoor)은
                            -- 확률적으로 통째로 뜯어낸다.
                            if door ~= nil and ZombRand(100) < BOMBARD_DOOR_STRIP_CHANCE then
                                if stripVehiclePart(v, part) then doors = doors + 1 end
                            end

                            -- 창문/유리는 뜯어내지 않고 "깨진 상태"로 만든다.
                            -- VehiclePart.damage()가 window 유무를 알아서 분기한다
                            -- (VehiclePart.java 832번). window 쪽으로 가면 유리 파편
                            -- 생성 + SmashWindow 사운드 + transmitPartWindow까지 처리됨
                            -- (VehicleWindow.java 79번, 서버 브랜치).
                            -- 창문이 열려 있으면 isHittable()이 false라 damage가 먹지 않으므로
                            -- 먼저 닫아준다.
                            if window ~= nil and window:isOpen() then
                                window:setOpen(false)
                                v:transmitPartWindow(part)
                            end

                            if part:getCondition() > 0 then
                                part:damage(100)
                                if window ~= nil then glass = glass + 1 end
                            end

                            -- damage()가 안 먹은 파츠(열린 창문 등)는 강제로 0.
                            if part:getCondition() > 0 then
                                part:setCondition(0)
                                v:transmitPartCondition(part)
                            end
                            damaged = damaged + 1
                        end)
                        if not ok then
                            srvlog("wreckVehicle part ERROR id=" .. tostring(part:getId()) .. " " .. tostring(err))
                        end
                    end
                end
                -- 폐차 연출: 녹 최대치 + 데미지 텍스처 갱신.
                -- setRust/transmitRust는 바닐라 Commands.setRust와 동일한 경로.
                pcall(function()
                    v:setRust(1.0)
                    v:transmitRust()
                    v:doDamageOverlay()
                end)
                wrecked = wrecked + 1
            end
        end
    end
    srvlog("wreckVehiclesAround done vehicles=" .. tostring(wrecked)
        .. " parts=" .. tostring(damaged)
        .. " glassSmashed=" .. tostring(glass)
        .. " doorsStripped=" .. tostring(doors))
end

-- ── 화력 지원 / 저격 ─────────────────────────────────────────────────────────
-- 대상 선정을 서버가 하는 이유: 킬 자체는 좀비 소유 클라가 해야 하지만
-- (B41 MP 좀비는 클라 권한), 각 클라가 독립적으로 "가까운 7마리"를 뽑으면
-- 자기 소유 좀비 기준이라 총합이 7을 훌쩍 넘는다. 폭격처럼 "반경 전체"가
-- 아니라 "정확히 N마리"가 스펙이므로 선정은 서버 권위여야 한다.
--
-- 우선순위: 특수좀비(modData PuppetMutant) 먼저, 같은 등급 안에서는 가까운 순.
-- 특수좀비가 N마리에 못 미치면 나머지는 일반좀비로 채운다.
-- 저격수는 "한 곳에 자리잡고" 쏘지만, 대상은 매 발마다 다시 고른다 --
-- 플레이어가 반경 안에서 움직이면 그때그때 플레이어와 가장 가까운(특좀 우선)
-- 좀비를 노려야 하므로, 발동 시점에 N마리를 한꺼번에 스냅샷해서 순차 처리하면
-- 안 된다(그 사이 좀비가 죽거나 자리를 뜨면 허공에 쏘거나 뒤늦게 안 맞는
-- 문제가 생긴다). 대신 job을 큐에 넣고 매 iv마다 그 시점의 플레이어 좌표
-- 기준으로 재선정한다.
local _sniperJobs = {}

DOServer["PongDuFireSupport"]["Sniper"] = function(player, data)
    local r      = tonumber(data["r"])  or 30
    local n      = tonumber(data["n"])  or 10
    local iv     = tonumber(data["iv"]) or 3000
    local sender = data["sender"] or ""

    -- 저격수 위치는 발동 시점 1회만 고정("한 곳에 자리잡은 저격수").
    -- r+25 타일 거리면 통상 줌에서 화면 밖이다.
    local cx, cy = player:getX(), player:getY()
    local ang    = ZombRand(628) / 100.0
    local odist  = r + 25
    local ox     = cx + math.cos(ang) * odist
    local oy     = cy + math.sin(ang) * odist
    local oz     = player:getZ()

    _sniperJobs[#_sniperJobs + 1] = {
        player = player, r = r, iv = iv, sender = sender,
        ox = ox, oy = oy, oz = oz,
        remaining = n, nextAt = getTimestampMs(),
        shotZids = {},   -- 이 job에서 이미 쏜 zid는 재선정 대상에서 제외
    }

    print(string.format("[PongDu][Sniper] job queued n=%d r=%d iv=%d origin=%d,%d sender=%s",
        n, r, iv, math.floor(ox), math.floor(oy), tostring(sender)))
end

-- job.player의 "현재" 좌표 기준으로 반경 내 미사살 좀비 중 최우선(특좀 > 근접) 1마리.
local function pickSniperTarget(job)
    local ok, cx, cy, cell = pcall(function()
        return job.player:getX(), job.player:getY(), job.player:getCell()
    end)
    if not ok then return nil end
    local zl = cell and cell:getZombieList()
    if not zl then return nil end

    local r2 = job.r * job.r
    local best, bd, bm = nil, nil, -1
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() and not job.shotZids[z:getOnlineID()] then
            local dx, dy = z:getX() - cx, z:getY() - cy
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then
                local md = z:getModData()
                local isMut = (md and md["PuppetMutant"]) and 1 or 0
                if isMut > bm or (isMut == bm and d2 < (bd or math.huge)) then
                    best, bd, bm = z, d2, isMut
                end
            end
        end
    end
    return best
end

local function processSniperJobs()
    if #_sniperJobs == 0 then return end
    local now = getTimestampMs()
    for i = #_sniperJobs, 1, -1 do
        local job = _sniperJobs[i]
        if job.remaining <= 0 then
            table.remove(_sniperJobs, i)
        elseif now >= job.nextAt then
            local target  = pickSniperTarget(job)
            local payload = { ox = job.ox, oy = job.oy, oz = job.oz, sender = job.sender }
            if target then
                local zid = target:getOnlineID()
                job.shotZids[zid] = true
                payload.id = zid
                payload.x, payload.y, payload.z = target:getX(), target:getY(), target:getZ()
                print("[PongDu][Sniper] shot zid=" .. zid .. " remaining_after=" .. (job.remaining - 1))
            else
                print("[PongDu][Sniper] shot MISS: no target in radius r=" .. job.r)
            end

            local players = getOnlinePlayers()
            for k = 0, players:size() - 1 do
                sendServerCommand(players:get(k), "PongDuFireSupport", "SniperFire", payload)
            end

            job.remaining = job.remaining - 1
            job.nextAt    = now + job.iv
        end
    end
end
Events.OnTick.Add(processSniperJobs)

-- ── 화력 지원 / 헬기 ─────────────────────────────────────────────────────────
-- 가상의 헬기가 랜덤 지점 A에서 B로 duration 동안 이동하면서 iv 간격으로
-- 플레이어 반경 r 내 좀비를 무차별 소사한다. 발당 킬 확률 kc%(기본 5).
--
-- A/B 산출: 플레이어 기준 랜덤 방향 u로 (r+25)타일 떨어진 점 C를 잡고,
-- u에 수직인 방향 v로 C ± (r+25)를 A/B로 한다.
--   - A->B 직선의 플레이어 최소거리(수선의 발 = C까지) = r+25
--     -> 저격수 원점과 같은 "화면 밖" 기준이라 경로 전체가 시야 밖.
--   - A-B 거리 = (r+25)*2 (r=30이면 110타일) -> "너무 가깝지 않음" 고정 보장.
--
-- 킬 룰렛(kc%)을 서버가 굴리는 이유: 클라마다 굴리면 같은 발이 어떤 클라에선
-- 킬, 어떤 클라에선 미스라 연출(정조준 vs 산탄)이 어긋나고, 소유 클라의 roll
-- 결과를 남이 알 수 없다. 서버가 kill 플래그를 박아 브로드캐스트해야
-- 전 클라 연출과 실제 킬이 일치한다.
--
-- 대상 선정: 저격(특좀 우선/최근접)과 달리 반경 내 랜덤 -- "무차별 난사" 컨셉.
-- 반경 내 좀비가 없으면 플레이어 주변 랜덤 지면에 쏜다(연출 유지, 킬 없음).
--
-- 중첩 후원: 같은 플레이어의 헬기가 이미 떠 있으면 endAt만 연장한다
-- (경로/속도 유지, 클라 로터음도 1개 유지 -- firesupport.lua 설계 제약 4).
local _heliJobs = {}

DOServer["PongDuFireSupport"]["Heli"] = function(player, data)
    local dur = (tonumber(data["dur"]) or 30) * 1000
    local r   = tonumber(data["r"])  or 30
    local iv  = tonumber(data["iv"]) or 200
    local kc  = tonumber(data["kc"]) or 5
    local sender = data["sender"] or ""

    -- 중첩: 기존 job 연장
    for i = 1, #_heliJobs do
        local job = _heliJobs[i]
        if job.player == player then
            job.endAt = job.endAt + dur
            local remain = job.endAt - getTimestampMs()
            local players = getOnlinePlayers()
            for k = 0, players:size() - 1 do
                sendServerCommand(players:get(k), "PongDuFireSupport", "HeliStart",
                    { remain = remain })
            end
            print(string.format("[PongDu][Heli] job EXTENDED +%dms remain=%dms sender=%s",
                dur, remain, tostring(sender)))
            return
        end
    end

    local cx, cy = player:getX(), player:getY()
    local odist  = r + 25
    local ang    = ZombRand(628) / 100.0
    local ux, uy = math.cos(ang), math.sin(ang)
    local vx, vy = -uy, ux                       -- u에 수직
    local px, py = cx + ux * odist, cy + uy * odist   -- 수선의 발 C
    local ax, ay = px - vx * odist, py - vy * odist
    local bx, by = px + vx * odist, py + vy * odist

    local now = getTimestampMs()
    _heliJobs[#_heliJobs + 1] = {
        player = player, r = r, iv = iv, kc = kc, sender = sender,
        ax = ax, ay = ay, bx = bx, by = by, oz = player:getZ(),
        startAt = now, endAt = now + dur, nextAt = now,
    }

    local players = getOnlinePlayers()
    for k = 0, players:size() - 1 do
        sendServerCommand(players:get(k), "PongDuFireSupport", "HeliStart",
            { remain = dur })
    end
    print(string.format(
        "[PongDu][Heli] job queued dur=%dms r=%d iv=%d kc=%d%% A=%d,%d B=%d,%d sender=%s",
        dur, r, iv, kc, math.floor(ax), math.floor(ay),
        math.floor(bx), math.floor(by), tostring(sender)))
end

-- 반경 내 랜덤 좀비 1마리. 헬기는 이 좀비를 "락온"해서 사살할 때까지 계속
-- 쏘고, 죽으면 다음 타겟을 다시 랜덤으로 고른다 (매 발 랜덤 대상 아님).
local function pickHeliTarget(job)
    local ok, cx, cy, cell = pcall(function()
        return job.player:getX(), job.player:getY(), job.player:getCell()
    end)
    if not ok then return nil end
    local zl = cell and cell:getZombieList()
    if not zl then return nil end

    local r2 = job.r * job.r
    local pool = {}
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() then
            local dx, dy = z:getX() - cx, z:getY() - cy
            if dx * dx + dy * dy <= r2 then
                pool[#pool + 1] = z
            end
        end
    end
    if #pool == 0 then return nil end
    return pool[ZombRand(#pool) + 1]
end

local function processHeliJobs()
    if #_heliJobs == 0 then return end
    local now = getTimestampMs()
    for i = #_heliJobs, 1, -1 do
        local job = _heliJobs[i]
        if now >= job.endAt then
            table.remove(_heliJobs, i)
            local players = getOnlinePlayers()
            for k = 0, players:size() - 1 do
                sendServerCommand(players:get(k), "PongDuFireSupport", "HeliStop", {})
            end
            print("[PongDu][Heli] job finished")
        elseif now >= job.nextAt then
            -- 헬기 현재 위치: A -> B 선형 보간 (연장돼도 endAt 기준이라 왕복 없이
            -- 남은 시간 동안 더 천천히 B에 도달하는 정도의 차이만 생긴다)
            local t  = (now - job.startAt) / (job.endAt - job.startAt)
            if t > 1 then t = 1 end
            local hx = job.ax + (job.bx - job.ax) * t
            local hy = job.ay + (job.by - job.ay) * t

            local payload = { ox = hx, oy = hy, oz = job.oz, sender = job.sender }

            -- 락온 유지 검사: 죽었거나 반경을 벗어났으면 락 해제 후 재선정.
            -- (킬은 소유 클라가 수행하므로 kill 전송 후에도 서버에서 isDead()가
            --  반영되기까지 지연이 있다 -- kill 보낸 발에서 즉시 락을 풀어
            --  같은 좀비에 탄을 낭비하지 않는다.)
            local target = job.target
            if target then
                local okV, valid = pcall(function()
                    if target:isDead() then return false end
                    local dx = target:getX() - job.player:getX()
                    local dy = target:getY() - job.player:getY()
                    return dx * dx + dy * dy <= job.r * job.r
                end)
                if not okV or not valid then
                    target = nil
                    job.target = nil
                end
            end
            if not target then
                target = pickHeliTarget(job)
                job.target = target
                if target then
                    print("[PongDu][Heli] lock zid=" .. target:getOnlineID())
                end
            end

            if target then
                payload.id = target:getOnlineID()
                payload.x, payload.y, payload.z = target:getX(), target:getY(), target:getZ()
                if ZombRand(100) < job.kc then
                    payload.kill = true
                    job.target = nil   -- 사살 -> 다음 발에 새 타겟 랜덤 선정
                    print("[PongDu][Heli] shot KILL zid=" .. payload.id)
                end
            else
                -- 좀비 없음: 플레이어 주변 랜덤 지면 난사 (연출만)
                local okP, gx, gy, gz = pcall(function()
                    return job.player:getX(), job.player:getY(), job.player:getZ()
                end)
                if okP then
                    local ga = ZombRand(628) / 100.0
                    local gd = ZombRand(job.r * 100) / 100.0
                    payload.x = gx + math.cos(ga) * gd
                    payload.y = gy + math.sin(ga) * gd
                    payload.z = gz
                end
            end

            local players = getOnlinePlayers()
            for k = 0, players:size() - 1 do
                sendServerCommand(players:get(k), "PongDuFireSupport", "HeliFire", payload)
            end
            job.nextAt = now + job.iv
        end
    end
end
Events.OnTick.Add(processHeliJobs)

DOServer["PongDuBombard"]["Kaboom"] = function(player, data)
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
    -- 반경 내 차량 고철화. 샌드박스에서 끌 수 있다(기본 켜짐).
    local sv = SandboxVars and SandboxVars.PongDu
    if sv == nil or sv.Bombard_VehicleDamage ~= false then
        local okv, errv = pcall(function() wreckVehiclesAround(e, cx, cy, r) end)
        if not okv then srvlog("wreckVehiclesAround ERROR: " .. tostring(errv)) end
    else
        srvlog("vehicle damage disabled by sandbox option")
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
            sendServerCommand(p, "PongDuBombard", "NearbyExplosion", {x = cx, y = cy, r = r})
        end
    end
end

DOServer["PongDuBombard"]["PlayExplosion"] = function(player, data)
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            sendServerCommand(p, "PongDuBombard", "PlayExplosion", {})
        end
    end
end

DOServer["PongDuDonation"]["PlayAlert"] = function(player, data)
    local cx = tonumber(data["x"]) or player:getX()
    local cy = tonumber(data["y"]) or player:getY()
    local r  = tonumber(data["r"]) or 40
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p:getOnlineID() ~= player:getOnlineID() then
            local dist = math.sqrt(math.pow(p:getX() - cx, 2) + math.pow(p:getY() - cy, 2))
            if dist < r then
                sendServerCommand(p, "PongDuDonation", "PlayAlert", {})
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
    if module == "PongDuMutant" and command == "MutantDeathMark" then
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

-- 부활 재스탬프 마크: RiseUp이 특좀 시체를 부활시킨 좌표를 잠깐 기록해둔다.
-- reanimateNow로 부활한 좀비는 새 zid를 받지만 시체에서 물려받은
-- PuppetMutantZid는 원래 zid(불일치)라, staleSweep이 '재활용 껍데기'로
-- 오판해 md를 지워 다회차 부활이 깨진다. 이 마크로 "부활 직후 그 자리의
-- zid불일치 좀비"는 삭제 대신 zid를 새로 스탬프(정상 부활)하고, 마크 없는
-- 곳의 zid불일치 좀비만 삭제(풀 재활용)하도록 staleSweep이 구분한다.
local _reviveRestamp = {}
local REVIVE_RESTAMP_MS = 15000   -- 부활 후 이 시간 안에 재스탬프 처리

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

-- ── 알몸 부활 차단: 시체를 fakeDead로 마킹한 뒤 부활시킨다 ───────────────────
-- IsoDeadBody.reanimate()는 isFakeDead() 하나로 완전히 다른 두 경로를 가른다
-- (IsoDeadBody.java:1309):
--   true  -> setWasFakeDead(true). pid(옷차림 ID)를 시체에서 그대로 물려받아
--            클라가 pid만으로 옷을 결정론적으로 재구성한다. 네트워크 의존 0.
--   false -> setReanimatedPlayer(true) + createPlayerZombieDescriptor().
--            옷이 pid로 안 가고 ZombieDescriptors 라는 별도 패킷으로 push되는데,
--            좀비 sync(ZombiePacket)와 다른 채널이라 좀비가 먼저 도착하면
--            ApplyReanimatedPlayerOutfit이 로컬 슬롯에서 null을 만나 '조용히'
--            아무것도 안 하고, 그 직전에 HumanVisual은 이미 clear된 상태 +
--            m_bPersistentOutfitInit=true 라 재시도조차 안 된다 -> 영구 알몸.
-- 바닐라 죽은척 좀비가 옷이 멀쩡한 건 서버 사이드라서가 아니라 플래그를 켠 채로
-- reanimate()에 들어가기 때문. 강령술도 같은 경로를 태우면 된다.
--
-- 문제: setFakeDead(true)는 샌드박스 DisableFakeDead==3(죽은척 OFF)이면 조용히
-- 무시된다 (IsoDeadBody.java:361  if (!fakeDead || 값 != 3)).
-- 우회: 옵션을 잠깐 1로 내렸다 즉시 되돌린다.
--   · getSandboxOptions():set()은 IntegerConfigOption.value 필드 직접 쓰기일 뿐
--     네트워크 전송/이벤트/저장이 전혀 없다. 위 좀비 스폰의 Cognition/Memory/
--     Hearing 임시 변경과 동일한, 이미 검증된 패턴.
--   · 되돌려도 무해한 이유: reanimate()는 bFakeDead 필드만 직독하고 샌드박스를
--     재확인하지 않는다. 필드가 켜졌으면 옵션이 3으로 돌아가도 경로는 유지된다.
--   · 값 1로 내리는 이유: 2는 updateRotting()에서 '내가 죽인 시체'를 1% 확률로
--     자발적 죽은척으로 전환시킨다(IsoDeadBody.java:1050). 1은 그 로직이 없어
--     이 짧은 창 동안 부작용이 없다.
-- 반환값으로 실제 마킹 여부를 알린다 (실패 = 구 경로로 부활 = 알몸 가능).
local function markFakeDead(body)
    local so = getSandboxOptions()
    local opt = so:getOptionByName("ZombieLore.DisableFakeDead")
    local orig = opt and opt:getValue()
    if orig == 3 then so:set("ZombieLore.DisableFakeDead", 1) end
    body:setFakeDead(true)
    if orig == 3 then so:set("ZombieLore.DisableFakeDead", orig) end
    return body:isFakeDead()
end

DOServer["PongDuRiseUp"]["RiseUp"] = function(player, data)
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
                                -- 좀비 시체만 마킹. 플레이어 시체는 옷이 pid가 아닌
                                -- 진짜 wornItems라 pid 재구성이 불가능하므로 원래대로
                                -- 디스크립터 경로(setReanimatedPlayer)를 타야 맞다.
                                if b:isZombie() and not markFakeDead(b) then
                                    print("[PongDu][RiseUp] setFakeDead BLOCKED @"
                                        .. tostring(sq:getX()) .. "," .. tostring(sq:getY())
                                        .. " -> 알몸 부활 가능. DisableFakeDead 확인 필요")
                                end
                                b:reanimateNow()
                                raised = raised + 1
                                -- ── 방금 부활한 좀비 재등록 ──────────────────
                                -- registerMutant(nz,...) : 서버 권위 pid로 즉시 재등록.
                                -- 기존엔 클라가 MutantReregister로 재등록했는데, 클라가
                                -- 본 부활좀비 pid와 서버가 다음 사이클에 시체에서 읽는
                                -- pid가 어긋나면(동기화 레이스) 다음 부활이 일반좀비가
                                -- 됐다. 등록·조회를 둘 다 서버 pid(mutantKey)로 통일해
                                -- 구조적으로 일치시킨다 (버그①: 2회차 부활 일반화).
                                --
                                -- ★ setReanimateTimer(0) 제거됨: IsoZombie.ReanimateTimer는
                                --   '부활 예약'이 아니라 ZombieOnGroundState의 기상
                                --   카운트다운이다(ZombieOnGroundState:38이 유일한 writer).
                                --   0으로 밀면 시체가 바닥에서 일어나는 모션이 사라진다.
                                --   부활 예약(IsoDeadBody.reanimateTime) 방어는 아래
                                --   LoadGridsquare 살균기가 담당한다.
                                --
                                -- ★ 알려진 결함: reanimateNow()는 setReanimateTime()만 하고
                                --   실제 reanimate()는 다음 틱 IsoDeadBody.update()에서 돈다
                                --   (IsoDeadBody:1240). 따라서 이 자리에서 findFreshZombie는
                                --   항상 nil이다 (로그 확증: NOT FOUND 100/100).
                                --   특좀 능력은 reanimate()의 modData 통째 복사로 계승되어
                                --   결과적으로 동작하지만, 이 재등록은 안 걸린다.
                                --   수집을 다음 틱으로 미루는 수정 필요 (별건).
                                local nz = findFreshZombie(sq, handled)
                                if nz then
                                    print("[PongDu][RiseUp] fresh zombie zid=" .. tostring(nz:getOnlineID())
                                        .. " newKey=" .. tostring(mutantKey(nz)))
                                    if kind then registerMutant(nz, kind, sender) end
                                else
                                    print("[PongDu][RiseUp] fresh zombie NOT FOUND on sq "
                                        .. tostring(sq:getX()) .. "," .. tostring(sq:getY()))
                                end
                                if kind then
                                    marked = marked + 1
                                    sendServerCommand("PongDuMutant", "MutantRevive", {
                                        ["x"]      = sq:getX(),
                                        ["y"]      = sq:getY(),
                                        ["z"]      = floor,
                                        ["kind"]   = kind,
                                        ["sender"] = sender or "",
                                        ["key"]    = nz and mutantKey(nz) or "N/A",
                                    })
                                    -- 서버측 재스탬프 마크: 이 자리에서 부활한 좀비는
                                    -- staleSweep이 삭제 대신 zid 재스탬프하도록.
                                    _reviveRestamp[#_reviveRestamp + 1] = {
                                        x = sq:getX(), y = sq:getY(), z = floor,
                                        kind = kind, sender = sender or "",
                                        expire = getTimestampMs() + REVIVE_RESTAMP_MS,
                                    }
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
    sendServerCommand("PongDuMutant", "MutantReviveDebug", {
        ["total"] = raised, ["readable"] = readable, ["marked"] = marked,
    })
    -- ── 기상 연출 창 브로드캐스트 ────────────────────────────────────────────
    -- fakeDead 경로 부활 좀비는 isReanimatedPlayer=false라 클라를 눕히는 바닐라
    -- 게이트(ParseZombie/setBooleanVariables) 두 개를 전부 통과 못 한다.
    -- realState 관측(클라 getupScan)은 첫 패킷에 "onground"가 실려온다는 보장이
    -- 없어 타이밍 의존적 — 그래서 서버가 "이 좌표 반경에서 방금 부활이 있었다"를
    -- 직접 알리고, 클라는 이 창 안에서 처음 나타나는 좀비를 눕힌다
    -- (riseup.lua GetupWindow 수신부 참조). 순수 연출용 — 게임 상태 영향 없음.
    if raised > 0 then
        sendServerCommand("PongDuRiseUp", "GetupWindow", {
            ["x"] = cx, ["y"] = cy, ["r"] = r,
        })
        -- 부활 좀비 어그로: onground 상태에서 target을 박아도 기상 전이
        -- (reanimatetimer 기반 AnimSet 조건)와 무관하고, 일어나는 즉시 추격
        -- 시작. target 보유 좀비는 랠리 편입에서 제외돼 흩어짐도 차단된다.
        -- 창 35초 = 밀집 더미 밟힘 리셋으로 인한 최대 기상 지연(관측 27초) + 여유.
        -- zid는 서버가 모르므로(reanimate 다음 틱) 빈 창 — 각 클라 riseup.lua
        -- layDown()이 부활 좀비 식별 시 addLocalIds()로 채운다.
        broadcastAggro(player, nil, 35000, "riseup")
    end
end

-- ── 라이즈 업 후처리: 부활 예약 청소 ─────────────────────────────────────────
-- 문제: 부활시킨 시체가 다시 죽으면 새 IsoDeadBody에 reanimateTime(부활 예약
-- 시각)이 박힐 수 있다. reanimateTime은 청크 세이브에 직렬화되므로 서버 재부팅
-- 후 로드되면 예약 시각이 이미 지나 있어 시체가 또 일어난다 ("한 번 되살렸던
-- 애들만 재부팅 후 부활" 증상).
--
-- ★ 구 RiseSweep(EveryOneMinute) 삭제됨 — 애초에 엉뚱한 필드를 건드리고 있었다.
--   IsoDeadBody.reanimateTime : 진짜 '시체 부활 예약 시각'
--   IsoZombie.ReanimateTimer  : 넘어진 좀비의 '기상 카운트다운' (30~90)
--   이름만 비슷할 뿐 완전히 무관하다. IsoZombie.ReanimateTimer의 유일한 writer는
--   ZombieOnGroundState.enter():38 이고, IsoZombie:582에서 AnimSet 변수
--   "reanimatetimer"로 노출돼 0이 되면 기상 애니메이션으로 전이하는 값이다.
--   즉 구 RiseSweep은 부활 예약을 지운 적이 없고, 부활 좀비 전원의 기상 타이머를
--   0으로 밀어 '모션 없이 즉시 기립'시키는 부작용만 냈다 (로그 확증: RiseUp
--   raised=100 -> RiseSweep cleared 100).
--
-- 실제 방어는 아래 LoadGridsquare 살균기 한 곳이면 충분하다 — 그쪽은 시체의
-- reanimateTime(올바른 필드)을 0으로 밀어서 이미 세이브에 예약이 박힌 오염
-- 시체까지 소급 무효화한다.

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
    -- 만료된 부활 마크 정리
    for i = #_reviveRestamp, 1, -1 do
        if now > _reviveRestamp[i].expire then table.remove(_reviveRestamp, i) end
    end
    local cell = getCell()
    if not cell then return end
    local zeds = cell:getZombieList()
    if not zeds then return end
    local wiped, restamped = 0, 0
    for i = 0, zeds:size() - 1 do
        local z = zeds:get(i)
        local md = z:getModData()
        if md["PuppetMutant"] and md["PuppetMutantZid"] ~= z:getOnlineID() then
            -- zid 불일치: 부활 좀비인가(마크 근처) vs 풀 재활용인가(마크 없음).
            local zx, zy = z:getX(), z:getY()
            local reviveHit = nil
            for _, m in ipairs(_reviveRestamp) do
                if md["PuppetMutant"] == m.kind
                    and math.abs(zx - m.x) <= 2 and math.abs(zy - m.y) <= 2 then
                    reviveHit = m
                    break
                end
            end
            if reviveHit then
                -- 정상 부활 좀비: 새 zid로 재스탬프 -> 이후 다회차 부활 정상.
                md["PuppetMutantZid"] = z:getOnlineID()
                restamped = restamped + 1
            else
                -- 풀 재활용 껍데기: 특좀 md 제거.
                md["PuppetMutant"] = nil
                md["PuppetMutantSender"] = nil
                md["PuppetMutantZid"] = nil
                md["_cs"] = nil
                wiped = wiped + 1
            end
        end
    end
    if wiped > 0 then
        print("[PongDu][StaleSweep] wiped stale PuppetMutant from " .. wiped .. " recycled zombies")
    end
    if restamped > 0 then
        print("[PongDu][StaleSweep] re-stamped " .. restamped .. " reanimated mutants")
    end
end
Events.OnTick.Add(staleSweep)

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
                -- 되어 자발적 재부활 대상에서 빠진다(updateFakeDead()가 첫 줄에서
                -- isFakeDead()로 컷).
                -- 주의: 의도적 강령술은 fakeDead와 '무관'하지 않다 — RiseUp이 부활
                -- 직전에 markFakeDead()로 플래그를 다시 켜서 옷 유지 경로를 태운다.
                -- 여기서 끄는 건 '자발적 부활 차단'이고, 저기서 켜는 건 '경로 선택'
                -- 이라 목적이 다르며, 이 살균기는 청크 로드 시점에만 돌아서 RiseUp
                -- 마킹(같은 틱에 reanimateNow까지 완료)과 겹치지 않는다.
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
-- Zombie spawning (PongDuZombie/ZedSpawn) and DOServer handlers above stay.

-- ── Donation stats collector ─────────────────────────────────────────────────
-- Each client forwards the raw donation lines it reads (DonationStats/Record).
-- The host labels them with the sender's account name and appends to a single
-- file on the SERVER machine:  Zomboid/Lua/profits.txt
--   line format (tab-separated):  <streamer username>\t<raw rewards.txt line>
-- Aggregation (per-streamer / per-viewer totals, Excel export) is done later by
-- an external Python script that reads profits.txt.
local PROFITS_FILE = "profits.txt"

local function onDonationStats(module, command, player, data)
    if module ~= "PongDuStats" or command ~= "Record" then return end
    if not player or not data or not data.line then return end
    local streamer = player:getUsername() or "unknown"
    local w = getFileWriter(PROFITS_FILE, true, true)   -- create, append
    if w then
        w:write(streamer .. "\t" .. tostring(data.line) .. "\r\n")
        w:close()
    end
end
Events.OnClientCommand.Add(onDonationStats)

