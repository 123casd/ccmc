-- ae2_dashboard.lua
-- Professional rotating AE2 dashboard for CC:Tweaked + Advanced Peripherals ME Bridge.

-- =========================
-- CONFIG
-- =========================

local CONFIG = {
    title = "SGNet AE2 Network",

    refreshSeconds = 5,
    pageRotateSeconds = 12,

    monitorTextScale = 0.5,

    topItemCount = 24,
    showChannelMethodHints = true,

    -- If your ME Bridge cannot report channels, you can use manual mode.
    -- channelMode = "auto" or "manual"
    channelMode = "auto",

    manualChannels = {
        used = 0,
        total = 32,
    },

    pages = {
        "overview",
        "items",
        "watched",
        "crafting",
        "diagnostics",
    },

    watchedItems = {
        { name = "minecraft:iron_ingot",      label = "Iron" },
        { name = "minecraft:gold_ingot",      label = "Gold" },
        { name = "minecraft:diamond",         label = "Diamonds" },
        { name = "minecraft:redstone",        label = "Redstone" },
        { name = "minecraft:quartz",          label = "Quartz" },
        { name = "ae2:certus_quartz_crystal", label = "Certus" },
        { name = "ae2:fluix_crystal",         label = "Fluix" },
        { name = "minecraft:coal",            label = "Coal" },
    },
}

-- =========================
-- COMPATIBILITY HELPERS
-- =========================

local unpackFn = table.unpack or unpack

local function safeToString(value)
    if value == nil then return "nil" end
    return tostring(value)
end

local function clamp(value, minValue, maxValue)
    if value < minValue then return minValue end
    if value > maxValue then return maxValue end
    return value
end

local function round(value)
    return math.floor((value or 0) + 0.5)
end

local function tableCount(t)
    local count = 0
    if type(t) ~= "table" then return 0 end

    for _ in pairs(t) do
        count = count + 1
    end

    return count
end

local function formatNumber(n)
    n = tonumber(n)
    if not n then return "N/A" end

    local abs = math.abs(n)

    if abs >= 1000000000 then
        return string.format("%.2fB", n / 1000000000)
    elseif abs >= 1000000 then
        return string.format("%.2fM", n / 1000000)
    elseif abs >= 1000 then
        return string.format("%.1fk", n / 1000)
    end

    return tostring(math.floor(n))
end

local function formatPercent(used, total)
    used = tonumber(used)
    total = tonumber(total)

    if not used or not total or total <= 0 then
        return "N/A"
    end

    return string.format("%d%%", round((used / total) * 100))
end

local function percentValue(used, total)
    used = tonumber(used)
    total = tonumber(total)

    if not used or not total or total <= 0 then
        return nil
    end

    return clamp(used / total, 0, 1)
end

local function cleanLabel(text, maxLen)
    text = safeToString(text)

    text = text:gsub("^minecraft:", "")
    text = text:gsub("^ae2:", "")
    text = text:gsub("^appliedenergistics2:", "")
    text = text:gsub("_", " ")

    if maxLen and #text > maxLen then
        return text:sub(1, math.max(1, maxLen - 3)) .. "..."
    end

    return text
end

-- =========================
-- PERIPHERAL DISCOVERY
-- =========================

local bridge = nil
local bridgeName = nil
local bridgeMethods = {}

local function getPeripheralTypes(name)
    local ok, a, b, c, d = pcall(peripheral.getType, name)
    if not ok then return {} end

    local types = {}
    if a then table.insert(types, a) end
    if b then table.insert(types, b) end
    if c then table.insert(types, c) end
    if d then table.insert(types, d) end

    return types
end

local function findBridge()
    local preferredTypes = {
        "me_bridge",
        "meBridge",
    }

    for _, typeName in ipairs(preferredTypes) do
        local found = { peripheral.find(typeName) }

        if found[1] then
            local wrapped = found[1]
            local name = nil

            if peripheral.getName then
                local ok, result = pcall(peripheral.getName, wrapped)
                if ok then name = result end
            end

            return wrapped, name or typeName
        end
    end

    for _, name in ipairs(peripheral.getNames()) do
        local types = getPeripheralTypes(name)

        for _, t in ipairs(types) do
            local lower = string.lower(t)

            if lower == "mebridge" or lower == "me_bridge" or lower:find("me") and lower:find("bridge") then
                return peripheral.wrap(name), name
            end
        end
    end

    return nil, nil
end

