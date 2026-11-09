-- ============================================================
--  PBRP/PKU UI - Loading Screen (versi premium)
-- ============================================================
local CONNECT_DURATION = 32
local OBJECT_DURATION  = 12
local FADE_IN          = 0.9     -- detik
local FADE_OUT         = 0.9     -- detik
local OBJECT_FINISH    = 0.8     -- detik animasi 100% saat object selesai

local CONNECT_STAGES = {
    { 0.00, "MENGHUBUNGKAN KE SERVER",  "Membuat koneksi yang aman..." },
    { 0.18, "AUTENTIKASI AKUN",         "Memverifikasi data karakter kamu..." },
    { 0.38, "MENGUNDUH DATA DUNIA",     "Menyinkronkan kendaraan, properti, dan bisnis..." },
    { 0.62, "MEMUAT LINGKUNGAN KOTA",   "Menyiapkan object map dan tekstur..." },
    { 0.85, "FINALISASI",               "Hampir selesai, bersiap masuk ke kota..." },
}

local OBJECT_STAGES = {
    { 0.00, "MEMUAT OBJECT DUNIA",      "Memuat object map..." },
    { 0.30, "MENYIAPKAN KOTA",          "Menyiapkan lingkungan kota..." },
    { 0.60, "MENYINKRONKAN DUNIA",      "Menyinkronkan dunia roleplay..." },
    { 0.90, "MERAPIKAN DETAIL",         "Sentuhan terakhir sebelum masuk..." },
}

