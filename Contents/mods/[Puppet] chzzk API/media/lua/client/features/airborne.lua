-- ═══════════════════════════════════════════════════════════════════════════
--  공수부대원 (fire_support/airborne) 클라이언트
--
--  서버(server.lua 공수부대 절)가 헬기 통과 중간에 우호 히트맨 1명을 z=7 공중
--  스퀘어에 스폰하고 AirborneDrop(hid)을 보낸다. 이 파일은 그 대원의
--   ① 강하: 공중에 있는 동안
--      - 전 클라: 낙하산(ItemVisual) 부착, 강하 자세(PongDuParaDescent) 고정,
--        바라보는 방향 고정
--      - 소유 클라: fallTime=0(낙하 데미지/넘어짐 방지) + 일정 속도 하강
--      (좀비 공습 낙하산과 같은 방식 -- features/zombierain.lua Rain_Parachute 절)
--   ② 착지: 지면에 닿으면 낙하산을 벗기고 Paraglider 모드처럼 달리다 멈추는
--      모션(Bob_SprintToStop, AnimSets/zombie/bumped/PongDuParaLand.xml)을 1회
--      재생한다. 모션이 끝나야 히트맨 AI 가 풀린다 -- HitmanUpdate.lua
--      OnHitmanUpdate 가 HoldsAI() 로 확인한다. 착지 순간 2타일 안에 적이 있으면
--      모션을 건너뛰고 바로 AI 를 푼다 (모션 중엔 반격을 못 한다).
--   ③ 표적 선정/사격 제어: 대원 전투 AI(HitmanUpdate.lua ManageCombat)가 부르는
--      - PickSelfThreat: 대원 10타일 안의 가장 가까운 적 (생존 최우선)
--      - FindAttacker: 그 밖에서 대원을 쏘는 적대 히트맨
--      - PickEscortThreat: 호위 대상에게 가장 위협적인 적
--      - FirePlan / AIM_TICKS: 30타일 이내 무조건 연발, 그 밖 5발 점사, 짧은 조준
--  를 맡는다.
--
--  키는 onlineID 가 아니라 히트맨 id(HitmanUtils.GetZombieID)다. SP 에선 모든
--  좀비의 onlineID 가 -1 이라 onlineID 키면 모든 좀비가 대원으로 잡힌다.
--
--  강하 클립(anims_X/PongDu/PongDuParaDescent.X)은 Parachuting Start 모드
--  (Panopticon, Glytch3r, Sapph, Dante271)의 ParadropFromAir 에서 내려오는
--  구간만 잘라 루트 높이 이동을 뺀 것이다 -- 실제 높이는 여기서 z 로 내린다.
--  원본의 Translation_Data / Body 트랙은 키프레임이 1개뿐이라 엔진
--  (AnimationTrack.getKeyframeSpan)이 index -1 을 읽고 매 프레임 예외를 던졌다.
--  두 트랙 모두 같은 값의 키를 클립 끝(11465)에 하나 더 넣어 2개로 맞췄다.
-- ═══════════════════════════════════════════════════════════════════════════
PongDuAirborne = PongDuAirborne or {}
local _a = PongDuAirborne

local deltaTime = require("utils/deltaTime")

local DESCENT_VAR   = "PongDuParaDescent"  -- AnimSets/zombie/<상태>/PongDuParaDescent.xml
local LAND_BUMP     = "PongDuParaLand"     -- AnimSets/zombie/bumped/PongDuParaLand.xml
local DESCENT_SPEED = 1.2      -- 층/초. 7층에서 약 5.8초 -- 강하 클립 SpeedScale 과 맞춘 값
local AIR_Z         = 0.05     -- 이 높이(층) 위면 공중
local LAND_MAX_MS   = 2500     -- 착지 모션 상한. 넘기면 AI 를 그냥 푼다
local LAND_SKIP_R   = 2        -- 착지 순간 이 반경(타일) 안에 적이 있으면 착지 모션 생략
local PENDING_MS    = 45000    -- 대기 항목 유효시간 (스트림아웃 등으로 못 본 경우 청소)

