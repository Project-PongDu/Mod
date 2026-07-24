local _a = {}

local global = require("global")

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
-- 옵션 없음(구 세이브) = 허용. 4종 전부 해제면 저격으로 폴백.
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
    local sv = SandboxVars and SandboxVars.PongDu
    local pool = {}
    for _, k in ipairs(KINDS) do
        if not (sv and sv[KIND_OPTION[k]] == false) then
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
-- 따라서 nil 이라는 건 sandbox-options.txt 등록 실패(오타/파싱 에러)뿐이고,
-- 그 상황에서 조용히 매직넘버로 굴러가면 샌박을 아무리 돌려도 안 먹는데
-- 로그가 안 남는다. 아래 비상값은 "후원이 통째로 먹통이 되지 않게" 하는
-- 최후 방어일 뿐 기본값이 아니므로, 탈 때마다 반드시 로그를 남긴다.
-- (기존 코드는 여기에 or 700 이 박혀 있었고 샌박 5000 과 조용히 어긋나 있었다.)
local _optWarned = {}

local function svInt(name, emergency)
    local sv = SandboxVars and SandboxVars.PongDu
    local v  = sv and tonumber(sv[name])
    if v then return v end
    if not _optWarned[name] then
        _optWarned[name] = true
        print("[PongDu] SANDBOX OPTION MISSING: PongDu." .. tostring(name)
            .. " -- check sandbox-options.txt registration, falling back to "
            .. tostring(emergency))
    end
    return emergency
end

-- 저격 파라미터: Sniper_Radius / Sniper_Count / Sniper_Interval(ms).
local function sniperCfg()
    return svInt("Sniper_Radius", 30),
           svInt("Sniper_Count", 10),
           svInt("Sniper_Interval", 3000)
end

-- 헬기 파라미터: Heli_Duration(s) / Heli_Radius / Heli_Interval(ms) / Heli_KillChance(%).
local function heliCfg()
    return svInt("Heli_Duration", 30),
           svInt("Heli_Radius", 30),
           svInt("Heli_Interval", 100),
           svInt("Heli_KillChance", 10)
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
    local radius, count, interval = sniperCfg()
    print(string.format("[PongDu] fire_support/sniper request r=%d n=%d interval=%d",
        radius, count, interval))
    sendClientCommand("PongDuFireSupport", "Sniper", {
        r = radius, n = count, iv = interval, sender = sender or "",
    })
end

-- 드론: 지속(짧음). interval 마다 소수 처치. 모터음 루프.
runners.drone = function(player, sender)
    print("[PongDu] fire_support/drone: not implemented yet")
    -- TODO: 지속형 틱 루프 + 루프 사운드 핸들 관리
end

-- 헬기: 지속(김). 랜덤 지점 A -> B 로 이동하며 플레이어 반경 내 좀비를
-- 무차별 소사. 저격과 달리 발당 킬 확률(기본 5%)이 낮은 대신 연사가 빠르다.
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

local _tracers = {}

-- oalt: 원점 고도(px). 생략 시 저격수 고도(ORIGIN_ALT). 헬기는 더 높은 값을 준다.
local function addTracer(ox, oy, oz, tx, ty, tz, oalt)
    _tracers[#_tracers + 1] = {
        ox = ox, oy = oy, oz = oz,
        tx = tx, ty = ty, tz = tz,
        t = 0, hit = 0, oalt = oalt,
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
            -- 두께: 히트맨 예광탄과 동일하게 단선 1줄로 되돌림(±1px 오프셋
            -- 외곽 2줄 제거). 알파(0.90)/색만 그대로 유지 -- 히트맨의 0.14보다
            -- 훨씬 밝게 보이는 건 의도한 그대로다.
            renderer:renderline(TRACER_TEX, x1, y1, x2, y2, 1, 1, 0.90, 0.90)
            -- 총구 화염: 처음 두 프레임만 원점에 짧고 밝게
            if tr.t < TRACER_STEP * 2 then
                local fx = math.floor(sx + (ex - sx) * 0.03)
                local fy = math.floor(sy + (ey - sy) * 0.03)
                renderer:renderline(TRACER_TEX, math.floor(sx), math.floor(sy), fx, fy,
                    1, 0.92, 0.55, 0.95)
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
-- 헬기 위치는 그림자 보간 좌표(heliShadowPos)를 매 발마다 다시 읽어서
-- 플레이어와의 거리를 재고, 볼륨을 갱신하면 "멀리서 접근 -> 최근접(머리 위
-- 통과) -> 멀어짐" 연출이 된다. 경로가 플레이어 중심 원 위 A -> 반대편 B라
-- 최근접은 ~0(머리 위 스침), 최원은 A/B 지점의 D(플레이어 기준 반경)다.
local HELI_VOL_NEAR     = 1.00   -- 최근접 시 로터음 볼륨
local HELI_VOL_FAR      = 0.20   -- 최원거리 시 로터음 볼륨
local HELI_LMG_VOL_NEAR = 0.85   -- 기관총음은 로터음보다 살짝 낮게
local HELI_LMG_VOL_FAR  = 0.15

