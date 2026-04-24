-- /update_sgnet_peripheral_scan.lua
-- SGNet Phase 2.1 updater: Peripheral Scanner Adapter

local VERSION = "sgnet-phase2.1-peripheral-scan-v1"

local PERIPHERAL_SCAN_ADAPTER = [=====[
-- /sgnet/adapters/peripheral_scan.lua
-- SGNet peripheral scanner adapter

local adapter = {
    id = "peripheral_scan",
    name = "Peripheral Scanner",
    type = "diagnostic",
    enabled = true
}

local MAX_METHOD_SAMPLE = 8
local MAX_MESSAGE_ITEMS = 5

local function tableLength(tbl)
    local count = 0

    if type(tbl) ~= "table" then
        return 0
    end

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function safeGetTypes(name)
    local result = { peripheral.getType(name) }

    if #result == 0 or result[1] == nil then
        return { "unknown" }
    end

    return result
end

local function joinTypes(types)
    local output = {}

    for _, value in ipairs(types or {}) do
        table.insert(output, tostring(value))
    end

    if #output == 0 then
        return "unknown"
    end

    return table.concat(output, ",")
end

local function safeGetMethods(name)
    local ok, methods = pcall(peripheral.getMethods, name)

    if not ok or type(methods) ~= "table" then
        return {}
    end

    table.sort(methods)
    return methods
end

local function sampleMethods(methods)
    local sample = {}

    for i = 1, math.min(#methods, MAX_METHOD_SAMPLE) do
        table.insert(sample, methods[i])
    end

    return sample
end

local function scanPeripherals()
    local names = peripheral.getNames()
    table.sort(names)

    local details = {}
    local summaryParts = {}

    for _, name in ipairs(names) do
        local types = safeGetTypes(name)
        local methods = safeGetMethods(name)

        details[name] = {
            name = name,
            types = types,
            type_text = joinTypes(types),
            method_count = #methods,
            method_sample = sampleMethods(methods)
        }

        if #summaryParts < MAX_MESSAGE_ITEMS then
            table.insert(summaryParts, name .. "=" .. joinTypes(types))
        end
    end

    local message = ""

    if #names == 0 then
        message = "No peripherals detected."
    else
        message = tostring(#names) .. " peripherals: " .. table.concat(summaryParts, "; ")

        if #names > MAX_MESSAGE_ITEMS then
            message = message .. "; +" .. tostring(#names - MAX_MESSAGE_ITEMS) .. " more"
        end
    end

    return names, details, message
end

function adapter.getStatus(config)
    local names, details, message = scanPeripherals()

    local state = "online"

    if #names == 0 then
        state = "warning"
    end

    return {
        id = adapter.id,
        name = adapter.name,
        type = adapter.type,
        state = state,
        message = message,
        peripheral_count = #names,
        peripherals = details
    }
end

function adapter.handleCommand(config, command, data)
    if command == "scan" then
        local names, details, message = scanPeripherals()

        return {
            ok = true,
            message = message,
            peripheral_count = #names,
            peripherals = details
        }
    end

    if command == "methods" then
        local name = data and data.name

        if not name or name == "" then
            return {
                ok = false,
                message = "Missing peripheral name."
            }
        end

        if not peripheral.isPresent(name) then
            return {
                ok = false,
                message = "Peripheral not present: " .. tostring(name)
            }
        end

        local methods = safeGetMethods(name)

        return {
            ok = true,
            message = "Found " .. tostring(#methods) .. " methods on " .. tostring(name),
            name = name,
            types = safeGetTypes(name),
            methods = methods
        }
    end

    return {
        ok = false,
        message = "Unknown peripheral_scan command: " .. tostring(command)
    }
end

return adapter
]=====]

local PERIPHERAL_REPORT_TOOL = [=====[
-- /sgnet/tools/peripheral_report.lua
-- Local gateway tool: prints a detailed peripheral report.

local function safeGetTypes(name)
    local result = { peripheral.getType(name) }

    if #result == 0 or result[1] == nil then
        return { "unknown" }
    end

    return result
end

local function safeGetMethods(name)
    local ok, methods = pcall(peripheral.getMethods, name)

    if not ok or type(methods) ~= "table" then
        return {}
    end

    table.sort(methods)
    return methods
end

local function join(values)
    local output = {}

    for _, value in ipairs(values or {}) do
        table.insert(output, tostring(value))
    end

    return table.concat(output, ", ")
end

term.clear()
term.setCursorPos(1, 1)

print("SGNet Peripheral Report")
print("=======================")
print("Computer ID: " .. tostring(os.getComputerID()))
print("")

local names = peripheral.getNames()
table.sort(names)

if #names == 0 then
    print("No peripherals detected.")
    return
end

for _, name in ipairs(names) do
    local types = safeGetTypes(name)
    local methods = safeGetMethods(name)

    print("Name:    " .. tostring(name))
    print("Types:   " .. join(types))
    print("Methods: " .. tostring(#methods))

    if #methods > 0 then
        local line = "         "

        for i = 1, #methods do
            local piece = methods[i]

            if #line + #piece + 2 > 48 then
                print(line)
                line = "         "
            end

            line = line .. piece

            if i < #methods then
                line = line .. ", "
            end
        end

        if line ~= "         " then
            print(line)
        end
    end

    print("")
end
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

print("SGNet Peripheral Scanner Updater")
print("================================")
print("Version: " .. VERSION)
print("")

writeFile("/sgnet/adapters/peripheral_scan.lua", PERIPHERAL_SCAN_ADAPTER)
writeFile("/sgnet/tools/peripheral_report.lua", PERIPHERAL_REPORT_TOOL)

print("Installed:")
print("- /sgnet/adapters/peripheral_scan.lua")
print("- /sgnet/tools/peripheral_report.lua")
print("")
print("Now restart the gateway with:")
print("startup")
print("")
print("Or, from the controller, select the gateway and press R to reload adapters.")