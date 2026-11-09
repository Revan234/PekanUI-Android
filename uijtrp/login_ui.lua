return function(imgui, V2, ffi, soundPath, uiSounds, logoPath)
    local P = {
        bg = imgui.ImVec4(0.035, 0.035, 0.045, 0.97),
        border = imgui.ImVec4(0.72, 0.10, 0.15, 0.72),
        red = imgui.ImVec4(0.88, 0.10, 0.16, 1),
        redHover = imgui.ImVec4(1, 0.18, 0.24, 1),
        text = imgui.ImVec4(0.96, 0.95, 0.96, 1),
        muted = imgui.ImVec4(0.66, 0.64, 0.67, 1),
        error = imgui.ImVec4(1, 0.39, 0.42, 1),
    }

    local VERIFY_DIALOG_ID, LOGIN_DIALOG_ID, REGISTER_DIALOG_ID = 0, 2, 3
    local dialogId, dialogMode, accountName, loginError
    local password = imgui.new.char[129]()
    local open = false
    local openedAt = 0
    local feedbackStream
    local feedbackWarned = false
    local lastTypeSoundAt = 0
    local lastPasswordValue = ""
    local logoTexture
    local frame

    local function colorU32(value)
        return imgui.ColorConvertFloat4ToU32(value)
    end

    local function cleanText(value)
        return tostring(value or "")
            :gsub("{%x%x%x%x%x%x}", "")
            :gsub("~[%w]~", "")
            :gsub("\r", "")
    end

    imgui.OnInitialize(function()
        if not logoPath or type(doesFileExist) ~= "function" or not doesFileExist(logoPath) then
            print("[PBRP/PKU UI] Logo login tidak ditemukan: " .. tostring(logoPath))
            return
        end
        local ok, texture = pcall(imgui.CreateTextureFromFile, logoPath)
        if ok and texture then
            logoTexture = texture
        else
            print("[PBRP/PKU UI] Gagal memuat logo login: " .. tostring(texture))
        end
    end)

    local function playFeedback(kind)
        if type(loadAudioStream) == "function" and soundPath and soundPath ~= "" then
            if not feedbackStream and not feedbackWarned then
                local exists = type(doesFileExist) == "function" and doesFileExist(soundPath)
                if exists then
                    local ok, stream = pcall(loadAudioStream, soundPath)
                    if ok and stream and stream ~= 0 then
                        feedbackStream = stream
                    else
                        feedbackWarned = true
                        print("[PBRP/PKU UI] Gagal memuat suara login: " .. tostring(stream))
                    end
                else
                    feedbackWarned = true
                    print("[PBRP/PKU UI] File suara login tidak ditemukan: " .. soundPath)
                end
            end

            if feedbackStream then
                local ok, err = pcall(function()
                    setAudioStreamVolume(feedbackStream, 0.48)
                    setAudioStreamState(feedbackStream, 0)
                    setAudioStreamState(feedbackStream, 1)
                end)
                if ok then return end
                print("[PBRP/PKU UI] Gagal memutar suara login: " .. tostring(err))
                feedbackStream = nil
                feedbackWarned = true
            end
        end

        if uiSounds and type(uiSounds.play) == "function" then
            uiSounds.play(kind)
        end
    end

    local function reset()
        ffi.fill(password, ffi.sizeof(password), 0)
        lastPasswordValue = ""
        lastTypeSoundAt = 0
        dialogId, dialogMode, accountName, loginError, open = nil, nil, "", nil, false
        if frame then frame.HideCursor = true end
    end

    local function respond(button)
        if not dialogId then return end
        if button == 1 then playFeedback("click") end
        if button == 1 and ffi.string(password) == "" then
            loginError = dialogMode == "verify"
                and "Masukkan PIN verifikasi terlebih dahulu."
                or "Masukkan kata sandi terlebih dahulu."
            return
        end
        if type(sampSendDialogResponse) ~= "function" then
            loginError = "API dialog Lua tidak tersedia. Coba muat ulang dialog."
            sampAddChatMessage("[PBRP/PKU UI] API respons dialog akun tidak tersedia.", 0xFFFF6A6A)
            return
        end

        local id = dialogId
        local input = button == 1 and ffi.string(password) or ""
        local ok, err = pcall(sampSendDialogResponse, id, button, -1, input)
        if not ok then
            loginError = "Gagal mengirim respons. Silakan coba lagi."
            sampAddChatMessage("[PBRP/PKU UI] Gagal mengirim respons dialog akun: " .. tostring(err), 0xFFFF6A6A)
            return
        end
        reset()
    end

    local function onShowDialog(id, style, title, button1, button2, text)
        if not isSampAvailable() or type(sampSendDialogResponse) ~= "function" then
            return nil
        end

        if id == VERIFY_DIALOG_ID and style == 1 then
            dialogMode = "verify"
        elseif id == LOGIN_DIALOG_ID and style == 3 then
            dialogMode = "login"
        elseif id == REGISTER_DIALOG_ID and style == 3 then
            dialogMode = "register"
        else
            return nil
        end

        local contents = cleanText(text)
        accountName = contents:match("Nama UCP:%s*([^\n]+)") or ""
        accountName = accountName:match("^%s*(.-)%s*$")
        loginError = contents:match("[Ee][Rr][Rr][Oo][Rr]:%s*([^\n]+)")
        if loginError then loginError = loginError:match("^%s*(.-)%s*$") end
        dialogId = id
        open = true
        openedAt = os.clock()
        ffi.fill(password, ffi.sizeof(password), 0)
        lastPasswordValue = ""
        lastTypeSoundAt = 0
        if frame then frame.HideCursor = false end
        return false
    end

    local function draw()
        local display = imgui.GetIO().DisplaySize
        local width = math.max(280, math.min(420, display.x - 32))
        local height = math.max(320, math.min(620, display.y - 32))

        local elapsed = math.max(0, os.clock() - openedAt)
        local progress = math.min(1, elapsed / 0.48)
        local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
        local alpha = math.min(1, progress * 1.8)
        local slide = (1 - eased) * 28
        imgui.SetNextWindowPos(V2(display.x - width - 24 + slide, 24), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, alpha)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 16)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(24, 22))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 8)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
        imgui.PushStyleColor(imgui.Col.WindowBg, P.bg)
        imgui.PushStyleColor(imgui.Col.Border, P.border)
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.055, 0.045, 0.052, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.12, 0.045, 0.060, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgActive, imgui.ImVec4(0.17, 0.045, 0.065, 1))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.72, 0.10, 0.15, 0.62))
        imgui.PushStyleColor(imgui.Col.Text, P.text)
        imgui.PushStyleColor(imgui.Col.TextDisabled, P.muted)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.48, 0.055, 0.09, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, P.redHover)
        imgui.PushStyleColor(imgui.Col.ButtonActive, P.red)

        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoCollapse
        imgui.Begin("##PBRP_login", nil, flags)

        local size = imgui.GetWindowSize()
        local drawList = imgui.GetWindowDrawList()
        local pos = imgui.GetWindowPos()
        local time = os.clock()
        local pulse = 0.5 + 0.5 * math.sin(time * 2.4)
        local headerLeft = imgui.ImVec4(0.50, 0.035, 0.085, 1)
        local headerRight = imgui.ImVec4(0.15, 0.025, 0.04, 1)
        local headerBottom = pos.y + 88
        drawList:AddRectFilledMultiColor(pos, V2(pos.x + size.x, headerBottom),
            colorU32(headerLeft), colorU32(headerRight), colorU32(headerRight), colorU32(headerLeft))
        drawList:AddRectFilled(V2(pos.x + 24, pos.y + 86), V2(pos.x + size.x - 24, pos.y + 88),
            colorU32(imgui.ImVec4(1, 0.16, 0.22, 0.46 + pulse * 0.34)))

        if logoTexture then
            drawList:AddImage(logoTexture, V2(pos.x + size.x - 78, pos.y + 12),
                V2(pos.x + size.x - 22, pos.y + 68), V2(0, 0), V2(1, 1),
                colorU32(imgui.ImVec4(1, 1, 1, alpha)))
        else
            local badgeX, badgeY = pos.x + size.x - 58, pos.y + 44
            drawList:AddCircle(V2(badgeX, badgeY), 17 + pulse * 2, colorU32(imgui.ImVec4(1, 0.22, 0.28, 0.18)))
            drawList:AddCircle(V2(badgeX, badgeY), 12, colorU32(imgui.ImVec4(1, 0.26, 0.31, 0.72)), 32, 1.5)
            drawList:AddLine(V2(badgeX - 5, badgeY), V2(badgeX + 5, badgeY),
                colorU32(imgui.ImVec4(1, 0.78, 0.79, 0.95)), 2)
            drawList:AddLine(V2(badgeX, badgeY - 5), V2(badgeX, badgeY + 5),
                colorU32(imgui.ImVec4(1, 0.78, 0.79, 0.95)), 2)
        end

        local sweep = (time * 0.42) % 1
        local sweepX = pos.x + 20 + (size.x - 40) * sweep
        drawList:AddRectFilledMultiColor(V2(sweepX - 42, pos.y + 1), V2(sweepX + 42, pos.y + 3),
            colorU32(imgui.ImVec4(1, 0.24, 0.30, 0)), colorU32(imgui.ImVec4(1, 0.30, 0.34, 0.8)),
            colorU32(imgui.ImVec4(1, 0.30, 0.34, 0.8)), colorU32(imgui.ImVec4(1, 0.24, 0.30, 0)))

        local heroX = size.x - 210
        imgui.SetCursorPos(V2(heroX, 16))
        imgui.TextColored(imgui.ImVec4(1, 0.18, 0.23, 1), "PEKANBARU")
        imgui.SetCursorPos(V2(heroX, 56))
        imgui.TextColored(P.muted, "ROLEPLAY")

        local heading = dialogMode == "verify" and "VERIFIKASI UCP"
            or dialogMode == "register" and "BUAT PASSWORD"
            or "LOGIN SERVER"
        local welcome = dialogMode == "verify" and "Verifikasi akun Anda"
            or dialogMode == "register" and "Minimal 6 karakter; huruf, angka, _ [ ] ( )."
            or "Selamat datang kembali"
        local fieldLabel = dialogMode == "verify" and "PIN verifikasi"
            or "Kata sandi"
        local fieldHint = dialogMode == "verify" and "Masukkan PIN dari Discord"
            or dialogMode == "register" and "Buat kata sandi baru"
            or "Masukkan kata sandi"
        local submitLabel = dialogMode == "verify" and "VERIFIKASI  >##PBRP_login"
            or dialogMode == "register" and "BUAT PASSWORD  >##PBRP_login"
            or "MASUK  >##PBRP_login"

        imgui.SetCursorPos(V2(24, 104))
        imgui.TextColored(imgui.ImVec4(1, 0.72, 0.75, 1), heading)
        imgui.SetCursorPos(V2(24, 134))
        imgui.Text(welcome)
        imgui.SetCursorPos(V2(24, 160))
        imgui.TextColored(P.muted, accountName ~= "" and accountName or "Akun PekanBaru Roleplay")

        drawList:AddRectFilled(V2(pos.x + 24, pos.y + 182), V2(pos.x + size.x - 24, pos.y + 183),
            colorU32(imgui.ImVec4(1, 1, 1, 0.07)))

        local fieldLabelY = math.max(196, height - 296)
        imgui.SetCursorPos(V2(24, fieldLabelY))
        if loginError and loginError ~= "" then
            imgui.TextColored(P.error, loginError)
        else
            imgui.TextColored(P.muted, fieldLabel)
        end

        imgui.SetCursorPos(V2(24, fieldLabelY + 28))
        local inputFlags = imgui.InputTextFlags.EnterReturnsTrue
        if dialogMode == "verify" then
            inputFlags = inputFlags + imgui.InputTextFlags.CharsDecimal
        else
            inputFlags = inputFlags + imgui.InputTextFlags.Password
        end
        local enterPressed = imgui.InputTextWithHint("##PBRP_login_password", fieldHint,
            password, ffi.sizeof(password), inputFlags)
        local passwordValue = ffi.string(password)
        if passwordValue ~= lastPasswordValue
            and (lastTypeSoundAt == 0 or os.clock() - lastTypeSoundAt >= 0.08) then
            lastTypeSoundAt = os.clock()
            playFeedback("type")
        end
        lastPasswordValue = passwordValue

        imgui.SetCursorPos(V2(24, size.y - 82))
        if imgui.Button("KELUAR##PBRP_login", V2(112, 42)) then
            respond(0)
        end
        imgui.SameLine(0, 12)
        local submitClicked = imgui.Button(submitLabel, V2(size.x - 172, 42))
        if submitClicked or enterPressed then
            respond(1)
        end
        imgui.SetCursorPos(V2(24, size.y - 26))
        local footer = dialogMode == "verify" and "PIN DIKIRIM MELALUI DISCORD"
            or dialogMode == "register" and "PASSWORD AKAN DIGUNAKAN UNTUK LOGIN UCP"
            or "KONEKSI AMAN  /  PEKANBARU ROLEPLAY"
        imgui.TextColored(P.muted, footer)

        imgui.End()
        imgui.PopStyleColor(11)
        imgui.PopStyleVar(6)
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
