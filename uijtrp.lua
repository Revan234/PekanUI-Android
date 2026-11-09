script_name("PekanBaru Roleplay UI - FiveM Style")
script_author("PekanBaru Roleplay")
script_description("Menu roleplay modular untuk PekanBaru Roleplay")

-- ============================================================
--  KONFIGURASI  (ubah bagian ini saja)
--  Simpan folder uiPBRP yang berisi modul ikon dan katalog di samping file ini.
-- ============================================================
local CONFIG = {
    serverName = "PekanBaru",
    serverTag  = "ROLEPLAY",
    shortTag   = "PBRP/PKU",

    -- Logo PNG transparan di folder assets UI.
    logoFile   = "assets/pbrp-logo.png",

    -- Link inti server (ganti dengan link aslimu)
    discordUrl = "https://discord.gg/CacxpYbhCw",
    websiteUrl = "https://web.pekanbaruu.my.id",

    -- Warna aksen (R, G, B  0.0 - 1.0)
    accent = { 0.86, 0.12, 0.16 },

    -- HUD kiri
    hud = {
        showFps         = true,  -- widget FPS + ping (/rpuifps untuk toggle)
        fpsPosition     = "top-left",
        fpsX            = nil,
        fpsY            = nil,
        statsX          = nil,
        statsY          = nil,
        statsBottomFrac = 0.56,  -- batas bawah panel status (0-1 tinggi layar); radar GTA ada di bawahnya
        needsTimeout    = 90,    -- detik; data lapar/haus dianggap basi kalau server berhenti mengirim
    },
}
-- ============================================================

local PATH_SEPARATOR = package.config and package.config:sub(1, 1) or "/"
local function joinPath(...)
    local parts = {}
    for index = 1, select("#", ...) do
        local part = tostring(select(index, ...))
        if part ~= "" then parts[#parts + 1] = part end
    end
    return table.concat(parts, PATH_SEPARATOR):gsub("[/\\]+", PATH_SEPARATOR)
end

local accentPath = joinPath(getWorkingDirectory(), "config", "uiPBRP_color.ini")
do
    local file = io.open(accentPath, "r")
    if file then
        local r, g, b = tonumber(file:read("*l")), tonumber(file:read("*l")), tonumber(file:read("*l"))
        file:close()
        if r and g and b and r >= 0 and r <= 1 and g >= 0 and g <= 1 and b >= 0 and b <= 1 then
            CONFIG.accent = { r, g, b }
        end
    end
end

local hudSettingsPath = joinPath(getWorkingDirectory(), "config", "uiPBRP_hud.ini")
do
    local file = io.open(hudSettingsPath, "r")
    if file then
        for line in file:lines() do
            local key, value = line:match("^([%w_]+)%s*=%s*(.-)%s*$")
            if key == "showFps" then
                if value == "true" then CONFIG.hud.showFps = true end
                if value == "false" then CONFIG.hud.showFps = false end
            elseif key == "fpsPosition"
                and (value == "top-left" or value == "top-right"
                    or value == "bottom-left" or value == "bottom-right") then
                CONFIG.hud.fpsPosition = value
            elseif key == "fpsX" or key == "fpsY" or key == "statsX" or key == "statsY" then
                local position = tonumber(value)
                if position and position >= 0 and position <= 1 then
                    CONFIG.hud[key] = position
                end
            end
        end
        file:close()
    end
end

local scriptDirectory = thisScript().path:match("^(.*)[\\/]")
local UPDATE_CONFIG = {
    owner = "Revan234",
    repository = "PekanUI-Android",
    branch = "main",
    serverIp = "43.173.14.35",
    checkIntervalSeconds = 600,
}
local updateStatus = {
    active = false,
    visible = false,
    title = "",
    detail = "",
    completed = 0,
    total = 0,
    currentBytes = 0,
    finishedAt = 0,
}
local updateLog = {}
local updateLogPath = scriptDirectory and joinPath(scriptDirectory, ".pbrp-update-log") or nil

local function cleanUpdateLogField(value)
    return tostring(value or ""):gsub("[\r\n\t]", " ")
end

local function loadUpdateLog()
    if not updateLogPath then return end
    local file = io.open(updateLogPath, "rb")
    if not file then return end
    for line in file:lines() do
        local timestamp, title, detail = line:match("^([^\t]*)\t([^\t]*)\t(.*)$")
        if timestamp and title then
            updateLog[#updateLog + 1] = {
                timestamp = timestamp,
                title = title,
                detail = detail or "",
            }
        end
    end
    file:close()
    while #updateLog > 8 do table.remove(updateLog, 1) end
end

local function recordUpdateLog(title, detail)
    updateLog[#updateLog + 1] = {
        timestamp = os.date("%Y-%m-%d %H:%M:%S"),
        title = cleanUpdateLogField(title),
        detail = cleanUpdateLogField(detail),
    }
    while #updateLog > 8 do table.remove(updateLog, 1) end

    if not updateLogPath then
        print("[PBRP Updater] Lokasi file log update tidak tersedia.")
        return
    end
    local file, openError = io.open(updateLogPath, "wb")
    if not file then
        print("[PBRP Updater] Gagal menyimpan log update: " .. tostring(openError))
        return
    end
    for _, entry in ipairs(updateLog) do
        local wrote, writeError = file:write(entry.timestamp, "\t", entry.title, "\t", entry.detail, "\n")
        if not wrote then
            file:close()
            print("[PBRP Updater] Gagal menulis log update: " .. tostring(writeError))
            return
        end
    end
    local closed, closeError = file:close()
    if not closed then
        print("[PBRP Updater] Gagal menutup log update: " .. tostring(closeError))
    end
end

loadUpdateLog()

if scriptDirectory then
    local localLibrary = joinPath(scriptDirectory, "lib")
    package.path = table.concat({
        joinPath(scriptDirectory, "?.lua"),
        joinPath(scriptDirectory, "?", "init.lua"),
        joinPath(localLibrary, "?.lua"),
        joinPath(localLibrary, "?", "init.lua"),
        package.path,
    }, ";")
end

local imgui = require "mimgui"
local ffi = require "ffi"
local V2 = imgui.ImVec2

-- ---------- pemuat modul aman ----------
-- Jika satu modul (icons, inventory, dll) gagal dimuat, script TIDAK mati.
-- Modul pengganti kosong dipakai, dan penyebabnya dicatat di moonloader.log
-- serta ditampilkan di menu Beranda.
local loadErrors = {}
local function noop() end
local function stubModule(fields)
    return setmetatable(fields or {}, { __index = function() return noop end })
end
local function reportLoadError(name, err)
    local message = name .. ": " .. (tostring(err):gsub("\n.*", ""))
    loadErrors[#loadErrors + 1] = message
    print("[PBRP/PKU UI] Gagal memuat modul " .. message)
end
local function loadFactory(name, fallback, ...)
    local okRequire, factory = pcall(require, name)
    if not okRequire then
        reportLoadError(name, factory)
        return fallback
    end
    if type(factory) ~= "function" then
        reportLoadError(name, "modul tidak mengembalikan fungsi")
        return fallback
    end
    local okInit, result = pcall(factory, ...)
    if not okInit then
        reportLoadError(name, result)
        return fallback
    end
    return result or fallback
end

local icons = loadFactory("uijtrp.icons", stubModule({ navigation = {} }), imgui)
if type(icons.navigation) ~= "table" then icons.navigation = {} end

local featureCatalog = {}
do
    local okCatalog, catalog = pcall(require, "uijtrp.feature_catalog")
    if okCatalog and type(catalog) == "table" then
        featureCatalog = catalog
    elseif not okCatalog then
        reportLoadError("uijtrp.feature_catalog", catalog)
    end
end

local adminCommands = {}
do
    local okCommands, commands = pcall(require, "uijtrp.admin_commands")
    if okCommands and type(commands) == "table" then
        adminCommands = commands
    elseif not okCommands then
        reportLoadError("uijtrp.admin_commands", commands)
    end
end

local sampev
do
    local okEvents, events = pcall(require, "lib.samp.events")
    if not okEvents then
        okEvents, events = pcall(require, "samp.events")
    end
    if okEvents and type(events) == "table" then
        sampev = events
    else
        reportLoadError("lib.samp.events", events)
        sampev = {}
    end
end

-- ---------- state ----------
local menuOpen = imgui.new.bool(false)
local radialOpen = imgui.new.bool(false)
local adminOpen = imgui.new.bool(false)
local hudOpen = imgui.new.bool(true)
local playerSpawned = false
local adminLevel = -1
local canUseAdminUi
local activePage = 0
local pageStart = 0
local menuAnim = 0
local radialAnim = 0
local lastUiError = nil
local curAlpha = 1.0
local logoTex = nil
local navAnim, cardAnim, radialHover = {}, {}, {}
local hudState = { health = 100, armour = 0, healthGhost = 100, armourGhost = 0,
    hp = 100, ar = 0, lastHealth = 100, hitFlash = 0,
    hunger = nil, thirst = nil, needsAt = nil, weapon = nil, ammo = nil }

local function isPlayerUiReady()
    if playerSpawned then return true end
    local ok, spawned = pcall(sampIsLocalPlayerSpawned)
    return (ok and spawned) and true or false
end

-- catat error UI sekali saja di log, dan tampilkan di menu agar mudah dilacak
local lastLoggedError = nil
local function logUiError(tag, err)
    local text = tag .. ": " .. tostring(err)
    lastUiError = text:sub(1, 1800)
    if text ~= lastLoggedError then
        lastLoggedError = text
        print("[PBRP/PKU UI] " .. text)
    end
end

local function newBuf() return imgui.new.char[129]() end
local actionInput, sceneInput, shoutInput, whisperInput = newBuf(), newBuf(), newBuf(), newBuf()
local oocInput, reportInput, adoInput, askInput = newBuf(), newBuf(), newBuf(), newBuf()
local animationInput, propAnimationInput, interactionInput = newBuf(), newBuf(), newBuf()
local accentR = imgui.new.float(CONFIG.accent[1])
local accentG = imgui.new.float(CONFIG.accent[2])
local accentB = imgui.new.float(CONFIG.accent[3])
local accentPicker = imgui.new.float[3](CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3])
local accentStatus = ""
local fpsEnabled = imgui.new.bool(CONFIG.hud.showFps)
local hudSettingsStatus = ""

local radialItems = {
    { label = "INVENTORI", icon = "inventory", action = "inventory", hint = "Buka inventori server" },
    { label = "HANDPHONE", icon = "phone", action = "phone", hint = "Buka aplikasi handphone server" },
    { label = "KENDARAAN", icon = "vehicle", action = "vehicles", hint = "Buka garasi kendaraan" },
    { label = "GPS", icon = "map", action = "gps", hint = "Buka dialog GPS" },
    { label = "PANDUAN", icon = "help", command = "/help", hint = "/help" },
    { label = "PENGATURAN", icon = "settings", command = "/settings", hint = "/settings" },
    { label = "MASKER", icon = "user", command = "/mask", hint = "/mask" },
    { label = "ANIMASI", icon = "chat", command = "/elist", hint = "/elist" },
    { label = "ADMIN ONLINE", icon = "user", command = "/admins", hint = "/admins" },
    { label = "RIWAYAT WARN", icon = "help", command = "/mywarn", hint = "/mywarn" }
}
local adminRadialItem = { label = "ADMIN", icon = "settings", action = "admin", hint = "Buka panel command admin" }
local adminSearch = imgui.new.char[96]()
local adminArgs = imgui.new.char[256]()
local selectedAdminCommand = nil

-- ---------- helper umum ----------
local function approach(cur, target, speed, dt)
    return cur + (target - cur) * math.min(1, speed * dt)
end

local function smooth(t)
    t = math.max(0, math.min(1, t))
    return t * t * (3 - 2 * t)
end

local function lerp(a, b, t)
    return a + (b - a) * t
end

local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end

-- ---------- metrik HUD (FPS, ping, vital, uang) ----------
local hudNet = { ping = 0, id = -1, online = 0, money = nil, name = nil, at = -10 }
local fpsLive, fpsHist, fpsHistAt = 60, {}, 0
local FPS_HIST_N = 48
local lastMetricFrame = -1

local function fpsColor(f)
    if f >= 55 then return 0.40, 0.90, 0.62 end
    if f >= 30 then return 1.00, 0.78, 0.30 end
    return 1.00, 0.38, 0.42
end

local function pingColor(p)
    if p <= 80 then return 0.40, 0.90, 0.62 end
    if p <= 160 then return 1.00, 0.78, 0.30 end
    return 1.00, 0.38, 0.42
end

local function updateHudMetrics(dt)
    -- aman dipanggil dari beberapa frame: hanya satu kali per frame imgui
    local okFrame, frameId = pcall(imgui.GetFrameCount)
    if okFrame and frameId == lastMetricFrame then return end
    if okFrame then lastMetricFrame = frameId end

    dt = math.max(0.0005, dt or 0.016)
    local now = os.clock()
    fpsLive = approach(fpsLive, 1 / dt, 4, dt)
    if now - fpsHistAt >= 0.25 then
        fpsHistAt = now
        fpsHist[#fpsHist + 1] = fpsLive
        if #fpsHist > FPS_HIST_N then table.remove(fpsHist, 1) end
    end

    -- vital karakter
    local okH, hp = pcall(getCharHealth, PLAYER_PED)
    if okH and hp then
        hp = math.max(0, math.min(100, hp))
        if hp < hudState.lastHealth - 0.5 then hudState.hitFlash = 1 end
        hudState.lastHealth, hudState.hp = hp, hp
        hudState.health = approach(hudState.health, hp, 8, dt)
        if hudState.healthGhost < hudState.health then
            hudState.healthGhost = hudState.health
        else
            hudState.healthGhost = approach(hudState.healthGhost, hudState.health, 1.4, dt)
        end
    end
    local okA, ar = pcall(getCharArmour, PLAYER_PED)
    if okA and ar then
        ar = math.max(0, math.min(100, ar))
        hudState.ar = ar
        hudState.armour = approach(hudState.armour, ar, 8, dt)
        if hudState.armourGhost < hudState.armour then
            hudState.armourGhost = hudState.armour
        else
            hudState.armourGhost = approach(hudState.armourGhost, hudState.armour, 1.4, dt)
        end
    end
    hudState.hitFlash = math.max(0, hudState.hitFlash - dt * 2.5)

    -- senjata aktif
    local okW, weapon = pcall(getCurrentCharWeapon, PLAYER_PED)
    if okW and weapon and weapon > 0 then
        local okM, ammo = pcall(getAmmoInCharWeapon, PLAYER_PED, weapon)
        hudState.weapon, hudState.ammo = weapon, (okM and ammo) or nil
    else
        hudState.weapon, hudState.ammo = nil, nil
    end

    -- data jaringan & uang: cukup 1x per detik
    if now - hudNet.at >= 1.0 then
        hudNet.at = now
        pcall(function()
            local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            if id and id >= 0 then
                hudNet.id = id
                hudNet.ping = sampGetPlayerPing(id)
                local nick = sampGetPlayerNickname(id)
                if nick then hudNet.name = (nick:gsub("_", " ")) end
            end
            hudNet.online = sampGetPlayerCount(false)
        end)
        local getMoney = storeScore or getPlayerMoney
        if getMoney then
            local okMoney, value = pcall(getMoney, PLAYER_HANDLE)
            hudNet.money = (okMoney and tonumber(value)) or nil
        end
    end
end

local function col(r, g, b, a)
    return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, (a or 1) * curAlpha))
end

local function colA(a)
    return col(CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3], a)
end

local function accentV4(a)
    return imgui.ImVec4(CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3], a or 1)
end

local function applyAccentStyle()
    local colors = imgui.GetStyle().Colors
    local v4 = imgui.ImVec4
    local a = CONFIG.accent
    colors[imgui.Col.Border] = v4(a[1], a[2], a[3], 0.28)
    colors[imgui.Col.Button] = v4(a[1] * 0.55, a[2] * 0.55, a[3] * 0.55, 1)
    colors[imgui.Col.ButtonHovered] = v4(a[1], a[2], a[3], 1)
    colors[imgui.Col.ButtonActive] = v4(a[1] * 0.8, a[2] * 0.8, a[3] * 0.8, 1)
    colors[imgui.Col.CheckMark] = v4(a[1], a[2], a[3], 1)
    colors[imgui.Col.ScrollbarGrab] = v4(a[1], a[2], a[3], 0.45)
    colors[imgui.Col.ScrollbarGrabHovered] = v4(a[1], a[2], a[3], 0.75)
    colors[imgui.Col.ScrollbarGrabActive] = v4(a[1], a[2], a[3], 1)
end

local function sendCommand(command) sampSendChat(command) end
local function getAccent()
    return CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3]
end
local assetDirectory = joinPath(scriptDirectory or ".", "assets")

local uiSounds = loadFactory("uijtrp.ui_sounds", stubModule())
local phoneMedia = loadFactory("uijtrp.phone_media", stubModule())
local phoneSoundDirectory = joinPath(scriptDirectory or ".", "jtrp_phone")
local phoneUI = loadFactory("uijtrp.phone_ui", stubModule(),
    imgui, icons, V2, ffi, phoneMedia, sendCommand, uiSounds,
    isPlayerUiReady, getAccent, phoneSoundDirectory)
local inventoryUI = loadFactory("uijtrp.inventory_ui", stubModule(),
    imgui, icons, V2, col, colA, getAccent,
    sendCommand, uiSounds, isPlayerUiReady)
local interactionUI = loadFactory("uijtrp.interaction_ui", stubModule({
    update = noop, isOpen = function() return false end,
}), imgui, V2, col, sendCommand, inventoryUI, isPlayerUiReady)
local vehiclesUI = loadFactory("uijtrp.vehicles_ui", stubModule(),
    imgui, V2, sendCommand, uiSounds, isPlayerUiReady, getAccent)
