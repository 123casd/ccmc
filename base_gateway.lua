-- /sgnet/gateway/base_gateway.lua
-- SGNet Phase 1.5 base gateway with command responses

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

local controllerId = config.controller_id
local lastControllerSeen = nil
local lastStatusLine = "Starting..."
local alertLine = ""

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

    if alertLine ~= "" then
        print("Alert:       " .. tostring(alertLine))
    end

    print("")
    print("Press Ctrl+T to terminate.")
end

local function discoverController()
    network.broadcast(config, config.protocols.discovery, "gateway_discover", {
        status = "online",
        modem = modemName,
        modem_kind = modemKind,
        uptime = math.floor(os.clock())
    })

    lastStatusLine = "Broadcasting discovery..."
    network.log(config, "Broadcasting controller discovery.")
end

local function sendHeartbeat()
    local data = {
        status = "online",
        modem = modemName,
        modem_kind = modemKind,
        uptime = math.floor(os.clock()),
        controller_id = controllerId,
        adapters = {}
    }

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
        sendResponse(senderId, true, command, "status online", {
            status = "online",
            node_id = config.node_id,
            base_id = config.base_id,
            dimension = config.dimension,
            computer_id = os.getComputerID(),
            modem = modemName,
            modem_kind = modemKind,
            uptime = math.floor(os.clock())
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

network.log(config, "Gateway started on modem " .. tostring(modemName))
parallel.waitForAny(receiveLoop, heartbeatLoop, drawLoop)