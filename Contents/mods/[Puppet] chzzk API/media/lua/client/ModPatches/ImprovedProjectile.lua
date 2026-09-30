HitmanPatches = HitmanPatches or {}

-- PONGDU: Improved Projectile(id ImprovedProjectile) 총탄이 공수부대원을 맞히지 않게 한다.
-- 이 모드는 IsoZombie.Hit 을 거치지 않고 setHealth/Kill 로 피해를 넣어서
-- shared/PongDuAirborneGuard.lua 의 OnHitZombie 무효화가 먹지 않는다.
-- 투사체가 매 틱 부르는 표적 탐색 전역 함수 IPPJcheckTarget(ImprovedProjectile_01_main.lua)
-- 의 결과에서 대원을 빼면 탄이 대원을 그대로 통과한다(피격 반응/피 튐도 없음).
-- 쏜 클라에서 맞은 걸로 치지 않으므로 멀티에서 다른 클라로 피해 명령도 안 나간다.
-- 반환 형식: zombieDataTable({좀비, 거리^2, 부위배율} 배열, 거리순), playerCheck, zombieNum.
-- 폭발물은 표적 탐색이 로컬 함수라 여기서 못 막는다 -> PongDuAirborneGuard.lua 의
-- OnWeaponHitCharacter 보정이 맡는다.
local ippjOrig = nil

HitmanPatches.ImprovedProjectile = function()

    if getActivatedMods():contains("ImprovedProjectile") then
        if ippjOrig or type(IPPJcheckTarget) ~= "function" then
            print("[PongDu][ModPatch] ImprovedProjectile: IPPJcheckTarget " .. (ippjOrig and "already wrapped" or "not found") .. " -- skipped")
            return
        end
        ippjOrig = IPPJcheckTarget
        IPPJcheckTarget = function(...)
            local zt, hp, n = ippjOrig(...)
            if zt and n and n > 0 then
                local kept, k = {}, 0
                for i = 1, n do
                    local e = zt[i]
                    if e and not HitmanUtils.IsAirborneTrooper(e[1]) then
                        k = k + 1
                        kept[k] = e
                    end
                end
                if k ~= n then return kept, hp, k end
            end
            return zt, hp, n
        end
        print("[PongDu][ModPatch] ImprovedProjectile: airborne troopers excluded from projectile targets")
    end
end

Events.OnGameStart.Add(HitmanPatches.ImprovedProjectile)
