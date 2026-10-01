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
--      모션(Bob_SprintToStop)을 1회 재생한다. 강하 자세와 같은 변수 노드 방식
--      (AnimSets/zombie/<상태>/PongDuParaLanding.xml, 변수 PongDuParaLanding)이라
--      착지 순간 좀비가 어느 상태(falling/turnalerted/idle...)에 있든 바로 재생된다.
--      모션 끝(End 이벤트 PongDuParaLandDone)에 히트맨 AI 가 풀린다 -- HitmanUpdate.lua
--      OnHitmanUpdate 가 HoldsAI() 로 확인한다. 착지 순간 2타일 안에 적이 있으면
--      모션을 건너뛰고 바로 AI 를 푼다 (모션 중엔 반격을 못 한다).
--      (예전 BumpType 방식은 turnalerted/falling 상태에 bumped 전이가 없어서
--       두리번 모션이 먼저 나오거나 아예 안 나왔다.)
--   ③ 착지 후 행동 상태: 대원 전투 AI(HitmanUpdate.lua ManageCombat)가 매 프레임 Think
--      - PATROL(50타일 안 보이는 적 없음) / FLEE(위험 + 3타일 안 5마리) / FIRE
--      - FIRE phase1 위험(자신을 무는 좀비/쏘는 적대 히트맨) > phase2 대원 10타일
--        > phase3 플레이어 호위. phase2/3 은 드론 호위 로직(A>L>N>D)
--      - FirePlan / AIM_TICKS: 15타일 이내 지속 사격, 그 밖 짧은 점사, 짧은 조준.
--        탄수/연사 속도/재발사 간격은 든 총의 스펙(HitmanPrograms.Weapon.FireSpec)에서 뽑는다.
--        표적을 붙잡는 거리도 든 총의 사거리(ManageCombat 사격 판정과 같은 값)다.
--        표적 전환 시 순간 회전 없이 TURN_DEG_PER_S 로 돌며 계속 사격(눈먼 탄)
--  를 맡는다. 자세한 규칙은 "착지 후 행동 상태" 절.
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
local LAND_VAR      = "PongDuParaLanding"  -- AnimSets/zombie/<상태>/PongDuParaLanding.xml
local LAND_DONE_VAR = "PongDuParaLandDone" -- 착지 클립 End 이벤트가 세운다
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
        z:clearVariable(LAND_DONE_VAR)
        z:setVariable(LAND_VAR, true)
        print(string.format("[PongDu][Airborne] landed hid=%s remote=%s state=%s -- landing motion",
            tostring(hid), tostring(z:isRemoteZombie()), tostring(z:getActionStateName())))
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
                z:clearVariable(LAND_VAR)
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
                -- 클립 End 이벤트가 LAND_DONE_VAR 를 세운다. 상한을 넘기면 그냥 푼다.
                local animEnd = z:getVariableBoolean(LAND_DONE_VAR)
                if animEnd or now - p.landAt > LAND_MAX_MS then
                    z:clearVariable(LAND_VAR)
                    z:clearVariable(LAND_DONE_VAR)
                    print(string.format("[PongDu][Airborne] landing done hid=%s after %dms (%s) -- AI released",
                        tostring(hid), now - p.landAt, animEnd and "anim end" or "timeout"))
                    finished = true
                else
                    z:setVariable(LAND_VAR, true)   -- 엔진이 지워도 매 틱 복구
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
--  착지 후 행동 상태 (HitmanUpdate.lua ManageCombat 이 대원일 때 매 프레임 _a.Think)
--
--  상태 3가지
--    PATROL  대원 50타일(DETECT_R) 안에 보이는 적이 없다 -> ZPAirborne 순찰
--    FLEE    위험 + 3타일 안 적 5마리 이상 -> 반대쪽으로 10타일 후퇴(RetreatTick)
--    FIRE    그 외 교전. 발포 phase 3단계:
--      phase1 위험: 대원에게 공격모션(물기)이 나온 좀비 / 대원을 쏘는 적대 히트맨.
--             후퇴가 막혔거나 쿨다운이면 3타일 안 최근접. 표적 고정을 무시하고 즉시 전환.
--      phase2 여유 + 대원 10타일 안에 적: 드론 호위 로직을 대원 자신을 중심으로
--      phase3 여유 + 대원 10타일 안이 정리됨: 드론 호위 로직을 플레이어 중심 20타일로
--    FIRE 인데 쏠 표적이 없으면(감지는 됐는데 phase2/3 조건 밖) 순찰을 멈추고
--    플레이어 곁에서 감지된 적 쪽을 겨누며 대기한다(ZPAirborne 경계).
--
--  위험 판정 (FIRE/FLEE 일 때만. PATROL 에서는 판정 안 함)
--    - 3타일(RETREAT_R) 안 적 RETREAT_N(5) 마리 이상
--    - 공격모션: 드론(firesupport.lua dronePickTarget)의 공격 판정은 좀비 상태
--      attack/attack-network 다. 좀비가 히트맨을 물 때는 바닐라 attack 상태로 안 가고
--      UpdateZombies 가 bumped + BumpType "Bite" 로 흉내 내므로(히트맨은
--      setZombiesDontAttack) 둘 다 공격모션으로 본다. 대상이 이 대원이어야 한다.
--      적대 히트맨이 이 대원에게 조준/사격/근접 태스크를 들고 있으면 그것도 공격모션.
--
--  드론 호위 로직 (dronePickTarget 과 같은 분류, 각 군 안에서는 중심점 최근접)
--    A 공격 판정 중 > L 돌진 중 > N 정상(걷기/추적/기어오는 크롤러) > D 제압 중
--    드론과 다른 점: 대원은 땅 위에서 쏘므로 같은 층 + 시야(CanSee/LineClear) 필수.
--
--  표적 고정: 잡은 표적은 죽을 때까지 유지한다. 예외는 더 높은 우선순위
--  (phase 숫자가 작거나, 같은 phase 에서 군이 더 급함)가 나타날 때와,
--  표적이 가려진 동안 다른 쏠 수 있는 적이 있을 때뿐이다. 쏠 표적이 전혀 없으면
--  가려진 표적은 LOCK_LOST_MS 동안 붙잡고 사격만 멈춘다.
-- ═══════════════════════════════════════════════════════════════════════════
local DETECT_R        = 50     -- 이 안에 보이는 적이 있으면 교전(FIRE/FLEE), 없으면 순찰
local DETECT_SCAN_MS  = 250
local DETECT_GRACE_MS = 2000   -- 마지막으로 본 뒤 이 시간은 교전 유지 (시야가 깜빡일 때 상태가 뒤집히지 않게)
local SELF_R          = 10     -- phase2: 대원 중심 반경
local ESCORT_SCAN_R   = 20     -- phase3: 플레이어 중심 반경 (드론 기본 인식 반경과 같음)
local BITE_R          = 1.5    -- 공격모션 판정 거리 (UpdateZombies 는 0.8 안에서 문다)
local ATTACKER_R      = 30     -- 대원을 노리는 적대 히트맨 탐지 반경
local PICK_SCAN_MS    = 100
-- 이보다 멀면 "안 보임"으로 친다. 든 총의 사거리(ManageCombat 사격 판정과 같은 값)로
-- Think 마다 다시 정한다. 총이 없으면(근접 모드) 감지 반경.
local _lockR          = DETECT_R
local LOCK_LOST_MS    = 2000
local RETREAT_R       = 3      -- 전략적 후퇴 절과 공유
local RETREAT_N       = 5

