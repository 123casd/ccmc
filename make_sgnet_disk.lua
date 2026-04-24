-- /make_sgnet_disk.lua
-- SGNet Unified Installer Disk Builder
-- Run this on any CC: Tweaked computer with a disk drive and blank floppy.

local VERSION = "sgnet-unified-disk-v2.1"

local INSTALLER_LUA = [==========[
-- /disk/install.lua
-- SGNet Unified Installer
-- Installs the current SGNet stack directly from this disk.

local INSTALLER_VERSION = "sgnet-unified-installer-v2.1"

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function trim(value)
    value = tostring(value or "")
    return string.match(value, "^%s*(.-)%s*$") or value
end

local function askString(prompt, default)
    while true do
        if default and default ~= "" then
            write(prompt .. " [" .. tostring(default) .. "]: ")
        else
            write(prompt .. ": ")
        end

        local answer = trim(read())

        if answer == "" and default then
            answer = default
        end

        if answer ~= "" then
            return answer
        end

        print("This value cannot be empty.")
    end
end

local function askYesNo(prompt, default)
    while true do
        local suffix = default and " [Y/n]: " or " [y/N]: "
        write(prompt .. suffix)

        local answer = string.lower(trim(read()))

        if answer == "" then
            return default
        elseif answer == "y" or answer == "yes" then
            return true
        elseif answer == "n" or answer == "no" then
            return false
        end

        print("Please answer y or n.")
    end
end

local function askNumber(prompt, default, allowBlank)
    while true do
        if default ~= nil then
            write(prompt .. " [" .. tostring(default) .. "]: ")
        elseif allowBlank then
            write(prompt .. " [blank for none]: ")
        else
            write(prompt .. ": ")
        end

        local answer = trim(read())

        if answer == "" then
            if allowBlank then
                return nil
            elseif default ~= nil then
                return default
            end
        end

        local number = tonumber(answer)

        if number then
            return number
        end

        print("Please enter a number.")
    end
end

local function askRole()
    while true do
        print("")
        print("Choose SGNet role:")
        print("1) controller")
        print("2) gateway")
        write("> ")

        local answer = string.lower(trim(read()))

        if answer == "1" or answer == "controller" then
            return "controller"
        elseif answer == "2" or answer == "gateway" then
            return "gateway"
        end

        print("Invalid choice.")
    end
end

local function writeFile(path, content)
    local dir = fs.getDir(path)

    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local handle, err = fs.open(path, "w")

    if not handle then
        error("Could not write " .. path .. ": " .. tostring(err))
    end

    handle.write(content)
    handle.close()
end

local function backupPath(path)
    if not fs.exists(path) then
        return nil
    end

    local backup = path .. ".backup_" .. tostring(os.getComputerID()) .. "_" .. tostring(math.floor(os.clock() * 1000))
    fs.move(path, backup)
    return backup
end

local function getInstallerRoot()
    local running = nil

    if shell and shell.getRunningProgram then
        running = shell.getRunningProgram()

        if shell.resolve then
            running = shell.resolve(running)
        end
    end

    if running then
        local dir = fs.getDir(running)

        if dir and dir ~= "" and fs.exists(fs.combine(dir, "sgnet")) then
            return dir
        end
    end

    if fs.exists("/disk/sgnet") then
        return "/disk"
    end

    if fs.exists("disk/sgnet") then
        return "disk"
    end

    error("Could not find installer disk root.")
end

local function makeStartup()
    return table.concat({
        "-- /startup.lua",
        "-- SGNet launcher",
        "",
        "local CONFIG_PATH = \"/sgnet/config.lua\"",
        "",
        "term.clear()",
        "term.setCursorPos(1, 1)",
        "",
        "print(\"SGNet startup\")",
        "print(\"-------------\")",
        "",
        "if not fs.exists(CONFIG_PATH) then",
        "    print(\"Missing config file: \" .. CONFIG_PATH)",
        "    return",
        "end",
        "",
        "local ok, config = pcall(dofile, CONFIG_PATH)",
        "",
        "if not ok then",
        "    print(\"Failed to load config:\")",
        "    print(config)",
        "    return",
        "end",
        "",
        "if type(config) ~= \"table\" then",
        "    print(\"Config did not return a table.\")",
        "    return",
        "end",
        "",
        "if config.role == \"controller\" then",
        "    shell.run(\"/sgnet/controller/network_controller.lua\")",
        "elseif config.role == \"gateway\" then",
        "    shell.run(\"/sgnet/gateway/base_gateway.lua\")",
        "else",
        "    print(\"Invalid SGNet role: \" .. tostring(config.role))",
        "end",
        ""
    }, "\n")
end

local function makeConfig(options)
    local controllerValue = "nil"

    if options.controller_id ~= nil then
        controllerValue = tostring(options.controller_id)
    end

    return string.format([[
-- /sgnet/config.lua
-- Generated by SGNet unified installer

local config = {
    network_name = %q,

    role = %q,
    node_id = %q,
    base_id = %q,
    dimension = %q,

    controller_id = %s,

    heartbeat_interval = %d,
    offline_after = %d,

    monitor = {
        enabled = %s,
        text_scale = %.2f
    },

    log_dir = "/sgnet/logs",

    protocols = {
        discovery = "sgnet.discovery",
        heartbeat = "sgnet.heartbeat",
        status = "sgnet.status",
        command = "sgnet.command",
        response = "sgnet.response",
        alert = "sgnet.alert"
    }
}

return config
]],
        options.network_name,
        options.role,
        options.node_id,
        options.base_id,
        options.dimension,
        controllerValue,
        options.heartbeat_interval,
        options.offline_after,
        tostring(options.monitor_enabled),
        options.monitor_text_scale
    )
end

local function defaultNodeId(role)
    local label = os.getComputerLabel()

    if label and label ~= "" then
        return string.gsub(string.lower(label), "%s+", "_")
    end

    if role == "controller" then
        return "main_controller"
    end

    return "gateway_" .. tostring(os.getComputerID())
end

local function validateInstallerFiles(root)
    local required = {
        "sgnet/lib/network.lua",
        "sgnet/lib/adapter_manager.lua",
        "sgnet/controller/network_controller.lua",
        "sgnet/gateway/base_gateway.lua",
        "sgnet/adapters/system.lua",
        "sgnet/adapters/peripheral_scan.lua",
        "sgnet/tools/peripheral_report.lua"
    }

    local ok = true

    for _, relative in ipairs(required) do
        local path = fs.combine(root, relative)

        if not fs.exists(path) then
            print("Missing installer file: " .. path)
            ok = false
        end
    end

    return ok
end

clear()

print("SGNet Unified Installer")
print("=======================")
print("Version: " .. INSTALLER_VERSION)
print("")
print("Computer ID: " .. tostring(os.getComputerID()))
print("")
print("This installs:")
print("- Controller command menu")
print("- Gateway heartbeat/status")
print("- Adapter framework")
print("- System adapter")
print("- Peripheral scanner adapter")
print("")

local root = getInstallerRoot()

if not validateInstallerFiles(root) then
    print("")
    print("Installer disk is incomplete.")
    return
end

local role = askRole()

local options = {
    network_name = askString("Network name", "sgnet"),
    role = role,
    node_id = askString("Node ID", defaultNodeId(role)),
    base_id = askString("Base ID", role == "controller" and "control_room" or "overworld_main"),
    dimension = askString("Dimension", "overworld"),
    controller_id = nil,
    heartbeat_interval = askNumber("Heartbeat interval seconds", 5, false),
    offline_after = askNumber("Offline timeout seconds", 20, false),
    monitor_enabled = false,
    monitor_text_scale = 0.5
}

if role == "controller" then
    options.monitor_enabled = askYesNo("Use monitor if attached", true)
    options.monitor_text_scale = askNumber("Monitor text scale", 0.5, false)
else
    options.controller_id = askNumber("Controller computer ID", nil, true)
end

print("")
print("Install summary")
print("---------------")
print("Role:      " .. options.role)
print("Node ID:   " .. options.node_id)
print("Base ID:   " .. options.base_id)
print("Dimension: " .. options.dimension)
print("Network:   " .. options.network_name)

if options.controller_id then
    print("Controller ID: " .. tostring(options.controller_id))
else
    print("Controller ID: auto-discovery")
end

print("")

if not askYesNo("Install SGNet on this computer", true) then
    print("Install cancelled.")
    return
end

if fs.exists("/sgnet") then
    print("")
    if askYesNo("/sgnet exists. Back up and replace", true) then
        local backup = backupPath("/sgnet")
        print("Backed up to " .. tostring(backup))
    else
        print("Install cancelled.")
        return
    end
end

if fs.exists("/startup.lua") then
    print("")
    if askYesNo("/startup.lua exists. Back up and replace", true) then
        local backup = backupPath("/startup.lua")
        print("Backed up to " .. tostring(backup))
    else
        print("Install cancelled.")
        return
    end
end

print("")
print("Copying SGNet files...")
fs.copy(fs.combine(root, "sgnet"), "/sgnet")

if not fs.exists("/sgnet/logs") then
    fs.makeDir("/sgnet/logs")
end

print("Writing config...")
writeFile("/sgnet/config.lua", makeConfig(options))

print("Writing startup...")
writeFile("/startup.lua", makeStartup())

print("")
print("SGNet installed successfully.")
print("")
print("Installed files include:")
print("- /startup.lua")
print("- /sgnet/config.lua")
print("- /sgnet/lib/network.lua")
print("- /sgnet/lib/adapter_manager.lua")
print("- /sgnet/controller/network_controller.lua")
print("- /sgnet/gateway/base_gateway.lua")
print("- /sgnet/adapters/system.lua")
print("- /sgnet/adapters/peripheral_scan.lua")
print("- /sgnet/tools/peripheral_report.lua")
print("")

if askYesNo("Reboot now", false) then
    os.reboot()
else
    print("Run 'startup' or reboot when ready.")
end

]==========]

