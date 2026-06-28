local _a = {}
local _b = require("utils/zone")
local _c = {}
local _d = false
local _e = {
[11] = {clanId = "1a9db80f-9f5e-4e9e-a842-a9ca9a6bc220", size = 4, ...},  -- 2만 melee
[15] = {clanId = "7b0273ef-54db-444f-97f9-bf2b22e7fe38", size = 2, ...},  -- 4만 ranged
}
local function _f(a, player)
    local angle = ZombRandFloat(0, 2 * math.pi)
    return {
        cid              = a.clanId,
        size             = a.size,
        enemyBehaviour   = 2,
        friendlyChance   = 0,
        hasPistolChance  = a.pistol,
        pistolMagCount   = 2,
        hasRifleChance   = a.rifle,
        rifleMagCount    = 1,
        x = math.floor(player:getX() + 20 * math.cos(angle)),
        y = math.floor(player:getY() + 20 * math.sin(angle)),
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
        sendClientCommand("Spawner", "Clan", cfg)
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