-- 사격 제어 (HitmanUpdate.lua ManageCombat -> HitmanPrograms.Weapon.Aim/Shoot)
-- 무기 박자(연사 속도, 점사 탄수, 다시 쏘기까지의 간격)는 총마다 다르므로 여기 두지 않는다.
-- HitmanPrograms.Weapon.FireSpec 이 플레이어가 그 총을 쏠 때와 같은 값으로 계산한다.
-- 아래는 총과 무관한 사격 "전술"이다 (초 단위 -> 총의 연사 속도로 탄수가 정해진다).
_a.AIM_TICKS            = 8    -- 조준 시간(틱, 1/60초). 기본 히트맨은 18 + 거리*2.5 (최대 60)
local CLOSE_R           = 15   -- 이 거리(타일) 이내: 지속 사격
local SUSTAIN_S         = 1.0  -- 지속 사격 1회 계획 길이(초). 다 쏘면 표적을 다시 확인하고 이어서 쏜다
local FAR_BURST_S       = 0.5  -- CLOSE_R 밖, 연사 총의 점사 길이(초)
local FAR_PAUSE_S       = 0.5  -- CLOSE_R 밖, 점사(단발) 사이 쉬는 시간(초). 새 표적의 첫 사격은 안 쉰다
_a.TURN_DEG_PER_S       = 360  -- 표적 쪽으로 도는 속도(도/초). 순간 회전 대신 이 속도로 돌며 계속 쏜다