local function heliUpdateVolume(hx, hy)
    if not _heliSound and not _lmgSound then return end
    local pl = getSpecificPlayer(0)
    if not pl then return end

    -- 경로 기하 기준 거리 범위: 머리 위 통과 경로라 최근접 ~0, 최원 = D(r+25)
    local dmin, dmax = 0, svInt("Heli_Radius", 30) + 25
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
--  헬기 그림자 (바닐라 renderShadow 재사용)
--
--  IsoDeadBody.renderShadow(x, y, z, forward, w, fm, bm, lightInfo, alpha)는
--  public static이고 (IsoDeadBody.java:780) 캐릭터/시체/마네킹이 전부 이걸로
--  바닐라 드랍섀도(media/textures/NewShadow.png)를 그린다. 임의 좌표 + 방향
--  벡터로 호출 가능하며, 내부에서 렌더 파이프라인의 현재 위치에 renderPoly로
--  enqueue하므로 OnPostFloorLayerDraw(바닥+엔진 그림자 직후, 그 층의 벽/캐릭터
--  전 -- IsoCell.java:910)에서 부르면 "바닥 위, 개체 아래"에 정확히 깔린다.
--  줌/카메라 변환도 내부 IsoUtils.XToScreenExact가 처리해서 수동 변환이 없다.
--
--  인자: forward = 진행 방향(그림자가 비행 방향으로 길게 눕는다),
--        w = 반폭, fm/bm = 전/후 길이(타일). lightInfo의 rgb 평균이 곱해져
--        어두운 곳에선 그림자도 옅어진다(엔진 특성 그대로).
--  필요 타입 3종(IsoDeadBody/Vector3f/ColorInfo) 모두 Lua 노출 확인,
--  Vector3f는 org.joml이라 renderShadow 시그니처와 동일 타입이다.
--
--  위치는 HeliStart가 준 경로(ax,ay -> bx,by)와 진행률(elapsed/total)을 받아
--  로컬 시계 기준으로 매 프레임 보간한다 -- HeliFire(발사 간격) 주기보다 훨씬
--  부드럽다. 연장(급선회) 시 서버가 갱신된 경로/진행률로 HeliStart를 다시
--  보내면 _heliPath를 통째로 갈아끼워서 즉시 새 직선으로 전환된다.
-- ═══════════════════════════════════════════════════════════════════════════

local SHADOW_W     = 1.6      -- 그림자 반폭 (타일)
local SHADOW_LEN   = 2.4      -- 전/후 길이 (타일) -- 진행 방향으로 눕는 장축
local SHADOW_ALPHA = 0.85     -- 엔진이 광량 평균 * 0.66을 추가로 곱한다

local _heliPath   = nil   -- { ax, ay, bx, by, oz, t0(로컬 시작 시각), total }
local _shadowFwd  = Vector3f.new()          -- 매 프레임 할당 방지용 캐시
local _shadowLite = ColorInfo.new(1, 1, 1, 1)

local function heliShadowPos()
    if not _heliPath then return nil end
    local t = (getTimestampMs() - _heliPath.t0) / _heliPath.total
    if t < 0 then t = 0 elseif t > 1 then t = 1 end
    local x = _heliPath.ax + (_heliPath.bx - _heliPath.ax) * t
    local y = _heliPath.ay + (_heliPath.by - _heliPath.ay) * t
    return x, y, _heliPath.oz
end

