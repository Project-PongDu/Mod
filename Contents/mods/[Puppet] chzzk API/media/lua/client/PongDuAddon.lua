-- ═══════════════════════════════════════════════════════════════════════════
--  PongDuAddon -- 외부(서버 전용) 모드가 퐁듀에 후원 기능을 붙이는 공식 입구
--
--  퐁듀 본체에는 특정 서버/스트리머 전용 내용을 넣지 않는다. 대신 이 모듈이
--  "featureId -> 효과" 등록 창구를 열어두고, 애드온 모드는 자기 파일에서
--  register() 한 번만 호출한다. 등록된 기능은 퐁듀 내장 기능과 같은 경로를
--  탄다: rewards.txt 수신 -> 큐박스 -> Delay 카운트다운 -> 발동,
--  pongdu_tiers.txt 게시(런처 금액 매핑), 어드민 테스트 메뉴.
--
--  사용법 (애드온 모드의 media/lua/client/*.lua):
--
--      local PongDuAddon = require("PongDuAddon")
--      PongDuAddon.register("my_feature", {
--          labelKey  = "IGUI_donation_my_feature",   -- 필수. 큐박스/런처/테스트메뉴 표시명
--          fn        = function(sender) ... end,     -- 필수. 실제 효과
--          immediate = true,                         -- 선택. true(기본)=안전지대에서도 즉시,
--                                                    --       false=안전지대 벗어날 때까지 대기,
--                                                    --       function()->bool 도 가능
--          blocked   = function(player) ... end,     -- 선택. true 반환 시 큐박스 슬롯 잠금
--          color     = {r, g, b},                    -- 선택. 큐박스 색 (0~1)
--          category  = "personal",                   -- 선택. "personal"(기본) / "server"
--      })
--
--  애드온 모드가 직접 선언해야 하는 샌드박스 옵션 (퐁듀 규약, 이름 고정):
--      option PongDu.Tier_<featureId>   integer  -- 후원 금액 (0 = 비활성)
--      option PongDu.Delay_<featureId>  integer  -- 발동 대기시간 0~60초
--  네임스페이스가 PongDu 여도 다른 모드에서 선언할 수 있다
--  (SandboxOptions.toTable 이 기존 SandboxVars.PongDu 테이블을 재사용한다).
--
--  주의:
--   * 파일 로드 순서는 "모든 모드의 경로를 합쳐 알파벳순"이다. 전역 변수에
--     기대지 말고 반드시 require("PongDuAddon") 으로 받는다 (require 는
--     필요 시 즉시 로드하고 반환값을 캐시한다).
--   * 퐁듀 내장 featureId 와 같은 id 를 등록하면 내장 기능이 우선한다
--     (rewardManager / ConnectionChecker 가 경고 로그를 남긴다).
--   * fn 안에서 에러가 나도 퐁듀 이벤트 처리 상태(processingEvent)는 항상
--     해제된다. 에러 내용은 [PongDuAddon] 로그로 남는다.
--
--  이 모듈은 leaf 여야 한다: utils/labelKey, utils/colorMap, global 외에는
--  require 하지 않는다 (rewardManager 가 이 모듈을 require 하므로 역방향
--  require 는 순환이 되어 PZ 가 nil 을 돌려준다).
-- ═══════════════════════════════════════════════════════════════════════════

local labelKey = require("utils/labelKey")
local colorMap = require("utils/colorMap")
local global   = require("global")

local LOG = "[PongDuAddon] "

local PongDuAddon = {}

local handlers = {}   -- featureId -> { immediate, blocked, fn }  (rewardManager 엔트리 형식)
local metas    = {}   -- featureId -> { labelKey, category }
local order    = {}   -- 등록 순서 (tiers 덤프 순서 = 중복 금액 시 우선순위)

local function isColor(c)
    return type(c) == "table"
        and type(c[1]) == "number" and type(c[2]) == "number" and type(c[3]) == "number"
end

-- register(featureId, def) -> true | false
function PongDuAddon.register(featureId, def)
    if type(featureId) ~= "string" or not featureId:match("^[a-z0-9_]+$") then
        print(LOG .. "REGISTER REJECTED: featureId must match [a-z0-9_]+ (got "
            .. tostring(featureId) .. ")")
        return false
    end
    if type(def) ~= "table" then
        print(LOG .. "REGISTER REJECTED: " .. featureId .. " - def is not a table")
        return false
    end
    if type(def.fn) ~= "function" then
        print(LOG .. "REGISTER REJECTED: " .. featureId .. " - def.fn is not a function")
        return false
    end
    if type(def.labelKey) ~= "string" or def.labelKey == "" then
        print(LOG .. "REGISTER REJECTED: " .. featureId .. " - def.labelKey is missing")
        return false
    end
    if handlers[featureId] then
        print(LOG .. "REGISTER REJECTED: " .. featureId .. " - already registered by another addon")
        return false
    end

    local immediate = def.immediate
    if immediate == nil then
        immediate = true
    elseif type(immediate) ~= "boolean" and type(immediate) ~= "function" then
        print(LOG .. "REGISTER REJECTED: " .. featureId
            .. " - def.immediate must be boolean or function (got " .. type(immediate) .. ")")
        return false
    end
    if def.blocked ~= nil and type(def.blocked) ~= "function" then
        print(LOG .. "REGISTER REJECTED: " .. featureId .. " - def.blocked must be a function")
        return false
    end

    local category = def.category
    if category == nil then category = "personal" end
    if category ~= "personal" and category ~= "server" then
        print(LOG .. "REGISTER REJECTED: " .. featureId
            .. " - def.category must be 'personal' or 'server' (got " .. tostring(category) .. ")")
        return false
    end

    local effect = def.fn
    handlers[featureId] = {
        immediate = immediate,
        blocked   = def.blocked,
        fn = function(sender)
            print(LOG .. "fire: " .. featureId .. " sender=" .. tostring(sender))
            local ok, err = pcall(effect, sender)
            if not ok then
                print(LOG .. "HANDLER ERROR: " .. featureId .. " - " .. tostring(err))
            end
            global.processingEvent = false
        end,
    }
    metas[featureId] = { labelKey = def.labelKey, category = category }
    table.insert(order, featureId)

    -- 큐박스 라벨 / 테스트 메뉴 표시명 / 큐박스 색은 퐁듀 공용 leaf 테이블을
    -- 그대로 참조하므로 여기서 같이 채워준다. 내장 기능 값은 덮어쓰지 않는다.
    if labelKey[featureId] == nil then
        labelKey[featureId] = def.labelKey
    end
    if def.color ~= nil then
        if isColor(def.color) then
            if colorMap.map[featureId] == nil then
                colorMap.map[featureId] = { def.color[1], def.color[2], def.color[3] }
            end
        else
            print(LOG .. "WARNING: " .. featureId .. " - def.color ignored (expected {r, g, b})")
        end
    end

    print(LOG .. "registered: " .. featureId .. " category=" .. category
        .. " immediate=" .. tostring(immediate) .. " labelKey=" .. def.labelKey)
    return true
end

-- getHandler(featureId) -> rewardManager 엔트리 | nil
function PongDuAddon.getHandler(featureId)
    return handlers[featureId]
end

-- getMeta(featureId) -> { labelKey, category } | nil
function PongDuAddon.getMeta(featureId)
    return metas[featureId]
end

-- getFeatureIds() -> 등록 순서대로의 featureId 배열 (복사본)
function PongDuAddon.getFeatureIds()
    local ids = {}
    for i = 1, #order do
        ids[i] = order[i]
    end
    return ids
end

return PongDuAddon
