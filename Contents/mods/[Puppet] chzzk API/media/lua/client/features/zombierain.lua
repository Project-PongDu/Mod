local _a = {}
require("ISUI/ISPanel")
local timerStack = require("utils/timerStack")
local colorMap = require("utils/colorMap")
local textOutline = require("utils/textOutline")
local fx = require("utils/fx")
local deltaTime = require("utils/deltaTime")
local mutantspawn = require("features/mutantspawn")

-- ── 좀비 레인 (zombie_rain) 클라이언트 ── [프로토타입: 런타임 스퀘어 생성] ─────
-- 역할 4가지:
--  ① 시작: 샌드박스 반경/지속시간/종류별 마리수를 읽어 서버에 세션 시작 요청
--  ② 컬럼 준비: 서버 Prep(컬럼 좌표) 수신 시 z=1..dropZ 빈 스퀘어를 로컬 생성.
--     클라 재생성 관문(NetworkZombieSimulator.parseZombie)이 "이 클라"의
--     getGridSquare(realZ)를 보므로, 스퀘어가 없으면 서버 좀비가 아예 생성되지
--     않는다. createNewGridSquare는 멱등(있으면 그대로 반환) -- 중복 안전.
--  ③ 남은시간 UI: 폭격 타이머와 동일 스타일의 30초 카운트다운 패널
--  ④ 착지 처리: 서버 RainMark(zedId+체력+종류)를 받아, 소유 좀비가
--     착지(z<=0.05)하면 낙하 전 체력으로 원복 -> 낙하 부상 무효화.
--     종류(k)가 있으면 특좀 적용기(mutantspawn.mark)에 넘긴다 -- 스프린터 포함
--     전 특좀이 도네 특좀과 같은 경로로 능력/체력/이름표(Mutant_NameTag)를 받는다.
--
-- 낙하 데미지는 엔진 DoLand가 착지 순간 소유 클라에서 넣는다 (fallTime>50 시
-- 체력 감소 + 80% 확률 bHardFall 넘어짐). 체력만 원복하고 넘어짐 연출은
-- 자연스러우므로 그대로 둔다. 착지 감지는 OnZombieUpdate가 아닌 좀비 리스트
-- 스캔을 쓴다 -- OnZombieUpdate는 ZombieFallDownState(착지 넘어짐) 동안
-- 발화가 배제되므로(IsoZombie:2096) 착지 직후를 놓칠 수 있다.
--
-- 투하 모드(Rain_AirdropMode): 이름이 "좀비 투하"로 바뀌고, 서버가 보내는 비행
-- 정보(Flight)로 바닥에 수송기 그림자를 그린다 (실제 차량 없음, 렌더만).
-- 그림자는 OnPostFloorLayerDraw(z=0)에서 그려 바닥 위, 물체/캐릭터 아래에 깔린다
-- (IsoCell 타일 렌더에서 WorldMarkers 바닥 마커 직후, IsoMarkers 직전에 발화).
--
-- [알려진 엣지] 낙하 도중 뒤늦게 스트림인한 클라는 컬럼 청크가 로드 전이라
-- 스퀘어 생성이 스킵될 수 있다 -> 해당 좀비는 착지(z=0) 후 패킷부터 정상
-- 재생성된다 (일시적 비표시만 발생, 유실 아님).

local PENDING_MS = 60000    -- RainMark 유효시간 (스트림아웃/원격 소유 잔여분 청소)
-- 서버 PongDuRainServer.lua 의 PREP_DELAY_MS 와 같은 값이어야 한다.
-- 서버는 Start 수신 후 이만큼 기다렸다가 첫 마리를 스폰하므로, 카운터/반경 마커도
-- 같은 만큼 늘려 "마지막 마리 스폰 = 카운터 0" 에 맞춘다.
local SERVER_PREP_MS = 1000

