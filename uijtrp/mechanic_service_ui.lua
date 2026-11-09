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
        green = imgui.ImVec4(0.20, 0.78, 0.47, 1.0),
        gold = imgui.ImVec4(0.96, 0.72, 0.31, 1.0),
    }

    local dialogId, items, open = nil, {}, false
    local frame

    local function colorU32(value)
        return imgui.ColorConvertFloat4ToU32(value)
    end

    local function cleanText(value)
        return tostring(value or "")
            :gsub("{%x%x%x%x%x%x}", "")
            :gsub("~[%w]~", "")
            :gsub("\r", "")
            :gsub("^%s+", "")
            :gsub("%s+$", "")
    end

    local function pushId(id)
        if type(id) == "number" then
            if imgui.PushIDInt then
                imgui.PushIDInt(id)
                return
            end
        elseif type(id) == "string" then
            if imgui.PushIDStr then
                imgui.PushIDStr(id)
                return
            end
        end

        if imgui.PushID then
            imgui.PushID(tostring(id))
        end
    end

    local function reset()
        dialogId, items, open = nil, {}, false
        if frame then frame.HideCursor = true end
    end

    local function respond(button, item)
        if not dialogId then return end
        local id = dialogId
        reset()
        if type(sampSendDialogResponse) ~= "function" then
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog tidak tersedia; service workshop tidak bisa dipilih.", 0xFFFF6A6A)
            return
        end
        local ok, err = pcall(sampSendDialogResponse, id, button, item or 0, "")
        if not ok then
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim pilihan service: " .. tostring(err), 0xFFFF6A6A)
        end
    end

    local function onShowDialog(id, style, title, button1, button2, text)
        local cleanTitle = cleanText(title)
        if not cleanTitle:find("Workshop > Service", 1, true) then
            return nil
        end

        local parsed = {}
        for line in tostring(text or ""):gmatch("[^\n]+") do
            local label, requirement = line:match("^(.-)\t(.-)$")
            label, requirement = cleanText(label), cleanText(requirement)
            if label ~= "" and label:lower() ~= "service name" then
                parsed[#parsed + 1] = {
                    name = label,
                    requirement = requirement,
                }
            end
        end
        if #parsed == 0 then return nil end

        dialogId = id
        items = parsed
        open = true
        if frame then frame.HideCursor = false end
        return false
    end

    local function draw()
        local display = imgui.GetIO().DisplaySize
        local width = math.min(880, display.x - 36)
        local height = math.min(760, display.y - 36)
        if width < 400 or height < 360 then
            width, height = math.max(320, display.x - 16), math.max(300, display.y - 16)
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
        imgui.Begin("##PBRP_mechanic_service", nil, flags)

        local dl = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local redLeft = imgui.ImVec4(0.83, 0.08, 0.14, 1)
        local redRight = imgui.ImVec4(0.39, 0.035, 0.07, 1)
        dl:AddRectFilledMultiColor(pos, V2(pos.x + size.x, pos.y + 72),
            colorU32(redLeft), colorU32(redRight), colorU32(redRight), colorU32(redLeft))
        dl:AddLine(V2(pos.x, pos.y + 72), V2(pos.x + size.x, pos.y + 72), colorU32(P.border), 1)

        imgui.SetCursorPos(V2(22, 13))
        imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), "PEKANBARU  /  WORKSHOP")
        imgui.SetCursorPos(V2(22, 39))
        imgui.TextColored(imgui.ImVec4(1, 0.82, 0.83, 1), "MECHANIC SERVICE")
        imgui.SetCursorPos(V2(size.x - 52, 18))
        if imgui.Button("X##mechanic_service_close", V2(32, 32)) then respond(0, 0) end

        imgui.SetCursorPos(V2(22, 88))
        imgui.TextColored(P.muted, "PILIH LAYANAN")
        imgui.SameLine()
        imgui.SetCursorPosX(size.x - 132)
        imgui.TextColored(P.muted, string.format("%02d SERVICE", #items))
        imgui.SetCursorPos(V2(18, 116))
        imgui.BeginChild("##PBRP_mechanic_service_cards", V2(size.x - 36, size.y - 174), false,
            imgui.WindowFlags.NoBackground)

        local cardDrawList = imgui.GetWindowDrawList()
        local spacing, cardHeight = 12, 76
        local available = imgui.GetContentRegionAvail().x
        local columns = available >= 660 and 3 or 2
        local cardWidth = (available - spacing * (columns - 1)) / columns
        for index, item in ipairs(items) do
            if (index - 1) % columns ~= 0 then imgui.SameLine(0, spacing) end
            pushId(index)
            imgui.PushStyleColor(imgui.Col.Button, P.card)
            imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
            imgui.PushStyleColor(imgui.Col.ButtonActive, P.red)
            imgui.PushStyleColor(imgui.Col.Border, P.border)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
            local clicked = imgui.Button("##service_card", V2(cardWidth, cardHeight))
            local cardPos = imgui.GetItemRectMin()
            local cardMax = imgui.GetItemRectMax()
            local hovered = imgui.IsItemHovered()
            local accent = hovered and P.redHover or P.red
            cardDrawList:AddRectFilled(V2(cardPos.x + 1, cardPos.y + 9),
                V2(cardPos.x + 4, cardMax.y - 9), colorU32(accent), 2)
            cardDrawList:AddText(V2(cardPos.x + 14, cardPos.y + 13), colorU32(P.text), item.name)
            cardDrawList:AddText(V2(cardPos.x + 14, cardPos.y + 40), colorU32(P.gold),
                item.requirement ~= "" and item.requirement or "Layanan mekanik")
            imgui.PopStyleVar()
            imgui.PopStyleColor(4)
            if imgui.PopID then imgui.PopID() end
            if clicked then
                respond(1, index - 1)
                break
            end
        end
        imgui.EndChild()

        imgui.SetCursorPos(V2(18, size.y - 48))
        imgui.TextDisabled("Pilih kartu untuk memulai layanan kendaraan.")
        imgui.SameLine()
        imgui.SetCursorPosX(size.x - 137)
        if imgui.Button("BATAL##mechanic_service_cancel", V2(119, 32)) then respond(0, 0) end
        imgui.End()

        imgui.PopStyleColor(4)
        imgui.PopStyleVar(5)
    end

    frame = imgui.OnFrame(
        function() return open and isSampAvailable() and isPlayerUiReady() end,
        draw)
    frame.LockPlayer = false
    frame.HideCursor = true

    return {
        onShowDialog = onShowDialog,
        isOpen = function() return open end,
        close = function() respond(0, 0) end,
        reset = reset,
    }
end