local ATTACK_STATES = { ["attack"] = true, ["attack-network"] = true }
local LUNGE_STATES  = { ["lunge"] = true, ["lunge-network"] = true }
local DOWN_STATES   = {
    ["hitreaction"] = true, ["hitreaction-hit"] = true, ["hitwhilestaggered"] = true,
    ["staggerback"] = true, ["falldown"] = true, ["onground"] = true, ["getup"] = true,
}
local TIER_ORDER    = { A = 1, L = 2, N = 3, D = 4 }
local ATTACK_ACTIONS = { Aim = true, Shoot = true, Smack = true, Push = true }

-- 적대 히트맨이 지금 eid 를 노리는 공격 태스크를 들고 있나.
-- (히트맨 AI 는 전 클라가 미러링하므로 이 클라의 brain.tasks 로 판정할 수 있다)
local function hitmanAttacking(brain, eid)
    local t = brain.tasks and brain.tasks[1]
    return t ~= nil and ATTACK_ACTIONS[t.action] == true and t.eid == eid
end

-- 이 대원을 공격 중인 적대 히트맨 중 가장 가까운(볼 수 있는) 놈
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

local function zombieState(z)
    local ok, st = pcall(function()
        if z:isRemoteZombie() then return tostring(z:getRealState()) end
        return z:getActionStateName()
    end)
    if ok then return st end
    return nil
end

-- 공격모션: 바닐라 공격 상태이거나, 히트맨 물기 흉내(bumped + BumpType "Bite").
-- 원격 좀비는 st 가 소유 클라의 realState 라 로컬 상태도 같이 본다. BumpType 은 물기가
-- 끝나도 남아 있으므로 bumped 상태일 때만 인정한다. 공격 중 여부만 보고 대상은 호출부가 본다.
local function isAttacking(z, st)
    if st and ATTACK_STATES[st] then return true end
    local ok, res = pcall(function()
        if z:getBumpType() ~= "Bite" then return false end
        return st == "bumped" or z:getActionStateName() == "bumped"
    end)
    return ok and res == true
end

-- 드론 분류 (dronePickTarget 과 같은 판정 순서: 공격/돌진 먼저, 그다음 제압, 나머지 정상)
local function droneTier(z)
    local st = zombieState(z)
    if isAttacking(z, st) then return "A" end
    if st and LUNGE_STATES[st] then return "L" end
    local down = (st and DOWN_STATES[st]) and true or false
    if not down and not z:isRemoteZombie() then
        local okF, fl = pcall(function()
            if z:isKnockedDown() then return true end
            return z:isOnFloor() and not z:isCrawling()
        end)
        down = okF and fl or false
    end
    if down then return "D" end
    return "N"
end

local function d2Less(a, b) return a.d2 < b.d2 end
local function candLess(a, b)
    if a.rank ~= b.rank then return a.rank < b.rank end
    return a.d2 < b.d2
end

-- 쏠 수 있는 적인가 (살아 있음, Bandits NPC 아님, 대원과 같은 층)
local function validEnemy(z, hitman, zz)
    return z ~= nil and z ~= hitman and z:isAlive() and not z:isDead()
        and math.abs(z:getZ() - zz) < 0.5 and not z:getVariableBoolean("Bandit")
end

local function visible(hitman, z)
    return hitman:CanSee(z) and HitmanUtils.LineClear(hitman, z)
end

-- ── 감지 (50타일, 시야) ─────────────────────────────────────────────────────
local _det = {}   -- [brain.id] = { at, seenAt, found, nx, ny, nd }