local PARA_ITEM     = "t3chzzkDonation.PongDuZombieParachute"   -- zombierain.lua 와 같은 에셋
local PARA_CLOTHING = "PongDu_ZombieParachute"

-- ── 낙하산 ItemVisual (zombierain.lua chuteHas/chuteAttach/chuteDetach 와 같은 방식) ──
local _paraScriptOk = nil

local function chuteHas(z)
    local found = false
    pcall(function()
        local ivs = z:getItemVisuals()
        for i = 0, ivs:size() - 1 do
            local iv = ivs:get(i)
            if iv and iv:getItemType() == PARA_ITEM then found = true; return end
        end
    end)
    return found
end

local function chuteAttach(z)
    if _paraScriptOk == nil then
        _paraScriptOk = getScriptManager():FindItem(PARA_ITEM) ~= nil
        if not _paraScriptOk then
            print("[PongDu][Airborne] WARN parachute item script missing: " .. PARA_ITEM)
        end
    end
    if not _paraScriptOk then return false end
    local ok, err = pcall(function()
        local iv = ItemVisual.new()
        iv:setItemType(PARA_ITEM)
        iv:setClothingItemName(PARA_CLOTHING)
        z:getItemVisuals():add(iv)
        z:resetModelNextFrame()
    end)
    if not ok then
        print("[PongDu][Airborne] parachute attach FAILED err=" .. tostring(err))
    end
    return ok
end

local function chuteDetach(z)
    local removed = 0
    pcall(function()
        local ivs = z:getItemVisuals()
        for i = ivs:size() - 1, 0, -1 do
            local iv = ivs:get(i)
            if iv and iv:getItemType() == PARA_ITEM then
                ivs:remove(iv)
                removed = removed + 1
            end
        end
        if removed > 0 then z:resetModelNextFrame() end
    end)
    return removed
end

-- ── 강하/착지 대기열 ────────────────────────────────────────────────────────
-- [hid] = { e=만료, phase="air"|"land", seenAir=공중에서 본 적 있음,
--           chute=낙하산 부착, pz=감속 목표 높이, ang=고정 방향, landAt=착지 시각 }
local _pending      = {}
local _pendingCount = 0

-- 히트맨 AI 를 잡고 있는가 (강하 중 또는 착지 모션 중)
function _a.HoldsAI(zombie)
    if _pendingCount == 0 then return false end
    return _pending[HitmanUtils.GetZombieID(zombie)] ~= nil
end

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuFireSupport" or command ~= "AirborneDrop" then return end
    local hid = args and tonumber(args.hid)
    if not hid then
        print("[PongDu][Airborne] AirborneDrop without hid -- ignored (version mismatch?)")
        return
    end
    if not _pending[hid] then _pendingCount = _pendingCount + 1 end
    _pending[hid] = { e = getTimestampMs() + PENDING_MS, phase = "air" }
    print(string.format("[PongDu][Airborne] drop registered hid=%s at %s,%s,%s",
        tostring(hid), tostring(args.x), tostring(args.y), tostring(args.z)))
end)

-- 공중: 방향/자세/낙하산 고정 + (소유 클라) 감속 하강
local function airTick(z, p, dtMs)
    local zz = z:getZ()
    p.seenAir = true
    if not p.ang then p.ang = z:getDirectionAngle() end
    z:setDirectionAngle(p.ang)
    z:setVariable(DESCENT_VAR, true)   -- 엔진이 지워도 매 틱 복구
    if not chuteHas(z) then
        if chuteAttach(z) then p.chute = true end
    end
    if not z:isRemoteZombie() then
        z:setFallTime(0)
        -- 목표 높이를 일정 속도로 내리고 실제 z 를 그 아래로 못 가게 한다.
        -- 목표는 절대 올라가지 않으므로 대원이 떠오를 수 없다.
        if not p.pz or p.pz > zz + 1 then p.pz = zz end
        p.pz = p.pz - DESCENT_SPEED * dtMs / 1000
        if p.pz < 0 then p.pz = 0 end
        if zz < p.pz then z:setZ(p.pz) end
    end
end