local vipRubyUI = loadFactory("uijtrp.vipruby_ui", stubModule(),
    imgui, V2, ffi, sendCommand, isPlayerUiReady)
local cctvUI = loadFactory("uijtrp.cctv_ui", stubModule({
    isOpen = function() return false end, close = noop,
}), imgui, V2, sendCommand, isPlayerUiReady)
local adminPanelUI = loadFactory("uijtrp.admin_panel_ui", stubModule({
    open = noop, close = noop, isOpen = function() return false end,
    onServerMessage = function() return false end, reset = noop,
}), imgui, V2, ffi, sendCommand, isPlayerUiReady, joinPath(assetDirectory, "pekanorganiz.png"))
local factionPanelUI = loadFactory("uijtrp.faction_panel_ui", stubModule({
    onShowDialog = function() return nil end, isOpen = function() return false end,
    close = noop, reset = noop,
}), imgui, V2, isPlayerUiReady)
local mechanicServiceUI = loadFactory("uijtrp.mechanic_service_ui", stubModule({
    onShowDialog = function() return nil end, isOpen = function() return false end,
    close = noop, reset = noop,
}), imgui, V2, isPlayerUiReady)
local businessUI = loadFactory("uijtrp.business_ui", stubModule({
    onShowDialog = function() return nil end, isOpen = function() return false end,
    close = noop, reset = noop,
}), imgui, V2, isPlayerUiReady, joinPath(assetDirectory, "pbrp-logo.png"))
local loginUI = loadFactory("uijtrp.login_ui", stubModule({
    onShowDialog = function() return nil end, isOpen = function() return false end,
    reset = noop,
}), imgui, V2, ffi, joinPath(assetDirectory, "sound", "login_feedback.wav"), uiSounds,
    joinPath(assetDirectory, "pbrp-logo.png"))
loginUI.characterSelect = loadFactory("uijtrp.character_select_ui", stubModule({
    onShowDialog = function() return nil end, isOpen = function() return false end,
    reset = noop,
}), imgui, V2, joinPath(assetDirectory, "sound", "f2383602-54e8-4e0b-b171-eec9722a328f.wav"))
local notificationUI = loadFactory("uijtrp.notification_ui", stubModule(),
    imgui, V2, isPlayerUiReady, uiSounds)
notificationUI.setInventoryOwner(inventoryUI.ownsTextdraw)
local factionVehicleUI = loadFactory("uijtrp.faction_vehicle_ui", stubModule({
    toggle = noop, isOpen = function() return false end, reset = noop,
}), imgui, V2, isPlayerUiReady, sendCommand)

local okTextdrawReader, textdrawReader = pcall(require, "uijtrp.td_reader")
if not okTextdrawReader or type(textdrawReader) ~= "table" then
    reportLoadError("uijtrp.td_reader", textdrawReader)
    textdrawReader = nil
end

local function chainInventoryTextdrawEvent(name, callback)
    local previous = sampev[name]
    sampev[name] = function(...)
        local ok, result = pcall(callback, ...)
        if not ok then
            logUiError(name, result)
            result = nil
        end
        local previousResult
        if previous then
            previousResult = previous(...)
        end
        if result == false or previousResult == false then
            return false
        end
        return previousResult
    end
end

chainInventoryTextdrawEvent("onShowTextDraw", inventoryUI.onShowTextDraw)
chainInventoryTextdrawEvent("onTextDrawSetString", inventoryUI.onTextDrawSetString)
chainInventoryTextdrawEvent("onTextDrawHide", inventoryUI.onTextDrawHide)
chainInventoryTextdrawEvent("onShowTextDraw", vehiclesUI.onShowTextDraw)
chainInventoryTextdrawEvent("onTextDrawSetString", vehiclesUI.onTextDrawSetString)
chainInventoryTextdrawEvent("onTextDrawHide", vehiclesUI.onTextDrawHide)
chainInventoryTextdrawEvent("onShowDialog", factionPanelUI.onShowDialog)
chainInventoryTextdrawEvent("onShowDialog", mechanicServiceUI.onShowDialog)
chainInventoryTextdrawEvent("onShowDialog", businessUI.onShowDialog)
chainInventoryTextdrawEvent("onShowDialog", loginUI.onShowDialog)
chainInventoryTextdrawEvent("onShowDialog", loginUI.characterSelect.onShowDialog)

local loadingUI = loadFactory("uijtrp.loading_screen", stubModule(),
    imgui, V2, joinPath(assetDirectory, "jtrp_loading.png"))
if not isPlayerUiReady() then
    loadingUI.startConnection()
end
loadFactory("uijtrp.animated_logo", nil,
    imgui, V2, joinPath(assetDirectory, "logo_frames"), function() return true end)
loadFactory("uijtrp.speedometer", nil, imgui, V2, approach, isPlayerUiReady)

local DIM = imgui.ImVec4(0.62, 0.66, 0.74, 1.0)

local function trim(value)
    return value:match("^%s*(.-)%s*$")
end

local function readInput(buffer)
    return trim(ffi.string(buffer))
end

local function clearInput(buffer)
    ffi.fill(buffer, ffi.sizeof(buffer), 0)
end

local function submitInput(command, buffer)
    local value = readInput(buffer)
    if value == "" then
        sampAddChatMessage("[" .. CONFIG.shortTag .. "] Isi pesan terlebih dahulu.", 0xFFFFB16A)
        return
    end
    sampSendChat(command .. " " .. value)
    clearInput(buffer)
end

-- buka link di browser (fallback: salin ke clipboard)
pcall(function()
    ffi.cdef [[ void* ShellExecuteA(void* hwnd, const char* op, const char* file, const char* params, const char* dir, int show); ]]
end)

local function openUrl(url)
    local copied, copyError = pcall(imgui.SetClipboardText, url)
    if copied then
        sampAddChatMessage("[" .. CONFIG.shortTag .. "] Link disalin. Tempel di browser Android: " .. url, 0xFFFFB16A)
        return true
    end
    sampAddChatMessage("[" .. CONFIG.shortTag .. "] Tidak dapat membuka browser atau menyalin link: "
        .. tostring(copyError), 0xFFFF6A6A)
    return false
end

local function openGameBrowser()
    sampAddChatMessage("[" .. CONFIG.shortTag .. "] Browser WebView PC tidak tersedia di Android.", 0xFFFFB16A)
    return openUrl(CONFIG.websiteUrl)
end

local function openServerInventory()
    menuOpen[0] = false
    sampSendChat("/rpui_inventory_data")
end

local function openServerPhone()
    menuOpen[0] = false
    sampSendChat("/rpui_phone")
end

local function normalizeServerMessage(text)
    return tostring(text or "")
        :gsub("{%x%x%x%x%x%x}", "")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
end

local previousServerMessageHandler = sampev.onServerMessage
sampev.onServerMessage = function(messageColor, text)
    local originalText = text
    local ok, handled = pcall(function()
        local clean = normalizeServerMessage(text)
        if adminPanelUI.onServerMessage(clean) then
            return true
        end
        if vipRubyUI.onServerMessage(clean) then
            radialItems[11] = vipRubyUI.hasAccess() and {
                label = "VIP RUBY", icon = "settings", action = "vipruby",
                hint = "Pengaturan musik, label, dan object"
            } or nil
            return true
        end
        if cctvUI.onServerMessage(clean) then
            return true
        end
        local hungerValue, thirstValue = clean:match("^@PBRPUI:HUD:NEEDS:(%d+):(%d+)$")
        if hungerValue then
            hudState.hunger = math.min(100, tonumber(hungerValue))
            hudState.thirst = math.min(100, tonumber(thirstValue))
            hudState.needsAt = os.clock()
            return true
        end
        local receivedAdminLevel = clean:match("^@PBRPUI:ADMIN:LEVEL:(%d+)$")
        if receivedAdminLevel then
            adminLevel = tonumber(receivedAdminLevel) or 0
            radialItems[10] = canUseAdminUi() and adminRadialItem
                or { label = "RIWAYAT WARN", icon = "help", command = "/mywarn", hint = "/mywarn" }
            if not canUseAdminUi() then adminOpen[0] = false end
            return true
        end
        if loadingUI.onServerMessage(clean) then
            return true
        end
        if inventoryUI.onServerMessage(clean) then
            radialOpen[0] = false
            return true
        end
        local vehicleMessage = vehiclesUI.onServerMessage(clean)
        local phoneMessage = phoneUI.onServerMessage(clean)
        local notificationMessage = notificationUI.onServerMessage(clean)
        if vehicleMessage or phoneMessage or notificationMessage then
            return true
        end
        return clean:sub(1, 8) == "@PBRPUI:"
    end)
    if not ok then
        logUiError("onServerMessage", handled)
    elseif handled then
        return false
    end
    if previousServerMessageHandler then
        return previousServerMessageHandler(messageColor, originalText)
    end
end

local function chainLoadingEvent(name, callback)
    local previous = sampev[name]
    sampev[name] = function(...)
        local ok, err = pcall(callback)
        if not ok then logUiError(name, err) end
        if previous then
            return previous(...)
        end
    end
end

chainLoadingEvent("onConnectionRequestAccepted", loadingUI.startConnection)
chainLoadingEvent("onSendRequestSpawn", loadingUI.startConnection)
for _, name in ipairs({
    "onConnectionLost",
    "onConnectionBanned",
    "onConnectionAttemptFailed",
    "onConnectionNoFreeSlot",
    "onConnectionPasswordInvalid",
    "onConnectionClosed",
}) do
    chainLoadingEvent(name, loadingUI.cancelConnection)
end
chainLoadingEvent("onConnectionClosed", function()
    loginUI.reset()
    loginUI.characterSelect.reset()
end)

local function radialAction(item)
    if item.action == "inventory" then
        radialOpen[0] = false
        openServerInventory()
    elseif item.action == "phone" then
        radialOpen[0] = false
        openServerPhone()
    elseif item.action == "vehicles" then
        radialOpen[0] = false
        vehiclesUI.open()
    elseif item.action == "gps" then
        radialOpen[0] = false
        lua_thread.create(function()
            wait(180)
            if isSampAvailable() and isPlayerUiReady() then
                sampSendChat("/rpui_gps")
            end
        end)
    elseif item.action == "admin" then
        radialOpen[0] = false
        menuOpen[0] = false
        adminPanelUI.open()
    elseif item.action == "vipruby" then
        radialOpen[0] = false
        sampSendChat("/vrubyui")
    elseif item.command then
        sampSendChat(item.command)
        radialOpen[0] = false
    end
end

canUseAdminUi = function()
    return adminLevel > 0 and #adminCommands > 0
end

local function toggleAdminUi()
    if adminPanelUI.isOpen() then
        adminPanelUI.close()
        return
    end
    if not canUseAdminUi() or not isSampAvailable() or not isPlayerUiReady()
        or phoneUI.isOpen() or inventoryUI.isOpen() or vehiclesUI.isOpen() or vipRubyUI.isOpen() then
        return
    end
    menuOpen[0] = false
    radialOpen[0] = false
    adminPanelUI.open()
end

local adminFrame
adminFrame = imgui.OnFrame(
    function() return adminOpen[0] and canUseAdminUi() and isSampAvailable() and isPlayerUiReady() end,
    function()
        adminFrame.LockPlayer = adminOpen[0]
        local display = imgui.GetIO().DisplaySize
        local width = math.min(800, display.x - 32)
        local height = math.min(650, display.y - 32)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.SetNextWindowPos(V2((display.x - width) / 2, (display.y - height) / 2), imgui.Cond.Always)
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.075, 0.025, 0.035, 0.98))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.82, 0.10, 0.15, 0.85))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.16, 0.055, 0.065, 1.0))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.25, 0.075, 0.085, 1.0))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.45, 0.055, 0.075, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.72, 0.09, 0.12, 1.0))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.56, 0.04, 0.07, 1.0))

        local flags = imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoSavedSettings
        imgui.Begin("ADMIN COMMAND CENTER##PBRP_admin", nil, flags)
        imgui.TextColored(imgui.ImVec4(1.0, 0.28, 0.32, 1.0), "PANEL COMMAND ADMIN")
        imgui.SameLine()
        imgui.Text(string.format("Level Admin %d  |  %d command", adminLevel, #adminCommands))
        imgui.SameLine()
        if imgui.Button("TUTUP##admin_close") then adminOpen[0] = false end
        imgui.Separator()
        imgui.TextWrapped("Pilih command, isi parameter bila diperlukan, lalu jalankan. Izin tetap diperiksa oleh server.")
        imgui.InputTextWithHint("##admin_search", "Cari nama command...", adminSearch, ffi.sizeof(adminSearch))

        local search = string.lower(trim(ffi.string(adminSearch)))
        local shown = 0
        local limitedRank = adminLevel == 2 or adminLevel == 3
        imgui.BeginChild("##admin_command_list", V2(0, math.max(150, height - 225)), true)
        for _, command in ipairs(adminCommands) do
            if command.level <= adminLevel and (not limitedRank or command.limitedAccess)
                and (search == "" or command.name:find(search, 1, true)) then
                shown = shown + 1
                local label = string.format("/%s    [Admin %d]+##admin_cmd_%s", command.name, command.level, command.name)
                if imgui.Button(label, V2(-1, 32)) then
                    selectedAdminCommand = command
                    clearInput(adminArgs)
                end
            end
        end
        if shown == 0 then imgui.Text("Tidak ada command yang cocok dengan pencarian.") end
        imgui.EndChild()

        if selectedAdminCommand then
            imgui.Text("Command: /" .. selectedAdminCommand.name)
            imgui.InputTextWithHint("##admin_arguments", "Parameter (opsional)", adminArgs, ffi.sizeof(adminArgs))
            local args = trim(ffi.string(adminArgs))
            local preview = "/" .. selectedAdminCommand.name .. (args ~= "" and (" " .. args) or "")
            imgui.TextDisabled("Akan dikirim: " .. preview)
            if imgui.Button("JALANKAN COMMAND##admin_run", V2(230, 38)) then
                sampSendChat(preview)
                adminOpen[0] = false
            end
            imgui.SameLine()
            if imgui.Button("BERSIHKAN##admin_clear", V2(160, 38)) then
                selectedAdminCommand = nil
                clearInput(adminArgs)
            end
        else
            imgui.TextDisabled("Pilih command dari daftar untuk mulai.")
        end
        imgui.End()
        imgui.PopStyleColor(7)
    end
)

local function strokePath(dl, color, thickness)
    local ok = pcall(function() dl:PathStroke(color, 0, thickness) end)
    if not ok then dl:PathStroke(color, false, thickness) end
end

-- ---------- logo ----------
local function drawLogo(dl, cx, cy, size)
    local half = size / 2
    if logoTex then
        dl:AddImage(logoTex, V2(cx - half, cy - half), V2(cx + half, cy + half),
            V2(0, 0), V2(1, 1), col(1, 1, 1, 1))
    else
        dl:AddCircleFilled(V2(cx, cy), half, colA(0.18), 48)
        dl:AddCircle(V2(cx, cy), half, colA(0.9), 48, 2.0)
        local txt = CONFIG.shortTag
        local ts = imgui.CalcTextSize(txt)
        dl:AddText(V2(cx - ts.x / 2, cy - ts.y / 2), colA(1.0), txt)
    end
end

-- ---------- komponen UI ----------
-- kartu klik gaya FiveM, mengembalikan true jika diklik
local function drawCard(id, title, subtitle, w, h, icon)
    local pos = imgui.GetCursorScreenPos()
    imgui.InvisibleButton(id, V2(w, h))
    local hovered = imgui.IsItemHovered()
    local clicked = imgui.IsItemClicked(0)
    local a = approach(cardAnim[id] or 0, hovered and 1 or 0, 14, imgui.GetIO().DeltaTime)
    cardAnim[id] = a

    local dl = imgui.GetWindowDrawList()
    local p2 = V2(pos.x + w, pos.y + h)
    dl:PushClipRect(pos, p2, true)
    dl:AddRectFilled(pos, p2, col(0.10 + 0.05 * a, 0.11 + 0.05 * a, 0.15 + 0.06 * a, 1), 10)
    dl:AddRect(pos, p2, colA(0.06 + 0.55 * a), 10)
    -- indikator aksen di kiri yang memanjang saat hover
    local barH = (h - 24) * (0.55 + 0.45 * a)
    local by = pos.y + (h - barH) / 2
    dl:AddRectFilled(V2(pos.x + 10, by), V2(pos.x + 13 + 2 * a, by + barH), colA(0.5 + 0.5 * a), 2)

    local tx = pos.x + 26 + 3 * a
    if icon then
        local iy = pos.y + (h - 22) / 2
        dl:AddCircleFilled(V2(pos.x + 29, pos.y + h / 2), 15, colA(0.10 + 0.12 * a), 24)
        icons.draw(dl, icon, pos.x + 18, iy, 22, colA(0.72 + 0.28 * a), col(0.07, 0.08, 0.11, 1))
        tx = pos.x + 52 + 3 * a
    end
    if subtitle then
        dl:AddText(V2(tx, pos.y + h * 0.5 - 17), col(0.95, 0.96, 0.98, 1), title)
        dl:AddText(V2(tx, pos.y + h * 0.5 + 3), colA(0.55 + 0.45 * a), subtitle)
    else
        local ts = imgui.CalcTextSize(title)
        dl:AddText(V2(tx, pos.y + h * 0.5 - ts.y / 2), col(0.95, 0.96, 0.98, 1), title)
    end
    dl:PopClipRect()
    return clicked
end

local function commandGrid(items, w)
    local gap = 10
    local cw = (w - gap) / 2
    for i, it in ipairs(items) do
        if (i - 1) % 2 == 1 then imgui.SameLine(0, gap) end
        if drawCard("##c" .. i .. it[2], it[1], it[2], cw, 58, icons.command(it[2])) then
            sampSendChat(it[2])
        end
    end
end

local function sectionTitle(text)
    imgui.Spacing()
    imgui.TextColored(accentV4(1), text)
    imgui.Spacing()
end

local function note(text)
    imgui.Spacing()
    imgui.PushStyleColor(imgui.Col.Text, DIM)
    imgui.TextWrapped(text)
    imgui.PopStyleColor()
end

local function inputAction(label, hint, buffer, command, buttonLabel, w)
    imgui.TextColored(DIM, label)
    imgui.PushItemWidth(math.max(80, w - 158))
    local entered = imgui.InputTextWithHint("##in" .. command, hint, buffer, ffi.sizeof(buffer),
        imgui.InputTextFlags.EnterReturnsTrue)
    imgui.PopItemWidth()
    imgui.SameLine(0, 8)
    local pressed = imgui.Button(buttonLabel .. "##b" .. command, V2(150, 0))
    if entered or pressed then
        submitInput(command, buffer)
    end
    imgui.Spacing()
end

local function linkCards(w)
    local gap = 10
    local cw = (w - gap) / 2
    if drawCard("##lnkdc", "Gabung Discord", CONFIG.discordUrl, cw, 58) then openUrl(CONFIG.discordUrl) end
    imgui.SameLine(0, gap)
    if drawCard("##lnkweb", "Kunjungi Website", CONFIG.websiteUrl, cw, 58) then openUrl(CONFIG.websiteUrl) end
end

local function getPlayerName()
    local ok, name = pcall(function()
        local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        return sampGetPlayerNickname(id)
    end)
    if ok and name and name ~= "" then return (name:gsub("_", " ")) end
    return "Warga"
end

-- ---------- halaman ----------
local function liveTile(dl, x, y, w, h, label, valueText, r, g, b, ratio)
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), col(0.10, 0.11, 0.15, 1), 10)
    dl:AddRect(V2(x, y), V2(x + w, y + h), colA(0.14), 10)
    dl:AddRectFilled(V2(x, y + 14), V2(x + 3, y + h - 14), col(r, g, b, 0.9), 2)
    dl:AddText(V2(x + 14, y + 9), col(0.62, 0.64, 0.76, 1), label)
    dl:AddText(V2(x + 14, y + 28), col(1, 1, 1, 1), valueText)
    if ratio then
        local bx0, bx1, by = x + 14, x + w - 12, y + h - 12
        dl:AddRectFilled(V2(bx0, by), V2(bx1, by + 5), col(1, 1, 1, 0.09), 3)
        if ratio > 0.01 then
            dl:AddRectFilled(V2(bx0, by), V2(bx0 + (bx1 - bx0) * math.min(1, ratio), by + 5),
                col(r, g, b, 1), 3)
        end
    end
