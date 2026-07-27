local _a = {}

local global = require("global")
local timerStack = require("utils/timerStack")

-- ═══════════════════════════════════════════════════════════════════════════
--  화력 지원 (fire_support): 저격 / 드론 / 헬기 / 공수 중 1종 랜덤 발동. [스텁]
--
--  미사일 폭격(bombard)과 달리 "환경 무피해" 지원 계열. 지형/차량/시체 아이템을
--  건드리지 않고 반경 내 좀비만 처치한다. 시청자가 부담 없이 도움을 줄 수 있는
--  후원을 목표로 함.
--
--    저격 (sniper)     : 즉시 1회. 반경 넓음 / 킬 수 적음.
--    드론 (drone)      : 지속(짧음). 반경 좁음 / 짧은 간격.
--    헬기 (helicopter) : 지속(김). 반경 넓음 / 로터음 루프 + 기관총.
--    공수 (airborne)   : 히트맨 기반. 강하한 병력이 좀비를 사격.
--
--  ── 구현 시 지켜야 할 제약 (합의된 설계) ──────────────────────────────────
--  1. 좀비 킬은 반드시 해당 좀비의 소유 클라이언트에서 실행할 것.
--     서버에서 setHealth(0) 하면 소유 클라 sync 패킷에 덮여서 되살아난다.
--     -> 서버가 대상 산출 -> sendServerCommand 로 소유 클라에 킬 지시.
--  2. clearAttachedItems() 절대 호출 금지. 시체 아이템 증발 버그 원인 후보.
--  3. 사운드는 어그로와 분리한다. addSound() 를 부르지 않으면 좀비는 반응하지
--     않으므로, 헬기 로터음/총성을 크게 틀어도 어그로는 0으로 유지 가능.
--     (바닐라 헬기 이벤트가 좀비를 끌어모으는 건 이벤트 스크립트가 별도로
--      addSound 를 호출하기 때문 -- PZ-Library 확인 필요)
--  4. 루프 사운드는 재생 핸들을 보관했다가 종료 시 명시적으로 정지할 것.
--     중첩 후원 정책은 "지속시간 연장"(소리 1개 유지)으로 간다.
--  5. 대상 선정은 플레이어 기준 최근접 순. 랜덤으로 뽑으면 붙어있는 좀비가
--     안 죽어서 지원 체감이 사라진다. 반경 내 좀비 수 상한 필요.
--  6. 지속형은 duration 종료 시 반드시 타이머/이벤트를 해제할 것.
-- ═══════════════════════════════════════════════════════════════════════════

local KINDS = { "sniper", "drone", "helicopter", "airborne" }

-- 샌드박스 타입 필터: PongDu.FireSupport_<종류> 체크된 것만 룰렛 풀에 포함.
-- 4종 전부 해제면 저격으로 폴백.
local KIND_OPTION = {
    sniper     = "FireSupport_Sniper",
    drone      = "FireSupport_Drone",
    helicopter = "FireSupport_Helicopter",
    airborne   = "FireSupport_Airborne",
}

-- 어떤 종류가 뽑혔는지 후원받은 플레이어가 직접 외친다 (player:Say).
-- skillpotion.lua/invsave.lua와 동일한 방식 -- 채팅 로그 + 말풍선.
local KIND_SAY = {
    sniper     = "IGUI_donation_fire_support_sniper",
    drone      = "IGUI_donation_fire_support_drone",
    helicopter = "IGUI_donation_fire_support_helicopter",
    airborne   = "IGUI_donation_fire_support_airborne",
}

