require "ISUI/ISCharacterScreen"

local function getHitmanKillCount()
    local gmd = GetHitmanModData()
    local id = HitmanUtils.GetCharacterID(getSpecificPlayer(0))
    if gmd.Kills[id] then
        return gmd.Kills[id]
    else
        return 0
    end
end

-- Backup the original render function
local originalRender = ISCharacterScreen.render

-- Override the render function
function ISCharacterScreen:render()
    -- Call the original render function to retain existing behavior
    originalRender(self)

    if SandboxVars.Hitmans.General_KillCounter then
        local h = self:getHeight() - 24
        local smallFontHgt = getTextManager():getFontFromEnum(UIFont.Small):getLineHeight()
        local offset

        local clock = UIManager.getClock()
        if clock and clock:isDateVisible() then
            offset = smallFontHgt 
        else
            offset = 0
        end

        local hitmanKills = getHitmanKillCount()
        self:drawTextRight(getText("IGUI_Hitmans_Hitmans_Killed"), 115, h + offset, 1, 1, 1, 1, UIFont.Small)
        self:drawText(tostring(hitmanKills), 115 + 10, h + offset, 1, 1, 1, 0.5, UIFont.Small)

        self:setHeightAndParentHeight(h + offset + 24)
    end
end