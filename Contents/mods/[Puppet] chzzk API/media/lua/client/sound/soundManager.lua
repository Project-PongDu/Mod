local _a = {}
function _a.a()
    local sounds = {"jump1", "jump2", "jump3", "jump4", "jump5", "jump6"}
    getSoundManager():PlaySound(sounds[ZombRand(1, #sounds)], false, 1.0)
end
function _a.b()
    local sounds = {"gunfire1", "gunfire2", "gunfire3", "gunfire4"}
    getSoundManager():PlaySound(sounds[ZombRand(1, #sounds)], false, 1.0)
end
return _a
