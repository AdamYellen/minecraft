local component = require("component")
local robot = require("robot")
local sides = require("sides")
local modem = component.modem
local inventory = component.inventory_controller
local term = require("term")
local event = require("event")
local keyboard = require("keyboard")

-- constants
local colorError = 0xFF0000
local colorStartup = 0xFFFFFF
local colorStop = 0x111111
local colorCharging = 0xFFCC33
local colorSearching = 0x66CC66
local colorDelivering = 0x6699FF
local waypointHomeName = "home"
local neededCropSticks = 48

-- globals
-- waypointHome = {}
-- pargs = {...}
local mainLoopDone = false
local waypointsOffset = -- offsets from home
{
    ["HOME"] = { 0, 0, 0 },
    ["PARENT1"] = { 2, 0, 0 },
    ["PARENT2"] = { 4, 0, 0 },
    ["CHILD"] = { 3, 0, 0 },
    ["ANALYZER"] = { 3, 0, 1 },
    ["OUTPUT"] = { 6, 0, 0 },
    ["SUPPLIES"] = { -1, 0, 0 },
    ["TRASH"] = { -2, 0, 0 },
}
local waypointsAbsolute = {}
local toolSlots =
{
    ["CLIPPER"] = 1,
    ["CROPS"] = 2,
    ["SEEDS"] = 3,
    ["ITEMS"] = 4,  -- ALWAYS last
}

function printMembers(var)
    for key,value in pairs(var) do
      print("found member " .. key .. value);
    end
  end
  
local function printError(msg)
    robot.setLightColor(colorError)
    print(msg)
end

-- find our home
local function findHomeWaypointRelative()
    local waypointList = component.navigation.findWaypoints(30)

    -- locate our waypoint label
    for i=1,#waypointList,1
    do
        local waypoint = waypointList[i]
        if waypoint.label == waypointHomeName
        then
            return waypoint.position
        end
    end

    return nil
end

local function findHomeWaypointAbsolute()
    local homeOffset = findHomeWaypointRelative()
    if homeOffset ~= nil
    then
        local currentPosX, currentPosY, currentPosZ = component.navigation.getPosition()
        if currentPosX ~= nil
        then
            return { homeOffset[1] + currentPosX, homeOffset[2] + currentPosY, homeOffset[3] + currentPosZ }
        end
    end
end

local turnFunctions =
{
    [sides.east] =
    {
        [sides.east] = robot.name,
        [sides.west] = robot.turnAround,
        [sides.north] = robot.turnLeft,
        [sides.south] = robot.turnRight
    },
    [sides.west] =
    {
        [sides.west] = robot.name,
        [sides.east] = robot.turnAround,
        [sides.south] = robot.turnLeft,
        [sides.north] = robot.turnRight
    },
    [sides.north] =
    {
        [sides.north] = robot.name,
        [sides.south] = robot.turnAround,
        [sides.west] = robot.turnLeft,
        [sides.east] = robot.turnRight
    },
    [sides.south] =
    {
        [sides.south] = robot.name,
        [sides.north] = robot.turnAround,
        [sides.east] = robot.turnLeft,
        [sides.west] = robot.turnRight
    },
}

local function moveRelativeXZ(arg, sidePos, sideNeg)
    if arg == 0
    then
        return
    elseif arg > 0
    then
        turnFunctions[component.navigation.getFacing()][sidePos]()
    else
        turnFunctions[component.navigation.getFacing()][sideNeg]()
    end

    arg = math.abs(arg)
    for _=1,arg
    do
        local result, reason = robot.forward()
        if not result
        then
            printError("Failed to moveRelativeXZ: " .. reason)
            if robot.up()
            then
                robot.down()
            elseif robot.down()
            then
                robot.up()
            end
            robot.forward()
        end
    end
end

local function moveRelativeY(arg)
    if arg == 0
    then
        return true
    elseif arg < 0
    then
        arg = math.abs(arg)
        for _=1,arg
        do
            result, reason = robot.down()
            if not result
            then
                printError("Failed to moveRelativeY: " .. reason)
            end
        end
    else
        arg = math.abs(arg)
        for _=1,arg
        do
            result, reason = robot.up()
            if not result
            then
                printError("Failed to moveRelativeY: " .. reason)
            end
        end
    end
end

local function moveRelative(offset)
    local target = offset

    moveRelativeXZ(offset[1], sides.east, sides.west)
    moveRelativeXZ(offset[3], sides.south, sides.north)
    moveRelativeY(offset[2])
    return true
end

local function moveAbsolute(pos)
    local offset = {}

    local currentPosX, currentPosY, currentPosZ = component.navigation.getPosition()
    if currentPosX ~= nil
    then
        offset[1] = pos[1] - currentPosX
        offset[2] = pos[2] - currentPosY
        offset[3] = pos[3] - currentPosZ
        return moveRelative(offset)
    end
    return false
end

local function moveToTarget(coords)
    if moveRelative(coords)
    then
        return true
    end
    return false
end

local function moveToHome(args)
    return moveAbsolute(waypointsAbsolute.HOME)
end