-- 착지 지점 주변 적(일반 좀비 / 적대 히트맨) 유무. Bandits 모드 NPC 는 제외.
local function enemyNear(z, r)
    local zx, zy, zz = z:getX(), z:getY(), z:getZ()
    local r2 = r * r
    local cache = HitmanZombie and HitmanZombie.Cache
    if not cache then return false end
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - zx, light.y - zy
        if dx * dx + dy * dy <= r2 and math.abs(light.z - zz) < 1 then
            local b = light.brain
            if not b or b.hostile or b.hostileP then
                local o = cache[id]
                if o and o ~= z and o:isAlive() and not o:getVariableBoolean("Bandit") then
                    return true
                end
            end
        end
    end
    return false
end

-- 지면 도착: 낙하산을 벗기고 착지 모션 시작. 공중에서 본 적이 없으면(늦게
-- 스트림인) 모션 없이 바로 AI 를 푼다. 바로 옆에 적이 있어도 모션을 건너뛴다
-- (착지 모션 동안은 AI 가 잠겨 반격을 못 한다).
local function startLanding(z, p, hid, now)
    z:clearVariable(DESCENT_VAR)
    if p.chute or chuteHas(z) then
        chuteDetach(z)
        p.chute = false
    end
    if p.seenAir and not z:isDead() and enemyNear(z, LAND_SKIP_R) then
        print("[PongDu][Airborne] landed hid=" .. tostring(hid) .. " enemy within "
            .. LAND_SKIP_R .. " tiles -- landing motion skipped, AI released")
        return true
    end
    if p.seenAir and not z:isDead() then
        p.phase  = "land"
        p.landAt = now
        z:setBumpType(LAND_BUMP)
        print(string.format("[PongDu][Airborne] landed hid=%s remote=%s -- landing motion",
            tostring(hid), tostring(z:isRemoteZombie())))
        return false
    end
    print("[PongDu][Airborne] landed hid=" .. tostring(hid) .. " (not seen in air) -- AI released")
    return true
end

local _done = {}

Events.OnTick.Add(function()
    if _pendingCount == 0 then return end
    local dtMs = deltaTime.ms()
    local now  = getTimestampMs()
    local cache = HitmanZombie and HitmanZombie.Cache
    local n = 0
    for hid, p in pairs(_pending) do
        local z = cache and cache[hid]
        local finished = false
        if now > p.e then
            if z then
                z:clearVariable(DESCENT_VAR)
                if p.chute then chuteDetach(z) end
            end
            print("[PongDu][Airborne] WARN pending expired hid=" .. tostring(hid) .. " phase=" .. p.phase)
            finished = true
        elseif z then
            if z:isDead() then
                finished = true
            elseif p.phase == "air" then
                if z:getZ() > AIR_Z then
                    airTick(z, p, dtMs)
                else
                    finished = startLanding(z, p, hid, now)
                end
            elseif p.phase == "land" then
                -- 모션이 끝나면 엔진이 BumpType 을 비운다. 상한을 넘기면 그냥 푼다.
                if z:getBumpType() ~= LAND_BUMP or now - p.landAt > LAND_MAX_MS then
                    print(string.format("[PongDu][Airborne] landing done hid=%s after %dms -- AI released",
                        tostring(hid), now - p.landAt))
                    finished = true
                end
            end
        end
        if finished then
            n = n + 1
            _done[n] = hid
        end
    end
    -- pairs 순회 중 삭제는 Kahlua 에서 보장되지 않아 모았다가 지운다
    for i = 1, n do
        if _pending[_done[i]] then
            _pending[_done[i]] = nil
            _pendingCount = _pendingCount - 1
        end
        _done[i] = nil
    end
end)

-- 강하 중 사살: Kill()이 itemVisuals 를 인벤토리로 옮긴 뒤 발화한다.
-- 낙하산이 시체에 남지 않게 비주얼+아이템을 지운다.
Events.OnZombieDead.Add(function(zombie)
    if _pendingCount == 0 or not zombie then return end
    local hid = HitmanUtils.GetZombieID(zombie)
    local p = _pending[hid]
    if not p then return end
    chuteDetach(zombie)
    pcall(function() zombie:getInventory():RemoveAll("PongDuZombieParachute") end)
    _pending[hid] = nil
    _pendingCount = _pendingCount - 1
    print("[PongDu][Airborne] trooper died during drop hid=" .. tostring(hid))
end)