local function detect(hitman, brain, now, zx, zy, zz)
    local d = _det[brain.id]
    if d and now < d.at + DETECT_SCAN_MS then return d end
    d = d or {}
    d.at = now
    local r2 = DETECT_R * DETECT_R
    local cands, n = {}, 0
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - zx, light.y - zy
        if dx <= DETECT_R and dx >= -DETECT_R and dy <= DETECT_R and dy >= -DETECT_R
           and math.abs(light.z - zz) < 0.5 then
            local d2 = dx * dx + dy * dy
            if d2 <= r2 and HitmanUtils.AreEnemies(light.brain, brain) then
                n = n + 1
                cands[n] = { id = id, d2 = d2 }
            end
        end
    end
    if n > 1 then table.sort(cands, d2Less) end
    local cache = HitmanZombie.Cache
    d.found = false
    for i = 1, n do
        local z = cache[cands[i].id]
        if validEnemy(z, hitman, zz) and hitman:CanSee(z) then
            d.found, d.seenAt = true, now
            d.nx, d.ny, d.nd = z:getX(), z:getY(), math.sqrt(cands[i].d2)
            break
        end
    end
    _det[brain.id] = d
    return d
end

-- ── 위험 판정 ────────────────────────────────────────────────────────────────
-- 반환: 3타일 안 적 수, 공격모션 표적(물고 있는 좀비 최근접 > 대원을 쏘는 적대 히트맨),
--       그 거리, 종류("bite"|"hitman"), 3타일 안 보이는 최근접 적, 그 거리^2
local function assessDangerScan(hitman, brain, zx, zy, zz)
    local cache = HitmanZombie.Cache
    local r2 = RETREAT_R * RETREAT_R
    local b2 = BITE_R * BITE_R
    local n, biter, biterD2, near, nearD2 = 0, nil, nil, nil, nil
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - zx, light.y - zy
        if dx <= RETREAT_R and dx >= -RETREAT_R and dy <= RETREAT_R and dy >= -RETREAT_R
           and math.abs(light.z - zz) < 1 and HitmanUtils.AreEnemies(light.brain, brain) then
            local d2 = dx * dx + dy * dy
            if d2 <= r2 then
                local z = cache[id]
                if z and z ~= hitman and z:isAlive() and not z:getVariableBoolean("Bandit") then
                    n = n + 1
                    if math.abs(z:getZ() - zz) < 0.5 then
                        if d2 <= b2 and (not biterD2 or d2 < biterD2)
                           and isAttacking(z, zombieState(z)) and z:getTarget() == hitman then
                            biter, biterD2 = z, d2
                        end
                        if (not nearD2 or d2 < nearD2) and visible(hitman, z) then
                            near, nearD2 = z, d2
                        end
                    end
                end
            end
        end
    end
    if biter then return n, biter, math.sqrt(biterD2), "bite", near, nearD2 end
    local shooter, sd = _a.FindAttacker(hitman, brain)
    if shooter then return n, shooter, sd, "hitman", near, nearD2 end
    return n, nil, nil, nil, near, nearD2
end

-- DANGER_SCAN_MS 마다 다시 센다. 그 사이 공격자가 죽었으면 바로 다시 센다.
local DANGER_SCAN_MS = 50
local _dng = {}   -- [brain.id] = { at, n, a, ad, ak, near, nearD2 }
local function assessDanger(hitman, brain, now, zx, zy, zz)
    local c = _dng[brain.id]
    if not c or now >= c.at + DANGER_SCAN_MS or (c.a and not c.a:isAlive()) then
        local n, a, ad, ak, near, nearD2 = assessDangerScan(hitman, brain, zx, zy, zz)
        c = { at = now, n = n, a = a, ad = ad, ak = ak, near = near, nearD2 = nearD2 }
        _dng[brain.id] = c
    end
    return c.n, c.a, c.ad, c.ak, c.near, c.nearD2
end

