-- /sgnet/controller/network_controller.lua
-- SGNet Phase 1.5 central controller with keyboard command menu

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

local function addAlert(message)
    local line = tostring(message)

    table.insert(alerts, 1, line)

    while #alerts > 6 do
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

local function sendCommandToSelected(command)
    local list = sortedNodes()
    clampSelection()

    local node = list[selectedIndex]

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

    local ok = network.send(config, node.computer_id, config.protocols.command, "command", {
        command = command,
        issued_by = config.node_id,
        issued_at = network.nowMs()
    })

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

    writeAt(1, 1, "SGNet Controller", colors and colors.cyan or nil)
    writeAt(1, 2, "Computer ID: " .. tostring(os.getComputerID()))
    writeAt(1, 3, "Node: " .. tostring(config.node_id))
    writeAt(1, 4, "Modem: " .. tostring(modemName) .. " (" .. tostring(modemKind) .. ")")
    writeAt(1, 5, "Network: " .. tostring(config.network_name) .. " | Known nodes: " .. tostring(countNodes()))

    writeAt(1, 6, "Keys: Up/Down select | P ping | I identify | S status | Q quit", colors and colors.yellow or nil)

    local y = 8

    writeAt(1, y, "  Status   ID    Node                         Base                 Dim        Seen")
    y = y + 1
    writeAt(1, y, string.rep("-", math.min(width, 80)))
    y = y + 1

    local list = sortedNodes()

    if #list == 0 then
        writeAt(1, y, "No gateways have checked in yet.")
        y = y + 2
    else
        for index, node in ipairs(list) do
            if y >= height - 7 then
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

            local line =
                marker .. " " ..
                network.padRight(status, 9) ..
                network.padRight(node.computer_id, 6) ..
                network.padRight(network.trimTo(node.node_id, 28), 29) ..
                network.padRight(network.trimTo(node.base, 20), 21) ..
                network.padRight(network.trimTo(node.dimension, 10), 11) ..
                tostring(age) .. "s"

            writeAt(1, y, line, color)
            y = y + 1
        end
    end

    y = math.max(y + 1, height - 6)
    writeAt(1, y, "Alerts:")
    y = y + 1

    if #alerts == 0 then
        writeAt(1, y, "No alerts.")
    else
        for i = 1, math.min(#alerts, 5) do
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
    node.modem = data.modem
    node.modem_kind = data.modem_kind
    node.uptime = data.uptime

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
        elseif key == keys.q then
            screen.clear()
            screen.setCursorPos(1, 1)
            print("SGNet controller stopped.")
            return
        end
    end
end

network.log(config, "Controller started on modem " .. tostring(modemName))
parallel.waitForAny(networkLoop, drawLoop, keyLoop)