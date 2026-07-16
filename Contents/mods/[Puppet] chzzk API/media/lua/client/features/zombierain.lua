local _a = {}
require("ISUI/ISPanel")

-- ── 좀비 레인 (zombie_rain) 클라이언트 ── [프로토타입: 런타임 스퀘어 생성] ─────
-- 역할 4가지:
--  ① 시작: 샌드박스 반경/스프린터비율을 읽어 서버에 세션 시작 요청
--  ② 컬럼 준비: 서버 Prep(컬럼 좌표) 수신 시 z=1..dropZ 빈 스퀘어를 로컬 생성.
--     클라 재생성 관문(NetworkZombieSimulator.parseZombie)이 "이 클라"의
--     getGridSquare(realZ)를 보므로, 스퀘어가 없으면 서버 좀비가 아예 생성되지
--     않는다. createNewGridSquare는 멱등(있으면 그대로 반환) -- 중복 안전.
--  ③ 남은시간 UI: 폭격 타이머와 동일 스타일의 30초 카운트다운 패널
--  ④ 착지 처리: 서버 RainMark(zedId+체력+스프린터)를 받아, 소유 좀비가
--     착지(z<=0.05)하면 낙하 전 체력으로 원복 -> 낙하 부상 무효화.
--     스프린터 플래그면 setWalkType 적용 (좀비는 클라 권한이라 클라 적용이 신뢰 경로).
--
-- 낙하 데미지는 엔진 DoLand가 착지 순간 소유 클라에서 넣는다 (fallTime>50 시
-- 체력 감소 + 80% 확률 bHardFall 넘어짐). 체력만 원복하고 넘어짐 연출은
-- 자연스러우므로 그대로 둔다. 착지 감지는 OnZombieUpdate가 아닌 좀비 리스트
-- 스캔을 쓴다 -- OnZombieUpdate는 ZombieFallDownState(착지 넘어짐) 동안
-- 발화가 배제되므로(IsoZombie:2096) 착지 직후를 놓칠 수 있다.
--
-- [알려진 엣지] 낙하 도중 뒤늦게 스트림인한 클라는 컬럼 청크가 로드 전이라
-- 스퀘어 생성이 스킵될 수 있다 -> 해당 좀비는 착지(z=0) 후 패킷부터 정상
-- 재생성된다 (일시적 비표시만 발생, 유실 아님).

local PENDING_MS = 60000    -- RainMark 유효시간 (스트림아웃/원격 소유 잔여분 청소)

-- ── 샌드박스 옵션 (사용 시점에 읽음 -- 파일 로드 시점엔 SandboxVars 비어있음) ──
-- 반경/스프린터비율에 더해 지속시간(Rain_Duration, 초)과 마리수(Rain_Count)도
-- 서버에 전달한다. 클라 UI 타이머 길이도 지속시간을 따른다 (1틱 = 1 감산).
local function rainCfg()
    local sv  = SandboxVars and SandboxVars.PongDu
    local r   = (sv and tonumber(sv.Rain_Radius))          or 55
    local pct = (sv and tonumber(sv.Rain_SprinterPercent)) or 0
    local dur = (sv and tonumber(sv.Rain_Duration))        or 30
    local cnt = (sv and tonumber(sv.Rain_Count))           or 100
    return r, pct, dur, cnt
end

-- 스프린터 이름표 (Rain_SprinterNameTag, 기본 켜짐). 실제 렌더는 특수좀비
-- 이름표 시스템(mutantspawn.lua)이 담당하므로 Mutant_NameTag가 꺼져 있으면
-- 이쪽을 켜도 표시되지 않는다.
local function sprinterTagEnabled()
    local sv = SandboxVars and SandboxVars.PongDu
    if sv and sv.Rain_SprinterNameTag == false then return false end
    return true
end

-- 반경 표시 (Rain_ShowRadius, 기본 켜짐)
local function showRadiusEnabled()
    local sv = SandboxVars and SandboxVars.PongDu
    if sv and sv.Rain_ShowRadius == false then return false end
    return true
end

-- 바닥 반경 마커: riseup.lua와 동일 API (ISSpawnHordeUI가 쓰는 것).
-- WorldMarkers는 로컬 렌더링이라 호출한 클라이언트(도네 본인) 화면에만 보인다.
-- 레인은 지속시간 동안 유지 (강령술의 3초와 달리 낙하가 계속되므로).
local function showRadiusMarker(square, radius, durationMs)
    if not square then return end
    local marker = getWorldMarkers():addGridSquareMarker(square, 0.35, 0.55, 1.0, true, radius)
    marker:setScaleCircleTexture(true)
    local start = getTimestampMs()
    local function tick()
        if getTimestampMs() - start >= durationMs then
            marker:remove()
            Events.OnTick.Remove(tick)
        end
    end
    Events.OnTick.Add(tick)
end