local function pickKind()
    local sv = SandboxVars.PongDu
    local pool = {}
    for _, k in ipairs(KINDS) do
        if sv[KIND_OPTION[k]] then
            pool[#pool + 1] = k
        end
    end
    if #pool == 0 then return "sniper" end
    return pool[ZombRand(#pool) + 1]
end

-- ── 샌드박스 옵션 (사용 시점에 읽음 -- 파일 로드 시점엔 SandboxVars 비어있음) ──
-- zombierain.rainCfg() / randomteleport.distCfg() 와 같은 형태.
--
-- 값의 출처는 sandbox-options.txt 하나뿐이다. 등록된 옵션은
-- SandboxOptions.toLua() -> SandboxOption.toTable() 이 SandboxVars 에 무조건
-- rawset 하므로 (SandboxOptions.java:1355) 게임 로드 후엔 nil 이 될 수 없다.
-- 옵션 추가 전에 만든 구 세이브도 initSandboxVars() 가 fromTable -> toTable
-- 순으로 돌아 sandbox-options.txt 의 default 가 채워진다.
-- 따라서 lua 쪽 폴백은 전부 도달 불가능한 데드코드이고, 오히려 샌박 값과
-- 조용히 어긋날 위험만 만든다. 값 범위(min/max/default)는 sandbox-options.txt
-- 한 곳에서만 정의한다.

-- 저격 파라미터: Sniper_Radius / Sniper_Count / Sniper_Interval(ms).
local function sniperCfg()
    local sv = SandboxVars.PongDu
    return sv.Sniper_Radius,
           sv.Sniper_Count,
           sv.Sniper_Interval,
           sv.Sniper_PierceChance,
           sv.Sniper_KnockdownChance
end

-- 헬기 파라미터: Heli_Duration(s) / Heli_Radius / Heli_Interval(ms) / Heli_KillChance(%).
local function heliCfg()
    local sv = SandboxVars.PongDu
    return sv.Heli_Duration,
           sv.Heli_Radius,
           sv.Heli_Interval,
           sv.Heli_KillChance
end

-- 드론 파라미터: Drone_Duration(s) / Drone_OrbitRadius / Drone_DetectRadius /
-- Drone_Interval(ms) / Drone_KillChance(%) / Drone_KnockdownChance(%) /
-- Drone_OrbitPeriod(s).
local function droneCfg()
    local sv = SandboxVars.PongDu
    return sv.Drone_Duration,
           sv.Drone_OrbitRadius,
           sv.Drone_DetectRadius,
           sv.Drone_Interval,
           sv.Drone_KillChance,
           sv.Drone_KnockdownChance,
           sv.Drone_OrbitPeriod
end

-- ── 종류별 실행부 (전부 미구현) ────────────────────────────────────────────
-- 각 함수는 player, sender 를 받아 해당 연출/처치를 수행한다.
-- 공통 파라미터는 샌드박스에서 읽되, SandboxVars 는 게임 로드 후에만 존재하므로
-- 반드시 발동 시점에 읽을 것.

local runners = {}

-- 저격: 화면 밖 랜덤 지점에 저격수가 자리잡고, 특수좀비 우선으로 최대 N마리
-- 순차 사살. 대상 선정은 서버가 한다 -- 각 클라가 독립적으로 뽑으면 소유 좀비
-- 기준이라 총합이 N을 넘어버린다(폭격처럼 반경 전체 킬이 아니라 "N마리"가
-- 스펙이므로 서버 권위 선정이 필수).
runners.sniper = function(player, sender)
    local radius, count, interval, pcChance, kdChance = sniperCfg()
    -- 관통: 저격수와 주 표적 사이 직선상의 좀비를 전부 훑는다.
    -- 사살 여부/넉다운 여부는 서버가 굴려서 내려보낸다.
    local pierce = SandboxVars.PongDu.Sniper_Pierce
    print(string.format("[PongDu] fire_support/sniper request r=%d n=%d interval=%d pierce=%s chance=%d knockdown=%d",
        radius, count, interval, tostring(pierce), pcChance, kdChance))
    sendClientCommand("PongDuFireSupport", "Sniper", {
        r = radius, n = count, iv = interval, sender = sender or "",
        pc = pierce, pcc = pcChance, kd = kdChance,
    })
end

-- 드론: 지속(짧음). interval 마다 소수 처치. 모터음 루프.
-- 드론: 저격과 같은 방식으로 뽑은 화면 밖 지점에서 접근해, 플레이어를 중심으로
-- 시계방향 공전하며 사격한다. 공전 위치/타겟팅/킬 굴림은 전부 서버 job이
-- 맡는다(저격·헬기와 동일한 이유 -- 킬 판정의 단일 권위가 필요).
runners.drone = function(player, sender)
    local dur, orbitR, detR, iv, kc, kd, period = droneCfg()
    print(string.format(
        "[PongDu] fire_support/drone request dur=%ds orbitR=%d detR=%d iv=%d kc=%d%% kd=%d%% period=%ds",
        dur, orbitR, detR, iv, kc, kd, period))
    sendClientCommand("PongDuFireSupport", "Drone", {
        dur = dur, orad = orbitR, dr = detR, iv = iv,
        kc = kc, kd = kd, pd = period, sender = sender or "",
    })
end

-- 헬기: 지속(김). 랜덤 지점 A -> B 로 이동하며 플레이어 반경 내 좀비를
-- 무차별 소사. 저격과 달리 발당 킬 확률(기본 30%)이 낮은 대신 연사가 빠르다.
-- A/B 산출, 대상 선정, 킬 룰렛, 발사 타이밍 전부 서버 job이 맡는다
-- (이유는 저격과 동일 -- 킬 총량/타이밍의 단일 권위가 필요).
runners.helicopter = function(player, sender)
    local dur, radius, interval, kc = heliCfg()
    print(string.format("[PongDu] fire_support/heli request dur=%ds r=%d iv=%d kc=%d%%",
        dur, radius, interval, kc))
    sendClientCommand("PongDuFireSupport", "Heli", {
        dur = dur, r = radius, iv = interval, kc = kc, sender = sender or "",
    })
end

-- 공수: 히트맨 개체를 우호 진영으로 강하시켜 좀비를 사격.
runners.airborne = function(player, sender)
    print("[PongDu] fire_support/airborne: not implemented yet")
    -- TODO: 히트맨 타겟팅을 플레이어 -> 최근접 좀비로 교체,
    --       좀비의 히트맨 인식 여부 / MP 소유권 / duration 후 소멸 처리 확인
end

-- a(player, sender): 화력 지원 발동. 4종 중 1종을 뽑아 실행한다. [public name: .a]
function _a.a(player, sender)
    if not player then
        print("[PongDu] fire_support: aborted, player is nil")
        return
    end

    local kind = pickKind()
    print(string.format("[PongDu] fire_support START kind=%s sender=%s x=%d y=%d",
        tostring(kind), tostring(sender or ""),
        math.floor(player:getX()), math.floor(player:getY())))

    local sayKey = KIND_SAY[kind]
    if sayKey then
        pcall(function() player:Say(getText(sayKey)) end)
    end

    local run = runners[kind]
    if not run then
        print("[PongDu] fire_support: no runner for kind=" .. tostring(kind))
        return
    end

    run(player, sender or "")
    print("[PongDu] fire_support END kind=" .. tostring(kind))
end

-- ═══════════════════════════════════════════════════════════════════════════
--  예광탄 렌더러
--
--  HitmanProjectile.lua와 같은 원리(OnPreUIDraw + renderer:renderline)지만
--  두 가지가 다르다:
--   ① 히트맨은 스크린 좌표를 저장해두고 그 값을 직접 이동시킨다 -> 카메라가
--      움직이면 탄이 화면에 붙어서 같이 끌려다닌다. 여기선 월드(iso) 좌표만
--      저장하고 매 프레임 ToScreen으로 다시 변환한다.
--   ② 히트맨은 방향각으로 뻗기만 하고 목표에 수렴하지 않는다(순수 연출).
--      저격은 실제 명중이 있으므로 원점->목표를 보간해 정확히 꽂히게 한다.
--
--  가시성: 히트맨은 alpha 0.14 단선이라 밝은 지형에선 거의 안 보인다.
--  renderline에는 두께 인자가 없으므로 평행선 3개(심지 1 + 외곽 2)로
--  굵기를 만들고 alpha를 크게 올렸다.
-- ═══════════════════════════════════════════════════════════════════════════

local TRACER_TEX  = getTexture("media/textures/mask_white.png")
local TRACER_STEP = 0.16      -- 프레임당 진행률 (1/0.16 = 약 7프레임에 도달)
local TRACER_SEG  = 0.20      -- 그려지는 선분 길이 (진행률 단위)
local ORIGIN_ALT  = 95        -- 원점 고도(px). PZ엔 3D가 없어 스크린 Y로 위조한다
local TARGET_ALT  = 70        -- 목표 고도(px). 좀비 상반신 높이
local TRACER_ALPHA      = 0.90   -- 기본(저격/헬기): 진한 흰색
local TRACER_ALPHA_FAINT = 0.14  -- 히트맨 예광탄과 동일한 옅은 알파(드론용)

local _tracers = {}

-- oalt : 원점 고도(px). 생략 시 저격수 고도(ORIGIN_ALT). 헬기는 더 높은 값을 준다.
-- alpha: 선 알파. 생략 시 TRACER_ALPHA(0.90, 진한 흰색). 드론만 옅게 쏜다.
local function addTracer(ox, oy, oz, tx, ty, tz, oalt, alpha)
    _tracers[#_tracers + 1] = {
        ox = ox, oy = oy, oz = oz,
        tx = tx, ty = ty, tz = tz,
        t = 0, hit = 0, oalt = oalt, alpha = alpha,
    }
end

local function drawTracers()
    if #_tracers == 0 then return end
    if isServer() then return end
    if not isIngameState() then return end

    local zoom = getCore():getZoom(0)
    if not zoom or zoom == 0 then return end
    local renderer = getRenderer()

    for i = #_tracers, 1, -1 do
        local tr = _tracers[i]
        local sx, sy = ISCoordConversion.ToScreen(tr.ox, tr.oy, tr.oz)
        local ex, ey = ISCoordConversion.ToScreen(tr.tx, tr.ty, tr.tz)
        sx = sx / zoom
        sy = sy / zoom - (tr.oalt or ORIGIN_ALT) / zoom
        ex = ex / zoom
        ey = ey / zoom - TARGET_ALT / zoom

        if tr.t < 1 then
            local a1 = tr.t
            local a2 = math.min(tr.t + TRACER_SEG, 1)
            local x1 = math.floor(sx + (ex - sx) * a1)
            local y1 = math.floor(sy + (ey - sy) * a1)
            local x2 = math.floor(sx + (ex - sx) * a2)
            local y2 = math.floor(sy + (ey - sy) * a2)
            -- 두께는 히트맨 예광탄과 동일하게 단선 1줄. 알파는 발사원별로
            -- 다르다(저격/헬기 0.90 진한 흰색, 드론 0.14). 색은 공통.
            renderer:renderline(TRACER_TEX, x1, y1, x2, y2,
                1, 1, 0.90, tr.alpha or TRACER_ALPHA)
            -- 총구 화염: 처음 두 프레임만 원점에 짧고 밝게.
            -- 예광탄 알파와 같은 비율로 낮춰 둘의 밝기 관계를 유지한다
            -- (기본 0.95, 드론은 0.95 * 0.14/0.90 = 약 0.148).
            if tr.t < TRACER_STEP * 2 then
                local fx = math.floor(sx + (ex - sx) * 0.03)
                local fy = math.floor(sy + (ey - sy) * 0.03)
                local fa = 0.95 * ((tr.alpha or TRACER_ALPHA) / TRACER_ALPHA)
                renderer:renderline(TRACER_TEX, math.floor(sx), math.floor(sy), fx, fy,
                    1, 0.92, 0.55, fa)
            end
            tr.t = tr.t + TRACER_STEP
        else
            -- 탄착 섬광: 목표 지점에 십자로 몇 프레임
            tr.hit = tr.hit + 1
            local alpha = 0.85 - tr.hit * 0.17
            if alpha > 0 then
                local sz = math.floor(7 / zoom)
                local cxp, cyp = math.floor(ex), math.floor(ey)
                renderer:renderline(TRACER_TEX, cxp - sz, cyp, cxp + sz, cyp, 1, 0.80, 0.40, alpha)
                renderer:renderline(TRACER_TEX, cxp, cyp - sz, cxp, cyp + sz, 1, 0.80, 0.40, alpha)
            end
            if tr.hit > 5 then table.remove(_tracers, i) end
        end
    end
end

Events.OnPreUIDraw.Add(drawTracers)

-- ═══════════════════════════════════════════════════════════════════════════
--  사격 처리 (저격 공용)
--  타이밍/대상 재선정은 이제 서버 job(server.lua processSniperJobs)이 맡는다.
--  서버가 iv 간격으로 한 발씩 SniperFire를 보내므로, 클라는 큐잉/지연 없이
--  수신 즉시 그 한 발을 처리하면 된다.
-- ═══════════════════════════════════════════════════════════════════════════

local function findZombieById(id)
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return nil end
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and z:getOnlineID() == id then return z end
    end
    return nil
end

-- 즉사 처리. B41 MP에서 좀비는 클라 권한이므로 소유 클라에서만 호출해야 한다
-- (서버 setHealth는 소유 클라 동기화 패킷에 덮인다).
--
-- 구현: 히트맨 사격(HitmanZombieActions/ZAShoot.lua hit())과 동일 경로.
-- 기존엔 setHealth(0) + becomeCorpse()로 즉시 시체화했는데, becomeCorpse가
-- 사망 애니메이션을 통째로 건너뛰어 "그냥 픽 사라지는" 밋밋한 연출이 됐다.
-- 대신 실제 총기로 Hit()을 먹인다:
--   IsoGameCharacter.hitConsequences (IsoGameCharacter.java:5523)
--     -> 조준총기면 Health -= damage * 0.7  -> isDead()면 Kill(wielder)
--   즉 데미지만 충분히 크면 확정 1발 즉사 + 바닐라 총격 사망 모션이 그대로 나온다.
--
-- 어그로가 붙지 않는 이유 (설계 제약 3 유지):
--   Hit() 내부에서 wielder:addWorldSoundUnlessInvisible(5,1,false)를 부르지만,
--   IsoCell.getFakeZombieForHit()은 new IsoZombie(cell)만 하고 좌표를 잡지 않아
--   항상 0,0에 있다. 즉 소리가 맵 구석에서 나므로 플레이어 주변 영향 0.
--   hitConsequences의 setTarget(wielder)도 fakeZombie를 가리키므로 플레이어를
--   물지 않는다.
--
-- clearAttachedItems()는 여전히 부르지 않는다 -- 지원 계열은 시체 아이템 손실이
-- 없어야 하고, 이 호출이 시체 아이템 증발 버그의 원인 후보다.
--
-- 알려진 한계(연출): hitDir이 wielder(0,0) 기준이라 넘어지는 방향이 항상 같다.
-- 저격수 방향으로 넘기려면 엔진 공용 fakeZombie의 좌표를 건드려야 해서 보류.
local SNIPER_DMG = 500       -- 좀비 체력 대비 압도적. 무기 숙련 보정을 먹어도 확정 킬.
local _sniperGun = nil       -- HandWeapon 캐시. 매 발 생성하면 GC 낭비.

-- Base.HuntingRifle = MSR788 Rifle (items_weapons.txt:5209).
-- 이미 쓰고 있는 총성 "MSR788Shoot"과 같은 총이고 IsAimedFirearm=TRUE라
-- hitConsequences의 *0.7 경로를 탄다.
local function sniperWeapon()
    if _sniperGun then return _sniperGun end
    local ok, item = pcall(function()
        return InventoryItemFactory.CreateItem("Base.HuntingRifle")
    end)
    if ok and item then
        _sniperGun = item
    else
        print("[PongDu] fire_support/sniper: weapon item creation failed, using fallback kill")
    end
    return _sniperGun
end

local function killZombieNow(z)
    local cell = getCell()
    if not cell then return end
    local fake = cell:getFakeZombieForHit()
    local gun  = sniperWeapon()
    if not gun then
        -- 폴백: 총기 생성 실패 시 구 경로(모션 없음)로라도 확실히 죽인다.
        z:setHealth(0)
        z:changeState(ZombieOnGroundState.instance())
        z:setAttackedBy(fake)
        z:becomeCorpse()
        return
    end
    z:setBumpDone(true)
    z:setHitReaction("ShotBelly")
    z:Hit(gun, fake, SNIPER_DMG, false, 1, false)
    z:setAttackedBy(fake)
end

-- 관통에 맞았지만 살아남은 좀비: 죽이지 않고 피격 반응만 준다.
--
--   knockDown(hitFromBehind) -- IsoZombie.java:3805. 데미지 없이 넘어뜨리는
--     바닐라 API로, 내부에서 setKnockedDown/setStaggerBack/setHitForce와
--     reportEvent("wasHit")까지 전부 처리한다.
--   setHitReaction(name) + reportEvent("wasHit") -- 넘어지지 않는 "움찔".
--     히트맨 ZAShoot의 hit()과 같은 방식이되 Hit()을 부르지 않는다.
--     Hit()을 쓰면 체력이 깎여서 서버의 관통 확률 판정과 무관하게 죽어버린다.
--
-- 리액션 이름은 바닐라 AnimSets/zombie/hitreaction/Shot/ 의 노드명이다.
local GRAZE_REACTIONS = {
    "ShotBelly", "ShotBellyStep",
    "ShotChestStepL", "ShotChestStepR",
    "ShotShoulderStepL", "ShotShoulderStepR",
    "ShotShoulderStaggerL", "ShotShoulderStaggerR",
}

-- kdForced: nil 이면 kdChance 로 로컬 굴림(저격 경로 -- 기존 동작 유지),
-- true/false 면 서버가 이미 굴린 결과를 그대로 적용한다(드론 경로). 서버가
-- 굴려야 하는 이유는 server.lua 의 processDroneJobs 주석 참고 -- 클라마다
-- 굴리면 넘어진 놈이 클라별로 갈리고, 서버가 억제창을 걸 수 없다.
local function grazeZombie(z, id, kdChance, kdForced)
    if not z or z:isDead() then return end
    -- 피격 연출은 전 클라에서. 어그로와 무관한 로컬 효과다.
    pcall(function() z:playSound("BulletHitBody") end)
    pcall(function() z:splatBlood(2, 0.3) end)
    -- 상태 변경(넉다운/리액션)은 소유 클라에서만. 원격 좀비에 걸면
    -- 소유 클라 sync 패킷에 덮여서 무효다.
    if z:isRemoteZombie() then return end
    local down
    if kdForced ~= nil then
        down = kdForced
    else
        down = ZombRand(100) < (kdChance or 50)
    end
    local ok, err = pcall(function()
        if down then
            z:knockDown(false)
        else
            z:setBumpDone(true)
            z:setHitReaction(GRAZE_REACTIONS[ZombRand(#GRAZE_REACTIONS) + 1])
            z:reportEvent("wasHit")
        end
    end)
    if not ok then
        print("[PongDu] fire_support/sniper GRAZE FAILED zid="
            .. tostring(id) .. " err=" .. tostring(err))
    end
end


-- ═══════════════════════════════════════════════════════════════════════════
--  헬기 로터음 (루프 사운드)
--
--  getSoundManager():PlaySound(name, loop, gain)은 loop/gain 인자를 통째로
--  버린다(SoundManager.java:551 -- 내부에서 1인자 playSound만 호출). 루프는
--  GameSound 스크립트의 loop = true 플래그로만 성립한다
--  (FMODSoundEmitter$FileSound.tick: clip.gameSound.isLooped()면
--   FMOD_LOOP_NORMAL 세팅). 그래서:
--    ① t3_rewards_sounds.txt 에 pongdu_heli 를 loop = true 로 등록하고
--    ② 로컬 플레이어 emitter 의 playSound 핸들을 보관, stopSound 로 정지한다
--       (바닐라 TimedAction 들이 쓰는 패턴 -- ISBuildAction.lua 등).
--  emitter:playSound 는 로컬 재생만 하고 네트워크 전송이 없으므로, 서버
--  브로드캐스트(HeliStart)로 각 클라가 각자 1개씩 틀면 중복 없이 전원이 듣는다.
--
--  안전장치: HeliStop 유실(호스트 이탈 등)에 대비해 HeliStart 가 들려준
--  남은 시간(ms)으로 로컬 데드라인을 잡고 OnTick 에서 자체 정지한다.
--  중첩 후원은 서버가 지속시간을 연장하고 HeliStart 를 다시 보내므로,
--  핸들이 살아있으면 데드라인만 갱신한다 (소리 1개 유지 -- 설계 제약 4).
-- ═══════════════════════════════════════════════════════════════════════════

local _heliSound  = nil      -- 로터음 emitter 핸들
local _lmgSound   = nil      -- 기관총 발사음 emitter 핸들 (발당 재생 대신 루프)
local _heliStopAt = nil      -- 자체 정지 데드라인 (ms)

-- 발당 PlaySound("LMG", false, ...)로 짜봤는데, iv(0.1~0.2초)가 LMG.wav 길이보다
-- 짧으면 매번 새 emitter가 잡히면서 기존 재생이 씹히는 문제가 있을 수 있다
-- (getFreeEmitter가 여유 emitter를 못 잡으면 이전 채널을 스틸). 로터음과 동일하게
-- t3_rewards_sounds.txt에 pongdu_heli_lmg를 loop = true로 등록해서, 발당 트리거가
-- 아니라 로터음처럼 발동~종료 구간 내내 한 번만 틀어놓고 정지도 같이 관리한다.
-- (PlaySound의 loop 인자는 무시되므로 스크립트 loop 플래그로만 루프가 성립 -- 위
-- 로터음 주석 참고.)
-- ── 거리 기반 볼륨 램프 ──────────────────────────────────────────────────────
-- 루프 사운드라도 emitter:setVolume(handle, v)로 실시간 볼륨 조절이 가능하다
-- (Sound.volume에 저장되고 FileSound.tick이 매 틱 volume * clip볼륨으로 반영 --
--  VehicleDropCraftSound.lua가 이미 쓰는 검증된 경로).
-- 헬기 위치는 실차량 좌표(heliCurPos -- 미스트리밍 시 경로 보간 폴백)를 매 틱
-- 다시 읽어서 플레이어와의 거리를 재고, 볼륨을 갱신하면 "멀리서 접근 ->
-- 최근접(머리 위 통과) -> 멀어짐" 연출이 된다. 경로가 플레이어 중심 원 위
-- A -> 반대편 B라 최근접은 ~0(머리 위 스침), 최원은 A/B 지점의 D다.
local HELI_VOL_NEAR     = 1.00   -- 최근접 시 로터음 볼륨
local HELI_VOL_FAR      = 0.20   -- 최원거리 시 로터음 볼륨
local HELI_LMG_VOL_NEAR = 0.85   -- 기관총음은 로터음보다 살짝 낮게
local HELI_LMG_VOL_FAR  = 0.15

local function heliUpdateVolume(hx, hy)
    if not _heliSound and not _lmgSound then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end

    -- 경로 기하 기준 거리 범위: 머리 위 통과 경로라 최근접 ~0, 최원 = D(r+25)
    -- svInt 라는 헬퍼가 이 모드 어디에도 정의돼 있지 않아 nil 호출로
    -- 즉사했다(heliUpdateVolume). 다른 곳과 동일하게 SandboxVars 직접 참조.
    local dmin, dmax = 0, SandboxVars.PongDu.Heli_Radius + 25
    local dx, dy = hx - pl:getX(), hy - pl:getY()
    local d = math.sqrt(dx * dx + dy * dy)

    -- d를 [dmin,dmax] -> [1,0]으로 정규화 (가까울수록 1)
    local k = 1 - (d - dmin) / (dmax - dmin)
    if k < 0 then k = 0 elseif k > 1 then k = 1 end

    local emitter = pl:getEmitter()
    if _heliSound then
        pcall(function()
            emitter:setVolume(_heliSound, HELI_VOL_FAR + (HELI_VOL_NEAR - HELI_VOL_FAR) * k)
        end)
    end
    if _lmgSound then
        pcall(function()
            emitter:setVolume(_lmgSound, HELI_LMG_VOL_FAR + (HELI_LMG_VOL_NEAR - HELI_LMG_VOL_FAR) * k)
        end)
    end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  헬기 실체 (Base.PongDuHeli 차량)
--
--  그림자 스프라이트(IsoDeadBody.renderShadow) 연출을 실제 차량으로 교체했다.
--  BetterHelicopterForMP의 UH-1 모델을 리네임한 Base.PongDuHeli를 서버가
--  addVehicleDebug로 스폰하고, 대상 플레이어 클라(파일럿)가 물리 권한을 받아
--  BH 모드와 동일한 리플렉션 텔레포트(setWorldTransform)로 경로를 비행시킨다.
--
--  MP 동기화 구조 (PZ-Library Java 검증 완료):
--   ① 서버: addVehicleDebug 스폰 -> authorizationChanged(player)로
--      대상 클라에 Local 권한 부여. serverUpdate가 연결별 상태
--      비교로 감지해 VehicleAuthorizationPacket을 자동 브로드캐스트한다.
--   ② 파일럿 클라: hasAuthorization=true -> 매 틱 이 파일이 경로 보간 좌표로
--      텔레포트 -> 엔진이 150ms 간격 sendPhysic(패킷9) 스트림 -> 서버 릴레이.
--   ③ 타 클라: VehicleInterpolation 버퍼로 보간 수신 (MP에서 달리는 모든
--      차량이 쓰는 검증된 경로 -- 별도 코드 불필요).
--   ④ 1초 무변동 자동 회수(WorldSimulation.java:140)는 LocalCollide 전용이라
--      Local 권한은 애초에 대상이 아니고, 비행 중엔 어차피 매 틱 변한다.
--   ⑤ 종료: 서버 permanentlyRemove() -> 제거 패킷(8) 브로드캐스트.
--
--  경로/타이밍은 기존 그대로 HeliStart의 (ax,ay)->(bx,by) + elapsed/total을
--  로컬 시계로 보간한다. 급선회(중첩 후원) 시 서버가 새 경로로 HeliStart를
--  다시 보내면 _heliPath 교체 + yaw 재설정으로 즉시 새 직선을 탄다.
--
--  블레이드 회전: BH와 동일하게 모델 8종(대)/4종(소)을 매 틱 순환 스왑.
--  엔진 시동은 걸지 않으므로(무인) 차량 엔진음은 존재하지 않고, 로터음은
--  기존 pongdu_heli 루프(아래 사운드 섹션)를 그대로 쓴다.
-- ═══════════════════════════════════════════════════════════════════════════

local HELI_FLY_ALT = 8.0   -- 물리 y 고도. iso 층수 환산 = y/2.46 (BaseVehicle.java:1456),
                           -- 8.0 ≈ 3.25층. 초기값 3.0(BH 조종 상한)은 1.2층이라 너무 낮았다.
local HELI_YAW_OFF = 0     -- fbx 전방축 보정(도). 기수 방향이 틀어져 보이면 여기로 교정.

local _heliPath   = nil   -- { ax, ay, bx, by, oz, t0(로컬 시작 시각), total, yawSet }
local _heliVid    = nil   -- 서버가 준 VehicleID
local _amPilot    = false -- 내가 물리 권한 클라인가 (HeliStart의 pilot == 내 onlineID)
local _wFieldNum  = nil   -- tempTransform 자바 필드 인덱스 캐시 (클래스 고정이라 재사용)
local _heliWarned = false -- "차량 미스트리밍" 로그 1회 제한
local _bladeInit  = false -- 첫 틱에 블레이드 전체 숨김 수행 여부
local _bladeStep  = 0

local function heliPathPos()
    if not _heliPath then return nil end
    local t = (getTimestampMs() - _heliPath.t0) / _heliPath.total
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local x = _heliPath.ax + (_heliPath.bx - _heliPath.ax) * t
    local y = _heliPath.ay + (_heliPath.by - _heliPath.ay) * t
    return x, y, _heliPath.oz
end

-- VehicleID 는 서버에서 재활용된다(VehicleIDMap.remove -> freeID 스택 ->
-- allocateID 가 LIFO 로 pop). 텔포 등으로 헬기 청크가 언로드되면 그 ID 가
-- 곧바로 다른 바닐라 차량에 넘어가고, _heliVid 로 그 차가 잡히면 파일럿
-- 틱이 남의 차를 비행경로로 끌고 간다. 스크립트명으로 반드시 걸러낸다.
local function findHeliVehicle()
    if not _heliVid then return nil end
    local ok, v = pcall(function() return getVehicleById(_heliVid) end)
    if not ok or not v then return nil end
    local okS, sn = pcall(function() return v:getScriptName() end)
    if okS and sn == "Base.PongDuHeli" then return v end
    return nil
end

-- 현재 헬기 좌표: 실차량 우선(화면과 정확히 일치), 스트리밍 전엔 경로 보간 폴백.
local function heliCurPos()
    local v = findHeliVehicle()
    if v then return v:getX(), v:getY(), v:getZ() end
    return heliPathPos()
end

-- BH 모드 moveVehicle과 동일한 리플렉션 경로. BaseVehicle의 private
-- tempTransform 필드를 꺼내 getWorldTransform/setWorldTransform으로 물리
-- 원점을 직접 옮긴다 (클라 setWorldTransform은 내부에서 Bullet.teleportVehicle
-- 호출 -- BaseVehicle.java:3453).
local function heliFieldNum(obj, name)
    for i = 0, getNumClassFields(obj) - 1 do
        local f = getClassField(obj, i)
        if luautils.stringEnds(tostring(f), "." .. name) then return i end
    end
    return nil
end

local function heliMoveTo(v, wx, wy)
    if not _wFieldNum then _wFieldNum = heliFieldNum(v, "tempTransform") end
    if not _wFieldNum then error("tempTransform field not found") end
    local tmp    = getClassFieldVal(v, getClassField(v, _wFieldNum))
    local tr     = v:getWorldTransform(tmp)
    local origin = getClassFieldVal(tr, getClassField(tr, 1))
    -- 물리축 매핑: origin.x = iso x(월드심 오프셋 좌표계), origin.y = 고도,
    -- origin.z = iso y. 오프셋 값을 몰라도 되도록 iso 좌표 "델타"를 더한다
    -- (BH moveVehicle 방식). 고도만 절대값으로 박아 중력 드리프트를 차단.
    origin:set(origin:x() + (wx - v:getX()), HELI_FLY_ALT, origin:z() + (wy - v:getY()))
    v:setWorldTransform(tr)
end

-- 기수 방향. addVehicleDebug의 savedRot 규약(dir.toAngle() + pi, Y축 회전)을
-- 역산하면 진행방향 (dx,dy)의 yaw = atan2(dx, dy) (IsoDirections.java:307
-- N=0/W=pi/2/S=pi/E=3pi/2 매핑으로 4방위 전수 검산함). setAngles는 도 단위.
local function heliSetYaw(v)
    local dx, dy = _heliPath.bx - _heliPath.ax, _heliPath.by - _heliPath.ay
    if dx == 0 and dy == 0 then return end
    local yaw = math.deg(math.atan2(dx, dy)) + HELI_YAW_OFF
    _heliPath.yaw = yaw
    local ok, err = pcall(function() v:setAngles(0, yaw, 0) end)
    if ok then
        print(string.format("[PongDu] fire_support/heli: yaw set %.1f deg", yaw))
    else
        print("[PongDu] fire_support/heli: yaw set FAILED err=" .. tostring(err))
    end
end

-- 파일럿 틱: 경로 보간 좌표로 텔레포트. 권한 클라에서만 호출된다.
local function heliPilotTick()
    local v = findHeliVehicle()
    if not v then
        if not _heliWarned then
            _heliWarned = true
            print("[PongDu] fire_support/heli: pilot tick but vehicle not streamed yet vid="
                .. tostring(_heliVid))
        end
        return
    end
    _heliWarned = false
    local wx, wy = heliPathPos()
    if not wx then return end
    if not _heliPath.yawSet then
        _heliPath.yawSet = true
        heliSetYaw(v)
    end
    local ok, err = pcall(function() heliMoveTo(v, wx, wy) end)
    if not ok and not _heliPath.moveErr then
        _heliPath.moveErr = true
        print("[PongDu] fire_support/heli: move FAILED err=" .. tostring(err))
    end
end

-- 블레이드 회전: 전 클라 공통, 매 틱 모델 순환 스왑 (BH rotateBlades 로직).
-- 엔진 시동 여부와 무관하게 무조건 돌린다. 첫 틱엔 Init이 켜둔 랜덤 블레이드가
-- 남지 않게 전체를 한 번 숨긴다.
--
-- 여기서 함께 그림자 좌표 갱신도 강제한다: BaseVehicle.polyDirty가 서야
-- initShadowPoly()가 shadowCoord를 재계산하는데, 이 플래그는 setAngles()
-- (실제 각도가 바뀔 때)에만 자동으로 서고 위치 갱신(setWorldTransform,
-- 인터폴레이션의 setX/setY)은 건드리지 않는다. 처음엔 "public 필드니까
-- v.polyDirty = true로 직접 대입하면 되겠지" 하고 시도했는데, Kahlua는 이
-- 문법을 테이블에만 허용해서 "attempted index of non-table"이라는 순수
-- 자바 RuntimeException을 던진다 -- Lua pcall이 못 잡는 종류라(Kahlua pcall은
-- LuaRuntimeException만 잡음) 사격할 때마다 최상위까지 뚫고 올라가 콘솔에
-- 크래시 로그가 찍혔다. 필드 직접 대입은 이 엔진에서 아예 불가능하다.
--
-- 대신 이미 검증된 유일한 트리거인 setAngles()를 매 틱 호출한다. 진짜로
-- 각도가 "변해야" 플래그가 서므로(정수 절삭 비교), 기수 방향(yaw)을 매 틱
-- ±0.6도씩 흔들어 절삭값이 확실히 달라지게 만든다. 빠르게 나는 헬기 + 회전
-- 중인 로터 애니메이션에 묻혀 육안으로는 거의 안 보이는 수준의 흔들림이다.
local _yawWobbleUp = false
local function heliShadowRefreshTick(v)
    if not _heliPath or not _heliPath.yaw then return end
    _yawWobbleUp = not _yawWobbleUp
    local yaw = _heliPath.yaw + (_yawWobbleUp and 0.6 or -0.6)
    pcall(function() v:setAngles(0, yaw, 0) end)
end

-- 블레이드 회전: 전 클라 공통, 매 틱 모델 순환 스왑 (BH rotateBlades 로직).
-- 엔진 시동 여부와 무관하게 무조건 돌린다. 첫 틱엔 Init이 켜둔 랜덤 블레이드가
-- 남지 않게 전체를 한 번 숨긴다.
local function heliBladeTick()
    local v = findHeliVehicle()
    if not v then return end
    heliShadowRefreshTick(v)
    local part = v:getPartById("heliblade")
    local ps   = v:getPartById("helibladeSmall")
    if not _bladeInit then
        _bladeInit = true
        if part then
            for i = 1, 8 do part:setModelVisible("blade" .. i, false) end
        end
        if ps then
            for i = 1, 4 do ps:setModelVisible("blade" .. i .. "Small", false) end
        end
    end
    _bladeStep = _bladeStep + 1
    if _bladeStep > 8 then _bladeStep = 1 end
    if part then
        local prev = _bladeStep - 1
        if prev < 1 then prev = 8 end
        part:setModelVisible("blade" .. prev, false)
        part:setModelVisible("blade" .. _bladeStep, true)
    end
    if ps then
        local s  = ((_bladeStep - 1) % 4) + 1
        local sp = s - 1
        if sp < 1 then sp = 4 end
        ps:setModelVisible("blade" .. sp .. "Small", false)
        ps:setModelVisible("blade" .. s .. "Small", true)
    end
    -- BH rotateBlades와 동일하게 스왑 직후 update()로 모델 상태 반영을 강제.
    pcall(function() v:update() end)
end

-- 남은시간 패널 상태. hide는 heliSoundStop이 참조하므로 여기(앞)에 정의한다
-- (뒤에 두면 Kahlua에서 전역(nil) 조회로 잡혀 "tried to call nil" 크래시).
local _heliEndAt = nil
local function heliTimerHide()
    _heliEndAt = nil   -- 패널 update()가 다음 프레임에 스스로 제거한다
end

local function heliSoundStop(reason)
    local pl = getSpecificPlayer(0)
    if _heliSound then
        if pl then pcall(function() pl:getEmitter():stopSound(_heliSound) end) end
        print("[PongDu] fire_support/heli: rotor sound stopped (" .. tostring(reason) .. ")")
    end
    if _lmgSound then
        if pl then pcall(function() pl:getEmitter():stopSound(_lmgSound) end) end
        print("[PongDu] fire_support/heli: LMG loop stopped (" .. tostring(reason) .. ")")
    end
    _heliSound  = nil
    _lmgSound   = nil
    _heliStopAt = nil
    _heliPath   = nil
    _heliVid    = nil    -- 차량 제거 자체는 서버(permanentlyRemove)가 한다
    _amPilot    = false
    _bladeInit  = false
    _heliWarned = false
    heliTimerHide()
end

local function heliSoundStart(remainMs)
    local pl = getSpecificPlayer(0)
    if not pl then return end
    if not _heliSound then
        local ok, handle = pcall(function()
            return pl:getEmitter():playSound("pongdu_heli")
        end)
        if ok and handle and handle ~= 0 then
            _heliSound = handle
            -- 원거리(A지점) 볼륨으로 시작. 이후 HeliFire마다 거리 기반 갱신.
            pcall(function() pl:getEmitter():setVolume(handle, HELI_VOL_FAR) end)
        else
            print("[PongDu] fire_support/heli: rotor sound start FAILED")
        end
    end
    -- 기관총 루프는 여기서 켜지 않는다: 서버의 engage/clear 상태머신이
    -- HeliEngage(대상 발견) / HeliClear(대상 소진) 명령으로 켜고 끈다.
    -- 유실 대비 자체 데드라인. 서버 HeliStop이 정상 도착하면 그쪽이 먼저 끈다.
    _heliStopAt = getTimestampMs() + (tonumber(remainMs) or 30000) + 2000
end

-- 기관총 루프 시작/정지 (engage/clear 전환 전용)
local function heliLmgStart()
    if _lmgSound then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local ok, handle = pcall(function()
        return pl:getEmitter():playSound("pongdu_heli_lmg")
    end)
    if ok and handle and handle ~= 0 then
        _lmgSound = handle
        pcall(function() pl:getEmitter():setVolume(handle, HELI_LMG_VOL_FAR) end)
        print("[PongDu] fire_support/heli: LMG loop ENGAGE")
    else
        print("[PongDu] fire_support/heli: LMG loop start FAILED")
    end
end

local function heliLmgStop(reason)
    if not _lmgSound then return end
    local pl = getSpecificPlayer(0)
    if pl then pcall(function() pl:getEmitter():stopSound(_lmgSound) end) end
    _lmgSound = nil
    print("[PongDu] fire_support/heli: LMG loop stopped (" .. tostring(reason) .. ")")
end

-- ═══════════════════════════════════════════════════════════════════════════
--  드론 실체 (Base.PongDuDrone 차량)
--
--  헬기와 공유하는 것: 서버 addVehicleDebug 스폰 + authorizationChanged
--  물리 권한 위임 + 파일럿 클라의 리플렉션 텔레포트(setWorldTransform).
--  MP 동기화 구조는 헬기 섹션 주석과 완전히 동일하므로 반복하지 않는다.
--
--  헬기와 다른 것 세 가지:
--   ① 경로 좌표를 서버에서 받지 않는다. 공전 중심이 "대상 플레이어의 현재
--      좌표"라 계속 움직이므로, 각 클라가 매 틱 droneCenter()로 직접 읽는다.
--      서버가 내려주는 건 스폰점/진입각/반경/주기뿐이다.
--   ② 3단계 상태머신(APPROACH 1s -> ORBIT dur -> DEPART 1s). 단계는 t0
--      경과시간에서 유도하므로 서버/클라가 같은 결과를 보장한다.
--   ③ 락온 캐시가 없다. 스펙상 "더 가까운 좀비가 나타나면 즉시 변경"이라
--      서버가 매 발 재선정한다.
--
--  ※ 이 블록은 반드시 Events.OnTick.Add(...) 등록보다 **앞**에 있어야 한다.
--    Kahlua는 렉시컬 스코프라, OnTick 클로저 생성 시점에 아래 local function
--    들이 선언돼 있지 않으면 전역(nil) 조회로 잡혀 "tried to call nil"로
--    즉사한다(파일 상단 _heliEndAt 주석과 같은 함정).
-- ═══════════════════════════════════════════════════════════════════════════

local DRONE_FLY_ALT     = 3.0     -- 물리 y 고도. iso 층 환산 = y/2.46 -> 약 1.2층.
                                  -- 헬기(8.0)보다 낮아야 "근접 호위" 느낌이 산다.
local DRONE_YAW_OFF     = 0       -- fbx 전방축 보정(도)
-- 예광탄 원점 고도(px). 헬기와 같은 환산비(HELI_ALT_PX_PER_UNIT = 86.7)를
-- DRONE_FLY_ALT 에 적용해 실제 기체가 뜬 높이와 일치시킨다. 기존 100 은
-- 임의값이라 탄이 기체보다 한참 아래에서 나갔다. FLY_ALT 를 바꾸면 여기도
-- 자동으로 따라온다.
local DRONE_ALT_PX      = DRONE_FLY_ALT * 86.7
local DRONE_APPROACH_MS = 1000
local DRONE_DEPART_MS   = 1000
local DRONE_DEPART_DIST = 60      -- 이탈 비행 거리(타일). 1초에 이만큼 = 화면 밖
local DRONE_TWO_PI      = 6.2831853

-- 거리 기반 볼륨 램프. 헬기와 같은 원리(emitter:setVolume 실시간 조절)지만
-- 거리 프로파일이 다르다: 접근(58->4타일) 페이드인 -> 공전(4타일 고정) 최대
-- -> 이탈(4->64타일) 페이드아웃. 공전 중엔 거의 최대 볼륨으로 붙어 있는다.
local DRONE_VOL_NEAR    = 0.3167   -- 기존 0.95 의 1/3
local DRONE_VOL_FAR     = 0.0333   -- 기존 0.10 의 1/3
-- 사격음(SMG). 헬기 LMG 와 동일하게 발당 트리거가 아니라 교전 구간 루프.
local DRONE_SMG_VOL_NEAR = 0.425   -- 기존 0.85 의 1/2
local DRONE_SMG_VOL_FAR  = 0.075   -- 기존 0.15 의 1/2

local _drone          = nil   -- { sx, sy, oz, th0, orbitR, orbitMs, periodMs, t0 }
local _droneVid       = nil
local _droneAmPilot   = false
local _droneTarget    = nil   -- 공전 중심이 될 플레이어 username
local _droneSound     = nil   -- 모터음 emitter 핸들
local _droneSmgSound  = nil   -- 사격음 emitter 핸들 (교전 중에만)
local _droneStopAt    = nil   -- 서버 DroneStop 유실 대비 자체 데드라인
local _droneWarned    = false
local _droneBladeInit = false
local _droneBladeStep = 0
local _droneYawWobble = false

-- 공전 중심 = 대상 플레이어의 현재 좌표. 대상이 스트리밍 밖이면 nil.
local function droneCenter()
    local p = getSpecificPlayer(0)
    if p and p:getUsername() == _droneTarget then return p:getX(), p:getY() end
    local ps = getOnlinePlayers()
    if ps then
        for i = 0, ps:size() - 1 do
            local o = ps:get(i)
            if o and o:getUsername() == _droneTarget then return o:getX(), o:getY() end
        end
    end
    return nil
end

-- 서버 droneComputePos와 **반드시 같은 식**. 한쪽만 고치면 실차량과 탄착점이
-- 어긋난다. theta 증가 = 화면상 시계방향(IsoUtils.XToScreen ∝ x-y,
-- YToScreen ∝ x+y 로 4방위 검산 완료).
local function droneComputePos()
    if not _drone then return nil end
    local cx, cy = droneCenter()
    if not cx then return nil end

    local el = getTimestampMs() - _drone.t0
    if el < 0 then el = 0 end

    if el < DRONE_APPROACH_MS then
        local t  = el / DRONE_APPROACH_MS
        local ex = cx + math.cos(_drone.th0) * _drone.orbitR
        local ey = cy + math.sin(_drone.th0) * _drone.orbitR
        return _drone.sx + (ex - _drone.sx) * t,
               _drone.sy + (ey - _drone.sy) * t, _drone.oz, "APPROACH"
    end

    local oel = el - DRONE_APPROACH_MS
    if oel < _drone.orbitMs then
        local th = _drone.th0 + (oel / _drone.periodMs) * DRONE_TWO_PI
        return cx + math.cos(th) * _drone.orbitR,
               cy + math.sin(th) * _drone.orbitR, _drone.oz, "ORBIT", th
    end

    -- 이탈: 궤도 종료 지점에서 접선 방향(시계방향이므로 -sin, cos)으로 직진.
    local t = (oel - _drone.orbitMs) / DRONE_DEPART_MS
    if t > 1 then t = 1 end
    local thE = _drone.th0 + (_drone.orbitMs / _drone.periodMs) * DRONE_TWO_PI
    local ex  = cx + math.cos(thE) * _drone.orbitR
    local ey  = cy + math.sin(thE) * _drone.orbitR
    return ex - math.sin(thE) * DRONE_DEPART_DIST * t,
           ey + math.cos(thE) * DRONE_DEPART_DIST * t, _drone.oz, "DEPART", thE
end

-- 헬기 findHeliVehicle 과 동일한 ID 재활용 가드. 실측으로 vid=255 가
-- Base.PongDuDrone -> Base.Van 으로 25초 만에 넘어가 그 밴이 공전 궤도에
-- 실려 떠다니는 사고가 확인됐다.
local function findDroneVehicle()
    if not _droneVid then return nil end
    local ok, v = pcall(function() return getVehicleById(_droneVid) end)
    if not ok or not v then return nil end
    local okS, sn = pcall(function() return v:getScriptName() end)
    if okS and sn == "Base.PongDuDrone" then return v end
    return nil
end

-- 현재 드론 좌표: 실차량 우선, 스트리밍 전엔 계산 좌표 폴백(헬기와 동일).
local function droneCurPos()
    local v = findDroneVehicle()
    if v then return v:getX(), v:getY(), v:getZ() end
    return droneComputePos()
end

-- heliMoveTo와 동일한 리플렉션 경로. _wFieldNum은 BaseVehicle 공용 필드
-- 인덱스라 헬기 쪽 캐시를 그대로 재사용한다(클래스가 같다).
local function droneMoveTo(v, wx, wy)
    if not _wFieldNum then _wFieldNum = heliFieldNum(v, "tempTransform") end
    if not _wFieldNum then error("tempTransform field not found") end
    local tmp    = getClassFieldVal(v, getClassField(v, _wFieldNum))
    local tr     = v:getWorldTransform(tmp)
    local origin = getClassFieldVal(tr, getClassField(tr, 1))
    origin:set(origin:x() + (wx - v:getX()), DRONE_FLY_ALT, origin:z() + (wy - v:getY()))
    v:setWorldTransform(tr)
end

-- 기수 방향. yaw = atan2(dx, dy) 규약은 헬기와 동일(heliSetYaw 주석 참조).
--
-- 그림자 폴리곤 갱신이 공전 중엔 공짜로 해결된다: polyDirty는 setAngles로
-- 각도가 실제 변할 때만 서는데, 공전은 접선 방향이 매 틱 바뀌므로 자연히
-- 선다. 헬기가 필요로 했던 ±0.6도 흔들기는 직진 구간(APPROACH/DEPART)
-- 에서만 의미가 있어 그 두 단계에서만 적용한다.
local function droneSetYaw(v, phase, th, wx, wy)
    local yaw
    if phase == "ORBIT" and th then
        -- 접선 방향 (-sin, cos)를 진행방향으로 넣는다.
        yaw = math.deg(math.atan2(-math.sin(th), math.cos(th))) + DRONE_YAW_OFF
    else
        local dx, dy = wx - v:getX(), wy - v:getY()
        if dx == 0 and dy == 0 then return end
        _droneYawWobble = not _droneYawWobble
        yaw = math.deg(math.atan2(dx, dy)) + DRONE_YAW_OFF
            + (_droneYawWobble and 0.6 or -0.6)
    end
    pcall(function() v:setAngles(0, yaw, 0) end)
end

-- 파일럿 틱: 계산 좌표로 텔레포트. 권한 클라에서만 호출된다.
local function dronePilotTick()
    local v = findDroneVehicle()
    if not v then
        if not _droneWarned then
            _droneWarned = true
            print("[PongDu] fire_support/drone: pilot tick but vehicle not streamed yet vid="
                .. tostring(_droneVid))
        end
        return
    end
    _droneWarned = false
    local wx, wy, _, phase, th = droneComputePos()
    if not wx then return end
    local ok, err = pcall(function()
        droneMoveTo(v, wx, wy)
        droneSetYaw(v, phase, th, wx, wy)
    end)
    if not ok and not _drone.moveErr then
        _drone.moveErr = true
        print("[PongDu] fire_support/drone: move FAILED err=" .. tostring(err))
    end
end

-- 블레이드 순환: 전 클라 공통. 파트가 하나뿐이라 헬기(대/소 2파트)보다 단순.
-- 첫 틱엔 Init이 켜둔 랜덤 블레이드가 남지 않게 전체를 한 번 숨긴다.
local function droneBladeTick()
    local v = findDroneVehicle()
    if not v then return end
    local part = v:getPartById("droneblade")
    if not part then return end

    if not _droneBladeInit then
        _droneBladeInit = true
        for i = 1, 8 do part:setModelVisible("blade" .. i, false) end
    end

    _droneBladeStep = _droneBladeStep + 1
    if _droneBladeStep > 8 then _droneBladeStep = 1 end
    local prev = _droneBladeStep - 1
    if prev < 1 then prev = 8 end
    part:setModelVisible("blade" .. prev, false)
    part:setModelVisible("blade" .. _droneBladeStep, true)
    -- 헬기 heliBladeTick 과 동일하게 update() 로 모델 상태 반영을 강제한다.
    -- 이게 없으면 BaseVehicle.updateTransform() 이 안 돌아 파트의
    -- renderTransform 이 직전 프레임 변환에 고정된다. 본체는 매 틱
    -- setWorldTransform 으로 따라가는데 파트만 뒤처지므로, 공전처럼 회전이
    -- 빠를수록 블레이드가 크게 어긋났다가 한 바퀴 돌아 자세가 비슷해지면
    -- 다시 맞아 보인다.
    pcall(function() v:update() end)
end

-- 모터음 거리 볼륨. 헬기와 달리 dmax를 detR+50(스폰 거리)로 잡는다 --
-- 접근 시작점이 정확히 그 거리이므로 페이드인이 0에서 자연스럽게 시작한다.
local function droneUpdateVolume(dx, dy)
    if not _droneSound then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end

    local dmax = SandboxVars.PongDu.Drone_DetectRadius + 50
    local ddx, ddy = dx - pl:getX(), dy - pl:getY()
    local d = math.sqrt(ddx * ddx + ddy * ddy)

    local k = 1 - d / dmax
    if k < 0 then k = 0 elseif k > 1 then k = 1 end

    local emitter = pl:getEmitter()
    pcall(function()
        emitter:setVolume(_droneSound,
            DRONE_VOL_FAR + (DRONE_VOL_NEAR - DRONE_VOL_FAR) * k)
    end)
    if _droneSmgSound then
        pcall(function()
            emitter:setVolume(_droneSmgSound,
                DRONE_SMG_VOL_FAR + (DRONE_SMG_VOL_NEAR - DRONE_SMG_VOL_FAR) * k)
        end)
    end
end

-- 사격음 루프 시작/정지 (engage/clear 전환 전용, 헬기 heliLmgStart 와 동형)
local function droneSmgStart()
    if _droneSmgSound then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    local ok, handle = pcall(function()
        return pl:getEmitter():playSound("pongdu_drone_smg")
    end)
    if ok and handle and handle ~= 0 then
        _droneSmgSound = handle
        pcall(function() pl:getEmitter():setVolume(handle, DRONE_SMG_VOL_FAR) end)
        print("[PongDu] fire_support/drone: SMG loop ENGAGE")
    else
        print("[PongDu] fire_support/drone: SMG loop start FAILED")
    end
end

local function droneSmgStop(reason)
    if not _droneSmgSound then return end
    local pl = getSpecificPlayer(0)
    if pl then pcall(function() pl:getEmitter():stopSound(_droneSmgSound) end) end
    _droneSmgSound = nil
    print("[PongDu] fire_support/drone: SMG loop stopped (" .. tostring(reason) .. ")")
end

-- ── 남은시간 패널 (헬기 h-210과 겹치지 않게 h-240) ────────────────────────
-- _droneEndAt은 droneStop이 참조하므로 패널보다 앞에 정의한다(헬기와 동일).
local _droneEndAt = nil
local _dronePanel = nil

local DroneTimerDisplay = ISPanel:derive("DroneTimerDisplay")

function DroneTimerDisplay:new()
    local w = getCore():getScreenWidth()
    -- y좌표는 timerStack이 등록 순서에 맞춰 잡아준다(register 전까지는 임시값 0).
    -- 폭 220 -> 240: 폰트를 한 단계(Small -> Medium) 키우면서 텍스트 폭도 늘어남.
    local o = ISPanel:new(w / 2 - 120, 0, 240, 30)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

function DroneTimerDisplay:render()
    if not _droneEndAt then return end
    local ms = _droneEndAt - getTimestampMs()
    if ms < 0 then ms = 0 end
    local totalSec = math.floor(ms / 1000)
    self:drawTextCentre(getText("IGUI_donation_fire_support_drone_timer")
        .. " " .. string.format("%02d:%02d", math.floor(totalSec / 60), totalSec % 60),
        self.width / 2, 0, 0.65, 0.85, 0.65, 1, UIFont.Medium)
end

function DroneTimerDisplay:update()
    if not _droneEndAt or _droneEndAt - getTimestampMs() <= 0 then
        timerStack.unregister(self)
        self:removeFromUIManager()
        _dronePanel = nil
    end
end

-- 카운터는 공전 진입 시점부터. 접근 1초는 제외한다.
local function droneTimerShow(orbitMs)
    _droneEndAt = getTimestampMs() + DRONE_APPROACH_MS + (tonumber(orbitMs) or 0)
    if not _dronePanel then
        _dronePanel = DroneTimerDisplay:new()
        _dronePanel:addToUIManager()
        _dronePanel:setVisible(true)
        timerStack.register(_dronePanel)
    end
end

local function droneStop(reason)
    droneSmgStop(reason)
    local pl = getSpecificPlayer(0)
    if _droneSound then
        if pl then pcall(function() pl:getEmitter():stopSound(_droneSound) end) end
        print("[PongDu] fire_support/drone: motor sound stopped (" .. tostring(reason) .. ")")
    end
    _droneSound     = nil
    _droneStopAt    = nil
    _drone          = nil
    _droneVid       = nil    -- 차량 제거 자체는 서버(permanentlyRemove)가 한다
    _droneAmPilot   = false
    _droneTarget    = nil
    _droneBladeInit = false
    _droneBladeStep = 0
    _droneWarned    = false
    _droneEndAt     = nil    -- 패널 update()가 다음 프레임에 스스로 제거한다
end

local function droneStart(orbitMs)
    local pl = getSpecificPlayer(0)
    if not pl then return end
    if not _droneSound then
        local ok, handle = pcall(function()
            return pl:getEmitter():playSound("pongdu_drone")
        end)
        if ok and handle and handle ~= 0 then
            _droneSound = handle
            -- 원거리 볼륨으로 시작. 이후 매 틱 거리 기반 갱신.
            pcall(function() pl:getEmitter():setVolume(handle, DRONE_VOL_FAR) end)
        else
            print("[PongDu] fire_support/drone: motor sound start FAILED")
        end
    end
    -- 유실 대비 자체 데드라인. 서버 DroneStop이 정상 도착하면 그쪽이 먼저 끈다.
    _droneStopAt = getTimestampMs() + DRONE_APPROACH_MS
        + (tonumber(orbitMs) or 60000) + DRONE_DEPART_MS + 2000
end

-- 드론 사격 1발 처리. 저격 SniperFire와 같은 구조지만 관통이 없고,
-- 킬/그레이즈 판정은 서버가 이미 굴려서 내려보낸 결과를 그대로 적용한다.
local function handleDroneFire(args)
    local ox = tonumber(args.ox) or 0
    local oy = tonumber(args.oy) or 0
    local oz = tonumber(args.oz) or 0
    local id = tonumber(args.id)

    if not id then
        -- 인식 반경 내 대상 없음. 연출 없이 스킵(로그도 남기지 않는다 --
        -- iv가 100ms라 대상 없는 구간에서 콘솔이 폭발한다).
        return
    end

    local z = findZombieById(id)
    -- 서버 좌표는 선정 시점 값이라 그 사이 움직였을 수 있다. 살아있으면 현재
    -- 좌표로 조준한다(저격과 동일).
    local tx, ty, tz = tonumber(args.tx) or 0, tonumber(args.ty) or 0, tonumber(args.tz) or 0
    if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end
    addTracer(ox, oy, oz, tx, ty, tz, DRONE_ALT_PX, TRACER_ALPHA_FAINT)

    if not z or z:isDead() then return end

    if args.kill then
        if z:isRemoteZombie() then
            -- 소유 클라가 아님 -> 연출만. 킬은 소유 클라가 수행한다.
            pcall(function() z:playSound("BulletHitBody") end)
        else
            local ok, err = pcall(function() killZombieNow(z) end)
            if ok then
                pcall(function() z:playSound("BulletHitBody") end)
            else
                print("[PongDu] fire_support/drone KILL FAILED zid="
                    .. tostring(id) .. " err=" .. tostring(err))
            end
        end
    else
        -- 사살 실패: 히트리액션만 반드시 재생(스펙). grazeZombie가 사운드/혈흔/
        -- 소유 클라 판정까지 전부 처리한다. 넉다운 여부는 서버가 굴려서
        -- kdHit(1/0)로 내려준다 -- 클라 굴림이 아니라 결과 적용만 한다.
        grazeZombie(z, id, nil, tonumber(args.kdHit) == 1)
    end
end

Events.OnTick.Add(function()
    if _heliStopAt and getTimestampMs() > _heliStopAt then
        heliSoundStop("local deadline")
    end
    if _heliPath then
        if _amPilot then heliPilotTick() end   -- 권한 클라만 실제 이동
        heliBladeTick()                        -- 로터 회전은 전 클라 로컬 연출
        -- 볼륨 램프: 기존엔 HeliFire 수신 시에만 갱신돼 clear(정찰) 구간에서
        -- 램프가 얼어붙었다. 매 틱 실좌표로 갱신해 교전 여부와 무관하게
        -- 접근/이탈이 이어지게 한다.
        local hx, hy = heliCurPos()
        if hx then heliUpdateVolume(hx, hy) end
    end
    -- 드론: 헬기와 독립적으로 동작한다(동시 발동 가능).
    if _droneStopAt and getTimestampMs() > _droneStopAt then
        droneStop("local deadline")
    end
    if _drone then
        if _droneAmPilot then dronePilotTick() end   -- 권한 클라만 실제 이동
        droneBladeTick()                             -- 로터 회전은 전 클라 로컬 연출
        local dx, dy = droneCurPos()
        if dx then droneUpdateVolume(dx, dy) end
    end
end)

-- ── 헬기 남은시간 표시 패널 (RainTimerDisplay/BombardTimerDisplay와 동일 스타일) ──
-- 레인(h-180), 폭격(h-150)과 동시 표시될 수 있으므로 30px 위(h-210)에 배치.
-- 남은시간은 HeliStart의 remain(ms)으로 로컬 데드라인을 잡아 계산한다.
local _heliPanel   = nil

local HeliTimerDisplay = ISPanel:derive("HeliTimerDisplay")

function HeliTimerDisplay:new()
    local w = getCore():getScreenWidth()
    -- y좌표는 timerStack이 등록 순서에 맞춰 잡아준다(register 전까지는 임시값 0).
    -- 폭 220 -> 240: 폰트를 한 단계(Small -> Medium) 키우면서 텍스트 폭도 늘어남.
    local o = ISPanel:new(w / 2 - 120, 0, 240, 30)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

function HeliTimerDisplay:render()
    if not _heliEndAt then return end
    local ms = _heliEndAt - getTimestampMs()
    if ms < 0 then ms = 0 end
    local totalSec = math.floor(ms / 1000)
    local m = math.floor(totalSec / 60)
    local sec = totalSec % 60
    self:drawTextCentre(getText("IGUI_donation_fire_support_heli_timer")
        .. " " .. string.format("%02d:%02d", m, sec),
        self.width / 2, 0, 0.65, 0.85, 0.65, 1, UIFont.Medium)
end

function HeliTimerDisplay:update()
    if not _heliEndAt or _heliEndAt - getTimestampMs() <= 0 then
        timerStack.unregister(self)
        self:removeFromUIManager()
        _heliPanel = nil
    end
end

local function heliTimerShow(remainMs)
    _heliEndAt = getTimestampMs() + (tonumber(remainMs) or 0)
    if not _heliPanel then
        _heliPanel = HeliTimerDisplay:new()
        _heliPanel:addToUIManager()
        _heliPanel:setVisible(true)
        timerStack.register(_heliPanel)
    end
end

-- 헬기 사격 1발 처리. 저격과 달리 "적당히 탄이 튀는" 난사 연출:
--   kill=true  -> 좀비 정조준(실명중). 소유 클라가 킬 수행.
--   kill 없음  -> 좀비 근처 ±2타일 산탄 오프셋으로 빗나가는 탄만 그린다.
--   id 없음    -> 반경 내 좀비가 없어 지면 난사(서버가 랜덤 지점 좌표를 보냄).
-- 헬기 원점 고도(px). 예광탄은 실제 3D 렌더와 무관한 수제 스크린좌표 연출이라
-- HELI_FLY_ALT(물리 y, 실제 모델이 뜨는 높이)와 원래 아예 안 이어져 있었다 --
-- 그래서 고도를 3.0->8.0으로 올렸을 때 헬기 본체는 위로 올라갔는데 예광탄은
-- 옛 낮은 고도 기준(260px)에 그대로 남아 "헬기 한참 아래에서 발사" 버그가 났다.
-- 정확한 물리y->스크린px 변환식은 엔진 렌더러 내부값이라 알 수 없어서, 처음
-- 튜닝됐던 3.0px<->260px 비율(≈86.7px/unit)을 그대로 다음 고도에도 적용해
-- 최소한 "같이 움직이게"는 만든다. 고도를 또 바꾸면 HELI_FLY_ALT만 고치면
-- 이 값이 자동으로 따라간다 -- 다만 비율 자체가 근사치라 눈으로 보고
-- HELI_ALT_PX_PER_UNIT을 미세조정할 것.
local HELI_ALT_PX_PER_UNIT = 86.7
local HELI_ALT     = HELI_FLY_ALT * HELI_ALT_PX_PER_UNIT
local HELI_SCATTER = 2.0     -- 미스탄 산탄 반경(타일)

local function handleHeliFire(args)
    local ox = tonumber(args.ox) or 0
    local oy = tonumber(args.oy) or 0
    local oz = tonumber(args.oz) or 0
    local id = tonumber(args.id)
    local tx = tonumber(args.x) or 0
    local ty = tonumber(args.y) or 0
    local tz = tonumber(args.z) or 0
    local kill = args.kill and true or false

    local z = id and findZombieById(id) or nil
    if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end

    -- 실차량(또는 폴백 경로 보간) 좌표를 예광탄 원점으로 쓴다 -- 서버 발사
    -- 시점 좌표(ox,oy)보다 화면의 헬기와 정확히 일치한다.
    local px2, py2 = heliCurPos()
    if px2 then ox, oy = px2, py2 end

    -- 헬기 현재 위치 기준 로터음/기관총음 볼륨 갱신 (접근/이탈 연출)
    heliUpdateVolume(ox, oy)

    if not kill then
        -- 난사 느낌: 미스탄은 목표에서 살짝 빗나가게
        tx = tx + (ZombRand(HELI_SCATTER * 200) - HELI_SCATTER * 100) / 100.0
        ty = ty + (ZombRand(HELI_SCATTER * 200) - HELI_SCATTER * 100) / 100.0
    end
    addTracer(ox, oy, oz, tx, ty, tz, HELI_ALT)

    -- 발당 트리거 없음: 총성은 heliSoundStart에서 튼 pongdu_heli_lmg 루프가
    -- 발동~종료 구간 내내 재생 중이라 여기선 예광탄/킬 판정만 처리한다.

    if kill and z and not z:isDead() then
        if z:isRemoteZombie() then
            pcall(function() z:playSound("BulletHitBody") end)
        else
            local ok, err = pcall(function() killZombieNow(z) end)
            if ok then
                pcall(function() z:playSound("BulletHitBody") end)
                print("[PongDu] fire_support/heli KILL zid=" .. tostring(id))
            else
                print("[PongDu] fire_support/heli KILL FAILED zid="
                    .. tostring(id) .. " err=" .. tostring(err))
            end
        end
    end
end

-- 서버가 iv 간격으로 한 발씩 보내는 사격 명령 수신. 전 클라에 브로드캐스트되며,
-- 각 클라는 연출(예광탄+총성)을 전부 그리되 킬은 자기가 소유한 좀비에 대해서만
-- 수행한다. 대상 선정/재선정과 타이밍은 전부 server.lua의 job 큐가 맡으므로,
-- 여기서는 큐잉 없이 수신 즉시 그 한 발을 처리한다.
Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuFireSupport" then return end
    -- HeliEngage/HeliClear/HeliStop처럼 빈 테이블로 보낸 명령은 수신 측에서
    -- args가 nil로 역직렬화된다. 여기서 return하면 그 명령들이 통째로
    -- 버려지므로(LMG/area_clear 미재생의 원인이었다) 빈 테이블로 정규화한다.
    args = args or {}

    if command == "HeliStart" then
        if args.ax then
            _heliPath = {
                ax = tonumber(args.ax) or 0, ay = tonumber(args.ay) or 0,
                bx = tonumber(args.bx) or 0, by = tonumber(args.by) or 0,
                oz = tonumber(args.oz) or 0,
                total = tonumber(args.total) or 30000,
                yawSet = false,   -- 새 경로마다 파일럿이 기수 방향 재설정
            }
            -- 로컬 시계 기준 시작점: 이미 elapsed만큼 진행된 상태에서 이어받는다
            -- (급선회로 갈아끼워질 때도 elapsed=0으로 오므로 자동으로 t0=now).
            _heliPath.t0 = getTimestampMs() - (tonumber(args.elapsed) or 0)
        end
        -- 실차량 연동: 서버가 스폰한 VehicleID와 물리 권한 대상(pilot).
        -- SP에선 양쪽 onlineID가 모두 -1이라 자동으로 파일럿이 된다.
        if args.vid then _heliVid = tonumber(args.vid) end
        local me = getSpecificPlayer(0)
        _amPilot = (me ~= nil) and (args.pilot ~= nil)
            and (tonumber(args.pilot) == me:getOnlineID())
        print(string.format("[PongDu] fire_support/heli: start vid=%s pilot=%s amPilot=%s",
            tostring(_heliVid), tostring(args.pilot), tostring(_amPilot)))
        heliSoundStart(args.remain)
        heliTimerShow(args.remain)
        return
    elseif command == "HeliStop" then
        heliSoundStop("server stop")
        return
    elseif command == "HeliEngage" then
        heliLmgStart()
        return
    elseif command == "HeliClear" then
        -- 교전 종료: 기관총 소리 끄고 "구역 정리" 무전 1회 재생.
        -- 남은 시간 동안 헬기(로터음)는 계속 떠 있고, 좀비가 다시 감지되면
        -- 서버가 HeliEngage를 다시 보내 사격을 재개한다.
        heliLmgStop("area clear")
        local okS = pcall(function()
            getSoundManager():PlaySound("area_clear", false, 1.0)
        end)
        if not okS then print("[PongDu] fire_support/heli: area_clear sound failed") end
        return
    elseif command == "HeliFire" then
        handleHeliFire(args)
        return
    elseif command == "DroneStart" then
        _drone = {
            sx       = tonumber(args.sx) or 0,
            sy       = tonumber(args.sy) or 0,
            oz       = tonumber(args.oz) or 0,
            th0      = tonumber(args.th0) or 0,
            orbitR   = tonumber(args.orbitR) or 4,
            orbitMs  = tonumber(args.orbitMs) or 60000,
            periodMs = tonumber(args.periodMs) or 6000,
            t0       = getTimestampMs(),
        }
        _droneVid    = args.vid and tonumber(args.vid) or nil
        _droneTarget = args.target
        _droneBladeInit = false
        _droneBladeStep = 0
        -- SP에선 양쪽 onlineID가 모두 -1이라 자동으로 파일럿이 된다(헬기와 동일).
        local meD = getSpecificPlayer(0)
        _droneAmPilot = (meD ~= nil) and (args.pilot ~= nil)
            and (tonumber(args.pilot) == meD:getOnlineID())
        print(string.format("[PongDu] fire_support/drone: start vid=%s pilot=%s amPilot=%s target=%s",
            tostring(_droneVid), tostring(args.pilot), tostring(_droneAmPilot),
            tostring(_droneTarget)))
        droneStart(_drone.orbitMs)
        droneTimerShow(_drone.orbitMs)
        return
    elseif command == "DroneStop" then
        droneStop("server stop")
        return
    elseif command == "DroneExtend" then
        -- 중첩 후원: 드론을 새로 띄우지 않고 궤도 시간만 늘린다.
        local addMs = tonumber(args.addMs) or 0
        if _drone then
            _drone.orbitMs = _drone.orbitMs + addMs
        end
        if _droneEndAt then _droneEndAt = _droneEndAt + addMs end
        if _droneStopAt then _droneStopAt = _droneStopAt + addMs end
        print("[PongDu] fire_support/drone: extended +" .. tostring(addMs) .. "ms")
        return
    elseif command == "DroneEngage" then
        droneSmgStart()
        return
    elseif command == "DroneClear" then
        droneSmgStop("area clear")
        return
    elseif command == "DroneFire" then
        handleDroneFire(args)
        return
    end

    if command ~= "SniperFire" then return end

    local ox = tonumber(args.ox) or 0
    local oy = tonumber(args.oy) or 0
    local oz = tonumber(args.oz) or 0
    local id = tonumber(args.id)

    if not id then
        -- 서버 job이 이번 발엔 반경 내 대상을 못 찾은 경우(MISS). 연출 없이 스킵.
        print("[PongDu] fire_support/sniper: shot MISS (no target in radius)")
        return
    end

    local z = findZombieById(id)
    -- 서버가 보낸 좌표는 선정 시점 값이라 좀비가 그 사이 움직였을 수 있다.
    -- 살아있으면 현재 좌표로 조준한다.
    local tx, ty, tz = tonumber(args.x) or 0, tonumber(args.y) or 0, tonumber(args.z) or 0
    if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end
    addTracer(ox, oy, oz, tx, ty, tz)

    -- 총성: 비위치성 로컬 재생. addSound()를 부르지 않으므로 어그로 0.
    local okS = pcall(function()
        getSoundManager():PlaySound("AWP_Bang", false, 0.8)
    end)
    if not okS then print("[PongDu] fire_support/sniper: shot sound failed") end

    if z and not z:isDead() then
        if z:isRemoteZombie() then
            -- 소유 클라가 아님 -> 연출만. 킬은 소유 클라가 수행한다.
            pcall(function() z:playSound("BulletHitBody") end)
        else
            local ok, err = pcall(function() killZombieNow(z) end)
            if ok then
                pcall(function() z:playSound("BulletHitBody") end)
                print("[PongDu] fire_support/sniper KILL zid=" .. tostring(id))
            else
                print("[PongDu] fire_support/sniper KILL FAILED zid="
                    .. tostring(id) .. " err=" .. tostring(err))
            end
        end
    else
        print("[PongDu] fire_support/sniper: target gone zid=" .. tostring(id))
    end

    -- 관통 사살: 서버가 저격수-주표적 선분 위에서 골라 확률 판정까지 마친 목록.
    -- 예광탄이 이미 그 선을 지나므로 별도 연출은 필요 없다.
    if args.ex then
        for k = 1, #args.ex do
            local eid = tonumber(args.ex[k])
            local ez  = eid and findZombieById(eid) or nil
            if ez and not ez:isDead() then
                if ez:isRemoteZombie() then
                    pcall(function() ez:playSound("BulletHitBody") end)
                else
                    local ok2, err2 = pcall(function() killZombieNow(ez) end)
                    if ok2 then
                        pcall(function() ez:playSound("BulletHitBody") end)
                        print("[PongDu] fire_support/sniper KILL(pierce) zid=" .. tostring(eid))
                    else
                        print("[PongDu] fire_support/sniper KILL(pierce) FAILED zid="
                            .. tostring(eid) .. " err=" .. tostring(err2))
                    end
                end
            end
        end
    end

    -- 관통에 맞았지만 확률 판정에서 살아남은 좀비: 넉다운 또는 움찔.
    if args.gz then
        local kd = tonumber(args.kd) or 50
        for k = 1, #args.gz do
            local gid = tonumber(args.gz[k])
            grazeZombie(gid and findZombieById(gid) or nil, gid, kd)
        end
    end
end)

-- b(): 진행 중인 화력 지원 연출을 전부 정리한다 (예광탄).
-- 사격 타이밍/잔여 발수는 이제 서버 job이 들고 있으므로 클라에서 정리할
-- 큐가 없다. 플레이어 사망/접속 종료 시 호출할 것. [public name: .b]
function _a.b()
    _tracers = {}
    heliSoundStop("cleanup")
    droneStop("cleanup")
end

return _a
