HitmanPost = HitmanPost or {}

function HitmanPost.GuardToggle(player, x, y, z)
    local args = {x=x, y=y, z=z, type="guard"}
    sendClientCommand(player, 't3_Commands', 'PostToggle', args)
end

function HitmanPost.Update(player, post)
    sendClientCommand(player, 't3_Commands', 'PostUpdate', post)
end

function HitmanPost.At(character, ptype)
    local gmd = GetHitmanModData()
    local px = math.floor(character:getX() )
    local py = math.floor(character:getY())
    local pz = character:getZ()
    for id, gp in pairs(gmd.Posts) do
        if gp.x == px and gp.y == py and gp.z == pz and (not ptype or gp.type == ptype) then return true end
    end
    return false
end

function HitmanPost.GetAll()
    local gmd = GetHitmanModData()
    return gmd.Posts
end

function HitmanPost.GetInRadius(character, ptype, radius)
    local gmd = GetHitmanModData()
    local px = character:getX()
    local py = character:getY()

    local nearPosts = {}
    for id, gp in pairs(gmd.Posts) do
        local dist = HitmanUtils.DistTo(gp.x, gp.y, px, py)
        if dist < radius and (not ptype or gp.type == ptype) then
            nearPosts[id] = gp
        end
    end
    return nearPosts
end

function HitmanPost.GetClosestFree(character, ptype, radius)
    local gmd = GetHitmanModData()
    local px = character:getX()
    local py = character:getY()

    local bestDist = radius
    local bestPost
    for id, gp in pairs(gmd.Posts) do
        local dist = HitmanUtils.DistTo(gp.x, gp.y, px, py)
        if dist <= radius then
            if dist < bestDist and (not ptype or gp.type == ptype) then
                local square = getCell():getGridSquare(gp.x, gp.y, gp.z)
                if square then
                    if not square:getZombie() then
                        bestPost = gp
                        bestDist = dist
                    end
                end
            end
        end
    end
    return bestPost
end

function HitmanPost.Get(x, y, z, ptype)
    local gmd = GetHitmanModData()
    local id = x .. "-" .. y .. "-" .. z
    if gmd.Posts[id] and (not ptype or gmd.Posts[id].type == ptype) then
        return gmd.Posts[id]
    end
end

function HitmanPost.Render()
    local playerObj = getSpecificPlayer(0)
	local bo = HitmanZSPosts:new("", "", playerObj)
	getCell():setDrag(bo, playerObj:getPlayerNum())
end

function HitmanPost.OnKeyPressed(keynum)
    if keynum == HitmanCompatibility.GetGuardpostKey() then
        HitmanPost.Render()
    end
end

Events.OnKeyPressed.Add(HitmanPost.OnKeyPressed)