-- ── 남은시간 표시 패널 (BombardTimerDisplay와 동일 스타일) ─────────────────────
local _rainTicks = 0
local _panel     = nil

local RainTimerDisplay = ISPanel:derive("RainTimerDisplay")

function RainTimerDisplay:new()
    local w = getCore():getScreenWidth()
    local h = getCore():getScreenHeight()
    -- 폭격 타이머(h-150)와 동시 표시될 수 있으므로 30px 위에 배치
    local o = ISPanel:new(w / 2 - 80, h - 180, 160, 25)
    setmetatable(o, self)
    self.__index = self
    o:noBackground()
    return o
end

function RainTimerDisplay:render()
    local totalSec = math.floor(_rainTicks / 60)
    local m = math.floor(totalSec / 60)
    local s = totalSec % 60
    self:drawTextCentre(getText("IGUI_donation_zombie_rain") .. " " .. string.format("%02d:%02d", m, s),
        self.width / 2, 0, 0.55, 0.75, 1, 1, UIFont.Small)
end

function RainTimerDisplay:update()
    if _rainTicks <= 0 then
        self:removeFromUIManager()
        _panel = nil
    end
end

-- ── 착지 처리 대기열 ──────────────────────────────────────────────────────────
-- [onlineID] = { h=원복 체력, s=스프린터(0/1), e=만료(ms), sApplied=적용 여부 }
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

    if command ~= "RainMark" then return end
    local zeds = args and args["zeds"]
    if type(zeds) ~= "table" then return end
    local sender = tostring(args["sender"] or "")   -- 세션 공통 (이름표용)
    local now = getTimestampMs()
    for _, e in pairs(zeds) do
        local id = e and tonumber(e["id"])
        if id then
            if not _pending[id] then _pendingCount = _pendingCount + 1 end
            _pending[id] = {
                h  = tonumber(e["h"]) or 1.0,
                s  = tonumber(e["s"]) or 0,
                e  = now + PENDING_MS,
                sd = sender,
            }
        end
    end
end)

local function onTick()
    -- ① 타이머 감산 (패널 update()가 0에서 자가 제거)
    if _rainTicks > 0 then _rainTicks = _rainTicks - 1 end

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
                else
                    -- 스프린터 적용: 시야에 들어온 모든 클라가 1회 적용 (멱등)
                    if p.s == 1 and not p.sApplied then
                        pcall(function() z:setWalkType("sprint" .. tostring(ZombRand(5) + 1)) end)
                        -- 이름표: 특수좀비 시스템과 동일하게 클라 로컬 modData 마킹
                        -- (RainMark는 전 클라 브로드캐스트라 각 클라가 각자 마킹 --
                        --  동기화 불필요). PuppetMutantZid 스탬프는 풀 재활용 스테일
                        --  방어(applyMutant 가드)의 판별 기준. 서버측 modData는 건드리지
                        --  않으므로 시체/부활 경로에는 영향 없음 (일반좀비로 부활).
                        if sprinterTagEnabled() then
                            pcall(function()
                                local md = z:getModData()
                                md["PuppetMutant"]    = "sprinter"
                                md["PuppetMutantZid"] = id
                                if p.sd and p.sd ~= "" then
                                    md["PuppetMutantSender"] = p.sd
                                end
                            end)
                        end
                        p.sApplied = true
                    end
                    -- 착지 시 체력 원복: 좀비 체력은 클라 권한 -> 소유 좀비만.
                    -- 낙하 중 사살된 좀비는 원복하지 않고 소모만 한다.
                    if z:getZ() <= 0.05 and not z:isRemoteZombie() then
                        if not z:isDead() then
                            pcall(function() z:setHealth(p.h) end)
                        end
                        _pending[id]  = nil
                        _pendingCount = _pendingCount - 1
                    end
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

-- ── 시작 (rewardManager에서 호출) ────────────────────────────────────────────
function _a.b(player, sender)
    local r, pct, dur, cnt = rainCfg()
    sendClientCommand("PongDuRain", "Start", {
        ["r"] = r, ["pct"] = pct, ["dur"] = dur, ["cnt"] = cnt,
        ["sender"] = sender or "",
    })
    getSoundManager():PlaySound("zombie_rain", false, 1.0)
    -- 반경 표시 (Rain_ShowRadius): 도네 본인 화면에 지속시간 동안
    if showRadiusEnabled() then
        showRadiusMarker(player:getCurrentSquare(), r, dur * 1000)
    end
    -- 독립 실행: 진행 중 재후원이 오면 서버는 세션을 병행하고,
    -- 클라 타이머는 "가장 늦게 끝나는 세션" 기준으로 지속시간만큼 리필한다.
    local ticks = dur * 60
    if _rainTicks < ticks then _rainTicks = ticks end
    if not _panel then
        _panel = RainTimerDisplay:new()
        _panel:addToUIManager()
        _panel:setVisible(true)
    end
end

return _a
