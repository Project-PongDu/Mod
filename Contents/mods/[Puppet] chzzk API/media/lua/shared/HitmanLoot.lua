require "HitmanCompatibility"
-- register modded loot items by adding them to tables below

HitmanLoot = HitmanLoot or {}

HitmanLoot.MakeItem = function(name, chance, quantity) 
    local item = {}
    item.name = HitmanCompatibility.GetLegacyItem(name)
    item.chance = chance
    return item
end

HitmanLoot.FillContainer = function(container, itemTab, itemNo)
    for k, v in pairs(itemTab) do
        local r = ZombRand(101)
        if r <= v.chance then
            for i=0, ZombRand(itemNo) do
                --container:AddItem(v.name)
                -- local item = InventoryItemFactory.CreateItem(v.name)
                -- container:addItem(item)

                local item = container:AddItem(v.name)
                if item then
                    container:addItemOnServer(item)
                end
            end
        end
    end
end

HitmanLoot.Items = HitmanLoot.Items or {}

-- HITMAN INVENTORY LOOT
-- essentials
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.WaterBottle", 80))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.HandTorch", 100))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.TinOpener", 11))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Hammer", 20))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Wrench", 20))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.PipeWrench", 10))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Scissors", 10))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Screwdriver", 22))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Spoon", 40))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Pencil", 35))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.WeldingMask", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.BlowTorch", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Needle", 5))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Soap2", 8))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Molotov", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.PipeBomb", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Bandage", 21))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Pills", 9))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Lighter", 21))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.HolsterSimple", 11))

if HitmanCompatibility.GetGameVersion() < 42 and not getActivatedMods():contains("Smoker") then
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cigarettes", 33))
end

-- food items
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.TinnedBeans", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedCarrots2", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedChili", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedCorn", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedCornedBeef", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedFruitCocktail", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedMushroomSoup", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedPeaches", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedPeas", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedPineapple", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedPotato2", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedSardines", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.TinnedSoup", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedBolognese", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedTomato2", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.TunaTin", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Salami", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Apple", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Pear", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cherry", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Grapes", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Onion", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.MushroomGeneric1", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.MushroomGeneric2", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.RedRadish", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Potato", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Cabbage", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedBroccoli", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedCabbage", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedCarrots", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedPotato", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedTomato", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedEggplant", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CannedBellPepper", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.BeerCan", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Whiskey", 3))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.JamFruit", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Coffee2", 4))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Teabag2", 4))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Gum", 2))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Peppermint", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.GummyWorms", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Jujubes", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.HiHis", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.CandyFruitSlices", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Crisps", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Crisps2", 1))
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Crisps3", 1))

if HitmanCompatibility.GetGameVersion() >= 42 then
    table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.Crisps4", 1))
end

-- valuables
table.insert(HitmanLoot.Items, HitmanLoot.MakeItem("Base.PetrolCan", 1))

-- HITMAN BASE LOOT
HitmanLoot.FreshFoodItems = HitmanLoot.FreshFoodItems or {}
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.RedRadish", 15))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Potato", 45))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Leek", 25))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Onion", 25))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Cabbage", 25))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Broccoli", 15))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.BellPepper", 10))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Lettuce", 10))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Pumpkin", 8))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Tomato", 31))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Jalapeno", 10))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Eggplant", 5))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Avocado", 10))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Mango", 7))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.MushroomGeneric3", 20))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Apple", 15))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Grapefruit", 15))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Grapes", 18))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Pear", 21))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Banana", 15))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Rabbitmeat", 40))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.FrogMeat", 10))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Steak", 5))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.MeatPatty", 7))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.MuttonChop", 7))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Egg", 20))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Milk", 22))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Cheese", 75))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Yoghurt", 9))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Butter", 44))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.BeerBottle", 66))
table.insert(HitmanLoot.FreshFoodItems, HitmanLoot.MakeItem("Base.Wine", 18))

HitmanLoot.CannedFoodItems = HitmanLoot.CannedFoodItems or {}
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.TinnedBeans", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedCarrots2", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedChili", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedCorn", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedCornedBeef", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedFruitCocktail", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedMushroomSoup", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedPeaches", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedPeas", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedPineapple", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedPotato2", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedSardines", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.TinnedSoup", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedBolognese", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedTomato2", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.TunaTin", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedBroccoli", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedCabbage", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedCarrots", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedPotato", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedTomato", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedEggplant", 10))
table.insert(HitmanLoot.CannedFoodItems, HitmanLoot.MakeItem("Base.CannedBellPepper", 10))


HitmanLoot.Ammo = HitmanLoot.Ammo or {}
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.223Box", 5))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.308Box", 9))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets38Box", 10))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets44Box", 13))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets45Box", 10))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.556Box", 11))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets9mmBox", 11))
table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.ShotgunShellsBox", 8))

if getActivatedMods():contains("firearmmod") or getActivatedMods():contains("firearmmodRevamp") then
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets4440Box", 5))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets357Box", 5))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.762x51Box", 5))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.762x39Box", 5))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets22Box", 5))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets3006Box", 5))
end

if getActivatedMods():contains("Guns93") then
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.3006Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.792Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.30CarBox", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.76239Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.3030Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.22Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.25Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.380Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.45LCBox", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.357Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.10mmBox", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.SlugBox", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.40Box", 4))
    table.insert(HitmanLoot.Ammo, HitmanLoot.MakeItem("Base.Bullets38Box", 4))
end
