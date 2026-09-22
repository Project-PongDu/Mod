HitmanPatches = HitmanPatches or {}

-- Arsenal(26) GunFighter 의 setStuckProjectile(OnHitZombie 핸들러)이
-- GunFighter_02Function.lua:4888 에서 Zombie_Armor_Check() 를 부르는데, 이 전역은
-- GunFighter 모드 어디에도 정의돼 있지 않다(모드 전체에서 이 한 줄에만 등장한다).
-- Brita's Armor Pack 계열이 제공하는 전역이라, 그게 없으면 값이 nil 이고 호출하는
-- 순간 se.krka.kahlua.vm.KahluaUtil.fail 로
--   "Object tried to call nil in setStuckProjectile"
-- 이 터진다.
--
-- 진입 조건은
--   target:getModData().Armored ~= nil  or  target:isReanimatedPlayer()
-- 인데 Armored 를 심는 모드가 없으므로 실제 트리거는 "부활한 플레이어 좀비"다.
-- 퐁듀 강령술(RiseUp)이 플레이어 시체를 의도적으로 setReanimatedPlayer(true) 경로로
-- 부활시키므로(server.lua 의 markFakeDead 주석 참조), 그 좀비를 때리거나 쏠 때마다
-- 터진다 -- 퐁듀 화력지원(드론/헬기)의 z:Hit() 뿐 아니라 플레이어의 평타/사격도
-- 똑같이 OnHitZombie 를 발화시키므로 동일하게 죽는다.
--
-- 이게 왜 성가신가: Kahlua 가 던지는 건 순수 자바 RuntimeException 이라 Lua pcall 이
-- 못 잡는다. 실제로 firesupport.lua 의 pcall 두 겹을 뚫고 Event.trigger 까지 올라갔다.
-- 그래서 z:Hit() 뒤에 있는 hitTime/target/becomeCrawler 원복과 킬 집계가 통째로
-- 건너뛰어지고, 그 프레임의 OnTick 나머지(사운드/큐 처리)도 같이 날아간다.
-- 우리 쪽에서 방어할 방법이 없으므로 빠진 전역을 여기서 채워준다.
--
-- 반환값 2 의 근거: GunFighter 원본이 같은 함수 4876 줄에서 penetration 의 기본값을
-- 2 로 두고, 4930 줄에서 `penetration > 1 or penetration < 0` 이면 "NO ARMOR /
-- FAILED PROTECTION" 으로 분기한다. 즉 2 = 방어구 없음 = 원본의 비장갑 경로와 동일한
-- 동작이다. 게임플레이를 바꾸지 않고 크래시만 없앤다.
--
-- ※ 다른 모드(Brita's Armor Pack 등)가 진짜 구현을 갖고 있으면 그쪽이 우선이다.
--   OnGameStart 는 전 모드의 Lua 로드가 끝난 뒤에 발화하므로, 여기서 nil 검사만으로
--   충분히 판별된다.
-- ※ 다른 ModPatches 와 달리 getActivatedMods() 결과로 분기하지 않는다. mod.info 의
--   id 가 "Arsenal(26)GunFighter[MAIN MOD 2.0]" 처럼 대괄호까지 포함한 긴 문자열이라
--   오타 하나로 패치가 조용히 안 먹는 쪽이 더 위험하다. 이 전역은 GunFighter 말고
--   부르는 곳이 없으므로, nil 일 때 채워두는 건 모드가 없어도 무해하다.
--   모드 활성 여부는 로그로만 남긴다.
local GUNFIGHTER_MOD_ID = "Arsenal(26)GunFighter[MAIN MOD 2.0]"

HitmanPatches.GunFighter = function()
    if Zombie_Armor_Check ~= nil then
        print("[PongDu][ModPatch] GunFighter: Zombie_Armor_Check already provided -- skipped")
        return
    end

    Zombie_Armor_Check = function(target, player, bodypart, weapon)
        return 2   -- NO ARMOR (GunFighter_02Function.lua 의 penetration 기본값과 동일)
    end

    local active = getActivatedMods():contains(GUNFIGHTER_MOD_ID)
    print("[PongDu][ModPatch] GunFighter: Zombie_Armor_Check stub installed"
        .. " (mod active=" .. tostring(active) .. ")")
end

Events.OnGameStart.Add(HitmanPatches.GunFighter)