-- ── 샌드박스 옵션 (사용 시점에 읽음 -- 파일 로드 시점엔 SandboxVars 비어있음) ──
-- 반경(Rain_Radius), 지속시간(Rain_Duration, 초), 종류별 마리수(Rain_Count_<종류>)를
-- 서버에 전달한다. 클라 UI 타이머 길이도 지속시간을 따른다 (실제 경과 ms 감산).
-- kinds 키는 서버 RAIN_KINDS / 특좀 kind 이름과 같다.
local function airdropEnabled()
    return SandboxVars.PongDu.Rain_AirdropMode
end

-- 타이머/큐박스에 쓸 표시 이름 키 (투하 모드면 "좀비 투하")
local function labelKeyNow()
    if airdropEnabled() then return "IGUI_donation_zombie_airdrop" end
    return "IGUI_donation_zombie_rain"
end

local function rainCfg()
    local sv = SandboxVars.PongDu
    local kinds = {
        ["normal"]   = sv.Rain_Count_Normal,
        ["sprinter"] = sv.Rain_Count_Sprinter,
        ["screamer"] = sv.Rain_Count_Screamer,
        ["brute"]    = sv.Rain_Count_Brute,
        ["roach"]    = sv.Rain_Count_Roach,
        ["tracer"]   = sv.Rain_Count_Tracer,
    }
    return sv.Rain_Radius, sv.Rain_Duration, kinds
end

-- 반경 표시 (Rain_ShowRadius)
local function showRadiusEnabled()
    return SandboxVars.PongDu.Rain_ShowRadius
end

-- 바닥 반경 마커/효과음은 utils/fx 가 처리한다 (본인 로컬 + 주변 브로드캐스트).
-- 레인 마커는 지속시간 동안 유지 (강령술의 3초와 달리 낙하가 계속되므로).

-- ── 남은시간 표시 패널 (BombardTimerDisplay와 동일 스타일) ─────────────────────
local _rainRemainMs = 0   -- 남은 시간(ms). OnTick에서 실제 경과시간만큼 감산
local _panel     = nil

local RainTimerDisplay = ISPanel:derive("RainTimerDisplay")

function RainTimerDisplay:new()
    local w = getCore():getScreenWidth()
    -- y좌표는 timerStack이 등록 순서에 맞춰 잡아준다(register 전까지는 임시값 0).
    -- 폭 160 -> 180: 폰트를 한 단계(Small -> Medium) 키우면서 텍스트 폭도 늘어남.
    local o = ISPanel:new(w / 2 - 90, 0, 180, 30)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

function RainTimerDisplay:render()
    -- 남은 시간에는 서버 준비 대기(SERVER_PREP_MS)가 포함돼 있다. 표시에선 그만큼 빼서
    -- 시작 순간 설정값(예: 30초)이 그대로 보이게 한다. 00:00 은 마지막 1초 동안 표시.
    local totalSec = math.ceil((_rainRemainMs - SERVER_PREP_MS) / 1000)
    if totalSec < 0 then totalSec = 0 end
    local m = math.floor(totalSec / 60)
    local s = totalSec % 60
    local col = colorMap.get("zombie_rain")
    textOutline.drawCentre(self, getText(labelKeyNow()) .. " " .. string.format("%02d:%02d", m, s),
        self.width / 2, 0, col[1], col[2], col[3], 1, UIFont.Medium)
end

function RainTimerDisplay:update()
    if _rainRemainMs <= 0 then
        timerStack.unregister(self)
        self:removeFromUIManager()
        _panel = nil
    end
end

-- ── 투하 모드: 수송기 그림자 ─────────────────────────────────────────────────
-- 위에서 본 수송기 실루엣(기수가 텍스처 위쪽). 경로 방향으로 회전한 정사각형
-- 네 꼭짓점을 월드 좌표로 잡아 화면에 투영하므로 아이소 시점에 맞게 찌그러진다.
-- renderPoly UV: 1=좌상, 2=우상, 3=우하, 4=좌하 (GenericSpriteRenderState.renderPoly).
local SHADOW_TEX    = getTexture("media/textures/Shadows/shadowPongDuAirdrop.png")
local SHADOW_SIZE   = 20     -- 그림자 한 변 (타일). 날개폭이 텍스처 폭을 거의 채운다
local SHADOW_ALPHA  = 0.38
local SHADOW_FADE   = 800    -- 등장/퇴장 페이드 (ms)
local SHADOW_TAIL   = 2500   -- 마지막 투하 후 화면 밖으로 빠져나가는 시간 (ms)
local FLIGHT_CULL   = 150    -- 비행 중심에서 이보다 멀면 수신 무시 (타일)
local _flights = {}