local function refreshBridgeMethods()
    bridgeMethods = {}

    if not bridgeName then return end

    local ok, methods = pcall(peripheral.getMethods, bridgeName)
    if not ok or type(methods) ~= "table" then return end

    for _, method in ipairs(methods) do
        bridgeMethods[method] = true
    end
end

local function hasMethod(methodName)
    if bridgeMethods[methodName] then return true end
    if bridge and type(bridge[methodName]) == "function" then return true end

    return false
end

local function callBridge(methodName, ...)
    if not bridge then
        return false, nil, "No ME Bridge found"
    end

    if type(bridge[methodName]) ~= "function" then
        return false, nil, "Missing method: " .. methodName
    end

    local ok, a, b, c = pcall(bridge[methodName], ...)
    if not ok then
        return false, nil, safeToString(a)
    end

    return true, a, b, c
end

local function firstNumber(methodNames, args)
    args = args or {}

    for _, methodName in ipairs(methodNames) do
        if hasMethod(methodName) then
            local ok, a, b, c = callBridge(methodName, unpackFn(args))

            if ok then
                local n = tonumber(a) or tonumber(b) or tonumber(c)
                if n then return n, methodName end
            end
        end
    end

    return nil, nil
end

local function firstTable(methodNames, args)
    args = args or {}

    for _, methodName in ipairs(methodNames) do
        if hasMethod(methodName) then
            local ok, result = callBridge(methodName, unpackFn(args))

            if ok and type(result) == "table" then
                return result, methodName
            end
        end
    end

    return nil, nil
end

-- =========================
-- MONITOR / UI HELPERS
-- =========================

local screen = nil

local THEME = {
    bg = colors.black,
    panel = colors.gray,
    panelDark = colors.gray,
    header = colors.blue,
    title = colors.white,
    text = colors.white,
    muted = colors.lightGray,
    accent = colors.cyan,
    good = colors.lime,
    warn = colors.orange,
    bad = colors.red,
    barBg = colors.gray,
    barFill = colors.cyan,
}

local function findScreen()
    local mon = peripheral.find("monitor")

    if mon then
        if mon.setTextScale then
            pcall(mon.setTextScale, CONFIG.monitorTextScale)
        end

        return mon
    end

    return term.current()
end

local function setBg(target, color)
    if target.setBackgroundColor then
        target.setBackgroundColor(color)
    elseif target.setBackgroundColour then
        target.setBackgroundColour(color)
    end
end

local function setFg(target, color)
    if target.setTextColor then
        target.setTextColor(color)
    elseif target.setTextColour then
        target.setTextColour(color)
    end
end

local function writeAt(x, y, text, fg, bg, maxLen)
    if not screen then return end

    text = safeToString(text)

    if maxLen and #text > maxLen then
        text = text:sub(1, math.max(1, maxLen - 3)) .. "..."
    end

    if bg then setBg(screen, bg) end
    if fg then setFg(screen, fg) end

    screen.setCursorPos(x, y)
    screen.write(text)
end

local function fillRect(x, y, width, height, bg)
    if not screen then return end

    width = math.max(0, width)
    height = math.max(0, height)

    setBg(screen, bg)

    local line = string.rep(" ", width)

    for yy = y, y + height - 1 do
        screen.setCursorPos(x, yy)
        screen.write(line)
    end
end

local function drawCard(x, y, width, height, title)
    fillRect(x, y, width, height, THEME.panel)
    writeAt(x + 1, y, " " .. title .. " ", THEME.title, THEME.header, width - 2)
end

