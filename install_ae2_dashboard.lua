-- install_ae2_dashboard.lua
-- Downloads the AE2 dashboard from GitHub for CC:Tweaked.

-- =========================
-- CONFIG
-- =========================

local CONFIG = {
    repoOwner = "123casd",
    repoName = "ccmc",
    branch = "main",

    remoteFile = "ae2_dashboard.lua",
    localFile = "ae2_dashboard.lua",

    createStartup = true,
    startupFile = "startup.lua",

    runAfterInstall = false,
}

-- =========================
-- HELPERS
-- =========================

local function status(msg)
    print("[AE2 Installer] " .. msg)
end

local function fail(msg)
    printError("[AE2 Installer] " .. msg)
    return false
end

local function buildRawUrl()
    return "https://raw.githubusercontent.com/"
        .. CONFIG.repoOwner .. "/"
        .. CONFIG.repoName .. "/"
        .. CONFIG.branch .. "/"
        .. CONFIG.remoteFile
end

local function ensureHttp()
    if not http then
        return fail("HTTP API is not enabled.")
    end

    return true
end

local function downloadFile(url)
    status("Downloading:")
    print(url)

    local response, err = http.get(url, {
        ["Cache-Control"] = "no-cache",
        ["Pragma"] = "no-cache",
    })

    if not response then
        return nil, "Download failed: " .. tostring(err)
    end

    local body = response.readAll()
    response.close()

    if not body or body == "" then
        return nil, "Downloaded file was empty."
    end

    if body:find("^404: Not Found") then
        return nil, "GitHub returned 404. Check repo, branch, and file path."
    end

    return body, nil
end

local function backupExisting(path)
    if not fs.exists(path) then
        return true
    end

    local backupPath = path .. ".bak"

    if fs.exists(backupPath) then
        fs.delete(backupPath)
    end

    fs.move(path, backupPath)
    status("Backed up existing file to " .. backupPath)

    return true
end

local function writeFile(path, content)
    local dir = fs.getDir(path)

    if dir and dir ~= "" and not fs.exists(dir) then
        fs.makeDir(dir)
    end

    local handle = fs.open(path, "w")
    if not handle then
        return fail("Could not write file: " .. path)
    end

    handle.write(content)
    handle.close()

    return true
end

local function writeStartup()
    local startupCode = [[
-- startup.lua
-- Auto-starts AE2 dashboard.

if fs.exists("ae2_dashboard.lua") then
    shell.run("ae2_dashboard.lua")
else
    printError("Missing ae2_dashboard.lua")
    print("Run: install_ae2_dashboard")
end
]]

    if fs.exists(CONFIG.startupFile) then
        local backupPath = CONFIG.startupFile .. ".bak"

        if fs.exists(backupPath) then
            fs.delete(backupPath)
        end

        fs.move(CONFIG.startupFile, backupPath)
        status("Backed up existing startup.lua to startup.lua.bak")
    end

    return writeFile(CONFIG.startupFile, startupCode)
end

-- =========================
-- MAIN
-- =========================

term.clear()
term.setCursorPos(1, 1)

status("Starting GitHub install...")

if not ensureHttp() then
    return
end

local url = buildRawUrl()
local content, err = downloadFile(url)

if not content then
    fail(err)
    return
end

backupExisting(CONFIG.localFile)

if not writeFile(CONFIG.localFile, content) then
    return
end

status("Installed " .. CONFIG.localFile)

if CONFIG.createStartup then
    if writeStartup() then
        status("Created startup.lua")
    end
end

status("Install complete.")

if CONFIG.runAfterInstall then
    status("Launching dashboard...")
    shell.run(CONFIG.localFile)
else
    print("")
    print("Run dashboard with:")
    print("  " .. CONFIG.localFile)
    print("")
    print("Or reboot the computer if startup.lua was created.")
end
