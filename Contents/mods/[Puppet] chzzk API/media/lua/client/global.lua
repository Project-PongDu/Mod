local _a = {
    chosenRandomText = "",
    chosenZombieCount = 0,
    processingEvent = false,
    player = nil,
    stats = nil,
    zombieSpawnQueue = {},
    textUpdateTimer = 0,
    displayStartTime = 0,
    isTextUpdateEventAdded = false,
    elapsedTime = 0,
    rewardQueue = {},
    currentSender = ""
}
function _a.a()
    return os.date("%Y-%m-%d %H:%M:%S")
end
function _a.b(a)
    print("[PongDu] " .. _a.a() .. " - " .. tostring(a))
end
return _a
