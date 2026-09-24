-- 차량 보급 낙하산 하강 연출 (개봉자 클라 = 물리 권한 클라에서만 동작).
--
-- 서버(server/t3VehicleDropSpawner.lua startChuteDrop)가 보급 차량과 낙하산 리그
-- (Base.PongDuChuteRig)를 지상에 스폰하고 두 차량의 Local 물리 권한을 개봉자에게
-- 준 뒤 ChuteStart를 보낸다(SP는 직접 호출). 이 파일은 매 틱:
--   ① 보급 차량을 "지면 + 현재 고도"로 텔레포트 (고도는 시간에 따라 선형 감소)
--   ② 리그를 보급 차량 바로 위(지붕 + 여유)로 텔레포트
--   ③ 고도가 releaseAlt 이하가 되면 차량 고정을 풀고 물리(중력)로 착지시킴
--   ④ settleMs 동안 리그만 차량 위를 따라가다가 서버에 ChuteLanded 보고
-- 서버는 리그 제거 + 바닥 낙하산 배치 + 권한 반환을 한다.
-- 다른 클라는 아무것도 안 해도 엔진 물리 스트림(sendPhysic)으로 같은 모습을 본다.
--
-- 텔레포트 방식은 헬기 화력지원(features/firesupport.lua heliMoveTo)과 동일하다:
-- BaseVehicle의 private tempTransform을 리플렉션으로 꺼내 getWorldTransform ->
-- origin 수정 -> setWorldTransform(클라에서는 내부적으로 Bullet.teleportVehicle).
-- 물리 좌표축: origin.x = iso x(월드심 오프셋 좌표계), origin.y = 고도, origin.z = iso y.
-- 월드심 오프셋은 플레이어 이동에 따라 바뀔 수 있으므로 x/z는 매 틱 차량의 현재
-- origin 값을 그대로 쓰고 y(고도)만 덮어쓴다.

t3VehicleDropChute = t3VehicleDropChute or {}

local LOG = "[t3VehicleDrop] chute: "

-- 리그 원점(산줄이 모이는 점)을 보급 차량 지붕에서 얼마나 띄울지(물리 y).
local RIG_ROOF_GAP = 0.35
local RIG_MODEL_SCRIPT = "PongDuChuteCluster"

-- 진단 로그
local PROGRESS_LOG_MS  = 2000  -- 하강 중 진행 로그 주기
local HOLD_WARN_DIST   = 1.0   -- 텔레포트 목표 대비 실제 높이가 이만큼 어긋나면 경고
local HOLD_WARN_MS     = 3000  -- 위 경고 반복 주기
local LAND_WARN_HEIGHT = 0.5   -- 착지 보고 시 지면보다 이만큼 높으면 "공중 정지 의심" 경고
local ERR_LOG_EVERY    = 10    -- 틱 에러는 첫 회 + 이 횟수마다 한 번 로그

local _jobs = {}      -- [cargoVid] = job
local _count = 0      -- Kahlua에 next()가 없어 개수로 빈 테이블 판정
local _fieldNum = nil -- BaseVehicle.tempTransform 필드 인덱스 (클래스 공용)

local function fieldNum(obj, name)
    for i = 0, getNumClassFields(obj) - 1 do
        local f = getClassField(obj, i)
        if luautils.stringEnds(tostring(f), "." .. name) then return i end
    end
    return nil
end

-- 차량의 월드 트랜스폼(tempTransform에 복사된 것)과 그 origin(Vector3f)을 돌려준다.
local function getOrigin(v)
    if not _fieldNum then _fieldNum = fieldNum(v, "tempTransform") end
    if not _fieldNum then error("tempTransform field not found") end
    local tmp = getClassFieldVal(v, getClassField(v, _fieldNum))
    local tr = v:getWorldTransform(tmp)
    local origin = getClassFieldVal(tr, getClassField(tr, 1))
    return tr, origin
end

