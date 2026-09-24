-- t3VehicleDrop.spawnVehicle: 실제 addVehicleDebug 호출부.
-- 이 파일은 media/lua/server/ 아래 있으므로 "솔로"와 "진짜 서버"에서만 로드된다.
-- 진짜 MP 클라이언트에서는 로드되지 않으므로, 반드시
-- shared/t3VehicleDrop.lua 의 OpenKit(solo면 직접호출 / MP면 sendClientCommand)을
-- 거쳐서만 호출되어야 한다 (InsurgentStartLUV AirdroppedLUVSpawnVehicle.lua와 동일 구조).

t3VehicleDrop = t3VehicleDrop or {}

local TARGET_CONDITION_MIN = 90 -- 기증 차량 컨디션 하한 (0~100)
local TARGET_CONDITION_MAX = 100 -- 기증 차량 컨디션 상한 (0~100)

-- 차량 주변에 펼쳐진 낙하산 데코를 뿌린다 (순수 연출용, 실패해도 무시).
-- 차량을 중심에 두고 등각으로 벌려 놓고, 각 낙하산이 바깥을 보도록 모델을 돌린다.
-- 실제로 놓인 타일 좌표를 "x,y,z" 문자열 배열로 돌려주고, 호출부가 차량 modData에
-- 심어둔다. 플레이어가 그 차량에 타는 순간 회수하기 위한 것.
--
-- [중심 정렬] 세 낙하산의 산줄이 모이는 점(하네스)이 차량 중심 한 점에 오도록
-- 아이템 원점을 "차량 중심 + 하네스 거리 x 바깥 방향"에 칸 안 오프셋까지 정확히 놓는다.
-- 예전 방식은 세 가지가 겹쳐 중심이 어긋났다:
--   ① 아이템 원점을 반경 5칸에 놓았는데 원점->하네스가 2.95칸이라 하네스가 중심에서 약 2칸 떨어짐
--   ② 반경 오프셋을 정수 칸으로 반올림하고 칸 중앙(0.5,0.5)에 놓음 (최대 0.7칸 오차)
--   ③ 기준점을 스폰 칸 모서리에서 y-1 보정(x 보정값은 선언만 되고 안 쓰임)
local PARACHUTE_TYPE = "t3chzzkDonation.t3DeployedParachute"
local PARACHUTE_COUNT = 3 -- 등각 분할 개수 (3이면 120도 간격)

-- 모델 원점 -> 하네스 거리(타일). t3DeployedParachute.fbx 실측값:
-- 노드 변환(x100) x 모델 스크립트 scale 0.005 적용 후 하네스는 로컬 (+2.95, 0.05),
-- 캐노피 끝은 -x 쪽(-3.45). 메시를 교체하면 이 값도 다시 재야 한다.
local PARACHUTE_HARNESS_DIST = 2.95
-- 하네스를 차량 중심에서 바깥으로 더 뺄 거리(타일). 0이면 세 산줄이 차량 중심에서 만난다.
local PARACHUTE_HARNESS_GAP = 0

-- 낙하산 메쉬의 기준 방향 보정값 (도). 로컬 +x(하네스 쪽)가 차량 중심을 향하게 한다.
local PARACHUTE_MODEL_ANGLE_OFFSET = 180

-- AddWorldInventoryItem의 x/y는 칸 안 오프셋(0~1)이다. 정확히 0이면
-- IsoWorldInventoryObject 생성자가 무작위 값으로 바꿔버리므로(생성자 xoff == 0 분기) 살짝 띄운다.
local function clampTileOffset(v)
    if v < 0.001 then return 0.001 end
    if v > 0.999 then return 0.999 end
    return v
end

