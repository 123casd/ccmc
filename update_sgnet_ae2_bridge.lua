-- /update_sgnet_ae2_bridge.lua
-- SGNet AE2 ME Bridge Adapter Updater

local VERSION = "sgnet-ae2-bridge-v1"

local AE2_BRIDGE_ADAPTER = [=====[
-- /sgnet/adapters/ae2_bridge.lua
-- SGNet AE2 ME Bridge adapter for Advanced Peripherals

local adapter = {
    id = "ae2_bridge",
    name = "AE2 ME Bridge",
    type = "ae2",
    enabled = true
}

-- Optional: set this to "left" if you want to force the known side.
-- Leave nil to auto-detect any meBridge peripheral.
local BRIDGE_NAME = nil

local function tableCount(tbl)
    local count = 0

    if type(tbl) ~= "table" then
        return 0
    end

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function hasType(name, wanted)
    local types = { peripheral.getType(name) }

    for _, value in ipairs(types) do
        if value == wanted then
            return true
        end
    end

    return false
end

local function findBridge()
    if BRIDGE_NAME and peripheral.isPresent(BRIDGE_NAME) then
        local wrapped = peripheral.wrap(BRIDGE_NAME)

        if wrapped then
            return BRIDGE_NAME, wrapped
        end
    end

    for _, name in ipairs(peripheral.getNames()) do
        if hasType(name, "meBridge") then
            local wrapped = peripheral.wrap(name)

            if wrapped then
                return name, wrapped
            end
        end
    end

    return nil, nil
end

local function getMethods(name)
    local ok, methods = pcall(peripheral.getMethods, name)

    if not ok or type(methods) ~= "table" then
        return {}
    end

    table.sort(methods)
    return methods
end

local function methodExists(methods, methodName)
    for _, name in ipairs(methods or {}) do
        if name == methodName then
            return true
        end
    end

    return false
end

local function safeCall(bridge, methodName, defaultValue)
    if type(bridge[methodName]) ~= "function" then
        return defaultValue, false, "missing method"
    end

    local ok, result = pcall(function()
        return bridge[methodName]()
    end)

    if ok then
        return result, true, nil
    end

    return defaultValue, false, tostring(result)
end

local function safeNumber(value)
    local number = tonumber(value)

    if not number then
        return nil
    end

    return number
end

local function formatNumber(value)
    local number = tonumber(value)

    if not number then
        return "?"
    end

    if number >= 1000000000 then
        return string.format("%.2fB", number / 1000000000)
    elseif number >= 1000000 then
        return string.format("%.2fM", number / 1000000)
    elseif number >= 1000 then
        return string.format("%.1fk", number / 1000)
    end

    return tostring(math.floor(number))
end

local function buildStatus()
    local bridgeName, bridge = findBridge()

    if not bridge then
        return {
            id = adapter.id,
            name = adapter.name,
            type = adapter.type,
            state = "error",
            message = "No meBridge peripheral found.",
            bridge_name = nil
        }
    end

    local methods = getMethods(bridgeName)

    local isOnline = safeCall(bridge, "isOnline", nil)
    local isConnected = safeCall(bridge, "isConnected", nil)

    local storedEnergy = safeCall(bridge, "getStoredEnergy", nil)
    local energyUsage = safeCall(bridge, "getEnergyUsage", nil)

    local totalItemStorage = safeCall(bridge, "getTotalItemStorage", nil)
    local usedItemStorage = safeCall(bridge, "getUsedItemStorage", nil)

    local totalFluidStorage = safeCall(bridge, "getTotalFluidStorage", nil)
    local usedFluidStorage = safeCall(bridge, "getUsedFluidStorage", nil)

    local totalChemicalStorage = safeCall(bridge, "getTotalChemicalStorage", nil)
    local usedChemicalStorage = safeCall(bridge, "getUsedChemicalStorage", nil)

    local state = "online"

    if isOnline == false or isConnected == false then
        state = "warning"
    end

    local message = "ME Bridge " .. tostring(bridgeName)

    if isOnline ~= nil then
        message = message .. " | online=" .. tostring(isOnline)
    end

    if usedItemStorage ~= nil or totalItemStorage ~= nil then
        message = message .. " | items " .. formatNumber(usedItemStorage) .. "/" .. formatNumber(totalItemStorage)
    end

    if storedEnergy ~= nil then
        message = message .. " | energy " .. formatNumber(storedEnergy)
    end

    return {
        id = adapter.id,
        name = adapter.name,
        type = adapter.type,
        state = state,
        message = message,

        bridge_name = bridgeName,
        method_count = #methods,

        is_online = isOnline,
        is_connected = isConnected,

        stored_energy = safeNumber(storedEnergy),
        energy_usage = safeNumber(energyUsage),

        total_item_storage = safeNumber(totalItemStorage),
        used_item_storage = safeNumber(usedItemStorage),

        total_fluid_storage = safeNumber(totalFluidStorage),
        used_fluid_storage = safeNumber(usedFluidStorage),

        total_chemical_storage = safeNumber(totalChemicalStorage),
        used_chemical_storage = safeNumber(usedChemicalStorage),

        supports = {
            getItems = methodExists(methods, "getItems"),
            getItem = methodExists(methods, "getItem"),
            getPatterns = methodExists(methods, "getPatterns"),
            isCraftable = methodExists(methods, "isCraftable"),
            isCrafting = methodExists(methods, "isCrafting"),
            importItem = methodExists(methods, "importItem"),
            importFluid = methodExists(methods, "importFluid"),
            importChemical = methodExists(methods, "importChemical")
        }
    }
end

local function getItemName(item)
    if type(item) ~= "table" then
        return nil
    end

    return item.name or item.id or item.item or item.fingerprint
end

local function getItemCount(item)
    if type(item) ~= "table" then
        return 0
    end

    return tonumber(item.count or item.amount or item.qty or item.size or 0) or 0
end

local function listTopItems(limit)
    limit = tonumber(limit) or 10

    local bridgeName, bridge = findBridge()

    if not bridge then
        return false, "No meBridge peripheral found.", nil
    end

    if type(bridge.getItems) ~= "function" then
        return false, "getItems method is not available.", nil
    end

    local ok, items = pcall(function()
        return bridge.getItems()
    end)

    if not ok then
        return false, tostring(items), nil
    end

    if type(items) ~= "table" then
        return false, "getItems returned non-table result.", nil
    end

    table.sort(items, function(a, b)
        return getItemCount(a) > getItemCount(b)
    end)

    local top = {}

    for i = 1, math.min(#items, limit) do
        local item = items[i]

        table.insert(top, {
            name = getItemName(item) or "unknown",
            count = getItemCount(item),
            raw = item
        })
    end

    return true, "Listed top " .. tostring(#top) .. " of " .. tostring(#items) .. " items.", {
        total_entries = #items,
        top = top
    }
end

function adapter.getStatus(config)
    return buildStatus()
end

function adapter.handleCommand(config, command, data)
    if command == "summary" or command == "status" then
        return {
            ok = true,
            message = "AE2 bridge status returned.",
            status = buildStatus()
        }
    end

    if command == "top_items" then
        local ok, message, result = listTopItems(data and data.limit or 10)

        return {
            ok = ok,
            message = message,
            result = result
        }
    end

    return {
        ok = false,
        message = "Unknown ae2_bridge command: " .. tostring(command)
    }
end

return adapter
]=====]

local AE2_TEST_TOOL = [=====[
-- /sgnet/tools/ae2_test.lua
-- Local AE2 ME Bridge test tool

local function hasType(name, wanted)
    local types = { peripheral.getType(name) }

    for _, value in ipairs(types) do
        if value == wanted then
            return true
        end
    end

    return false
end

local function findBridge()
    for _, name in ipairs(peripheral.getNames()) do
        if hasType(name, "meBridge") then
            return name, peripheral.wrap(name)
        end
    end

    return nil, nil
end

local function safeCall(bridge, methodName)
    if type(bridge[methodName]) ~= "function" then
        return false, "missing method"
    end

    local ok, result = pcall(function()
        return bridge[methodName]()
    end)

    return ok, result
end

local function printValue(label, value)
    print(label .. ": " .. tostring(value))
end

term.clear()
term.setCursorPos(1, 1)

print("SGNet AE2 Bridge Test")
print("====================")
print("")

local name, bridge = findBridge()

if not bridge then
    print("No meBridge peripheral found.")
    print("")
    print("Check that the ME Bridge is touching the computer")
    print("or attached through a wired modem.")
    return
end

print("Bridge: " .. tostring(name))
print("Type:   " .. tostring(peripheral.getType(name)))
print("")

local methods = peripheral.getMethods(name)
table.sort(methods)

print("Methods found: " .. tostring(#methods))
print("")

local tests = {
    "isOnline",
    "isConnected",
    "getStoredEnergy",
    "getEnergyUsage",
    "getTotalItemStorage",
    "getUsedItemStorage",
    "getTotalFluidStorage",
    "getUsedFluidStorage",
    "getTotalChemicalStorage",
    "getUsedChemicalStorage"
}

for _, method in ipairs(tests) do
    local ok, result = safeCall(bridge, method)

    if ok then
        printValue(method, result)
    else
        printValue(method, "ERROR - " .. tostring(result))
    end
end

print("")

if type(bridge.getItems) == "function" then
    print("Testing getItems...")

    local ok, items = pcall(function()
        return bridge.getItems()
    end)

    if ok and type(items) == "table" then
        print("getItems returned " .. tostring(#items) .. " entries.")

        for i = 1, math.min(#items, 5) do
            local item = items[i]
            local itemName = item.name or item.id or item.item or "unknown"
            local count = item.count or item.amount or item.qty or "?"

            print("- " .. tostring(itemName) .. " x " .. tostring(count))
        end
    else
        print("getItems failed: " .. tostring(items))
    end
else
    print("getItems method not available.")
end

print("")
print("Done.")
]=====]

local function writeFile(path, content)
    local dir = fs.getDir(path)

    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    if fs.exists(path) then
        fs.delete(path)
    end

    local handle, err = fs.open(path, "w")

    if not handle then
        error("Could not write " .. path .. ": " .. tostring(err))
    end

    handle.write(content)
    handle.close()
end

term.clear()
term.setCursorPos(1, 1)

print("SGNet AE2 Bridge Updater")
print("========================")
print("Version: " .. VERSION)
print("")

writeFile("/sgnet/adapters/ae2_bridge.lua", AE2_BRIDGE_ADAPTER)
writeFile("/sgnet/tools/ae2_test.lua", AE2_TEST_TOOL)

print("Installed:")
print("- /sgnet/adapters/ae2_bridge.lua")
print("- /sgnet/tools/ae2_test.lua")
print("")
print("Restart the gateway with:")
print("startup")
print("")
print("Or reload adapters from the controller with R.")