local function setOrigin(v, ox, oy, oz)
    local tr, origin = getOrigin(v)
    origin:set(ox, oy, oz)
    v:setWorldTransform(tr)
end

-- MP 물리 권한/정적/활성 상태 한 줄 요약 (BaseVehicle.getAuthorizationDescription).
-- 차량이 안 움직이면 대부분 auth가 Local이 아니거나 static=true 인 경우다.
local function authDesc(v)
    if not v then return "nil" end
    local ok, s = pcall(function() return v:getAuthorizationDescription() end)
    if ok then return tostring(s) end
    return "auth-read-failed(" .. tostring(s) .. ")"
end

-- VehicleID 재활용 가드: 스크립트명까지 맞아야 우리 차량으로 인정한다.
local function findVehicle(vid, scriptName)
    if not vid then return nil end
    local ok, v = pcall(function() return getVehicleById(vid) end)
    if not ok or not v then return nil end
    local okS, sn = pcall(function() return v:getScriptName() end)
    if okS and sn == scriptName then return v end
    return nil
end

-- 순회 중 테이블 삭제를 피하려고 tickJob은 종료 사유만 job.closeWhy에 적고,
-- 실제 삭제는 onTick 루프가 끝난 뒤 한다 (firesupport.lua의 _expired 패턴).
local function removeJob(job, why)
    if _jobs[job.cargoVid] then
        _jobs[job.cargoVid] = nil
        _count = _count - 1
    end
    print(LOG .. "job closed cargo=" .. tostring(job.cargoVid) .. " (" .. tostring(why) .. ")")
end

local function closeJob(job, why)
    job.closeWhy = job.closeWhy or why
end

local function reportLanded(job)
    if isClient() then
        sendClientCommand("PongDuVehicleDrop", "ChuteLanded", { cargoVid = job.cargoVid })
    elseif t3VehicleDrop and t3VehicleDrop.chuteLanded then
        -- SP: server/t3VehicleDropSpawner.lua가 같은 프로세스에 로드돼 있다
        t3VehicleDrop.chuteLanded(job.cargoVid, nil)
    else
        print(LOG .. "t3VehicleDrop.chuteLanded missing, landing decor not applied")
    end
end

-- 보급 차량 지붕 높이(원점 기준). 스크립트 값은 Loaded()에서 model scale이 이미 곱해져 있다.
-- extents는 전체 크기라 절반만 올린다.
local function roofOffset(v)
    local ok, off = pcall(function()
        local sc = v:getScript()
        return sc:getCenterOfMassOffset():y() + sc:getExtents():y() * 0.5
    end)
    if ok and off then return off + RIG_ROOF_GAP end
    print(LOG .. "roof offset read FAILED, using default err=" .. tostring(off))
    return 1.5 + RIG_ROOF_GAP
end

local function placeRig(job, ox, cargoY, oz, now)
    local rig = findVehicle(job.rigVid, job.rigScript)
    if not rig then
        if not job.rigMissingLogged then
            job.rigMissingLogged = true
            print(LOG .. "rig not streamed yet vid=" .. tostring(job.rigVid)
                .. " -- if this never resolves, the parachutes will not show (check server rig spawn log)")
        end
        return
    end
    if not job.rigAcquired then
        job.rigAcquired = true
        print(LOG .. "rig acquired vid=" .. tostring(job.rigVid) .. " " .. authDesc(rig))
    end
    job.rigY = cargoY + job.roofOff
    setOrigin(rig, ox, job.rigY, oz)
end