local function plantSeed()
    robot.select(toolSlots.SEEDS)
    inventory.equip()
    robot.useDown()
    inventory.equip()
end

local function plantCrops()
    robot.select(toolSlots.CROPS)
    inventory.equip()
    robot.useDown()
    inventory.equip()
end

local function plow()
    robot.swingDown()
end

local function findNextItemInChest(side, item, offset)
    local chestSize = inventory.getInventorySize(side)
    for i=offset,chestSize,1
    do
        local contents = inventory.getStackInSlot(sides.down, i)
        if contents ~= nil
        then
            if string.find(contents.name, item) ~= nil
            then
                return i, contents.size
            end
        end
    end
    return 0
end

local function restockInventory()
    moveAbsolute(waypointsAbsolute.HOME)
    moveAbsolute(waypointsAbsolute.SUPPLIES)
    robot.select(toolSlots.CLIPPER)
    robot.dropDown()
    robot.select(toolSlots.CROPS)
    robot.dropDown()
    robot.select(toolSlots.SEEDS)
    robot.dropDown()

    -- find our supplies
    local sourceSlot = findNextItemInChest(sides.down, "agricraft.clipper", 1)
    if sourceSlot > 0
    then
        --  we need our clipper
        robot.select(toolSlots.CLIPPER)
        if inventory.suckFromSlot(sides.down, sourceSlot, 1)
        then
            -- grab some crop sticks
            local retryCount = 0
            robot.select(toolSlots.CROPS)
            local totalCrops = robot.count()
            while totalCrops < neededCropSticks and retryCount < 3
            do
                -- crop sticks can be scattered in the supply chest
                -- need to keep gathering until we have enough, but retry only a limited number of times
                sourceSlot = findNextItemInChest(sides.down, "agricraft.crop_sticks", 1)
                if sourceSlot > 0
                then
                    if inventory.suckFromSlot(sides.down, sourceSlot, neededCropSticks-totalCrops)
                    then
                        -- got some, keep trying
                        totalCrops = robot.count()
                        retryCount = 0
                    else
                        retryCount = retryCount + 1
                    end
                else
                    retryCount = retryCount + 1
                end
            end
            
            -- do we have enough crop sticks?
            robot.select(toolSlots.CROPS)
            if robot.count() >= neededCropSticks
            then
                -- need a pair of seeds
                local sourceSlot = 1
                local sourceCount
                while true
                do
                    sourceSlot, sourceCount = findNextItemInChest(sides.down, "seed", sourceSlot)
                    if sourceSlot > 0
                    then
                        -- we're looking for a pair of seeds
                        if sourceCount >= 2
                        then
                            -- only pull 2 seeds from any matching slot
                            robot.select(toolSlots.SEEDS)
                            if inventory.suckFromSlot(sides.down, sourceSlot, 2)
                            then
                                if robot.count() == 2
                                then
                                    return true
                                else
                                    -- no good, drop them back into the supply chest
                                    robot.dropDown()
                                end
                            end
                        end
                        -- try the next slot in the supply chest
                        sourceSlot = sourceSlot + 1
                    else
                        -- either there are no seeds or we reached the end of the supply chest
                        break
                    end
                end
                printError("Error: can't find starting seeds!")
                return false
            else
                printError("Error: not enough crop sticks!")
                return false
            end
        end
    end
    printError("Error: can't find our clipper!")
    return false
end

local function dumpInventory()
    moveAbsolute(waypointsAbsolute.HOME)
    moveAbsolute(waypointsAbsolute.TRASH)
    local slot = robot.select()
    -- starting with our seed slot dump our inventory in the trash
    -- NOTE: don't call this unless you are OK with the source seeds being trashed
    for i=toolSlots.SEEDS,robot.inventorySize(),1 do
        robot.select(i)
        robot.dropDown()
    end
    robot.select(slot)
    return true
end

local function analyzeChild()
    -- TODO: needs to check for errors
    -- TODO: needs more resilient error handling
    moveAbsolute(waypointsAbsolute.CHILD)
    robot.select(toolSlots.CLIPPER)
    inventory.equip()
    robot.select(toolSlots.ITEMS)
    robot.useDown()
    -- os.sleep(1)
    robot.useDown()
    robot.select(toolSlots.CLIPPER)
    inventory.equip()
    moveAbsolute(waypointsAbsolute.ANALYZER)
    robot.select(toolSlots.ITEMS)
    inventory.dropIntoSlot(sides.down, 1)
    return true
end

local function pickupAnalyzedSeeds()
    -- if we still have any source seeds in our seed slot, trash them now
    robot.select(toolSlots.SEEDS)
    if robot.count() > 0
    then
        moveAbsolute(waypointsAbsolute.HOME)
        if moveAbsolute(waypointsAbsolute.TRASH)
        then
            if not robot.dropDown()
            then
                printError("Error: failed to drop seeds -- inventory full?")
                return false
            end
        else
            printError("Error: failed to navigate")
            return false
        end
    end

    if moveAbsolute(waypointsAbsolute.ANALYZER)
    then
        if inventory.suckFromSlot(sides.down, 1)
        then
            -- the assumption here is that we only retrieve two seeds from the analyzer
            -- they are either 10/10/10 and will be dropped into the output chest or they will become the next parents
            return true
        else
            printError("Error: failed to retrieve seeds")
        end
    else
        printError("Error: failed to navigate")
    end
    return false