local function scatterParachutes(centerX, centerY, z)
    local cell = getCell()
    local placed = {}
    local r = PARACHUTE_HARNESS_DIST + PARACHUTE_HARNESS_GAP

    -- 매번 같은 방위로 고정되면 티가 나므로 시작 각도만 무작위로 돌린다.
    -- (등각 간격 자체는 유지되므로 방사형 배치는 그대로)
    local startAngle = ZombRand(360)
    local step = 360 / PARACHUTE_COUNT

    for i = 0, PARACHUTE_COUNT - 1 do
        local angleDeg = (startAngle + step * i) % 360
        local rad = math.rad(angleDeg)
        local px = centerX + r * math.cos(rad)
        local py = centerY + r * math.sin(rad)
        local tx, ty = math.floor(px), math.floor(py)

        local sq = cell:getGridSquare(tx, ty, z)
        if sq and sq:isOutside() then
            -- 문자열 오버로드가 아니라 아이템 인스턴스를 먼저 만든다.
            -- IsoWorldInventoryObject 생성자가 worldZRotation < 0 일 때만 랜덤값을
            -- 채우므로, 미리 넣어두면 그 각도가 그대로 유지된다.
            local item = instanceItem(PARACHUTE_TYPE)
            if item then
                item:setWorldZRotation(math.floor((angleDeg + PARACHUTE_MODEL_ANGLE_OFFSET) % 360))
                sq:AddWorldInventoryItem(item, clampTileOffset(px - tx), clampTileOffset(py - ty), 0)
                placed[#placed + 1] = sq:getX() .. "," .. sq:getY() .. "," .. sq:getZ()
                print(string.format("[t3VehicleDrop] Parachute %d placed at %.2f,%.2f (angle %d, center %.2f,%.2f)",
                    i + 1, px, py, math.floor(angleDeg), centerX, centerY))
            else
                print("[t3VehicleDrop] Failed to instance parachute item: " .. PARACHUTE_TYPE)
            end
        else
            print(string.format("[t3VehicleDrop] Parachute %d skipped at %.2f,%.2f (%s)",
                i + 1, px, py, sq and "indoor" or "square not loaded"))
        end
    end
    return placed
end

-- 보급 차량에 처음 탑승했을 때 연출용 낙하산을 월드에서 지운다.
-- 좌표는 스폰 시점에 차량 modData에 심어둔 값을 쓴다 (차량이 이동한 뒤여도 무관).
-- 낙하산은 AddWorldInventoryItem으로 놓은 월드 인벤토리 아이템이라, 오브젝트용
-- transmitRemoveItemFromSquare만으로는 부족하고 removeWorldObject까지 같이 불러야 한다
-- (바닐라 ISMoveableSpriteProps가 월드아이템을 치울 때 쓰는 조합).
--
-- 낙하산을 다 치운 김에, 개봉자 본인 맵에 찍혀 있던 투하 지점 마커(파란 배 심볼)도
-- 같이 지운다. 마커는 client/VehicleDropMapMarker.lua가 "개봉한 플레이어 본인의
-- 맵에만" 찍어두는 것이라, 여기서도 그 사람(t3DropOwnerUsername) 앞으로만 알림을
-- 보낸다 -- 지금 탑승한 사람이 개봉자와 다를 수 있기 때문(다른 사람이 먼저 타는 경우).
local function findOnlinePlayerByUsername(username)
    if not username or username == "" then return nil end
    local players = getOnlinePlayers()
    for i = 0, players:size() - 1 do
        local p = players:get(i)
        if p and p:getUsername() == username then return p end
    end
    return nil
end

local function notifyMarkerRemoval(ownerUsername, mx, my)
    if not isClient() and not isServer() then
        -- 솔로: client/VehicleDropMapMarker.lua도 같은 프로세스에 로드돼 있다.
        if t3VehicleDropMarker then
            t3VehicleDropMarker.remove(getPlayer(), mx, my)
        end
    elseif isServer() then
        local owner = findOnlinePlayerByUsername(ownerUsername)
        if owner then
            sendServerCommand(owner, "PongDuVehicleDrop", "RemoveMapMarker", { x = mx, y = my })
        end
        -- 개봉자가 오프라인이면 알릴 방법이 없다 -- 그 사람 맵에 마커 하나가
        -- 영구히 남는 정도의 사소한 흔적이라 별도 재시도 큐는 두지 않는다.
    end
end

function t3VehicleDrop.clearParachutes(vehicle)
    if not vehicle then return end

    -- 모든 차량 탑승에서 호출되므로, 우리 보급차가 아니면 조용히 빠진다 (로그 스팸 방지)
    local modData = vehicle:getModData()
    local coords = modData.t3ParachuteSquares
    if type(coords) ~= "table" or #coords == 0 then return end

    local cell = getCell()
    local removed = 0
    for i = 1, #coords do
        local sx, sy, sz = string.match(coords[i], "^(-?%d+),(-?%d+),(-?%d+)$")
        if sx then
            local sq = cell:getGridSquare(tonumber(sx), tonumber(sy), tonumber(sz))
            if sq then
                local worldObjects = sq:getWorldObjects()
                -- 역순 순회: 제거하면 리스트 인덱스가 당겨진다
                for j = worldObjects:size() - 1, 0, -1 do
                    local worldObject = worldObjects:get(j)
                    local item = worldObject:getItem()
                    if item and item:getFullType() == PARACHUTE_TYPE then
                        sq:transmitRemoveItemFromSquare(worldObject)
                        sq:removeWorldObject(worldObject)
                        removed = removed + 1
                    end
                end
            end
        else
            print("[t3VehicleDrop] Malformed parachute coord: " .. tostring(coords[i]))
        end
    end

    -- 한 번 치웠으면 재진입 때 다시 훑지 않도록 마킹을 지운다
    modData.t3ParachuteSquares = nil

    -- 맵마커 정리 알림 (연출용, 실패해도 무시)
    local center = modData.t3DropCenter
    local ownerUsername = modData.t3DropOwnerUsername
    modData.t3DropCenter = nil
    modData.t3DropOwnerUsername = nil
    if center then
        local mx, my = string.match(center, "^(-?%d+),(-?%d+)$")
        if mx then
            notifyMarkerRemoval(ownerUsername, tonumber(mx), tonumber(my))
        else
            print("[t3VehicleDrop] Malformed drop center: " .. tostring(center))
        end
    end

    print("[t3VehicleDrop] Parachutes cleared on vehicle entry: " .. removed)
end

-- 바닐라 trySpawnKey가 addToWorld 시점에 자동으로 뿌리는 키를 회수한다.
-- (BaseVehicle 디컴파일 기준 자동 키의 행선지: 점화구/도어, 글로브박스,
--  차량 기준 ±10타일 z0~2의 counter/officedrawers/shelves/desk 컨테이너,
--  같은 범위 바닥 월드아이템, 그리고 ±10타일 내 좀비의 사망드랍.)
-- 좀비 사망드랍(addItemToSpawnAtDeath)만은 제거 API가 없어 회수 불가 — 드물게
-- 근처 좀비 시체에서 여분 키가 나올 수 있는 알려진 한계.
local KEY_CLEANUP_RADIUS = 10 -- addKeyToSquare의 탐색 반경과 동일

local function isAutoKey(item, keyId)
    return item and item:getType() == "CarKey" and item:getKeyId() == keyId
end

local function removeKeysFromContainer(container, keyId)
    if not container then return 0 end
    local removed = 0
    local items = container:getItems()
    for i = items:size() - 1, 0, -1 do
        local item = items:get(i)
        if isAutoKey(item, keyId) then
            container:Remove(item)
            removed = removed + 1
        end
    end
    return removed
end

local function removeAutoSpawnedKeys(vehicle)
    local keyId = vehicle:getKeyId()
    local removed = 0

    -- 점화구/도어에 꽂힌 키
    if vehicle:isKeysInIgnition() then vehicle:setKeysInIgnition(false) end
    if vehicle:isKeyIsOnDoor() then vehicle:setKeyIsOnDoor(false) end
    if vehicle:getCurrentKey() then
        vehicle:setCurrentKey(nil)
        removed = removed + 1
    end

    -- 글로브박스 (VehicleEasyUse=true면 여기로 확정 스폰됨)
    local gloveBox = vehicle:getPartById("GloveBox")
    if gloveBox then
        removed = removed + removeKeysFromContainer(gloveBox:getItemContainer(), keyId)
    end

    -- 차량 기준 ±10타일, z 0~2: 바닥 월드아이템 + 가구 컨테이너
    local cell = getCell()
    local vx = math.floor(vehicle:getX())
    local vy = math.floor(vehicle:getY())
    for sx = vx - KEY_CLEANUP_RADIUS, vx + KEY_CLEANUP_RADIUS do
        for sy = vy - KEY_CLEANUP_RADIUS, vy + KEY_CLEANUP_RADIUS do
            for sz = 0, 2 do
                local sq = cell:getGridSquare(sx, sy, sz)
                if sq then
                    -- 바닥 월드아이템
                    local wobjs = sq:getWorldObjects()
                    for i = wobjs:size() - 1, 0, -1 do
                        local wobj = wobjs:get(i)
                        local item = wobj and wobj:getItem()
                        if isAutoKey(item, keyId) then
                            sq:transmitRemoveItemFromSquare(wobj)
                            removed = removed + 1
                        end
                    end
                    -- 가구 컨테이너 (trySpawnKey가 노리는 4종만)
                    local objs = sq:getObjects()
                    for i = 0, objs:size() - 1 do
                        local obj = objs:get(i)
                        local cont = obj and obj:getContainer()
                        if cont then
                            local ctype = cont:getType()
                            if ctype == "counter" or ctype == "officedrawers"
                                or ctype == "shelves" or ctype == "desk" then
                                removed = removed + removeKeysFromContainer(cont, keyId)
                            end
                        end
                    end
                end
            end
        end
    end

    print("[t3VehicleDrop] Auto-spawned keys removed: " .. removed .. " (keyId " .. tostring(keyId) .. ")")
end

-- 착지 후 연출: 바닥 낙하산 아이템을 뿌리고, 탑승 시 회수할 수 있도록 좌표를 차량 modData에
-- 심어둔다. 예전엔 스폰 직후 바로 실행했지만, 이제는 낙하산 하강 연출이 끝나 착지한 뒤
-- (finishChuteJob) 실행한다. 리그 스폰 실패로 하강 연출을 못 하면 스폰 직후 바로 부른다.
-- 낙하산 중심은 착지한 차량의 실제 위치, t3DropCenter는 맵마커를 찍은 원래 투하 좌표 기준이다.
--
-- modData는 재조회(getVehicleById)한 실제 차량 인스턴스에 세팅해야 붙는다.
-- transmitModData는 부르지 않는다 -- IsoObject 구현이 square의 Objects 인덱스를
-- 전제하는데 차량은 거기 등록되지 않아 신뢰할 수 없다. 이 값은 서버에서만 읽으면 되고,
-- 차량 세이브에 함께 저장되므로 서버 재시작 후에도 남는다.
local function applyLandingDecor(vehicle, z, dropX, dropY, ownerUsername)
    if not vehicle then return 0 end
    -- 착지한 차량의 실제(소수점) 위치를 중심으로 쓴다
    local parachuteSquares = scatterParachutes(vehicle:getX(), vehicle:getY(), z)
    if #parachuteSquares > 0 then
        vehicle:getModData().t3ParachuteSquares = parachuteSquares
        -- 맵마커 정리 알림용. 마커는 개봉자 본인 맵에만 찍혀 있으므로 그 사람
        -- 유저네임과, 마커를 찍을 때 쓴 것과 동일한 좌표(x,y)를 같이 심어둔다.
        vehicle:getModData().t3DropCenter = tostring(dropX) .. "," .. tostring(dropY)
        vehicle:getModData().t3DropOwnerUsername = ownerUsername or ""
    end
    return #parachuteSquares
end

-- ═══════════════════════════════════════════════════════════════════════════
--  낙하산 하강 연출 (Base.PongDuChuteRig)
--
--  보급 차량을 지상에 스폰한 뒤, 개봉자 클라(VehicleDropChute.lua)가 차량을
--  공중으로 올려 천천히 내리고, 낙하산 3개짜리 리그 차량을 차량 지붕 위에 붙여
--  같이 내린다. 차량을 공중에 띄우는 방식은 헬기 화력지원과 동일하다
--  (리플렉션 tempTransform -> setWorldTransform, firesupport.lua heliMoveTo).
--
--  MP 동기화 구조 (헬기와 동일):
--   ① 서버: 보급 차량 + 리그 스폰 -> authorizationChanged(개봉자)로 Local 물리 권한
--   ② 개봉자 클라: ChuteStart 수신 -> 매 틱 텔레포트 -> 엔진 물리 스트림으로 전파
--   ③ 착지 후 개봉자 클라가 ChuteLanded 전송 -> 서버가 리그 제거 + 바닥 낙하산
--      배치 + 차량 권한을 Server로 되돌림(평소 주차 차량과 같은 상태)
--   ④ 개봉자 이탈/스트리밍 실패 대비: 서버 자체 데드라인에서 같은 마무리를 강제
--
--  리그를 보급 차량과 같은 칸에 스폰하면 IsoChunk.doSpawnedVehiclesInInvalidPosition의
--  차량 간 충돌 검사에 걸려 월드에 추가되지 않는다(addVehicleDebug는 그래도 객체를
--  돌려준다). 그래서 투하 영역(반경 7칸 전부 실외/빈칸, findDropSquare) 안에서
--  몇 칸 떨어진 곳에 스폰하고, 클라가 첫 틱에 차량 지붕 위로 옮긴다.
-- ═══════════════════════════════════════════════════════════════════════════

local CHUTE_RIG_SCRIPT     = "Base.PongDuChuteRig"
local CHUTE_START_ALT      = 10.0   -- 지면 대비 시작 고도(물리 y). 2.46 = 1층 -> 약 4층
local CHUTE_RELEASE_ALT    = 0.4    -- 이 고도까지 내려오면 고정을 풀고 물리 낙하로 착지
-- 하강 시간은 샌드박스 VehicleDrop_ChuteDuration(초)으로 조절한다(수치 튜닝용, 추후 하드코딩 예정).
-- 속도(물리 y/초) = (CHUTE_START_ALT - CHUTE_RELEASE_ALT) / 하강 시간.
local CHUTE_SETTLE_MS      = 1200   -- 고정 해제 후 착지 안정 대기(ms)
local CHUTE_STREAM_WAIT_MS = 15000  -- 클라가 차량을 받기까지 허용하는 대기(ms)
local CHUTE_DEADLINE_PAD_MS = 8000  -- 서버 데드라인 여유(ms)
local CHUTE_TICK_MS        = 1000   -- 서버 데드라인 검사 주기
local CHUTE_ORPHAN_MS      = 10000  -- 추적 안 되는 리그 정리 주기

-- 리그 스폰 후보 오프셋. 보급 차량은 IsoDirections.S로 스폰되어 y축으로 길다.
-- 폭 방향(x)을 우선 쓰고, 투하 영역(반경 7) 밖으로도 한 번 더 넓혀 본다.
local CHUTE_RIG_OFFSETS = {
    { 6, 0 }, { -6, 0 }, { 5, 5 }, { -5, 5 }, { 5, -5 }, { -5, -5 },
    { 0, 7 }, { 0, -7 }, { 9, 0 }, { -9, 0 }, { 0, 10 }, { 0, -10 },
}

-- [cargoVid] = job. 서버(또는 SP)에서만 채워진다. 이 파일은 MP 클라에서도
-- 로드되지만 거기선 spawnVehicle이 호출되지 않으므로 항상 비어 있다.
t3VehicleDrop._chuteJobs = t3VehicleDrop._chuteJobs or {}

-- 샌드박스 값은 사용 시점에 읽는다(파일 로드 시 캐싱하면 런타임 변경이 안 먹는다).
local function chuteDurationSec()
    return SandboxVars.PongDu.VehicleDrop_ChuteDuration
end

local function chuteDescentMs()
    return math.floor(chuteDurationSec() * 1000)
end

local function findChuteRig(vid)
    if not vid then return nil end
    local v = getVehicleById(vid)
    if not v then return nil end
    local ok, sn = pcall(function() return v:getScriptName() end)
    if ok and sn == CHUTE_RIG_SCRIPT then return v end
    return nil
end

-- VehicleID는 서버에서 재활용되므로(VehicleIDMap freeID LIFO) 스크립트명까지 맞아야
-- 우리 보급 차량으로 인정한다 (firesupport.lua findHeliVehicle과 같은 가드).
local function findChuteCargo(job)
    local v = getVehicleById(job.cargoVid)
    if not v then return nil end
    local ok, sn = pcall(function() return v:getScriptName() end)
    if ok and sn == job.cargoScript then return v end
    return nil
end

-- MP 물리 권한 상태 한 줄 요약 (BaseVehicle.getAuthorizationDescription).
local function chuteAuthDesc(v)
    if not v then return "nil" end
    local ok, s = pcall(function() return v:getAuthorizationDescription() end)
    if ok then return tostring(s) end
    return "auth-read-failed(" .. tostring(s) .. ")"
end

local function spawnChuteRig(x, y, z)
    -- 스크립트 파싱 실패/파일 누락이면 addVehicleDebug가 스크립트 없는 차량을 만든다.
    -- 원인 파악이 어려운 증상이라 여기서 먼저 걸러 로그를 남긴다.
    local okS, rigScript = pcall(function() return getScriptManager():getVehicle(CHUTE_RIG_SCRIPT) end)
    if not okS or not rigScript then
        print("[t3VehicleDrop] Chute rig script " .. CHUTE_RIG_SCRIPT
            .. " NOT LOADED (pongdu_chute_rig_vehicle.txt missing or parse error)")
        return nil
    end

    local cell = getCell()
    local skippedNil, skippedIndoor = 0, 0
    for i = 1, #CHUTE_RIG_OFFSETS do
        local o = CHUTE_RIG_OFFSETS[i]
        local sq = cell:getGridSquare(x + o[1], y + o[2], z)
        if not sq then
            skippedNil = skippedNil + 1
        elseif not sq:isOutside() then
            skippedIndoor = skippedIndoor + 1
        else
            local ok, v = pcall(function()
                return addVehicleDebug(CHUTE_RIG_SCRIPT, IsoDirections.N, 0, sq)
            end)
            if ok and v then
                -- 충돌 검사에 걸리면 월드에 안 들어간 객체가 돌아오므로 재조회로 확인
                local rig = getVehicleById(v:getId())
                if rig then
                    print(string.format("[t3VehicleDrop] Chute rig spawned vid=%s at %d,%d (offset %d,%d)",
                        tostring(rig:getId()), sq:getX(), sq:getY(), o[1], o[2]))
                    return rig
                end
                print(string.format("[t3VehicleDrop] Chute rig rejected at %d,%d (collision/indoor), trying next",
                    sq:getX(), sq:getY()))
            else
                print("[t3VehicleDrop] Chute rig addVehicleDebug FAILED err=" .. tostring(v))
            end
        end
    end
    print(string.format("[t3VehicleDrop] Chute rig: no usable square around %d,%d,%d (candidates=%d unloaded=%d indoor=%d)",
        x, y, z, #CHUTE_RIG_OFFSETS, skippedNil, skippedIndoor))
    return nil
end

local function finishChuteJob(job, reason)
    -- 1) 리그 제거: permanentlyRemove가 제거 패킷을 전 클라에 보내고 VehiclesDB에서도 지운다
    local rig = findChuteRig(job.rigVid)
    if rig then
        local ok, err = pcall(function() rig:permanentlyRemove() end)
        if ok then
            print("[t3VehicleDrop] Chute rig removed vid=" .. tostring(job.rigVid))
        else
            print("[t3VehicleDrop] Chute rig remove FAILED vid=" .. tostring(job.rigVid) .. " err=" .. tostring(err))
        end
    else
        print("[t3VehicleDrop] Chute rig not found on finish vid=" .. tostring(job.rigVid))
    end

    local cargo = findChuteCargo(job)
    if not cargo then
        -- 청크 언로드 등으로 서버가 차량을 못 잡으면 modData를 못 심는다.
        -- 이때 낙하산을 뿌리면 탑승해도 영영 안 치워지므로 뿌리지 않는다.
        print("[t3VehicleDrop] Chute finish (" .. tostring(reason) .. "): cargo vid="
            .. tostring(job.cargoVid) .. " not found, landing decor skipped")
        return
    end

    -- 2) 이미 누가 탔으면 탑승 회수 이벤트가 지나간 뒤라 낙하산을 뿌리면 안 치워진다.
    --    권한도 운전자 것(authorizationServerOnSeat)이므로 건드리지 않는다.
    if cargo:getDriver() then
        print("[t3VehicleDrop] Chute finish (" .. tostring(reason) .. "): cargo already driven, decor/authority skipped")
        return
    end

    -- 3) 물리 권한을 Server로 되돌린다(평소 주차 차량 상태 = 클라에서 static).
    --    서버 데드라인으로 강제 종료된 경우 차량이 공중이면 그 자리에 굳을 수 있다
    --    (누가 타서 권한을 가져가면 다시 떨어진다). 로그로 구분해 둔다.
    if isServer() then
        local okA, errA = pcall(function() cargo:authorizationChanged(nil) end)
        if okA then
            print("[t3VehicleDrop] Chute authority reset to Server: " .. chuteAuthDesc(cargo))
        else
            print("[t3VehicleDrop] Chute authority reset FAILED err=" .. tostring(errA) .. " " .. chuteAuthDesc(cargo))
        end
    end

    -- 4) 착지 지점 기준 바닥 낙하산 + modData
    local placed = applyLandingDecor(cargo, job.z, job.x, job.y, job.owner)
    print(string.format("[t3VehicleDrop] Chute finish (%s): cargo vid=%s landed at %.1f,%.1f, parachutes placed=%d",
        tostring(reason), tostring(job.cargoVid), cargo:getX(), cargo:getY(), placed))