local function toScreen(x, y)
    return IsoUtils.XToScreen(x, y, 0, 0) - IsoCamera.getOffX(),
           IsoUtils.YToScreen(x, y, 0, 0) - IsoCamera.getOffY()
end

local function drawFlights(z)
    if z ~= 0 or #_flights == 0 then return end
    if not SHADOW_TEX then return end
    local now = getTimestampMs()
    local renderer = getRenderer()
    for i = #_flights, 1, -1 do
        local f = _flights[i]
        local t = now - f.t0
        local endT = f.prep + f.dur + SHADOW_TAIL
        if t > endT then
            table.remove(_flights, i)
            print("[PongDuRain] airdrop shadow done")
        else
            -- 경로 위치: prep 시점에 -r, prep+dur 시점에 +r (서버 스폰 시각과 같은 식)
            local s = -f.r + (t - f.prep) * f.v
            local a = SHADOW_ALPHA
            if t < SHADOW_FADE then a = a * t / SHADOW_FADE end
            if endT - t < SHADOW_FADE then a = a * (endT - t) / SHADOW_FADE end
            local h  = SHADOW_SIZE / 2
            local mx = f.cx + f.ux * s
            local my = f.cy + f.uy * s
            local fx_, fy_ = f.ux * h, f.uy * h      -- 기수 방향
            local rx, ry   = -f.uy * h, f.ux * h     -- 오른쪽 날개 방향
            local x1, y1 = toScreen(mx + fx_ - rx, my + fy_ - ry)   -- 기수-왼쪽
            local x2, y2 = toScreen(mx + fx_ + rx, my + fy_ + ry)   -- 기수-오른쪽
            local x3, y3 = toScreen(mx - fx_ + rx, my - fy_ + ry)   -- 꼬리-오른쪽
            local x4, y4 = toScreen(mx - fx_ - rx, my - fy_ - ry)   -- 꼬리-왼쪽
            renderer:renderPoly(SHADOW_TEX, x1, y1, x2, y2, x3, y3, x4, y4, 0, 0, 0, a)
        end
    end
end
Events.OnPostFloorLayerDraw.Add(drawFlights)

-- ── 착지 처리 대기열 ──────────────────────────────────────────────────────────
-- [onlineID] = { h=서버 스폰 직후 체력, k=특좀 종류(nil=일반), e=만료(ms),
--               air=공중에서 마지막으로 본 체력 }
local _pending      = {}
local _pendingCount = 0
local _sweepAcc     = 0

