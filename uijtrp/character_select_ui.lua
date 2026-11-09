return function(imgui, V2, musicPath)
    local P = {
        bg = imgui.ImVec4(0.035, 0.035, 0.045, 0.97),
        panel = imgui.ImVec4(0.075, 0.065, 0.075, 0.98),
        card = imgui.ImVec4(0.095, 0.075, 0.085, 0.98),
        cardHover = imgui.ImVec4(0.19, 0.075, 0.09, 1),
        border = imgui.ImVec4(0.72, 0.10, 0.15, 0.72),
        red = imgui.ImVec4(0.88, 0.10, 0.16, 1),
        redHover = imgui.ImVec4(1, 0.18, 0.24, 1),
        text = imgui.ImVec4(0.96, 0.95, 0.96, 1),
        muted = imgui.ImVec4(0.66, 0.64, 0.67, 1),
        warning = imgui.ImVec4(1, 0.69, 0.28, 1),
    }

    local TABLIST_HEADERS = 5
    local dialogId, characters, createListItem, open = nil, {}, nil, false
    local openedAt = 0
    local selectionMusicWarned = false
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

    local function reset()
        dialogId, characters, createListItem, open = nil, {}, nil, false
        if frame then frame.HideCursor = true end
    end

    local function playSelectionMusic()
        if not musicPath or type(loadAudioStream) ~= "function"
            or type(setAudioStreamState) ~= "function" then
            if not selectionMusicWarned then
                selectionMusicWarned = true
                print("[PBRP/PKU UI] API audio tidak tersedia; lagu pemilihan karakter tidak dapat diputar.")
            end
            return
        end
        if type(doesFileExist) ~= "function" or not doesFileExist(musicPath) then
            if not selectionMusicWarned then
                selectionMusicWarned = true
                print("[PBRP/PKU UI] Lagu pemilihan karakter tidak ditemukan: " .. musicPath)
            end
            return
        end

        local loaded, stream = pcall(loadAudioStream, musicPath)
        if not loaded or not stream or stream == 0 then
            if not selectionMusicWarned then
                selectionMusicWarned = true
                print("[PBRP/PKU UI] Gagal memuat lagu pemilihan karakter: " .. tostring(stream))
            end
            return
        end

        local volumeOk, volumeError = pcall(setAudioStreamVolume, stream, 0.65)
        if not volumeOk and not selectionMusicWarned then
            selectionMusicWarned = true
            print("[PBRP/PKU UI] Gagal mengatur volume lagu karakter: " .. tostring(volumeError))
        end
        local playing, playError = pcall(setAudioStreamState, stream, 1)
        if not playing then
            pcall(setAudioStreamState, stream, 0)
            if type(releaseAudioStream) == "function" then pcall(releaseAudioStream, stream) end
            if not selectionMusicWarned then
                selectionMusicWarned = true
                print("[PBRP/PKU UI] Gagal memutar lagu pemilihan karakter: " .. tostring(playError))
            end
            return
        end

        if type(lua_thread) == "table" and type(lua_thread.create) == "function"
            and type(releaseAudioStream) == "function" then
            local scheduled, scheduleError = pcall(function()
                lua_thread.create(function()
                    wait(13000)
                    pcall(setAudioStreamState, stream, 0)
                    local released, releaseError = pcall(releaseAudioStream, stream)
                    if not released then
                        print("[PBRP/PKU UI] Gagal melepas lagu karakter: " .. tostring(releaseError))
                    end
                end)
            end)
            if not scheduled and not selectionMusicWarned then
                selectionMusicWarned = true
                print("[PBRP/PKU UI] Gagal menjadwalkan pembersihan lagu karakter: " .. tostring(scheduleError))
            end
        end
    end

    local function respond(button, item, playMusic)
        if not dialogId then return end
        if type(sampSendDialogResponse) ~= "function" then
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog karakter tidak tersedia.", 0xFFFF6A6A)
            return
        end

        local id = dialogId
        local ok, err = pcall(sampSendDialogResponse, id, button, item or -1, "")
        if not ok then
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim pilihan karakter: " .. tostring(err), 0xFFFF6A6A)
            return
        end
        if playMusic then playSelectionMusic() end
        reset()
    end

    local function onShowDialog(id, style, title, button1, button2, text)
        local cleanTitle = cleanText(title)
        if style ~= TABLIST_HEADERS
            or not cleanTitle:find("Pilih Karakter", 1, true)
            or not isSampAvailable()
            or type(sampSendDialogResponse) ~= "function" then
            return nil
        end

        local rows, createItem = {}, nil
        local firstLine = true
        for line in (tostring(text or "") .. "\n"):gmatch("(.-)\n") do
            if firstLine then
                firstLine = false
            elseif line:match("%S") then
                local slot, name = line:match("^(.-)\t(.-)%s*$")
                if slot and name then
                    slot, name = cleanText(slot), cleanText(name)
                    if slot:lower():find("buat karakter baru", 1, true) then
                        createItem = #rows
                    else
                        local banned = name:find("[BANNED]", 1, true) ~= nil
                        name = name:gsub("%s*%[BANNED%]%s*$", "")
                        rows[#rows + 1] = {
                            slot = slot,
                            name = cleanText(name),
                            banned = banned,
                            listItem = #rows,
                        }
                    end
                end
            end
        end
        if #rows == 0 and createItem == nil then return nil end

        dialogId, characters, createListItem, open = id, rows, createItem, true
        openedAt = os.clock()
        if frame then frame.HideCursor = false end
        return false
    end

    local function draw()
        local display = imgui.GetIO().DisplaySize
        local width = math.max(320, math.min(500, display.x - 32))
        local height = math.max(360, math.min(800, display.y - 32))

        local elapsed = math.max(0, os.clock() - openedAt)
        local progress = math.min(1, elapsed / 0.55)
        local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        local alpha = math.min(1, progress * 1.8)
        local slide = (1 - eased) * 32
        imgui.SetNextWindowPos(V2(display.x - width - 24 + slide, 24), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 16)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(22, 20))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(12, 12))
        imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
        imgui.PushStyleColor(imgui.Col.Border, P.border)
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.Button, P.card)
        imgui.PushStyleColor(imgui.Col.ButtonHovered, P.cardHover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.38, 0.055, 0.09, 1))
        imgui.PushStyleColor(imgui.Col.FrameBg, P.panel)
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        imgui.PushStyleColor(imgui.Col.TextDisabled, P.muted)

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
        imgui.Begin("##PBRP_character_select", nil, flags)

        local size = imgui.GetWindowSize()
        local pos = imgui.GetWindowPos()
        local drawList = imgui.GetWindowDrawList()
        local headerLeft = imgui.ImVec4(0.48, 0.035, 0.085, 1)
        local headerRight = imgui.ImVec4(0.13, 0.025, 0.04, 1)
        drawList:AddRectFilledMultiColor(pos, V2(pos.x + size.x, pos.y + 92),
            colorU32(headerLeft), colorU32(headerRight), colorU32(headerRight), colorU32(headerLeft))

        local pulse = 0.5 + 0.5 * math.sin(os.clock() * 2.2)
        drawList:AddRectFilled(V2(pos.x + 22, pos.y + 90), V2(pos.x + size.x - 22, pos.y + 92),
            colorU32(imgui.ImVec4(1, 0.15, 0.22, 0.42 + pulse * 0.38)))

        imgui.SetCursorPos(V2(24, 17))
        imgui.TextColored(P.text, "PEKANBARU ROLEPLAY")
        imgui.SetCursorPos(V2(24, 43))
        imgui.TextColored(imgui.ImVec4(1, 0.70, 0.72, 1), "PILIH KARAKTER")
        imgui.SetCursorPos(V2(size.x - 174, 36))
        imgui.TextColored(P.muted, string.format("%02d KARAKTER", #characters))

        imgui.SetCursorPos(V2(24, 111))
        imgui.Text("Pilih profil untuk melanjutkan ke kota")
        imgui.SetCursorPos(V2(24, 135))
        imgui.TextColored(P.muted, "Setiap karakter memiliki progres dan identitasnya sendiri.")

        local childHeight = math.max(130, size.y - 226)
        imgui.SetCursorPos(V2(20, 169))
        imgui.BeginChild("##PBRP_character_cards", V2(size.x - 40, childHeight), false,
            imgui.WindowFlags.NoBackground)

        local childPos = imgui.GetWindowPos()
        local available = imgui.GetContentRegionAvail()
        local spacing = 12
        local columns = available.x >= 570 and 2 or 1
        local cardWidth = (available.x - spacing * (columns - 1)) / columns
        local cardHeight, rowSpacing = 112, 12
        local totalCards = #characters + (createListItem ~= nil and 1 or 0)

        for index = 1, totalCards do
            local column = (index - 1) % columns
            local row = math.floor((index - 1) / columns)
            local x, y = column * (cardWidth + spacing), row * (cardHeight + rowSpacing)
            local character = characters[index]
            local createCard = not character and createListItem ~= nil
            local enter = math.max(0, math.min(1, (elapsed - (index - 1) * 0.07) / 0.28))
            local cardAlpha = 1 - (1 - enter) * (1 - enter)

            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha * cardAlpha)
            imgui.SetCursorPos(V2(x, y))
            local label = character and ("##PBRP_character_" .. index)
                or (createCard and "##PBRP_create_character" or "##PBRP_character_empty")
            local clicked = imgui.Button(label, V2(cardWidth, cardHeight))
            local cardPos = V2(childPos.x + x, childPos.y + y)
            local cardEnd = V2(childPos.x + x + cardWidth, childPos.y + y + cardHeight)
            local accent = character and (character.banned and P.warning or P.red)
                or imgui.ImVec4(0.78, 0.25, 0.30, 1)

            drawList = imgui.GetWindowDrawList()
            drawList:AddRect(cardPos, cardEnd, colorU32(imgui.ImVec4(accent.x, accent.y, accent.z, 0.48 * cardAlpha)), 10, 0, 1)
            drawList:AddRectFilled(V2(cardPos.x + 15, cardPos.y + 18),
                V2(cardPos.x + 65, cardPos.y + 68), colorU32(imgui.ImVec4(accent.x, accent.y, accent.z, 0.18 * cardAlpha)), 25)
            drawList:AddCircle(V2(cardPos.x + 40, cardPos.y + 35), 11,
                colorU32(imgui.ImVec4(accent.x, accent.y, accent.z, 0.9 * cardAlpha)), 20, 2)
            drawList:AddLine(V2(cardPos.x + 32, cardPos.y + 57), V2(cardPos.x + 48, cardPos.y + 57),
                colorU32(imgui.ImVec4(accent.x, accent.y, accent.z, 0.9 * cardAlpha)), 2)

            if character then
                drawList:AddText(V2(cardPos.x + 78, cardPos.y + 18),
                    colorU32(imgui.ImVec4(0.72, 0.70, 0.73, cardAlpha)), character.slot:upper())
                drawList:AddText(V2(cardPos.x + 78, cardPos.y + 42),
                    colorU32(imgui.ImVec4(0.97, 0.95, 0.96, cardAlpha)), character.name)
                drawList:AddText(V2(cardPos.x + 78, cardPos.y + 77),
                    colorU32(character.banned
                        and imgui.ImVec4(1, 0.69, 0.28, cardAlpha)
                        or imgui.ImVec4(0.64, 0.62, 0.65, cardAlpha)),
                    character.banned and "AKUN DIBLOKIR" or "KLIK UNTUK MEMILIH")
                if clicked then respond(1, character.listItem, true) end
            elseif createCard then
                drawList:AddText(V2(cardPos.x + 78, cardPos.y + 27),
                    colorU32(imgui.ImVec4(0.97, 0.95, 0.96, cardAlpha)), "BUAT KARAKTER BARU")
                drawList:AddText(V2(cardPos.x + 78, cardPos.y + 57),
                    colorU32(imgui.ImVec4(0.72, 0.68, 0.71, cardAlpha)), "Mulai perjalanan roleplay")
                if clicked then respond(1, createListItem) end
            end
            imgui.PopStyleVar()
        end

        imgui.EndChild()
        imgui.SetCursorPos(V2(size.x - 142, size.y - 50))
        if imgui.Button("KELUAR##PBRP_character_exit", V2(120, 34)) then
            respond(0, -1)
        end
        imgui.SetCursorPos(V2(24, size.y - 43))
        imgui.TextColored(P.muted, "Pilih salah satu kartu karakter")
        imgui.End()

        imgui.PopStyleColor(9)
        imgui.PopStyleVar(7)
    end

    frame = imgui.OnFrame(
        function() return open and isSampAvailable() end,
        draw)
    frame.LockPlayer = false
    frame.HideCursor = true

    return {
        onShowDialog = onShowDialog,
        isOpen = function() return open end,
        reset = reset,
    }
end