-- ── 드론 호위 로직 스캔 (중심점 cx,cy 반경 r) ────────────────────────────────
-- 반환: 표적, 군, 대원과의 거리
local function droneScan(hitman, brain, cx, cy, r, zx, zy, zz)
    local cache = HitmanZombie.Cache
    local r2 = r * r
    local maxR2 = _lockR * _lockR
    local cands, n = {}, 0
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - cx, light.y - cy
        if dx <= r and dx >= -r and dy <= r and dy >= -r and math.abs(light.z - zz) < 0.5 then
            local d2 = dx * dx + dy * dy
            local tx, ty = light.x - zx, light.y - zy
            if d2 <= r2 and tx * tx + ty * ty <= maxR2 and HitmanUtils.AreEnemies(light.brain, brain) then
                local z = cache[id]
                if validEnemy(z, hitman, zz) then
                    local tier = droneTier(z)
                    n = n + 1
                    cands[n] = { z = z, tier = tier, rank = TIER_ORDER[tier], d2 = d2 }
                end
            end
        end
    end
    if n > 1 then table.sort(cands, candLess) end
    for i = 1, n do
        local z = cands[i].z
        if visible(hitman, z) then
            local dx, dy = z:getX() - zx, z:getY() - zy
            return z, cands[i].tier, math.sqrt(dx * dx + dy * dy)
        end
    end
    return nil
end

-- 여유 상태 최선 표적: phase2(대원 10타일) 가 있으면 그것, 없으면 phase3(플레이어 20타일)
local function relaxedBest(hitman, brain, zx, zy, zz)
    local z, tier, d = droneScan(hitman, brain, zx, zy, SELF_R, zx, zy, zz)
    if z then return z, 2, tier, d end
    local escort = HitmanUtils.GetTrackedPlayer(hitman)
    if escort then
        z, tier, d = droneScan(hitman, brain, escort:getX(), escort:getY(), ESCORT_SCAN_R, zx, zy, zz)
        if z then return z, 3, tier, d end
    end
    return nil
end

-- 지금 표적의 여유 상태 phase/군 (phase2 반경 안이면 2, phase3 반경 안이면 3, 둘 다 밖이면 nil)
local function relaxedClassOf(hitman, z, zx, zy)
    local dx, dy = z:getX() - zx, z:getY() - zy
    if dx * dx + dy * dy <= SELF_R * SELF_R then return 2, droneTier(z) end
    local escort = HitmanUtils.GetTrackedPlayer(hitman)
    if escort then
        local ex, ey = z:getX() - escort:getX(), z:getY() - escort:getY()
        if ex * ex + ey * ey <= ESCORT_SCAN_R * ESCORT_SCAN_R then return 3, droneTier(z) end
    end
    return nil
end

local function better(p1, t1, p2, t2)
    if p1 ~= p2 then return p1 < p2 end
    return TIER_ORDER[t1] < TIER_ORDER[t2]
end

-- ── 표적 고정 ────────────────────────────────────────────────────────────────
local _lock = {}   -- [brain.id] = { z, phase, tier, lostAt, fresh }
local _scan = {}   -- [brain.id] = { at, z, phase, tier, d }

local function lockTo(brain, z, phase, tier, d, why)
    local prev = _lock[brain.id]
    _lock[brain.id] = { z = z, phase = phase, tier = tier, fresh = true }
    print(string.format("[PongDu][Airborne] lock id=%s -> %s phase=%d tier=%s dist=%.1f (%s%s)",
        tostring(brain.id), tostring(HitmanUtils.GetCharacterID(z)), phase, tier, d or -1, why,
        prev and (", was " .. tostring(HitmanUtils.GetCharacterID(prev.z)) .. " phase=" .. tostring(prev.phase)) or ""))
end

local function releaseLock(brain, why)
    if _lock[brain.id] then
        print("[PongDu][Airborne] lock released id=" .. tostring(brain.id) .. " (" .. why .. ")")
        _lock[brain.id] = nil
    end
end

