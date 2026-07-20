-- 차량 드랍 키트("Open Vehicle Drop Kit") 개봉 진행 중 연출 3가지를 처리한다.
-- 전부 같은 레시피를 대상으로 같은 ISCraftAction을 후킹하므로 파일 하나로 묶음.
--
--   1) start():  개봉 시작 시 레시피 Sound(RadioTalk) 볼륨을 절반으로 낮춤
--   2) update(): 진행 중 머리 위 대사를 "차량보급 호출 중." -> ".." -> "..." 순으로 반복 표시,
--                진행률(jobDelta)이 50%를 넘는 순간 vehicle_call_signal 사운드를 1회 재생
--   3) stop(): 액션이 "취소"된 경우에만 재생 중이던 vehicle_call_signal을 즉시 정지.
--              정상 완료(perform) 시에는 정지하지 않고 소리가 끝까지 재생되도록 둔다.
--              (바닐라 craftSound(RadioTalk)는 stop/perform 양쪽에서 바닐라가 알아서 끊음 — 유지)
--
-- [사운드 볼륨] 레시피 Sound 필드는 ISCraftAction:start()에서
-- craftSound = character:playSound(...)로 재생되어 Time(스크립트 지정 틱수) 동안
-- 지속되다 완료/취소 시 stop()에서 정지된다 (PZ-Library ISCraftAction.lua 확인).
-- Recipe 스크립트 자체엔 볼륨 필드가 없어 조절 수단이 없어 시작 시점에 여기서 낮춘다.
--
-- [대사] Kahlua stdlib에는 string.rep이 없어(PZ-Library StringLib 확인, 미구현 함수는
-- "tried to call nil"로 즉시 죽음) 점 개수별 문자열을 테이블로 미리 준비해 인덱싱한다.
--
-- character:Say(text)는 ChatManager.showInfoMessage로 채팅 로그에 "새 줄"을 추가하는
-- 함수라(IsoGameCharacter.ProcessSay 디컴파일 확인), 호출할 때마다 머리 위에 이전
-- 줄들이 최근 몇 개까지 겹쳐 쌓이며 표시된다(요청한 "한 줄 교체"가 아니라 로그 누적).
-- 대신 character:setHaloNote(text, r, g, b, dispTime)를 쓴다. 이건 캐릭터가 들고
-- 있는 단일 TextDrawObject(haloNote)의 문자열을 매번 덮어쓰는 방식이라(ReadString()
-- 호출, 새 줄 추가 아님) 항상 한 줄만 표시되고 내용만 교체된다. ISSearchManager.lua의
-- 채집 결과 표시(searchManager:setHaloNote)와 동일한 표준 패턴.
-- dispTime 단위는 초가 아니라 내부 틱 카운트(바닐라 기본값 haloDispTime=128)라
-- DOT_INTERVAL_TICKS(40)보다 충분히 큰 값을 매 갱신마다 다시 넣어줘야 끊기지 않는다.
--
-- [호출 사운드 취소 처리] 취소 경로(stop)에서만 끊는다. 바닐라 ISCraftAction은
-- craftSound를 stop/perform 양쪽에서 끊지만, 우리 사운드는 "완료 시 끝까지 재생"이
-- 요구사항이므로 perform은 후킹하지 않는다.
-- character:stopOrTriggerSound(handle)은 IsoGameCharacter가 getEmitter()로 위임하는
-- 표준 정지 API (craftSound 정지와 동일 메서드).
--
-- [재생 시점] 고정 틱(예: 250) 대신 진행률 self:getJobDelta() >= 0.5 를 쓴다.
-- jobDelta는 ISBaseTimedAction:getJobDelta() -> self.action:getJobDelta()로
-- 0.0~1.0 진행률을 돌려주므로, 레시피 Time 값이 나중에 바뀌어도
-- "절반 지점"이라는 의미가 그대로 유지된다.

-- [중요] recipe:getName()은 Translator.getRecipeName()을 거친 "번역된 이름"을 반환한다
-- (Recipe.java 디컴파일 확인). Recipes_KO.txt에 번역이 등록된 뒤로는 KO 클라에서
-- getName()이 "보급상자 열기"를 돌려줘 영문 비교가 전부 실패했음.
-- 로케일과 무관한 스크립트 원본 이름인 getOriginalname()으로 비교한다.
local TARGET_RECIPE_NAME = "Open Vehicle Drop Kit" -- 스크립트 원본(getOriginalname) 기준

