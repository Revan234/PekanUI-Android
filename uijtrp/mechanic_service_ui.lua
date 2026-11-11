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
        local width = math.max(300, display.x - 24)
        local height = math.min(148, math.max(124, display.y * 0.34))
        local left = (display.x - width) / 2
        local top = display.y - height - 12

        imgui.SetNextWindowPos(V2(left, top), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 7)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(7, 7))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 4)
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(7, 0))
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.035, 0.035, 0.04, 0.92))
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
        local brandWidth = math.min(142, math.max(96, size.x * 0.25))
        local brandTop = pos.y + 7
        local brandBottom = pos.y + size.y - 7
        local brandColor = imgui.ImVec4(0.0, 0.58, 0.48, 1)
        dl:AddRectFilled(V2(pos.x + 7, brandTop), V2(pos.x + 7 + brandWidth, brandBottom),
            colorU32(brandColor), 5)
        dl:AddRectFilled(V2(pos.x + 7 + brandWidth - 4, brandTop),
            V2(pos.x + 7 + brandWidth, brandBottom), colorU32(imgui.ImVec4(0.12, 0.88, 0.72, 1)))

        imgui.SetCursorPos(V2(16, 20))
        imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), "PBRP")
        imgui.SetCursorPos(V2(16, 42))
        imgui.TextColored(imgui.ImVec4(0.82, 1, 0.96, 1), "MECHANIC")
        imgui.SetCursorPos(V2(16, 59))
        imgui.TextColored(imgui.ImVec4(0.82, 1, 0.96, 1), "WORKS")
        imgui.SetCursorPos(V2(16, size.y - 34))
        imgui.TextColored(imgui.ImVec4(0.82, 1, 0.96, 1), string.format("%02d SERVICES", #items))
        imgui.SetCursorPos(V2(16 + brandWidth - 38, size.y - 38))
        if imgui.Button("X##mechanic_service_close", V2(30, 28)) then respond(0, 0) end

        local cardsX = brandWidth + 18
        local cardsWidth = size.x - cardsX - 10
        local cardHeight = size.y - 14
        local cardWidth = math.min(132, math.max(94, display.x * 0.22))
        local itemSpacing = 7
        imgui.SetCursorPos(V2(cardsX, 7))
        imgui.BeginChild("##PBRP_mechanic_service_cards", V2(cardsWidth, cardHeight), false,
            imgui.WindowFlags.HorizontalScrollbar)

        local cardDrawList = imgui.GetWindowDrawList()
        for index, item in ipairs(items) do
            if index > 1 then imgui.SameLine(0, itemSpacing) end
            pushId(index)
            imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.055, 0.055, 0.065, 1))
            imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
            imgui.PushStyleColor(imgui.Col.ButtonActive, P.red)
            imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.14, 0.14, 0.16, 1))
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
            imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 3)
            local clicked = imgui.Button("##service_card", V2(cardWidth, cardHeight - 4))
            local cardPos = imgui.GetItemRectMin()
            local cardMax = imgui.GetItemRectMax()
            local hovered = imgui.IsItemHovered()
            local accent = hovered and imgui.ImVec4(0.12, 0.88, 0.72, 1) or brandColor
            local centerX = cardPos.x + cardWidth / 2
            cardDrawList:AddRectFilled(V2(cardPos.x + 1, cardPos.y + 1),
                V2(cardMax.x - 1, cardPos.y + 3), colorU32(accent), 1)
            cardDrawList:AddText(V2(cardMax.x - 43, cardPos.y + 7), colorU32(P.gold),
                item.requirement ~= "" and item.requirement or "SERVICE")
            cardDrawList:AddCircle(V2(centerX, cardPos.y + 37), 14, colorU32(P.muted), 8, 2)
            cardDrawList:AddCircle(V2(centerX, cardPos.y + 37), 5, colorU32(accent), 8, 2)
            cardDrawList:AddLine(V2(centerX - 10, cardPos.y + 27),
                V2(centerX - 15, cardPos.y + 22), colorU32(P.text), 3)
            cardDrawList:AddLine(V2(centerX + 10, cardPos.y + 27),
                V2(centerX + 15, cardPos.y + 22), colorU32(P.text), 3)
            cardDrawList:AddLine(V2(centerX - 10, cardPos.y + 47),
                V2(centerX - 15, cardPos.y + 52), colorU32(P.text), 3)
            cardDrawList:AddLine(V2(centerX + 10, cardPos.y + 47),
                V2(centerX + 15, cardPos.y + 52), colorU32(P.text), 3)
            cardDrawList:AddText(V2(cardPos.x + 8, cardMax.y - 27), colorU32(P.text),
                item.name:sub(1, 20))
            imgui.PopStyleVar(2)
            imgui.PopStyleColor(4)
            if imgui.PopID then imgui.PopID() end
            if clicked then
                respond(1, index - 1)
                break
            end
        end
        imgui.EndChild()
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