end

-- finishChuteJob 안에서 에러가 나면 리그/권한/낙하산이 어중간하게 남으므로 원인을 로그로 남긴다.
local function safeFinishChuteJob(job, reason)
    local ok, err = pcall(finishChuteJob, job, reason)
    if not ok then
        print("[t3VehicleDrop] Chute finish (" .. tostring(reason) .. ") FAILED cargo vid="
            .. tostring(job.cargoVid) .. " rig vid=" .. tostring(job.rigVid) .. " err=" .. tostring(err))
    end
end

-- 착지 보고(개봉자 클라 -> 서버, SP는 직접 호출). reporter가 있으면 그 job의 개봉자인지 확인한다.
function t3VehicleDrop.chuteLanded(cargoVid, reporter)
    local vid = tonumber(cargoVid)
    local job = vid and t3VehicleDrop._chuteJobs[vid]
    if not job then
        print("[t3VehicleDrop] ChuteLanded for unknown job vid=" .. tostring(cargoVid) .. " (already finished?)")
        return
    end
    if reporter and job.pilotId and reporter:getOnlineID() ~= job.pilotId then
        print("[t3VehicleDrop] ChuteLanded ignored: reporter " .. tostring(reporter:getOnlineID())
            .. " is not the pilot " .. tostring(job.pilotId) .. " (vid=" .. tostring(vid) .. ")")
        return
    end
    t3VehicleDrop._chuteJobs[vid] = nil
    print(string.format("[t3VehicleDrop] ChuteLanded received vid=%s after %dms",
        tostring(vid), getTimestampMs() - job.startedAt))
    safeFinishChuteJob(job, "landed")