end

local function drawLiveTiles(w)
    local dl = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()
    local gap, h = 10, 62
    local cw = (w - gap * 3) / 4
    imgui.Dummy(V2(w, h))
    local fr, fg, fb = fpsColor(fpsLive)
    local pr, pg, pb = pingColor(hudNet.ping)
    liveTile(dl, pos.x, pos.y, cw, h, "HEALTH",
        string.format("%d%%", math.floor(hudState.health + 0.5)), 0.98, 0.36, 0.52, hudState.health / 100)
    liveTile(dl, pos.x + (cw + gap), pos.y, cw, h, "ARMOR",
        string.format("%d%%", math.floor(hudState.armour + 0.5)), 0.56, 0.52, 1.0, hudState.armour / 100)
    liveTile(dl, pos.x + (cw + gap) * 2, pos.y, cw, h, "FPS",
        tostring(math.floor(fpsLive + 0.5)), fr, fg, fb, nil)
    liveTile(dl, pos.x + (cw + gap) * 3, pos.y, cw, h, "PING",
        tostring(hudNet.ping) .. " ms", pr, pg, pb, nil)
end

local function drawHome(w)
    local dl = imgui.GetWindowDrawList()
    local pos = imgui.GetCursorScreenPos()
    local h = 150
    imgui.Dummy(V2(w, h))
    local p2 = V2(pos.x + w, pos.y + h)
    dl:AddRectFilled(pos, p2, col(0.09, 0.10, 0.14, 1), 14)
    dl:AddRect(pos, p2, colA(0.35), 14)
    dl:AddRectFilledMultiColor(V2(pos.x + 18, p2.y - 5), V2(p2.x - 18, p2.y - 2),
        colA(0.9), colA(0.0), colA(0.0), colA(0.9))

    local pulse = math.sin(os.clock() * 2.2) * 0.5 + 0.5
    local lcx, lcy = pos.x + 24 + 46, pos.y + h / 2 - 4
    dl:AddCircle(V2(lcx, lcy), 52 + 3 * pulse, colA(0.15 + 0.25 * pulse), 56, 2.0)
    drawLogo(dl, lcx, lcy, 84)

    local tx = pos.x + 140
    dl:AddText(V2(tx, pos.y + 26), colA(1.0), "SELAMAT DATANG")
    local title = CONFIG.serverName .. " " .. CONFIG.serverTag
    dl:AddText(V2(tx, pos.y + 48), col(1, 1, 1, 1), title)
    dl:AddText(V2(tx + 1, pos.y + 48), col(1, 1, 1, 1), title)
    dl:AddText(V2(tx, pos.y + 72), col(0.78, 0.82, 0.90, 1), "Halo, " .. getPlayerName() .. ". Selamat bermain dan tetap roleplay!")
    local skin = 0
    local okSkin, model = pcall(getCharModel, PLAYER_PED)
    if okSkin and model then skin = math.floor(model) end
    dl:AddRectFilled(V2(tx, pos.y + 101), V2(pos.x + w - 18, pos.y + 136),
        col(0.14, 0.15, 0.20, 0.95), 8)
    dl:AddCircleFilled(V2(tx + 17, pos.y + 118), 9, colA(0.9), 20)
    dl:AddText(V2(tx + 34, pos.y + 108),
        col(0.90, 0.92, 0.96, 1), string.format("KARAKTER  ·  SKIN %d", skin))
    dl:AddText(V2(tx + 34, pos.y + 123), col(0.64, 0.69, 0.78, 1),
        "Model mengikuti skin aktif karakter")

    sectionTitle("STATUS LIVE")
    drawLiveTiles(w)

    sectionTitle("AKSES CEPAT")
    commandGrid({
        { "Lihat status karakter", "/stats" },
        { "Buka panduan server", "/help" },
        { "Lihat kendaraan saya", "/myv" },
        { "Pengaturan karakter", "/settings" },
    }, w)

    sectionTitle("APLIKASI")
    if drawCard("##pbrp_browser", "Browser", "Buka browser web PekanBaru", w, 58, "map") then
        openGameBrowser()
    end

    sectionTitle("KOMUNITAS")
    linkCards(w)

    imgui.Spacing()
    imgui.TextColored(imgui.ImVec4(0.55, 0.78, 0.96, 1.0), "PETUNJUK")
    note("Tekan F2 untuk membuka menu utama, atau M untuk radial (tekan 1-0 untuk memilih cepat). Gunakan tombol Browser di Beranda atau /browser untuk membuka browser web. Inventori dan handphone tersedia dari radial.")

    sectionTitle("LOG UPDATE PEKANBARU UI")
    if updateStatus.active then
        imgui.TextColored(imgui.ImVec4(0.96, 0.70, 0.30, 1), "Sedang berjalan: " .. updateStatus.title)
        if updateStatus.detail ~= "" then imgui.TextWrapped(updateStatus.detail) end
    end
    if #updateLog == 0 then
        note("Belum ada riwayat pemeriksaan atau update.")
    else
        for index = #updateLog, 1, -1 do
            local entry = updateLog[index]
            imgui.Separator()
            imgui.TextColored(imgui.ImVec4(0.68, 0.75, 0.88, 1), entry.timestamp .. "  |  " .. entry.title)
            if entry.detail ~= "" then imgui.TextWrapped(entry.detail) end
        end
    end

    if #loadErrors > 0 then
        sectionTitle("MODUL GAGAL DIMUAT")
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0.98, 0.45, 0.35, 1.0))
        for _, message in ipairs(loadErrors) do
            imgui.TextWrapped("- " .. message)
        end
        imgui.PopStyleColor()
        note("Pastikan folder uiPBRP berisi semua modul, lalu muat ulang script dengan CTRL + R.")
    end
end

local function saveAccent()
    pcall(createDirectory, joinPath(getWorkingDirectory(), "config"))
    local file, err = io.open(accentPath, "w")
    if not file then
        accentStatus = "Warna gagal disimpan: " .. tostring(err)
        return
    end
    file:write(string.format("%.3f\n%.3f\n%.3f\n",
        CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3]))
    file:close()
    accentStatus = "Warna aksen berhasil disimpan."
end

local function saveHudSettings()
    local okDir, dirErr = pcall(createDirectory, joinPath(getWorkingDirectory(), "config"))
    if not okDir then
        hudSettingsStatus = "Pengaturan HUD gagal disimpan: " .. tostring(dirErr)
        return false
    end
    local file, err = io.open(hudSettingsPath, "w")
    if not file then
        hudSettingsStatus = "Pengaturan HUD gagal disimpan: " .. tostring(err)
        return false
    end
    local wrote, writeErr = file:write(
        "showFps=", CONFIG.hud.showFps and "true" or "false", "\n",
        "fpsPosition=", CONFIG.hud.fpsPosition, "\n",
        "fpsX=", CONFIG.hud.fpsX and string.format("%.5f", CONFIG.hud.fpsX) or "", "\n",
        "fpsY=", CONFIG.hud.fpsY and string.format("%.5f", CONFIG.hud.fpsY) or "", "\n",
        "statsX=", CONFIG.hud.statsX and string.format("%.5f", CONFIG.hud.statsX) or "", "\n",
        "statsY=", CONFIG.hud.statsY and string.format("%.5f", CONFIG.hud.statsY) or "", "\n")
    if not wrote then
        file:close()
        hudSettingsStatus = "Pengaturan HUD gagal disimpan: " .. tostring(writeErr)
        return false
    end
    local closed, closeErr = file:close()
    if not closed then
        hudSettingsStatus = "Pengaturan HUD gagal disimpan: " .. tostring(closeErr)
        return false
    end
    hudSettingsStatus = "Pengaturan posisi HUD berhasil disimpan."
    return true
end

local function drawAppearance(w)
    sectionTitle("TEMA UI ROLEPLAY")
    imgui.TextWrapped("Atur warna aksen untuk menu RPUI, radial, HUD, inventori, dan dialog Lua.")
    imgui.Spacing()
    imgui.PushItemWidth(w)
    accentPicker[0], accentPicker[1], accentPicker[2] =
        accentR[0], accentG[0], accentB[0]
    if imgui.ColorPicker3("Warna aksen##accent_picker", accentPicker) then
        accentR[0], accentG[0], accentB[0] =
            accentPicker[0], accentPicker[1], accentPicker[2]
    end
    imgui.PopItemWidth()
    CONFIG.accent = { accentR[0], accentG[0], accentB[0] }
    applyAccentStyle()
    local preview = imgui.GetWindowDrawList()
    local p = imgui.GetCursorScreenPos()
    preview:AddRectFilled(p, V2(p.x + w, p.y + 34), colA(1), 8)
    imgui.Dummy(V2(w, 38))
    if imgui.Button("SIMPAN WARNA##accent_save", V2(w, 38)) then
        saveAccent()
    end
    if imgui.Button("PULIHKAN DEFAULT##accent_reset", V2(w, 38)) then
        accentR[0], accentG[0], accentB[0] = 0.86, 0.12, 0.16
        accentPicker[0], accentPicker[1], accentPicker[2] = 0.86, 0.12, 0.16
        CONFIG.accent = { accentR[0], accentG[0], accentB[0] }
        saveAccent()
    end
    if accentStatus ~= "" then
        imgui.TextWrapped(accentStatus)
    end

    sectionTitle("WIDGET FPS & PING")
    imgui.TextWrapped("Atur visibilitas dan posisi panel FPS, ping, serta jam. Perubahan langsung terlihat.")
    imgui.TextWrapped("Gunakan /rpuihudedit untuk menggeser panel HUD dengan mouse. Posisi tersimpan saat mouse dilepas.")
    if imgui.Button("MODE GESER HUD##hud_edit_toggle", V2(w, 38)) then
        CONFIG.hud.toggleEdit()
    end
    if imgui.Checkbox("Tampilkan FPS dan ping##hud_fps_visible", fpsEnabled) then
        CONFIG.hud.showFps = fpsEnabled[0]
    end

    local buttonW = (w - 10) / 2
    if imgui.Button((CONFIG.hud.fpsX == nil and CONFIG.hud.fpsPosition == "top-left" and "KIRI ATAS (AKTIF)" or "KIRI ATAS")
        .. "##fps_top_left", V2(buttonW, 36)) then
        CONFIG.hud.fpsPosition = "top-left"
        CONFIG.hud.fpsX, CONFIG.hud.fpsY = nil, nil
    end
    imgui.SameLine(0, 10)
    if imgui.Button((CONFIG.hud.fpsX == nil and CONFIG.hud.fpsPosition == "top-right" and "KANAN ATAS (AKTIF)" or "KANAN ATAS")
        .. "##fps_top_right", V2(buttonW, 36)) then
        CONFIG.hud.fpsPosition = "top-right"
        CONFIG.hud.fpsX, CONFIG.hud.fpsY = nil, nil
    end
    if imgui.Button((CONFIG.hud.fpsX == nil and CONFIG.hud.fpsPosition == "bottom-left" and "KIRI BAWAH (AKTIF)" or "KIRI BAWAH")
        .. "##fps_bottom_left", V2(buttonW, 36)) then
        CONFIG.hud.fpsPosition = "bottom-left"
        CONFIG.hud.fpsX, CONFIG.hud.fpsY = nil, nil
    end
    imgui.SameLine(0, 10)
    if imgui.Button((CONFIG.hud.fpsX == nil and CONFIG.hud.fpsPosition == "bottom-right" and "KANAN BAWAH (AKTIF)" or "KANAN BAWAH")
        .. "##fps_bottom_right", V2(buttonW, 36)) then
        CONFIG.hud.fpsPosition = "bottom-right"
        CONFIG.hud.fpsX, CONFIG.hud.fpsY = nil, nil
    end
    if imgui.Button("SIMPAN PENGATURAN HUD##hud_settings_save", V2(w, 38)) then
        saveHudSettings()
    end
    if hudSettingsStatus ~= "" then
        imgui.TextWrapped(hudSettingsStatus)
    end
end

local function drawRoleplay(w)
    sectionTitle("AKSI & SUASANA")
    inputAction("Aksi karakter (/me)", "Contoh: merapikan jaket", actionInput, "/me", "Kirim aksi", w)
    inputAction("Situasi / deskripsi (/do)", "Contoh: cuaca terlihat mendung", sceneInput, "/do", "Kirim deskripsi", w)
    inputAction("Keterangan situasi 3D (/ado)", "Contoh: sedang menunggu seseorang", adoInput, "/ado", "Pasang keterangan", w)
    sectionTitle("ANIMASI")
    inputAction("Animasi (/e)", "Nama animasi", animationInput, "/e", "Jalankan animasi", w)
    inputAction("Animasi properti (/eprop)", "Nama animasi properti", propAnimationInput, "/eprop", "Jalankan animasi", w)
    inputAction("Animasi interaksi (/einter)", "Nama animasi interaksi", interactionInput, "/einter", "Jalankan animasi", w)
    note("Untuk menghapus keterangan /ado, isi kolom dengan off. Teks aksi mengikuti mekanisme roleplay server.")
end

local function drawCommunication(w)
    sectionTitle("KANAL PERCAKAPAN")
    inputAction("Teriak - jangkauan lokal (/s)", "Pesan untuk area sekitar", shoutInput, "/s", "Kirim teriakan", w)
    inputAction("Berbisik - jarak dekat (/w)", "Pesan untuk pemain terdekat", whisperInput, "/w", "Kirim bisikan", w)
    inputAction("Chat OOC lokal (/b)", "Pesan di luar karakter", oocInput, "/b", "Kirim OOC", w)
    inputAction("Lapor ke administrator (/report)", "Jelaskan laporan dengan singkat", reportInput, "/report", "Kirim laporan", w)
end

local function drawVehicles(w)
    sectionTitle("KENDARAAN")
    if drawCard("##vehicles_lua_menu", "Buka garasi UI", "Daftar kendaraan, status, pelacakan, dan kontrol kendaraan terdekat", w, 68, "vehicle") then
        menuOpen[0] = false
        vehiclesUI.open()
    end
    imgui.Spacing()
    commandGrid({
        { "Daftar kendaraan saya", "/myv" },
        { "Nyalakan / matikan mesin", "/en" },
        { "Atur jendela kendaraan", "/windows" },
    }, w)
    note("Perintah kendaraan tertentu hanya dapat digunakan saat berada di kendaraan atau memenuhi syarat server.")
end

local function drawFactions(w)
    sectionTitle("FAKSI & KOTA")
    commandGrid({
        { "Anggota fraksi online", "/fonline" },
        { "Petugas yang sedang duty", "/flist" },
        { "Panduan perintah fraksi", "/fhelp" },
        { "Status mendung kegiatan RP", "/sm" },
    }, w)
    note("Status mendung menampilkan kebutuhan petugas untuk kegiatan tertentu. Ikuti ketentuan yang ditampilkan oleh server.")