-- 하강 중 주기 로그 + "텔레포트가 안 먹는" 상황 경고.
-- actualY(이번 틱 시작 시 실제 높이)가 직전 틱에 넣은 목표(lastTargetY)와 크게 다르면
-- 텔레포트가 물리에 덮어써지고 있다는 뜻이다(권한 없음/static 바디 등).
local function progressLog(job, cargo, alt, actualY, now)
    if job.lastTargetY then
        local diff = math.abs(actualY - job.lastTargetY)
        if diff > HOLD_WARN_DIST and now - (job.holdWarnAt or 0) >= HOLD_WARN_MS then
            job.holdWarnAt = now
            print(string.format("%sWARN teleport not holding vid=%s actualY=%.2f lastTarget=%.2f diff=%.2f %s",
                LOG, tostring(job.cargoVid), actualY, job.lastTargetY, diff, authDesc(cargo)))
        end
    end
    if now - (job.progressAt or 0) >= PROGRESS_LOG_MS then
        job.progressAt = now
        print(string.format("%sdescending vid=%s alt=%.2f actualY=%.2f rigY=%s rig=%s %s",
            LOG, tostring(job.cargoVid), alt, actualY,
            job.rigY and string.format("%.2f", job.rigY) or "none",
            job.rigAcquired and "ok" or "missing", authDesc(cargo)))
    end
end

local function tickJob(job, now)
    local cargo = findVehicle(job.cargoVid, job.cargoScript)
    if not cargo then
        if not job.cargoMissingLogged then
            job.cargoMissingLogged = true
            print(LOG .. "cargo not available vid=" .. tostring(job.cargoVid) .. " script=" .. tostring(job.cargoScript)
                .. " phase=" .. tostring(job.phase) .. " -- not streamed yet or vid reused")
        end
        if now > job.localDeadline then closeJob(job, "local deadline, cargo missing in phase " .. tostring(job.phase)) end
        return
    end
    if job.cargoMissingLogged and job.phase ~= "wait" and not job.cargoBackLogged then
        job.cargoBackLogged = true
        print(LOG .. "cargo available again vid=" .. tostring(job.cargoVid))
    end

    local _, origin = getOrigin(cargo)
    local ox, oy, oz = origin:x(), origin:y(), origin:z()

    if job.phase == "wait" then
        -- 첫 확보 시점의 높이가 스폰 지면 높이다 (addVehicleDebug는 지상에 놓는다).
        job.groundY = oy
        job.roofOff = roofOffset(cargo)
        job.t0 = now
        job.phase = "descend"
        print(string.format("%scargo acquired vid=%s after %dms groundY=%.3f roofOff=%.2f startAlt=%.1f speed=%.2f %s",
            LOG, tostring(job.cargoVid), now - job.startedAt, oy, job.roofOff, job.startAlt, job.speed, authDesc(cargo)))
    end

    if job.phase == "descend" then
        local alt = job.startAlt - job.speed * (now - job.t0) / 1000
        progressLog(job, cargo, alt, oy, now)
        if alt <= job.releaseAlt then
            job.phase = "settle"
            job.releaseAt = now
            -- 비활성 물리 바디는 중력이 안 걸리므로 확실히 깨운다
            local okP, errP = pcall(function() cargo:setPhysicsActive(true) end)
            if not okP then
                print(LOG .. "setPhysicsActive(true) FAILED vid=" .. tostring(job.cargoVid) .. " err=" .. tostring(errP))
            end
            print(string.format("%sreleased vid=%s at alt=%.2f after %dms %s",
                LOG, tostring(job.cargoVid), alt, now - job.t0, authDesc(cargo)))
            placeRig(job, ox, oy, oz, now)
            return
        end
        local y = job.groundY + alt
        setOrigin(cargo, ox, y, oz)
        job.lastTargetY = y
        placeRig(job, ox, y, oz, now)
        return
    end

    if job.phase == "settle" then
        -- 차량은 물리로 떨어지는 중. 리그만 차량 위를 따라간다.
        placeRig(job, ox, oy, oz, now)
        if now - job.releaseAt >= job.settleMs then
            local height = oy - job.groundY
            print(string.format("%slanded vid=%s y=%.3f ground=%.3f height=%.3f rig=%s, reporting %s",
                LOG, tostring(job.cargoVid), oy, job.groundY, height,
                job.rigAcquired and "ok" or "never-acquired", authDesc(cargo)))
            if height > LAND_WARN_HEIGHT then
                print(string.format("%sWARN cargo still %.2f above ground after settle -- physics not falling? vid=%s",
                    LOG, height, tostring(job.cargoVid)))
            end
            reportLanded(job)
            closeJob(job, "landed")
        end
    end
