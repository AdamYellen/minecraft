local component = require("component")
-- local adapter = component.adapter
local transposer = component.transposer
local keyboard = require("keyboard")

for address, componentType in component.list()
do
    -- print(tostring(address), tostring(componentType))
end

-- local databaseAddress
-- for k,_ in component.list("database") do databaseAddress = k break end

-- local database = component.database

-- local entryNum = {}
-- for i = 1, 81 do
--   local item = database.get(i)
--   if item
--   then
--     entryNum[item.name] = i
--     print(item.name)
--   else
--     print("null")
--   end
  
-- end

local trashTable =
{
    ['minecraft:arrow'] = true,
    ['minecraft:bow'] = true,
    ['minecraft:carrot'] = true,
    ['minecraft:coal'] = true,
    ['minecraft:dye'] = true,
    ['minecraft:ender_pearl'] = true,
    ['minecraft:firework_charge'] = true,
    ['minecraft:glownstone_dust'] = true,
    ['minecraft:gold_nugget'] = true,
    ['minecraft:potato'] = true,
    ['minecraft:potion'] = true,
    ['minecraft:pumpkin'] = true,
    ['minecraft:redstone'] = true,
    ['minecraft:slime_ball'] = true,
    ['minecraft:stick'] = true,
    ['minecraft:string'] = true,
    ['minecraft:sugar'] = true,
    ['minecraft:web'] = true,
    ['minecraft:wheat'] = true,
    ['minecraft:chainmail_helmet'] = true,
    ['minecraft:chainmail_chestplate'] = true,
    ['minecraft:chainmail_leggings'] = true,
    ['minecraft:chainmail_boots'] = true,
    ['mysticalagriculture:crafting'] = true,
    ['actuallyadditions:item_misc'] = true,
    ['dungeontactics:bag_food'] = true,
    ['dungeontactics:bag_record'] = true,
    ['dungeontactics:bag_quiver'] = true,
    ['dungeontactics:bag_potion'] = true,
    ['dungeontactics:bag_arbour'] = true,
    ['dungeontactics:magic_scroll'] = true,
    ['charm:endermite_powder'] = true,
    ['quark:witch_hat'] = true,
    ['rats:piper_hat'] = true,
    ['vampirism:blood_bottle'] = true,
}

local regExTrashTable =
{
    "minecraft:wooden_.+",
    "minecraft:leather_.+",
    "minecraft:stone_.+",
    "minecraft:iron_.+",
    "minecraft:golden_.+",
    "dungeontactics:iron_.+",
    "dungeontactics:stone_.+",
    "mekanismtools:lapis.+",
    "mekanismtools:glowstone.+",
    "mekanismtools:obsidian.+",
    "mekanismtools:steel.+",
    "instrumentalmobs:.+",
}

local sourceSide = nil
local destSide = nil
local trashSide = nil

local function mainLoop()
    local mainLoopDone = false

    print("Hold Alt to break")
    while mainLoopDone ~= true
    do
        if not keyboard.isAltDown()
        then
            local sourceStacks = transposer.getAllStacks(sourceSide)
            local count = sourceStacks.count()

            for i = 1, count
            do
                local trash = false
                if sourceStacks[i].size > 0
                then
                    -- print(sourceStacks[i].name)
                    if trashTable[sourceStacks[i].name] ~= nil
                    then
                        trash = true
                    else
                        for j = 1, #regExTrashTable
                        do
                            if string.find(sourceStacks[i].name, regExTrashTable[j]) ~= nil
                            then
                                trash = true
                            end
                        end
                    end

                    if trash == false
                    then
                        transposer.transferItem(sourceSide, destSide, sourceStacks[i].size, i, 1)
                    else
                        print("Trashing", sourceStacks[i].name)
                        transposer.transferItem(sourceSide, trashSide, sourceStacks[i].size, i, 1)
                    end
                end
            end
            -- local sourceSize = transposer.getInventorySize(sourceSide)
            -- for i = 1, sourceSize do
            --     local name = transposer.get
            -- end
            os.sleep(2)
        else
            mainLoopDone = true
        end
    end
end

-- find our chest, crate, and trash

for side = 0, 5 do
    local name = transposer.getInventoryName(side)
    if name == "actuallyadditions:block_giant_chest"
    then
        sourceSide = side
    elseif name == "minecraft:chest"
    then
        destSide = side
    elseif name == "extrautils2:trashchest"
    then
        trashSide = side
    end
end

if sourceSide ~= nil and destSide ~= nil and trashSide ~= nil
then
    print("Found our things")
    mainLoop()
else
    print("Couldn't find our chests/trash")
end