end

local function drawCharacter(w)
    sectionTitle("INFORMASI KARAKTER")
    commandGrid({
        { "Statistik karakter", "/stats" },
        { "Level karakter", "/mylevel" },
        { "Pengaturan karakter", "/settings" },
        { "Gunakan / lepas masker", "/mask" },
        { "Daftar animasi", "/elist" },
        { "Mulai / atur livemode", "/livemode" },
        { "Pemain yang sedang live", "/livelist" },
        { "Riwayat peringatan", "/mywarn" },
        { "Waktu jeda pekerjaan", "/delay" },
        { "Dokter lokal (EMS tidak tersedia)", "/dokterlokal" },
        { "Simpan data akun", "/saving" },
    }, w)
end

local function drawToys(w)
    sectionTitle("TOYS & AKSESORI")
    commandGrid({
        { "Buka menu aksesori", "/axp" },
        { "Buka set VIP", "/toysaxp" },
    }, w)
    note("Set VIP diperiksa oleh server. Toys yang dipasang melalui menu ini bersifat sementara dan tidak mengubah data fashion tersimpan.")
end

local function drawHelp(w)
    sectionTitle("BANTUAN")
    commandGrid({
        { "Buka bantuan lengkap", "/help" },
        { "Laporkan masalah ke admin", "/report" },
        { "Ajukan permintaan perbaikan", "/fixme" },
        { "Administrator online", "/admins" },
    }, w)
    sectionTitle("TANYA ADMIN")
    inputAction("Tanya fitur ke administrator (/ask)", "Tuliskan pertanyaanmu", askInput, "/ask", "Kirim pertanyaan", w)
    imgui.TextColored(imgui.ImVec4(0.55, 0.78, 0.96, 1.0), "FITUR ROLEPLAY")
    imgui.BulletText("Kebutuhan karakter: lapar, haus, dan stress.")
    imgui.BulletText("Aksi dan suasana: /me, /do, serta /ado.")
    imgui.BulletText("Kendaraan: daftar kendaraan, mesin, jendela, dan limit speed.")
    imgui.BulletText("Aktivitas kota: pekerjaan, layanan fraksi, interior, dan radial menu.")
    note("Gunakan /help untuk membaca syarat dan perintah selengkapnya. Fitur yang memerlukan item, level, kendaraan, atau status tertentu tetap divalidasi oleh server. HUD kiri menampilkan health, armor, FPS, dan ping; lapar dan haus tampil di HUD bila server mengirimkannya, atau gunakan /stats.")
end

local function drawServerInfo(w)
    sectionTitle("INFO SERVER")
    commandGrid({
        { "Panduan dan perintah server", "/help" },
        { "Administrator online", "/admins" },
        { "Informasi karakter dari server", "/stats" },
        { "Anggota fraksi online", "/fonline" },
    }, w)
    sectionTitle("LINK RESMI")
    linkCards(w)
    note("Data akun, pemain online, inventori, dan kendaraan tidak dibuat secara lokal oleh menu ini. Server tetap menjadi sumber data dan validasi.")
end

local function drawFeatureInfo(title, detail, icon, w)
    local pos = imgui.GetCursorScreenPos()
    local h = 58
    imgui.Dummy(V2(w, h))
    local dl = imgui.GetWindowDrawList()
    dl:AddRectFilled(pos, V2(pos.x + w, pos.y + h), col(0.10, 0.11, 0.15, 1), 10)
    dl:AddRect(pos, V2(pos.x + w, pos.y + h), colA(0.10), 10)
    dl:AddCircleFilled(V2(pos.x + 29, pos.y + h / 2), 15, colA(0.12), 24)
    icons.draw(dl, icon or "default", pos.x + 18, pos.y + 18, 22,
        colA(0.8), col(0.07, 0.08, 0.11, 1))
    dl:AddText(V2(pos.x + 54, pos.y + 10), col(0.95, 0.96, 0.98, 1), title)
    dl:AddText(V2(pos.x + 54, pos.y + 31), col(0.67, 0.71, 0.79, 1), detail)
end

local function drawCatalogPage(page, w)
    sectionTitle(page.name:upper())
    for i, item in ipairs(page.items) do
        if item.command then
            if drawCard("##feature_" .. page.name .. i, tostring(item.title or ""),
                item.detail and tostring(item.detail) or nil, w, 58, item.icon) then
                sampSendChat(item.command)
            end
        else
            drawFeatureInfo(tostring(item.title or ""), tostring(item.detail or ""), item.icon, w)
        end
        imgui.Spacing()
    end

    if page.name == "Kota & Ekonomi" or page.name == "Aktivitas Kota" then
        note("Menu sistem dibuka melalui titik interaksi, lokasi, atau kondisi yang ditentukan gamemode. Panel ini tidak melewati validasi server.")
    elseif page.name == "Pekerjaan" then
        note("Ketersediaan pekerjaan mengikuti level, lokasi, dan syarat server. Gunakan titik kerja resmi untuk membuka UI pekerjaannya.")
    end
end

local pages = {
    { name = "Beranda", sub = "Pusat pintas aktivitas karakter", draw = drawHome },
    { name = "Aksi Roleplay", sub = "Gunakan /me untuk aksi dan /do untuk situasi", draw = drawRoleplay },
    { name = "Komunikasi", sub = "Pilih kanal sesuai jarak dan konteks", draw = drawCommunication },
    { name = "Kendaraan", sub = "Fitur kendaraan dari gamemode", draw = drawVehicles },
    { name = "Faksi", sub = "Layanan publik dan rekan satu fraksi", draw = drawFactions },
    { name = "Karakter", sub = "Informasi akun, kebutuhan, dan fitur personal", draw = drawCharacter },
    { name = "Bantuan", sub = "Panduan resmi gamemode", draw = drawHelp },
    { name = "Info Server", sub = "Informasi dan link resmi server", draw = drawServerInfo },
    { name = "VIP Toys", sub = "Pasang aksesori karakter", draw = drawToys },
    { name = "Tampilan", sub = "Atur warna dan tampilan UI", draw = drawAppearance },
}

for _, page in ipairs(featureCatalog) do
    if type(page) == "table" and page.name and type(page.items) == "table" then
        local catalogPage = page
        icons.navigation[page.name] = page.icon or "default"
        pages[#pages + 1] = {
            name = page.name,
            sub = page.sub or "",
            draw = function(w) drawCatalogPage(catalogPage, w) end
        }
    end
end

-- ---------- inisialisasi style ----------
imgui.OnInitialize(function()
    local style = imgui.GetStyle()
    style.WindowRounding = 18
    style.ChildRounding = 14
    style.FrameRounding = 10
    style.PopupRounding = 12
    style.ScrollbarRounding = 8
    style.GrabRounding = 8
    style.ScrollbarSize = 6
    style.WindowBorderSize = 1
    style.FrameBorderSize = 0
    style.ItemSpacing = V2(10, 10)
    style.FramePadding = V2(12, 9)

    local C, v4 = style.Colors, imgui.ImVec4
    local a = CONFIG.accent
    C[imgui.Col.WindowBg] = v4(0.025, 0.025, 0.03, 0.97)
    C[imgui.Col.ChildBg] = v4(0, 0, 0, 0)
    C[imgui.Col.Border] = v4(a[1], a[2], a[3], 0.28)
    C[imgui.Col.FrameBg] = v4(0.09, 0.075, 0.065, 1.0)
    C[imgui.Col.FrameBgHovered] = v4(0.15, 0.085, 0.075, 1.0)
    C[imgui.Col.FrameBgActive] = v4(0.20, 0.095, 0.075, 1.0)
    C[imgui.Col.Button] = v4(a[1] * 0.55, a[2] * 0.55, a[3] * 0.55, 1.0)
    C[imgui.Col.ButtonHovered] = v4(a[1], a[2], a[3], 1.0)
    C[imgui.Col.ButtonActive] = v4(a[1] * 0.8, a[2] * 0.8, a[3] * 0.8, 1.0)
    C[imgui.Col.Header] = v4(0.18, 0.11, 0.07, 1.0)
    C[imgui.Col.HeaderHovered] = v4(0.28, 0.12, 0.09, 1.0)
    C[imgui.Col.HeaderActive] = v4(a[1] * 0.60, a[2] * 0.60, a[3] * 0.60, 1.0)
    C[imgui.Col.CheckMark] = v4(a[1], a[2], a[3], 1.0)
    C[imgui.Col.ScrollbarBg] = v4(0, 0, 0, 0)
    C[imgui.Col.ScrollbarGrab] = v4(a[1], a[2], a[3], 0.45)
    C[imgui.Col.ScrollbarGrabHovered] = v4(a[1], a[2], a[3], 0.75)
    C[imgui.Col.ScrollbarGrabActive] = v4(a[1], a[2], a[3], 1.0)
    C[imgui.Col.Separator] = v4(1, 1, 1, 0.07)

    -- muat logo (jika ada)
    local path = joinPath(scriptDirectory or ".", CONFIG.logoFile)
    if doesFileExist(path) then
        local ok, tex = pcall(imgui.CreateTextureFromFile, path)
        if ok and tex then logoTex = tex end
    end
end)

-- ---------- MENU UTAMA ----------
local SIDE_W, WIN_W, WIN_H = 236, 1080, 760
local menuFrame
menuFrame = imgui.OnFrame(
    function() return menuOpen[0] or menuAnim > 0.01 end,
    function()
        local dt = imgui.GetIO().DeltaTime
        menuAnim = approach(menuAnim, menuOpen[0] and 1 or 0, 11, dt)
        updateHudMetrics(dt)
        menuFrame.LockPlayer = menuOpen[0]
        local ease = smooth(menuAnim)
        curAlpha = ease

        local ds = imgui.GetIO().DisplaySize
        local mobileLayout = ds.x < 760
        local panelSideWidth = mobileLayout and 0 or SIDE_W
        local W = math.max(260, math.min(WIN_W, ds.x - 16))
        local H = math.max(280, math.min(WIN_H, ds.y - 16))

        -- latar gelap di belakang menu
        imgui.GetBackgroundDrawList():AddRectFilled(V2(0, 0), ds, col(0.01, 0.02, 0.04, 0.55))

        imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
        imgui.SetNextWindowPos(V2((ds.x - W) / 2, (ds.y - H) / 2 + (1 - ease) * 26), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, ease)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
            + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoCollapse
        imgui.Begin("##PBRP_hub", nil, flags)
        imgui.PopStyleVar()

        -- panel sidebar (sisi kiri membulat, sisi kanan rata)
        local wp = imgui.GetWindowPos()
        local wdl = imgui.GetWindowDrawList()
        if not mobileLayout then
            wdl:AddRectFilled(V2(wp.x, wp.y), V2(wp.x + SIDE_W + 40, wp.y + H), col(0.04, 0.045, 0.065, 1), 18)
            wdl:AddRectFilled(V2(wp.x + SIDE_W, wp.y + 1), V2(wp.x + SIDE_W + 40, wp.y + H - 1), col(0.06, 0.07, 0.10, 1))
            wdl:AddRectFilled(V2(wp.x + SIDE_W - 1, wp.y + 18), V2(wp.x + SIDE_W, wp.y + H - 18), col(1, 1, 1, 0.06))
        end
        -- glow aksen lembut di area utama + garis aksen di tepi atas
        wdl:AddRectFilledMultiColor(V2(wp.x + panelSideWidth + 1, wp.y + 2), V2(wp.x + W - 18, wp.y + 170),
            colA(0.16), colA(0.02), colA(0.0), colA(0.0))
        wdl:AddRectFilledMultiColor(V2(wp.x + 24, wp.y), V2(wp.x + W - 24, wp.y + 2),
            colA(0.0), colA(0.9), colA(0.9), colA(0.0))

        if not mobileLayout then
            -- ================= SIDEBAR =================
            imgui.BeginChild("##side", V2(SIDE_W, 0), false)
            local sdl = imgui.GetWindowDrawList()
            local sp = imgui.GetWindowPos()
            local pulse = math.sin(os.clock() * 2.2) * 0.5 + 0.5
            drawLogo(sdl, sp.x + 52, sp.y + 52, 56)
            sdl:AddCircle(V2(sp.x + 52, sp.y + 52), 33 + 2 * pulse, colA(0.12 + 0.28 * pulse), 40, 2.0)
            sdl:AddText(V2(sp.x + 92, sp.y + 36), col(1, 1, 1, 1), CONFIG.serverName)
            sdl:AddText(V2(sp.x + 93, sp.y + 36), col(1, 1, 1, 1), CONFIG.serverName)
            sdl:AddText(V2(sp.x + 92, sp.y + 54), colA(1), CONFIG.serverTag)

            imgui.SetCursorPos(V2(14, 104))
            imgui.BeginChild("##navpages", V2(SIDE_W - 14, math.max(120, H - 246)), false)
            local navDrawList = imgui.GetWindowDrawList()
            imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(0, 4))
            for i, page in ipairs(pages) do
                imgui.SetCursorPosX(0)
                local p = imgui.GetCursorScreenPos()
                imgui.InvisibleButton("##nav" .. i, V2(SIDE_W - 28, 40))
                local hovered = imgui.IsItemHovered()
                if imgui.IsItemClicked(0) and activePage ~= i - 1 then
                    activePage = i - 1
                    pageStart = os.clock()
                end
                local active = activePage == i - 1
                local target = active and 1 or (hovered and 0.45 or 0)
                local a = approach(navAnim[i] or 0, target, 14, dt)
                navAnim[i] = a
                local p2 = V2(p.x + SIDE_W - 28, p.y + 40)
                if a > 0.01 then
                    navDrawList:AddRectFilled(p, p2, colA(0.16 * a), 10)
                end
                local bh = 22 * a
                navDrawList:AddRectFilled(V2(p.x, p.y + 20 - bh / 2), V2(p.x + 3, p.y + 20 + bh / 2), colA(a), 2)
                local bx, by = p.x + 22, p.y + 20
                navDrawList:AddCircleFilled(V2(bx, by), 13, active and colA(0.95) or col(0.14, 0.16, 0.21, 1), 24)
                icons.draw(navDrawList, icons.navigation[page.name] or "default", bx - 10, by - 10, 20,
                    active and col(0.05, 0.05, 0.07, 1) or col(0.8, 0.84, 0.9, 1),
                    col(0.07, 0.08, 0.11, 1))
                navDrawList:AddText(V2(p.x + 44 + 3 * a, p.y + 20 - 7),
                    active and col(1, 1, 1, 1) or col(0.72 + 0.2 * a, 0.76 + 0.17 * a, 0.83 + 0.12 * a, 1), page.name)
            end
            imgui.PopStyleVar()
            imgui.EndChild()

            imgui.SetCursorPos(V2(14, H - 116))
            local cw = SIDE_W - 28
            if drawCard("##sidedc", "Discord", nil, cw, 40) then openUrl(CONFIG.discordUrl) end
            imgui.SetCursorPosX(14)
            if drawCard("##sideweb", "Website", nil, cw, 40) then openUrl(CONFIG.websiteUrl) end
            imgui.EndChild()
        end

        -- ================= AREA UTAMA =================
        if not mobileLayout then imgui.SameLine(0, 0) end
        imgui.BeginChild("##main", V2(0, 0), false)
        local mw = imgui.GetWindowWidth()
        local mdl = imgui.GetWindowDrawList()
        local mp = imgui.GetWindowPos()

        -- header
        imgui.SetCursorPos(V2(mobileLayout and 18 or 28, 16))
        imgui.SetWindowFontScale(1.35)
        imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), pages[activePage + 1].name)
        imgui.SetWindowFontScale(1.0)
        imgui.SetCursorPos(V2(mobileLayout and 18 or 28, 46))
        imgui.TextColored(DIM, pages[activePage + 1].sub)

        imgui.SetCursorPos(V2(mw - (mobileLayout and 54 or 62), 20))
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.13, 0.14, 0.19, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.85, 0.25, 0.28, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.70, 0.18, 0.20, 1))
        if imgui.Button("X", V2(mobileLayout and 42 or 34, mobileLayout and 42 or 34)) then menuOpen[0] = false end
        imgui.PopStyleColor(3)
        if not mobileLayout then
            imgui.SetCursorPos(V2(mw - 28 - 34 - 8 - 96, 20))
            if drawCard("##hdrweb", "Website", nil, 96, 34) then openUrl(CONFIG.websiteUrl) end
            imgui.SetCursorPos(V2(mw - 28 - 34 - 8 - 96 - 8 - 96, 20))
            if drawCard("##hdrdc", "Discord", nil, 96, 34) then openUrl(CONFIG.discordUrl) end
        end

        -- garis gradasi aksen di bawah header
        local contentTop = 88
        if mobileLayout then
            imgui.SetCursorPos(V2(18, 74))
            if imgui.Button("<##pbrp_prev_page", V2(44, 42)) then
                activePage = (activePage - 1) % #pages
                pageStart = os.clock()
            end
            imgui.SameLine(0, 8)
            imgui.SetNextItemWidth(math.max(80, mw - 154))
            if imgui.BeginCombo("##pbrp_mobile_page", pages[activePage + 1].name) then
                for index, page in ipairs(pages) do
                    if imgui.Selectable(page.name .. "##pbrp_mobile_page_" .. index, activePage == index - 1) then
                        activePage = index - 1
                        pageStart = os.clock()
                    end
                    if activePage == index - 1 then imgui.SetItemDefaultFocus() end
                end
                imgui.EndCombo()
            end
            imgui.SameLine(0, 8)
            if imgui.Button(">##pbrp_next_page", V2(44, 42)) then
                activePage = (activePage + 1) % #pages
                pageStart = os.clock()
            end
            contentTop = 126
        end
        mdl:AddRectFilledMultiColor(V2(mp.x + (mobileLayout and 16 or 28), mp.y + contentTop - 10),
            V2(mp.x + mw - (mobileLayout and 16 or 28), mp.y + contentTop - 8),
            colA(0.9), colA(0.0), colA(0.0), colA(0.9))

        -- konten halaman dengan transisi slide + fade
        local pp = smooth((os.clock() - pageStart) / 0.30)
        local saved = curAlpha
        curAlpha = ease * pp
        imgui.SetCursorPos(V2(0, contentTop))
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, ease * pp)
        imgui.BeginChild("##page", V2(0, 0), false)
        local pagePadding = mobileLayout and 14 or 28
        imgui.SetCursorPos(V2(pagePadding, 4 + (1 - pp) * 18))
        imgui.Indent(pagePadding)
        local pw = imgui.GetContentRegionAvail().x - pagePadding
        local ok, err = xpcall(function() pages[activePage + 1].draw(pw) end, debug.traceback)
        if not ok then lastUiError = tostring(err):sub(1, 1800) end
        if lastUiError then
            imgui.Spacing()
            imgui.TextColored(imgui.ImVec4(0.98, 0.35, 0.30, 1.0), "ERROR UI LUA")
            imgui.TextWrapped(lastUiError)
            if imgui.Button("Hapus pesan error", V2(-1, 34)) then lastUiError = nil end
        end
        imgui.Dummy(V2(1, 16))
        imgui.Unindent(pagePadding)
        imgui.EndChild()
        imgui.PopStyleVar()
        curAlpha = saved

        imgui.EndChild()
        imgui.End()
        imgui.PopStyleVar()
        uiSounds.playClickIfHovered(imgui)
        curAlpha = 1.0
    end
)

