-- ═══════════════════════════════════════════════════════════════════════════
--  연사 총기 탄씹힘 수정 (저FPS에서 총구화염만 나고 탄이 안 나가는 문제)
--
--  원인 (B41 엔진):
--   총 한 발은 사격 애니 노드(AnimSets/player/ranged/...)의 AttackCollisionCheck 이벤트가
--   SwipeStatePlayer 에 도착해야 ConnectSwing -> OnWeaponSwingHitPoint 로 이어진다.
--   Arsenal 탄 차감, Improved Projectile 투사체 생성, 바닐라 히트 판정이 전부 여기서 일어난다.
--   노드들은 이 이벤트를 진행률(TimePc 0.001)로 걸어두는데, 진행률 이벤트는 "다음 프레임"의
--   AnimLayer 갱신에서야 확인된다. 사격 클립(Bob_AttackRifle_Small 0.667초)을 SpeedScale 로
--   빠르게 돌리는 연사 노드는 한 프레임이 (클립 길이 / SpeedScale) 보다 길어지면 클립이 한 번의
--   AnimationPlayer 갱신 안에서 시작하고 끝나버린다. 그러면 다음 프레임 맨 앞에서
--   ActiveAnimFinishing 으로 ranged 상태를 먼저 빠져나가고, 뒤늦게 확인된 진행률 이벤트는
--   받을 상태가 없어 버려진다. 화염/발사음은 그 전에(attackHook) 나오므로 쏜 것처럼 보인다.
--     Arsenal Auto/Burst x8  : 12 FPS 미만에서 손실
--     Real Life Fire Rate x10 : 15 FPS 미만
--     Arsenal [6]Rotary x15   : 22 FPS 미만
--   탄도학 모드는 대규모 좀비에서 FPS 를 떨어뜨려 이 문턱을 넘기게 만드는 쪽이고,
--   투사체를 막는 주체는 아니다 (손실은 탄도학 코드가 도는 ③ 이전 단계에서 난다).
--
--  수정 (손실되는 발에만 끼어드는 End 폴백):
--   AttackCollisionCheck 를 End 시점에도 하나 더 건다. End 이벤트는 클립이 끝나는(조기 전환
--   노드는 페이드아웃이 시작되는) 그 트랙 갱신 안에서 트랙이 직접 보낸다. 손실되는 경우는
--   "클립이 첫 갱신 한 번에 끝나는" 경우뿐이므로, 이때 End 는 ActiveAnimFinishing 과 같은
--   갱신에서 오고 ranged 상태 이탈(다음 프레임)보다 앞선다 -> 이 한 발이 연결된다.
--   정상 프레임에서는 원래 진행률 판정이 다음 프레임 AnimLayer 갱신에서 먼저 연결되고
--   (PARAM_ATTACKED), 그 뒤에 오는 End 판정은 SwipeStatePlayer 가 무시한다.
--   즉 정상 발은 판정 시점·횟수가 바닐라와 완전히 같고, 손실될 발만 End 에서 연결된다.
--   도중에 상태가 끊긴 발(피격 반응·밀치기 전환 등)은 노드가 TransitioningOut 이라 클립 끝 End 가
--   안 나가므로 바닐라처럼 연결되지 않는다. (조기 전환 노드의 페이드아웃 End 는 이 검사가 없지만,
--   그 시점엔 ranged 하위 상태가 이미 빠져 있어 받을 SwipeStatePlayer 가 없다. 예외적으로
--   길이가 다른 클립을 섞은 조기 전환 노드에서 다음 발이 이미 ranged 에 들어와 있으면 그 발이
--   최대 1프레임 먼저 연결될 수 있다. 바닐라 AttackAnim End 도 같은 경로로 새며, 한 스윙 1발은 유지된다.)
--   (이전 방식은 Start 시점에 걸어서 모든 발의 판정을 한 프레임 당겼다. 손실과 무관한 발의
--    타이밍까지 바꾸는 것이라 End 폴백으로 좁혔다.)
--   XML 파일을 덮어쓰지 않고 로드된 노드에 이벤트만 더하므로 Arsenal / Real Life Fire Rate /
--   다른 총기 모드가 정한 연사속도는 그대로 유지되고 모드 로드 순서와도 무관하다.
--   End 이벤트 객체는 PongDuShotEventDonor.xml(선택되지 않는 추상 노드)에서 가져온다.
--   AnimEvent 는 Lua 에서 만들 수 없어서 로드된 객체를 재사용한다.
--
--  대상: ranged 상태의 노드 중 AttackCollisionCheck 가 진행률 1% 이하에 있는 것
--   (투척 Throw 처럼 중간 시점에 판정하는 노드는 건드리지 않는다).
--   Start/End 판정을 이미 가진 노드(바닐라 바닥조준 FirearmOnFloor 등)는 원래 손실이 없어서 건너뛴다.
--  애니셋은 캐릭터마다가 아니라 이름별 공유 객체라 한 번만 고치면 된다.
--  차량 탑승 시 쓰는 player-vehicle 애니셋도 바뀌는 순간 같이 고친다.
--  Kahlua 는 AnimNode 등을 노출하지 않으므로 공개 필드를 getClassField 리플렉션으로 읽는다.
--
--  PongDuShotComp(저FPS 연사속도 보정)용으로 두 가지를 전역 PongDuShotFix 에 내보낸다:
--   fieldVal  : 아래 리플렉션 헬퍼
--   shotClips : 판정 이벤트가 있는 ranged 노드들이 쓰는 클립 이름 집합 (m_AnimName + 2D 블렌드, 소문자)
-- ═══════════════════════════════════════════════════════════════════════════
local LOG = "[PongDu][ShotFix] "
local DONOR_NAME = "PongDuShotEventDonor"
local DONOR_TIME = "End"
local EARLY_PC = 0.01
local CHECK_MS = 1000

