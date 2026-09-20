local _a = {}

local global = require("global")
local timerStack = require("utils/timerStack")
local colorMap = require("utils/colorMap")
local textOutline = require("utils/textOutline")

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

-- 저격 파라미터: Sniper_Radius / Sniper_Duration(s) / Sniper_Interval(ms).
local function sniperCfg()
    local sv = SandboxVars.PongDu
    return sv.Sniper_Radius,
           sv.Sniper_Duration,
           sv.Sniper_Interval,
           sv.Sniper_PierceChance,
           sv.Sniper_KnockdownChance
end

-- 헬기 파라미터: Heli_Duration(s) / Heli_Radius / Heli_Interval(ms) / Heli_CritChance(%).
local function heliCfg()
    local sv = SandboxVars.PongDu
    return sv.Heli_Duration,
           sv.Heli_Radius,
           sv.Heli_Interval,
           sv.Heli_CritChance
end

-- 드론 파라미터: Drone_Duration(s) / Drone_DetectRadius / Drone_Interval(ms) /
-- Drone_CritChance(%) / Drone_KnockdownChance(%).
-- 공전 반경/주기는 서버 상수(DRONE_ORBIT_R / DRONE_PERIOD_S)로 고정됐다.
local function droneCfg()
    local sv = SandboxVars.PongDu
    return sv.Drone_Duration,
           sv.Drone_DetectRadius,
           sv.Drone_Interval,
           sv.Drone_CritChance,
           sv.Drone_KnockdownChance
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
    local radius, dur, interval, pcChance, kdChance = sniperCfg()
    -- 관통: 저격수와 주 표적 사이 직선상의 좀비를 전부 훑는다.
    -- 사살 여부/넉다운 여부는 서버가 굴려서 내려보낸다.
    local pierce = SandboxVars.PongDu.Sniper_Pierce
    print(string.format("[PongDu] fire_support/sniper request r=%d dur=%d interval=%d pierce=%s chance=%d knockdown=%d",
        radius, dur, interval, tostring(pierce), pcChance, kdChance))
    sendClientCommand("PongDuFireSupport", "Sniper", {
        r = radius, dur = dur, iv = interval, sender = sender or "",
        pc = pierce, pcc = pcChance, kd = kdChance,
    })
end

-- 드론: 지속(짧음). interval 마다 소수 처치. 모터음 루프.
-- 드론: 저격과 같은 방식으로 뽑은 화면 밖 지점에서 접근해, 플레이어를 중심으로
-- 시계방향 공전하며 사격한다. 공전 위치/타겟팅/킬 굴림은 전부 서버 job이
-- 맡는다(저격·헬기와 동일한 이유 -- 킬 판정의 단일 권위가 필요).
runners.drone = function(player, sender)
    local dur, detR, iv, kc, kd = droneCfg()
    print(string.format(
        "[PongDu] fire_support/drone request dur=%ds detR=%d iv=%d crit=%d%% kd=%d%%",
        dur, detR, iv, kc, kd))
    sendClientCommand("PongDuFireSupport", "Drone", {
        dur = dur, dr = detR, iv = iv,
        kc = kc, kd = kd, sender = sender or "",
    })
end