-- ═══════════════════════════════════════════════════════════════════════════
--  표적 선정 (HitmanUpdate.lua ManageCombat 이 대원일 때 호출)
-- ═══════════════════════════════════════════════════════════════════════════
local ESCORT_SCAN_R    = 20    -- 호위 대상 중심 위협 탐지 반경 (드론 기본 인식 반경과 같음)
local ESCORT_RESCAN_MS = 100   -- 좀비 리스트 전수 스캔 주기 (표적이 죽으면 즉시 재스캔)
local SELF_R           = 10    -- 자기 방어 반경: 이 안의 적은 호위보다 먼저 가장 가까운 순으로 처리
local SELF_R2          = SELF_R * SELF_R
local SELF_RESCAN_MS   = 100
local SELF_SWITCH_GAIN = 1.5   -- 새 적이 지금 표적보다 이만큼(타일) 더 가까워야 표적을 갈아탄다

-- 사격 제어 (HitmanUpdate.lua ManageCombat -> HitmanPrograms.Weapon.Aim/Shoot)
_a.AIM_TICKS            = 8    -- 조준 시간(틱, 1/60초). 기본 히트맨은 18 + 거리*2.5 (최대 60)
local FULLAUTO_MAX      = 30   -- 이 거리(타일) 이내: 무조건 연발
local FULLAUTO_ROUNDS   = 10   -- 연발 1회 계획 탄수. 다 쏘면 표적을 다시 확인하고 이어서 쏜다
local LONG_BURST        = 5    -- FULLAUTO_MAX 밖: 5발 점사
local AUTO_INTERVAL     = 6    -- 연발 탄 간격(틱). 기본 히트맨 점사와 같은 값
local ATTACKER_R       = 30    -- 자기를 노리는 적대 히트맨 탐지 반경

-- 좀비 상태 분류는 firesupport.lua dronePickTarget 과 같다. 한쪽을 바꾸면 맞출 것.
local ATTACK_STATES = { ["attack"] = true, ["attack-network"] = true }
local LUNGE_STATES  = { ["lunge"] = true, ["lunge-network"] = true }
local DOWN_STATES   = {
    ["hitreaction"] = true, ["hitreaction-hit"] = true, ["hitwhilestaggered"] = true,
    ["staggerback"] = true, ["falldown"] = true, ["onground"] = true, ["getup"] = true,
}
local ATTACK_ACTIONS = { Aim = true, Shoot = true, Smack = true, Push = true }

-- 적대 히트맨이 지금 eid 를 노리는 공격 태스크를 들고 있나.
-- (히트맨 AI 는 전 클라가 미러링하므로 이 클라의 brain.tasks 로 판정할 수 있다)
local function hitmanAttacking(brain, eid)
    local t = brain.tasks and brain.tasks[1]
    return t ~= nil and ATTACK_ACTIONS[t.action] == true and t.eid == eid
end

-- 자기 위협: 자기를 공격 중인 적대 히트맨 중 가장 가까운(볼 수 있는) 놈
function _a.FindAttacker(hitman, brain)
    local myId = HitmanUtils.GetCharacterID(hitman)
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local cache = HitmanZombie.Cache
    local best, bestDist
    for id, light in pairs(HitmanZombie.CacheLightB) do
        local ob = light.brain
        if ob and ob ~= brain and (ob.hostile or ob.hostileP) and hitmanAttacking(ob, myId) then
            local dx, dy = light.x - zx, light.y - zy
            local dist = math.sqrt(dx * dx + dy * dy)
            if dist <= ATTACKER_R and (not bestDist or dist < bestDist) then
                local e = cache[id]
                if e and e:isAlive() and math.abs(e:getZ() - zz) < 0.5
                   and hitman:CanSee(e) and HitmanUtils.LineClear(hitman, e) then
                    best, bestDist = e, dist
                end
            end
        end
    end
    return best, bestDist
end