local touchToggleFrame = imgui.OnFrame(
    function()
        return isSampAvailable() and isPlayerUiReady() and not menuOpen[0]
            and not radialOpen[0] and not adminOpen[0] and menuAnim <= 0.01
    end,
    function()
        local display = imgui.GetIO().DisplaySize
        local width, height = 82, 46
        imgui.SetNextWindowPos(V2(math.max(8, display.x - width - 12), math.max(8, display.y * 0.16)),
            imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0.82)
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
        imgui.Begin("##pbrp_android_touch_toggle", nil, flags)
        if imgui.Button("PBRP UI", V2(width - 8, height - 8)) then
            toggleMenu()
        end
        imgui.End()
    end
)
touchToggleFrame.HideCursor = true

-- ---------- RADIAL MENU ----------
local RADIAL_KEYS = { 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38, 0x39, 0x30 }

local function getRadialEntries()
    local items = {}
    for idx, item in ipairs(radialItems) do
        if item then
            items[#items + 1] = item
        end
    end
    return items
end

-- potong teks agar muat di lebar tertentu
local function fitText(text, maxWidth)
    text = tostring(text or "")
    if imgui.CalcTextSize(text).x <= maxWidth then return text end
    while #text > 1 and imgui.CalcTextSize(text .. "..").x > maxWidth do
        text = text:sub(1, -2)
    end
    return text .. ".."
end

local function drawRadial(dl, ds, dt, ease)
    local entries = getRadialEntries()
    local cx, cy = ds.x / 2, ds.y / 2
    local center = V2(cx, cy)
    local s = math.max(0.6, math.min(1, math.min(ds.x, ds.y) / 860))
    local rs = s * (0.74 + 0.26 * ease)
    local inner, outer, centerR = 112 * rs, 196 * rs, 84 * rs
    local ar, ag, ab = CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3]
    local n = #entries
    local seg = 360 / n
    local gapDeg = 3.2
    local now = os.clock()

    -- latar redup + cahaya lembut di belakang cincin
    dl:AddRectFilled(V2(0, 0), ds, col(0.01, 0.02, 0.04, 0.58))
    for k = 1, 5 do
        dl:AddCircleFilled(center, outer + (6 + k * 16) * rs, colA(0.016), 96)
    end

    -- cincin dekoratif: garis luar + tick yang berputar pelan
    dl:AddCircle(center, outer + 18 * rs, col(1, 1, 1, 0.08), 96, 1.0)
    local spinTick = now * 0.12
    for k = 0, 71 do
        local ang = spinTick + k * (math.pi * 2 / 72)
        local major = (k % 6 == 0)
        local r0 = inner - 11 * rs
        local r1 = r0 + (major and 6 or 3) * rs
        local c, sn = math.cos(ang), math.sin(ang)
        dl:AddLine(V2(cx + c * r0, cy + sn * r0), V2(cx + c * r1, cy + sn * r1),
            colA(major and 0.38 or 0.14), 1.0)
    end

    -- deteksi item yang di-hover (area diperluas sampai label di luar cincin)
    local mouse = imgui.GetMousePos()
    local dx, dy = mouse.x - cx, mouse.y - cy
    local dist = math.sqrt(dx * dx + dy * dy)
    local hoverIdx = nil
    if radialOpen[0] and dist >= centerR and dist <= outer + 130 * rs then
        local a = (math.deg(atan2(dy, dx)) + 90 + seg / 2) % 360
        hoverIdx = math.min(n, math.floor(a / seg) + 1)
    end

    for i, item in ipairs(entries) do
        local hv = approach(radialHover[i] or 0, (hoverIdx == i) and 1 or 0, 16, dt)
        radialHover[i] = hv
        -- muncul bergiliran + sedikit memutar saat dibuka
        local ie = smooth(radialAnim * 1.5 - (i - 1) * 0.05)
        curAlpha = ie
        local spin = (1 - ie) * 0.22

        local baseA0 = math.rad(-90 - seg / 2 + (i - 1) * seg + gapDeg / 2)
        local baseA1 = math.rad(-90 - seg / 2 + i * seg - gapDeg / 2)
        local a0, a1 = baseA0 + spin, baseA1 + spin
        local am = (a0 + a1) / 2
        local rIn = inner - 2 * rs * hv
        local rOut = outer + 12 * rs * hv
        local mid, thick = (rIn + rOut) / 2, rOut - rIn

        local sr = lerp(0.07, ar * 0.50, hv)
        local sg = lerp(0.08, ag * 0.50, hv)
        local sb = lerp(0.11, ab * 0.50, hv)

        -- cahaya saat hover
        if hv > 0.02 then
            dl:PathClear()
            dl:PathArcTo(center, mid, a0, a1, 28)
            strokePath(dl, colA(0.14 * hv), thick + 16 * rs)
        end
        -- badan segmen
        dl:PathClear()
        dl:PathArcTo(center, mid, a0, a1, 28)
        strokePath(dl, col(sr, sg, sb, 0.94), thick)
        -- garis tepi dalam
        dl:PathClear()
        dl:PathArcTo(center, rIn + 1, a0, a1, 28)
        strokePath(dl, colA(0.22 + 0.5 * hv), 1.5)
        -- garis tepi luar saat hover
        if hv > 0.02 then
            dl:PathClear()
            dl:PathArcTo(center, rOut + 4 * rs, a0, a1, 28)
            strokePath(dl, colA(hv), 3)
        end

        -- ikon dalam lencana bulat
        local ix, iy = cx + math.cos(am) * mid, cy + math.sin(am) * mid
        local badgeR = 21 * rs
        dl:AddCircleFilled(V2(ix, iy), badgeR, colA(0.07 + 0.22 * hv), 32)
        dl:AddCircle(V2(ix, iy), badgeR, colA(0.22 + 0.68 * hv), 32, 1.5)
        local isz = 24 * rs
        icons.draw(dl, item.icon or "default", ix - isz / 2, iy - isz / 2, isz,
            col(lerp(ar, 1, 0.35 * hv), lerp(ag, 1, 0.35 * hv), lerp(ab, 1, 0.35 * hv), 1),
            col(sr, sg, sb, 1))

        -- label di luar cincin (tidak lagi menimpa ikon), dengan nomor pintasan
        local ca, sa = math.cos(am - spin), math.sin(am - spin)
        local lr = outer + (28 + 12 * hv) * rs
        local num = i == 10 and "0" or (i <= #RADIAL_KEYS and tostring(i) or "")
        local nw = imgui.CalcTextSize(num).x
        local ls = imgui.CalcTextSize(item.label)
        local total = nw + (num ~= "" and 8 or 0) + ls.x
        local px, py = cx + ca * lr, cy + sa * lr
        local x0
        if ca > 0.35 then
            x0 = px
        elseif ca < -0.35 then
            x0 = px - total
        else
            x0 = px - total / 2
        end
        local y0 = py - ls.y / 2 + sa * ls.y * 0.6
        if num ~= "" then dl:AddText(V2(x0, y0), colA(0.55 + 0.45 * hv), num) end
        dl:AddText(V2(x0 + nw + (num ~= "" and 8 or 0), y0),
            col(lerp(0.66, 1, hv), lerp(0.70, 1, hv), lerp(0.78, 1, hv), lerp(0.78, 1, hv)),
            item.label)
    end
    curAlpha = ease

    -- lingkaran tengah
    local pulse = math.sin(now * 2.4) * 0.5 + 0.5
    dl:AddCircleFilled(center, centerR + 8 * rs, colA(0.05 + 0.05 * pulse), 64)
    dl:AddCircleFilled(center, centerR, col(0.05, 0.06, 0.09, 0.97), 64)
    dl:AddCircle(center, centerR, colA(0.5 + 0.4 * pulse), 64, 2.0)
    drawLogo(dl, cx, cy - 26 * rs, math.max(40, 46 * rs))

    local item = hoverIdx and entries[hoverIdx] or nil
    local head = item and item.label or CONFIG.serverName
    local sub = item and (item.hint or "") or "Pilih menu - ESC tutup"
    local maxW = centerR * 2 - 18 * rs
    head, sub = fitText(head, maxW), fitText(sub, maxW)
    local t1, t2 = imgui.CalcTextSize(head), imgui.CalcTextSize(sub)
    local ty = cy + 6 * rs
    dl:AddText(V2(cx - t1.x / 2, ty), col(1, 1, 1, 1), head)
    dl:AddText(V2(cx - t1.x / 2 + 1, ty), col(1, 1, 1, 1), head)
    dl:AddText(V2(cx - t2.x / 2, ty + 17), colA(0.9), sub)

    -- klik: pilih item; klik di mana pun selain item (tengah/luar) atau klik kanan menutup
    if radialOpen[0] then
        if imgui.IsMouseClicked(0) then
            if hoverIdx then
                uiSounds.play("click")
                radialAction(entries[hoverIdx])
            else
                radialOpen[0] = false
            end
        elseif imgui.IsMouseClicked(1) then
            radialOpen[0] = false
        end
    end
end

local radialFrame
radialFrame = imgui.OnFrame(
    function()
        return (radialOpen[0] or radialAnim > 0.01) and isSampAvailable() and isPlayerUiReady()
    end,
    function()
        local io = imgui.GetIO()
        local dt, ds = io.DeltaTime, io.DisplaySize
        radialAnim = approach(radialAnim, radialOpen[0] and 1 or 0, 13, dt)
        radialFrame.LockPlayer = radialOpen[0]
        local ease = smooth(radialAnim)
        curAlpha = ease

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoScrollWithMouse
        imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
        imgui.SetNextWindowSize(ds, imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0.0)
        imgui.Begin("##PBRP_radial_menu", nil, flags)
        local dl = imgui.GetWindowDrawList()
        -- End() selalu dipanggil walau ada error, supaya stack imgui tidak rusak
        local ok, err = xpcall(function() drawRadial(dl, ds, dt, ease) end, debug.traceback)
        imgui.End()
        curAlpha = 1.0
        if not ok then
            radialOpen[0] = false
            radialAnim = 0
            logUiError("radial", err)
        end
    end
)

-- ---------- HUD ----------
local function textSized(dl, x, y, text, color, size)
    local ok = pcall(function() dl:AddText(imgui.GetFont(), size, V2(x, y), color, text) end)
    if not ok then dl:AddText(V2(x, y), color, text) end
end

local function sizedWidth(text, size)
    return imgui.CalcTextSize(text).x * size / imgui.GetFontSize()
end

local function chip(dl, x, y, text, r, g, b, rightAlign)
    local ts = imgui.CalcTextSize(text)
    local w, h = ts.x + 16, ts.y + 6
    if rightAlign then x = x - w end
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), col(r, g, b, 0.16), h / 2)
    dl:AddRect(V2(x, y), V2(x + w, y + h), col(r, g, b, 0.55), h / 2, 0, 1)
    dl:AddText(V2(x + 8, y + 3), col(r, g, b, 1), text)
    return w, h
end

local function hudPanel(dl, x, y, w, h, borderA, br, bg2, bb)
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), col(0.040, 0.036, 0.070, 0.88), 13)
    dl:AddRectFilledMultiColor(V2(x + 6, y + 1), V2(x + w - 6, y + 24),
        colA(0.14), colA(0.14), colA(0.0), colA(0.0))
    local border = br and col(br, bg2, bb, borderA) or colA(borderA)
    dl:AddRect(V2(x, y), V2(x + w, y + h), border, 13, 0, 1)
    dl:AddRectFilled(V2(x + 14, y), V2(x + w - 14, y + 2), colA(0.9), 1)
end

local function fmtNum(n)
    local s = tostring(math.floor(n))
    local neg = s:sub(1, 1) == "-"
    if neg then s = s:sub(2) end
    s = s:reverse():gsub("(%d%d%d)", "%1,"):reverse():gsub("^,", "")
    return (neg and "-" or "") .. s
end

-- ===== widget FPS + PING (kiri atas) =====
local FPS_H = 46
local HUD_MUTED = nil
CONFIG.hud.editMode = false
CONFIG.hud.drag = { target = nil, offsetX = 0, offsetY = 0 }

CONFIG.hud.clampPosition = function(x, y, w, h, display)
    return math.max(0, math.min(display.x - w, x)),
        math.max(0, math.min(display.y - h, y))
end

CONFIG.hud.position = function(xValue, yValue, defaultX, defaultY, w, h, display)
    if xValue == nil or yValue == nil then return defaultX, defaultY end
    local maxX, maxY = math.max(0, display.x - w), math.max(0, display.y - h)
    return maxX * xValue, maxY * yValue
end

CONFIG.hud.updateDrag = function(target, x, y, w, h, display)
    if not CONFIG.hud.editMode then return x, y end

    local mouse = imgui.GetMousePos()
    if CONFIG.hud.drag.target == nil and imgui.IsMouseClicked(0)
        and mouse.x >= x and mouse.x <= x + w
        and mouse.y >= y and mouse.y <= y + h then
        CONFIG.hud.drag.target = target
        CONFIG.hud.drag.offsetX, CONFIG.hud.drag.offsetY = mouse.x - x, mouse.y - y
    end

    if CONFIG.hud.drag.target == target then
        if imgui.IsMouseDown(0) or imgui.IsMouseReleased(0) then
            x, y = CONFIG.hud.clampPosition(mouse.x - CONFIG.hud.drag.offsetX,
                mouse.y - CONFIG.hud.drag.offsetY, w, h, display)
            local maxX, maxY = math.max(0, display.x - w), math.max(0, display.y - h)
            if target == "fps" then
                CONFIG.hud.fpsX = maxX > 0 and x / maxX or 0
                CONFIG.hud.fpsY = maxY > 0 and y / maxY or 0
            else
                CONFIG.hud.statsX = maxX > 0 and x / maxX or 0
                CONFIG.hud.statsY = maxY > 0 and y / maxY or 0
            end
        end
        if imgui.IsMouseReleased(0) then
            CONFIG.hud.drag.target = nil
            if not saveHudSettings() then
                sampAddChatMessage("[PekanBaru UI] " .. hudSettingsStatus, 0xFFFF6A6A)
            end
        end
    end
    return x, y
end

local function fpsHudWidth()
    local tagW = imgui.CalcTextSize(CONFIG.shortTag).x + 18
    local digitsW = sizedWidth("000", 19)
    local timeW = sizedWidth("00:00", 19)
    local fpsBlock = 104
    local pingBlock = digitsW + 26 + 24
    return 9 + tagW + 12 + fpsBlock + 12 + 1 + 14 + pingBlock + 12 + 1 + 14 + timeW + 14
end

