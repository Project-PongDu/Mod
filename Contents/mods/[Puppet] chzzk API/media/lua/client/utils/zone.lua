local _a = {}
function _a.a(a)
    local b = a:getX()
    local c = a:getY()
    local d = getCell():getGridSquare(b, c, 0)
    if not d then return false end
    local e = SafeHouse.getSafehouseList()
    if not e or e:size() == 0 then return false end
    for f = 0, e:size() - 1 do
        local g = e:get(f)
        if g then
            if b >= g:getX() - 10 and b < g:getX2() + 10 and c >= g:getY() - 10 and c < g:getY2() + 10 then
                return true
            end
        end
    end
    return false
end
function _a.b()
    local a = ZombRand(0, 2)
    if a == 0 then return ZombRand(-4, -1) else return ZombRand(2, 5) end
end
return _a