-- 필드 이름으로 공개 필드 값을 읽는다. Field 객체는 클래스별로 한 번만 찾는다.
local fieldCache = {}
local function fieldVal(obj, kind, name)
    local key = kind .. "." .. name
    local f = fieldCache[key]
    if f == nil then
        f = false
        local suffix = "." .. name
        local slen = string.len(suffix)
        for i = 0, getNumClassFields(obj) - 1 do
            local cf = getClassField(obj, i)
            local s = tostring(cf)
            if string.sub(s, -slen) == suffix then
                f = cf
                break
            end
        end
        fieldCache[key] = f
        if not f then print(LOG .. "field not found: " .. key) end
    end
    if not f then return nil end
    return getClassFieldVal(obj, f)
end

PongDuShotFix = PongDuShotFix or {}
PongDuShotFix.fieldVal = fieldVal
PongDuShotFix.shotClips = PongDuShotFix.shotClips or {}

-- 노드가 재생하는 클립 이름(단일 애니 + 2D 블렌드 트랙)을 소문자로 shotClips 에 모은다
local function addClip(name)
    if not name or name == "" then return 0 end
    local k = string.lower(name)
    if PongDuShotFix.shotClips[k] then return 0 end
    PongDuShotFix.shotClips[k] = true
    return 1
end

local function addClips(node)
    local n = addClip(fieldVal(node, "node", "m_AnimName"))
    local blends = fieldVal(node, "node", "m_2DBlends")
    if blends then
        for j = 0, blends:size() - 1 do
            n = n + addClip(fieldVal(blends:get(j), "blend", "m_AnimName"))
        end
    end
    return n
end

local function eventInfo(ev)
    local name = fieldVal(ev, "event", "m_EventName")
    local time = tostring(fieldVal(ev, "event", "m_Time"))
    local pc = tonumber(tostring(fieldVal(ev, "event", "m_TimePc")))
    local param = fieldVal(ev, "event", "m_ParameterValue")
    return name and string.lower(name) or "", time, pc, param
end

local donorMissLogged = false
local donor = nil -- { hit = AttackCollisionCheck(End), set = SetVariable ZombieHitReaction=Shot(End) }