Events.OnServerCommand.Add(function(module, command, args)
    if module ~= "PongDuRain" then return end

    -- ── 컬럼 공중 스퀘어 생성 (서버 스폰 전 선행) ──
    if command == "Prep" then
        local cols = args and args["cols"]
        if type(cols) ~= "table" then return end
        local dropZ = tonumber(args["z"]) or 4
        local cell  = getCell()
        if not cell then return end
        -- [계측] 클라 로컬 생성 소요시간 + 성공/스킵 카운트 (서버 로그와 대조용)
        local t0 = getTimestampMs()
        local created, reused, failed = 0, 0, 0
        for _, c in pairs(cols) do
            local x = c and tonumber(c["x"])
            local y = c and tonumber(c["y"])
            if x and y then
                for zz = 1, dropZ do
                    if cell:getGridSquare(x, y, zz) then
                        reused = reused + 1
                    else
                        local ok = pcall(function() cell:createNewGridSquare(x, y, zz, true) end)
                        if ok and cell:getGridSquare(x, y, zz) then
                            created = created + 1
                        else
                            failed = failed + 1
                        end
                    end
                end
            end
        end
        print("[PongDuRain] client prep ms=" .. tostring(getTimestampMs() - t0)
            .. " created=" .. tostring(created) .. " reused=" .. tostring(reused)
            .. " failed=" .. tostring(failed))
        return
    end

    -- ── 투하 모드 비행 정보 (그림자 연출) ──
    if command == "Flight" then
        local cx, cy = tonumber(args["cx"]), tonumber(args["cy"])
        local ux, uy = tonumber(args["ux"]), tonumber(args["uy"])
        local r, dur = tonumber(args["r"]), tonumber(args["dur"])
        if not (cx and cy and ux and uy and r and dur) or dur <= 0 then
            print("[PongDuRain] airdrop flight ignored (bad args)")
            return
        end
        local me = getPlayer()
        if me then
            local dx, dy = me:getX() - cx, me:getY() - cy
            if dx * dx + dy * dy > (r + FLIGHT_CULL) * (r + FLIGHT_CULL) then return end
        end
        if not SHADOW_TEX then
            print("[PongDuRain] WARN airdrop shadow texture missing")
        end
        _flights[#_flights + 1] = {
            cx = cx, cy = cy, ux = ux, uy = uy, r = r,
            prep = tonumber(args["prep"]) or SERVER_PREP_MS,
            dur = dur,
            v = 2 * r / dur,           -- 타일/ms
            t0 = getTimestampMs(),
        }
        print(string.format("[PongDuRain] airdrop shadow start c=(%.1f,%.1f) dir=(%.2f,%.2f) r=%.0f durMs=%.0f",
            cx, cy, ux, uy, r, dur))
        return
    end

    if command ~= "RainMark" then return end
    local zeds = args and args["zeds"]
    if type(zeds) ~= "table" then return end
    local sender = tostring(args["sender"] or "")   -- 세션 공통 (이름표용)
    local now = getTimestampMs()
    for _, e in pairs(zeds) do
        local id = e and tonumber(e["id"])
        if id then
            if not _pending[id] then _pendingCount = _pendingCount + 1 end
            local kind = e["k"]
            _pending[id] = {
                h = tonumber(e["h"]) or 1.0,
                k = kind,
                e = now + PENDING_MS,
            }
            -- 특좀: 도네 특좀(MutantMark)과 같은 대기열에 등록 -> OnZombieUpdate
            -- 적용기가 onlineID로 매칭해 능력/체력/이름표를 입힌다 (전 클라 각자).
            if kind then mutantspawn.mark(id, kind, sender) end
        end
    end
end)

local function onTick()
    -- ① 타이머 감산 (패널 update()가 0에서 자가 제거). 프레임 수가 아닌 실제 경과시간.
    if _rainRemainMs > 0 then
        _rainRemainMs = _rainRemainMs - deltaTime.ms()
        if _rainRemainMs < 0 then _rainRemainMs = 0 end
    end

    -- ② 착지 스캔 (대기 항목 있을 때만)
    if _pendingCount == 0 then return end
    local now  = getTimestampMs()
    local cell = getCell()
    local zl   = cell and cell:getZombieList()
    if zl then
        for i = 0, zl:size() - 1 do
            local z  = zl:get(i)
            local id = z and z:getOnlineID()
            local p  = id and _pending[id]
            if p then
                if now > p.e then
                    _pending[id]  = nil
                    _pendingCount = _pendingCount - 1
                elseif z:getZ() > 0.05 then
                    -- 공중: 착지 직전 체력 기록. 특좀은 적용기 초기화(체력 설정)가
                    -- 끝난 뒤의 값만 기록한다 -- 초기화 전 값(바닐라 체력)으로
                    -- 원복하면 특좀 체력 설정이 날아간다.
                    if not p.k or z:getVariableBoolean("PuppetMutantInit") then
                        p.air = z:getHealth()
                    end
                elseif not z:isRemoteZombie() then
                    -- 착지 시 체력 원복: 좀비 체력은 클라 권한 -> 소유 좀비만.
                    -- 낙하 중 사살된 좀비는 원복하지 않고 소모만 한다.
                    if not z:isDead() then
                        if p.k then
                            -- 특좀: 초기화 후 공중 체력이 있을 때만 원복. 스냅샷도
                            -- 같이 갱신해야 guardStats가 "외부 덮어쓰기"로 되돌리지
                            -- 않는다. 착지 전에 초기화가 안 됐으면 원복하지 않는다
                            -- (이후 초기화가 설정 체력을 새로 씌우므로 불필요).
                            if p.air then
                                pcall(function() mutantspawn.restoreHealth(z, p.air) end)
                            else
                                print("[PongDuRain] landed before mutant init, skip restore kind="
                                    .. tostring(p.k) .. " zid=" .. tostring(id))
                            end
                        else
                            local hp = p.air or p.h
                            pcall(function() z:setHealth(hp) end)
                        end
                    end
                    _pending[id]  = nil
                    _pendingCount = _pendingCount - 1
                end
            end
        end
    end

    -- ③ 만료 청소 (스트림아웃/원격 소유라 리스트 스캔에 안 잡히는 잔여분, ~10초마다)
    _sweepAcc = _sweepAcc + 1
    if _sweepAcc >= 600 then
        _sweepAcc = 0
        for id, p in pairs(_pending) do
            if now > p.e then
                _pending[id]  = nil
                _pendingCount = _pendingCount - 1
            end
        end
    end