-- 위협 등급 (작을수록 먼저). nil = 표적 아님.
--  1 A: 호위 대상을 물고 있는 좀비 / 호위 대상을 공격 중인 적대 히트맨
--  2 L: 돌진 중인 좀비
--  3 S: 특수 풀 -- 특수좀비(PuppetMutant) + 적대 히트맨
--  4 N: 일반 좀비 (걷기/추적/기어오는 크롤러)
--  5 D: 제압 중(넘어짐/기상/피격 반응)
local function threatRank(z, escortId)
    if z:getVariableBoolean("Hitman") then
        local b = HitmanBrain.Get(z)
        if not b or not (b.hostile or b.hostileP) then return nil end
        if hitmanAttacking(b, escortId) then return 1 end
        return 3
    end
    if z:getVariableBoolean("Bandit") then return nil end   -- Bandits 모드 NPC: 적대 여부 불명

    local remote = z:isRemoteZombie()
    local ok, st = pcall(function()
        if remote then return tostring(z:getRealState()) end
        return z:getActionStateName()
    end)
    if not ok then st = nil end
    if st and ATTACK_STATES[st] then return 1 end
    if st and LUNGE_STATES[st] then return 2 end

    local down = (st and DOWN_STATES[st]) and true or false
    if not down and not remote then
        local okF, fl = pcall(function()
            if z:isKnockedDown() then return true end
            return z:isOnFloor() and not z:isCrawling()
        end)
        down = okF and fl or false
    end
    if down then return 5 end

    local md = z:getModData()
    if md and md["PuppetMutant"] then return 3 end
    return 4
end

local _pick = {}   -- [brain.id] = { at = ms, target = zombie|nil, rank = n }
local _self = {}   -- [brain.id] = { at = ms, target = zombie|nil }

