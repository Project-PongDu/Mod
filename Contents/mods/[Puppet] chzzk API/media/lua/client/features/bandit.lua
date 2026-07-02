local _a = {}
local _b = require("utils/zone")
local _c = {}
local _d = false
local _e = {
    [11] = {clanId = "f6e2ca8c-311e-4ee2-9fe6-1c9e14dbcd11", size = 3, pistol = 0,  rifle = 0},
    [15] = {clanId = "f6e2ca8c-311e-4ee2-9fe6-1c9e14dbcd11", size = 2, pistol = 80, rifle = 60},
}
local function _f(a, player)
    return {
        cid              = a.clanId,
        size             = a.size,
        enemyBehaviour   = 2,
        friendlyChance   = 0,
        hasPistolChance  = a.pistol,
        pistolMagCount   = 2,
        hasRifleChance   = a.rifle,
        rifleMagCount    = 1,
        x = player:getX(),
        y = player:getY(),
        z = player:getZ(),
    }
end
function _a.a(a, sender)
    local b = getPlayer()
    table.insert(_c, {wave = a, sender = sender or ""})
    if not _b.a(b) then _a.b() end
end
function _a.b()
    if _d or #_c == 0 then return end
    local a = getPlayer()
    if not a or _b.a(a) then return end
    _d = true
    local b = table.remove(_c, 1)
    local c = _e[b.wave]
    if c then
        local cfg = _f(c, a)
        local existing = {}
        if BanditZombie and BanditZombie.GetAllB then
            for id, _ in pairs(BanditZombie.GetAllB()) do existing[id] = true end
        end
        sendClientCommand("t3_Spawner", "Clan", cfg)
        if b.sender ~= "" then
            local name = b.sender .. getText("IGUI_donation_bandit_owner")
            local timeout = 600
            local function _tag()
                timeout = timeout - 1
                if timeout <= 0 then Events.OnTick.Remove(_tag) return end
                if not (BanditZombie and BanditZombie.GetAllB) then return end
                for id, _ in pairs(BanditZombie.GetAllB()) do
                    if not existing[id] then
                        existing[id] = true
                        local z = BanditZombie.GetInstanceById(id)
                        if z then z:getModData()["_cs"] = name end
                    end
                end
            end
            Events.OnTick.Add(_tag)
        end
    end
    _d = false
end
return _a