-- 여유 상태 표적 선정 (phase2/3). 반환: 표적, 거리, phase  |  nil = 쏠 표적 없음
local function pickRelaxed(hitman, brain, now, zx, zy, zz)
    local L = _lock[brain.id]
    local cur, curD, curP, curT, hidden
    local force = false   -- 이번에 고정이 풀렸으면 주기와 무관하게 바로 다시 찾는다 (즉시 전환)
    if L then
        local t = L.z
        if not t or t:isDead() or not t:isAlive() then
            releaseLock(brain, "target down")
            force = true
        elseif HitmanZombie.Cache[HitmanUtils.GetCharacterID(t)] ~= t then
            releaseLock(brain, "gone")   -- 월드에서 빠짐(언로드/제거): 살아 있어도 쏠 수 없다
            force = true
        else
            local dx, dy = t:getX() - zx, t:getY() - zy
            curD = math.sqrt(dx * dx + dy * dy)
            if math.abs(t:getZ() - zz) < 0.5 and curD <= _lockR and visible(hitman, t) then
                L.lostAt = nil
                curP, curT = relaxedClassOf(hitman, t, zx, zy)
                if curP then
                    cur = t
                    L.phase, L.tier = curP, curT
                else
                    releaseLock(brain, string.format("out of range, dist=%.1f", curD))
                    force = true
                end
            else
                if not L.lostAt then L.lostAt = now; force = true end
                if now - L.lostAt > LOCK_LOST_MS then
                    releaseLock(brain, string.format("lost %dms, dist=%.1f", now - L.lostAt, curD))
                    force = true
                else
                    hidden = t
                end
            end
        end
    end

    -- 최선 후보 재계산: PICK_SCAN_MS 주기, 또는 방금 고정이 풀렸거나 표적이 가려졌을 때 즉시.
    -- (쏠 표적이 없는 대기 중에는 주기대로만 -- 매 프레임 시야 검사를 반복하지 않게)
    local s = _scan[brain.id]
    if not s or force or now >= s.at + PICK_SCAN_MS then
        local z, p, t, d = relaxedBest(hitman, brain, zx, zy, zz)
        s = { at = now, z = z, phase = p, tier = t, d = d }
        _scan[brain.id] = s
    end
    local bz = s.z
    if bz and (bz:isDead() or not bz:isAlive()) then bz = nil end

    if cur then
        if bz and bz ~= cur and better(s.phase, s.tier, curP, curT) then
            lockTo(brain, bz, s.phase, s.tier, s.d, "higher priority")
            return bz, s.d, s.phase
        end
        return cur, curD, curP
    end
    if bz then
        lockTo(brain, bz, s.phase, s.tier, s.d, hidden and "locked target hidden" or "new")
        return bz, s.d, s.phase
    end
    return nil   -- 가려진 표적만 있거나 아무도 없음: 사격 중지(고정은 유지)
end

local function setState(brain, state, why)
    if brain.abState ~= state then
        print(string.format("[PongDu][Airborne] state id=%s %s -> %s (%s)",
            tostring(brain.id), tostring(brain.abState or "LANDED"), state, why))
        brain.abState = state
    end
end

-- ManageCombat 진입점. gunRange = 지금 쏠 총의 사거리 (총이 없으면 nil)
-- 반환: "flee", 태스크  |  "fire", 표적, 거리, phase  |  "hold"(교전인데 쏠 표적 없음)  |  "patrol"
function _a.Think(hitman, brain, gunRange)
    local now = getTimestampMs()
    _lockR = (gunRange and gunRange > 0) and gunRange or DETECT_R
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()

    -- 후퇴 중이면 도착/시간초과까지 계속 달린다
    if brain.abRetreat then
        local t = _a.RetreatTick(hitman, brain)
        if t then return "flee", t end
    end

    local det = detect(hitman, brain, now, zx, zy, zz)
    if det.found then brain.abFace = { x = det.nx, y = det.ny } end
    if not (det.seenAt and now - det.seenAt <= DETECT_GRACE_MS) then
        setState(brain, "PATROL", "no zombie in sight within " .. DETECT_R)
        brain.abFace = nil
        if _lock[brain.id] then releaseLock(brain, "patrol") end
        return "patrol"
    end

    -- 순찰 -> 교전 전환: 걷던 순찰 구간을 끊는다 (안 끊으면 표적이 없을 때 구간 끝까지 걷는다)
    if brain.abState == "PATROL" and Hitman.HasMoveTask(hitman) then
        Hitman.ClearTasks(hitman)
    end

    -- 위험
    local n, attacker, ad, akind, near, nearD2 = assessDanger(hitman, brain, now, zx, zy, zz)
    if near and not near:isAlive() then near = nil end
    if n >= RETREAT_N then
        local t = _a.RetreatTick(hitman, brain)
        if t then
            setState(brain, "FLEE", n .. " enemies within " .. RETREAT_R)
            return "flee", t
        end
    end
    local danger = attacker or (n >= RETREAT_N and near)
    if danger then
        local d = ad or math.sqrt(nearD2)
        local L = _lock[brain.id]
        if not L or L.z ~= danger then
            lockTo(brain, danger, 1, "A", d, akind and ("danger " .. akind) or ("danger crowd " .. n))
        else
            L.phase, L.tier = 1, "A"
        end
        setState(brain, "FIRE", "danger")
        return "fire", danger, d, 1
    end

    -- 여유
    setState(brain, "FIRE", string.format("zombie seen at %.1f", det.nd or -1))
    local t, d, p = pickRelaxed(hitman, brain, now, zx, zy, zz)
    if t then return "fire", t, d, p end
    return "hold"
