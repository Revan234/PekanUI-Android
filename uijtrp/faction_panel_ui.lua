return function(imgui, V2, isPlayerUiReady)
    local P = {
        bg = imgui.ImVec4(0.047, 0.047, 0.059, 0.98),
        panel = imgui.ImVec4(0.075, 0.075, 0.094, 1.0),
        card = imgui.ImVec4(0.102, 0.102, 0.125, 1.0),
        cardHover = imgui.ImVec4(0.149, 0.149, 0.184, 1.0),
        border = imgui.ImVec4(0.18, 0.18, 0.22, 0.85),
        red = imgui.ImVec4(0.88, 0.11, 0.18, 1.0),
        redHover = imgui.ImVec4(0.96, 0.17, 0.24, 1.0),
        text = imgui.ImVec4(0.92, 0.92, 0.94, 1.0),
        muted = imgui.ImVec4(0.54, 0.54, 0.59, 1.0),
    }

    local dialogId, dialogTitle, items = nil, "", {}
    local open = false
    local frame

    local function colorU32(color)
        return imgui.ColorConvertFloat4ToU32(color)
    end

    local function cleanText(value)
        return tostring(value or "")
            :gsub("{%x%x%x%x%x%x}", "")
            :gsub("~[%w]~", "")
            :gsub("\r", "")
            :gsub("^%s+", "")
            :gsub("%s+$", "")
    end

    local function reset()
        dialogId, dialogTitle, items, open = nil, "", {}, false
        if frame then frame.HideCursor = true end
    end

    local function respond(button, item)
        if not dialogId then return end
        local id = dialogId
        reset()
        if type(sampSendDialogResponse) ~= "function" then
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog tidak tersedia; faction menu tidak bisa dipilih.", 0xFFFF6A6A)
            return
        end
        local ok, err = pcall(sampSendDialogResponse, id, button, item or 0, "")
        if not ok then
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim pilihan faction: " .. tostring(err), 0xFFFF6A6A)
        end
    end

    local function factionTitle(title)
        local name = title:match("%((.-)%)")
        if name then return cleanText(name):upper() end
        return "MENU FRACTION"
    end

    local function onShowDialog(id, style, title, button1, button2, text)
        if style ~= 2 then return nil end
        local cleanTitle = cleanText(title)
        if not cleanTitle:find("Faction Panel", 1, true)
            and not cleanTitle:find("Faction Menu", 1, true) then
            return nil
        end

        dialogId = id
        dialogTitle = cleanTitle
        items = {}
        for line in tostring(text or ""):gmatch("[^\n]+") do
            local label = cleanText(line)
            if label ~= "" then items[#items + 1] = label end
        end
        if #items == 0 then
            dialogId = nil
            dialogTitle = ""
            items = {}
            return nil
        end
        open = true
        if frame then frame.HideCursor = not open end
        return false
    end

    local function draw()
        local display = imgui.GetIO().DisplaySize
        local width = math.min(660, display.x - 32)
        local height = math.min(590, display.y - 32)
        if width < 360 or height < 300 then
            width, height = math.max(300, display.x - 16), math.max(260, display.y - 16)
        end

        imgui.SetNextWindowPos(V2((display.x - width) / 2, (display.y - height) / 2), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)

        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 9)
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(10, 10))
        imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
        imgui.PushStyleColor(imgui.Col.Border, P.border)
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        imgui.PushStyleColor(imgui.Col.TextDisabled, P.muted)

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
        imgui.Begin("##PBRP_faction_panel", nil, flags)

        local dl = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local redLeft = imgui.ImVec4(0.83, 0.08, 0.14, 1)
        local redRight = imgui.ImVec4(0.39, 0.035, 0.07, 1)
        dl:AddRectFilledMultiColor(pos, V2(pos.x + size.x, pos.y + 64),
            colorU32(redLeft), colorU32(redRight), colorU32(redRight), colorU32(redLeft))
        dl:AddLine(V2(pos.x, pos.y + 64), V2(pos.x + size.x, pos.y + 64), colorU32(P.border), 1)

        imgui.SetCursorPos(V2(20, 12))
        imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), "PEKANBARU")
        imgui.SetCursorPos(V2(20, 34))
        imgui.TextColored(imgui.ImVec4(1, 0.78, 0.79, 1), factionTitle(dialogTitle))
        imgui.SetCursorPos(V2(size.x - 54, 16))
        if imgui.Button("X", V2(34, 30)) then respond(0, 0) end

        imgui.SetCursorPos(V2(18, 78))
        imgui.TextColored(P.muted, "PILIH AKSI")
        imgui.SameLine()
        imgui.SetCursorPosX(size.x - 126)
        imgui.TextColored(P.muted, string.format("%02d MENU", #items))
        imgui.SetCursorPos(V2(16, 104))
        imgui.BeginChild("##PBRP_faction_cards", V2(size.x - 32, size.y - 122), false,
            imgui.WindowFlags.NoBackground)

        local spacing = 12
        local cardWidth = (imgui.GetContentRegionAvail().x - spacing) / 2
        for index, label in ipairs(items) do
            if index % 2 == 0 then imgui.SameLine(0, spacing) end
            if imgui.PushIDInt then
                imgui.PushIDInt(index)
            elseif imgui.PushIDStr then
                imgui.PushIDStr(tostring(index))
            elseif imgui.PushID then
                imgui.PushID(tostring(index))
            end
            imgui.PushStyleColor(imgui.Col.Button, P.card)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
            imgui.PushStyleColor(imgui.Col.ButtonActive, P.red)
            imgui.PushStyleColor(imgui.Col.Border, P.border)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
            if imgui.Button(string.format("%02d   %s", index, label), V2(cardWidth, 54)) then
                respond(1, index - 1)
            end
            imgui.PopStyleVar()
            imgui.PopStyleColor(4)
            if imgui.PopID then imgui.PopID() end
        end
        imgui.EndChild()
        imgui.End()

        imgui.PopStyleColor(4)
        imgui.PopStyleVar(5)
    end

    frame = imgui.OnFrame(
        function() return open and isSampAvailable() and isPlayerUiReady() end,
        draw)
    frame.LockPlayer = true
    frame.HideCursor = true

    return {
        onShowDialog = onShowDialog,
        isOpen = function() return open end,
        close = function() respond(0, 0) end,
        reset = reset,
    }
end
