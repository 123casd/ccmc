-- /update_sgnet_ae2_commands.lua
-- SGNet AE2 Commands Update
-- Adds AE2 top item and find item commands to the controller + AE2 adapter.

local VERSION = "sgnet-ae2-commands-v1"

local AE2_BRIDGE_ADAPTER = [=====[
-- /sgnet/adapters/ae2_bridge.lua
-- SGNet AE2 ME Bridge adapter with flexible detection and item commands.

local adapter = {
    id = "ae2_bridge",
    name = "AE2 ME Bridge",
    type = "ae2",
    enabled = true
}

-- Force the known side first. Your ME Bridge was detected on the left.
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

local function safeGetItems(bridge)
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
        return false, "getItems returned a non-table value.", nil
    end

    return true, "Items returned.", items
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

local function getItemName(item)
    if type(item) ~= "table" then
        return "unknown"
    end

    return item.name
        or item.id
        or item.item
        or item.fingerprint
        or item.displayName
        or "unknown"
end

local function getItemDisplayName(item)
    if type(item) ~= "table" then
        return nil
    end

    return item.displayName
        or item.display_name
        or item.label
        or item.name
        or item.id
        or item.item
end

local function getItemCount(item)
    if type(item) ~= "table" then
        return 0
    end

    return tonumber(item.count or item.amount or item.qty or item.size or 0) or 0
end

local function compactItem(item)
    return {
        name = getItemName(item),
        display_name = getItemDisplayName(item),
        count = getItemCount(item)
    }
end

local function buildStatus()
    local bridgeName, bridge = findBridge()

    if not bridge then
        return {
            id = adapter.id,
            name = adapter.name,
            type = adapter.type,
            state = "error",
            message = "No ME Bridge found.",
            bridge_name = nil
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

local function topItems(limit)
    limit = tonumber(limit) or 8

    if limit < 1 then
        limit = 1
    elseif limit > 20 then
        limit = 20
    end

    local bridgeName, bridge = findBridge()

    if not bridge then
        return {
            ok = false,
            message = "No ME Bridge found."
        }
    end

    local ok, message, items = safeGetItems(bridge)

    if not ok then
        return {
            ok = false,
            message = message
        }
    end

    table.sort(items, function(a, b)
        return getItemCount(a) > getItemCount(b)
    end)

    local top = {}

    for i = 1, math.min(#items, limit) do
        table.insert(top, compactItem(items[i]))
    end

    return {
        ok = true,
        message = "Top " .. tostring(#top) .. " AE2 items returned.",
        bridge_name = bridgeName,
        total_entries = #items,
        top = top
    }
end

local function findItems(query, limit)
    query = string.lower(tostring(query or ""))
    limit = tonumber(limit) or 8

    if limit < 1 then
        limit = 1
    elseif limit > 20 then
        limit = 20
    end

    if query == "" then
        return {
            ok = false,
            message = "Missing search query."
        }
    end

    local bridgeName, bridge = findBridge()

    if not bridge then
        return {
            ok = false,
            message = "No ME Bridge found."
        }
    end

    local ok, message, items = safeGetItems(bridge)

    if not ok then
        return {
            ok = false,
            message = message
        }
    end

    local matches = {}

    for _, item in ipairs(items) do
        local name = string.lower(tostring(getItemName(item)))
        local display = string.lower(tostring(getItemDisplayName(item) or ""))

        if string.find(name, query, 1, true) or string.find(display, query, 1, true) then
            table.insert(matches, compactItem(item))
        end
    end

    table.sort(matches, function(a, b)
        return tonumber(a.count or 0) > tonumber(b.count or 0)
    end)

    local limited = {}

    for i = 1, math.min(#matches, limit) do
        table.insert(limited, matches[i])
    end

    return {
        ok = true,
        message = "Found " .. tostring(#matches) .. " AE2 matches for '" .. query .. "'.",
        bridge_name = bridgeName,
        query = query,
        total_entries = #items,
        total_matches = #matches,
        matches = limited
    }
end

function adapter.getStatus(config)
    return buildStatus()
end

function adapter.handleCommand(config, command, data)
    data = data or {}

    if command == "status" or command == "summary" then
        return {
            ok = true,
            message = "AE2 bridge status returned.",
            status = buildStatus()
        }
    end

    if command == "top_items" then
        return topItems(data.limit or 8)
    end

    if command == "find_item" or command == "find_items" then
        return findItems(data.query or data.search or "", data.limit or 8)
    end

    return {
        ok = false,
        message = "Unknown ae2_bridge command: " .. tostring(command)
    }
end

return adapter
]=====]

local CONTROLLER_LUA = [=====[
-- /sgnet/controller/network_controller.lua
-- SGNet controller with adapter-aware commands and AE2 item commands.

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
local uiPaused = false

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

    while #alerts > 12 do
        table.remove(alerts)
    end

    network.log(config, "ALERT " .. line)
end

local function addAlertsInOrder(lines)
    for i = #lines, 1, -1 do
        addAlert(lines[i])
    end
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

local function selectedIsOnline(node)
    if not node then
        return false
    end

    local age = network.secondsSince(node.last_seen)
    return age <= (config.offline_after or 20)
end

local function sendCommandToSelected(command, extraData)
    local node = getSelectedNode()

    if not node then
        addAlert("No gateway selected.")
        return
    end

    if not selectedIsOnline(node) then
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

local function sendAdapterCommandToSelected(adapterId, adapterCommand, adapterData)
    sendCommandToSelected("adapter_command", {
        adapter_id = adapterId,
        adapter_command = adapterCommand,
        adapter_data = adapterData or {}
    })
end

local function promptOnTerminal(prompt)
    uiPaused = true

    local oldX, oldY = term.getCursorPos()

    term.clear()
    term.setCursorPos(1, 1)
    print(prompt)
    write("> ")

    local value = read()

    term.clear()
    term.setCursorPos(oldX or 1, oldY or 1)

    uiPaused = false

    return value
end

local function draw()
    clampSelection()

    screen.clear()
    screen.setCursorPos(1, 1)

    local width, height = screen.getSize()

    writeAt(1, 1, "SGNet Controller - AE2 Commands", colors and colors.cyan or nil)
    writeAt(1, 2, "Computer ID: " .. tostring(os.getComputerID()))
    writeAt(1, 3, "Node: " .. tostring(config.node_id))
    writeAt(1, 4, "Modem: " .. tostring(modemName) .. " (" .. tostring(modemKind) .. ")")
    writeAt(1, 5, "Network: " .. tostring(config.network_name) .. " | Known nodes: " .. tostring(countNodes()))

    writeAt(1, 6, "Keys: Up/Down | P ping | I identify | S status | A adapters | R reload | T AE2 top | F AE2 find | Q quit", colors and colors.yellow or nil)

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
            if y >= height - 10 then
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

    if selected and y < height - 9 then
        y = y + 1
        writeAt(1, y, "Selected adapters:", colors and colors.cyan or nil)
        y = y + 1

        local shown = 0

        for id, status in pairs(selected.adapters or {}) do
            shown = shown + 1

            if shown > 4 then
                writeAt(1, y, "...more adapters...")
                y = y + 1
                break
            end

            writeAt(1, y, "- " .. tostring(id) .. ": " .. tostring(status.state or "unknown") .. " | " .. tostring(status.message or ""))
            y = y + 1
        end
    end

    y = math.max(y + 1, height - 9)
    writeAt(1, y, "Alerts:")
    y = y + 1

    if #alerts == 0 then
        writeAt(1, y, "No alerts.")
    else
        for i = 1, math.min(#alerts, 8) do
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

local function handleAe2AdapterResult(node, data)
    local result = data.result

    if type(result) ~= "table" then
        addAlert("AE2 response from " .. tostring(node.node_id) .. ": " .. tostring(data.message))
        return
    end

    local adapterResult = result.result

    if result.message and not adapterResult then
        addAlert("AE2: " .. tostring(result.message))
    end

    if type(adapterResult) ~= "table" then
        return
    end

    if type(adapterResult.top) == "table" then
        local lines = {}
        table.insert(lines, "AE2 top items:")

        for i, item in ipairs(adapterResult.top) do
            table.insert(lines, tostring(i) .. ". " .. tostring(item.name or item.display_name or "unknown") .. " x" .. formatNumber(item.count))
        end

        addAlertsInOrder(lines)
        return
    end

    if type(adapterResult.matches) == "table" then
        local lines = {}
        table.insert(lines, "AE2 find '" .. tostring(adapterResult.query or "?") .. "': " .. tostring(adapterResult.total_matches or #adapterResult.matches) .. " matches")

        for i, item in ipairs(adapterResult.matches) do
            table.insert(lines, tostring(i) .. ". " .. tostring(item.name or item.display_name or "unknown") .. " x" .. formatNumber(item.count))
        end

        addAlertsInOrder(lines)
        return
    end

    if type(adapterResult.status) == "table" then
        addAlert("AE2 status: " .. tostring(adapterResult.status.message or "returned"))
        return
    end
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

        if data.command == "adapter_command" and data.adapter_id == "ae2_bridge" then
            handleAe2AdapterResult(node, data)
        else
            addAlert(okText .. " " .. tostring(node.node_id) .. " [" .. command .. "]: " .. response)
        end
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

        if not uiPaused then
            draw()
        end

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

        elseif key == keys.t then
            sendAdapterCommandToSelected("ae2_bridge", "top_items", {
                limit = 8
            })

        elseif key == keys.f then
            local query = promptOnTerminal("AE2 item search term")
            query = tostring(query or "")

            if query ~= "" then
                sendAdapterCommandToSelected("ae2_bridge", "find_item", {
                    query = query,
                    limit = 8
                })
            else
                addAlert("AE2 search cancelled.")
            end

        elseif key == keys.q then
            screen.clear()
            screen.setCursorPos(1, 1)
            print("SGNet controller stopped.")
            return
        end
    end
end

network.log(config, "Controller AE2 commands started on modem " .. tostring(modemName))
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

print("SGNet AE2 Commands Updater")
print("==========================")
print("Version: " .. VERSION)
print("")

writeFile("/sgnet/adapters/ae2_bridge.lua", AE2_BRIDGE_ADAPTER)
writeFile("/sgnet/controller/network_controller.lua", CONTROLLER_LUA)

print("Updated:")
print("- /sgnet/adapters/ae2_bridge.lua")
print("- /sgnet/controller/network_controller.lua")
print("")
print("Run startup to restart SGNet.")