return function(imgui, V2, imagePath)
    local objectLoading = false
    local objectStart = 0
    local finishAt = 0
    local finishUntil = 0
    local finishFrom = 0
    local startedAt = 0
    local connectionLoading = false
    local texture
    local objectFinishRequested = false
    local master = 1 -- alpha global per-frame
    local players = {}
    local playerCount = 0
    local playersUpdatedAt = 0

    imgui.OnInitialize(function()
        local function loadTexture(path, label)
            if not path or not doesFileExist(path) then
                print("[PBRP/PKU UI] Gambar " .. label .. " tidak ditemukan: " .. tostring(path))
                return nil
            end
            local ok, loadedTexture = pcall(imgui.CreateTextureFromFile, path)
            if ok and loadedTexture then
                return loadedTexture
            end
            print("[PBRP/PKU UI] Gagal memuat gambar " .. label .. ": " .. tostring(loadedTexture))
            return nil
        end

        texture = loadTexture(imagePath, "loading")
    end)

    local function startConnection()
        startedAt = os.clock()
        objectStart = startedAt
        finishUntil = 0
        objectLoading = false
        objectFinishRequested = false
        connectionLoading = true
    end

    local function finishConnection()
        if not connectionLoading and not objectLoading then
            return
        end
        local now = os.clock()
        if objectLoading and now - objectStart < OBJECT_DURATION then
            objectFinishRequested = true
            return
        end
        local progressStart = objectLoading and objectStart or startedAt
        local elapsed = math.max(0, now - progressStart)
        if objectLoading then
            finishFrom = 0.96 * math.min(elapsed / OBJECT_DURATION, 1)
        else
            finishFrom = math.min(0.96, 0.96 * (1 - math.exp(-elapsed / 8)))
        end
        finishAt = now
        finishUntil = now + OBJECT_FINISH + FADE_OUT
        connectionLoading = false
        objectLoading = false
        objectFinishRequested = false
    end

    local function cancelConnection()
        connectionLoading = false
        objectLoading = false
        objectFinishRequested = false
        finishUntil = 0
    end

    local function onServerMessage(text)
        if text == "@PBRPUI:CONNECT:LOADING" then
            startConnection()
            return true
        end
        if text == "@PBRPUI:OBJECTS:LOAD:BEGIN" then
            if not connectionLoading then
                startedAt = os.clock()
                connectionLoading = true
            end
            objectLoading = true
            objectStart = os.clock()
            objectFinishRequested = false
            finishUntil = 0
            return true
        end
        if text == "@PBRPUI:OBJECTS:LOAD:END" then
            finishConnection()
            return true
        end
        return false
    end

    local function isActive()
        local now = os.clock()
        return connectionLoading or objectLoading or now < finishUntil
    end

    ---------------------------------------------------------------- helpers
    local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
    local function smooth(t) t = clamp(t, 0, 1); return t * t * (3 - 2 * t) end
    local function lerp(a, b, t) return a + (b - a) * t end

    local function col(r, g, b, a)
        return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, (a or 1) * master))
    end

    local function textC(dl, text, cx, y, color, scale, shadow)
        imgui.SetWindowFontScale(scale or 1)
        local s = imgui.CalcTextSize(text)
        local x = cx - s.x / 2
        if shadow then
            dl:AddText(V2(x + 1.5, y + 1.5), col(0, 0, 0, 0.65), text)
        end
        dl:AddText(V2(x, y), color, text)
        imgui.SetWindowFontScale(1)
        return s
    end

    local function textL(dl, text, x, y, color, scale, shadow)
        imgui.SetWindowFontScale(scale or 1)
        if shadow then
            dl:AddText(V2(x + 1, y + 1), col(0, 0, 0, 0.65), text)
        end
        dl:AddText(V2(x, y), color, text)
        imgui.SetWindowFontScale(1)
    end

    local function refreshPlayers(now)
        if now - playersUpdatedAt < 1 or not isSampAvailable() then
            return
        end

        playersUpdatedAt = now
        local refreshed = {}
        local maxPlayerId = sampGetMaxPlayerId(false)
        for id = 0, maxPlayerId do
            if sampIsPlayerConnected(id) then
                local name = sampGetPlayerNickname(id)
                if name and name ~= "" then
                    refreshed[#refreshed + 1] = {
                        name = name:gsub("_", " "),
                        ping = sampGetPlayerPing(id),
                    }
                end
            end
        end
        players = refreshed
        playerCount = #refreshed
    end

    local function stageFor(list, p)
        local idx = 1
        for i = 1, #list do
            if p >= list[i][1] then idx = i end
        end
        return idx, list[idx]
    end

    ---------------------------------------------------------------- frame
    local frame
    frame = imgui.OnFrame(
        function()
            return isActive()
        end,
        function()
            local now = os.clock()
            if objectLoading and objectFinishRequested
                and now - objectStart >= OBJECT_DURATION then
                finishConnection()
            end
            frame.LockPlayer = isActive()

            -- tentukan mode, progress, dan alpha global
            local mode, progress, elapsed
            master = 1
            if objectLoading then
                mode = "object"
                elapsed = now - objectStart
                progress = 0.96 * clamp(elapsed / OBJECT_DURATION, 0, 1)
                master = 1
            elseif connectionLoading then
                mode = "connect"
                elapsed = now - startedAt
                progress = math.min(0.96, 0.96 * (1 - math.exp(-elapsed / 8)))
                master = smooth(elapsed / FADE_IN)
            else
                mode = "finish"
                elapsed = now - objectStart
                local ft = now - finishAt
                progress = lerp(finishFrom, 1, smooth(ft / OBJECT_FINISH))
                master = smooth((finishUntil - now) / FADE_OUT)
            end
            master = clamp(master, 0, 1)

            local display = imgui.GetIO().DisplaySize
            local W, H = display.x, display.y
            local cx = W / 2
            local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs
            imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
            imgui.SetNextWindowSize(display, imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(master)
            imgui.Begin("##PBRP_object_loading", nil, flags)

            local dl = imgui.GetWindowDrawList()

            -- ===== latar belakang (zoom pelan ala Ken Burns) =====
            local zoom = 1 + 0.035 * clamp(elapsed / CONNECT_DURATION, 0, 1.2)
            if texture then
                local dx, dy = W * (zoom - 1) / 2, H * (zoom - 1) / 2
                dl:AddImage(texture, V2(-dx, -dy), V2(W + dx, H + dy),
                    V2(0, 0), V2(1, 1), col(1, 1, 1, 1))
            else
                dl:AddRectFilledMultiColor(V2(0, 0), V2(W, H),
                    col(0.08, 0.015, 0.02, 1), col(0.14, 0.02, 0.025, 1),
                    col(0.02, 0.01, 0.01, 1), col(0.03, 0.01, 0.01, 1))
            end

            -- vignette atas & bawah
            dl:AddRectFilledMultiColor(V2(0, 0), V2(W, 190),
                col(0.01, 0.005, 0.005, 0.85), col(0.01, 0.005, 0.005, 0.85),
                col(0.01, 0.005, 0.005, 0), col(0.01, 0.005, 0.005, 0))
            dl:AddRectFilledMultiColor(V2(0, H - 300), V2(W, H),
                col(0.01, 0.005, 0.005, 0), col(0.01, 0.005, 0.005, 0),
                col(0.01, 0.005, 0.005, 0.95), col(0.01, 0.005, 0.005, 0.95))

            refreshPlayers(now)
            local pulse = (math.sin(now * 2.4) + 1) / 2
            local list = (mode == "connect") and CONNECT_STAGES or OBJECT_STAGES
            local _, stage = stageFor(list, progress)
            if mode == "finish" then
                stage = { 1, "SELESAI", "Selamat bermain!" }
            end

            -- ===== panel tim staff =====
            local sideMargin = math.max(18, math.min(32, W * 0.03))
            local panelW = math.min(320, W * 0.235)
            local panelY = H * 0.23
            local panelH = math.min(430, H * 0.56)
            local panelPad = math.max(10, math.min(16, W * 0.018))
            local rowH = clamp(H * 0.058, 21, 29)
            local leftX = sideMargin
            local rightX = W - sideMargin - panelW
            local panelBottom = panelY + panelH

            local function drawPanel(x, title)
                dl:AddRectFilled(V2(x, panelY), V2(x + panelW, panelBottom),
                    col(0.035, 0.035, 0.04, 0.82), 5)
                dl:AddRect(V2(x, panelY), V2(x + panelW, panelBottom),
                    col(1, 1, 1, 0.12), 5, 0, 1)
                dl:AddRectFilled(V2(x, panelY), V2(x + panelW, panelY + 2),
                    col(0.90, 0.08, 0.10, 0.95), 2)
                textL(dl, title, x + panelPad, panelY + 11,
                    col(1, 1, 1, 1), 0.95, true)
            end

            drawPanel(leftX, "STAFF TEAM")
            local staff = {
                { "Ryvann", "LEAD" },
                { "PekanTeam Dev", "DEV" },
            }
            local staffY = panelY + 36
            for i, member in ipairs(staff) do
                local y = staffY + (i - 1) * rowH
                dl:AddRectFilled(V2(leftX + 7, y), V2(leftX + panelW - 7, y + rowH - 2),
                    col(0.12, 0.10, 0.09, 0.64), 2)
                dl:AddRectFilled(V2(leftX + 10, y + 4), V2(leftX + 24, y + rowH - 6),
                    col(0.93, 0.68, 0.20, 0.95), 2)
                textC(dl, "N", leftX + 17, y + 4,
                    col(0.12, 0.08, 0.02, 1), 0.65, false)
                textL(dl, member[1], leftX + 30, y + 5,
                    col(0.95, 0.93, 0.93, 1), 0.83, false)
                imgui.SetWindowFontScale(0.68)
                local roleSize = imgui.CalcTextSize(member[2])
                dl:AddText(V2(leftX + panelW - panelPad - roleSize.x, y + 6),
                    col(0.93, 0.27, 0.29, 1), member[2])
                imgui.SetWindowFontScale(1)
            end
            textL(dl, "Made by PekanCommunity", leftX + panelPad, panelBottom - 22,
                col(0.73, 0.70, 0.72, 0.95), 0.75, false)

            -- ===== panel pemain online =====
            drawPanel(rightX, string.format("PLAYERS  %d", playerCount))
            local maxRows = math.min(8, math.max(0, math.floor((panelH - 47) / rowH)))
            local playerY = panelY + 36
            if #players == 0 then
                textL(dl, "Menunggu data pemain...", rightX + panelPad, playerY + 6,
                    col(0.78, 0.76, 0.78, 1), 0.82, false)
            else
                for i = 1, math.min(#players, maxRows) do
                    local player = players[i]
                    local y = playerY + (i - 1) * rowH
                    dl:AddRectFilled(V2(rightX + 7, y), V2(rightX + panelW - 7, y + rowH - 2),
                        col(0.12, 0.10, 0.09, 0.64), 2)
                    dl:AddRectFilled(V2(rightX + 10, y + 4), V2(rightX + 24, y + rowH - 6),
                        col(0.93, 0.68, 0.20, 0.95), 2)
                    textC(dl, "N", rightX + 17, y + 4,
                        col(0.12, 0.08, 0.02, 1), 0.65, false)
                    local name = player.name
                    if #name > 15 then name = name:sub(1, 13) .. ".." end
                    textL(dl, name, rightX + 30, y + 5,
                        col(0.95, 0.93, 0.93, 1), 0.83, false)
                    local pingText = tostring(player.ping)
                    imgui.SetWindowFontScale(0.72)
                    local pingSize = imgui.CalcTextSize(pingText)
                    dl:AddText(V2(rightX + panelW - panelPad - pingSize.x, y + 6),
                        col(0.92, 0.25, 0.27, 1), pingText)
                    imgui.SetWindowFontScale(1)
                end
            end

            -- ===== branding utama =====
            imgui.SetWindowFontScale(2.35)
            local pekanSize = imgui.CalcTextSize("PEKAN")
            local baruSize = imgui.CalcTextSize("BARU")
            local titleX = cx - (pekanSize.x + baruSize.x) / 2
            local titleY = H * 0.395
            dl:AddText(V2(titleX + 1, titleY + 2), col(0, 0, 0, 0.7), "PEKAN")
            dl:AddText(V2(titleX + pekanSize.x + 1, titleY + 2), col(0, 0, 0, 0.7), "BARU")
            dl:AddText(V2(titleX, titleY), col(0.94, 0.08, 0.11, 1), "PEKAN")
            dl:AddText(V2(titleX + pekanSize.x, titleY), col(1, 1, 1, 1), "BARU")
            imgui.SetWindowFontScale(1)

            textC(dl, "ROLEPLAY", cx, titleY + 42,
                col(1, 1, 1, 1), 1.05, true)
            local dividerW = math.min(270, W * 0.30)
            dl:AddRectFilled(V2(cx - dividerW / 2, titleY + 70),
                V2(cx + dividerW / 2, titleY + 72), col(0.90, 0.08, 0.10, 0.80))
            textC(dl, "Kota penuh cerita, mulai kisahmu di Pekanbaru.",
                cx, titleY + 85, col(0.91, 0.89, 0.89, 1), 0.83, true)
            textC(dl, stage[2], cx, titleY + 120,
                col(1, 1, 1, 0.88 + pulse * 0.12), 0.77, false)
            textC(dl, stage[3], cx, titleY + 138,
                col(0.82, 0.80, 0.81, 0.95), 0.70, false)

            -- ===== progress bar =====
            local barW = math.min(560, W * 0.31)
            local barX = (W - barW) / 2
            local barY = H * 0.965
            local barH = 4
            dl:AddRectFilled(V2(barX, barY), V2(barX + barW, barY + barH),
                col(0.75, 0.75, 0.75, 0.55))

            local fillW = barW * clamp(progress, 0, 1)
            if fillW > 1 then
                dl:AddRectFilled(V2(barX, barY), V2(barX + fillW, barY + barH),
                    col(0.94, 0.08, 0.11, 1))
            end
            textC(dl, string.format("%d%%", math.floor(progress * 100 + 0.0001)),
                cx, barY - 18, col(1, 1, 1, 1), 0.78, true)
            textL(dl, "PekanBaru Roleplay", sideMargin, H - 24,
                col(0.78, 0.74, 0.76, 0.90), 0.68, false)

            imgui.End()
        end
    )
    frame.HideCursor = true
    frame.LockPlayer = false

    return {
        startConnection = startConnection,
        finishConnection = finishConnection,
        cancelConnection = cancelConnection,
        onServerMessage = onServerMessage,
        isActive = isActive
    }
end
