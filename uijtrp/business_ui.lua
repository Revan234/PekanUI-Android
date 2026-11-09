return function(imgui, V2, isPlayerUiReady, logoPath)
    local P = {
        bg = imgui.ImVec4(0.047, 0.047, 0.059, 0.98),
        card = imgui.ImVec4(0.102, 0.102, 0.125, 1.0),
        cardHover = imgui.ImVec4(0.149, 0.149, 0.184, 1.0),
        border = imgui.ImVec4(0.18, 0.18, 0.22, 0.85),
        red = imgui.ImVec4(0.88, 0.11, 0.18, 1.0),
        redHover = imgui.ImVec4(0.96, 0.17, 0.24, 1.0),
        text = imgui.ImVec4(0.92, 0.92, 0.94, 1.0),
        muted = imgui.ImVec4(0.54, 0.54, 0.59, 1.0),
        gold = imgui.ImVec4(0.96, 0.72, 0.31, 1.0),
    }

    local dialogId, dialogTitle, items, open = nil, "", {}, false
    local animationStarted, visualAlpha = 0, 1
    local frame, logoTexture

    imgui.OnInitialize(function()
        if not logoPath or not doesFileExist(logoPath) then
            print("[PBRP/PKU UI] Logo menu bisnis tidak ditemukan: " .. tostring(logoPath))
            return
        end
        local ok, texture = pcall(imgui.CreateTextureFromFile, logoPath)
        if ok and texture then
            logoTexture = texture
        else
            print("[PBRP/PKU UI] Gagal memuat logo menu bisnis: " .. tostring(texture))
        end
    end)

    local function clamp(value, minimum, maximum)
        return math.max(minimum, math.min(maximum, value))
    end

    local function ease(value)
        return 1 - (1 - value) ^ 3
    end

    local function colorU32(value, alpha)
        return imgui.ColorConvertFloat4ToU32(imgui.ImVec4(
            value.x, value.y, value.z, value.w * visualAlpha * (alpha or 1)))
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
        animationStarted = 0
        if frame then frame.HideCursor = true end
    end

    local function respond(button, item)
        if not dialogId then return end
        local id = dialogId
        reset()
        if type(sampSendDialogResponse) ~= "function" then
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog tidak tersedia; menu bisnis tidak bisa dipilih.", 0xFFFF6A6A)
            return
        end
        local ok, err = pcall(sampSendDialogResponse, id, button, item or 0, "")
        if not ok then
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim pilihan bisnis: " .. tostring(err), 0xFFFF6A6A)
        end
    end

    local function splitColumns(line)
        local columns = {}
        for column in (line .. "\t"):gmatch("(.-)\t") do
            columns[#columns + 1] = cleanText(column)
        end
        return columns
    end

    local function parseRows(text, tabular)
        local parsed = {}
        local isHeader = tabular
        for line in tostring(text or ""):gmatch("[^\n]+") do
            local columns
            if tabular then
                columns = splitColumns(line)
            else
                columns = { cleanText(line) }
            end

            local hasContent = false
            for _, column in ipairs(columns) do
                if column ~= "" then
                    hasContent = true
                    break
                end
            end

            if hasContent then
                if isHeader then
                    isHeader = false
                else
                    parsed[#parsed + 1] = columns
                end
            end
        end
        return parsed
    end

    local function isBusinessDialog(style, title, text)
        local cleanTitle = cleanText(title)
        if style == 2 and (cleanTitle == "Bisnis Menu" or cleanTitle:match("^Bisnis Menu %-")) then
            return true, cleanTitle, false
        end

        if style ~= 5 then return false end
        local firstLine = tostring(text or ""):match("([^\n]+)") or ""
        local header = splitColumns(firstLine)
        if cleanTitle == "Pilih Bisnis"
            and header[1] == "ID" and header[2] == "Nama Bisnis" then
            return true, cleanTitle, true
        end
        if cleanTitle == "Set Product Price"
            and header[1] == "Nama Item" and header[2] == "Harga" then
            return true, cleanTitle, true
        end

        local businessTypes = {
            "Market", "Electronic Store", "Ammunation", "Pom Bensin",
            "Fast Food", "Clothes Store", "Bar",
        }
        local isShop = false
        for _, businessType in ipairs(businessTypes) do
            if cleanTitle:match("^" .. businessType .. "%s+%-") then
                isShop = true
                break
            end
        end
        if isShop and header[1] == "Nama Item"
            and (header[2] == "Harga" or header[2] == "Ammo") then
            return true, cleanTitle, true
        end
        return false
    end

    local function onShowDialog(id, style, title, button1, button2, text)
        if not isPlayerUiReady() or type(sampSendDialogResponse) ~= "function" then
            return nil
        end

        local matches, cleanTitle, tabular = isBusinessDialog(style, title, text)
        if not matches then return nil end

        local parsed = parseRows(text, tabular)
        if #parsed == 0 then return nil end

        dialogId = id
        dialogTitle = cleanTitle
        items = parsed
        animationStarted = os.clock()
        open = true
        if frame then frame.HideCursor = false end
        return false
    end

    local function draw()
        local io = imgui.GetIO()
        local display = io.DisplaySize
        local width = math.min(820, display.x - 32)
        local height = math.min(680, display.y - 32)
        if width < 340 or height < 300 then
            width, height = math.max(300, display.x - 16), math.max(260, display.y - 16)
        end

        local progress = clamp((os.clock() - animationStarted) / 0.32, 0, 1)
        visualAlpha = ease(progress)
        imgui.SetNextWindowPos(V2((display.x - width) / 2,
            (display.y - height) / 2 + (1 - visualAlpha) * 24), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 14)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 9)
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(10, 10))
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, visualAlpha)
        imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
        imgui.PushStyleColor(imgui.Col.Border, P.border)
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        imgui.PushStyleColor(imgui.Col.TextDisabled, P.muted)

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
        imgui.Begin("##PBRP_business", nil, flags)

        local dl = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local size = imgui.GetWindowSize()
        local redLeft = imgui.ImVec4(0.83, 0.08, 0.14, 1)
        local redRight = imgui.ImVec4(0.39, 0.035, 0.07, 1)
        dl:AddRectFilledMultiColor(pos, V2(pos.x + size.x, pos.y + 70),
            colorU32(redLeft), colorU32(redRight), colorU32(redRight), colorU32(redLeft))
        dl:AddLine(V2(pos.x, pos.y + 70), V2(pos.x + size.x, pos.y + 70), colorU32(P.border), 1)

        if logoTexture then
            dl:AddImage(logoTexture, V2(pos.x + 14, pos.y + 10), V2(pos.x + 58, pos.y + 58))
        end
        imgui.SetCursorPos(V2(logoTexture and 68 or 20, 12))
        imgui.TextColored(imgui.ImVec4(1, 1, 1, 1), "PEKANBARU  /  BUSINESS")
        imgui.SetCursorPos(V2(logoTexture and 68 or 20, 37))
        imgui.TextColored(imgui.ImVec4(1, 0.82, 0.83, 1), dialogTitle)
        imgui.SetCursorPos(V2(size.x - 52, 18))
        if imgui.Button("X##business_close", V2(32, 32)) then respond(0, 0) end

        imgui.SetCursorPos(V2(18, 84))
        imgui.TextColored(P.muted, "PILIH ITEM ATAU MENU")
        imgui.SameLine()
        imgui.SetCursorPosX(size.x - 130)
        imgui.TextColored(P.muted, string.format("%02d PILIHAN", #items))
        imgui.SetCursorPos(V2(16, 110))
        imgui.BeginChild("##PBRP_business_items", V2(size.x - 32, size.y - 170), false,
            imgui.WindowFlags.NoBackground)

        local cardDrawList = imgui.GetWindowDrawList()
        for index, columns in ipairs(items) do
            local name = columns[1] ~= "" and columns[1] or "Pilihan"
            local rowAlpha = ease(clamp((os.clock() - animationStarted - (index - 1) * 0.035) / 0.24, 0, 1))
            local details = {}
            for columnIndex = 2, #columns do
                if columns[columnIndex] ~= "" then
                    details[#details + 1] = columns[columnIndex]
                end
            end
            local cardHeight = #details > 0 and 66 or 54

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
            local clicked = imgui.Button("##business_item", V2(-1, cardHeight))
            local cardPos = imgui.GetItemRectMin()
            local cardMax = imgui.GetItemRectMax()
            local hovered = imgui.IsItemHovered()
            local accent = hovered and P.redHover or P.red
            cardDrawList:AddRectFilled(V2(cardPos.x + 1, cardPos.y + 8),
                V2(cardPos.x + 4, cardMax.y - 8), colorU32(accent, rowAlpha), 2)
            cardDrawList:AddText(V2(cardPos.x + 14, cardPos.y + 10), colorU32(P.text, rowAlpha), name)
            if #details > 0 then
                cardDrawList:AddText(V2(cardPos.x + 14, cardPos.y + 36),
                    colorU32(P.gold, rowAlpha), table.concat(details, "  |  "))
            end
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
        imgui.TextDisabled("Pilih kartu untuk melanjutkan.")
        imgui.SameLine()
        imgui.SetCursorPosX(size.x - 137)
        if imgui.Button("BATAL##business_cancel", V2(119, 32)) then respond(0, 0) end
        imgui.End()

        imgui.PopStyleColor(4)
        imgui.PopStyleVar(6)
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