local function isTargetRecipe(recipe)
    return recipe and recipe:getOriginalname() == TARGET_RECIPE_NAME
end
local TARGET_VOLUME = 0.5
local DOT_INTERVAL_TICKS = 40 -- 점 개수가 바뀌는 간격(틱). Time 값이 바뀌면 체감 순환 속도도 바뀜.
local DOT_PATTERNS = { ".", "..", "..." }
local DOT_HALO_DISPLAY_TICKS = 100 -- setHaloNote 표시 지속(내부 틱). 갱신 간격(40)보다 여유있게.
local DOT_HALO_COLOR = { 255, 255, 255 } -- r, g, b

local CALL_SOUND_NAME = "vehicle_call_signal" -- t3_rewards_sounds.txt 등록명
local CALL_SOUND_PROGRESS = 0.5 -- 진행률이 이 값을 넘는 순간 1회 재생
local CALL_SOUND_VOLUME = 0.5 -- 재생 볼륨 절반

local original_start = ISCraftAction.start
function ISCraftAction:start()
    original_start(self)

    if isTargetRecipe(self.recipe) and self.craftSound then
        local emitter = self.character:getEmitter()
        if emitter then
            emitter:setVolume(self.craftSound, TARGET_VOLUME)
            print("[VehicleDropCraftSound] RadioTalk 볼륨 " .. TARGET_VOLUME .. "로 낮춤")
        else
            print("[VehicleDropCraftSound] emitter 조회 실패, 볼륨 조절 생략")
        end
    end
end

local original_update = ISCraftAction.update
function ISCraftAction:update()
    original_update(self)

    if isTargetRecipe(self.recipe) then
        self.t3CallTick = (self.t3CallTick or 0) + 1

        -- 점 개수 순환 대사 (3,1,2,3,1,2...)
        local dotIndex = (math.floor(self.t3CallTick / DOT_INTERVAL_TICKS) + 2) % 3 + 1
        if dotIndex ~= self.t3LastDotIndex then
            self.t3LastDotIndex = dotIndex
            self.character:setHaloNote(
                getText("IGUI_donation_vehicle_drop_calling") .. DOT_PATTERNS[dotIndex],
                DOT_HALO_COLOR[1], DOT_HALO_COLOR[2], DOT_HALO_COLOR[3],
                DOT_HALO_DISPLAY_TICKS
            )
        end

        -- 진행률 50% 도달 시 호출 사운드 1회 재생
        if not self.t3CallSoundPlayed and self:getJobDelta() >= CALL_SOUND_PROGRESS then
            self.t3CallSoundPlayed = true
            local emitter = self.character:getEmitter()
            if emitter then
                self.t3CallSoundHandle = emitter:playSound(CALL_SOUND_NAME)
                if self.t3CallSoundHandle and self.t3CallSoundHandle ~= 0 then
                    emitter:setVolume(self.t3CallSoundHandle, CALL_SOUND_VOLUME)
                end
                -- handle이 0/nil이면 GameSounds.getSound()가 null -> 사운드 미등록/빌드 미반영 신호
                print("[VehicleDropCraftSound] " .. CALL_SOUND_NAME .. " 재생 시도 (jobDelta "
                    .. tostring(self:getJobDelta()) .. ", handle=" .. tostring(self.t3CallSoundHandle) .. ")")
                if not self.t3CallSoundHandle or self.t3CallSoundHandle == 0 then
                    print("[VehicleDropCraftSound] 경고: handle 0/nil -> 사운드 등록 실패 추정")
                end
            end
        end
    end
end

-- 재생 중인 호출 사운드를 즉시 정지 (취소 경로 전용)
local function stopCallSound(self)
    if self.t3CallSoundHandle and self.character:getEmitter():isPlaying(self.t3CallSoundHandle) then
        self.character:stopOrTriggerSound(self.t3CallSoundHandle)
        print("[VehicleDropCraftSound] " .. CALL_SOUND_NAME .. " 중간 정지")
    end
end

local original_stop = ISCraftAction.stop
function ISCraftAction:stop()
    if isTargetRecipe(self.recipe) then
        stopCallSound(self)
    end
    original_stop(self)
end

-- perform(정상 완료)은 후킹하지 않는다: 완료 시 vehicle_call_signal은 끝까지 재생.