local function findDonor(nodes)
    for i = 0, nodes:size() - 1 do
        local node = nodes:get(i)
        if fieldVal(node, "node", "m_Name") == DONOR_NAME then
            local evs = fieldVal(node, "node", "m_Events")
            local d = {}
            for j = 0, evs:size() - 1 do
                local ev = evs:get(j)
                local name, time, _, param = eventInfo(ev)
                if time == DONOR_TIME then
                    if name == "attackcollisioncheck" then
                        d.hit = ev
                    elseif name == "setvariable" and param == "ZombieHitReaction=Shot" then
                        d.set = ev
                    end
                end
            end
            if d.hit then return d end
        end
    end
    return nil
end

local function patchSet(animSet)
    local setName = tostring(fieldVal(animSet, "set", "m_Name"))
    local states = fieldVal(animSet, "set", "states")
    if not states then
        print(LOG .. "animset=" .. setName .. " states unreadable, skipped")
        return
    end
    local ranged = states:get("ranged")
    if not ranged then
        print(LOG .. "animset=" .. setName .. " has no ranged state, nothing to patch")
        return
    end
    local nodes = fieldVal(ranged, "state", "m_Nodes")
    if not nodes then
        print(LOG .. "animset=" .. setName .. " ranged nodes unreadable, skipped")
        return
    end
    if not donor then donor = findDonor(nodes) end
    if not donor then
        -- 기부 노드는 player 애니셋에만 있다. 차량 안에서 시작해 player-vehicle 을 먼저 만나면
        -- 하차 후 player 애니셋에서 찾을 때까지 이 애니셋은 보류한다.
        if not donorMissLogged then
            donorMissLogged = true
            print(LOG .. "animset=" .. setName .. " donor node " .. DONOR_NAME .. " not found yet, shot fix waiting")
        end
        return false
    end

    local patched, already, names, newClips = 0, 0, {}, 0
    for i = 0, nodes:size() - 1 do
        local node = nodes:get(i)
        local nodeName = fieldVal(node, "node", "m_Name")
        local evs = fieldVal(node, "node", "m_Events")
        if evs and nodeName ~= DONOR_NAME then
            local earlyHit, timedHit, shotVar = false, false, false
            for j = 0, evs:size() - 1 do
                local name, time, pc, param = eventInfo(evs:get(j))
                if name == "attackcollisioncheck" then
                    if time == "Start" or time == "End" then
                        timedHit = true
                    elseif time == "Percentage" and pc and pc <= EARLY_PC then
                        earlyHit = true
                    end
                elseif name == "setvariable" and time == "Percentage" and pc and pc <= EARLY_PC
                    and param == "ZombieHitReaction=Shot" then
                    shotVar = true
                end
            end
            if timedHit or earlyHit then
                newClips = newClips + addClips(node)
            end
            if timedHit then
                already = already + 1
            elseif earlyHit then
                -- End 이벤트는 리스트 순서대로 돈다. SetVariable 을 먼저 넣어야 판정보다 먼저 적용된다
                if shotVar and donor.set then evs:add(donor.set) end
                evs:add(donor.hit)
                patched = patched + 1
                names[#names + 1] = tostring(nodeName)
            end
        end
    end
    print(string.format(LOG .. "animset=%s ranged nodes=%d patched=%d (End fallback) alreadyTimed=%d shotClips+%d [%s]",
        setName, nodes:size(), patched, already, newClips, table.concat(names, ",")))
    return true
end

local done = {}
local nextCheck = 0

local function checkPlayer(player)
    local adv = player:getAdvancedAnimator()
    if not adv then return end
    local animSet = fieldVal(adv, "animator", "animSet")
    if not animSet or done[animSet] then return end
    local ok, res = pcall(patchSet, animSet)
    if not ok then
        -- 예외는 매 초 반복해도 결과가 같으므로 한 번만 남기고 포기한다
        done[animSet] = true
        print(LOG .. "patch failed: " .. tostring(res))
    elseif res ~= false then
        done[animSet] = true
    end
end

Events.OnPlayerUpdate.Add(function(player)
    if not player or not player:isLocalPlayer() then return end
    local now = getTimestampMs()
    if now < nextCheck then return end
    nextCheck = now + CHECK_MS
    local ok, err = pcall(checkPlayer, player)
    if not ok then print(LOG .. "check failed: " .. tostring(err)) end
end)