end

-- 하강 연출 시작. 리그 스폰에 실패하면 false -> 호출부가 예전처럼 즉시 착지 처리.
local function startChuteDrop(player, vehicle, x, y, z)
    if not t3VehicleDropChute and not isServer() then
        -- SP인데 클라 모듈이 없으면(로드 실패) 연출을 돌릴 주체가 없다
        print("[t3VehicleDrop] t3VehicleDropChute not loaded, chute descent skipped")
        return false
    end

    local rig = spawnChuteRig(x, y, z)
    if not rig then
        print("[t3VehicleDrop] Chute rig spawn FAILED at all offsets, falling back to instant landing")
        return false
    end

    local now = getTimestampMs()
    local durationSec = chuteDurationSec()
    local speed = (CHUTE_START_ALT - CHUTE_RELEASE_ALT) / durationSec
    local job = {
        cargoVid    = vehicle:getId(),
        cargoScript = vehicle:getScriptName(),
        rigVid      = rig:getId(),
        x = x, y = y, z = z,
        player      = player,
        owner       = player and player:getUsername() or "",
        startedAt   = now,
        deadline    = now + CHUTE_STREAM_WAIT_MS + chuteDescentMs() + CHUTE_SETTLE_MS + CHUTE_DEADLINE_PAD_MS,
    }

    if isServer() then
        -- 헬기와 같은 권한 부여 경로(authorizationServerCollide는 Kahlua short 변환 문제로 못 씀)
        local okA, errA = pcall(function()
            job.pilotId = player:getOnlineID()
            vehicle:authorizationChanged(player)
            rig:authorizationChanged(player)
        end)
        if okA then
            print("[t3VehicleDrop] Chute authority granted pilot=" .. tostring(job.pilotId)
                .. " cargo[" .. chuteAuthDesc(vehicle) .. "] rig[" .. chuteAuthDesc(rig) .. "]")
        else
            print("[t3VehicleDrop] Chute authority grant FAILED err=" .. tostring(errA))
        end
    end

    t3VehicleDrop._chuteJobs[job.cargoVid] = job

    local args = {
        cargoVid    = job.cargoVid,
        cargoScript = job.cargoScript,
        rigVid      = job.rigVid,
        rigScript   = CHUTE_RIG_SCRIPT,
        startAlt    = CHUTE_START_ALT,
        releaseAlt  = CHUTE_RELEASE_ALT,
        speed       = speed,
        settleMs    = CHUTE_SETTLE_MS,
        timeoutMs   = job.deadline - now,
    }
    if isServer() then
        sendServerCommand(player, "PongDuVehicleDrop", "ChuteStart", args)
    else
        t3VehicleDropChute.start(args)
    end

    print(string.format("[t3VehicleDrop] Chute descent started cargo=%s(%s) rig=%s alt=%.1f duration=%.2fs speed=%.3f deadline=%dms",
        tostring(job.cargoVid), tostring(job.cargoScript), tostring(job.rigVid),
        CHUTE_START_ALT, durationSec, speed, job.deadline - now))
    return true
