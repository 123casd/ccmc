-- /fix_sgnet_ae2_bridge.lua
-- Fix SGNet AE2 bridge detection for ME Bridge on left side or alternate peripheral type names.

local AE2_TEST_TOOL = [=====[
-- /sgnet/tools/ae2_test.lua
-- Local AE2 ME Bridge test tool with flexible detection.

local PREFERRED_BRIDGE_SIDE = "left"

local function hasMethod(name, method)
    local ok, methods = pcall(peripheral.getMethods, name)

    if not ok or type(methods) ~= "table" then
        return false
    end

    for _, value in ipairs(methods) do
        if value == method then
            return true
        end
    end

    return false
end

local function looksLikeMeBridge(name)
    if not peripheral.isPresent(name) then
        return false
    end

    if hasMethod(name, "getItems") and hasMethod(name, "isOnline") then
        return true
    end

    if hasMethod(name, "getStoredEnergy") and hasMethod(name, "getUsedItemStorage") then
        return true
    end

    local types = { peripheral.getType(name) }

    for _, value in ipairs(types) do
        local text = string.lower(tostring(value))

        if string.find(text, "me", 1, true) and string.find(text, "bridge", 1, true) then
            return true
        end
    end

    return false
end

local function findBridge()
    if peripheral.isPresent(PREFERRED_BRIDGE_SIDE) and looksLikeMeBridge(PREFERRED_BRIDGE_SIDE) then
        return PREFERRED_BRIDGE_SIDE, peripheral.wrap(PREFERRED_BRIDGE_SIDE)
    end

    for _, name in ipairs(peripheral.getNames()) do
        if looksLikeMeBridge(name) then
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

term.clear()
term.setCursorPos(1, 1)

print("SGNet AE2 Bridge Test")
print("====================")
print("")

local name, bridge = findBridge()

if not bridge then
    print("No ME Bridge found.")
    print("")
    print("Detected peripherals:")
    for _, p in ipairs(peripheral.getNames()) do
        print("- " .. tostring(p) .. " = " .. tostring(peripheral.getType(p)))
    end
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
        print(method .. ": " .. tostring(result))
    else
        print(method .. ": ERROR - " .. tostring(result))
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

local AE2_BRIDGE_ADAPTER = [=====[
-- /sgnet/adapters/ae2_bridge.lua
-- SGNet AE2 ME Bridge adapter with flexible detection.

local adapter = {
    id = "ae2_bridge",
    name = "AE2 ME Bridge",
    type = "ae2",
    enabled = true
}

local PREFERRED_BRIDGE_SIDE = "left"

local function hasMethod(name, method)
    local ok, methods = pcall(peripheral.getMethods, name)

    if not ok or type(methods) ~= "table" then
        return false
    end

    for _, value in ipairs(methods) do
        if value == method then
            return true
        end
    end

    return false
end

local function looksLikeMeBridge(name)
    if not peripheral.isPresent(name) then
        return false
    end

    if hasMethod(name, "getItems") and hasMethod(name, "isOnline") then
        return true
    end

    if hasMethod(name, "getStoredEnergy") and hasMethod(name, "getUsedItemStorage") then
        return true
    end

    local types = { peripheral.getType(name) }

    for _, value in ipairs(types) do
        local text = string.lower(tostring(value))

        if string.find(text, "me", 1, true) and string.find(text, "bridge", 1, true) then
            return true
        end
    end

    return false
end

local function findBridge()
    if peripheral.isPresent(PREFERRED_BRIDGE_SIDE) and looksLikeMeBridge(PREFERRED_BRIDGE_SIDE) then
        return PREFERRED_BRIDGE_SIDE, peripheral.wrap(PREFERRED_BRIDGE_SIDE)
    end

    for _, name in ipairs(peripheral.getNames()) do
        if looksLikeMeBridge(name) then
            return name, peripheral.wrap(name)
        end
    end

    return nil, nil
end

local function safeCall(bridge, methodName, defaultValue)
    if type(bridge[methodName]) ~= "function" then
        return defaultValue
    end

    local ok, result = pcall(function()
        return bridge[methodName]()
    end)

    if ok then
        return result
    end

    return defaultValue
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

function adapter.getStatus(config)
    local bridgeName, bridge = findBridge()

    if not bridge then
        return {
            id = adapter.id,
            name = adapter.name,
            type = adapter.type,
            state = "error",
            message = "No ME Bridge found."
        }
    end

    local isOnline = safeCall(bridge, "isOnline", nil)
    local isConnected = safeCall(bridge, "isConnected", nil)
    local storedEnergy = safeCall(bridge, "getStoredEnergy", nil)
    local energyUsage = safeCall(bridge, "getEnergyUsage", nil)
    local totalItemStorage = safeCall(bridge, "getTotalItemStorage", nil)
    local usedItemStorage = safeCall(bridge, "getUsedItemStorage", nil)

    local state = "online"

    if isOnline == false or isConnected == false then
        state = "warning"
    end

    return {
        id = adapter.id,
        name = adapter.name,
        type = adapter.type,
        state = state,
        message = "ME Bridge " .. tostring(bridgeName) ..
            " | online=" .. tostring(isOnline) ..
            " | items " .. formatNumber(usedItemStorage) .. "/" .. formatNumber(totalItemStorage) ..
            " | energy " .. formatNumber(storedEnergy),

        bridge_name = bridgeName,
        is_online = isOnline,
        is_connected = isConnected,
        stored_energy = tonumber(storedEnergy),
        energy_usage = tonumber(energyUsage),
        total_item_storage = tonumber(totalItemStorage),
        used_item_storage = tonumber(usedItemStorage)
    }
end

function adapter.handleCommand(config, command, data)
    if command == "status" or command == "summary" then
        return {
            ok = true,
            message = "AE2 bridge status returned.",
            status = adapter.getStatus(config)
        }
    end

    return {
        ok = false,
        message = "Unknown ae2_bridge command: " .. tostring(command)
    }
end

return adapter
]=====]

local function writeFile(path, content)
    local dir = fs.getDir(path)

    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    if fs.exists(path) then
        fs.delete(path)
    end

    local handle = fs.open(path, "w")
    handle.write(content)
    handle.close()
end

term.clear()
term.setCursorPos(1, 1)

print("Fixing SGNet AE2 Bridge detection...")
print("")

writeFile("/sgnet/tools/ae2_test.lua", AE2_TEST_TOOL)
writeFile("/sgnet/adapters/ae2_bridge.lua", AE2_BRIDGE_ADAPTER)

print("Updated:")
print("- /sgnet/tools/ae2_test.lua")
print("- /sgnet/adapters/ae2_bridge.lua")
print("")
print("Now run:")
print("/sgnet/tools/ae2_test")