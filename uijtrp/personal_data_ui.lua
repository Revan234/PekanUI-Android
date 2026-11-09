return function(imgui, V2, ffi)
    local P = {
        bg = imgui.ImVec4(0.035, 0.035, 0.045, 0.98),
        panel = imgui.ImVec4(0.075, 0.065, 0.075, 1),
        card = imgui.ImVec4(0.105, 0.085, 0.095, 1),
        cardHover = imgui.ImVec4(0.20, 0.075, 0.09, 1),
        border = imgui.ImVec4(0.72, 0.10, 0.15, 0.72),
        red = imgui.ImVec4(0.88, 0.10, 0.16, 1),
        redHover = imgui.ImVec4(1, 0.18, 0.24, 1),
        text = imgui.ImVec4(0.96, 0.95, 0.96, 1),
        muted = imgui.ImVec4(0.66, 0.64, 0.67, 1),
    }

    local open, dialog, frame = false, nil, nil
    local input = imgui.new.char[129]()
    local itemLabels = {
        ["Name"] = "Nama karakter",
        ["Date Of Birthday"] = "Tanggal lahir",
        ["Gender"] = "Jenis kelamin",
        ["Height"] = "Tinggi badan",
        ["Weight"] = "Berat badan",
        ["Origin"] = "Negara kelahiran",
        ["+ Create Characters"] = "Selesaikan pembuatan karakter",
    }

    local function trim(value)
        return tostring(value or ""):match("^%s*(.-)%s*$")
    end

    local function cleanText(value)
        return tostring(value or "")
            :gsub("{%x%x%x%x%x%x}", "")
            :gsub("~[%w]~", "")
            :gsub("\r", "")
    end

    local function reset()
        open, dialog = false, nil
        ffi.fill(input, ffi.sizeof(input), 0)
        if frame then frame.HideCursor = true end
    end

    local function respond(button, item, value)
        if not dialog then return end
        if type(sampSendDialogResponse) ~= "function" then
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog data diri tidak tersedia.", 0xFFFF6A6A)
            return
        end

        local id = dialog.id
        local ok, err = pcall(sampSendDialogResponse, id, button, item or -1, value or "")
        if not ok then
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim respons dialog data diri: " .. tostring(err), 0xFFFF6A6A)
            return
        end
        reset()
    end

    local function openDialog(id, kind, title, button1, button2, body)
        dialog = {
            id = id,
            kind = kind,
            title = cleanText(title),
            button1 = cleanText(button1),
            button2 = cleanText(button2),
            body = cleanText(body),
            items = {},
        }

        if kind == "menu" then
            local firstLine, itemIndex = true, 0
            for line in (dialog.body .. "\n"):gmatch("(.-)\n") do
                if firstLine then
                    firstLine = false
                elseif line:match("%S") then
                    local label, value = line:match("^(.-)\t(.-)%s*$")
                    label = trim(cleanText(label or line))
                    value = trim(cleanText(value or ""))
                    dialog.items[#dialog.items + 1] = {
                        item = itemIndex,
                        label = itemLabels[label:gsub(":$", "")] or itemLabels[label] or label:gsub(":$", ""),
                        value = value,
                        action = label:find("Create Characters", 1, true) ~= nil,
                    }
                    itemIndex = itemIndex + 1
                end
            end
        elseif kind == "select" then
            for line in (dialog.body .. "\n"):gmatch("(.-)\n") do
                line = trim(cleanText(line))
                if line ~= "" then
                    dialog.items[#dialog.items + 1] = line
                end
            end
        end

        ffi.fill(input, ffi.sizeof(input), 0)
        open = true
        if frame then frame.HideCursor = false end
    end

    local function onShowDialog(id, style, title, button1, button2, body)
        if not isSampAvailable() or type(sampSendDialogResponse) ~= "function" then
            return nil
        end

        local cleanTitle = cleanText(title)
        if style == 5 and cleanTitle:find("Create Characters", 1, true) then
            openDialog(id, "menu", title, button1, button2, body)
        elseif style == 1 and cleanTitle:find("Pembuatan Karakter", 1, true) then
            openDialog(id, "name", title, button1, button2, body)
        elseif style == 1 and cleanTitle:find("Tanggal Lahir", 1, true) then
            openDialog(id, "birthday", title, button1, button2, body)
        elseif style == 1 and cleanTitle:find("Tinggi Badan", 1, true) then
            openDialog(id, "height", title, button1, button2, body)
        elseif style == 1 and cleanTitle:find("Berat Badan", 1, true) then
            openDialog(id, "weight", title, button1, button2, body)
        elseif style == 2 and cleanTitle:find("Jenis Kelamin", 1, true) then
            openDialog(id, "gender", title, button1, button2, body)
        elseif style == 2 and cleanTitle:find("Negara Kelahiran", 1, true) then
            openDialog(id, "origin", title, button1, button2, body)
        else
            return nil
        end

        return false
    end

    local function draw()
        if not dialog then return end
        local display = imgui.GetIO().DisplaySize
        local width = math.max(300, math.min(450, display.x - 32))
        local height = math.max(320, math.min(760, display.y - 32))

        imgui.SetNextWindowPos(V2(display.x - width - 24, 24), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 1)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(10, 10))
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(12, 9))
        imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
        imgui.PushStyleColor(imgui.Col.Border, P.border)
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        imgui.PushStyleColor(imgui.Col.TextDisabled, P.muted)
        imgui.PushStyleColor(imgui.Col.FrameBg, P.panel)
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, P.cardHover)
        imgui.PushStyleColor(imgui.Col.FrameBgActive, P.cardHover)
        imgui.PushStyleColor(imgui.Col.Button, P.card)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, P.red)

        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
        if imgui.Begin("##PBRP_personal_data", nil, flags) then
            local pos = imgui.GetWindowPos()
            local size = imgui.GetWindowSize()
            local drawList = imgui.GetWindowDrawList()
            local left = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.50, 0.035, 0.085, 1))
            local right = imgui.ColorConvertFloat4ToU32(imgui.ImVec4(0.15, 0.025, 0.04, 1))
            drawList:AddRectFilledMultiColor(pos, V2(pos.x + size.x, pos.y + 64),
                left, right, right, left)
            drawList:AddRectFilled(V2(pos.x + 22, pos.y + 62),
                V2(pos.x + size.x - 22, pos.y + 64),
                imgui.ColorConvertFloat4ToU32(P.border))

            local isSelect = dialog.kind == "gender" or dialog.kind == "origin"
            local heading = dialog.kind == "menu" and "DATA DIRI"
                or dialog.kind == "gender" and "PILIH JENIS KELAMIN"
                or dialog.kind == "origin" and "PILIH NEGARA KELAHIRAN"
                or "LENGKAPI DATA DIRI"
            imgui.SetCursorPos(V2(22, 16))
            imgui.TextColored(imgui.ImVec4(1, 0.72, 0.75, 1), heading)
            imgui.SetCursorPos(V2(22, 40))
            imgui.TextColored(P.muted, "PEKANBARU ROLEPLAY  /  PEMBUATAN KARAKTER")

            if dialog.kind == "menu" then
                imgui.SetCursorPos(V2(22, 78))
                imgui.TextColored(P.muted, "Pilih bagian profil untuk diisi atau diperbarui.")
                local y = 110
                for _, row in ipairs(dialog.items) do
                    imgui.SetCursorPos(V2(22, y))
                    local label = row.label
                    if row.action then
                        imgui.PushStyleColor(imgui.Col.Button, P.red)
                        imgui.PushStyleColor(imgui.Col.ButtonHovered, P.redHover)
                    end
                    local buttonText = row.action and (">  " .. label)
                        or (label .. "    " .. (row.value ~= "" and row.value or "Belum diisi"))
                    if imgui.Button(buttonText .. ("##profile_%d"):format(row.item), V2(size.x - 44, 44)) then
                        respond(1, row.item, "")
                    end
                    if row.action then imgui.PopStyleColor(2) end
                    y = y + 52
                end
                imgui.SetCursorPos(V2(22, size.y - 54))
                imgui.TextColored(P.muted, "Isi semua data sebelum menyelesaikan pembuatan karakter.")
            elseif isSelect then
                imgui.SetCursorPos(V2(22, 78))
                imgui.TextColored(P.muted, "Pilih salah satu pilihan berikut.")
                imgui.SetCursorPos(V2(22, 106))
                imgui.BeginChild("##personal_data_options", V2(size.x - 44, size.y - 174), true)
                for index, option in ipairs(dialog.items) do
                    if imgui.Button(option .. ("##profile_option_%d"):format(index),
                        V2(size.x - 68, 42)) then
                        respond(1, index - 1, "")
                    end
                end
                imgui.EndChild()
                imgui.SetCursorPos(V2(22, size.y - 54))
                if imgui.Button("KEMBALI##personal_data_select_cancel", V2(150, 38)) then
                    respond(0, -1, "")
                end
            else
                local field = dialog.kind == "name" and "Nama karakter"
                    or dialog.kind == "birthday" and "Tanggal lahir"
                    or dialog.kind == "height" and "Tinggi badan (cm)"
                    or "Berat badan (kg)"
                imgui.SetCursorPos(V2(22, 82))
                imgui.TextColored(P.text, field)
                imgui.SetCursorPos(V2(22, 108))
                imgui.PushTextWrapPos(size.x - 22)
                imgui.TextWrapped(dialog.body)
                imgui.PopTextWrapPos()

                imgui.SetCursorPos(V2(22, size.y - 128))
                local hint = dialog.kind == "name" and "Contoh: Ucok_Siregar"
                    or dialog.kind == "birthday" and "DD/MM/YYYY"
                    or dialog.kind == "height" and "Masukkan tinggi dalam cm"
                    or "Masukkan berat dalam kg"
                imgui.PushItemWidth(size.x - 44)
                local inputFlags = imgui.InputTextFlags.EnterReturnsTrue
                if dialog.kind == "height" or dialog.kind == "weight" then
                    inputFlags = inputFlags + imgui.InputTextFlags.CharsDecimal
                end
                local enterPressed = imgui.InputTextWithHint("##personal_data_input", hint,
                    input, ffi.sizeof(input), inputFlags)
                imgui.PopItemWidth()

                imgui.SetCursorPos(V2(22, size.y - 72))
                if imgui.Button("KEMBALI##personal_data_input_cancel", V2(150, 40)) then
                    respond(0, -1, "")
                end
                imgui.SameLine(0, 12)
                local submit = imgui.Button("LANJUTKAN  >##personal_data_input_submit",
                    V2(size.x - 206, 40))
                if submit or enterPressed then
                    respond(1, -1, ffi.string(input))
                end
            end
            imgui.End()
        else
            imgui.End()
        end

        imgui.PopStyleColor(11)
        imgui.PopStyleVar(7)
    end

    frame = imgui.OnFrame(function() return open and isSampAvailable() end, draw)
    frame.LockPlayer = false
    frame.HideCursor = true

    return {
        onShowDialog = onShowDialog,
        isOpen = function() return open end,
        reset = reset,
    }
end
