HitmanPatches = HitmanPatches or {}

HitmanPatches.ImprovedProjectile = function()

    if getActivatedMods():contains("ImprovedProjectile") then
       
    end
end

Events.OnGameStart.Add(HitmanPatches.ImprovedProjectile)


