script_name("PekanBaru Roleplay UI - Android")
script_author("PekanBaru Roleplay")
script_description("UI mobile PekanBaru Roleplay untuk MonetLoader")

local UPDATE_CONFIG = {
    owner = "Revan234",
    repository = "PekanUI-Android",
    branch = "main",
    file = "uijtrp.lua",
    intervalSeconds = 600,
}

local okImgui, imgui = pcall(require, "mimgui")
if not okImgui then
    print("[PBRP Android UI] mimgui MonetLoader tidak tersedia: " .. tostring(imgui))
    return
end

local V2 = imgui.ImVec2
local menuOpen = imgui.new.bool(false)
local frame
local updateCheckRunning = false
local lastUpdateNotice = nil

local commands = {
    { "STATUS KARAKTER", "/stats" },
    { "PANDUAN SERVER", "/help" },
    { "KENDARAAN SAYA", "/myv" },
    { "PENGATURAN", "/settings" },
    { "ADMIN ONLINE", "/admins" },
    { "ANGGOTA FAKSI", "/fonline" },
}

local function closeMenu()
    menuOpen[0] = false
end

local function sendCommand(command)
    if not isSampAvailable() then
        sampAddChatMessage("[PBRP Android] Server belum terhubung.", 0xFFFF6A6A)
        return
    end
    sampSendChat(command)
    closeMenu()
end

local function toggleMenu()
    menuOpen[0] = not menuOpen[0]
end

local function updaterNotice(message)
    if message == lastUpdateNotice then return end
    lastUpdateNotice = message
    local text = "[PBRP Android Updater] " .. message
    print(text)
    if isSampAvailable() then
        sampAddChatMessage(text, 0xFFD4AF37)
    end
end

local function readFile(path)
    local file, openError = io.open(path, "rb")
    if not file then return nil, tostring(openError) end
    local content, readError = file:read("*a")
    local closed, closeError = file:close()
    if not content then return nil, tostring(readError or "gagal membaca file") end
    if not closed then return nil, tostring(closeError or "gagal menutup file") end
    return content
end

local function checkForUpdate()
    if updateCheckRunning then return end
    updateCheckRunning = true

    local ok, err = pcall(function()
        local okRequests, requests = pcall(require, "requests")
        if not okRequests or type(requests.get) ~= "function" then
            error("library requests MonetLoader tidak tersedia")
        end

        local scriptInfo = thisScript()
        local scriptPath = scriptInfo and scriptInfo.path
        if type(scriptPath) ~= "string" or scriptPath == "" then
            error("lokasi script Android tidak dapat ditentukan")
        end

        local url = string.format(
            "https://raw.githubusercontent.com/%s/%s/%s/%s",
            UPDATE_CONFIG.owner,
            UPDATE_CONFIG.repository,
            UPDATE_CONFIG.branch,
            UPDATE_CONFIG.file)
        local response = requests.get(url, { timeout = 8 })
        local statusCode = tonumber(tostring(response.status_code):match("^%d+"))
        if statusCode ~= 200 then
            error("GitHub mengembalikan HTTP " .. tostring(response.status_code))
        end

        local remoteSource = response.text
        if type(remoteSource) ~= "string" or remoteSource == ""
            or not remoteSource:find('script_name("PekanBaru Roleplay UI - Android")', 1, true) then
            error("file update kosong atau bukan script PekanBaru Android")
        end

        local compile, compileError = loadstring(remoteSource, "@" .. scriptPath)
        if not compile then
            error("script update tidak valid: " .. tostring(compileError))
        end

        local currentSource, readError = readFile(scriptPath)
        if not currentSource then
            error("gagal membaca script terpasang: " .. readError)
        end
        if currentSource == remoteSource then
            return
        end

        local temporaryPath = scriptPath .. ".update.tmp"
        local file, openError = io.open(temporaryPath, "wb")
        if not file then
            error("gagal membuat file sementara: " .. tostring(openError))
        end
        local wrote, writeError = file:write(remoteSource)
        local closed, closeError = file:close()
        if not wrote or not closed then
            os.remove(temporaryPath)
            error("gagal menyimpan update: " .. tostring(writeError or closeError))
        end

        local installed, installError = os.rename(temporaryPath, scriptPath)
        if not installed then
            os.remove(temporaryPath)
            error("gagal memasang update: " .. tostring(installError))
        end

        updaterNotice("Update berhasil dipasang. Muat ulang script untuk mengaktifkannya.")
        if type(reloadScripts) == "function" then
            local reloaded, reloadError = pcall(reloadScripts)
            if not reloaded then
                updaterNotice("Update terpasang, tetapi reload gagal: " .. tostring(reloadError))
            end
        end
    end)

    updateCheckRunning = false
    if not ok then
        updaterNotice("Pemeriksaan gagal: " .. tostring(err))
    end
end

frame = imgui.OnFrame(
    function()
        return menuOpen[0] and isSampAvailable()
    end,
    function()
        local display = imgui.GetIO().DisplaySize
        local width = math.min(520, display.x - 24)
        local height = math.min(540, display.y - 24)
        if width < 280 or height < 300 then
            width = math.max(260, display.x - 16)
            height = math.max(280, display.y - 16)
        end

        imgui.SetNextWindowPos(V2((display.x - width) / 2, (display.y - height) / 2), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(18, 16))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(8, 8))
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.055, 0.065, 0.09, 0.98))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.82, 0.12, 0.17, 0.85))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.15, 0.20, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.75, 0.10, 0.15, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.58, 0.08, 0.12, 1))
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.96, 0.97, 1, 1))

        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings
        imgui.Begin("PEKANBARU ROLEPLAY##pbrp_android", menuOpen, flags)
        imgui.TextColored(imgui.ImVec4(1, 0.20, 0.24, 1), "MENU MOBILE")
        imgui.Separator()
        imgui.TextWrapped("Pilih fitur untuk mengirim perintah ke server.")
        imgui.Spacing()

        for index, item in ipairs(commands) do
            if imgui.Button(item[1] .. "##pbrp_android_" .. index, V2(-1, 44)) then
                sendCommand(item[2])
            end
        end

        imgui.Spacing()
        if imgui.Button("TUTUP##pbrp_android_close", V2(-1, 42)) then
            closeMenu()
        end
        imgui.End()
        imgui.PopStyleColor(6)
        imgui.PopStyleVar(3)
    end)

frame.LockPlayer = false
frame.HideCursor = false

function main()
    while not isSampAvailable() do wait(250) end
    sampRegisterChatCommand("rpui", toggleMenu)
    sampAddChatMessage("[PBRP Android] UI mobile aktif. Ketik /rpui untuk membuka menu.", 0xFFD4AF37)
    lua_thread.create(checkForUpdate)
    while true do
        wait(UPDATE_CONFIG.intervalSeconds * 1000)
        lua_thread.create(checkForUpdate)
    end
end
