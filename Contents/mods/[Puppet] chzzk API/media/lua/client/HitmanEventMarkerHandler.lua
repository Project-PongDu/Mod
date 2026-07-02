HitmanEventMarkerHandler = {}
HitmanEventMarkerHandler.markers = {}

-- this is now called by server for all clients
-- it also handles duration
function HitmanEventMarkerHandler.set(eventID, icon, duration, posX, posY, color, desc)

    local player = getSpecificPlayer(0)
    local marker = HitmanEventMarkerHandler.markers[eventID]

    if not marker and duration > 0 then
        local dist = HitmanUtils.DistTo(posX, posY, player:getX(), player:getY())
        if dist <= HitmanEventMarker.maxRange then
            --print(" -- not marker: generating")
            local oldX
            local oldY
            local pModData = player:getModData()["HitmanEventMarkerPlacement"]
            if pModData then
                oldX = pModData[1]
                oldY = pModData[2]
            end
            local screenX = oldX or (getCore():getScreenWidth()/2) - (HitmanEventMarker.iconSize/2)
            local screenY = oldY or (HitmanEventMarker.iconSize/2)
            --print("HitmanEventMarkerHandler: generateNewMarker: "..p:getUsername().." ".."("..screenX..","..screenY..")")

            marker = HitmanEventMarker:new(eventID, icon, duration, posX, posY, player, screenX, screenY, color, desc)
            HitmanEventMarkerHandler.markers[eventID] = marker
        end
    end

    if marker then
        --print(" --- marker given duration")
        marker.textureIcon = getTexture(icon)
        marker:setDuration(duration)
        marker:update(posX, posY)
    end

end

function HitmanEventMarkerHandler.RemoveOldMarkers ()
    local markers = HitmanEventMarkerHandler.markers
    for eventId, marker in pairs(markers) do
        if marker.start + marker.duration < getGametimeTimestamp() then

            marker:setDuration(0)
            HitmanEventMarkerHandler.markers[eventId] = nil
        end
    end
end

Events.EveryTenMinutes.Add(HitmanEventMarkerHandler.RemoveOldMarkers)