Events.OnPostFloorLayerDraw.Add(function(z)
    if not _heliPath then return end
    if isServer() then return end
    if not isIngameState() then return end

    local pl = getSpecificPlayer(0)
    if not pl then return end
    -- 플레이어가 있는 층에만 그림: 다른 층 루프에서 중복으로 찍히는 것 방지
    if z ~= math.floor(pl:getZ()) then return end

    local hx, hy, hz = heliShadowPos()
    if not hx then return end

    -- 그림자 장축 = 비행 방향. 경로 길이 0 가드(정규화 NaN 방지).
    local dx, dy = _heliPath.bx - _heliPath.ax, _heliPath.by - _heliPath.ay
    if dx == 0 and dy == 0 then dx = 1 end
    _shadowFwd:set(dx, dy, 0)

    -- 헬기 그림자 위치의 광량 반영: 어두우면 그림자도 옅게 (캐릭터와 동일 거동)
    local sq = getCell():getGridSquare(math.floor(hx), math.floor(hy), math.floor(hz))
    local ll = 1.0
    if sq then
        local ok, v = pcall(function() return sq:getLightLevel(0) end)
        if ok and v then ll = v end
    end
    _shadowLite:set(ll, ll, ll, 1)

    local ok, err = pcall(function()
        IsoDeadBody.renderShadow(hx, hy, hz, _shadowFwd,
            SHADOW_W, SHADOW_LEN, SHADOW_LEN, _shadowLite, SHADOW_ALPHA)
    end)
    if not ok and not _heliPath.shadowErr then
        _heliPath.shadowErr = true
        print("[PongDu] fire_support/heli: shadow render FAILED err=" .. tostring(err))
    end
end)

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

Events.OnTick.Add(function()
    if _heliStopAt and getTimestampMs() > _heliStopAt then
        heliSoundStop("local deadline")
    end
end)

-- ── 헬기 남은시간 표시 패널 (RainTimerDisplay/BombardTimerDisplay와 동일 스타일) ──
-- 레인(h-180), 폭격(h-150)과 동시 표시될 수 있으므로 30px 위(h-210)에 배치.
-- 남은시간은 HeliStart의 remain(ms)으로 로컬 데드라인을 잡아 계산한다.
local _heliPanel   = nil

local HeliTimerDisplay = ISPanel:derive("HeliTimerDisplay")

function HeliTimerDisplay:new()
    local w = getCore():getScreenWidth()
    local h = getCore():getScreenHeight()
    local o = ISPanel:new(w / 2 - 110, h - 210, 220, 25)
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
        self.width / 2, 0, 0.65, 0.85, 0.65, 1, UIFont.Small)
end

function HeliTimerDisplay:update()
    if not _heliEndAt or _heliEndAt - getTimestampMs() <= 0 then
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
    end
end

-- 헬기 사격 1발 처리. 저격과 달리 "적당히 탄이 튀는" 난사 연출:
--   kill=true  -> 좀비 정조준(실명중). 소유 클라가 킬 수행.
--   kill 없음  -> 좀비 근처 ±2타일 산탄 오프셋으로 빗나가는 탄만 그린다.
--   id 없음    -> 반경 내 좀비가 없어 지면 난사(서버가 랜덤 지점 좌표를 보냄).
local HELI_ALT     = 260     -- 헬기 원점 고도(px). 저격수(95)보다 훨씬 높게.
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

    -- 클라 보간 그림자 위치가 있으면 그걸 예광탄 원점으로 쓴다 -- 서버 발사
    -- 시점 좌표(ox,oy)보다 화면의 그림자와 정확히 일치한다.
    local px2, py2 = heliShadowPos()
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
    if not args then return end

    if command == "HeliStart" then
        if args.ax then
            _heliPath = {
                ax = tonumber(args.ax) or 0, ay = tonumber(args.ay) or 0,
                bx = tonumber(args.bx) or 0, by = tonumber(args.by) or 0,
                oz = tonumber(args.oz) or 0,
                total = tonumber(args.total) or 30000,
            }
            -- 로컬 시계 기준 시작점: 이미 elapsed만큼 진행된 상태에서 이어받는다
            -- (급선회로 갈아끼워질 때도 elapsed=0으로 오므로 자동으로 t0=now).
            _heliPath.t0 = getTimestampMs() - (tonumber(args.elapsed) or 0)
        end
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
end)

-- b(): 진행 중인 화력 지원 연출을 전부 정리한다 (예광탄).
-- 사격 타이밍/잔여 발수는 이제 서버 job이 들고 있으므로 클라에서 정리할
-- 큐가 없다. 플레이어 사망/접속 종료 시 호출할 것. [public name: .b]
function _a.b()
    _tracers = {}
    heliSoundStop("cleanup")
end

return _a