-- 헬기: 지속(김). 랜덤 지점 A -> B 로 이동하며 플레이어 반경 내 좀비를
-- 무차별 소사. 저격과 달리 발당 킬 확률(기본 30%)이 낮은 대신 연사가 빠르다.
-- A/B 산출, 대상 선정, 킬 룰렛, 발사 타이밍 전부 서버 job이 맡는다
-- (이유는 저격과 동일 -- 킬 총량/타이밍의 단일 권위가 필요).
runners.helicopter = function(player, sender)
    local dur, radius, interval, kc = heliCfg()
    print(string.format("[PongDu] fire_support/heli request dur=%ds r=%d iv=%d crit=%d%%",
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
-- true/false 면 서버가 이미 굴린 결과를 그대로 적용한다(구 드론 경로 --
-- 지금 드론은 fsApplyShot 의 kd 인자를 쓴다). 서버가
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
--  헬기/드론 사격 데미지 (크리티컬 / 일반)
--
--  샌드박스 값은 "깎이는 체력" 단위다. Hit()에 넣는 값은 그대로 체력에서
--  빠지지 않고 엔진이 배율을 곱하므로 역산해서 넘긴다
--  (IsoGameCharacter.processHitDamage / Hit / hitConsequences, B41.78.20):
--    x1.5  맞는 쪽이 IsoPlayer 가 아님
--    x0.3  쏘는 쪽(fakeZombie) 무기 레벨 0 -- 손에 든 무기가 없음
--    x0.5  TwoHandWeapon 을 양손에 안 듦 (HuntingRifle = TwoHandWeapon)
--    x0.7  IsAimedFirearm
--  → 실제 체력 감소 = 입력값 x 0.1575. 쏘는 쪽/무기를 바꾸면 이 값도 바뀐다.
--
--  Hit() 부작용 처리:
--    hitTime  -- 같은 좀비가 4번째 피격부터 입력값에 (hitTime-2)*1.5 가 곱해진다
--                (IsoGameCharacter.Hit). 좀비 평생 누적이라 그대로 두면 일반
--                데미지가 4발째부터 폭증한다. Hit 직전 0으로 두고 끝나면 원복해서
--                화력지원 탄은 카운트에 안 남긴다.
--    setTarget -- 생존 시 hitConsequences 가 target 을 fakeZombie(0,0)로 바꾼다.
--                원래 타겟으로 되돌려 플레이어 추적이 끊기지 않게 한다.
--    크롤러화  -- 생존 피격마다 1/30 확률로 기어다니는 좀비가 된다
--                (IsoZombie.shouldBecomeCrawler). 드론은 수십 발을 맞히므로
--                원래 크롤러 예정이 아니었으면 플래그를 되돌린다.
--  피격 리액션은 hitConsequences 의 reportEvent("wasHit")가 setHitReaction
--  으로 지정한 모션을 재생한다.
-- ═══════════════════════════════════════════════════════════════════════════
local HIT_SCALE          = 1.5 * 0.3 * 0.5 * 0.7   -- 0.1575
local DRONE_NORMAL_RATIO = 0.25                     -- 드론 일반 = 헬기 일반의 1/4

-- kind: "heli" | "drone". 발동 시점에 읽는다(샌드박스 캐싱 금지).
local function fsShotHp(kind, crit)
    local sv = SandboxVars.PongDu
    if crit then return sv.FireSupport_CritDamage end
    if kind == "drone" then return sv.FireSupport_NormalDamage * DRONE_NORMAL_RATIO end
    return sv.FireSupport_NormalDamage
end

-- ── 검증 로그 ──────────────────────────────────────────────────────────────
-- 드론은 초당 수십 발이라 발당 로그는 콘솔을 터뜨린다. 대신:
--   ① 좀비별 누적 집계 -> 사망 시 KILL 로그 한 줄(hits/crits/dealt/hp0)
--   ② 교전 시작(같은 tag 로 FS_VERIFY_GAP_MS 이상 쉬었다 재개) 후 첫
--      FS_VERIFY_SHOTS 발만 VERIFY 로그(체력 전/후/기대값 + 부작용 복구 결과)
--   ③ 폴백 경로 진입은 세션당 1회
-- 집계는 소유 클라에서만 쌓인다(데미지를 실제로 넣는 쪽). 소유권이 중간에
-- 넘어가면 새 소유 클라는 그 시점부터 센다.
local FS_VERIFY_SHOTS  = 3
local FS_VERIFY_GAP_MS = 5000
local FS_STATS_MAX     = 256     -- 이 이상 쌓이면 오래된 항목 정리
local FS_STATS_TTL_MS  = 60000   -- 마지막 피격 후 이 시간 지나면 정리 대상

local _fsStats  = {}   -- zid -> { hits, crits, dealt, hp0, t }
local _fsStatsN = 0
local _fsVerify = {}   -- tag -> { n, lastAt }
local _fsFallbackWarned = false

local function fsStatsGet(id, z, now)
    local st = _fsStats[id]
    if st then return st end
    if _fsStatsN >= FS_STATS_MAX then
        -- pairs 순회 중 삭제는 Kahlua 에서 보장되지 않으므로 새 테이블로 재구성.
        local fresh, n = {}, 0
        for k, v in pairs(_fsStats) do
            if now - v.t < FS_STATS_TTL_MS then
                fresh[k] = v
                n = n + 1
            end
        end
        print("[PongDu] fire_support: stats pruned " .. tostring(_fsStatsN) .. " -> " .. tostring(n))
        _fsStats, _fsStatsN = fresh, n
    end
    st = { hits = 0, crits = 0, dealt = 0, hp0 = z:getHealth(), t = now }
    _fsStats[id] = st
    _fsStatsN = _fsStatsN + 1
    return st
end

local function fsVerifyTick(tag, now)
    local v = _fsVerify[tag]
    if not v then
        v = { n = 0, lastAt = 0 }
        _fsVerify[tag] = v
    end
    if now - v.lastAt > FS_VERIFY_GAP_MS then v.n = 0 end
    v.lastAt = now
    v.n = v.n + 1
    return v.n <= FS_VERIFY_SHOTS
end

-- 한 발 적용. 사운드/혈흔은 전 클라 로컬 연출, 데미지는 소유 클라만.
-- crit: 서버가 굴린 크리티컬 여부(집계/로그용 -- hp 는 이미 반영돼 들어온다).
-- kd: true 면 생존 시 넘어뜨린다(드론 일반탄, 서버가 굴린 결과).
local function fsApplyShot(z, id, hp, crit, kd, tag)
    if not z or z:isDead() then return end
    pcall(function() z:playSound("BulletHitBody") end)
    pcall(function() z:splatBlood(2, 0.3) end)
    -- 원격 좀비에 Hit 하면 소유 클라 sync 에 덮인다 -- 연출만 하고 끝.
    if z:isRemoteZombie() then return end

    local ok, err = pcall(function()
        local now    = getTimestampMs()
        local st     = fsStatsGet(id, z, now)
        local verify = fsVerifyTick(tag, now)
        local before = z:getHealth()
        st.hits = st.hits + 1
        if crit then st.crits = st.crits + 1 end
        st.t = now

        local gun = sniperWeapon()
        if not gun then
            -- 폴백: 총기 생성 실패. 체력만 직접 깎는다(모션 없음).
            if not _fsFallbackWarned then
                _fsFallbackWarned = true
                print("[PongDu] fire_support/" .. tag
                    .. " FALLBACK: no weapon item, applying setHealth directly (no hit anim)")
            end
            st.dealt = st.dealt + math.min(hp, before)
            local left = before - hp
            if left <= 0 then
                killZombieNow(z)
            else
                z:setHealth(left)
            end
            return
        end
        local fake        = getCell():getFakeZombieForHit()
        local prevTarget  = z:getTarget()
        local prevHitTime = z:getHitTime()
        local prevCrawler = z:isBecomeCrawler()

        z:setHitTime(0)
        z:setBumpDone(true)
        z:setHitReaction(GRAZE_REACTIONS[ZombRand(#GRAZE_REACTIONS) + 1])
        z:Hit(gun, fake, hp / HIT_SCALE, false, 1, false)
        local hitTimeAfter = z:getHitTime()   -- 1 이어야 정상(0 에서 +1)
        z:setHitTime(prevHitTime)

        local after = z:getHealth()
        st.dealt = st.dealt + (before - after)
        local dead = z:isDead()

        local crawlerBlocked = false
        local targetKept = true
        if not dead then
            if z:getTarget() ~= prevTarget then
                z:setTarget(prevTarget)
                targetKept = (z:getTarget() == prevTarget)
            end
            if not prevCrawler and z:isBecomeCrawler() then
                z:setBecomeCrawler(false)
                crawlerBlocked = true
                print("[PongDu] fire_support/" .. tag .. " crawler blocked zid=" .. tostring(id))
            end
            if kd then z:knockDown(false) end
        end

        if verify then
            -- expected 는 요청 hp 와 남은 체력 중 작은 값(체력보다 많이 깎을 순 없다).
            -- delta 가 expected 와 다르면 HIT_SCALE(0.1575) 가정이 틀린 것.
            print(string.format(
                "[PongDu] fire_support/%s VERIFY zid=%s crit=%d in=%.3f before=%.3f after=%.3f delta=%.3f expected=%.3f hitTime=%d->%d(restored %d) target=%s crawlerBlocked=%s dead=%s",
                tag, tostring(id), crit and 1 or 0, hp / HIT_SCALE, before, after,
                before - after, math.min(hp, before), hitTimeAfter, prevHitTime,
                z:getHitTime(), targetKept and "kept" or "LOST",
                tostring(crawlerBlocked), tostring(dead)))
        end

        if dead then
            z:setAttackedBy(fake)
            print(string.format(
                "[PongDu] fire_support/%s KILL zid=%s hits=%d crits=%d dealt=%.3f hp0=%.3f last=%.3f",
                tag, tostring(id), st.hits, st.crits, st.dealt, st.hp0, hp))
            _fsStats[id] = nil
            _fsStatsN = _fsStatsN - 1
        end
    end)
    if not ok then
        print("[PongDu] fire_support/" .. tag .. " HIT FAILED zid="
            .. tostring(id) .. " hp=" .. tostring(hp) .. " err=" .. tostring(err))
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

-- ═══════════════════════════════════════════════════════════════════════════
--  멀티 인스턴스 레지스트리
--
--  [왜 바뀌었나]
--   서버는 _heliJobs/_droneJobs 를 리스트로 들고 있어 플레이어별 job 을 동시에
--   여러 개 굴린다(플레이어당 1개, 중첩 후원은 기존 job 연장). 그런데 클라는
--   _heliPath/_drone 을 모듈 전역 하나로만 갖고 있어서, 두 번째 HeliStart 가
--   도착하는 순간 첫 번째를 덮어썼다. 결과:
--     - 먼저 뜬 헬기가 화면에서 증발(서버 job 은 계속 사격 중)
--     - 둘 중 하나의 Stop 이 나머지까지 같이 종료
--     - _amPilot 이 하나뿐이라 실차량 물리 권한이 뒤섞임
--   개인후원 두 명이 동시에 받기만 해도 재현되는 구조적 결함이었다.
--
--  [키]
--   서버가 모든 화력지원 페이로드에 own(소유 플레이어 onlineID)을 싣는다.
--   서버 쪽이 "플레이어당 job 1개"를 이미 강제하므로 own 은 유효한 유일키다.
--   SP 에선 양쪽 onlineID 가 -1 이라 -1 하나로 정상 동작한다(기존과 동일).
--
--  [무엇이 인스턴스이고 무엇이 공유인가]
--   인스턴스별  : 경로/궤도, 차량 vid, 파일럿 여부, 블레이드 위상, 데드라인
--   공유(싱글턴): 사운드 핸들, 남은시간 패널
--     - 사운드를 인스턴스마다 틀면 8대일 때 로터음 8중첩이라 귀가 터지고
--       emitter 도 고갈된다. 루프는 1개만 유지하고(설계 제약 4 그대로)
--       볼륨은 "가장 가까운 기체" 기준으로 매 틱 갱신한다.
--     - 패널은 "내 화력지원"의 남은시간만 띄운다. 남의 헬기 타이머까지
--       쌓으면 화면만 어지럽고 행동에 쓸 정보가 아니다.
-- ═══════════════════════════════════════════════════════════════════════════

local _helis  = {}    -- [own] = 헬기 인스턴스
local _drones = {}    -- [own] = 드론 인스턴스

-- tempTransform 자바 필드 인덱스. BaseVehicle 클래스 공용이라 인스턴스와
-- 무관하게 하나만 캐시하면 된다(헬기/드론 공용).
local _wFieldNum = nil

local function myOnlineID()
    local p = getSpecificPlayer(0)
    if not p then return nil end
    local ok, id = pcall(function() return p:getOnlineID() end)
    if ok then return id end
    return nil
end

-- own 파싱. 서버/클라가 같은 모드에서 나가므로 nil 이 나올 일은 없지만,
-- 나오면 조용히 무시하지 말고 반드시 로그를 남긴다.
local function ownOf(args, where)
    local own = tonumber(args.own)
    if not own then
        print("[PongDu] fire_support: missing own in " .. tostring(where)
            .. " -- version mismatch?")
        return nil
    end
    return own
end

local function tcount(t)
    local n = 0
    for _ in pairs(t) do n = n + 1 end
    return n
end

-- ── 루프 사운드 핸들 관리 (플레이어 객체 교체 대비) ────────────────────────
--
-- [왜 emitter 객체를 같이 들고 있어야 하는가]
--   IsoGameCharacter.emitter 는 final 필드라 생성자에서 한 번 만들어진다
--   (IsoGameCharacter.java:340, 626). 즉 플레이어 객체가 교체되면 emitter 도
--   통째로 새것이 된다.
--   CharacterSoundEmitter.stopSound(handle) 는 "자기 소유" 의 vocals/footsteps/
--   extra FMODSoundEmitter 3개에만 정지를 넘긴다(CharacterSoundEmitter.java:263).
--   따라서 A 의 emitter 에서 얻은 핸들을 B 의 emitter 에 걸면 조용히 no-op 이다.
--   그리고 SoundManager.unregisterEmitter 는 리스트에서 빼기만 하고 재생을
--   멈추지 않으므로(SoundManager.java:374), loop = true 인 로터음/기관총음이
--   영원히 남는다. 이게 "화력지원이 끝나도 소리가 잔존" 의 정체다.
--
--   -> 재생한 emitter 객체를 핸들과 한 쌍으로 보관했다가, 정지할 때 반드시
--      "그 emitter" 로 끈다. getSpecificPlayer(0) 을 정지 시점에 다시 조회하면
--      안 된다.
--
-- [이름 기준 정지를 한 번 더 거는 이유]
--   핸들이 이미 무효화된 경우(FMOD 인스턴스 재활용 등)에도 alias 로는 잡힌다.
--   stopSoundByName 은 BaseSoundEmitter 의 public 추상 메서드이며
--   CharacterSoundEmitter 가 3개 하위 emitter 로 그대로 위임한다
--   (CharacterSoundEmitter.java:299). 이 모듈은 alias 하나당 루프를 최대 1개만
--   유지하므로 이름으로 싹 끄는 게 안전하다.
local function loopSoundStart(alias, vol)
    local pl = getSpecificPlayer(0)
    if not pl then return nil, nil end
    local okE, em = pcall(function() return pl:getEmitter() end)
    if not okE or not em then return nil, nil end
    local okH, handle = pcall(function() return em:playSound(alias) end)
    if not okH or not handle or handle == 0 then return nil, nil end
    pcall(function() em:setVolume(handle, vol) end)
    return handle, em
end

local function loopSoundStop(emitter, handle, alias)
    if emitter then
        pcall(function() emitter:stopSound(handle) end)
        pcall(function() emitter:stopSoundByName(alias) end)
    end
    -- 저장본과 현재 플레이어 emitter 가 다를 수 있으므로 현재 쪽도 이름으로 정리.
    local pl = getSpecificPlayer(0)
    if pl then
        pcall(function() pl:getEmitter():stopSoundByName(alias) end)
    end
end

-- 이 모듈이 유지하는 loop = true 사운드 전부. t3_rewards_sounds.txt 에서
-- loop 이 걸린 건 이 4개뿐이다.
local FS_LOOP_ALIASES = {
    "pongdu_heli", "pongdu_heli_lmg", "pongdu_drone", "pongdu_drone_smg",
}

-- 로드 직후 1회 스윕. /reloadlua 나 모드 핫리로드로 Lua state 가 재생성되면
-- _heliSound/_heliEmitter 같은 전역이 통째로 날아가서, 이미 돌고 있던 루프
-- 사운드를 끌 수단이 완전히 사라진다(게임 재시작 전까지 영구 잔존).
-- 핸들이 없어도 alias 로는 잡히므로, 새 state 의 첫 틱에 4종을 이름으로
-- 한 번 쓸어준다. 이 시점엔 _helis/_drones 가 반드시 비어 있으므로
-- 정상 재생 중인 소리를 잘못 끄는 경우는 없다.
local _sndSwept = false
local function fsSweepStaleLoops()
    if _sndSwept then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end
    _sndSwept = true
    for i = 1, #FS_LOOP_ALIASES do
        local alias = FS_LOOP_ALIASES[i]
        pcall(function() pl:getEmitter():stopSoundByName(alias) end)
    end
    print("[PongDu] fire_support: stale loop sound sweep done")
end

-- ── 저격 남은시간 패널 (내 화력지원 전용) ──────────────────────────────────
-- 헬기/드론 패널과 동시 표시될 수 있으므로 timerStack이 배치한다.
local _sniperEndAt = nil
local _sniperPanel = nil

local SniperTimerDisplay = ISPanel:derive("SniperTimerDisplay")

function SniperTimerDisplay:new()
    local w = getCore():getScreenWidth()
    local o = ISPanel:new(w / 2 - 120, 0, 240, 30)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

function SniperTimerDisplay:render()
    if not _sniperEndAt then return end
    local ms = _sniperEndAt - getTimestampMs()
    if ms < 0 then ms = 0 end
    local totalSec = math.floor(ms / 1000)
    local col = colorMap.get("fire_support")
    textOutline.drawCentre(self, getText("IGUI_donation_fire_support_sniper_timer")
        .. " " .. string.format("%02d:%02d",
            math.floor(totalSec / 60), totalSec % 60),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
end

function SniperTimerDisplay:update()
    if not _sniperEndAt or _sniperEndAt - getTimestampMs() <= 0 then
        timerStack.unregister(self)
        self:removeFromUIManager()
        _sniperPanel = nil
    end
end

local function sniperTimerShow(remainMs)
    _sniperEndAt = getTimestampMs() + (tonumber(remainMs) or 0)
    if not _sniperPanel then
        _sniperPanel = SniperTimerDisplay:new()
        _sniperPanel:addToUIManager()
        _sniperPanel:setVisible(true)
        timerStack.register(_sniperPanel)
    end
end

local function sniperTimerHide()
    _sniperEndAt = nil   -- 패널 update()가 다음 프레임에 스스로 제거한다
end

local HELI_VOL_NEAR     = 0.50   -- 최근접 시 로터음 볼륨
local HELI_VOL_FAR      = 0.20   -- 최원거리 시 로터음 볼륨
local HELI_LMG_VOL_NEAR = 0.40   -- 기관총음은 로터음보다 살짝 낮게
local HELI_LMG_VOL_FAR  = 0.15

-- 핸들은 반드시 "재생한 emitter" 와 한 쌍으로 보관한다 (loopSoundStart 주석 참조).
local _heliSound,   _heliEmitter = nil, nil   -- 로터음 (전체 공유 1개)
local _lmgSound,    _lmgEmitter  = nil, nil   -- 기관총 루프 (전체 공유 1개)

-- ── 헬기 남은시간 패널 (내 화력지원 전용) ──────────────────────────────────
-- 레인(h-180), 폭격(h-150)과 동시 표시될 수 있으므로 timerStack이 배치한다.
-- _heliEndAt은 패널 클래스와 heliRemove가 모두 참조하므로 앞에 선언한다
-- (뒤에 두면 Kahlua에서 전역(nil) 조회로 잡혀 "tried to call nil" 크래시).
local _heliEndAt = nil
local _heliPanel = nil

local HeliTimerDisplay = ISPanel:derive("HeliTimerDisplay")

function HeliTimerDisplay:new()
    local w = getCore():getScreenWidth()
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
    local col = colorMap.get("fire_support")
    textOutline.drawCentre(self, getText("IGUI_donation_fire_support_heli_timer")
        .. " " .. string.format("%02d:%02d",
            math.floor(totalSec / 60), totalSec % 60),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
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

local function heliTimerHide()
    _heliEndAt = nil   -- 패널 update()가 다음 프레임에 스스로 제거한다
end

-- ═══════════════════════════════════════════════════════════════════════════
--  헬기 실체 (Base.PongDuHeli 차량)
--
--  MP 동기화 구조 (PZ-Library Java 검증 완료):
--   ① 서버: addVehicleDebug 스폰 -> authorizationChanged(player)로
--      대상 클라에 Local 권한 부여. serverUpdate가 연결별 상태
--      비교로 감지해 VehicleAuthorizationPacket을 자동 브로드캐스트한다.
--   ② 파일럿 클라: hasAuthorization=true -> 매 틱 이 파일이 경로 보간 좌표로
--      텔레포트 -> 엔진이 150ms 간격 sendPhysic(패킷9) 스트림 -> 서버 릴레이.
--   ③ 타 클라: VehicleInterpolation 버퍼로 보간 수신.
--   ④ 1초 무변동 자동 회수(WorldSimulation.java:140)는 LocalCollide 전용이라
--      Local 권한은 애초에 대상이 아니고, 비행 중엔 어차피 매 틱 변한다.
--   ⑤ 종료: 서버 permanentlyRemove() -> 제거 패킷(8) 브로드캐스트.
--
--  경로/타이밍은 HeliStart의 (ax,ay)->(bx,by) + elapsed/total을 로컬 시계로
--  보간한다. 급선회(중첩 후원) 시 서버가 새 경로로 HeliStart를 다시 보내면
--  해당 인스턴스의 경로 교체 + yaw 재설정으로 즉시 새 직선을 탄다.
-- ═══════════════════════════════════════════════════════════════════════════

local HELI_FLY_ALT = 8.0   -- 물리 y 고도. iso 층수 환산 = y/2.46 (BaseVehicle.java:1456),
                           -- 8.0 ≈ 3.25층. 초기값 3.0(BH 조종 상한)은 1.2층이라 너무 낮았다.
local HELI_YAW_OFF = 0     -- fbx 전방축 보정(도). 기수 방향이 틀어져 보이면 여기로 교정.

local function heliPathPos(h)
    if not h or not h.total then return nil end
    local t = (getTimestampMs() - h.t0) / h.total
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    return h.ax + (h.bx - h.ax) * t, h.ay + (h.by - h.ay) * t, h.oz
end

-- VehicleID 는 서버에서 재활용된다(VehicleIDMap.remove -> freeID 스택 ->
-- allocateID 가 LIFO 로 pop). 텔포 등으로 헬기 청크가 언로드되면 그 ID 가
-- 곧바로 다른 바닐라 차량에 넘어가고, vid 로 그 차가 잡히면 파일럿 틱이
-- 남의 차를 비행경로로 끌고 간다. 스크립트명으로 반드시 걸러낸다.
local function findHeliVehicle(h)
    if not h or not h.vid then return nil end
    local ok, v = pcall(function() return getVehicleById(h.vid) end)
    if not ok or not v then return nil end
    local okS, sn = pcall(function() return v:getScriptName() end)
    if okS and sn == "Base.PongDuHeli" then return v end
    return nil
end

-- 현재 헬기 좌표: 실차량 우선(화면과 정확히 일치), 스트리밍 전엔 경로 보간 폴백.
local function heliCurPos(h)
    local v = findHeliVehicle(h)
    if v then return v:getX(), v:getY(), v:getZ() end
    return heliPathPos(h)
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
local function heliSetYaw(h, v)
    local dx, dy = h.bx - h.ax, h.by - h.ay
    if dx == 0 and dy == 0 then return end
    local yaw = math.deg(math.atan2(dx, dy)) + HELI_YAW_OFF
    h.yaw = yaw
    local ok, err = pcall(function() v:setAngles(0, yaw, 0) end)
    if ok then
        print(string.format("[PongDu] fire_support/heli: yaw set %.1f deg own=%s",
            yaw, tostring(h.own)))
    else
        print("[PongDu] fire_support/heli: yaw set FAILED own=" .. tostring(h.own)
            .. " err=" .. tostring(err))
    end
end

-- 파일럿 틱: 경로 보간 좌표로 텔레포트. 권한 클라에서만 호출된다.
local function heliPilotTick(h)
    local v = findHeliVehicle(h)
    if not v then
        if not h.warned then
            h.warned = true
            print("[PongDu] fire_support/heli: pilot tick but vehicle not streamed yet own="
                .. tostring(h.own) .. " vid=" .. tostring(h.vid))
        end
        return
    end
    h.warned = false
    local wx, wy = heliPathPos(h)
    if not wx then return end
    if not h.yawSet then
        h.yawSet = true
        heliSetYaw(h, v)
    end
    local ok, err = pcall(function() heliMoveTo(v, wx, wy) end)
    if not ok and not h.moveErr then
        h.moveErr = true
        print("[PongDu] fire_support/heli: move FAILED own=" .. tostring(h.own)
            .. " err=" .. tostring(err))
    end
end

-- 그림자 좌표 갱신 강제: BaseVehicle.polyDirty가 서야 initShadowPoly()가
-- shadowCoord를 재계산하는데, 이 플래그는 setAngles()(실제 각도가 바뀔 때)
-- 에만 자동으로 서고 위치 갱신(setWorldTransform, 인터폴레이션의 setX/setY)은
-- 건드리지 않는다. public 필드 직접 대입(v.polyDirty = true)은 Kahlua가
-- 테이블에만 허용해서 "attempted index of non-table"이라는 순수 자바
-- RuntimeException을 던진다 -- Lua pcall이 못 잡는 종류다. 그래서 검증된
-- 유일한 트리거인 setAngles()를 매 틱 호출하되, 진짜로 각도가 "변해야"
-- 플래그가 서므로(정수 절삭 비교) yaw를 매 틱 ±0.6도씩 흔든다.
local function heliShadowRefreshTick(h, v)
    if not h.yaw then return end
    h.yawWobbleUp = not h.yawWobbleUp
    local yaw = h.yaw + (h.yawWobbleUp and 0.6 or -0.6)
    pcall(function() v:setAngles(0, yaw, 0) end)
end

-- 블레이드 회전: 전 클라 공통, 매 틱 모델 순환 스왑 (BH rotateBlades 로직).
-- 엔진 시동 여부와 무관하게 무조건 돌린다. 첫 틱엔 Init이 켜둔 랜덤 블레이드가
-- 남지 않게 전체를 한 번 숨긴다.
local function heliBladeTick(h)
    local v = findHeliVehicle(h)
    if not v then return end
    heliShadowRefreshTick(h, v)
    local part = v:getPartById("heliblade")
    local ps   = v:getPartById("helibladeSmall")
    if not h.bladeInit then
        h.bladeInit = true
        if part then
            for i = 1, 8 do part:setModelVisible("blade" .. i, false) end
        end
        if ps then
            for i = 1, 4 do ps:setModelVisible("blade" .. i .. "Small", false) end
        end
    end
    h.bladeStep = (h.bladeStep or 0) + 1
    if h.bladeStep > 8 then h.bladeStep = 1 end
    if part then
        local prev = h.bladeStep - 1
        if prev < 1 then prev = 8 end
        part:setModelVisible("blade" .. prev, false)
        part:setModelVisible("blade" .. h.bladeStep, true)
    end
    if ps then
        local s  = ((h.bladeStep - 1) % 4) + 1
        local sp = s - 1
        if sp < 1 then sp = 4 end
        ps:setModelVisible("blade" .. sp .. "Small", false)
        ps:setModelVisible("blade" .. s .. "Small", true)
    end
    -- BH rotateBlades와 동일하게 스왑 직후 update()로 모델 상태 반영을 강제.
    pcall(function() v:update() end)
end

-- ── 공유 사운드 (가장 가까운 기체 기준) ────────────────────────────────────
-- 루프 사운드라도 emitter:setVolume(handle, v)로 실시간 볼륨 조절이 가능하다
-- (Sound.volume에 저장되고 FileSound.tick이 매 틱 volume * clip볼륨으로 반영 --
--  VehicleDropCraftSound.lua가 이미 쓰는 검증된 경로).
local function heliSoundStopAll(reason)
    if _heliSound then
        loopSoundStop(_heliEmitter, _heliSound, "pongdu_heli")
        print("[PongDu] fire_support/heli: rotor sound stopped (" .. tostring(reason) .. ")")
    end
    if _lmgSound then
        loopSoundStop(_lmgEmitter, _lmgSound, "pongdu_heli_lmg")
        print("[PongDu] fire_support/heli: LMG loop stopped (" .. tostring(reason) .. ")")
    end
    _heliSound, _heliEmitter = nil, nil
    _lmgSound,  _lmgEmitter  = nil, nil
end

local function heliRotorEnsure()
    if _heliSound then return end
    -- 원거리 볼륨으로 시작. 이후 매 틱 거리 기반 갱신.
    local handle, em = loopSoundStart("pongdu_heli", HELI_VOL_FAR)
    if handle then
        _heliSound, _heliEmitter = handle, em
    else
        print("[PongDu] fire_support/heli: rotor sound start FAILED")
    end
end

local function heliLmgEnsure()
    if _lmgSound then return end
    local handle, em = loopSoundStart("pongdu_heli_lmg", HELI_LMG_VOL_FAR)
    if handle then
        _lmgSound, _lmgEmitter = handle, em
        print("[PongDu] fire_support/heli: LMG loop ENGAGE")
    else
        print("[PongDu] fire_support/heli: LMG loop start FAILED")
    end
end

local function heliLmgStop(reason)
    if not _lmgSound then return end
    loopSoundStop(_lmgEmitter, _lmgSound, "pongdu_heli_lmg")
    _lmgSound, _lmgEmitter = nil, nil
    print("[PongDu] fire_support/heli: LMG loop stopped (" .. tostring(reason) .. ")")
end

-- 매 틱: 로터음 볼륨을 최근접 헬기 기준으로, 기관총 루프는 "교전 중인 헬기가
-- 하나라도 있는가"로 판정한다. 인스턴스마다 루프를 틀면 8중첩이 되므로
-- 각각 1개만 유지하고 볼륨/on-off만 집계로 결정한다.
local function heliSoundTick()
    -- 워치독: 인스턴스가 하나도 없는데 핸들이 살아있으면 무조건 정리한다.
    -- heliRemove 를 거치지 않고 _helis 가 비는 경로(테이블 순회 중 삭제,
    -- 예외로 중단된 정리 등)가 생겨도 여기서 확실히 끊긴다. 아래 "if not best
    -- then return end" 가 바로 그 상태에서 사운드를 손대지 않고 빠져나가므로
    -- 반드시 함수 최상단이어야 한다.
    if (_heliSound or _lmgSound) and tcount(_helis) == 0 then
        heliSoundStopAll("watchdog: no instance")
    end

    local pl = getSpecificPlayer(0)
    if not pl then return end
    local px, py = pl:getX(), pl:getY()

    local best, bestEng = nil, nil
    for _, h in pairs(_helis) do
        local hx, hy = heliCurPos(h)
        if hx then
            local dx, dy = hx - px, hy - py
            local d2 = dx * dx + dy * dy
            if (not best) or d2 < best then best = d2 end
            if h.engaged and ((not bestEng) or d2 < bestEng) then bestEng = d2 end
        end
    end
    if not best then return end

    -- 경로 기하 기준 거리 범위: 머리 위 통과 경로라 최근접 ~0, 최원 = D(r+25)
    local dmax = SandboxVars.PongDu.Heli_Radius + 25
    -- 볼륨도 반드시 "재생한 emitter" 에 걸어야 한다. pl:getEmitter() 를 다시
    -- 조회하면 플레이어 교체 후엔 엉뚱한 emitter 를 만진다.

    if _heliSound and _heliEmitter then
        local k = 1 - math.sqrt(best) / dmax
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        pcall(function()
            _heliEmitter:setVolume(_heliSound, HELI_VOL_FAR + (HELI_VOL_NEAR - HELI_VOL_FAR) * k)
        end)
    end

    if bestEng then
        heliLmgEnsure()
        if _lmgSound and _lmgEmitter then
            local k = 1 - math.sqrt(bestEng) / dmax
            if k < 0 then k = 0 elseif k > 1 then k = 1 end
            pcall(function()
                _lmgEmitter:setVolume(_lmgSound,
                    HELI_LMG_VOL_FAR + (HELI_LMG_VOL_NEAR - HELI_LMG_VOL_FAR) * k)
            end)
        end
    else
        heliLmgStop("no engaged heli")
    end
end

-- 인스턴스 제거. 마지막 하나가 빠질 때만 공유 사운드를 끈다.
local function heliRemove(own, reason)
    local h = _helis[own]
    if not h then return end
    _helis[own] = nil
    print("[PongDu] fire_support/heli: instance removed own=" .. tostring(own)
        .. " (" .. tostring(reason) .. ") remaining=" .. tostring(tcount(_helis)))
    if own == myOnlineID() then heliTimerHide() end
    if tcount(_helis) == 0 then heliSoundStopAll(reason) end
end

local function heliRemoveAll(reason)
    -- pairs 순회 중 원본을 지우면 Kahlua 에서 일부 키가 남을 수 있다.
    -- 남으면 tcount(_helis) 가 영영 0 이 안 돼서 이후 어떤 heliRemove 도
    -- 사운드를 끄지 못한다(=영구 잔존). 키를 먼저 모으고 나서 지운다 --
    -- OnTick 의 _expired 버퍼와 같은 패턴.
    local keys, n = {}, 0
    for own in pairs(_helis) do n = n + 1; keys[n] = own end
    for i = 1, n do _helis[keys[i]] = nil end
    heliTimerHide()
    heliSoundStopAll(reason)
end

-- HeliStart 수신: 신규 생성 또는 기존 인스턴스의 경로 교체(급선회/롤오버).
local function heliUpsert(args)
    local own = ownOf(args, "HeliStart")
    if not own then return end

    local h = _helis[own]
    if not h then
        h = { own = own, bladeStep = 0, engaged = false }
        _helis[own] = h
    end

    if args.ax then
        h.ax    = tonumber(args.ax) or 0
        h.ay    = tonumber(args.ay) or 0
        h.bx    = tonumber(args.bx) or 0
        h.by    = tonumber(args.by) or 0
        h.oz    = tonumber(args.oz) or 0
        h.total = tonumber(args.total) or 30000
        h.yawSet = false   -- 새 경로마다 파일럿이 기수 방향 재설정
        -- 로컬 시계 기준 시작점: 이미 elapsed만큼 진행된 상태에서 이어받는다
        -- (급선회로 갈아끼워질 때도 elapsed=0으로 오므로 자동으로 t0=now).
        h.t0 = getTimestampMs() - (tonumber(args.elapsed) or 0)
    end

    -- 실차량 연동: 서버가 스폰한 VehicleID와 물리 권한 대상(pilot).
    -- SP에선 양쪽 onlineID가 모두 -1이라 자동으로 파일럿이 된다.
    if args.vid then h.vid = tonumber(args.vid) end
    local me = myOnlineID()
    h.amPilot = (me ~= nil) and (args.pilot ~= nil)
        and (tonumber(args.pilot) == me)

    -- 유실 대비 자체 데드라인. 서버 HeliStop이 정상 도착하면 그쪽이 먼저 끈다.
    h.stopAt = getTimestampMs() + (tonumber(args.remain) or 30000) + 2000

    print(string.format(
        "[PongDu] fire_support/heli: start own=%s vid=%s pilot=%s amPilot=%s count=%d",
        tostring(own), tostring(h.vid), tostring(args.pilot),
        tostring(h.amPilot), tcount(_helis)))

    heliRotorEnsure()
    if own == me then heliTimerShow(args.remain) end
end

-- ═══════════════════════════════════════════════════════════════════════════
--  드론 실체 (Base.PongDuDrone 차량)
--
--  헬기와 공유하는 것: 서버 addVehicleDebug 스폰 + authorizationChanged
--  물리 권한 위임 + 파일럿 클라의 리플렉션 텔레포트(setWorldTransform).
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
--    즉사한다.
-- ═══════════════════════════════════════════════════════════════════════════

local DRONE_FLY_ALT     = 3.0     -- 물리 y 고도. iso 층 환산 = y/2.46 -> 약 1.2층.
                                  -- 헬기(8.0)보다 낮아야 "근접 호위" 느낌이 산다.
local DRONE_YAW_OFF     = 0       -- fbx 전방축 보정(도)
-- 예광탄 원점 고도(px). 헬기와 같은 환산비(86.7px/unit)를 DRONE_FLY_ALT 에
-- 적용해 실제 기체가 뜬 높이와 일치시킨다.
local DRONE_ALT_PX      = DRONE_FLY_ALT * 86.7
local DRONE_APPROACH_MS = 1000
local DRONE_DEPART_MS   = 1000
local DRONE_DEPART_DIST = 60      -- 이탈 비행 거리(타일). 1초에 이만큼 = 화면 밖
local DRONE_TWO_PI      = 6.2831853

-- 거리 기반 볼륨 램프. 헬기와 같은 원리지만 거리 프로파일이 다르다:
-- 접근(58->4타일) 페이드인 -> 공전(4타일 고정) 최대 -> 이탈(4->64타일) 페이드아웃.
local DRONE_VOL_NEAR    = 0.25
local DRONE_VOL_FAR     = 0.0333
-- 사격음(SMG). 헬기 LMG 와 동일하게 발당 트리거가 아니라 교전 구간 루프.
local DRONE_SMG_VOL_NEAR = 0.3
local DRONE_SMG_VOL_FAR  = 0.075

-- 헬기와 동일하게 핸들 + emitter 쌍으로 보관한다 (loopSoundStart 주석 참조).
local _droneSound,    _droneEmitter    = nil, nil   -- 모터음 (전체 공유 1개)
local _droneSmgSound, _droneSmgEmitter = nil, nil   -- 사격음 (전체 공유 1개)

-- ── 드론 남은시간 패널 (내 화력지원 전용, 헬기와 동형) ─────────────────────
local _droneEndAt = nil
local _dronePanel = nil

local DroneTimerDisplay = ISPanel:derive("DroneTimerDisplay")

function DroneTimerDisplay:new()
    local w = getCore():getScreenWidth()
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
    local col = colorMap.get("fire_support")
    textOutline.drawCentre(self, getText("IGUI_donation_fire_support_drone_timer")
        .. " " .. string.format("%02d:%02d",
            math.floor(totalSec / 60), totalSec % 60),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
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

local function droneTimerHide()
    _droneEndAt = nil
end

-- 공전 중심 = 대상 플레이어의 현재 좌표. 대상이 스트리밍 밖이면 nil.
local function droneCenter(d)
    if not d.target then return nil end
    local p = getSpecificPlayer(0)
    if p and p:getUsername() == d.target then return p:getX(), p:getY() end
    local ps = getOnlinePlayers()
    if ps then
        for i = 0, ps:size() - 1 do
            local o = ps:get(i)
            if o and o:getUsername() == d.target then return o:getX(), o:getY() end
        end
    end
    return nil
end

-- 공전 위치(서버엔 사본이 없다 -- 사격이 클라 권한이라 서버는 위치를 안 쓴다).
-- 파일럿 클라(실차량 이동)와 사격 클라(ORBIT 판정)가 같이 쓴다. theta 증가 = 화면상 시계방향(IsoUtils.XToScreen ∝ x-y,
-- YToScreen ∝ x+y 로 4방위 검산 완료).
local function droneComputePos(d)
    if not d then return nil end
    local cx, cy = droneCenter(d)
    if not cx then return nil end

    local el = getTimestampMs() - d.t0
    if el < 0 then el = 0 end

    if el < DRONE_APPROACH_MS then
        local t  = el / DRONE_APPROACH_MS
        local ex = cx + math.cos(d.th0) * d.orbitR
        local ey = cy + math.sin(d.th0) * d.orbitR
        return d.sx + (ex - d.sx) * t,
               d.sy + (ey - d.sy) * t, d.oz, "APPROACH"
    end

    local oel = el - DRONE_APPROACH_MS
    if oel < d.orbitMs then
        local th = d.th0 + (oel / d.periodMs) * DRONE_TWO_PI
        return cx + math.cos(th) * d.orbitR,
               cy + math.sin(th) * d.orbitR, d.oz, "ORBIT", th
    end

    -- 이탈: 궤도 종료 지점에서 접선 방향(시계방향이므로 -sin, cos)으로 직진.
    local t = (oel - d.orbitMs) / DRONE_DEPART_MS
    if t > 1 then t = 1 end
    local thE = d.th0 + (d.orbitMs / d.periodMs) * DRONE_TWO_PI
    local ex  = cx + math.cos(thE) * d.orbitR
    local ey  = cy + math.sin(thE) * d.orbitR
    return ex - math.sin(thE) * DRONE_DEPART_DIST * t,
           ey + math.cos(thE) * DRONE_DEPART_DIST * t, d.oz, "DEPART", thE
end

-- 헬기 findHeliVehicle 과 동일한 ID 재활용 가드. 실측으로 vid=255 가
-- Base.PongDuDrone -> Base.Van 으로 25초 만에 넘어가 그 밴이 공전 궤도에
-- 실려 떠다니는 사고가 확인됐다.
local function findDroneVehicle(d)
    if not d or not d.vid then return nil end
    local ok, v = pcall(function() return getVehicleById(d.vid) end)
    if not ok or not v then return nil end
    local okS, sn = pcall(function() return v:getScriptName() end)
    if okS and sn == "Base.PongDuDrone" then return v end
    return nil
end

-- 현재 드론 좌표: 실차량 우선, 스트리밍 전엔 계산 좌표 폴백(헬기와 동일).
local function droneCurPos(d)
    local v = findDroneVehicle(d)
    if v then return v:getX(), v:getY(), v:getZ() end
    return droneComputePos(d)
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
local function droneSetYaw(d, v, phase, th, wx, wy)
    local yaw
    if phase == "ORBIT" and th then
        -- 접선 방향 (-sin, cos)를 진행방향으로 넣는다.
        yaw = math.deg(math.atan2(-math.sin(th), math.cos(th))) + DRONE_YAW_OFF
    else
        local dx, dy = wx - v:getX(), wy - v:getY()
        if dx == 0 and dy == 0 then return end
        d.yawWobble = not d.yawWobble
        yaw = math.deg(math.atan2(dx, dy)) + DRONE_YAW_OFF
            + (d.yawWobble and 0.6 or -0.6)
    end
    pcall(function() v:setAngles(0, yaw, 0) end)
end

-- 파일럿 틱: 계산 좌표로 텔레포트. 권한 클라에서만 호출된다.
local function dronePilotTick(d)
    local v = findDroneVehicle(d)
    if not v then
        if not d.warned then
            d.warned = true
            print("[PongDu] fire_support/drone: pilot tick but vehicle not streamed yet own="
                .. tostring(d.own) .. " vid=" .. tostring(d.vid))
        end
        return
    end
    d.warned = false
    local wx, wy, _, phase, th = droneComputePos(d)
    if not wx then return end
    local ok, err = pcall(function()
        droneMoveTo(v, wx, wy)
        droneSetYaw(d, v, phase, th, wx, wy)
    end)
    if not ok and not d.moveErr then
        d.moveErr = true
        print("[PongDu] fire_support/drone: move FAILED own=" .. tostring(d.own)
            .. " err=" .. tostring(err))
    end
end

-- 블레이드 순환: 전 클라 공통. 파트가 하나뿐이라 헬기(대/소 2파트)보다 단순.
local function droneBladeTick(d)
    local v = findDroneVehicle(d)
    if not v then return end
    local part = v:getPartById("droneblade")
    if not part then return end

    if not d.bladeInit then
        d.bladeInit = true
        for i = 1, 8 do part:setModelVisible("blade" .. i, false) end
    end

    d.bladeStep = (d.bladeStep or 0) + 1
    if d.bladeStep > 8 then d.bladeStep = 1 end
    local prev = d.bladeStep - 1
    if prev < 1 then prev = 8 end
    part:setModelVisible("blade" .. prev, false)
    part:setModelVisible("blade" .. d.bladeStep, true)
    -- 헬기 heliBladeTick 과 동일하게 update() 로 모델 상태 반영을 강제한다.
    -- 이게 없으면 BaseVehicle.updateTransform() 이 안 돌아 파트의
    -- renderTransform 이 직전 프레임 변환에 고정된다.
    pcall(function() v:update() end)
end

-- ── 공유 사운드 (헬기와 동형) ──────────────────────────────────────────────
local function droneSoundStopAll(reason)
    if _droneSound then
        loopSoundStop(_droneEmitter, _droneSound, "pongdu_drone")
        print("[PongDu] fire_support/drone: motor sound stopped (" .. tostring(reason) .. ")")
    end
    if _droneSmgSound then
        loopSoundStop(_droneSmgEmitter, _droneSmgSound, "pongdu_drone_smg")
        print("[PongDu] fire_support/drone: SMG loop stopped (" .. tostring(reason) .. ")")
    end
    _droneSound,    _droneEmitter    = nil, nil
    _droneSmgSound, _droneSmgEmitter = nil, nil
end

local function droneMotorEnsure()
    if _droneSound then return end
    local handle, em = loopSoundStart("pongdu_drone", DRONE_VOL_FAR)
    if handle then
        _droneSound, _droneEmitter = handle, em
    else
        print("[PongDu] fire_support/drone: motor sound start FAILED")
    end
end

local function droneSmgEnsure()
    if _droneSmgSound then return end
    local handle, em = loopSoundStart("pongdu_drone_smg", DRONE_SMG_VOL_FAR)
    if handle then
        _droneSmgSound, _droneSmgEmitter = handle, em
        print("[PongDu] fire_support/drone: SMG loop ENGAGE")
    else
        print("[PongDu] fire_support/drone: SMG loop start FAILED")
    end
end

local function droneSmgStop(reason)
    if not _droneSmgSound then return end
    loopSoundStop(_droneSmgEmitter, _droneSmgSound, "pongdu_drone_smg")
    _droneSmgSound, _droneSmgEmitter = nil, nil
    print("[PongDu] fire_support/drone: SMG loop stopped (" .. tostring(reason) .. ")")
end

-- 모터음 거리 볼륨. 헬기와 달리 dmax를 detR+50(스폰 거리)로 잡는다 --
-- 접근 시작점이 정확히 그 거리이므로 페이드인이 0에서 자연스럽게 시작한다.
local function droneSoundTick()
    -- 헬기 heliSoundTick 과 동일한 워치독. 이유는 그쪽 주석 참조.
    if (_droneSound or _droneSmgSound) and tcount(_drones) == 0 then
        droneSoundStopAll("watchdog: no instance")
    end

    local pl = getSpecificPlayer(0)
    if not pl then return end
    local px, py = pl:getX(), pl:getY()

    local best, bestEng = nil, nil
    for _, d in pairs(_drones) do
        local dx, dy = droneCurPos(d)
        if dx then
            local ddx, ddy = dx - px, dy - py
            local d2 = ddx * ddx + ddy * ddy
            if (not best) or d2 < best then best = d2 end
            if d.engaged and ((not bestEng) or d2 < bestEng) then bestEng = d2 end
        end
    end
    if not best then return end

    local dmax = SandboxVars.PongDu.Drone_DetectRadius + 50
    -- 볼륨도 "재생한 emitter" 에 건다 (헬기 heliSoundTick 과 동일한 이유).

    if _droneSound and _droneEmitter then
        local k = 1 - math.sqrt(best) / dmax
        if k < 0 then k = 0 elseif k > 1 then k = 1 end
        pcall(function()
            _droneEmitter:setVolume(_droneSound,
                DRONE_VOL_FAR + (DRONE_VOL_NEAR - DRONE_VOL_FAR) * k)
        end)
    end

    if bestEng then
        droneSmgEnsure()
        if _droneSmgSound and _droneSmgEmitter then
            local k = 1 - math.sqrt(bestEng) / dmax
            if k < 0 then k = 0 elseif k > 1 then k = 1 end
            pcall(function()
                _droneSmgEmitter:setVolume(_droneSmgSound,
                    DRONE_SMG_VOL_FAR + (DRONE_SMG_VOL_NEAR - DRONE_SMG_VOL_FAR) * k)
            end)
        end
    else
        droneSmgStop("no engaged drone")
    end
end

local function droneRemove(own, reason)
    local d = _drones[own]
    if not d then return end
    _drones[own] = nil
    if d.st then
        -- 대상 플레이어 클라의 조준 집계. A/L/N/D = 우선순위 군별 발수,
        -- idle = 대상이 없어 쉰 발. D 비중이 크면 폴백(제압 중 좀비)을 많이 쐈다는 뜻.
        print(string.format(
            "[PongDu] fire_support/drone local summary shots=%d crits=%d kds=%d A=%d L=%d N=%d D=%d idle=%d",
            d.st.shots, d.st.crits, d.st.kds, d.st.A, d.st.L, d.st.N, d.st.D, d.st.idle))
    end
    print("[PongDu] fire_support/drone: instance removed own=" .. tostring(own)
        .. " (" .. tostring(reason) .. ") remaining=" .. tostring(tcount(_drones)))
    if own == myOnlineID() then droneTimerHide() end
    if tcount(_drones) == 0 then droneSoundStopAll(reason) end
end

local function droneRemoveAll(reason)
    -- 헬기 heliRemoveAll 과 동일한 이유로 키를 먼저 모은다.
    local keys, n = {}, 0
    for own in pairs(_drones) do n = n + 1; keys[n] = own end
    for i = 1, n do _drones[keys[i]] = nil end
    droneTimerHide()
    droneSoundStopAll(reason)
end

local function droneUpsert(args)
    local own = ownOf(args, "DroneStart")
    if not own then return end

    local me = myOnlineID()
    local d = {
        own      = own,
        sx       = tonumber(args.sx) or 0,
        sy       = tonumber(args.sy) or 0,
        oz       = tonumber(args.oz) or 0,
        th0      = tonumber(args.th0) or 0,
        orbitR   = tonumber(args.orbitR) or 4,
        orbitMs  = tonumber(args.orbitMs) or 60000,
        periodMs = tonumber(args.periodMs) or 6000,
        t0       = getTimestampMs(),
        vid      = args.vid and tonumber(args.vid) or nil,
        target   = args.target,
        bladeStep = 0,
        engaged  = false,
        -- 사격 파라미터. 대상 플레이어 클라만 쓴다(droneFireTick).
        dr = tonumber(args.dr) or 20,
        iv = tonumber(args.iv) or 25,
        kc = tonumber(args.kc) or 10,
        kd = tonumber(args.kd) or 80,
    }
    -- SP에선 양쪽 onlineID가 모두 -1이라 자동으로 파일럿이 된다(헬기와 동일).
    d.amPilot = (me ~= nil) and (args.pilot ~= nil)
        and (tonumber(args.pilot) == me)
    -- 유실 대비 자체 데드라인. 서버 DroneStop이 정상 도착하면 그쪽이 먼저 끈다.
    d.stopAt = getTimestampMs() + DRONE_APPROACH_MS + d.orbitMs + DRONE_DEPART_MS + 2000

    _drones[own] = d
    print(string.format(
        "[PongDu] fire_support/drone: start own=%s vid=%s pilot=%s amPilot=%s target=%s count=%d",
        tostring(own), tostring(d.vid), tostring(args.pilot),
        tostring(d.amPilot), tostring(d.target), tcount(_drones)))

    droneMotorEnsure()
    if own == me then droneTimerShow(d.orbitMs) end
end

-- 중첩 후원: 드론을 새로 띄우지 않고 궤도 시간만 늘린다.
local function droneExtend(args)
    local own = ownOf(args, "DroneExtend")
    if not own then return end
    local d = _drones[own]
    if not d then
        print("[PongDu] fire_support/drone: extend for unknown own=" .. tostring(own))
        return
    end
    local addMs = tonumber(args.addMs) or 0
    d.orbitMs = d.orbitMs + addMs
    -- 파라미터는 최신 후원 기준으로 갱신(서버 job 갱신과 동일 정책).
    if args.dr then d.dr = tonumber(args.dr) or d.dr end
    if args.iv then d.iv = tonumber(args.iv) or d.iv end
    if args.kc then d.kc = tonumber(args.kc) or d.kc end
    if args.kd then d.kd = tonumber(args.kd) or d.kd end
    if d.stopAt then d.stopAt = d.stopAt + addMs end
    if own == myOnlineID() and _droneEndAt then _droneEndAt = _droneEndAt + addMs end
    print("[PongDu] fire_support/drone: extended +" .. tostring(addMs)
        .. "ms own=" .. tostring(own))
end

-- ═══════════════════════════════════════════════════════════════════════════
--  발사 재생 (헬기/드론 공용)
--
--  서버 틱은 약 10Hz(실측: 드론 25ms 설정에서 60초 590발)라 한 틱 1발 구조로는
--  100ms 보다 짧은 간격이 불가능했다. 이제 한 패킷에 여러 발(shots 배열)이
--  오고, 각 발의 dt(ms) 만큼 지연 재생해서 연사 간격을 복원한다.
--    헬기: 서버가 틱마다 밀린 발수를 몰아 굴려 보낸다(server.lua HELI_MAX_BURST).
--    드론: 대상 플레이어 클라가 직접 쏘고 약 100ms 마다 묶어 보고한 걸 서버가
--          다른 클라에 중계한다(droneFireTick / server.lua DroneShots).
-- ═══════════════════════════════════════════════════════════════════════════
local HELI_ALT_PX_PER_UNIT = 86.7
local HELI_ALT     = HELI_FLY_ALT * HELI_ALT_PX_PER_UNIT
-- ↑ 헬기 원점 고도(px). 예광탄은 실제 3D 렌더와 무관한 수제 스크린좌표 연출이라
--   물리 y->스크린px 변환식을 알 수 없어, 처음 튜닝된 3.0px<->260px 비율
--   (≈86.7px/unit)로 최소한 "같이 움직이게"만 만든다.

local _fsQueue = {}   -- { at, kind, own, ox, oy, oz, shot }

-- 헬기 1발: 락온 좀비에 명중. crit=1 크리티컬, 0 일반.
local function heliShotPlay(own, ox, oy, oz, sh)
    local id = tonumber(sh.id)
    local tx, ty, tz = tonumber(sh.x) or 0, tonumber(sh.y) or 0, tonumber(sh.z) or 0
    local z = id and findZombieById(id) or nil
    if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end
    -- 실차량(또는 폴백 경로 보간) 좌표를 예광탄 원점으로 쓴다.
    local h = own and _helis[own] or nil
    if h then
        local px2, py2 = heliCurPos(h)
        if px2 then ox, oy = px2, py2 end
    end
    addTracer(ox, oy, oz, tx, ty, tz, HELI_ALT)
    -- 총성은 pongdu_heli_lmg 루프가 교전 내내 재생 중이라 발당 트리거 없음.
    fsApplyShot(z, id, fsShotHp("heli", tonumber(sh.crit) == 1), tonumber(sh.crit) == 1, false, "heli")
end

-- 드론 1발(중계 수신측). 넉다운은 일반탄에만 발사 클라가 굴려 보낸다.
local function droneShotPlay(own, ox, oy, oz, sh)
    local id = tonumber(sh.id)
    local d = own and _drones[own] or nil
    if d then
        local dx2, dy2 = droneCurPos(d)
        if dx2 then ox, oy = dx2, dy2 end
    end
    local z = id and findZombieById(id) or nil
    local tx, ty, tz = tonumber(sh.tx) or 0, tonumber(sh.ty) or 0, tonumber(sh.tz) or 0
    if z then tx, ty, tz = z:getX(), z:getY(), z:getZ() end
    addTracer(ox, oy, oz, tx, ty, tz, DRONE_ALT_PX, TRACER_ALPHA_FAINT)
    if not z or z:isDead() then return end
    local crit = tonumber(sh.crit) == 1
    local kd   = (not crit) and tonumber(sh.kd) == 1
    fsApplyShot(z, id, fsShotHp("drone", crit), crit, kd, "drone")
end

local function fsPlay(kind, own, ox, oy, oz, sh)
    local ok, err = pcall(function()
        if kind == "heli" then heliShotPlay(own, ox, oy, oz, sh)
        else droneShotPlay(own, ox, oy, oz, sh) end
    end)
    if not ok then
        print("[PongDu] fire_support/" .. kind .. " shot play FAILED err=" .. tostring(err))
    end
end

-- shots 배열 수신: dt<=0 은 즉시, 나머지는 큐에 넣어 OnTick 에서 재생.
local function fsReceiveShots(kind, args)
    local own = tonumber(args.own)
    local ox, oy, oz = tonumber(args.ox) or 0, tonumber(args.oy) or 0, tonumber(args.oz) or 0
    local shots = args.shots
    local n = tonumber(args.n) or 0
    if not shots or n <= 0 then
        print("[PongDu] fire_support/" .. kind .. ": fire packet without shots")
        return
    end
    local now = getTimestampMs()
    for i = 1, n do
        local sh = shots[i]
        if sh then
            local dt = tonumber(sh.dt) or 0
            if dt <= 0 then
                fsPlay(kind, own, ox, oy, oz, sh)
            else
                _fsQueue[#_fsQueue + 1] = { at = now + dt, kind = kind, own = own,
                                            ox = ox, oy = oy, oz = oz, shot = sh }
            end
        end
    end
end

local function fsQueueTick(now)
    if #_fsQueue == 0 then return end
    -- 순회 중 삭제 대신 남는 항목으로 새 배열을 만든다(Kahlua 안전).
    local keep = {}
    local q = _fsQueue
    _fsQueue = keep
    for i = 1, #q do
        local e = q[i]
        if now >= e.at then
            fsPlay(e.kind, e.own, e.ox, e.oy, e.oz, e.shot)
        else
            keep[#keep + 1] = e
        end
    end
end

local function handleHeliFire(args)  fsReceiveShots("heli", args)  end
local function handleDroneFire(args) fsReceiveShots("drone", args) end

-- ═══════════════════════════════════════════════════════════════════════════
--  드론 조준/사격 (대상 플레이어 클라 권한)
--
--  [왜 클라인가] 서버가 보는 좀비 위치/realState 는 혼자일 때 최대 4초 늦고
--  isOnFloor() 는 아예 안 온다(server.lua DroneShots 주석). 대상 플레이어 클라는
--  주변 좀비 대부분의 소유자라 위치/상태/사망을 지연 없이 안다.
--
--  [우선순위] 각 군 안에서는 플레이어 최근접.
--    A 공격 판정 중(attack)  >  L 돌진 중(lunge)  >  N 정상(걷기/추적)
--    >  D 제압 중(넘어짐/기상/피격 반응) 또는 방금 쏜 원격 소유 좀비
--  D 는 다른 후보가 없을 때만 쏜다(폴백 -- 현행 정책 유지).
--
--  [상태 읽기]
--    내가 소유한 좀비: getActionStateName() -- 실제 상태머신 현재 상태.
--      + isOnFloor()/isKnockedDown() -- 전환 프레임 사이도 잡는다.
--    다른 클라 소유(원격) 좀비: getRealState() -- 소유 클라 패킷 값.
--      이 경우는 근처에 다른 플레이어가 있다는 뜻이라 주기 200ms.
--      isOnFloor 는 원격 좀비엔 동기화되지 않으므로 쓰지 않는다.
--  [홀드] 내가 쏜 크리티컬/넉다운은 원격 좀비면 중계 왕복 + 상대 패킷
--    동안 결과를 모르니 DRONE_REMOTE_HOLD_MS 동안 D 로 둔다. 로컬 좀비는
--    다음 프레임 상태가 바로 보이지만 전환 1~2프레임 공백을 DRONE_LOCAL_HOLD_MS 로 덮는다.
-- ═══════════════════════════════════════════════════════════════════════════
local DRONE_BATCH_MS       = 100   -- 보고 묶음 주기
local DRONE_MAX_BURST      = 8     -- 한 프레임 최대 발수(히칭 후 폭주 방지)
local DRONE_LOCAL_HOLD_MS  = 150
local DRONE_REMOTE_HOLD_MS = 800

local DRONE_ATTACK_STATES = { ["attack"] = true, ["attack-network"] = true }
local DRONE_LUNGE_STATES  = { ["lunge"] = true, ["lunge-network"] = true }
local DRONE_DOWN_STATES   = {
    ["hitreaction"] = true, ["hitreaction-hit"] = true, ["hitwhilestaggered"] = true,
    ["staggerback"] = true, ["falldown"] = true, ["onground"] = true, ["getup"] = true,
}

local function droneZombieState(z, remote)
    local ok, st
    if remote then
        ok, st = pcall(function() return z:getRealState() end)
    else
        ok, st = pcall(function() return z:getActionStateName() end)
    end
    if ok and st then return tostring(st) end
    return nil
end

-- 반환: 대상 좀비, 우선순위 군("A"|"L"|"N"|"D")
local function dronePickTarget(d, cx, cy, now)
    local cell = getCell()
    local zl = cell and cell:getZombieList()
    if not zl then return nil end
    local dr2 = d.dr * d.dr
    local hold = d.hold
    local bA, dA, bL, dL, bN, dN, bD, dD
    for i = 0, zl:size() - 1 do
        local z = zl:get(i)
        if z and not z:isDead() then
            local dx, dy = z:getX() - cx, z:getY() - cy
            local d2 = dx * dx + dy * dy
            if d2 <= dr2 then
                local remote = z:isRemoteZombie()
                local st = droneZombieState(z, remote)
                local down = (st and DRONE_DOWN_STATES[st]) and true or false
                if not remote and not down then
                    local okF, fl = pcall(function() return z:isOnFloor() or z:isKnockedDown() end)
                    down = okF and fl or false
                end
                local h = hold[z]   -- 객체 키: SP 는 onlineID 가 전부 -1 이라 id 키면 충돌
                if h and now < h then down = true end

                if down then
                    if not dD or d2 < dD then bD, dD = z, d2 end
                elseif st and DRONE_ATTACK_STATES[st] then
                    if not dA or d2 < dA then bA, dA = z, d2 end
                elseif st and DRONE_LUNGE_STATES[st] then
                    if not dL or d2 < dL then bL, dL = z, d2 end
                else
                    if not dN or d2 < dN then bN, dN = z, d2 end
                end
            end
        end
    end
    if bA then return bA, "A" end
    if bL then return bL, "L" end
    if bN then return bN, "N" end
    if bD then return bD, "D" end
    return nil
end

local function droneSetEngaged(d, on)
    if d.engaged == on then return end
    d.engaged = on
    sendClientCommand("PongDuFireSupport", "DroneEngaged", { on = on and 1 or 0 })
end

local function droneFlush(d, ox, oy, now)
    if not d.batchN or d.batchN == 0 then return end
    sendClientCommand("PongDuFireSupport", "DroneShots", {
        ox = ox, oy = oy, shots = d.batch, n = d.batchN,
    })
    d.batch, d.batchN, d.batchAt = {}, 0, nil
    -- 만료 홀드 정리(새 테이블 재구성 -- Kahlua 안전)
    local fresh = {}
    for k, v in pairs(d.hold) do
        if v > now then fresh[k] = v end
    end
    d.hold = fresh
end

-- 대상 플레이어 클라에서만 매 프레임 호출된다(OnTick).
local function droneFireTick(d, now)
    local ox, oy, oz, phase = droneComputePos(d)
    if phase ~= "ORBIT" then
        if ox then droneFlush(d, ox, oy, now) end
        d.nextShotAt = nil
        if phase == "DEPART" then droneSetEngaged(d, false) end
        return
    end
    local vx, vy = droneCurPos(d)
    if vx then ox, oy = vx, vy end
    local cx, cy = droneCenter(d)
    if not cx then return end

    d.hold  = d.hold or {}
    d.batch = d.batch or {}
    d.batchN = d.batchN or 0
    d.st = d.st or { shots = 0, crits = 0, kds = 0, A = 0, L = 0, N = 0, D = 0, idle = 0 }
    if not d.nextShotAt then d.nextShotAt = now end

    local burst = 0
    while now >= d.nextShotAt and burst < DRONE_MAX_BURST do
        local shotT = d.nextShotAt
        d.nextShotAt = d.nextShotAt + d.iv
        burst = burst + 1

        local z, tier = dronePickTarget(d, cx, cy, now)
        if not z then
            d.st.idle = d.st.idle + 1
            d.nextShotAt = now + d.iv
            droneSetEngaged(d, false)
            break
        end
        droneSetEngaged(d, true)

        local crit = ZombRand(100) < d.kc
        local kd   = (not crit) and ZombRand(100) < d.kd
        local id   = z:getOnlineID()
        local remote = z:isRemoteZombie()

        -- 로컬 즉시 적용(서버 왕복 없음). 원격 소유 좀비면 연출만 되고
        -- 데미지는 중계를 받은 소유 클라가 넣는다(fsApplyShot 참조).
        addTracer(ox, oy, oz, z:getX(), z:getY(), z:getZ(), DRONE_ALT_PX, TRACER_ALPHA_FAINT)
        fsApplyShot(z, id, fsShotHp("drone", crit), crit, kd, "drone")

        if crit or kd or remote then
            d.hold[z] = now + (remote and DRONE_REMOTE_HOLD_MS or DRONE_LOCAL_HOLD_MS)
        end

        d.st.shots = d.st.shots + 1
        d.st[tier] = d.st[tier] + 1
        if crit then d.st.crits = d.st.crits + 1 end
        if kd then d.st.kds = d.st.kds + 1 end

        if d.batchN == 0 then d.batchAt = shotT end
        d.batchN = d.batchN + 1
        d.batch[d.batchN] = {
            id = id, tx = z:getX(), ty = z:getY(), tz = z:getZ(),
            crit = crit and 1 or 0, kd = kd and 1 or 0,
            dt = shotT - d.batchAt,
        }
    end
    if burst >= DRONE_MAX_BURST and now - d.nextShotAt > d.iv * DRONE_MAX_BURST then
        -- 긴 히칭 뒤: 밀린 걸 다 쏘지 않고 재동기화.
        d.nextShotAt = now + d.iv
    end
    if d.batchN > 0 and (now - d.batchAt >= DRONE_BATCH_MS) then
        droneFlush(d, ox, oy, now)
    end
end

-- ── 통합 틱 ────────────────────────────────────────────────────────────────
-- 인스턴스별로 파일럿 이동/블레이드를 돌리고, 사운드는 집계로 한 번만 갱신한다.
-- 데드라인 만료 인스턴스는 순회 중 지우지 않고 모아뒀다 뒤에서 제거한다
-- (pairs 순회 도중 삭제는 Kahlua 에서 동작이 보장되지 않는다).
local _expired = {}

Events.OnTick.Add(function()
    fsSweepStaleLoops()
    local now = getTimestampMs()

    local n = 0
    for own, h in pairs(_helis) do
        if h.stopAt and now > h.stopAt then
            n = n + 1
            _expired[n] = own
        else
            if h.amPilot then heliPilotTick(h) end   -- 권한 클라만 실제 이동
            heliBladeTick(h)                         -- 로터 회전은 전 클라 로컬 연출
        end
    end
    for i = 1, n do
        heliRemove(_expired[i], "local deadline")
        _expired[i] = nil
    end
    heliSoundTick()

    -- 드론: 헬기와 독립적으로 동작한다(동시 발동 가능).
    local me = myOnlineID()
    n = 0
    for own, d in pairs(_drones) do
        if d.stopAt and now > d.stopAt then
            n = n + 1
            _expired[n] = own
        else
            if d.amPilot then dronePilotTick(d) end
            droneBladeTick(d)
            -- 사격은 대상 플레이어 클라만(SP 는 양쪽 -1 이라 자동 일치).
            if me ~= nil and own == me then
                local okF, errF = pcall(function() droneFireTick(d, now) end)
                if not okF and not d.fireErr then
                    d.fireErr = true
                    print("[PongDu] fire_support/drone fire tick FAILED err=" .. tostring(errF))
                end
            end
        end
    end
    for i = 1, n do
        droneRemove(_expired[i], "local deadline")
        _expired[i] = nil
    end
    droneSoundTick()

    fsQueueTick(now)
end)

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
        heliUpsert(args)
        return
    elseif command == "HeliStop" then
        local own = ownOf(args, "HeliStop")
        if own then
            heliRemove(own, "server stop")
        else
            print("[PongDu] fire_support/heli: HeliStop without own -- clearing all instances")
            heliRemoveAll("server stop (own missing)")
        end
        return
    elseif command == "HeliEngage" then
        -- 기관총 루프는 OnTick 집계(heliSoundTick)가 켠다. 여기선 플래그만.
        local own = ownOf(args, "HeliEngage")
        local h = own and _helis[own] or nil
        if h then h.engaged = true end
        return
    elseif command == "HeliClear" then
        -- LMG 사운드 전용 -- 실제 사격이 끊겼을 때만 서버가 보낸다.
        -- 무전("구역 정리")은 더 이상 여기서 재생하지 않는다 -- HeliAreaClear로 분리됨.
        -- 남은 시간 동안 헬기(로터음)는 계속 떠 있고, 좀비가 다시 감지되면
        -- 서버가 HeliEngage를 다시 보내 사격을 재개한다.
        local own = ownOf(args, "HeliClear")
        local h = own and _helis[own] or nil
        if h then h.engaged = false end
        return
    elseif command == "HeliAreaClear" then
        -- 무전 전용: 사격/LMG 상태와 무관하게, 확장반경까지 완전히 비었을 때
        -- 서버가 1회 보낸다. 내 헬기일 때만 재생 -- 전 인스턴스가 방송하면
        -- 동시 발동 상황에서 무전이 인원수만큼 겹쳐 들린다.
        local own = ownOf(args, "HeliAreaClear")
        if own and own == myOnlineID() then
            local okS = pcall(function()
                getSoundManager():PlaySound("area_clear", false, 1.0)
            end)
            if not okS then print("[PongDu] fire_support/heli: area_clear sound failed") end
        end
        return
    elseif command == "HeliFire" then
        handleHeliFire(args)
        return
    elseif command == "DroneStart" then
        droneUpsert(args)
        return
    elseif command == "DroneStop" then
        local own = ownOf(args, "DroneStop")
        if own then
            droneRemove(own, "server stop")
        else
            print("[PongDu] fire_support/drone: DroneStop without own -- clearing all instances")
            droneRemoveAll("server stop (own missing)")
        end
        return
    elseif command == "DroneExtend" then
        droneExtend(args)
        return
    elseif command == "DroneEngage" then
        local own = ownOf(args, "DroneEngage")
        local d = own and _drones[own] or nil
        if d then d.engaged = true end
        return
    elseif command == "DroneClear" then
        local own = ownOf(args, "DroneClear")
        local d = own and _drones[own] or nil
        if d then d.engaged = false end
        return
    elseif command == "DroneFire" then
        handleDroneFire(args)
        return
    elseif command == "SniperStart" then
        local own = ownOf(args, "SniperStart")
        if own == myOnlineID() then sniperTimerShow(args.remain) end
        return
    elseif command == "SniperStop" then
        local own = ownOf(args, "SniperStop")
        if own == myOnlineID() then sniperTimerHide() end
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

-- c(): 내 화력 지원이 지금 진행 중인가. [public name: .c]
-- rewardManager의 random_teleport 락 판정에 쓴다. 랜텔로 좌표가 튀면 헬기/드론은
-- 서버 isOwnerTeleported 가 job 을 즉시 종료시켜 후원이 통째로 날아가고, 저격도
-- 원점이 고정이라 예광탄이 화면을 가로지르는 선으로 남는다. 그래서 지속시간
-- 동안엔 랜텔을 큐박스 슬롯에 잠가둔다.
--
-- 세 타이머는 전부 own == myOnlineID() 게이트를 통과한 값만 세팅되므로
-- (SniperStart/HeliStart/DroneStart 수신부), 다른 플레이어가 받은 화력 지원은
-- 여기 걸리지 않는다.
function _a.c()
    local now = getTimestampMs()
    if _sniperEndAt and _sniperEndAt > now then return true end
    if _heliEndAt   and _heliEndAt   > now then return true end
    if _droneEndAt  and _droneEndAt  > now then return true end
    return false
end

-- b(): 진행 중인 화력 지원 연출을 전부 정리한다 (예광탄).
-- 사격 타이밍/잔여 발수는 이제 서버 job이 들고 있으므로 클라에서 정리할
-- 큐가 없다. 플레이어 사망/접속 종료 시 호출할 것. [public name: .b]
function _a.b()
    _tracers = {}
    heliRemoveAll("cleanup")
    droneRemoveAll("cleanup")
    sniperTimerHide()
end

-- ═══════════════════════════════════════════════════════════════════════════
--  플레이어 생명주기 훅
--
--  루프 사운드는 "재생한 emitter" 에 묶여 있는데, IsoGameCharacter.emitter 는
--  final 이라 플레이어 객체가 교체되면 그 emitter 도 같이 버려진다
--  (loopSoundStart 주석 참조). 사망/리스폰/접속종료 시점을 직접 잡아서
--  버려지기 "전에" 정리하고, 필요하면 새 emitter 에 다시 건다.
--
--  ※ _a.b() 는 외부에서 호출되지 않고 있었다. 정리 책임을 이 모듈 안으로
--    가져오는 게 이 훅들의 목적이다.
-- ═══════════════════════════════════════════════════════════════════════════

-- 사망: 아직 옛 emitter 가 유효한 시점이라 여기서 끊어야 확실히 멈춘다.
-- 인스턴스(_helis/_drones)는 지우지 않는다 -- 남의 화력지원이 진행 중일 수
-- 있고, 그건 리스폰 후에도 계속 보여야 한다. 리스폰 시 새 emitter 로 다시 건다.
Events.OnPlayerDeath.Add(function(player)
    if not player or player ~= getSpecificPlayer(0) then return end
    heliSoundStopAll("player death")
    droneSoundStopAll("player death")
end)

-- 리스폰/접속: 새 IsoPlayer = 새 emitter. 사망 이벤트를 놓친 경로(강제 종료,
-- 사망 처리 순서 등)를 대비해 한 번 더 정리한 뒤, 아직 살아있는 인스턴스가
-- 있으면 새 emitter 에 루프를 다시 건다. 기관총/SMG 루프는 교전 상태를 보고
-- OnTick 집계(heliSoundTick/droneSoundTick)가 알아서 다시 켜므로 손대지 않는다.
Events.OnCreatePlayer.Add(function(index, player)
    if index ~= 0 then return end
    heliSoundStopAll("player recreated")
    droneSoundStopAll("player recreated")
    if tcount(_helis)  > 0 then heliRotorEnsure()  end
    if tcount(_drones) > 0 then droneMotorEnsure() end
end)

-- 접속 종료: 세션이 끝났으므로 인스턴스까지 통째로 비운다. 이게 없으면
-- 재접속 시(게임 재시작 없이) 옛 인스턴스가 engaged=true 로 남아 있어
-- heliSoundTick 이 다음 틱에 곧바로 기관총 루프를 다시 켠다.
Events.OnDisconnect.Add(function()
    _a.b()
end)

return _a