local function candLess(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.d2 < b.d2
end

local function d2Less(a, b) return a.d2 < b.d2 end

local function aliveSameFloor(z, zz)
    return z ~= nil and z:isAlive() and not z:isDead() and math.abs(z:getZ() - zz) < 0.5
end

local function logPick(kind, brain, prev, best, n)
    if best == prev then return end
    print(string.format("[PongDu][Airborne] %s target id=%s -> %s (candidates=%d)", kind,
        tostring(brain.id), best and tostring(HitmanUtils.GetCharacterID(best)) or "none", n))
end

-- 자기 위협: 대원 기준 SELF_R 안의 적 중 가장 가까운 놈 (일반 좀비 전부 + 적대 히트맨).
-- 잡은 표적은 죽거나/시야를 잃거나/반경을 벗어나기 전까지 유지하고, 새 적이
-- SELF_SWITCH_GAIN 이상 더 가까울 때만 갈아탄다 -- 거리가 비슷한 두 놈 사이에서
-- 매 스캔마다 표적이 뒤집히면 돌아서기만 하다 못 쏜다.
-- 반환: 표적, 대원과의 거리
function _a.PickSelfThreat(hitman, brain)
    local now = getTimestampMs()
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local c = _self[brain.id]
    local cur = c and c.target
    local curD2
    if aliveSameFloor(cur, zz) then
        local dx, dy = cur:getX() - zx, cur:getY() - zy
        curD2 = dx * dx + dy * dy
        if curD2 > SELF_R2 then cur, curD2 = nil, nil end
    else
        cur = nil
    end
    -- 스캔 사이에는 잡은 표적 유지. 표적이 죽으면 캐시를 무시하고 바로 다시 찾는다.
    if cur and now < c.at + SELF_RESCAN_MS then
        return cur, math.sqrt(curD2)
    end

    local cache = HitmanZombie.Cache
    local cands, n = {}, 0
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - zx, light.y - zy
        if dx <= SELF_R and dx >= -SELF_R and dy <= SELF_R and dy >= -SELF_R then
            local d2 = dx * dx + dy * dy
            if d2 <= SELF_R2 and HitmanUtils.AreEnemies(light.brain, brain) then
                n = n + 1
                cands[n] = { id = id, d2 = d2 }
            end
        end
    end
    if n > 1 then table.sort(cands, d2Less) end

    local best, bestD2
    for i = 1, n do
        local z = cache[cands[i].id]
        if z and z ~= hitman and aliveSameFloor(z, zz) and not z:getVariableBoolean("Bandit")
           and hitman:CanSee(z) and HitmanUtils.LineClear(hitman, z) then
            local dx, dy = z:getX() - zx, z:getY() - zy
            best, bestD2 = z, dx * dx + dy * dy
            break
        end
    end

    if cur and best ~= cur and hitman:CanSee(cur) and HitmanUtils.LineClear(hitman, cur) then
        if not best or math.sqrt(bestD2) > math.sqrt(curD2) - SELF_SWITCH_GAIN then
            best, bestD2 = cur, curD2
        end
    end

    logPick("self", brain, c and c.target, best, n)
    _self[brain.id] = { at = now, target = best }
    if best then return best, math.sqrt(bestD2) end
    return nil
end

-- 호위 대상에게 가장 위협적인 적 (등급 -> 호위 대상과의 거리). 대원이 볼 수
-- 있고 같은 층인 놈만 -- 못 쏘는 표적을 잡고 있으면 아무것도 못 한다.
-- 잡은 표적은 살아 있고 보이는 동안 유지하며, 등급이 더 높은(숫자가 작은) 적이
-- 나타날 때만 갈아탄다. 같은 등급끼리 거리 순위가 바뀌는 건 무시한다.
function _a.PickEscortThreat(hitman, brain, escort)
    local now = getTimestampMs()
    local zz = hitman:getZ()
    local c = _pick[brain.id]
    local cur = c and c.target
    if not aliveSameFloor(cur, zz) then cur = nil end
    if c and now < c.at + ESCORT_RESCAN_MS and (cur or not c.target) then
        return cur
    end

    local escortId = HitmanUtils.GetCharacterID(escort)
    local ex, ey = escort:getX(), escort:getY()
    local r2 = ESCORT_SCAN_R * ESCORT_SCAN_R
    local cands, n = {}, 0
    local curRank
    local zl = getCell():getZombieList()
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and z ~= hitman and not z:isDead() and math.abs(z:getZ() - zz) < 0.5 then
            local dx, dy = z:getX() - ex, z:getY() - ey
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then
                local rank = threatRank(z, escortId)
                if rank then
                    n = n + 1
                    cands[n] = { z = z, rank = rank, d2 = d2 }
                    if z == cur then curRank = rank end
                end
            end
        end
    end
    if n > 1 then table.sort(cands, candLess) end

    local best, bestRank = nil, nil
    for i = 1, n do
        local z = cands[i].z
        if hitman:CanSee(z) and HitmanUtils.LineClear(hitman, z) then
            best, bestRank = z, cands[i].rank
            break
        end
    end

    -- 지금 표적이 여전히 반경 안이고 보이면, 더 급한 등급이 아닌 한 유지
    if cur and curRank and best ~= cur and (not bestRank or bestRank >= curRank)
       and hitman:CanSee(cur) and HitmanUtils.LineClear(hitman, cur) then
        best, bestRank = cur, curRank
    end

    logPick("escort", brain, c and c.target, best, n)
    _pick[brain.id] = { at = now, target = best, rank = bestRank }
    return best
end

-- 사격 계획: FULLAUTO_MAX 이내는 무조건 연발(첫 발부터 연발 간격), 그 밖은
-- 5발 점사(첫 발은 기본 발사 지연 = 점사 사이 간격). HitmanPrograms.Weapon.Shoot
-- 는 Auto 모드가 있는 총에만 이 계획을 쓴다.
function _a.FirePlan(dist)
    if dist <= FULLAUTO_MAX then
        return { bullets = FULLAUTO_ROUNDS, interval = AUTO_INTERVAL, firstTime = AUTO_INTERVAL }
    end
    return { bullets = LONG_BURST, interval = AUTO_INTERVAL }
end

-- 대원 사망 시 표적 캐시 정리 (HitmanUpdate.lua OnZombieDead 에서 호출)
function _a.Forget(brain)
    if brain and brain.id then
        _pick[brain.id] = nil
        _self[brain.id] = nil
    end
end

return _a