end
Events.OnTick.Add(onTick)

-- ── 활성 여부 조회 (rewardManager의 random_teleport 락용) ────────────────────
-- [public name: .c]
function _a.c()
    return _rainRemainMs > 0
end

-- ── 시작 (rewardManager에서 호출) ────────────────────────────────────────────
function _a.b(player, sender)
    local r, dur, kinds = rainCfg()
    local air = airdropEnabled()
    sendClientCommand("PongDuRain", "Start", {
        ["r"] = r, ["dur"] = dur, ["kinds"] = kinds,
        ["sender"] = sender or "",
        ["air"] = air,
    })
    print("[PongDuRain] start request air=" .. tostring(air) .. " r=" .. tostring(r) .. " dur=" .. tostring(dur)
        .. " normal=" .. tostring(kinds["normal"]) .. " sprinter=" .. tostring(kinds["sprinter"])
        .. " screamer=" .. tostring(kinds["screamer"]) .. " brute=" .. tostring(kinds["brute"])
        .. " roach=" .. tostring(kinds["roach"]) .. " tracer=" .. tostring(kinds["tracer"]))
    -- 효과음/반경 표시: 본인은 즉시 로컬, 나머지 접속자는 서버 거리컷 브로드캐스트.
    -- 반경 표시는 Rain_ShowRadius 를 따르고(꺼져 있으면 markerRadius=0 -> 아무에게도
    -- 안 뜸), 마커는 낙하가 이어지는 지속시간 내내 유지된다.
    local px, py, pz = player:getX(), player:getY(), player:getZ()
    -- 투하 모드는 원형 반경이 실제 낙하 범위(경로 띠)와 달라 마커를 띄우지 않는다.
    -- 그림자가 범위 표시를 대신한다.
    local showRadius = showRadiusEnabled() and not air
    local totalMs = dur * 1000 + SERVER_PREP_MS   -- 서버 준비 대기 포함
    fx.playAt("zombie_rain", px, py)
    fx.broadcast({
        f = "zombie_rain",
        x = px, y = py, z = pz,
        sound = "zombie_rain",
        markerRadius = showRadius and r or 0,
        markerMs = totalMs,
    })
    if showRadius then
        fx.marker(px, py, pz, "zombie_rain", r, totalMs)
    end
    -- 독립 실행: 진행 중 재후원이 오면 서버는 세션을 병행하고,
    -- 클라 타이머는 "가장 늦게 끝나는 세션" 기준으로 지속시간만큼 리필한다.
    if _rainRemainMs < totalMs then _rainRemainMs = totalMs end
    print("[PongDuRain] client timer start durS=" .. tostring(dur) .. " totalMs=" .. tostring(totalMs)
        .. " remainMs=" .. tostring(math.floor(_rainRemainMs)))
    if not _panel then
        _panel = RainTimerDisplay:new()
        _panel:addToUIManager()
        _panel:setVisible(true)
        timerStack.register(_panel)
    end
end

return _a
