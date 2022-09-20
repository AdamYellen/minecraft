local component = require("component")
local shell = require("shell")
local side = require("sides")
local terminal = require("term")
local io = require("io")
local computer = require("computer")
local modem = component.modem
local serialization = require("serialization")
local fs = require("filesystem")
local keyboard = require("keyboard")
local term = require("term")
-- inv = component.inventory_controller
-- gen = component.generator


-- https://github.com/MightyPirates/OpenComputers/blob/master-MC1.12/src/main/resources/assets/opencomputers/loot/openos/lib/sides.lua
-- https://github.com/OpenPrograms/Sangar-Programs/blob/master/drone-sort.lua
-- https://openprograms.github.io/
-- https://github.com/OpenPrograms/Kilobyte-Programs
-- https://github.com/TheRealGangsir/Gangsir_MC_LuaPrograms/blob/master/OpenComputers/WirelessCommandSender.lua
-- https://github.com/AshnakAGQ/SeedBreeder/blob/master/OpenComputers/SeedBreader.lua

local version = "1.0.1"

local seedAnalyzerParents = {}
local seedAnalyzerChild = {}
local mainLoopDone = false
local modemPort = 8001

local states =
{
    ["ERROR"] = 0,
    ["INIT"] = 1,
    ["MAIN_MENU"] = 2,
    ["START"] = 3,
    ["NEED_ANALYZERS"] = 4,
    ["NEED_SUPPLIES"] = 5,
    ["NEED_PARENTS"] = 6,
    ["NEED_CROSS_CROPS"] = 7,
    ["NEED_CHILD"] = 8,
    ["NEED_ANALYSIS"] = 9,
    ["ANALYZING"] = 10,
    ["DONE"] = 11,
}

local function tableLength(T)
  local count = 0
  for _ in pairs(T) do count = count + 1 end
  return count
end

local function printFunctions(t)
  local s={}
  local n=0
  for k in pairs(t) do
      n=n+1 s[n]=k
  end
  table.sort(s)
  for k,v in ipairs(s) do
      f = t[v]
      if type(f) == "function" then
          print(v)
      end
  end
end

local function typeof(var)
  local _type = type(var);
  if(_type ~= "table" and _type ~= "userdata") then
      return _type;
  end
  local _meta = getmetatable(var);
  if(_meta ~= nil and _meta._NAME ~= nil) then
      return _meta._NAME;
  else
      return _type;
  end
end

local function printMembers(var)
  for key,value in pairs(var) do
    print("found member " .. key .. value);
  end
end

local function printMetatable(var)
  for key,value in pairs(getmetatable(var)) do
    print(key, value);
  end
end

local function printError(message)
    print(message)
end

local function checkForFacingPair(side1, side2, soilSamples)
-- check for valid soil samples, facing each other or not
-- args: side1, side2: opposite directions (e.g. "NORTH", "SOUTH")
-- args: soilSamples[3]: nil or valid
-- returns: true, soilSample index 1, soilSample index 2 -- two valid soilSamples that face each other
-- returns: false, soilSample index -- one valid soilSample
-- returns: nil, no valid soilSamples
    if soilSamples[1][side1] ~= nil
    then
        if soilSamples[2][side2] ~= nil
        then
            return true, 1, 2
        elseif soilSamples[3][side2] ~= nil
        then
            return true, 1, 3
        end
        return false, 1
    elseif soilSamples[2][side1] ~= nil
    then
        if soilSamples[3][side2] ~= nil
        then
            return true, 2, 3
        end
        return false, 2
    elseif soilSamples[3][side1] ~= nil
    then
        return false, 3
    end
    return nil
end