local function drawFpsHud(dl, p, dt)
    updateHudMetrics(dt)
    local muted = col(0.62, 0.60, 0.76, 1)
    local x, y = p.x, p.y

    local tag = CONFIG.shortTag
    local tagSize = imgui.CalcTextSize(tag)
    local tagW = tagSize.x + 18
    local digitsW = sizedWidth("000", 19)
    local fpsBlock = 104
    local pingBlock = digitsW + 26 + 24
    local totalW = fpsHudWidth()

    hudPanel(dl, x, y, totalW, FPS_H, 0.40)

    -- tag server
    dl:AddRectFilled(V2(x + 9, y + 9), V2(x + 9 + tagW, y + FPS_H - 9), colA(0.22), 8)
    dl:AddRect(V2(x + 9, y + 9), V2(x + 9 + tagW, y + FPS_H - 9), colA(0.75), 8, 0, 1)
    dl:AddText(V2(x + 18, y + FPS_H / 2 - tagSize.y / 2), colA(1), tag)
    local cx = x + 9 + tagW + 12

    -- FPS + sparkline
    local fr, fg, fb = fpsColor(fpsLive)
    dl:AddText(V2(cx, y + 7), muted, "FPS")
    textSized(dl, cx, y + 21, tostring(math.floor(fpsLive + 0.5)), col(fr, fg, fb, 1), 19)
    local sx0, sy0, sw, sh = cx + 46, y + 11, 58, 24
    if #fpsHist > 1 then
        local peak = 60
        for _, v in ipairs(fpsHist) do
            if v > peak then peak = v end
        end
        peak = peak * 1.1
        local offset = FPS_HIST_N - #fpsHist
        local prevX, prevY
        for i, v in ipairs(fpsHist) do
            local px = sx0 + sw * (i - 1 + offset) / (FPS_HIST_N - 1)
            local py = sy0 + sh - sh * math.min(1, v / peak)
            if prevX then dl:AddLine(V2(prevX, prevY), V2(px, py), col(fr, fg, fb, 0.9), 1.6) end
            prevX, prevY = px, py
        end
    end

    -- PING + indikator sinyal
    local dx = cx + fpsBlock + 12
    dl:AddLine(V2(dx, y + 12), V2(dx, y + FPS_H - 12), col(1, 1, 1, 0.10), 1)
    local px0 = dx + 14
    local pr, pg, pb = pingColor(hudNet.ping)
    local pingText = tostring(hudNet.ping)
    dl:AddText(V2(px0, y + 7), muted, "PING")
    textSized(dl, px0, y + 21, pingText, col(pr, pg, pb, 1), 19)
    dl:AddText(V2(px0 + sizedWidth(pingText, 19) + 3, y + 27), muted, "ms")
    local bars = (hudNet.ping <= 60 and 4) or (hudNet.ping <= 100 and 3) or (hudNet.ping <= 160 and 2) or 1
    local bx = px0 + digitsW + 26
    for i = 1, 4 do
        local bh = 4 + i * 4
        local bxi = bx + (i - 1) * 6
        dl:AddRectFilled(V2(bxi, y + 38 - bh), V2(bxi + 4, y + 38),
            i <= bars and col(pr, pg, pb, 1) or col(1, 1, 1, 0.12), 2)
    end

    -- jam
    local dx2 = px0 + pingBlock + 12
    dl:AddLine(V2(dx2, y + 12), V2(dx2, y + FPS_H - 12), col(1, 1, 1, 0.10), 1)
    local tx0 = dx2 + 14
    dl:AddText(V2(tx0, y + 7), muted, "WAKTU")
    textSized(dl, tx0, y + 21, os.date("%H:%M"), col(0.94, 0.95, 1, 1), 19)
end

local fpsFrame = imgui.OnFrame(
    function() return CONFIG.hud.showFps and isSampAvailable() and isPlayerUiReady() end,
    function()
        curAlpha = 1.0
        local io = imgui.GetIO()
        local dt, ds = io.DeltaTime, io.DisplaySize
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
        if not CONFIG.hud.editMode then flags = flags + imgui.WindowFlags.NoInputs end
        local margin = 4
        local width = fpsHudWidth()
        local defaultX = (CONFIG.hud.fpsPosition == "top-right" or CONFIG.hud.fpsPosition == "bottom-right")
            and math.max(0, ds.x - width - margin) or margin
        local defaultY = (CONFIG.hud.fpsPosition == "bottom-left" or CONFIG.hud.fpsPosition == "bottom-right")
            and math.max(0, ds.y - FPS_H - margin) or margin
        local x, y = CONFIG.hud.position(CONFIG.hud.fpsX, CONFIG.hud.fpsY, defaultX, defaultY, width, FPS_H, ds)
        x, y = CONFIG.hud.updateDrag("fps", x, y, width, FPS_H, ds)
        imgui.SetNextWindowPos(V2(x, y), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, FPS_H), imgui.Cond.Always)
        imgui.Begin("##PBRP_fps_hud", nil, flags)
        local dl, p = imgui.GetWindowDrawList(), imgui.GetWindowPos()
        local ok, err = xpcall(function() drawFpsHud(dl, p, dt) end, debug.traceback)
        imgui.End()
        if not ok then logUiError("fps hud", err) end
    end
)
fpsFrame.HideCursor = not CONFIG.hud.editMode

-- ===== panel status karakter (kiri) =====
local STATS_W = 286

local function statsNeedsVisible()
    return hudState.hunger ~= nil and hudState.needsAt ~= nil
        and (os.clock() - hudState.needsAt) < CONFIG.hud.needsTimeout
end

local function statsLayout()
    local needs = statsNeedsVisible()
    local footer = (hudNet.money ~= nil) or (hudState.ammo ~= nil and hudState.ammo > 1)
    local h = 14 + 26 + 60 + (needs and 40 or 0) + (footer and 34 or 0) + 10
    return h, needs, footer
end

local function drawStatBar(dl, x, y, w, label, icon, value, ghost, r, g, b, flashing)
    icons.draw(dl, icon, x, y, 22, col(r, g, b, 1), col(0.07, 0.08, 0.11, 1))
    local bx0, bx1 = x + 32, x + w
    dl:AddText(V2(bx0, y), col(0.74, 0.74, 0.88, 1), label)
    local txt = string.format("%d%%", math.floor(value + 0.5))
    local ts = imgui.CalcTextSize(txt)
    dl:AddText(V2(bx1 - ts.x, y), col(1, 1, 1, 1), txt)
    local by = y + 17
    dl:AddRectFilled(V2(bx0, by), V2(bx1, by + 8), col(1, 1, 1, 0.08), 4)
    local gw = (bx1 - bx0) * math.min(1, ghost / 100)
    if gw > 1 then dl:AddRectFilled(V2(bx0, by), V2(bx0 + gw, by + 8), col(1, 1, 1, 0.22), 4) end
    local fw = (bx1 - bx0) * math.min(1, value / 100)
    if fw > 1 then
        local pulse = flashing and (0.65 + 0.35 * (math.sin(os.clock() * 8) * 0.5 + 0.5)) or 1
        dl:AddRectFilled(V2(bx0, by), V2(bx0 + fw, by + 8), col(r, g, b, pulse), 4)
        dl:AddRectFilled(V2(bx0 + 2, by + 1), V2(bx0 + math.max(3, fw - 2), by + 3), col(1, 1, 1, 0.20), 2)
    end
    for k = 1, 9 do
        local tx = bx0 + (bx1 - bx0) * k / 10
        dl:AddLine(V2(tx, by), V2(tx, by + 8), col(0.04, 0.036, 0.07, 0.8), 1)
    end
end

local function drawMiniBar(dl, x, y, w, label, icon, value, r, g, b)
    icons.draw(dl, icon, x, y, 18, col(r, g, b, 1), col(0.07, 0.08, 0.11, 1))
    dl:AddText(V2(x + 24, y), col(0.74, 0.74, 0.88, 1), label)
    local txt = string.format("%d%%", math.floor(value + 0.5))
    local ts = imgui.CalcTextSize(txt)
    dl:AddText(V2(x + w - ts.x, y), col(1, 1, 1, 1), txt)
    local by = y + 21
    dl:AddRectFilled(V2(x, by), V2(x + w, by + 6), col(1, 1, 1, 0.08), 3)
    local fw = w * math.min(1, value / 100)
    if fw > 1 then dl:AddRectFilled(V2(x, by), V2(x + fw, by + 6), col(r, g, b, 1), 3) end
end

local function drawVignette(ds, strength)
    if strength <= 0.01 then return end
    local bg = imgui.GetBackgroundDrawList()
    local t = math.min(ds.x, ds.y) * 0.18
    local c1, c0 = col(0.95, 0.12, 0.20, strength), col(0.95, 0.12, 0.20, 0)
    bg:AddRectFilledMultiColor(V2(0, 0), V2(ds.x, t), c1, c1, c0, c0)
    bg:AddRectFilledMultiColor(V2(0, ds.y - t), V2(ds.x, ds.y), c0, c0, c1, c1)
    bg:AddRectFilledMultiColor(V2(0, 0), V2(t, ds.y), c1, c0, c0, c1)
    bg:AddRectFilledMultiColor(V2(ds.x - t, 0), V2(ds.x, ds.y), c0, c1, c1, c0)
end

local function drawStatsHud(dl, p, h, needs, footer, dt, ds)
    updateHudMetrics(dt)
    local low = hudState.hp <= 25
    local pulse = math.sin(os.clock() * 7) * 0.5 + 0.5
    drawVignette(ds, math.max(low and (0.10 + 0.20 * pulse) or 0, hudState.hitFlash * 0.35))

    local x, y = p.x, p.y
    if low then
        hudPanel(dl, x, y, STATS_W, h, 0.45 + 0.4 * pulse, 0.95, 0.28, 0.30)
    else
        hudPanel(dl, x, y, STATS_W, h, 0.40)
    end

    -- header: nama + ID
    dl:AddRectFilled(V2(x + 14, y + 14), V2(x + 17, y + 32), colA(1), 2)
    local idText = hudNet.id >= 0 and ("ID " .. hudNet.id) or "ID -"
    local cw = chip(dl, x + STATS_W - 14, y + 13, idText, CONFIG.accent[1], CONFIG.accent[2], CONFIG.accent[3], true)
    dl:AddText(V2(x + 25, y + 15), col(0.96, 0.96, 1, 1), fitText(hudNet.name or getPlayerName(), STATS_W - 25 - 14 - cw - 8))

    local bw = STATS_W - 28
    local cy = y + 40
    local hr, hg, hb = 0.98, 0.36, 0.52
    if low then hr, hg, hb = 0.95, 0.22, 0.26 end
    drawStatBar(dl, x + 14, cy, bw, "HEALTH", "health", hudState.health, hudState.healthGhost, hr, hg, hb, low)
    cy = cy + 30
    drawStatBar(dl, x + 14, cy, bw, "ARMOR", "armor", hudState.armour, hudState.armourGhost, 0.56, 0.52, 1.0, false)
    cy = cy + 30

    if needs then
        local half = (bw - 14) / 2
        drawMiniBar(dl, x + 14, cy + 2, half, "LAPAR", "food", hudState.hunger, 1.0, 0.70, 0.28)
        drawMiniBar(dl, x + 14 + half + 14, cy + 2, half, "HAUS", "drink", hudState.thirst, 0.35, 0.80, 0.98)
        cy = cy + 40
    end

    if footer then
        if hudNet.money ~= nil then
            chip(dl, x + 14, cy + 3, "Rp " .. fmtNum(hudNet.money), 0.40, 0.90, 0.62, false)
        end
        if hudState.ammo ~= nil and hudState.ammo > 1 then
            chip(dl, x + STATS_W - 14, cy + 3, "AMMO " .. hudState.ammo, 1.0, 0.78, 0.30, true)
        end
    end
end

local hudFrame
hudFrame = imgui.OnFrame(
    function() return hudOpen[0] and isSampAvailable() and isPlayerUiReady() end,
    function()
        curAlpha = 1.0
        local io = imgui.GetIO()
        local dt, ds = io.DeltaTime, io.DisplaySize
        local h, needs, footer = statsLayout()
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
        if not CONFIG.hud.editMode then flags = flags + imgui.WindowFlags.NoInputs end

        local defaultY = math.max(80, ds.y * CONFIG.hud.statsBottomFrac - h)
        local x, y = CONFIG.hud.position(CONFIG.hud.statsX, CONFIG.hud.statsY, 16, defaultY, STATS_W, h, ds)
        x, y = CONFIG.hud.updateDrag("stats", x, y, STATS_W, h, ds)
        imgui.SetNextWindowPos(V2(x, y), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(STATS_W, h), imgui.Cond.Always)
        imgui.Begin("##PBRP_status_hud", nil, flags)
        local dl, p = imgui.GetWindowDrawList(), imgui.GetWindowPos()
        local ok, err = xpcall(function() drawStatsHud(dl, p, h, needs, footer, dt, ds) end, debug.traceback)
        imgui.End()
        if not ok then logUiError("hud", err) end
    end
)
hudFrame.HideCursor = not CONFIG.hud.editMode

CONFIG.hud.toggleEdit = function()
    CONFIG.hud.editMode = not CONFIG.hud.editMode
    CONFIG.hud.drag.target = nil
    fpsFrame.HideCursor = not CONFIG.hud.editMode
    hudFrame.HideCursor = not CONFIG.hud.editMode
    if CONFIG.hud.editMode then
        sampAddChatMessage("[PekanBaru UI] Mode geser aktif: tarik panel HUD dengan mouse, lepas untuk menyimpan. Ketik /rpuihudedit untuk selesai.", 0xFFD4AF37)
    else
        sampAddChatMessage("[PekanBaru UI] Mode geser HUD dinonaktifkan.", 0xFFD4AF37)
    end
end

-- petunjuk tombol di sisi kanan (disembunyikan saat UI lain terbuka)
local function keycap(dl, x, y, label)
    local ts = imgui.CalcTextSize(label)
    local w, h = math.max(24, ts.x + 14), 22
    dl:AddRectFilled(V2(x, y + 2), V2(x + w, y + h + 2), col(0, 0, 0, 0.45), 6)
    dl:AddRectFilled(V2(x, y), V2(x + w, y + h), colA(0.24), 6)
    dl:AddRect(V2(x, y), V2(x + w, y + h), colA(0.85), 6, 0, 1.2)
    dl:AddText(V2(x + (w - ts.x) / 2, y + (h - ts.y) / 2), col(1, 1, 1, 1), label)
    return w
end

