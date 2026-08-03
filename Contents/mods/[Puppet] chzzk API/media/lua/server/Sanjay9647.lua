-- ModPatches/Sanjay9647.lua (서버 전용, media/lua/server/ 경로에만 배치)
--
-- SSAULAVI(작성자 Sanjay9647, 워크샵 2887274097) 호환성 패치.
--
-- ── 증상 ────────────────────────────────────────────────────────────────────
-- 부활한 플레이어 좀비가 알몸으로 렌더링되고, 머리모델/피부색이 다른 캐릭터로
-- 바뀌며, 혈흔 텍스처가 계속 깜빡인다. 알파테스트#2에서 재현 확인.
--
-- ── 근본 원인 ────────────────────────────────────────────────────────────────
-- SSAULAVI의 media/lua/shared/NPCs/Ssaulavi41_ZombiesZoneDefinition.lua:
--
--   if isServer() then
--       Events.OnServerStarted.Add(CallSandboxVars)
--   else
--       Events.OnPostDistributionMerge.Add(CallSandboxVars);
--   end
--
-- CallSandboxVars()는 ZombiesZoneDefinition.Default에 커스텀 outfit
-- (Shihan / Hitokiri / Toukenshuushuuka) 3개를 등록한다. 이 3개는
-- PersistentOutfits의 전체 outfit 목록(m_all)에 새 항목으로 추가되고,
-- 그 뒤에 오는 모든 항목(플레이어가 좀비로 부활할 때 쓰는
-- ReanimatedPlayer 포함)의 인덱스를 3칸 밀어낸다.
--
-- 문제는 이 등록이 클라와 서버에서 서로 다른 시점에 일어난다는 것이다.
-- OnPostDistributionMerge(IsoWorld.java:1577)는 outfit 목록을 실제로
-- 조립하는 PersistentOutfits.init()(IsoWorld.java:1688)보다 먼저
-- 발화해서 클라에서는 3개가 정상적으로 포함된다. 반면 OnServerStarted
-- (GameServer.java:1509)는 IsoWorld.instance.init()(GameServer.java:770)
-- 보다 한참 뒤에 발화하기 때문에, 서버에서는 목록이 이미 조립된 뒤에야
-- 3개가 추가된다 -- 즉 서버 쪽 outfit 목록에는 이 3개가 아예 안 들어간다.
--
-- 결과: 서버가 보낸 부활 플레이어 pid(outfit 인덱스)를 클라가 3칸 밀린
-- 엉뚱한 outfit으로 해석해 그 outfit의 dressInNamedOutfit() 경로를 타고,
-- 이 경로는 알몸/얼굴 소실/혈흔 재생성을 유발한다 (PongDuReanimatedOutfit.lua
-- 상단 주석의 "원인 B" 참조).
--
-- ── 패치 방법 ────────────────────────────────────────────────────────────────
-- 서버에서만 CallSandboxVars를 OnServerStarted에서 떼어 OnPostDistributionMerge로
-- 옮긴다. 클라 쪽은 원래도 올바르게 등록돼 있으므로 손대지 않는다.
--
-- CallSandboxVars는 SSAULAVI의 shared 파일이 local 없이 선언한 전역 함수라
-- 여기서 이름으로 직접 참조할 수 있다 -- SSAULAVI 원본 파일을 복제하거나
-- Shihan/Hitokiri/Toukenshuushuuka 목록을 우리 쪽에서 다시 정의하지 않는다.
-- SSAULAVI가 이 목록을 나중에 바꿔도(이름 추가/제거) 우리 패치는 그대로
-- 작동한다 -- 이벤트 재배선만 할 뿐 원본 로직을 복제하지 않기 때문이다.
--
-- ── 전제조건: 로드 순서 ──────────────────────────────────────────────────────
-- 이 패치가 성립하려면 이 파일이 로드되는 시점에 SSAULAVI의 shared 파일이
-- 이미 로드되어 CallSandboxVars가 전역으로 존재하고, Events.OnServerStarted에
-- 이미 등록까지 끝난 상태여야 한다. 두 이벤트(OnPostDistributionMerge/
-- OnServerStarted) 모두 전체 모드의 Lua 로드가 끝난 뒤에야 발화하므로,
-- 이벤트 핸들러로 감싸는 방식으로는 이 순서를 보장할 수 없다 -- 순수하게
-- "SSAULAVI가 우리보다 먼저 로드되는가"라는 모드 로드 순서에 달려 있다.
-- mod.info의 requiredMods로 최대한 순서를 유도하되, 그것만으로 순서가
-- 강제되지 않는 PZ 버전/런처 조합이 있을 수 있어 아래 방어 코드가 필요하다.
--
-- 만약 이 파일이 SSAULAVI보다 먼저 로드돼 CallSandboxVars를 못 찾으면,
-- 조용히 실패하지 않고 로그를 남긴다. 그 로그가 보이면 서버 Mods= 목록에서
-- SSAULAVI(Sanjay9647)를 퐁듀보다 앞에 두도록 순서를 조정해야 한다.

if isServer() then

PongDuPatches = PongDuPatches or {}

PongDuPatches.Sanjay9647 = function()
    if not getActivatedMods():contains("Sanjay9647") then return end

    if type(CallSandboxVars) ~= "function" then
        print("[PongDu][ModPatch] Sanjay9647 detected but CallSandboxVars global not found -- "
            .. "load order issue (SSAULAVI must load before PongDu) or SSAULAVI updated its code. "
            .. "Patch NOT applied; naked reanimated player bug may occur.")
        return
    end

    Events.OnServerStarted.Remove(CallSandboxVars)
    Events.OnPostDistributionMerge.Add(CallSandboxVars)
    print("[PongDu][ModPatch] Sanjay9647 (SSAULAVI) rewired: CallSandboxVars moved from "
        .. "OnServerStarted to OnPostDistributionMerge")
end

PongDuPatches.Sanjay9647()

end