end

local _closing = {}

local function onTick()
    if _count <= 0 then return end
    local now = getTimestampMs()
    local n = 0
    for _, job in pairs(_jobs) do
        local ok, err = pcall(tickJob, job, now)
        if not ok then
            job.errCount = (job.errCount or 0) + 1
            if job.errCount == 1 or job.errCount % ERR_LOG_EVERY == 0 then
                print(string.format("%stick FAILED cargo=%s phase=%s count=%d err=%s",
                    LOG, tostring(job.cargoVid), tostring(job.phase), job.errCount, tostring(err)))
            end
            -- 계속 실패하면 공중에 영구 고정되지 않도록 포기한다(서버 데드라인이 마무리).
            if job.errCount >= 30 then
                closeJob(job, "too many tick errors (" .. tostring(job.errCount) .. "), server deadline will finish")
            end
        end
        if job.closeWhy then
            n = n + 1
            _closing[n] = job
        end
    end
    for i = 1, n do
        removeJob(_closing[i], _closing[i].closeWhy)
        _closing[i] = nil
    end
end

-- 에셋 누락은 런타임 에러 없이 "그냥 안 보이는" 증상이라 시작 시 한 번 확인해 둔다.
local _assetChecked = false
local function checkAssets(rigScript)
    if _assetChecked then return end
    _assetChecked = true
    local sm = getScriptManager()
    local okV, vs = pcall(function() return sm:getVehicle(rigScript) end)
    local okM, ms = pcall(function() return sm:getModelScript(RIG_MODEL_SCRIPT) end)
    print(string.format("%sasset check vehicleScript(%s)=%s modelScript(%s)=%s",
        LOG, tostring(rigScript), (okV and vs) and "ok" or "MISSING",
        RIG_MODEL_SCRIPT, (okM and ms) and "ok" or "MISSING"))
end

function t3VehicleDropChute.start(args)
    local cargoVid = tonumber(args.cargoVid)
    local timeoutMs = tonumber(args.timeoutMs)
    if not cargoVid or not timeoutMs or not tonumber(args.startAlt) or not tonumber(args.speed) then
        print(LOG .. "ChuteStart bad args cargoVid=" .. tostring(args.cargoVid) .. " timeoutMs=" .. tostring(args.timeoutMs)
            .. " startAlt=" .. tostring(args.startAlt) .. " speed=" .. tostring(args.speed) .. " -- version mismatch?")
        return
    end
    checkAssets(args.rigScript)
    if _jobs[cargoVid] then
        print(LOG .. "ChuteStart duplicate for cargo=" .. tostring(cargoVid) .. ", replacing")
    else
        _count = _count + 1
    end
    local now = getTimestampMs()
    _jobs[cargoVid] = {
        cargoVid      = cargoVid,
        cargoScript   = args.cargoScript,
        rigVid        = tonumber(args.rigVid),
        rigScript     = args.rigScript,
        startAlt      = tonumber(args.startAlt),
        releaseAlt    = tonumber(args.releaseAlt),
        speed         = tonumber(args.speed),
        settleMs      = tonumber(args.settleMs),
        startedAt     = now,
        localDeadline = now + timeoutMs,
        phase         = "wait",
    }
    print(string.format("%sstart cargo=%s(%s) rig=%s timeout=%sms active=%d",
        LOG, tostring(cargoVid), tostring(args.cargoScript), tostring(args.rigVid), tostring(args.timeoutMs), _count))
end

Events.OnTick.Add(onTick)

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuVehicleDrop" then return end
    if command == "ChuteStart" then
        t3VehicleDropChute.start(args)
    end
end)