end

-- 사격 계획. 총 이름을 보지 않고 FireSpec(플레이어가 그 총을 쏠 때의 박자)으로 탄수를 정한다.
--   연사 총 : CLOSE_R 이내 SUSTAIN_S 초 분량을 이어서, 그 밖은 FAR_BURST_S 초 분량 점사 후 FAR_PAUSE_S 쉼
--   점사 총 : 한 번에 그 총의 점사 탄수. 점사 사이는 그 총의 재발사 간격(cycle) 이상
--   단발 총 : CLOSE_R 이내 SUSTAIN_S 초 동안 쏠 수 있는 만큼, 그 밖은 1발씩 FAR_PAUSE_S 쉼
--   발 사이 간격은 ZAShoot 이 spec.rate 로 지킨다(태스크가 바뀌어도 이어진다).
-- fresh = 막 새로 잡은 표적(_a.TakeFreshLock): 전술상 쉬는 시간 없이 바로 쏜다.
-- turnRate: 사격 태스크가 표적 쪽으로 TURN_DEG_PER_S 로 돌면서 쏜다. 총구가 아직 표적을
-- 향하지 않은 동안 나가는 탄은 총구 방향으로 날아가(눈먼 탄) 그 선 위의 좀비를 맞힐 수 있다.
local function roundsFor(rate, seconds)
    local n = math.floor(rate * seconds + 0.5)
    if n < 1 then n = 1 end
    return n
end

function _a.FirePlan(hitman, weaponName, dist, fresh)
    local item = HitmanCompatibility.InstanceItem(weaponName)
    if not item then return nil end   -- 기본 히트맨 사격 규칙으로
    local spec = HitmanPrograms.Weapon.FireSpec(item, hitman)
    local close = dist <= CLOSE_R

    local pause = (close or fresh) and 0 or FAR_PAUSE_S   -- 전술상 쉬는 시간
    local bullets
    if spec.auto then
        bullets = roundsFor(spec.rate, close and SUSTAIN_S or FAR_BURST_S)
    elseif (spec.burst or 1) > 1 then
        bullets = spec.burst
        -- 점사 사이 반동 대기(cycle)는 총의 성질이라 새 표적이어도 줄지 않는다.
        -- 단발/연사는 ZAShoot 이 rate 로 발 간격을 지키므로 여기서 더할 필요가 없다.
        if pause < spec.cycle then pause = spec.cycle end
    else
        bullets = close and roundsFor(spec.rate, SUSTAIN_S) or 1
    end

    return { bullets = bullets, firstTime = math.floor(pause * 60 + 0.5), turnRate = _a.TURN_DEG_PER_S }
end

-- 지금 표적이 새로 잡은 뒤 아직 한 번도 사격 계획을 안 세운 표적이면 true (한 번만).
function _a.TakeFreshLock(brain)
    local L = _lock[brain.id]
    if L and L.fresh then
        L.fresh = nil
        return true
    end
    return false
end

-- ═══════════════════════════════════════════════════════════════════════════
--  전략적 후퇴 (HitmanUpdate.lua ManageCombat 이 표적 선정보다 먼저 부른다)
--
--  대원 RETREAT_R 타일 안에 적이 RETREAT_N 마리 이상이면, 그 무리의 중심 반대쪽으로
--  RETREAT_DIST 타일 달려 빠진 뒤 다시 쏜다. 후퇴 중에는 사격하지 않는다.
--  정반대가 막혀 있으면 좌우 30/60/90도로 틀어 본다. 다 막히면 그 자리에서 싸운다.
--  반환: nil = 후퇴 아님(평소대로 교전) / 태스크 목록 = 후퇴 중(비어 있으면 이동 중)
-- ═══════════════════════════════════════════════════════════════════════════
local RETREAT_DIST     = 10
local RETREAT_REACH    = 1.3
local RETREAT_MAX_MS   = 7000    -- 막혀서 못 가면 이 시간 뒤 포기하고 교전 재개
local RETREAT_CD_MS    = 1500    -- 후퇴 직후 재발동 대기 (도착하자마자 또 뛰는 것 방지)
local RETREAT_ANGLES   = { 0, 30, -30, 60, -60, 90, -90 }

