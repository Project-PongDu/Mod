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
    local b = getFileWriter("log.txt", true, true)
    b:write(_a.a() .. " - " .. a .. "\n")
    b:close()
end
return _a
