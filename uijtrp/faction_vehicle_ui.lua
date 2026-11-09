return function(imgui, V2, isPlayerUiReady, sendCommand)
    local sirenActive = false
    local hazardActive = false
    local strobeActive = false
    local blinkActive = false
    local menuOpen = false

    -- ====== Warna tema ======
    local function C(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1.0) end
    local COL = {
        bg        = C(0.07, 0.09, 0.13, 0.96),
        panel     = C(0.11, 0.14, 0.20, 1.0),
        text      = C(0.90, 0.93, 0.98, 1.0),
        dim       = C(0.55, 0.60, 0.70, 1.0),
        off       = C(0.15, 0.19, 0.27, 1.0),
        offHover  = C(0.20, 0.25, 0.35, 1.0),
        red       = C(0.90, 0.16, 0.20, 1.0),
        blue      = C(0.15, 0.45, 0.95, 1.0),
        amber     = C(1.00, 0.68, 0.10, 1.0),
        green     = C(0.20, 0.85, 0.45, 1.0),
        accent    = C(0.94, 0.70, 0.25, 1.0),
    }

    local function u32(c) return imgui.ColorConvertFloat4ToU32(c) end
    local function scale(c, k) return C(math.min(c.x * k, 1), math.min(c.y * k, 1), math.min(c.z * k, 1), c.w) end

    local function isDriving()
        if not isCharInAnyCar or not getCarCharIsUsing or not getDriverOfCar then
            return false
        end
        local okInCar, inCar = pcall(isCharInAnyCar, PLAYER_PED)
        if not okInCar or not inCar then return false end
        local okCar, vehicle = pcall(getCarCharIsUsing, PLAYER_PED)
        if not okCar or not vehicle then return false end
        local okDriver, driver = pcall(getDriverOfCar, vehicle)
        return okDriver and driver == PLAYER_PED
    end

    -- ====== Komponen UI ======
    local function bigToggle(label, sub, active, colOn, height, width)
        local pulse = active and (0.82 + 0.18 * math.sin(os.clock() * 6)) or 1.0
        local base  = active and scale(colOn, pulse) or COL.off
        local hover = active and scale(colOn, 1.15) or COL.offHover
        imgui.PushStyleColor(imgui.Col.Button, base)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, hover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, scale(base, 0.8))
        imgui.PushStyleColor(imgui.Col.Text, active and C(1, 1, 1, 1) or COL.text)
        local w = width or imgui.GetContentRegionAvail().x
        local clicked = imgui.Button(label, V2(w, height))
        imgui.PopStyleColor(4)
        return clicked
    end

    local function statusDot(dl, label, on, colOn)
        local p = imgui.GetCursorScreenPos()
        local col = on and colOn or COL.dim
        dl:AddCircleFilled(V2(p.x + 6, p.y + 8), 5, u32(col))
        if on then
            dl:AddCircle(V2(p.x + 6, p.y + 8), 8, u32(C(col.x, col.y, col.z, 0.35)), 16, 1.5)
        end
        imgui.SetCursorPosX(imgui.GetCursorPosX() + 20)
        imgui.TextColored(on and COL.text or COL.dim, label)
    end

    local function drawLightBar(dl, width, height, active, hazard)
        local p = imgui.GetCursorScreenPos()
        local half = width / 2
        local phase = math.floor(os.clock() * 5) % 2 == 0
        local function lamp(x0, x1, col, lit)
            local c = lit and col or C(col.x * 0.22, col.y * 0.22, col.z * 0.22, 1)
            dl:AddRectFilled(V2(p.x + x0, p.y), V2(p.x + x1, p.y + height), u32(c), 7)
            if lit then
                dl:AddRect(V2(p.x + x0 - 2, p.y - 2), V2(p.x + x1 + 2, p.y + height + 2), u32(C(col.x, col.y, col.z, 0.4)), 8, 0, 2)
            end
        end
        if hazard and not active then
            local lit = phase
            lamp(0, half - 3, COL.amber, lit)
            lamp(half + 3, width, COL.amber, lit)
        else
            lamp(0, half - 3, COL.red, active and phase)
            lamp(half + 3, width, COL.blue, active and not phase)
        end
        imgui.Dummy(V2(width, height))
    end

    local frame
    frame = imgui.OnFrame(
        function()
            return isSampAvailable() and isPlayerUiReady()
                and (sirenActive or (menuOpen and isDriving()))
        end,
        function()
            if not menuOpen or not isDriving() then return end

            local display = imgui.GetIO().DisplaySize
            local width, height = 300, 410
            imgui.SetNextWindowPos(V2(display.x - width - 18, (display.y - height) / 2), imgui.Cond.Always)
            imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)

            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(14, 12))
            imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(8, 8))
            imgui.PushStyleColor(imgui.Col.WindowBg, COL.bg)
            imgui.PushStyleColor(imgui.Col.Border, C(0.42, 0.14, 0.10, 0.6))
            imgui.PushStyleColor(imgui.Col.Separator, C(0.42, 0.14, 0.10, 0.5))

            local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoScrollbar
            imgui.Begin("##PBRP_faction_vehicle", nil, flags)
            local dl = imgui.GetWindowDrawList()
            local innerW = imgui.GetContentRegionAvail().x

            -- Header
            imgui.TextColored(COL.accent, "KENDARAAN DARURAT")
            imgui.SameLine(innerW - 28)
            if imgui.Button("X", V2(24, 22)) then
                menuOpen = false
                frame.HideCursor = true
            end
            imgui.Separator()

            -- Light bar animasi
            drawLightBar(dl, innerW, 14, sirenActive or strobeActive or blinkActive, hazardActive)

            -- Kontrol suara sirene
            if bigToggle(sirenActive and "SIRENE  :  ON" or "SIRENE  :  OFF", "", sirenActive, COL.red, 56) then
                sirenActive = not sirenActive
                sendCommand(sirenActive and "/siren on" or "/siren off")
            end

            -- Strobo kendaraan terpisah dari suara sirene
            if bigToggle(strobeActive and "STROBO  :  ON" or "STROBO  :  OFF", "", strobeActive, COL.blue, 42) then
                if not strobeActive and (hazardActive or blinkActive) then
                    sampAddChatMessage("[PBRP/PKU] Matikan hazard atau blink lights sebelum menyalakan strobo.", 0xFFFFB96B)
                else
                    sendCommand(strobeActive and "/togstrobo off" or "/togstrobo on")
                    strobeActive = not strobeActive
                end
            end

            if bigToggle(blinkActive and "BLINK LIGHTS  :  ON" or "BLINK LIGHTS  :  OFF", "", blinkActive, COL.blue, 42) then
                if not blinkActive and (hazardActive or strobeActive) then
                    sampAddChatMessage("[PBRP/PKU] Matikan hazard dan strobo sebelum menyalakan blink lights.", 0xFFFFB96B)
                else
                    sendCommand("/blinklights")
                    blinkActive = not blinkActive
                end
            end

            -- Flash lampu kendaraan satu kali
            if bigToggle("FLASH LIGHTS", "", false, COL.amber, 42) then
                sendCommand("/togflashlight")
            end

            -- Tombol hazard
            if bigToggle(hazardActive and "HAZARD  :  ON" or "HAZARD  :  OFF", "", hazardActive, COL.amber, 44) then
                if not hazardActive and (strobeActive or blinkActive) then
                    sampAddChatMessage("[PBRP/PKU] Matikan strobo atau blink lights sebelum menyalakan hazard.", 0xFFFFB96B)
                else
                    sendCommand("/toghazard")
                    hazardActive = not hazardActive
                end
            end

            -- Panel status
            imgui.Separator()
            statusDot(dl, "Sirene", sirenActive, COL.red)
            imgui.SameLine(innerW / 2)
            statusDot(dl, "Hazard", hazardActive, COL.amber)
            statusDot(dl, "Strobo", strobeActive, COL.blue)
            statusDot(dl, "Blink", blinkActive, COL.blue)
            imgui.TextDisabled("Audio server: dekat 0-50 m | jauh 51-120 m")

            imgui.End()
            imgui.PopStyleColor(3)
            imgui.PopStyleVar(5)
        end
    )
    frame.HideCursor = true

    return {
        toggle = function()
            menuOpen = not menuOpen
            frame.HideCursor = not menuOpen
        end,
        isOpen = function() return menuOpen end,
        reset = function()
            menuOpen = false
            frame.HideCursor = true
            sirenActive = false
            hazardActive = false
            strobeActive = false
            blinkActive = false
        end,
    }
end
