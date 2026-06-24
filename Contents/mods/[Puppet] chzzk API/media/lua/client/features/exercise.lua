local _a = {}
local _b = require("global")

function ISFitnessAction:start()
    self.character:setVariable("ExerciseType", self.exercise)
    self.character:reportEvent("EventFitness")
    self.character:clearVariable("ExerciseStarted")
    self.character:clearVariable("ExerciseEnded")
    self.character:reportEvent("EventUpdateFitness")
end
function ISFitnessAction:new(a, b, c, d, e)
    local f = {}
    setmetatable(f, self)
    self.__index = self
    f.character = a
    f.stopOnWalk = false
    f.stopOnRun = false
    f.fitnessUI = d
    f.exercise = b
    f.timeToExe = c
    f.exeData = e
    f.switchTime = 5
    f.switchHandUsed = "right"
    f.startMS = getGameTime():getCalender():getTimeInMillis()
    f.endMS = f.startMS + (c * 60000)
    f.maxTime = 5000000
    f.fitness = a:getFitness()
    f.repnb = 0
    f:setFitnessSpeed()
    f.fitness:setCurrentExercise(e.type)
    f.caloriesModifier = 3
    return f
end
function ISFitnessAction:stop()
    self.character:PlayAnim("Idle")
    self.character:setVariable("ExerciseEnded", true)
    setGameSpeed(1)
    ISBaseTimedAction.stop(self)
end
function ISFitnessAction:update()
    if self.character:getMoodles():getMoodleLevel(MoodleType.Endurance) > ISFitnessUI.enduranceLevelTreshold then
        self.character:setVariable("ExerciseStarted", false)
        self.character:setVariable("ExerciseEnded", true)
    end
    if getGameTime():getCalender():getTimeInMillis() > self.endMS then
        self.character:setVariable("ExerciseStarted", false)
        self.character:setVariable("ExerciseEnded", true)
    end
    self.character:setMetabolicTarget(self.exeData.metabolics)
end

function _a.a()
    local a = getPlayer()
    if a then
        a:setBlockMovement(true)
        a:StopAllActionQueue()
        a:PlayAnim("Idle")
    end
end
function _a.b()
    local a = getPlayer()
    if a then
        a:setBlockMovement(false)
    end
end
function _a.c()
    local a = getPlayer()
    if not a then return end
    if a:isAiming() then
        a:nullifyAiming()
    end
    _a.a()
    local b = "burpees"
    local c = 10
    local d = {type = "Strength", item = nil, prop = "switch", metabolics = 1.0}
    local function e(f)
        local g = ISFitnessAction:new(a, b, c, nil, d)
        if g then
            local h = 0
            local function i()
                h = h + 1
                if h >= 20 then
                    g:start()
                    Events.OnTick.Remove(i)
                    local j = 0
                    local function k()
                        j = j + 1
                        if j >= 90 then
                            g:stop()
                            Events.OnTick.Remove(k)
                            if f then f() end
                        end
                    end
                    Events.OnTick.Add(k)
                end
            end
            Events.OnTick.Add(i)
        else
            if f then f() end
        end
    end
    e(function()
        e(function()
            _b.processingEvent = false
            _a.b()
        end)
    end)
end
return _a