local function findAnalyzers()
    local index = 1
    local analyzers = {}
    for address, componentType in component.list("agricraft_peripheral", true)
    do
        analyzers[index] = tostring(address)
        index = index + 1
    end

    if(#analyzers == 3)
    then
        local soils = {}
        for i=1,3,1
        do
            local proxy = component.proxy(analyzers[i])
            soils[i] = {}
            soils[i].NORTH = proxy.isFertile("NORTH")
            soils[i].EAST = proxy.isFertile("EAST")
            soils[i].SOUTH = proxy.isFertile("SOUTH")
            soils[i].WEST = proxy.isFertile("WEST")
        end

        -- find the two analyzers facing each other
        local possiblePairs =
        {
            { "NORTH", "SOUTH" },
            { "SOUTH", "NORTH" },
            { "EAST", "WEST" },
            { "WEST", "EAST" },
        }
        for i=1,4,1
        do
            local foundMatch, match1, match2
            foundMatch, match1, match2 = checkForFacingPair(possiblePairs[i][1], possiblePairs[i][2], soils)
            if foundMatch ~= nil
            then
                if foundMatch == true
                then
                    seedAnalyzerParents[1] = { proxy = component.proxy(analyzers[match1]), side = possiblePairs[i][1] }
                    seedAnalyzerParents[2] = { proxy = component.proxy(analyzers[match2]), side = possiblePairs[i][2] }
                    print("Found our parent analyzers", possiblePairs[i][1], possiblePairs[i][2])
                end
            end
        end

        -- find the analyzer not already found (not facing another)
        for i=1,4,1
        do
            local foundMatch, match1, match2
            foundMatch, match1, match2 = checkForFacingPair(possiblePairs[i][1], possiblePairs[i][2], soils)
            if foundMatch ~= nil
            then
                if foundMatch == false
                then
                    if component.proxy(analyzers[match1]) ~= seedAnalyzerParents[1].proxy and component.proxy(analyzers[match1]) ~= seedAnalyzerParents[2].proxy
                    then
                        seedAnalyzerChild = { proxy = component.proxy(analyzers[match1]), side = possiblePairs[i][1] }
                        print("Found our child analyzer", possiblePairs[i][1])
                    end
                end
            end
        end

        if seedAnalyzerParents[1] ~= nil and seedAnalyzerParents[2] ~= nil and seedAnalyzerChild ~= nil
        then
            return true
        end
    else
        print("Requires exactly 3 connected Computer Controlled Seed Analyzers")
    end
    return false
end

local function InitComponents()
    return true
end

local function UnInitComponents()
end

-- States:
--  unknown
--  empty field
--  one or two parent crops
--  one or two parent seeds (immature)
--  one or two parent seeds (mature)
--  child crops
--  child seed (immature)
--  child seed (mature)
-- 

local function robotCommand(command)
    os.sleep(1)
    print("Sending command to robot", tostring(command))
    local sent = modem.broadcast(modemPort, command)
    local _,_,_,_,_,reply = require("event").pull(30, "modem") -- wait 'timeout' secs for reply
    if reply ~= nil then
        if tostring(reply) == "true"
        then
            return true
        elseif tostring(reply) == "false"
        then
            return false
        end
        return reply
    end
    printError("Error: Failed to send/receive command")
    return nil
end

local function menuLoop(menuData)
    print("State:", menuData.state)

    if menuData.state == 0
    then
        term.clear()
        print("1. Run")
        print("2. Settings")
        print("3. Exit")
    elseif menuData.state == 1
    then
        term.clear()
        print("1. Load Settings")
        print("2. Save Settings")
    end

    -- if ((io.read() or "n").."y"):match("^%s*[Yy]") then

    local choice = io.read()
    choice = string.gsub(choice, "%c", "")

    -- see if the pipe was closed
    if choice ~= nil
    then
        if menuData.state == 0
        then
            if choice == "1"
            then
                return states.START
            elseif choice == "2"
            then
                print("Entering state 1")
                menuData.state = 1
            elseif choice == "3"
            then
                mainLoopDone = true
            end
        elseif menuData.state == 1
        then
            menuData.state = 0
        end
    else
        mainLoopDone = true
    end
    return states.MAIN_MENU
end

local function initMenu()
    local menuData =
    {
        state = 0
    }
    return menuData
end

local menuData

local function mainLoop()
    local state = states.INIT
    
    print("Hold Alt to break")
    while mainLoopDone ~= true
    do
        if not keyboard.isAltDown()
        then
            if state == states.INIT
            then
                menuData = initMenu()
                if menuData ~= nil
                then
                    state = states.MAIN_MENU
                end
            elseif state == states.MAIN_MENU
            then
                state = menuLoop(menuData)
            elseif state == states.START
            then
                if robotCommand("INIT") == true
                then
                    state = states.NEED_ANALYZERS
                end
            elseif state == states.NEED_ANALYZERS
            then
                if findAnalyzers()
                then
                    print("Found our analyzers")
                    state = states.NEED_SUPPLIES
                    robotCommand("DUMP")
                end
            elseif state == states.NEED_SUPPLIES
            then
                if robotCommand("RESTOCK") == true
                then
                    state = states.NEED_PARENTS
                end
            elseif state == states.NEED_PARENTS
            then
                if robotCommand("PLOW") == true
                then
                    robotCommand("DUMP")
                    state = states.NEED_CROSS_CROPS
                end
            elseif state == states.NEED_CROSS_CROPS
            then
                if seedAnalyzerParents[1].proxy.isMature(seedAnalyzerParents[1].side) and seedAnalyzerParents[2].proxy.isMature(seedAnalyzerParents[2].side)
                then
                    if robotCommand("CROSS") == true
                    then
                        state = states.NEED_CHILD
                    end
                else
                    robotCommand("HOME")
                end
            elseif state == states.NEED_CHILD
            then
                if seedAnalyzerChild.proxy.isMature(seedAnalyzerChild.side)
                then
                    robotCommand("DUMP")
                    if robotCommand("ANALYZE") == true
                    then
                        state = states.NEED_ANALYSIS
                    end
                else
                    robotCommand("HOME")
                end
            elseif state == states.NEED_ANALYSIS
            then
                seedAnalyzerChild.proxy.analyze()
                state = states.ANALYZING
            elseif state == states.ANALYZING
            then
                if seedAnalyzerChild.proxy.isAnalyzed()
                then
                    local stat1, stat2, stat3 = seedAnalyzerChild.proxy.getSpecimenStats()
                    if robotCommand("PICKUP_ANALYZED") == true
                    then
                        if stat1 == 10 and stat2 == 10 and stat3 == 10
                        then
                            state = states.DONE
                        else
                            state = states.NEED_PARENTS
                        end
                    end
                end
            elseif state == states.DONE
            then
                if robotCommand("STORE_ANALYZED") == true
                then
                    state = states.NEED_SUPPLIES
                end
            elseif state == states.ERROR
            then
                robotCommand("HOME")
            end
            os.sleep(1)
        else
            mainLoopDone = true
        end
    end
end

local function Init()
    if InitComponents()
    then
        modem.close()
        modem.open(modemPort)
        if modem.isOpen(modemPort)
        then
            modem.setStrength(9999)
            return true
        else
            printError("Error: Failed to open modem")
        end
        UnInitComponents()
    end
    return false
end

local function UnInit()
    modem.close()
    UnInitComponents()
end

local function main()

    if Init()
    then
        mainLoop()
        UnInit()
    end

  -- t.clear()
  -- t.setCursor(1,1)
end

main()