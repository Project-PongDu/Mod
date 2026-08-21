local _a = {}
-- 좌표 기준 세이프존(세이프하우스 사각형 +10타일) 판정.  [public name: .c]
-- _a.a 와 달리 그리드 스퀘어 로딩이 필요 없다 -- 세이프하우스 목록은 MP에서도
-- 클라에 동기화돼 있어서 아직 스트리밍되지 않은 먼 좌표도 그대로 판정된다.
-- (랜덤 텔레포트처럼 100~200타일 밖 후보를 텔포 전에 걸러내야 하는 쪽 전용.)
function _a.c(b, c)
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
function _a.a(a)
    local b = a:getX()
    local c = a:getY()
    local d = getCell():getGridSquare(b, c, 0)
    if not d then return false end
    return _a.c(b, c)
end
function _a.b()
    local a = ZombRand(0, 2)
    if a == 0 then return ZombRand(-4, -1) else return ZombRand(2, 5) end
end
return _a