end

-- 서버 데드라인 + 고아 리그 정리. 이 파일은 MP 클라에서도 로드되므로(server.lua
-- addServerTick 주석 참고) 클라에서는 등록하지 않는다. SP는 isClient()가 false라 등록된다.
local _chuteLastTick = 0
local _chuteLastOrphan = 0

local function chuteIsTrackedRig(vid)
    for _, job in pairs(t3VehicleDrop._chuteJobs) do
        if job.rigVid == vid then return true end
    end
    return false
end

-- 서버 재시작/세이브 로드 등으로 job 없이 남은 리그를 치운다 (화력지원 orphan sweep과 같은 이유).
local function chuteSweepOrphanRigs()
    local ok, cell = pcall(getCell)
    if not ok or not cell then return end
    local vehicles = cell:getVehicles()
    if not vehicles then return end
    for i = vehicles:size() - 1, 0, -1 do
        local v = vehicles:get(i)
        if v then
            local okS, sn = pcall(function() return v:getScriptName() end)
            if okS and sn == CHUTE_RIG_SCRIPT and not chuteIsTrackedRig(v:getId()) then
                local okR, err = pcall(function() v:permanentlyRemove() end)
                print("[t3VehicleDrop] Orphan chute rig vid=" .. tostring(v:getId())
                    .. (okR and " removed" or (" remove FAILED err=" .. tostring(err))))
            end
        end
    end