local hintFrame = imgui.OnFrame(
    function()
        return isSampAvailable() and isPlayerUiReady()
            and not menuOpen[0] and not radialOpen[0]
            and menuAnim < 0.05 and radialAnim < 0.05
            and not phoneUI.isOpen() and not inventoryUI.isOpen() and not vehiclesUI.isOpen()
            and not factionVehicleUI.isOpen() and not vipRubyUI.isOpen()
            and not adminPanelUI.isOpen() and not adminOpen[0]
    end,
    function()
        curAlpha = 1.0
        local display = imgui.GetIO().DisplaySize
        local width, height = 206, 44
        if canUseAdminUi() then width = 292 end
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoBackground
        imgui.SetNextWindowPos(V2(display.x - width - 18, display.y * 0.36), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.Begin("##rpui_hint", nil, flags)
        local pos = imgui.GetWindowPos()
        local drawList = imgui.GetWindowDrawList()
        hudPanel(drawList, pos.x, pos.y, width, height, 0.40)
        local x, y = pos.x + 12, pos.y + 11
        x = x + keycap(drawList, x, y, "M") + 7
        local label1 = "Radial"
        drawList:AddText(V2(x, y + 3), col(0.86, 0.86, 0.96, 1), label1)
        x = x + imgui.CalcTextSize(label1).x + 16
        x = x + keycap(drawList, x, y, "F2") + 7
        drawList:AddText(V2(x, y + 3), col(0.86, 0.86, 0.96, 1), "Menu")
        if canUseAdminUi() then
            x = x + imgui.CalcTextSize("Menu").x + 12
            x = x + keycap(drawList, x, y, "F3") + 6
            drawList:AddText(V2(x, y + 3), col(1.0, 0.38, 0.42, 1), "Admin")
        end
        imgui.End()
    end
)
hintFrame.HideCursor = true

local notificationFrame = imgui.OnFrame(
    function()
        return isSampAvailable() and isPlayerUiReady() and notificationUI.hasItems()
    end,
    function()
        curAlpha = 1.0
        local ok, err = pcall(notificationUI.draw)
        if not ok then logUiError("notifikasi", err) end
    end
)
notificationFrame.HideCursor = true

local updaterFrame = imgui.OnFrame(
    function()
        return isSampAvailable()
            and updateStatus.visible
            and updateStatus.title ~= ""
            and (updateStatus.active or os.clock() - updateStatus.finishedAt < 5)
    end,
    function()
        local display = imgui.GetIO().DisplaySize
        local width, height = 390, 96
        local x, y = display.x - width - 18, 18
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs
            + imgui.WindowFlags.NoBackground

        imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
        imgui.SetNextWindowSize(display, imgui.Cond.Always)
        imgui.Begin("##PBRP_updater_overlay", nil, flags)
        local dl = imgui.GetWindowDrawList()
        hudPanel(dl, x, y, width, height, 0.82)

        local accentColor = updateStatus.active and colA(0.95) or col(0.35, 0.88, 0.58, 1)
        dl:AddText(V2(x + 14, y + 10), accentColor, "PEKANBARU UI  /  " .. updateStatus.title)
        dl:AddText(V2(x + 14, y + 34), col(0.90, 0.92, 0.97, 1),
            fitText(updateStatus.detail, width - 28))

        local progressText
        local progress = 0
        if updateStatus.total > 0 then
            progress = math.max(0, math.min(1, updateStatus.completed / updateStatus.total))
            progressText = string.format("%d/%d file selesai  |  %.1f KB file aktif",
                updateStatus.completed, updateStatus.total, updateStatus.currentBytes / 1024)
        else
            progressText = updateStatus.active and "Menghubungi GitHub..." or updateStatus.detail
        end
        dl:AddText(V2(x + 14, y + 57), col(0.67, 0.71, 0.79, 1),
            fitText(progressText, width - 28))

        local barX, barY, barW = x + 14, y + height - 14, width - 28
        dl:AddRectFilled(V2(barX, barY), V2(barX + barW, barY + 3), col(1, 1, 1, 0.10), 2)
        if progress > 0 then
            dl:AddRectFilled(V2(barX, barY), V2(barX + barW * progress, barY + 3), accentColor, 2)
        elseif updateStatus.active then
            local pulse = (math.sin(os.clock() * 5) + 1) * 0.5
            dl:AddRectFilled(V2(barX, barY), V2(barX + barW * (0.18 + pulse * 0.22), barY + 3),
                accentColor, 2)
        end
        imgui.End()
    end
)
updaterFrame.HideCursor = true

-- ---------- perintah & loop ----------
local function isOtherUiOpen()
    return phoneUI.isOpen() or inventoryUI.isOpen() or vehiclesUI.isOpen()
        or vipRubyUI.isOpen() or cctvUI.isOpen() or adminPanelUI.isOpen()
        or factionVehicleUI.isOpen() or factionPanelUI.isOpen() or mechanicServiceUI.isOpen()
        or businessUI.isOpen()
end

local function toggleFactionVehicleUi()
    if factionVehicleUI.isOpen() then
        factionVehicleUI.toggle()
        return
    end
    if not isSampAvailable() or not isPlayerUiReady() or isOtherUiOpen() or adminOpen[0] then
        return
    end
    factionVehicleUI.toggle()
end

local function toggleMenu()
    if menuOpen[0] then
        menuOpen[0] = false
        return
    end
    if not isSampAvailable() or not isPlayerUiReady() or isOtherUiOpen() or adminOpen[0] then
        return
    end
    radialOpen[0] = false
    menuOpen[0] = true
    pageStart = os.clock()
end

local function toggleRadial()
    if radialOpen[0] then
        radialOpen[0] = false
        return
    end
    if not isSampAvailable() or not isPlayerUiReady() or menuOpen[0] or adminOpen[0] or isOtherUiOpen() then
        return
    end
    radialOpen[0] = true
end

local updaterDownloadSound
local updaterDownloadSoundWarned = false

local function playUpdaterDownloadSound()
    if not updaterDownloadSound then
        local soundPath = joinPath(phoneSoundDirectory, "notify.wav")
        if type(doesFileExist) ~= "function" or not doesFileExist(soundPath) then
            if not updaterDownloadSoundWarned then
                updaterDownloadSoundWarned = true
                print("[PBRP Updater] Suara notifikasi tidak ditemukan: " .. soundPath)
            end
            return false
        end

        local loaded, stream = pcall(loadAudioStream, soundPath)
        if not loaded or not stream or stream == 0 then
            if not updaterDownloadSoundWarned then
                updaterDownloadSoundWarned = true
                print("[PBRP Updater] Gagal memuat suara notifikasi: " .. tostring(stream))
            end
            return false
        end
        updaterDownloadSound = stream
    end

    local ok, err = pcall(function()
        setAudioStreamVolume(updaterDownloadSound, 0.6)
        setAudioStreamState(updaterDownloadSound, 0)
        setAudioStreamState(updaterDownloadSound, 1)
    end)
    if not ok and not updaterDownloadSoundWarned then
        updaterDownloadSoundWarned = true
        print("[PBRP Updater] Gagal memutar suara notifikasi: " .. tostring(err))
    end
    return ok
end

local lastUpdaterNotice = ""
updateStatus.notice = function(message)
    local text = "[PBRP Updater] " .. tostring(message)
    if text ~= lastUpdaterNotice then
        lastUpdaterNotice = text
        print(text)
        if isSampAvailable() then
            sampAddChatMessage(text, 0xFFD4AF37)
        end
    end
end

local function setUpdaterStatus(title, detail)
    updateStatus.active = true
    updateStatus.visible = title ~= "Memeriksa GitHub"
    updateStatus.title = title
    updateStatus.detail = detail or ""
    updateStatus.finishedAt = 0
end

local function finishUpdaterStatus(title, detail)
    updateStatus.title = title
    updateStatus.detail = detail or ""
    updateStatus.active = false
    updateStatus.visible = title ~= "Versi terbaru"
    updateStatus.finishedAt = os.clock()
    if title ~= "Versi terbaru" then
        recordUpdateLog(title, detail)
    end
end

local function updaterFileExists(path)
    local file = io.open(path, "rb")
    if not file then return false end
    file:close()
    return true
end

local function readUpdaterFile(path)
    local file = io.open(path, "rb")
    if not file then return nil, "file tidak ditemukan atau tidak dapat dibuka" end

    local readOk, content, readError = pcall(file.read, file, "*a")
    local closeOk, closed, closeError = pcall(file.close, file)
    if not readOk then return nil, tostring(content) end
    if not content then return nil, tostring(readError or "file tidak dapat dibaca") end
    if not closeOk or not closed then
        return nil, tostring(closeError or "file gagal ditutup setelah dibaca")
    end
    return content
end

local function fetchUpdaterResponse(url)
    local function unpackResponse(response)
        if type(response) == "string" then return response, 200 end
        if type(response) ~= "table" then return nil, nil end
        local body = response.text or response.body or response.content
        local status = tonumber(response.status_code or response.status or response.code) or 200
        if type(body) == "string" then return body, status end
        return nil, status
    end

    local okRequests, requests = pcall(require, "requests")
    if okRequests and type(requests) == "table" and type(requests.get) == "function" then
        local ok, response = pcall(requests.get, url, { timeout = 15 })
        if ok then
            local body, status = unpackResponse(response)
            if body then return body, status end
        end
    end

    local httpLibrary = rawget(_G, "http")
    if type(httpLibrary) == "table" and type(httpLibrary.get) == "function" then
        local ok, response = pcall(httpLibrary.get, url, { timeout = 15 })
        if ok then
            local body, status = unpackResponse(response)
            if body then return body, status end
        end
    end

    local httpGet = rawget(_G, "httpGet") or rawget(_G, "http_get") or rawget(_G, "getHttp")
    if type(httpGet) == "function" then
        local ok, response = pcall(httpGet, url)
        if ok then
            local body, status = unpackResponse(response)
            if body then return body, status end
        end
    end
    return nil, nil, "API HTTP requests/httpGet MonetLoader tidak tersedia"
end

local function saveUpdaterContent(path, content)
    local file, openError = io.open(path, "wb")
    if not file then return false, tostring(openError) end
    local wrote, writeError = file:write(content)
    local closed, closeError = file:close()
    if not wrote or not closed then
        os.remove(path)
        return false, tostring(writeError or closeError or "gagal menutup file unduhan")
    end
    return true
end

local function downloadUpdaterFile(url, path, validate, fallbackUrls)
    local okMoonloader, moonloader = pcall(require, "moonloader")
    local downloadStatus = okMoonloader and type(moonloader) == "table"
        and moonloader.download_status or nil
    local maxAttempts = 2
    local lastError = "unduhan gagal"
    local lastHost = url:match("^https?://([^/]+)") or "server"
    local urls = { url }
    for _, fallbackUrl in ipairs(fallbackUrls or {}) do
        urls[#urls + 1] = fallbackUrl
    end

    if type(downloadUrlToFile) ~= "function" or type(downloadStatus) ~= "table" then
        for urlIndex, currentUrl in ipairs(urls) do
            lastHost = currentUrl:match("^https?://([^/]+)") or "server"
            for attempt = 1, maxAttempts do
                local attemptNumber = (urlIndex - 1) * maxAttempts + attempt
                local attemptPath = path .. ".attempt-" .. attemptNumber
                os.remove(attemptPath)
                local content, status, fetchError = fetchUpdaterResponse(currentUrl)
                if type(content) ~= "string" or status ~= 200 then
                    lastError = fetchError or ("respons HTTP " .. tostring(status or "tidak valid"))
                else
                    local saved, saveError = saveUpdaterContent(attemptPath, content)
                    if not saved then
                        lastError = saveError
                    else
                        local valid, validationError = true, nil
                        if validate then
                            local ok, result, detail = pcall(validate, attemptPath, content)
                            valid = ok and result or false
                            validationError = ok and detail or result
                        end
                        if not valid then
                            lastError = tostring(validationError or "isi file hasil unduhan tidak valid")
                        else
                            os.remove(path)
                            local moved, moveError = os.rename(attemptPath, path)
                            if moved then
                                updateStatus.currentBytes = #content
                                return true, nil, content
                            end
                            lastError = "file hasil unduhan tidak dapat dipasang: " .. tostring(moveError)
                        end
                    end
                end
                os.remove(attemptPath)
                if attemptNumber < #urls * maxAttempts then wait(500 * attemptNumber) end
            end
        end
        return false, string.format("gagal setelah %d percobaan melalui %d host: %s",
            #urls * maxAttempts, #urls, lastHost .. ": " .. lastError)
    end

    for urlIndex, currentUrl in ipairs(urls) do
        for attempt = 1, maxAttempts do
            local totalAttempts = #urls * maxAttempts
            local attemptNumber = (urlIndex - 1) * maxAttempts + attempt
            lastHost = currentUrl:match("^https?://([^/]+)") or "server"
            local attemptPath = path .. ".attempt-" .. attemptNumber
            os.remove(attemptPath)

            local success = false
            local failed = false
            local finalStatus
            updateStatus.currentBytes = 0
            local okStart, startResult, startError = pcall(downloadUrlToFile, currentUrl, attemptPath, function(_, status)
                finalStatus = status
                if status == downloadStatus.STATUS_DOWNLOADINGDATA
                    or status == downloadStatus.STATUSEX_DATAAVAILABLE then
                    local file = io.open(attemptPath, "rb")
                    if file then
                        updateStatus.currentBytes = file:seek("end") or updateStatus.currentBytes
                        file:close()
                    end
                end
                if status == downloadStatus.STATUS_ENDDOWNLOADDATA
                    or status == downloadStatus.STATUSEX_ENDDOWNLOAD
                    or status == downloadStatus.STATUS_USINGCACHEDCOPY then
                    success = true
                elseif (downloadStatus.STATUS_DOWNLOADERROR and status == downloadStatus.STATUS_DOWNLOADERROR)
                    or (downloadStatus.STATUS_DOWNLOAD_ERROR and status == downloadStatus.STATUS_DOWNLOAD_ERROR)
                    or (downloadStatus.STATUSEX_LOWRESOURCE and status == downloadStatus.STATUSEX_LOWRESOURCE)
                    or (downloadStatus.STATUS_SSLUX_NAVBLOCKED and status == downloadStatus.STATUS_SSLUX_NAVBLOCKED) then
                    failed = true
                end
            end)

            if not okStart then
                lastError = tostring(startResult)
            elseif startResult == false then
                lastError = tostring(startError or "downloadUrlToFile menolak unduhan")
            else
                local deadline = os.clock() + 45
                while not success and not failed and os.clock() < deadline do
                    local file = io.open(attemptPath, "rb")
                    if file then
                        updateStatus.currentBytes = file:seek("end") or updateStatus.currentBytes
                        file:close()
                    end
                    wait(50)
                end

                if failed then
                    lastError = "status unduhan " .. tostring(finalStatus)
                elseif not success then
                    lastError = "unduhan timeout"
                else
                    local content, readError = readUpdaterFile(attemptPath)
                    if not content then
                        lastError = readError
                    elseif content == "" then
                        lastError = "file unduhan kosong"
                    else
                        local valid = true
                        local validationError
                        if validate then
                            local validateOk, validationResult, validationMessage =
                                pcall(validate, attemptPath, content)
                            if not validateOk then
                                valid = false
                                validationError = tostring(validationResult)
                            else
                                valid = validationResult
                                validationError = validationMessage
                            end
                        end

                        if not valid then
                            lastError = tostring(validationError or "isi file hasil unduhan tidak valid")
                        else
                            os.remove(path)
                            local moved, moveError = os.rename(attemptPath, path)
                            if moved then
                                local savedContent, savedError = readUpdaterFile(path)
                                if savedContent == content then
                                    updateStatus.currentBytes = #savedContent
                                    return true, nil, savedContent
                                end
                                os.remove(path)
                                lastError = "file tidak terbaca setelah disimpan: "
                                    .. tostring(savedError or "isi file berubah")
                            else
                                lastError = "file hasil unduhan tidak dapat dipasang: " .. tostring(moveError)
                            end
                        end
                    end
                end
            end

            os.remove(attemptPath)
            if attemptNumber < totalAttempts then
                local host = currentUrl:match("^https?://([^/]+)") or "server"
                setUpdaterStatus("Mengulangi unduhan", string.format(
                    "Percobaan %d/%d via %s", attemptNumber + 1, totalAttempts, host))
                wait(500 * attemptNumber)
            end
        end
    end

    return false, string.format("gagal setelah %d percobaan melalui %d host: %s",
        #urls * maxAttempts, #urls, lastHost .. ": " .. lastError)
end

updateStatus.removeFiles = function(paths)
    for _, path in ipairs(paths) do
        os.remove(path)
    end
end

updateStatus.rollbackFiles = function(applied)
    for index = #applied, 1, -1 do
        local item = applied[index]
        os.remove(item.destination)
        if item.hadOriginal then
            local restored, restoreError = os.rename(item.backup, item.destination)
            if not restored then
                updateStatus.notice("Rollback gagal untuk " .. item.relativePath .. ": " .. tostring(restoreError))
            end
        end
    end
end

updateStatus.isAllowedPath = function(relativePath)
    if relativePath == "uijtrp.lua" then return true end
    local normalizedPath = relativePath:lower()
    local isModule = normalizedPath:sub(1, 7) == "uijtrp/"
    local isAsset = normalizedPath:sub(1, 7) == "assets/"
    local isPhoneAsset = normalizedPath:sub(1, 11) == "jtrp_phone/"
    if (not isModule and not isAsset and not isPhoneAsset) or relativePath:find("\\", 1, true)
        or relativePath:find("//", 1, true) or relativePath:find(":", 1, true)
        or not relativePath:match("^[%w_%.%-/]+$") then
        return false
    end

    local segments = {}
    for segment in normalizedPath:gmatch("[^/]+") do
        if segment == "." or segment == ".." or segment:sub(1, 1) == "." then
            return false
        end
        segments[#segments + 1] = segment
    end
    if #segments < 2 or segments[1] ~= "uijtrp" then return false end

    local extension = segments[#segments]:match("%.([%w]+)$")
    if not extension then return false end

    if isModule and normalizedPath:sub(1, 11) == "uijtrp/web/" then return false end
    if extension == "lua" then return true end

    if isPhoneAsset then
        for _, segment in ipairs(segments) do
            if segment:find("notif", 1, true)
                or segment:find("notify", 1, true)
                or segment:find("ringtone", 1, true) then
                return false
            end
        end
    end

    local allowedAssetExtensions = {
        bmp = true,
        gif = true,
        jpeg = true,
        jpg = true,
        m4a = true,
        mp3 = true,
        ogg = true,
        png = true,
        webp = true,
        wav = true,
    }
    return allowedAssetExtensions[extension] == true
end

updateStatus.isValidAsset = function(relativePath, content)
    local extension = relativePath:match("%.([%w]+)$")
    if not extension then return false, "ekstensi aset tidak valid" end
    extension = extension:lower()

    local valid = false
    if extension == "png" then
        valid = content:sub(1, 8) == "\137PNG\r\n\26\n"
    elseif extension == "jpg" or extension == "jpeg" then
        valid = content:sub(1, 3) == "\255\216\255"
    elseif extension == "gif" then
        valid = content:sub(1, 6) == "GIF87a" or content:sub(1, 6) == "GIF89a"
            or content:sub(1, 8) == "\137PNG\r\n\26\n"
    elseif extension == "bmp" then
        valid = content:sub(1, 2) == "BM"
    elseif extension == "webp" then
        valid = content:sub(1, 4) == "RIFF" and content:sub(9, 12) == "WEBP"
    elseif extension == "wav" then
        valid = content:sub(1, 4) == "RIFF" and content:sub(9, 12) == "WAVE"
    elseif extension == "mp3" then
        local first, second = content:byte(1, 2)
        valid = content:sub(1, 3) == "ID3"
            or (first == 255 and second and second >= 224)
    elseif extension == "ogg" then
        valid = content:sub(1, 4) == "OggS"
    elseif extension == "m4a" then
        valid = content:sub(5, 8) == "ftyp"
    elseif extension == "txt" then
        valid = not content:find("\0", 1, true)
    elseif extension == "json" then
        local json = content:match("^%s*(.-)%s*$")
        valid = json and json:sub(1, 1) == "{" and json:sub(-1) == "}"
            and json:find('"product"%s*:%s*"SanAndreasOnline%-Browser"') ~= nil
    elseif extension == "exe" then
        if content:sub(1, 2) == "MZ" and #content >= 64 then
            local b1, b2, b3, b4 = content:byte(61, 64)
            local peOffset = b1 + b2 * 256 + b3 * 65536 + b4 * 16777216
            valid = peOffset >= 64 and peOffset + 4 <= #content
                and content:sub(peOffset + 1, peOffset + 4) == "PE\0\0"
        end
    end

    if not valid then
        return false, "isi bukan file " .. extension .. " yang valid"
    end
    return true
end

updateStatus.ensureParentDirectory = function(relativePath)
    local current = scriptDirectory
    local segments = {}
    for segment in relativePath:gmatch("[^/]+") do
        segments[#segments + 1] = segment
    end
    for index = 1, #segments - 1 do
        current = joinPath(current, segments[index])
        if not doesDirectoryExist(current) then
            local okCreate, createError = pcall(createDirectory, current)
            if not okCreate or not doesDirectoryExist(current) then
                return false, tostring(createError or ("tidak bisa membuat " .. current))
            end
        end
    end
    return true
end

updateStatus.check = function()
    if not scriptDirectory then
        updateStatus.notice("Lokasi script tidak dapat ditentukan; update dibatalkan.")
        finishUpdaterStatus("Update gagal", "Lokasi script tidak dapat ditentukan.")
        return
    end

    local prefix = "https://raw.githubusercontent.com/" .. UPDATE_CONFIG.owner .. "/"
        .. UPDATE_CONFIG.repository .. "/"
    local commitUrl = "https://api.github.com/repos/" .. UPDATE_CONFIG.owner .. "/"
        .. UPDATE_CONFIG.repository .. "/commits/" .. UPDATE_CONFIG.branch
    local commitPath = joinPath(scriptDirectory, ".pbrp-update-commit.tmp")
    local manifestPath = joinPath(scriptDirectory, ".pbrp-update-manifest.tmp")
    local statePath = joinPath(scriptDirectory, ".pbrp-update-version")
    local temporaryPaths = { commitPath, manifestPath }
    local atomCommitUrl = "https://github.com/" .. UPDATE_CONFIG.owner .. "/"
        .. UPDATE_CONFIG.repository .. "/commits/" .. UPDATE_CONFIG.branch .. ".atom"

    setUpdaterStatus("Memeriksa GitHub", UPDATE_CONFIG.repository .. "/" .. UPDATE_CONFIG.branch)
    local downloaded, downloadError, commitBody = downloadUpdaterFile(commitUrl, commitPath, function(_, content)
        if content:match('"sha"%s*:%s*"[%x]+"')
            or content:match("Grit::Commit/[%x]+") then
            return true
        end
        return false, "respons GitHub tidak berisi commit yang valid"
    end, { atomCommitUrl })
    if not downloaded then
        updateStatus.removeFiles(temporaryPaths)
        updateStatus.notice("Tidak bisa memeriksa GitHub: " .. tostring(downloadError))
        finishUpdaterStatus("Pemeriksaan gagal", tostring(downloadError))
        return
    end

    local commit = commitBody and (commitBody:match('"sha"%s*:%s*"([%x]+)"')
        or commitBody:match("Grit::Commit/([%x]+)"))
    os.remove(commitPath)
    if not commit then
        updateStatus.removeFiles(temporaryPaths)
        updateStatus.notice("Respons GitHub tidak berisi commit yang valid.")
        finishUpdaterStatus("Pemeriksaan gagal", "Respons GitHub tidak berisi commit yang valid.")
        return
    end

    local installedCommit = readUpdaterFile(statePath)
    local sameCommit = installedCommit and installedCommit:match("^([%x]+)") == commit

    setUpdaterStatus("Memeriksa daftar file", "Commit " .. commit:sub(1, 7))
    local manifestUrl = prefix .. commit .. "/update-manifest.txt"
    local cdnPrefix = "https://cdn.jsdelivr.net/gh/" .. UPDATE_CONFIG.owner .. "/"
        .. UPDATE_CONFIG.repository .. "@" .. commit .. "/"
    local manifest
    downloaded, downloadError, manifest = downloadUpdaterFile(manifestUrl, manifestPath, function(_, content)
        local foundMainScript = false
        for line in content:gmatch("[^\r\n]+") do
            local relativePath = line:match("^%s*(.-)%s*$")
            if relativePath ~= "" and relativePath:sub(1, 1) ~= "#" then
                if relativePath:sub(1, 7):lower() == "ufjtrp/" then
                    relativePath = "uijtrp/" .. relativePath:sub(8)
                end
                if not updateStatus.isAllowedPath(relativePath) then
                    return false, "path manifest ditolak: " .. relativePath
                end
                if relativePath == "uijtrp.lua" then
                    foundMainScript = true
                end
            end
        end
        if not foundMainScript then
            return false, "manifest tidak menyertakan uijtrp.lua"
        end
        return true
    end, { cdnPrefix .. "update-manifest.txt" })
    if not downloaded then
        updateStatus.removeFiles(temporaryPaths)
        updateStatus.notice("Tidak bisa mengunduh manifest: " .. tostring(downloadError))
        finishUpdaterStatus("Update gagal", "Manifest: " .. tostring(downloadError))
        return
    end

    if not manifest then
        updateStatus.removeFiles(temporaryPaths)
        updateStatus.notice("Manifest update tidak dapat dibaca.")
        finishUpdaterStatus("Update gagal", "Manifest update tidak dapat dibaca.")
        return
    end

    os.remove(manifestPath)

    local files, seenPaths = {}, {}
    for line in manifest:gmatch("[^\r\n]+") do
        local relativePath = line:match("^%s*(.-)%s*$")
        if relativePath ~= "" and relativePath:sub(1, 1) ~= "#" then
            if relativePath:sub(1, 7):lower() == "ufjtrp/" then
                relativePath = "uijtrp/" .. relativePath:sub(8)
                updateStatus.notice("Path manifest ufjtrp/ dikoreksi menjadi uijtrp/.")
            end
            if not updateStatus.isAllowedPath(relativePath) then
                updateStatus.notice("Path di manifest ditolak: " .. relativePath)
                finishUpdaterStatus("Update dibatalkan", "Path manifest ditolak: " .. relativePath)
                return
            end
            if not seenPaths[relativePath] then
                seenPaths[relativePath] = true
                files[#files + 1] = relativePath
            end
        end
    end
    if #files == 0 or not seenPaths["uijtrp.lua"] then
        updateStatus.notice("Manifest kosong atau tidak menyertakan uijtrp.lua.")
        finishUpdaterStatus("Update dibatalkan", "Manifest harus menyertakan uijtrp.lua.")
        return
    end

    if sameCommit then
        local repairFiles = {}
        for _, relativePath in ipairs(files) do
            local localPath = relativePath:gsub("/", PATH_SEPARATOR)
            local destination = joinPath(scriptDirectory, localPath)
            local content = readUpdaterFile(destination)
            local needsRepair = not content or content == ""
            if not needsRepair and relativePath:lower():match("%.lua$") then
                local compiled = loadfile(destination)
                needsRepair = compiled == nil
            elseif not needsRepair then
                local validAsset = updateStatus.isValidAsset(relativePath, content)
                needsRepair = not validAsset
            end
            if needsRepair then
                repairFiles[#repairFiles + 1] = relativePath
            end
        end
        files = repairFiles
        if #files == 0 then
            print("[PBRP Updater] Script sudah versi terbaru.")
            finishUpdaterStatus("Versi terbaru", "Tidak ada file yang perlu diunduh.")
            return
        end
        updateStatus.notice(string.format("%d file hilang atau tidak terbaca; akan diunduh ulang.", #files))
    end

    updateStatus.completed = 0
    updateStatus.total = #files
    local staged, stagedPaths = {}, {}
    local downloadSoundPlayed = false
    for index, relativePath in ipairs(files) do
        local localPath = relativePath:gsub("/", PATH_SEPARATOR)
        local destination = joinPath(scriptDirectory, localPath)
        local temporary = destination .. ".pbrp-update.tmp"
        local backup = destination .. ".pbrp-update.bak"
        local sourceUrl = prefix .. commit .. "/" .. relativePath

        local directoryReady, directoryError = updateStatus.ensureParentDirectory(relativePath)
        if not directoryReady then
            updateStatus.removeFiles(stagedPaths)
            updateStatus.notice("Folder tujuan gagal disiapkan untuk " .. relativePath .. ": " .. directoryError)
            finishUpdaterStatus("Pemasangan gagal", relativePath .. ": " .. directoryError)
            return
        end

        updateStatus.currentBytes = 0
        setUpdaterStatus("Mengunduh file", string.format("%d/%d  %s", index, #files, relativePath))
        if not downloadSoundPlayed then
            playUpdaterDownloadSound()
            downloadSoundPlayed = true
        end
        os.remove(temporary)
        downloaded, downloadError = downloadUpdaterFile(sourceUrl, temporary, function(path, content)
            if relativePath:lower():match("%.lua$") then
                local compiled, compileError = loadfile(path)
                return compiled ~= nil, compileError
            end
            return updateStatus.isValidAsset(relativePath, content)
        end, { cdnPrefix .. relativePath })
        if not downloaded then
            updateStatus.removeFiles(stagedPaths)
            os.remove(temporary)
            updateStatus.notice("Gagal mengunduh " .. relativePath .. ": " .. tostring(downloadError))
            finishUpdaterStatus("Unduhan gagal", relativePath .. ": " .. tostring(downloadError))
            return
        end

        staged[#staged + 1] = {
            relativePath = relativePath,
            destination = destination,
            temporary = temporary,
            backup = backup,
            hadOriginal = updaterFileExists(destination),
        }
        stagedPaths[#stagedPaths + 1] = temporary
        updateStatus.completed = index
    end

    setUpdaterStatus("Memasang update", string.format("%d file", #files))
    local stateTemporary = statePath .. ".tmp"
    local stateFile, stateError = io.open(stateTemporary, "wb")
    if not stateFile then
        updateStatus.removeFiles(stagedPaths)
        updateStatus.notice("Tidak bisa menyimpan versi update: " .. tostring(stateError))
        finishUpdaterStatus("Pemasangan gagal", tostring(stateError))
        return
    end
    local wroteState, writeError = stateFile:write(commit, "\n")
    local closedState, closeError = stateFile:close()
    if not wroteState or not closedState then
        os.remove(stateTemporary)
        updateStatus.removeFiles(stagedPaths)
        updateStatus.notice("Tidak bisa menulis versi update: " .. tostring(writeError or closeError))
        finishUpdaterStatus("Pemasangan gagal", tostring(writeError or closeError))
        return
    end
    staged[#staged + 1] = {
        relativePath = "versi update",
        destination = statePath,
        temporary = stateTemporary,
        backup = statePath .. ".bak",
        hadOriginal = updaterFileExists(statePath),
    }

    local applied = {}
    for _, item in ipairs(staged) do
        os.remove(item.backup)
        if item.hadOriginal then
            local backedUp, backupError = os.rename(item.destination, item.backup)
            if not backedUp then
                updateStatus.rollbackFiles(applied)
                updateStatus.removeFiles(stagedPaths)
                os.remove(stateTemporary)
                updateStatus.notice("Tidak bisa membuat backup " .. item.relativePath .. ": " .. tostring(backupError))
                finishUpdaterStatus("Pemasangan gagal", "Backup gagal: " .. item.relativePath)
                return
            end
        end

        local installed, installError = os.rename(item.temporary, item.destination)
        if not installed then
            if item.hadOriginal then
                local restored, restoreError = os.rename(item.backup, item.destination)
                if not restored then
                    updateStatus.notice("Rollback gagal untuk " .. item.relativePath .. ": " .. tostring(restoreError))
                end
            end
            updateStatus.rollbackFiles(applied)
            updateStatus.removeFiles(stagedPaths)
            os.remove(stateTemporary)
            updateStatus.notice("Tidak bisa memasang " .. item.relativePath .. ": " .. tostring(installError))
            finishUpdaterStatus("Pemasangan gagal", "Gagal mengganti " .. item.relativePath)
            return
        end
        applied[#applied + 1] = item
    end

    for _, item in ipairs(applied) do
        if item.hadOriginal then os.remove(item.backup) end
    end
    updateStatus.notice("Update GitHub berhasil. Script akan dimuat ulang.")
    finishUpdaterStatus("Update selesai", string.format("%d file terpasang. Memuat ulang...", #files))
    wait(1000)
    thisScript():reload()
end

function main()
    while not isSampAvailable() do wait(100) end
    sampAddChatMessage("[PekanBaru UI] Client UI aktif. F2 membuka menu utama; M atau /lradial membuka radial.", 0xFFD4AF37)
    if #loadErrors > 0 then
        sampAddChatMessage("[PBRP/PKU UI] " .. #loadErrors .. " modul gagal dimuat. Lihat moonloader.log atau menu Beranda.", 0xFFFF6A6A)
    end
    sampRegisterChatCommand("rpui", toggleMenu)
    sampRegisterChatCommand("lradial", toggleRadial)
    sampRegisterChatCommand("adminui", toggleAdminUi)
    sampRegisterChatCommand("browser", openGameBrowser)
    sampRegisterChatCommand("factioncar", toggleFactionVehicleUi)
    sampRegisterChatCommand("rpuihud", function()
        hudOpen[0] = not hudOpen[0]
    end)
    sampRegisterChatCommand("rpuihudedit", CONFIG.hud.toggleEdit)
    sampRegisterChatCommand("rpuifps", function()
        CONFIG.hud.showFps = not CONFIG.hud.showFps
        fpsEnabled[0] = CONFIG.hud.showFps
    end)
    if textdrawReader then
        sampRegisterChatCommand("tddump", function()
            textdrawReader.scan()
            local count, pathOrError = textdrawReader.dump()
            if count then
                sampAddChatMessage(string.format("[PekanBaru UI] %d textdraw ditulis ke %s", count, pathOrError), 0xFFD4AF37)
            else
                logUiError("tddump", pathOrError)
                sampAddChatMessage("[PBRP/PKU UI] Gagal menulis dump textdraw. Lihat moonloader.log.", 0xFFFF6A6A)
            end
        end)
    end

    local lastReadyHeartbeat = 0
    local wasPlayerSpawned = false
    local lastObservedServer = nil
    local nextServerCheck = 0
    local nextUpdateCheck = 0
    local updateCheckRunning = false

    local function tick()
        local spawned = isSampAvailable() and sampIsLocalPlayerSpawned() and true or false
        playerSpawned = spawned
        if phoneUI.updateSharedMusic then phoneUI.updateSharedMusic() end
        local typing = isSampAvailable() and (sampIsChatInputActive() or sampIsDialogActive())
        interactionUI.update(spawned and not typing and not menuOpen[0] and not radialOpen[0]
            and not adminOpen[0] and not isOtherUiOpen())
        if not spawned then
            lastReadyHeartbeat = 0
            adminLevel = -1
            phoneUI.reset()
            radialItems[10] = { label = "RIWAYAT WARN", icon = "help", command = "/mywarn", hint = "/mywarn" }
            radialItems[11] = nil
            vipRubyUI.reset()
            adminPanelUI.reset()
            factionVehicleUI.reset()
            factionPanelUI.reset()
            mechanicServiceUI.reset()
            businessUI.reset()
            -- keluar dari spawn / disconnect: pastikan menu tidak menggantung
            menuOpen[0] = false
            radialOpen[0] = false
            adminOpen[0] = false
        else
            if not wasPlayerSpawned then
                loadingUI.finishConnection()
            end
            if not wasPlayerSpawned or os.time() - lastReadyHeartbeat >= 10 then
                sampSendChat("/rpui_client_ready 2")
                lastReadyHeartbeat = os.time()
            end
        end
        wasPlayerSpawned = spawned
        if not (isSampAvailable() and isPlayerUiReady()) then return end

        if wasKeyPressed(0x4D) and not typing and not isOtherUiOpen() then
            toggleRadial()
        end
        if wasKeyPressed(0x71) and not typing then
            toggleMenu()
        end
        if wasKeyPressed(0x72) and not typing then
            toggleAdminUi()
        end
        -- pintasan angka 1..9, 0 saat radial terbuka
        if radialOpen[0] and not typing then
            local entries = getRadialEntries()
            for idx, vk in ipairs(RADIAL_KEYS) do
                if entries[idx] and wasKeyPressed(vk) then
                    uiSounds.play("click")
                    radialAction(entries[idx])
                    break
                end
            end
        end
        if wasKeyPressed(0x1B) and factionPanelUI.isOpen() then
            factionPanelUI.close()
        elseif wasKeyPressed(0x1B) and mechanicServiceUI.isOpen() then
            mechanicServiceUI.close()
        elseif wasKeyPressed(0x1B) and businessUI.isOpen() then
            businessUI.close()
        elseif wasKeyPressed(0x1B) and not typing then
            if phoneUI.isOpen() then
                phoneUI.close()
            elseif inventoryUI.isOpen() then
                inventoryUI.close()
            elseif vehiclesUI.isOpen() then
                vehiclesUI.close()
            elseif factionVehicleUI.isOpen() then
                factionVehicleUI.toggle()
            elseif factionPanelUI.isOpen() then
                factionPanelUI.reset()
            elseif mechanicServiceUI.isOpen() then
                mechanicServiceUI.close()
            elseif businessUI.isOpen() then
                businessUI.close()
            elseif vipRubyUI.isOpen() then
                vipRubyUI.close()
            elseif radialOpen[0] then
                radialOpen[0] = false
            elseif adminOpen[0] then
                adminOpen[0] = false
            elseif menuOpen[0] then
                menuOpen[0] = false
            end
        end
    end

    while true do
        wait(0)
        if os.time() >= nextServerCheck then
            nextServerCheck = os.time() + 1
            if not isSampAvailable() then
                lastObservedServer = nil
                nextUpdateCheck = 0
            else
                local serverIp = sampGetCurrentServerAddress()
                if serverIp then
                    local normalizedIp = tostring(serverIp)
                    if normalizedIp ~= lastObservedServer then
                        lastObservedServer = normalizedIp
                    end
                    if normalizedIp == UPDATE_CONFIG.serverIp
                        and os.clock() >= nextUpdateCheck and not updateCheckRunning then
                        nextUpdateCheck = os.clock() + UPDATE_CONFIG.checkIntervalSeconds
                        updateCheckRunning = true
                        lua_thread.create(function()
                            local ok, updateError = pcall(updateStatus.check)
                            updateCheckRunning = false
                            if not ok then
                                updateStatus.notice("Pemeriksaan update gagal: " .. tostring(updateError))
                                finishUpdaterStatus("Update gagal", tostring(updateError))
                            end
                            local retryableStatuses = {
                                ["Pemeriksaan gagal"] = true,
                                ["Update gagal"] = true,
                                ["Unduhan gagal"] = true,
                                ["Pemasangan gagal"] = true,
                            }
                            if updateStatus.title ~= "Versi terbaru"
                                and updateStatus.title ~= "Update selesai"
                                and not retryableStatuses[updateStatus.title] then
                                nextUpdateCheck = os.clock() + UPDATE_CONFIG.checkIntervalSeconds
                            else
                                nextUpdateCheck = os.clock() + UPDATE_CONFIG.checkIntervalSeconds * 2
                            end
                        end)
                    elseif normalizedIp ~= UPDATE_CONFIG.serverIp then
                        nextUpdateCheck = 0
                    end
                else
                    lastObservedServer = nil
                    nextUpdateCheck = 0
                end
            end
        end
        -- error di satu tick tidak boleh mematikan seluruh script
        local ok, err = pcall(tick)
        if not ok then logUiError("main loop", err) end
    end
end