local function retreatSquareOk(cell, x, y, z)
    local sq = cell:getGridSquare(math.floor(x), math.floor(y), z)
    if not sq or not sq:isFree(false) then return false end
    if sq:Is(IsoFlagType.water) then return false end
    return true
end

function _a.RetreatTick(hitman, brain)
    local now = getTimestampMs()
    local zx, zy, zz = hitman:getX(), hitman:getY(), hitman:getZ()
    local r = brain.abRetreat
    if r then
        local dx, dy = r.x - zx, r.y - zy
        local d = math.sqrt(dx * dx + dy * dy)
        if d <= RETREAT_REACH or now > r.untilMs then
            brain.abRetreat = nil
            brain.abRetreatCd = now + RETREAT_CD_MS
            print(string.format("[PongDu][Airborne] retreat done id=%s %s (left %.1f tiles)",
                tostring(brain.id), d <= RETREAT_REACH and "reached" or "timeout", d))
            return nil
        end
        -- 물리면 태스크가 비워지므로(UpdateZombies bite -> ClearTasks) 이동을 다시 건다
        if not Hitman.HasMoveTask(hitman) then
            return { HitmanUtils.GetMoveTask(0, r.x, r.y, r.z, "Run", d, false) }
        end
        return {}
    end
    if brain.abRetreatCd and now < brain.abRetreatCd then return nil end

    local cache = HitmanZombie.Cache
    local r2 = RETREAT_R * RETREAT_R
    local n, sx, sy = 0, 0, 0
    for id, light in pairs(HitmanZombie.CacheLight) do
        local dx, dy = light.x - zx, light.y - zy
        if dx <= RETREAT_R and dx >= -RETREAT_R and dy <= RETREAT_R and dy >= -RETREAT_R
           and dx * dx + dy * dy <= r2 and math.abs(light.z - zz) < 1
           and HitmanUtils.AreEnemies(light.brain, brain) then
            local o = cache[id]
            if o and o ~= hitman and o:isAlive() and not o:getVariableBoolean("Bandit") then
                n = n + 1
                sx, sy = sx + light.x, sy + light.y
            end
        end
    end
    if n < RETREAT_N then return nil end

    local vx, vy = zx - sx / n, zy - sy / n
    local base
    if vx * vx + vy * vy < 0.01 then
        base = ZombRand(360)   -- 한가운데 포위: 아무 방향
    else
        base = math.deg(math.atan2(vy, vx))
    end
    local cell = getCell()
    local tx, ty
    for i = 1, #RETREAT_ANGLES do
        local a = math.rad(base + RETREAT_ANGLES[i])
        local x, y = zx + math.cos(a) * RETREAT_DIST, zy + math.sin(a) * RETREAT_DIST
        if retreatSquareOk(cell, x, y, zz) then
            tx, ty = x, y
            break
        end
    end
    if not tx then
        print("[PongDu][Airborne] retreat blocked id=" .. tostring(brain.id) .. " enemies=" .. n .. " -- fighting in place")
        brain.abRetreatCd = now + RETREAT_CD_MS
        return nil
    end

    brain.abRetreat = { x = tx, y = ty, z = zz, untilMs = now + RETREAT_MAX_MS }
    Hitman.ClearTasks(hitman)
    print(string.format("[PongDu][Airborne] retreat start id=%s enemies=%d within %d -> %d,%d",
        tostring(brain.id), n, RETREAT_R, math.floor(tx), math.floor(ty)))
    return { HitmanUtils.GetMoveTask(0, tx, ty, zz, "Run", RETREAT_DIST, false) }
end

-- 대원 사망 시 표적/후퇴 상태 정리 (HitmanUpdate.lua OnZombieDead 에서 호출)
function _a.Forget(brain)
    if brain and brain.id then
        _det[brain.id] = nil
        _dng[brain.id] = nil
        _scan[brain.id] = nil
        _lock[brain.id] = nil
    end
end

return _a
