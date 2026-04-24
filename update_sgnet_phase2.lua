-- /update_sgnet_phase2.lua
-- SGNet Phase 2 updater: Adapter Framework

local VERSION = "sgnet-phase2-adapters-v1"

local ADAPTER_MANAGER_LUA = [=====[
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
]=====]

local SYSTEM_ADAPTER_LUA = [=====[
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
]=====]

local GATEWAY_LUA = [=====[
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
]=====]

local CONTROLLER_LUA = [=====[
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

print("SGNet Phase 2 Updater")
print("=====================")
print("Version: " .. VERSION)
print("")

writeFile("/sgnet/lib/adapter_manager.lua", ADAPTER_MANAGER_LUA)
writeFile("/sgnet/adapters/system.lua", SYSTEM_ADAPTER_LUA)
writeFile("/sgnet/gateway/base_gateway.lua", GATEWAY_LUA)
writeFile("/sgnet/controller/network_controller.lua", CONTROLLER_LUA)

print("Updated files:")
print("- /sgnet/lib/adapter_manager.lua")
print("- /sgnet/adapters/system.lua")
print("- /sgnet/gateway/base_gateway.lua")
print("- /sgnet/controller/network_controller.lua")
print("")
print("Phase 2 adapter framework installed.")
print("")
print("Run startup to restart SGNet.")