end

local function storeAnalyzedSeeds()
    robot.select(toolSlots.SEEDS)
    if robot.count() > 0
    then
        moveAbsolute(waypointsAbsolute.HOME)
        if moveAbsolute(waypointsAbsolute.OUTPUT)
        then
            if not robot.dropDown()
            then
                printError("Error: failed to drop seeds -- inventory full?")
                return false
            end
        else
            printError("Error: failed to navigate")
            return false
        end
    end
    return true
end

local function plantCrossCrops()
    moveAbsolute(waypointsAbsolute.CHILD)
    plantCrops()
    plantCrops()
    return true
end

local function initializeField()
    -- we need crop sticks on each location for the Computer Controlled Seed Analyzers to recognize their orientation
    moveAbsolute(waypointsAbsolute.PARENT1)
    plow()
    plantCrops()
    moveAbsolute(waypointsAbsolute.CHILD)
    plow()
    plantCrops()
    moveAbsolute(waypointsAbsolute.PARENT2)
    plow()
    plantCrops()
    return true
end

local function plowField(args)
    moveAbsolute(waypointsAbsolute.PARENT1)
    plow()
    plantCrops()
    plantSeed()
    moveAbsolute(waypointsAbsolute.CHILD)
    plow()
    moveAbsolute(waypointsAbsolute.PARENT2)
    plow()
    plantCrops()
    plantSeed()
    return true
end

local function stopMainLoop(args)
    mainLoopDone = true
    return true
end

local function mainLoop()
    local functionTable = 
    {
        ["TERM"] = stopMainLoop,
        ["HOME"] = moveToHome,
        ["PLOW"] = plowField,
        ["INIT"] = initializeField,
        ["ANALYZE"] = analyzeChild,
        ["PICKUP_ANALYZED"] = pickupAnalyzedSeeds,
        ["DUMP"] = dumpInventory,
        ["RESTOCK"] = restockInventory,
        ["CROSS"] = plantCrossCrops,
        ["STORE_ANALYZED"] = storeAnalyzedSeeds,
        ["GET"] = getSetting,
        ["SET"] = setSetting,
    }

    print("Hold Alt to break")
    while mainLoopDone ~= true
    do
        if not keyboard.isAltDown()
        then
            -- wait 1 second for any message to arrive
            _,_,sender,_,_,message = require("event").pull(1, "modem")
            if message ~= nil
            then
                -- the modem doesn't like it if we hit it too quickly?
                os.sleep(0)

                -- strip special characters including LF/CR
                local messageStripped = string.gsub(message, "%c", "")

                -- gather remaining args
                local cmdArgs = {}
                for p in messageStripped:gmatch("([^,%s]+),?")
                do
                    table.insert(cmdArgs, p)
                end

                -- pull out the command from the arguments table
                local command = table.remove(cmdArgs, 1)
                print("command:" .. command)

                -- locate command in our function table
                local cmdResult
                local func = functionTable[command]
                if(func)
                then
                    cmdResult = func(table.unpack(cmdArgs))
                    modem.send(sender, 8001, tostring(cmdResult))
                    os.sleep(1)
                else
                    -- fallback, execute command via shell
                    table.insert(cmdArgs, 1, command)
                    cmdResult = os.execute(table.concat(cmdArgs, ' '))
                    modem.send(sender, 8001, tostring(cmdResult))
                    os.sleep(1)
                end
            end
        else
            mainLoopDone = true
        end
    end
    print("exiting mainLoop")
end

local function initNavigation()
    local homeOffset = findHomeWaypointRelative()
    if homeOffset ~= nil
    then
        print("Found home waypoint @ x:" .. homeOffset[1] .. ", y:" .. homeOffset[2] .. ", z:" .. homeOffset[3])
        local homeLoc = findHomeWaypointAbsolute()

        -- calculate absolute poisition of our waypoints
        for name, values in pairs(waypointsOffset) do
            waypointsAbsolute[name] = {}
            waypointsAbsolute[name][1] = homeLoc[1] + waypointsOffset[name][1]
            waypointsAbsolute[name][2] = homeLoc[2] + waypointsOffset[name][2]
            waypointsAbsolute[name][3] = homeLoc[3] + waypointsOffset[name][3]
        end

        return true
    end
    return false
end

local function unInitNavigation()
end

local function init()
    robot.setLightColor(colorStartup)
    if initNavigation()
    then
        modem.close()
        modem.open(8001) -- tonumber(pargs[1]))
        if modem.isOpen(8001)
        then
            modem.setStrength(400)
            return true
        else
            printError("Error: Failed to open modem")
        end
        unInitNavigation()
    else
        printError("Error: Failed to initialize navigation system")
    end
    return false
end

local function unInit()
    modem.close()
    robot.setLightColor(colorStop)
end

local function main()
    if init()
    then
        mainLoop()
        unInit()
    else
        printError("Error: Failed to initialize robot")
    end
end

main()