local NETWORK_LUA = [==========[

-- /sgnet/lib/network.lua
-- Shared SGNet network helpers

local M = {}

M.VERSION = 1

function M.nowMs()
    if os.epoch then
        return os.epoch("utc")
    end

    return math.floor(os.clock() * 1000)
end

function M.secondsSince(ms)
    if not ms then
        return 0
    end

    return math.floor((M.nowMs() - ms) / 1000)
end

function M.ensureDir(path)
    if path and path ~= "" and not fs.exists(path) then
        fs.makeDir(path)
    end
end

function M.hasPeripheralType(name, wantedType)
    if peripheral.hasType then
        return peripheral.hasType(name, wantedType)
    end

    return peripheral.getType(name) == wantedType
end

function M.findModem()
    local fallback = nil

    for _, name in ipairs(peripheral.getNames()) do
        if M.hasPeripheralType(name, "modem") then
            fallback = fallback or name

            local modem = peripheral.wrap(name)

            if modem and modem.isWireless and modem.isWireless() then
                return name, true
            end
        end
    end

    if fallback then
        return fallback, false
    end

    return nil, false
end

function M.openRednet()
    local modemName, isWireless = M.findModem()

    if not modemName then
        return false, nil, "No modem peripheral found."
    end

    if not rednet.isOpen(modemName) then
        rednet.open(modemName)
    end

    if not rednet.isOpen(modemName) then
        return false, modemName, "Found modem, but rednet failed to open it."
    end

    local modemKind = isWireless and "wireless_or_ender" or "wired"

    return true, modemName, modemKind
end

function M.getComputerLabelSafe()
    local label = os.getComputerLabel()

    if label == nil or label == "" then
        return "unlabeled"
    end

    return label
end

function M.message(config, messageType, data)
    return {
        sgnet = true,
        version = M.VERSION,
        network = config.network_name or "sgnet",

        type = messageType,
        from = config.node_id or ("computer_" .. tostring(os.getComputerID())),
        computer_id = os.getComputerID(),
        label = M.getComputerLabelSafe(),

        role = config.role or "unknown",
        base = config.base_id or "unknown",
        dimension = config.dimension or "unknown",

        time = M.nowMs(),
        data = data or {}
    }
end

function M.isValid(config, message)
    if type(message) ~= "table" then
        return false
    end

    if message.sgnet ~= true then
        return false
    end

    if message.version ~= M.VERSION then
        return false
    end

    if message.network ~= (config.network_name or "sgnet") then
        return false
    end

    if type(message.type) ~= "string" then
        return false
    end

    return true
end

function M.send(config, targetId, protocol, messageType, data)
    local message = M.message(config, messageType, data)
    return rednet.send(targetId, message, protocol)
end

function M.broadcast(config, protocol, messageType, data)
    local message = M.message(config, messageType, data)
    return rednet.broadcast(message, protocol)
end

function M.log(config, line)
    local logDir = config.log_dir or "/sgnet/logs"
    M.ensureDir(logDir)

    local nodeId = config.node_id or ("computer_" .. tostring(os.getComputerID()))
    local path = fs.combine(logDir, nodeId .. ".log")

    local handle = fs.open(path, "a")

    if not handle then
        return false
    end

    handle.writeLine("[" .. tostring(M.nowMs()) .. "] " .. tostring(line))
    handle.close()

    return true
end

function M.padRight(value, length)
    local text = tostring(value or "")

    if #text >= length then
        return string.sub(text, 1, length)
    end

    return text .. string.rep(" ", length - #text)
end

function M.trimTo(value, length)
    local text = tostring(value or "")

    if #text <= length then
        return text
    end

    return string.sub(text, 1, math.max(1, length - 3)) .. "..."
end

return M

]==========]

local ADAPTER_MANAGER_LUA = [==========[

-- /sgnet/lib/adapter_manager.lua
-- SGNet adapter manager

local M = {}

M.adapters = {}
M.adapter_dir = "/sgnet/adapters"

local function isLuaFile(name)
    return type(name) == "string" and string.sub(name, -4) == ".lua"
end

local function safeCall(fn, ...)
    local ok, result = pcall(fn, ...)

    if ok then
        return true, result
    end

    return false, tostring(result)
end

local function normalizeStatus(adapter, status)
    if type(status) ~= "table" then
        status = {
            state = "error",
            message = "Adapter returned non-table status."
        }
    end

    status.id = status.id or adapter.id or "unknown"
    status.name = status.name or adapter.name or status.id
    status.type = status.type or adapter.type or "generic"
    status.state = status.state or "unknown"
    status.time = os.epoch and os.epoch("utc") or math.floor(os.clock() * 1000)

    return status
end

function M.ensureAdapterDir()
    if not fs.exists(M.adapter_dir) then
        fs.makeDir(M.adapter_dir)
    end
end

function M.loadAdapters(config)
    M.ensureAdapterDir()

    M.adapters = {}

    local files = fs.list(M.adapter_dir)
    table.sort(files)

    for _, file in ipairs(files) do
        if isLuaFile(file) then
            local path = fs.combine(M.adapter_dir, file)
            local ok, adapter = pcall(dofile, path)

            if ok and type(adapter) == "table" then
                local id = adapter.id or string.sub(file, 1, -5)

                adapter.id = id
                adapter.path = path

                M.adapters[id] = {
                    id = id,
                    path = path,
                    module = adapter,
                    loaded = true,
                    last_status = nil,
                    last_error = nil
                }
            else
                local id = string.sub(file, 1, -5)

                M.adapters[id] = {
                    id = id,
                    path = path,
                    module = nil,
                    loaded = false,
                    last_status = nil,
                    last_error = tostring(adapter)
                }
            end
        end
    end

    return M.adapters
end

function M.countAdapters()
    local count = 0

    for _ in pairs(M.adapters) do
        count = count + 1
    end

    return count
end

function M.collectStatus(config)
    local statuses = {}

    for id, entry in pairs(M.adapters) do
        if not entry.loaded or not entry.module then
            statuses[id] = {
                id = id,
                name = id,
                type = "unknown",
                state = "error",
                message = entry.last_error or "Adapter failed to load."
            }
        elseif entry.module.enabled == false then
            statuses[id] = {
                id = id,
                name = entry.module.name or id,
                type = entry.module.type or "generic",
                state = "disabled",
                message = "Adapter disabled."
            }
        elseif type(entry.module.getStatus) == "function" then
            local ok, status = safeCall(entry.module.getStatus, config)

            if ok then
                status = normalizeStatus(entry.module, status)
                entry.last_status = status
                entry.last_error = nil
                statuses[id] = status
            else
                entry.last_error = status

                statuses[id] = {
                    id = id,
                    name = entry.module.name or id,
                    type = entry.module.type or "generic",
                    state = "error",
                    message = status
                }
            end
        else
            statuses[id] = {
                id = id,
                name = entry.module.name or id,
                type = entry.module.type or "generic",
                state = "loaded",
                message = "No getStatus function."
            }
        end
    end

    return statuses
end

function M.handleAdapterCommand(config, adapterId, command, data)
    local entry = M.adapters[adapterId]

    if not entry then
        return false, "Adapter not found: " .. tostring(adapterId), nil
    end

    if not entry.loaded or not entry.module then
        return false, "Adapter is not loaded: " .. tostring(adapterId), nil
    end

    if type(entry.module.handleCommand) ~= "function" then
        return false, "Adapter does not support commands: " .. tostring(adapterId), nil
    end

    local ok, result = safeCall(entry.module.handleCommand, config, command, data or {})

    if ok then
        return true, "Adapter command completed.", result
    end

    return false, result, nil
end

return M

]==========]

local SYSTEM_ADAPTER_LUA = [==========[

-- /sgnet/adapters/system.lua
-- Basic SGNet system adapter. This should work on every computer.

local adapter = {
    id = "system",
    name = "Gateway System",
    type = "system",
    enabled = true
}

function adapter.getStatus(config)
    local label = os.getComputerLabel()

    if label == nil or label == "" then
        label = "unlabeled"
    end

    local freeSpace = nil

    if fs.getFreeSpace then
        freeSpace = fs.getFreeSpace("/")
    end

    return {
        id = adapter.id,
        name = adapter.name,
        type = adapter.type,
        state = "online",
        message = "Gateway computer is running.",
        computer_id = os.getComputerID(),
        label = label,
        uptime = math.floor(os.clock()),
        free_space = freeSpace,
        role = config.role,
        node_id = config.node_id,
        base_id = config.base_id,
        dimension = config.dimension
    }
end

function adapter.handleCommand(config, command, data)
    if command == "ping" then
        return {
            ok = true,
            message = "pong from system adapter",
            node_id = config.node_id,
            computer_id = os.getComputerID()
        }
    end

    return {
        ok = false,
        message = "Unknown system adapter command: " .. tostring(command)
    }
end

return adapter

]==========]

local PERIPHERAL_SCAN_ADAPTER_LUA = [==========[

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

]==========]

local PERIPHERAL_REPORT_TOOL_LUA = [==========[

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

]==========]

local CONTROLLER_LUA = [==========[

-- /sgnet/controller/network_controller.lua
-- SGNet Phase 2 controller with adapter-aware commands

local CONFIG_PATH = "/sgnet/config.lua"
local NETWORK_PATH = "/sgnet/lib/network.lua"

local okConfig, config = pcall(dofile, CONFIG_PATH)

if not okConfig then
    error("Failed to load config: " .. tostring(config))
end

local okNetwork, network = pcall(dofile, NETWORK_PATH)

if not okNetwork then
    error("Failed to load network library: " .. tostring(network))
end

local opened, modemName, modemKindOrError = network.openRednet()

if not opened then
    error(modemKindOrError or "Could not open rednet.")
end

local modemKind = modemKindOrError

pcall(rednet.host, config.protocols.discovery, config.node_id)
pcall(rednet.host, config.protocols.status, config.node_id)

local nodes = {}
local alerts = {}
local lastAnnounce = 0
local selectedIndex = 1

local function countTable(tbl)
    local count = 0

    if type(tbl) ~= "table" then
        return 0
    end

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function addAlert(message)
    local line = tostring(message)

    table.insert(alerts, 1, line)

    while #alerts > 7 do
        table.remove(alerts)
    end

    network.log(config, "ALERT " .. line)
end

local function getScreen()
    if config.monitor and config.monitor.enabled then
        local monitor = peripheral.find("monitor")

        if monitor then
            if config.monitor.text_scale then
                pcall(monitor.setTextScale, config.monitor.text_scale)
            end

            return monitor
        end
    end

    return term.current()
end

local screen = getScreen()

local function canUseColor()
    return screen.isColor and screen.isColor() and colors
end

local function setColor(color)
    if canUseColor() and color then
        pcall(screen.setTextColor, color)
    end
end

local function resetColor()
    if canUseColor() then
        pcall(screen.setTextColor, colors.white)
    end
end

local function writeAt(x, y, text, color)
    local width = screen.getSize()
    local output = network.trimTo(text, math.max(1, width - x + 1))

    if color then
        setColor(color)
    else
        resetColor()
    end

    screen.setCursorPos(x, y)
    screen.write(output)
    resetColor()
end

local function countNodes()
    local count = 0

    for _ in pairs(nodes) do
        count = count + 1
    end

    return count
end

local function sortedNodes()
    local list = {}

    for _, node in pairs(nodes) do
        table.insert(list, node)
    end

    table.sort(list, function(a, b)
        return tostring(a.node_id) < tostring(b.node_id)
    end)

    return list
end

local function clampSelection()
    local total = countNodes()

    if total < 1 then
        selectedIndex = 1
        return
    end

    if selectedIndex < 1 then
        selectedIndex = total
    elseif selectedIndex > total then
        selectedIndex = 1
    end
end

local function updateOfflineAlerts()
    local offlineAfter = config.offline_after or 20

    for _, node in pairs(nodes) do
        local age = network.secondsSince(node.last_seen)
        local isOffline = age > offlineAfter

        if isOffline and not node.offline_alerted then
            node.offline_alerted = true
            addAlert(node.node_id .. " is offline.")
        elseif not isOffline then
            node.offline_alerted = false
        end
    end
end

local function getSelectedNode()
    local list = sortedNodes()
    clampSelection()
    return list[selectedIndex]
end

local function sendCommandToSelected(command, extraData)
    local node = getSelectedNode()

    if not node then
        addAlert("No gateway selected.")
        return
    end

    local age = network.secondsSince(node.last_seen)
    local isOffline = age > (config.offline_after or 20)

    if isOffline then
        addAlert("Cannot send " .. command .. ": " .. node.node_id .. " is offline.")
        return
    end

    local payload = extraData or {}
    payload.command = command
    payload.issued_by = config.node_id
    payload.issued_at = network.nowMs()

    local ok = network.send(config, node.computer_id, config.protocols.command, "command", payload)

    if ok then
        addAlert("Sent " .. command .. " to " .. tostring(node.node_id))
    else
        addAlert("Failed to send " .. command .. " to " .. tostring(node.node_id))
    end
end

local function draw()
    clampSelection()

    screen.clear()
    screen.setCursorPos(1, 1)

    local width, height = screen.getSize()

    writeAt(1, 1, "SGNet Controller - Phase 2", colors and colors.cyan or nil)
    writeAt(1, 2, "Computer ID: " .. tostring(os.getComputerID()))
    writeAt(1, 3, "Node: " .. tostring(config.node_id))
    writeAt(1, 4, "Modem: " .. tostring(modemName) .. " (" .. tostring(modemKind) .. ")")
    writeAt(1, 5, "Network: " .. tostring(config.network_name) .. " | Known nodes: " .. tostring(countNodes()))

    writeAt(1, 6, "Keys: Up/Down select | P ping | I identify | S status | A adapters | R reload adapters | Q quit", colors and colors.yellow or nil)

    local y = 8

    writeAt(1, y, "  Status   ID    Node                    Base              Dim       Ad  Seen")
    y = y + 1
    writeAt(1, y, string.rep("-", math.min(width, 78)))
    y = y + 1

    local list = sortedNodes()

    if #list == 0 then
        writeAt(1, y, "No gateways have checked in yet.")
        y = y + 2
    else
        for index, node in ipairs(list) do
            if y >= height - 8 then
                writeAt(1, y, "...more nodes not shown...")
                break
            end

            local age = network.secondsSince(node.last_seen)
            local isOffline = age > (config.offline_after or 20)
            local status = isOffline and "OFFLINE" or "ONLINE"
            local color = nil

            if colors then
                color = isOffline and colors.red or colors.lime
            end

            local marker = index == selectedIndex and ">" or " "
            local adapterCount = node.adapter_count or countTable(node.adapters)

            local line =
                marker .. " " ..
                network.padRight(status, 9) ..
                network.padRight(node.computer_id, 6) ..
                network.padRight(network.trimTo(node.node_id, 23), 24) ..
                network.padRight(network.trimTo(node.base, 18), 19) ..
                network.padRight(network.trimTo(node.dimension, 9), 10) ..
                network.padRight(adapterCount, 4) ..
                tostring(age) .. "s"

            writeAt(1, y, line, color)
            y = y + 1
        end
    end

    local selected = getSelectedNode()

    if selected and y < height - 8 then
        y = y + 1
        writeAt(1, y, "Selected adapters:", colors and colors.cyan or nil)
        y = y + 1

        local shown = 0

        for id, status in pairs(selected.adapters or {}) do
            shown = shown + 1

            if shown > 3 then
                writeAt(1, y, "...more adapters...")
                y = y + 1
                break
            end

            writeAt(1, y, "- " .. tostring(id) .. ": " .. tostring(status.state or "unknown") .. " | " .. tostring(status.message or ""))
            y = y + 1
        end
    end

    y = math.max(y + 1, height - 7)
    writeAt(1, y, "Alerts:")
    y = y + 1

    if #alerts == 0 then
        writeAt(1, y, "No alerts.")
    else
        for i = 1, math.min(#alerts, 6) do
            writeAt(1, y, "- " .. alerts[i], colors and colors.orange or nil)
            y = y + 1
        end
    end
end

local function announceController()
    network.broadcast(config, config.protocols.discovery, "controller_announce", {
        controller_id = os.getComputerID(),
        controller_node = config.node_id,
        status = "online",
        modem = modemName,
        modem_kind = modemKind
    })
end

local function updateNode(senderId, message, protocol)
    if senderId == os.getComputerID() then
        return
    end

    local data = message.data or {}
    local key = tostring(senderId)

    local node = nodes[key] or {}

    node.computer_id = senderId
    node.node_id = message.from or ("computer_" .. tostring(senderId))
    node.label = message.label or "unlabeled"
    node.role = message.role or "unknown"
    node.base = message.base or "unknown"
    node.dimension = message.dimension or "unknown"
    node.last_seen = network.nowMs()
    node.last_type = message.type
    node.last_protocol = protocol
    node.status = data.status or "online"
    node.modem = data.modem or node.modem
    node.modem_kind = data.modem_kind or node.modem_kind
    node.uptime = data.uptime or node.uptime
    node.adapter_count = data.adapter_count or node.adapter_count
    node.adapters = data.adapters or node.adapters or {}

    nodes[key] = node

    if message.type == "gateway_discover" then
        network.send(config, senderId, config.protocols.discovery, "controller_announce", {
            controller_id = os.getComputerID(),
            controller_node = config.node_id,
            status = "online",
            modem = modemName,
            modem_kind = modemKind
        })

        addAlert("Discovered gateway: " .. tostring(node.node_id))

    elseif message.type == "command_response" then
        local okText = data.ok and "OK" or "FAIL"
        local command = tostring(data.command or "unknown")
        local response = tostring(data.message or "no response")

        if data.adapters then
            node.adapters = data.adapters
            node.adapter_count = data.adapter_count or countTable(data.adapters)
            nodes[key] = node
        end

        addAlert(okText .. " " .. tostring(node.node_id) .. " [" .. command .. "]: " .. response)
    end
end

local function networkLoop()
    announceController()
    lastAnnounce = network.nowMs()

    while true do
        local now = network.nowMs()

        if now - lastAnnounce > 10000 then
            announceController()
            lastAnnounce = now
        end

        local senderId, message, protocol = rednet.receive(nil, 1)

        if senderId and network.isValid(config, message) then
            updateNode(senderId, message, protocol)
        end
    end
end

local function drawLoop()
    while true do
        updateOfflineAlerts()
        draw()
        os.sleep(1)
    end
end

local function keyLoop()
    while true do
        local _, key = os.pullEvent("key")

        if key == keys.up then
            selectedIndex = selectedIndex - 1
            clampSelection()
        elseif key == keys.down then
            selectedIndex = selectedIndex + 1
            clampSelection()
        elseif key == keys.p then
            sendCommandToSelected("ping")
        elseif key == keys.i then
            sendCommandToSelected("identify")
        elseif key == keys.s then
            sendCommandToSelected("status")
        elseif key == keys.a then
            sendCommandToSelected("adapter_status")
        elseif key == keys.r then
            sendCommandToSelected("adapter_reload")
        elseif key == keys.q then
            screen.clear()
            screen.setCursorPos(1, 1)
            print("SGNet controller stopped.")
            return
        end
    end
end

network.log(config, "Controller Phase 2 started on modem " .. tostring(modemName))
parallel.waitForAny(networkLoop, drawLoop, keyLoop)

]==========]

local GATEWAY_LUA = [==========[

-- /sgnet/gateway/base_gateway.lua
-- SGNet Phase 2 base gateway with adapter framework

local CONFIG_PATH = "/sgnet/config.lua"
local NETWORK_PATH = "/sgnet/lib/network.lua"
local ADAPTER_MANAGER_PATH = "/sgnet/lib/adapter_manager.lua"

local okConfig, config = pcall(dofile, CONFIG_PATH)

if not okConfig then
    error("Failed to load config: " .. tostring(config))
end

local okNetwork, network = pcall(dofile, NETWORK_PATH)

if not okNetwork then
    error("Failed to load network library: " .. tostring(network))
end

local okAdapterManager, adapterManager = pcall(dofile, ADAPTER_MANAGER_PATH)

if not okAdapterManager then
    error("Failed to load adapter manager: " .. tostring(adapterManager))
end

local opened, modemName, modemKindOrError = network.openRednet()

if not opened then
    error(modemKindOrError or "Could not open rednet.")
end

local modemKind = modemKindOrError

pcall(rednet.host, config.protocols.discovery, config.node_id)
pcall(rednet.host, config.protocols.status, config.node_id)

adapterManager.loadAdapters(config)

local controllerId = config.controller_id
local lastControllerSeen = nil
local lastStatusLine = "Starting..."
local alertLine = ""
local lastAdapterStatus = {}

local function countTable(tbl)
    local count = 0

    if type(tbl) ~= "table" then
        return 0
    end

    for _ in pairs(tbl) do
        count = count + 1
    end

    return count
end

local function drawAdapters(y)
    print("")
    print("Adapters:    " .. tostring(adapterManager.countAdapters()))

    local shown = 0

    for id, status in pairs(lastAdapterStatus or {}) do
        shown = shown + 1

        if shown > 4 then
            print("             ...more adapters")
            break
        end

        print("             " .. tostring(id) .. " = " .. tostring(status.state or "unknown"))
    end
end

local function draw()
    term.clear()
    term.setCursorPos(1, 1)

    print("SGNet Base Gateway")
    print("------------------")
    print("Computer ID: " .. tostring(os.getComputerID()))
    print("Node:        " .. tostring(config.node_id))
    print("Base:        " .. tostring(config.base_id))
    print("Dimension:   " .. tostring(config.dimension))
    print("Network:     " .. tostring(config.network_name))
    print("Modem:       " .. tostring(modemName) .. " (" .. tostring(modemKind) .. ")")
    print("")

    if controllerId then
        local age = lastControllerSeen and network.secondsSince(lastControllerSeen) or "?"
        print("Controller:  " .. tostring(controllerId) .. " | last seen " .. tostring(age) .. "s ago")
    else
        print("Controller:  searching...")
    end

    print("")
    print("Status:      " .. tostring(lastStatusLine))
    drawAdapters()

    if alertLine ~= "" then
        print("")
        print("Alert:       " .. tostring(alertLine))
    end

    print("")
    print("Press Ctrl+T to terminate.")
end

local function discoverController()
    lastAdapterStatus = adapterManager.collectStatus(config)

    network.broadcast(config, config.protocols.discovery, "gateway_discover", {
        status = "online",
        modem = modemName,
        modem_kind = modemKind,
        uptime = math.floor(os.clock()),
        adapter_count = countTable(lastAdapterStatus),
        adapters = lastAdapterStatus
    })

    lastStatusLine = "Broadcasting discovery..."
    network.log(config, "Broadcasting controller discovery.")
end

local function buildStatusData()
    lastAdapterStatus = adapterManager.collectStatus(config)

    return {
        status = "online",
        modem = modemName,
        modem_kind = modemKind,
        uptime = math.floor(os.clock()),
        controller_id = controllerId,
        adapter_count = countTable(lastAdapterStatus),
        adapters = lastAdapterStatus
    }
end

local function sendHeartbeat()
    local data = buildStatusData()

    if controllerId then
        network.send(config, controllerId, config.protocols.heartbeat, "heartbeat", data)
        lastStatusLine = "Heartbeat sent to controller " .. tostring(controllerId)
    else
        discoverController()
    end
end

local function sendResponse(targetId, ok, command, message, extraData)
    local data = extraData or {}

    data.ok = ok
    data.command = command
    data.message = message

    network.send(config, targetId, config.protocols.response, "command_response", data)
end

local function handleCommand(senderId, message)
    if controllerId and senderId ~= controllerId then
        network.log(config, "Rejected command from non-controller ID " .. tostring(senderId))
        return
    end

    if not controllerId then
        controllerId = senderId
        lastControllerSeen = network.nowMs()
    end

    local data = message.data or {}
    local command = data.command

    if command == "ping" then
        alertLine = "Ping received from controller."
        sendResponse(senderId, true, command, "pong from " .. tostring(config.node_id))

    elseif command == "identify" then
        alertLine = "IDENTIFY command received."
        sendResponse(senderId, true, command, "identify acknowledged by " .. tostring(config.node_id))

    elseif command == "status" then
        alertLine = "Status requested by controller."
        local statusData = buildStatusData()

        statusData.node_id = config.node_id
        statusData.base_id = config.base_id
        statusData.dimension = config.dimension
        statusData.computer_id = os.getComputerID()

        sendResponse(senderId, true, command, "status online", statusData)

    elseif command == "adapter_status" then
        alertLine = "Adapter status requested."
        local statuses = adapterManager.collectStatus(config)
        lastAdapterStatus = statuses

        sendResponse(senderId, true, command, "adapter status returned", {
            adapter_count = countTable(statuses),
            adapters = statuses
        })

    elseif command == "adapter_reload" then
        alertLine = "Reloading adapters..."
        local ok, err = pcall(adapterManager.loadAdapters, config)

        if ok then
            local statuses = adapterManager.collectStatus(config)
            lastAdapterStatus = statuses

            alertLine = "Adapters reloaded."
            sendResponse(senderId, true, command, "adapters reloaded", {
                adapter_count = countTable(statuses),
                adapters = statuses
            })
        else
            alertLine = "Adapter reload failed."
            sendResponse(senderId, false, command, tostring(err))
        end

    elseif command == "adapter_command" then
        local adapterId = data.adapter_id
        local adapterCommand = data.adapter_command
        local adapterData = data.adapter_data or {}

        local ok, msg, result = adapterManager.handleAdapterCommand(config, adapterId, adapterCommand, adapterData)

        sendResponse(senderId, ok, command, msg, {
            adapter_id = adapterId,
            adapter_command = adapterCommand,
            result = result
        })

    else
        sendResponse(senderId, false, command or "unknown", "Unsupported command.")
    end
end

local function receiveLoop()
    while true do
        local senderId, message, protocol = rednet.receive(nil, 2)

        if senderId and network.isValid(config, message) then
            if message.type == "controller_announce" and message.role == "controller" then
                controllerId = senderId
                lastControllerSeen = network.nowMs()
                alertLine = ""
                lastStatusLine = "Controller found: " .. tostring(controllerId)
                network.log(config, "Controller found: " .. tostring(controllerId))
            elseif protocol == config.protocols.command and message.type == "command" then
                handleCommand(senderId, message)
            elseif senderId == controllerId then
                lastControllerSeen = network.nowMs()
            end
        end
    end
end

local function heartbeatLoop()
    discoverController()

    while true do
        if controllerId and lastControllerSeen then
            local age = network.secondsSince(lastControllerSeen)

            if age > (config.offline_after or 20) then
                alertLine = "Controller timed out. Rediscovering..."
                network.log(config, "Controller timed out. Rediscovering.")

                if not config.controller_id then
                    controllerId = nil
                    lastControllerSeen = nil
                end
            end
        end

        sendHeartbeat()
        os.sleep(config.heartbeat_interval or 5)
    end
end

local function drawLoop()
    while true do
        draw()
        os.sleep(1)
    end
end

network.log(config, "Gateway Phase 2 started on modem " .. tostring(modemName))
parallel.waitForAny(receiveLoop, heartbeatLoop, drawLoop)

]==========]

local README = [==========[
SGNet Unified Installer Disk

Usage:
1. Place this disk in a disk drive attached to the target computer.
2. Run: /disk/install
3. Choose controller or gateway.
4. Enter the node/base/dimension details.
5. Reboot or run startup.

This installer includes:
- SGNet rednet backbone
- Controller command menu
- Gateway heartbeat/status tracking
- Adapter framework
- System adapter
- Peripheral scanner adapter
- Local peripheral report tool

Recommended install order:
1. Install/start the controller first.
2. Install/start one gateway.
3. Confirm the gateway appears online.
4. Install the remaining gateways.

Use ender modems for cross-dimensional SGNet.
Use wireless modems for local-only testing.

Controller controls:
Up/Down = select gateway
P = ping
I = identify
S = status
A = adapter status
R = reload adapters
Q = quit

Gateway diagnostic:
Run /sgnet/tools/peripheral_report on a gateway to see all attached peripherals.

]==========]

local function clear()
    term.clear()
    term.setCursorPos(1, 1)
end

local function trim(value)
    value = tostring(value or "")
    return string.match(value, "^%s*(.-)%s*$") or value
end

local function askYesNo(prompt, default)
    while true do
        local suffix = default and " [Y/n]: " or " [y/N]: "
        write(prompt .. suffix)

        local answer = string.lower(trim(read()))

        if answer == "" then
            return default
        elseif answer == "y" or answer == "yes" then
            return true
        elseif answer == "n" or answer == "no" then
            return false
        end

        print("Please answer y or n.")
    end
end

local function hasPeripheralType(name, wantedType)
    if peripheral.hasType then
        return peripheral.hasType(name, wantedType)
    end

    return peripheral.getType(name) == wantedType
end

local function findDrive()
    for _, name in ipairs(peripheral.getNames()) do
        if hasPeripheralType(name, "drive") then
            return name
        end
    end

    return nil
end

local function getDiskMount()
    local drive = findDrive()

    if not drive then
        return nil, nil, "No disk drive found."
    end

    if not disk.isPresent(drive) then
        return drive, nil, "Disk drive found, but no disk is inserted."
    end

    if not disk.hasData(drive) then
        return drive, nil, "Inserted disk does not provide writable data. Use a floppy disk."
    end

    local mount = disk.getMountPath(drive)

    if not mount then
        return drive, nil, "Could not get disk mount path."
    end

    if fs.isReadOnly(mount) then
        return drive, mount, "Disk is read-only."
    end

    return drive, mount, nil
end

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

local function clearDisk(mount)
    for _, item in ipairs(fs.list(mount)) do
        fs.delete(fs.combine(mount, item))
    end
end

clear()

print("SGNet Unified Installer Disk Builder")
print("====================================")
print("Version: " .. VERSION)
print("")
print("This creates a disk that installs the current SGNet stack:")
print("- Backbone")
print("- Controller commands")
print("- Adapter framework")
print("- System adapter")
print("- Peripheral scanner")
print("")

local drive, mount, err = getDiskMount()

if err then
    print(err)
    return
end

print("Disk drive: " .. tostring(drive))
print("Disk path:  " .. tostring(mount))
print("")
print("This will erase the inserted floppy disk.")
print("")

if not askYesNo("Create unified SGNet installer disk", false) then
    print("Cancelled.")
    return
end

pcall(disk.setLabel, drive, "SGNet Installer")

print("")
print("Clearing disk...")
clearDisk(mount)

print("Writing installer files...")

writeFile(fs.combine(mount, "install.lua"), INSTALLER_LUA)
writeFile(fs.combine(mount, "README.txt"), README)
writeFile(fs.combine(mount, "VERSION.txt"), VERSION)

writeFile(fs.combine(mount, "sgnet/lib/network.lua"), NETWORK_LUA)
writeFile(fs.combine(mount, "sgnet/lib/adapter_manager.lua"), ADAPTER_MANAGER_LUA)
writeFile(fs.combine(mount, "sgnet/controller/network_controller.lua"), CONTROLLER_LUA)
writeFile(fs.combine(mount, "sgnet/gateway/base_gateway.lua"), GATEWAY_LUA)
writeFile(fs.combine(mount, "sgnet/adapters/system.lua"), SYSTEM_ADAPTER_LUA)
writeFile(fs.combine(mount, "sgnet/adapters/peripheral_scan.lua"), PERIPHERAL_SCAN_ADAPTER_LUA)
writeFile(fs.combine(mount, "sgnet/tools/peripheral_report.lua"), PERIPHERAL_REPORT_TOOL_LUA)

print("")
print("Unified installer disk created successfully.")
print("")
print("Disk contents:")
print("- install.lua")
print("- README.txt")
print("- VERSION.txt")
print("- sgnet/lib/network.lua")
print("- sgnet/lib/adapter_manager.lua")
print("- sgnet/controller/network_controller.lua")
print("- sgnet/gateway/base_gateway.lua")
print("- sgnet/adapters/system.lua")
print("- sgnet/adapters/peripheral_scan.lua")
print("- sgnet/tools/peripheral_report.lua")
print("")
print("To use it on another computer:")
print("/disk/install")