local function drawProgressBar(x, y, width, pct, label, fillColor)
    width = math.max(4, width)

    fillRect(x, y, width, 1, THEME.barBg)

    if pct then
        local filled = clamp(round(width * pct), 0, width)

        if filled > 0 then
            fillRect(x, y, filled, 1, fillColor or THEME.barFill)
        end
    end

    local text = " " .. safeToString(label) .. " "
    local tx = x + math.floor((width - #text) / 2)

    if tx < x then tx = x end

    writeAt(tx, y, text, colors.white, nil, width)
end

local function metricLine(x, y, label, value, width, valueColor)
    local labelText = safeToString(label)
    local valueText = safeToString(value)
    local available = width - #labelText - 1

    if available < 4 then available = 4 end

    writeAt(x, y, labelText, THEME.muted, THEME.panel, width)
    writeAt(x + width - math.min(#valueText, available), y, valueText, valueColor or THEME.text, THEME.panel, available)
end

local function statusPill(x, y, label, state, width)
    local color = THEME.bad
    local text = " OFFLINE "

    if state == true then
        color = THEME.good
        text = " ONLINE "
    elseif state == "warn" then
        color = THEME.warn
        text = " WARNING "
    elseif state == "unknown" then
        color = THEME.muted
        text = " UNKNOWN "
    end

    writeAt(x, y, label .. " ", THEME.muted, THEME.panel, width)
    writeAt(x + #label + 1, y, text, colors.black, color, math.max(1, width - #label - 1))
end

-- =========================
-- AE2 DATA COLLECTION
-- =========================

local function getObjectField(obj, fieldNames, methodNames)
    if type(obj) ~= "table" then return nil end

    for _, field in ipairs(fieldNames or {}) do
        if obj[field] ~= nil then
            return obj[field]
        end
    end

    for _, method in ipairs(methodNames or {}) do
        if type(obj[method]) == "function" then
            local ok, result = pcall(obj[method])

            if ok and result ~= nil then
                return result
            end
        end
    end

    return nil
end

local function getItemName(item)
    return getObjectField(
        item,
        { "displayName", "display_name", "label", "name", "id" },
        { "getDisplayName", "getName", "getId" }
    ) or "unknown"
end

local function getItemRegistryName(item)
    return getObjectField(
        item,
        { "name", "id", "registryName" },
        { "getName", "getId" }
    ) or "unknown"
end

local function getItemAmount(item)
    local amount = getObjectField(
        item,
        { "amount", "count", "size", "qty", "quantity" },
        { "getAmount", "getCount", "getQuantity" }
    )

    return tonumber(amount) or 0
end

local function fetchItems()
    local items, methodUsed = firstTable({ "getItems" }, { {} })

    if not items then
        items, methodUsed = firstTable({ "listItems" })
    end

    if type(items) ~= "table" then
        return {
            list = {},
            map = {},
            totalAmount = 0,
            typeCount = 0,
            method = methodUsed,
        }
    end

    local list = {}
    local map = {}
    local totalAmount = 0

    for _, item in pairs(items) do
        if type(item) == "table" then
            local amount = getItemAmount(item)
            local display = getItemName(item)
            local registry = getItemRegistryName(item)

            totalAmount = totalAmount + amount

            local normalized = {
                name = registry,
                displayName = display,
                amount = amount,
                isCraftable = item.isCraftable,
            }

            table.insert(list, normalized)

            if registry and registry ~= "unknown" then
                map[registry] = normalized
            end
        end
    end

    table.sort(list, function(a, b)
        return (a.amount or 0) > (b.amount or 0)
    end)

    return {
        list = list,
        map = map,
        totalAmount = totalAmount,
        typeCount = #list,
        method = methodUsed,
    }
end

local function fetchCells()
    local cells, methodUsed = firstTable({ "getCells", "listCells" })

    if type(cells) ~= "table" then
        return {
            count = 0,
            usedBytes = nil,
            totalBytes = nil,
            method = methodUsed,
        }
    end

    local count = 0
    local usedBytes = 0
    local totalBytes = 0
    local hasBytes = false

    for _, cell in pairs(cells) do
        if type(cell) == "table" then
            count = count + 1

            local used = tonumber(cell.usedBytes or cell.used or cell.bytesUsed)
            local total = tonumber(cell.bytes or cell.capacity or cell.totalBytes)

            if used then
                usedBytes = usedBytes + used
                hasBytes = true
            end

            if total then
                totalBytes = totalBytes + total
                hasBytes = true
            end
        end
    end

    return {
        count = count,
        usedBytes = hasBytes and usedBytes or nil,
        totalBytes = hasBytes and totalBytes or nil,
        method = methodUsed,
    }
end

local function fetchStorage(cells)
    local used = firstNumber({ "getUsedItemStorage" })
    local total = firstNumber({ "getTotalItemStorage" })
    local available = firstNumber({ "getAvailableItemStorage" })

    if not total and used and available then
        total = used + available
    end

    if (not used or not total) and cells and cells.usedBytes and cells.totalBytes then
        used = used or cells.usedBytes
        total = total or cells.totalBytes
    end

    local externUsed = firstNumber({ "getUsedExternItemStorage" })
    local externTotal = firstNumber({ "getTotalExternItemStorage" })

    return {
        used = used,
        total = total,
        available = available,
        pct = percentValue(used, total),
        externUsed = externUsed,
        externTotal = externTotal,
    }
end

local function fetchEnergy()
    local stored = firstNumber({ "getStoredEnergy", "getEnergyStorage" })
    local capacity = firstNumber({ "getEnergyCapacity", "getMaxEnergyStorage" })
    local usage = firstNumber({ "getEnergyUsage" })
    local injection = firstNumber({ "getAvgPowerInjection" })

    return {
        stored = stored,
        capacity = capacity,
        usage = usage,
        injection = injection,
        pct = percentValue(stored, capacity),
    }
end

local function fetchCrafting()
    local tasks = firstTable({ "getCraftingTasks" })
    local cpus = firstTable({ "getCraftingCPUs" })

    local taskCount = tasks and tableCount(tasks) or nil
    local cpuCount = cpus and tableCount(cpus) or nil
    local busyCpus = nil

    if type(cpus) == "table" then
        busyCpus = 0

        for _, cpu in pairs(cpus) do
            if type(cpu) == "table" and cpu.isBusy then
                busyCpus = busyCpus + 1
            end
        end
    end

    return {
        taskCount = taskCount,
        cpuCount = cpuCount,
        busyCpus = busyCpus,
    }
end

local function getTableNumber(t, keys)
    if type(t) ~= "table" then return nil end

    for _, key in ipairs(keys) do
        local value = t[key]
        local n = tonumber(value)

        if n then return n end
    end

    return nil
end

local function fetchChannels()
    local channelMethods = {}

    for methodName in pairs(bridgeMethods) do
        if string.lower(methodName):find("channel") then
            table.insert(channelMethods, methodName)
        end
    end

    table.sort(channelMethods)

    if CONFIG.channelMode == "manual" then
        local used = tonumber(CONFIG.manualChannels.used)
        local total = tonumber(CONFIG.manualChannels.total)

        return {
            used = used,
            total = total,
            pct = percentValue(used, total),
            supported = true,
            methods = channelMethods,
            methodUsed = "manual config",
        }
    end

    local used = nil
    local total = nil
    local methodUsed = nil

    local tableMethods = {
        "getChannels",
        "getChannelInfo",
        "getChannelUsage",
        "getChannelStats",
        "getNetworkChannels",
        "getChannelStatus",
    }

    for _, methodName in ipairs(tableMethods) do
        if hasMethod(methodName) then
            local ok, result = callBridge(methodName)

            if ok and type(result) == "table" then
                used = used or getTableNumber(result, {
                    "used",
                    "usedChannels",
                    "channelsUsed",
                    "active",
                    "activeChannels",
                    "inUse",
                })

                total = total or getTableNumber(result, {
                    "total",
                    "max",
                    "maxChannels",
                    "totalChannels",
                    "capacity",
                    "available",
                })

                methodUsed = methodName
                break
            elseif ok and tonumber(result) then
                used = tonumber(result)
                methodUsed = methodName
                break
            end
        end
    end

    if not used then
        used, methodUsed = firstNumber({
            "getUsedChannels",
            "getChannelsUsed",
            "getChannelUsage",
            "getActiveChannels",
            "getUsedChannelCount",
            "getInUseChannels",
        })
    end

    if not total then
        local foundTotal, totalMethod = firstNumber({
            "getTotalChannels",
            "getMaxChannels",
            "getChannelCapacity",
            "getChannelCount",
            "getAvailableChannels",
            "getMaxChannelCount",
        })

        total = foundTotal
        methodUsed = methodUsed or totalMethod
    end

    return {
        used = used,
        total = total,
        pct = percentValue(used, total),
        supported = used ~= nil or total ~= nil,
        methods = channelMethods,
        methodUsed = methodUsed,
    }
end

local function fetchWatchedItems(itemData)
    local watched = {}

    for _, watch in ipairs(CONFIG.watchedItems) do
        local amount = nil

        if itemData and itemData.map and itemData.map[watch.name] then
            amount = itemData.map[watch.name].amount
        end

        if amount == nil and hasMethod("getItem") then
            local ok, result = callBridge("getItem", { name = watch.name })

            if ok and type(result) == "table" then
                amount = getItemAmount(result)
            end
        end

        table.insert(watched, {
            name = watch.name,
            label = watch.label or cleanLabel(watch.name),
            amount = amount or 0,
        })
    end

    return watched
end

local function fetchConnection()
    local connected = nil
    local online = nil

    if hasMethod("isConnected") then
        local ok, result = callBridge("isConnected")
        if ok then connected = result and true or false end
    end

    if hasMethod("isOnline") then
        local ok, result = callBridge("isOnline")
        if ok then online = result and true or false end
    end

    if connected == nil then connected = bridge ~= nil end
    if online == nil then online = bridge ~= nil end

    return {
        connected = connected,
        online = online,
    }
end

local function collectData()
    if not bridge then
        return {
            hasBridge = false,
            error = "No ME Bridge found",
        }
    end

    local connection = fetchConnection()
    local items = fetchItems()
    local cells = fetchCells()
    local storage = fetchStorage(cells)
    local energy = fetchEnergy()
    local crafting = fetchCrafting()
    local channels = fetchChannels()
    local watched = fetchWatchedItems(items)

    return {
        hasBridge = true,
        bridgeName = bridgeName or "unknown",
        connection = connection,
        items = items,
        cells = cells,
        storage = storage,
        energy = energy,
        crafting = crafting,
        channels = channels,
        watched = watched,
    }
end

-- =========================
-- DRAWING: COMMON CARDS
-- =========================

local function getPageTitle(pageId)
    if pageId == "overview" then return "Overview" end
    if pageId == "items" then return "Top Items" end
    if pageId == "watched" then return "Watched Resources" end
    if pageId == "crafting" then return "Crafting / Channels" end
    if pageId == "diagnostics" then return "Diagnostics" end

    return "Dashboard"
end

local function drawHeader(w, pageIndex, pageId)
    fillRect(1, 1, w, 3, THEME.header)

    local pageTitle = getPageTitle(pageId)
    local title = CONFIG.title .. " - " .. pageTitle

    writeAt(2, 1, title, colors.white, THEME.header, w - 2)

    local clock = textutils and textutils.formatTime and textutils.formatTime(os.time(), true) or "running"
    local rightText = "Page " .. pageIndex .. "/" .. #CONFIG.pages .. " | " .. clock

    writeAt(math.max(2, w - #rightText), 1, rightText, colors.lightGray, THEME.header, #rightText)

    writeAt(2, 2, "Applied Energistics 2 Dashboard", colors.lightGray, THEME.header, w - 2)
end

local function drawFooter(w, h, data, pageIndex)
    fillRect(1, h, w, 1, THEME.bg)

    local bridgeText = "ME Bridge: " .. safeToString(data.bridgeName or "unknown")
    local rotateText = "Rotates every " .. CONFIG.pageRotateSeconds .. "s | Ctrl+T to terminate"

    writeAt(2, h, bridgeText, colors.lightGray, THEME.bg, math.floor(w / 2))
    writeAt(math.max(2, w - #rotateText), h, rotateText, colors.lightGray, THEME.bg, #rotateText)

    local dots = ""
    for i = 1, #CONFIG.pages do
        if i == pageIndex then
            dots = dots .. "[" .. i .. "]"
        else
            dots = dots .. " " .. i .. " "
        end
    end

    local dx = math.floor((w - #dots) / 2)
    if dx > 2 then
        writeAt(dx, h, dots, colors.cyan, THEME.bg, #dots)
    end
end

local function drawNoBridge(w, h, pageIndex, pageId)
    fillRect(1, 1, w, h, THEME.bg)
    drawHeader(w, pageIndex, pageId)

    local boxW = math.min(w - 4, 58)
    local boxH = 8
    local x = math.floor((w - boxW) / 2)
    local y = math.floor((h - boxH) / 2)

    if x < 1 then x = 1 end
    if y < 4 then y = 4 end

    drawCard(x, y, boxW, boxH, "ME BRIDGE NOT FOUND")

    writeAt(x + 2, y + 2, "No Advanced Peripherals ME Bridge was detected.", colors.white, THEME.panel, boxW - 4)
    writeAt(x + 2, y + 4, "Check wired modem, bridge block, and AE2 connection.", colors.lightGray, THEME.panel, boxW - 4)
    writeAt(x + 2, y + 6, "Expected peripheral type: me_bridge or meBridge", colors.orange, THEME.panel, boxW - 4)
end

local function drawStatusCard(x, y, width, data)
    drawCard(x, y, width, 5, "STATUS")
    statusPill(x + 2, y + 2, "Grid", data.connection.online, width - 4)
    metricLine(x + 2, y + 3, "Bridge", data.bridgeName or "unknown", width - 4, THEME.accent)
end

local function drawStorageCard(x, y, width, data)
    drawCard(x, y, width, 7, "ITEM STORAGE")

    local used = data.storage.used
    local total = data.storage.total
    local pctText = formatPercent(used, total)

    metricLine(x + 2, y + 2, "Used", formatNumber(used) .. " / " .. formatNumber(total), width - 4, colors.white)
    drawProgressBar(x + 2, y + 3, width - 4, data.storage.pct, pctText, THEME.accent)

    metricLine(x + 2, y + 5, "Item Types", formatNumber(data.items.typeCount), width - 4, THEME.good)
    metricLine(x + 2, y + 6, "Total Items", formatNumber(data.items.totalAmount), width - 4, THEME.good)
end

local function drawEnergyCard(x, y, width, data)
    drawCard(x, y, width, 7, "ENERGY")

    local stored = data.energy.stored
    local capacity = data.energy.capacity
    local pctText = formatPercent(stored, capacity)

    metricLine(x + 2, y + 2, "Stored", formatNumber(stored) .. " / " .. formatNumber(capacity), width - 4, colors.white)
    drawProgressBar(x + 2, y + 3, width - 4, data.energy.pct, pctText, THEME.good)

    metricLine(x + 2, y + 5, "Usage", formatNumber(data.energy.usage) .. " AE/t", width - 4, THEME.warn)
    metricLine(x + 2, y + 6, "Injection", formatNumber(data.energy.injection) .. " AE/t", width - 4, THEME.accent)
end

local function drawChannelCard(x, y, width, data)
    drawCard(x, y, width, 7, "AE2 CHANNELS")

    if data.channels.supported then
        local used = data.channels.used
        local total = data.channels.total
        local pctText = formatPercent(used, total)

        metricLine(x + 2, y + 2, "Used", formatNumber(used) .. " / " .. formatNumber(total), width - 4, colors.white)
        drawProgressBar(x + 2, y + 3, width - 4, data.channels.pct, pctText, THEME.warn)

        local method = data.channels.methodUsed or "auto-detected"
        metricLine(x + 2, y + 5, "Source", method, width - 4, THEME.accent)
    else
        writeAt(x + 2, y + 2, "Channel count unsupported by this bridge API.", colors.orange, THEME.panel, width - 4)

        if CONFIG.showChannelMethodHints then
            if #data.channels.methods > 0 then
                writeAt(x + 2, y + 4, "Detected:", colors.lightGray, THEME.panel, width - 4)
                writeAt(x + 2, y + 5, table.concat(data.channels.methods, ", "), colors.cyan, THEME.panel, width - 4)
            else
                writeAt(x + 2, y + 4, "No channel-related methods found.", colors.lightGray, THEME.panel, width - 4)
            end
        end
    end
end

local function drawCraftingCard(x, y, width, data)
    drawCard(x, y, width, 6, "AUTOCRAFTING")

    local tasks = data.crafting.taskCount
    local cpus = data.crafting.cpuCount
    local busy = data.crafting.busyCpus

    metricLine(x + 2, y + 2, "Active Tasks", tasks ~= nil and formatNumber(tasks) or "N/A", width - 4, THEME.accent)
    metricLine(x + 2, y + 3, "Crafting CPUs", cpus ~= nil and formatNumber(cpus) or "N/A", width - 4, THEME.good)
    metricLine(x + 2, y + 4, "Busy CPUs", busy ~= nil and formatNumber(busy) or "N/A", width - 4, THEME.warn)
end

local function drawCellsCard(x, y, width, data)
    drawCard(x, y, width, 6, "STORAGE CELLS")

    metricLine(x + 2, y + 2, "Cells", formatNumber(data.cells.count), width - 4, THEME.good)

    if data.cells.usedBytes and data.cells.totalBytes then
        metricLine(x + 2, y + 3, "Cell Bytes", formatNumber(data.cells.usedBytes) .. " / " .. formatNumber(data.cells.totalBytes), width - 4, colors.white)
        drawProgressBar(x + 2, y + 4, width - 4, percentValue(data.cells.usedBytes, data.cells.totalBytes), formatPercent(data.cells.usedBytes, data.cells.totalBytes), THEME.accent)
    else
        writeAt(x + 2, y + 4, "Cell byte details unavailable.", colors.lightGray, THEME.panel, width - 4)
    end
end

-- =========================
-- DRAWING: PAGES
-- =========================

local function drawOverviewPage(w, h, data)
    if w >= 70 and h >= 25 then
        local cardW = math.floor((w - 6) / 2)
        local leftX = 2
        local rightX = leftX + cardW + 2

        drawStatusCard(leftX, 5, cardW, data)
        drawStorageCard(rightX, 5, cardW, data)

        drawEnergyCard(leftX, 13, cardW, data)
        drawChannelCard(rightX, 13, cardW, data)

        drawCraftingCard(leftX, 21, cardW, data)
        drawCellsCard(rightX, 21, cardW, data)
    else
        local cardW = w - 2
        local y = 5

        drawStatusCard(2, y, cardW, data)
        y = y + 6

        if y + 7 < h then
            drawStorageCard(2, y, cardW, data)
            y = y + 8
        end

        if y + 7 < h then
            drawEnergyCard(2, y, cardW, data)
            y = y + 8
        end

        if y + 7 < h then
            drawChannelCard(2, y, cardW, data)
        end
    end
end

local function drawItemsPage(w, h, data)
    local x = 2
    local y = 5
    local width = w - 2
    local height = h - 6

    drawCard(x, y, width, height, "TOP STORED ITEMS")

    local rowsAvailable = height - 3
    local columns = 1

    if w >= 90 then
        columns = 2
    end

    local rowsPerColumn = math.floor(rowsAvailable)
    local colWidth = math.floor((width - 4) / columns)

    for col = 1, columns do
        local colX = x + 2 + ((col - 1) * colWidth)
        local startIndex = ((col - 1) * rowsPerColumn) + 1

        writeAt(colX, y + 2, "Item", colors.lightGray, THEME.panel, colWidth - 12)
        writeAt(colX + colWidth - 11, y + 2, "Amount", colors.lightGray, THEME.panel, 10)

        for row = 1, rowsPerColumn do
            local itemIndex = startIndex + row - 1

            if itemIndex > CONFIG.topItemCount then
                break
            end

            local item = data.items.list[itemIndex]
            local rowY = y + 2 + row

            if rowY >= h then break end

            if item then
                local nameWidth = colWidth - 13
                local label = cleanLabel(item.displayName or item.name, nameWidth)
                local amount = formatNumber(item.amount)

                writeAt(colX, rowY, label, colors.white, THEME.panel, nameWidth)
                writeAt(colX + colWidth - 11, rowY, amount, THEME.good, THEME.panel, 10)
            else
                writeAt(colX, rowY, "-", colors.gray, THEME.panel, colWidth - 2)
            end
        end
    end
end

local function drawWatchedPage(w, h, data)
    local x = 2
    local y = 5
    local width = w - 2
    local height = h - 6

    drawCard(x, y, width, height, "WATCHED RESOURCES")

    local columns = 1
    if w >= 80 then columns = 2 end

    local colWidth = math.floor((width - 4) / columns)
    local rowsPerColumn = math.ceil(#data.watched / columns)

    for col = 1, columns do
        local colX = x + 2 + ((col - 1) * colWidth)
        local startIndex = ((col - 1) * rowsPerColumn) + 1

        writeAt(colX, y + 2, "Resource", colors.lightGray, THEME.panel, colWidth - 12)
        writeAt(colX + colWidth - 11, y + 2, "Stored", colors.lightGray, THEME.panel, 10)

        for row = 1, rowsPerColumn do
            local itemIndex = startIndex + row - 1
            local item = data.watched[itemIndex]
            local rowY = y + 2 + row

            if not item or rowY >= h then
                break
            end

            local labelWidth = colWidth - 13

            writeAt(colX, rowY, cleanLabel(item.label, labelWidth), colors.white, THEME.panel, labelWidth)
            writeAt(colX + colWidth - 11, rowY, formatNumber(item.amount), THEME.accent, THEME.panel, 10)
        end
    end
end

local function drawCraftingChannelsPage(w, h, data)
    if w >= 70 then
        local cardW = math.floor((w - 6) / 2)
        local leftX = 2
        local rightX = leftX + cardW + 2

        drawCraftingCard(leftX, 5, cardW, data)
        drawChannelCard(rightX, 5, cardW, data)

        local diagY = 13
        local diagH = h - diagY - 1

        if diagH >= 6 then
            drawCard(2, diagY, w - 2, diagH, "CHANNEL METHOD DETECTION")

            writeAt(4, diagY + 2, "Mode: " .. CONFIG.channelMode, colors.white, THEME.panel, w - 6)
            writeAt(4, diagY + 3, "Method Used: " .. safeToString(data.channels.methodUsed or "none"), colors.cyan, THEME.panel, w - 6)

            if #data.channels.methods > 0 then
                writeAt(4, diagY + 5, "Detected channel-related methods:", colors.lightGray, THEME.panel, w - 6)

                local rowY = diagY + 6
                for _, methodName in ipairs(data.channels.methods) do
                    if rowY >= h then break end
                    writeAt(6, rowY, "- " .. methodName, colors.white, THEME.panel, w - 8)
                    rowY = rowY + 1
                end
            else
                writeAt(4, diagY + 5, "No channel-related bridge methods detected.", colors.orange, THEME.panel, w - 6)
                writeAt(4, diagY + 7, "Use CONFIG.channelMode = \"manual\" if you want fixed channel values.", colors.lightGray, THEME.panel, w - 6)
            end
        end
    else
        drawCraftingCard(2, 5, w - 2, data)

        if h >= 19 then
            drawChannelCard(2, 12, w - 2, data)
        end
    end
end

local function drawDiagnosticsPage(w, h, data)
    local x = 2
    local y = 5
    local width = w - 2
    local height = h - 6

    drawCard(x, y, width, height, "DIAGNOSTICS")

    metricLine(x + 2, y + 2, "Bridge", data.bridgeName or "unknown", width - 4, THEME.accent)
    metricLine(x + 2, y + 3, "Item Method", data.items.method or "unknown", width - 4, THEME.good)
    metricLine(x + 2, y + 4, "Cell Method", data.cells.method or "unknown", width - 4, THEME.good)
    metricLine(x + 2, y + 5, "Channel Source", data.channels.methodUsed or "none", width - 4, THEME.warn)

    writeAt(x + 2, y + 7, "Detected ME Bridge Methods:", colors.lightGray, THEME.panel, width - 4)

    local methods = {}
    for methodName in pairs(bridgeMethods) do
        table.insert(methods, methodName)
    end
    table.sort(methods)

    local rowY = y + 8
    local maxY = y + height - 1

    for _, methodName in ipairs(methods) do
        if rowY > maxY then break end

        writeAt(x + 4, rowY, "- " .. methodName, colors.white, THEME.panel, width - 6)
        rowY = rowY + 1
    end

    if #methods == 0 then
        writeAt(x + 4, rowY, "No methods detected.", colors.orange, THEME.panel, width - 6)
    end
end

-- =========================
-- DASHBOARD ROUTER
-- =========================

local PAGE_DRAWERS = {
    overview = drawOverviewPage,
    items = drawItemsPage,
    watched = drawWatchedPage,
    crafting = drawCraftingChannelsPage,
    diagnostics = drawDiagnosticsPage,
}

local function drawDashboard(data, pageIndex)
    screen = screen or findScreen()

    if screen.setTextScale then
        pcall(screen.setTextScale, CONFIG.monitorTextScale)
    end

    local w, h = screen.getSize()
    local pageId = CONFIG.pages[pageIndex] or "overview"

    fillRect(1, 1, w, h, THEME.bg)
    drawHeader(w, pageIndex, pageId)

    if not data.hasBridge then
        drawNoBridge(w, h, pageIndex, pageId)
        return
    end

    local drawer = PAGE_DRAWERS[pageId] or drawOverviewPage
    drawer(w, h, data)

    drawFooter(w, h, data, pageIndex)
end

-- =========================
-- MAIN LOOP
-- =========================

local function bootMessage(message)
    term.clear()
    term.setCursorPos(1, 1)
    print(message)
end

local function nextPage(currentPage)
    currentPage = currentPage + 1

    if currentPage > #CONFIG.pages then
        currentPage = 1
    end

    return currentPage
end

bootMessage("Starting AE2 Rotating Dashboard...")

local currentPage = 1
local pageElapsed = 0

while true do
    bridge, bridgeName = findBridge()

    if bridge then
        refreshBridgeMethods()
    else
        bridgeMethods = {}
    end

    local data = collectData()
    drawDashboard(data, currentPage)

    sleep(CONFIG.refreshSeconds)

    pageElapsed = pageElapsed + CONFIG.refreshSeconds

    if pageElapsed >= CONFIG.pageRotateSeconds then
        currentPage = nextPage(currentPage)
        pageElapsed = 0
    end
end