end

local function chuteServerTick()
    local now = getTimestampMs()
    if now - _chuteLastTick >= CHUTE_TICK_MS then
        _chuteLastTick = now
        local expired = nil
        for vid, job in pairs(t3VehicleDrop._chuteJobs) do
            if now > job.deadline then
                expired = expired or {}
                expired[#expired + 1] = vid
            end
        end
        if expired then
            for i = 1, #expired do
                local job = t3VehicleDrop._chuteJobs[expired[i]]
                t3VehicleDrop._chuteJobs[expired[i]] = nil
                print("[t3VehicleDrop] Chute job deadline reached vid=" .. tostring(expired[i])
                    .. " (pilot lost or vehicle not streamed), forcing finish")
                safeFinishChuteJob(job, "deadline")
            end
        end
    end
    if now - _chuteLastOrphan >= CHUTE_ORPHAN_MS then
        _chuteLastOrphan = now
        chuteSweepOrphanRigs()
    end
end

-- OnTick 핸들러 에러는 매 틱 반복되므로 첫 회 + 10초마다 한 번만 남긴다.
local _chuteTickErrAt = 0
local _chuteTickErrCount = 0
local function chuteServerTickSafe()
    local ok, err = pcall(chuteServerTick)
    if not ok then
        _chuteTickErrCount = _chuteTickErrCount + 1
        local now = getTimestampMs()
        if _chuteTickErrCount == 1 or now - _chuteTickErrAt >= 10000 then
            _chuteTickErrAt = now
            print("[t3VehicleDrop] Chute server tick FAILED count=" .. tostring(_chuteTickErrCount) .. " err=" .. tostring(err))
        end
    end
end

if not isClient() then
    Events.OnTick.Add(chuteServerTickSafe)
end

function t3VehicleDrop.spawnVehicle(player, x, y, z, vehicleType, sender)
    local square = getCell():getGridSquare(x, y, z)
    if not square then
        print("[t3VehicleDrop] Square not found at (" .. tostring(x) .. "," .. tostring(y) .. "," .. tostring(z) .. "), spawn cancelled")
        return
    end

    local vehicle = addVehicleDebug(vehicleType, IsoDirections.S, nil, square)
    if not vehicle then
        print("[t3VehicleDrop] Vehicle spawn failed: " .. tostring(vehicleType))
        return
    end

    -- addVehicleDebug 직후 반환값이 완전하지 않을 수 있어 재조회 (AirdroppedLUV와 동일 관례)
    local vehicleId = vehicle:getId()
    vehicle = getVehicleById(vehicleId)
    if not vehicle then
        print("[t3VehicleDrop] Failed to re-acquire vehicle after spawn: " .. tostring(vehicleType))
        return
    end

    -- 바닐라가 자동으로 뿌린 키 회수 (우리 키만 유일한 키가 되도록)
    removeAutoSpawnedKeys(vehicle)

    -- 연료 풀
    local gasTank = vehicle:getPartById("GasTank")
    if gasTank then
        gasTank:setContainerContentAmount(gasTank:getContainerCapacity() * 100)
        vehicle:transmitPartModData(gasTank)
    end

    -- 배터리 정상화
    local battery = vehicle:getBattery()
    if battery then
        battery:setDelta(1)
        vehicle:transmitPartUsedDelta(battery)
        vehicle:transmitPartModData(battery)
    end

    -- 부품 상태를 90~100 사이 값(차량당 1회 결정)으로 강제 세팅.
    -- cond가 0(완파)이어도 반드시 세팅해야 하므로 하한 조건(cond >= 1)은 두지 않음.
    local targetCondition = ZombRand(TARGET_CONDITION_MIN, TARGET_CONDITION_MAX + 1)
    for i = 0, vehicle:getPartCount() - 1 do
        local part = vehicle:getPartByIndex(i)
        if part:getCategory() ~= "nodisplay" then
            local cond = part:getCondition()
            if cond and cond < targetCondition then
                part:setCondition(targetCondition)
                vehicle:transmitPartCondition(part)
            end
        end
    end

    local engineLoudness = vehicle:getScript():getEngineLoudness() or 40
    local engineForce    = vehicle:getScript():getEngineForce()
    vehicle:setEngineFeature(100, engineLoudness, engineForce)
    vehicle:transmitEngine()

    -- 열쇠 지급.
    -- 키의 실체는 "CarKey 아이템 + keyId(int) 일치"가 전부라 (BaseVehicle.createVehicleKey
    -- 디컴파일 확인), 차량 객체 없이도 keyId만 있으면 어디서든 유효한 키를 만들 수 있다.
    -- 예전 방식(클라가 getVehicleById로 차량을 찾아 createVehicleKey)은 드랍 지점이
    -- 50~100타일이라 차량이 클라 스트리밍 범위 밖이면 조회 실패 -> 키 미지급 버그가 있었다.
    -- 이제 서버가 keyId/차종/색상만 뽑아 보내고, 클라(VehicleDropKeyGrant.lua)가
    -- 차량 조회 없이 로컬에서 키를 직접 생성한다.
    if not isClient() and not isServer() then
        -- 솔로: 같은 프로세스이므로 바로 생성+지급해도 동기화 문제 없음
        local key = vehicle:createVehicleKey()
        if key then
            local keyName = (sender and sender ~= "" and (sender .. "의 ") or "") .. key:getDisplayName()
            key:setName(keyName)
            player:getInventory():AddItem(key)
            print("[t3VehicleDrop] Solo key granted: " .. keyName)
        else
            print("[t3VehicleDrop] Solo key creation failed (vehicleId " .. tostring(vehicleId) .. ")")
        end
    elseif isServer() then
        -- 서버측 키를 임시 생성해 색상만 추출 (바닐라 키 색 = 차체 색 유지용)
        local colR, colG, colB
        local tmpKey = vehicle:createVehicleKey()
        local col = tmpKey and tmpKey:getColor()
        if col then
            colR, colG, colB = col:getR(), col:getG(), col:getB()
        end

        sendServerCommand(player, "PongDuVehicleDrop", "GrantKey", {
            keyId      = vehicle:getKeyId(),
            scriptName = vehicle:getScript():getName(),
            colR = colR, colG = colG, colB = colB,
            sender = sender,
            vehicleId = vehicleId, -- 로그 추적용
        })
        print("[t3VehicleDrop] GrantKey sent (keyId " .. tostring(vehicle:getKeyId()) .. ", vehicleId " .. tostring(vehicleId) .. ")")
    end

    print("[t3VehicleDrop] " .. tostring(vehicleType) .. " spawned (donor: " .. tostring(sender) .. ")")

    -- 낙하산 하강 연출. 바닥 낙하산 배치 + 탑승 회수용 modData는 착지 후(finishChuteJob)로
    -- 미뤄진다. 리그를 못 띄우면 예전처럼 스폰 지점에 바로 배치한다.
    if not startChuteDrop(player, vehicle, x, y, z) then
        local placed = applyLandingDecor(vehicle, z, x, y, player and player:getUsername() or "")
        print("[t3VehicleDrop] Instant landing decor placed=" .. tostring(placed))
    end
end
