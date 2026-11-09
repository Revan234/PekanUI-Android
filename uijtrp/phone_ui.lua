-- phone_ui.lua  (v2 - tampilan iOS / FiveM realistis)
-- Handphone bergaya FiveM: bezel titanium, dynamic island, wallpaper hidup, tema warna per aplikasi,
-- animasi pegas (buka/tutup/peek), badge notifikasi, banner notifikasi, suara getar + nada notif.
--
-- Protokol server (@PBRPUI:*) dan perintah chat lama TIDAK berubah.
-- Tambahan (opsional) untuk notifikasi masuk, dikirim server lewat SendClientMessage:
--   @PBRPUI:PHONE:NOTIFY:SMS:<nomorPengirim>:<isi pesan>
--   @PBRPUI:PHONE:NOTIFY:GROUP:<namaGrup>:<isi pesan>
--   @PBRPUI:PHONE:NOTIFY:MISSED:<nomorPenelepon>
--   @PBRPUI:PHONE:NOTIFY:INFO:<judul>:<isi>
--
-- File suara (opsional, WAV) dicari di:  <moonloader>\resource\PBRP_phone\
--   notify.wav  (nada notif)    vibrate.wav  (getar)
-- Jika file tidak ada, nada notif jatuh ke uiSounds.play("success").

return function(imgui, icons, V2, ffi, photoMedia, sendChat, uiSounds, isPlayerUiReady, getAccent, mediaDirectory)
    ------------------------------------------------------------------ konfigurasi
    local okDir, workDir = pcall(getWorkingDirectory)
    local SOUND_DIR = (okDir and workDir or ".") .. "/resource/PBRP_phone/"
    local PHONE_SOUND_DIR = (mediaDirectory or ".") .. "/"
    local PHONE_SETTINGS_PATH = (okDir and workDir or ".") .. "/config/uiPBRP_phone.ini"
    local PEEK_H = 285        -- tinggi bagian HP yang terlihat saat "mengintip" (px)
    local PEEK_TIME = 5.5     -- lama HP mengintip di pojok kanan bawah (detik)
    local BANNER_TIME = 4.6   -- lama banner notifikasi saat HP terbuka (detik)

    local RINGTONES = {
        { file = "01_classic_phone.wav", label = "Classic Phone" },
        { file = "02_marimba_loop.wav", label = "Marimba Loop" },
        { file = "03_digital_arpeggio.wav", label = "Digital Arpeggio" },
        { file = "04_music_box.wav", label = "Music Box" },
        { file = "05_retro_8bit.wav", label = "Retro 8-bit" },
        { file = "06_soft_bells.wav", label = "Soft Bells" },
        { file = "07_funky_pluck.wav", label = "Funky Pluck" },
        { file = "08_mechanical_bell.wav", label = "Mechanical Bell" },
        { file = "09_rising_pulse.wav", label = "Rising Pulse" },
        { file = "10_gamelan_pentatonic.wav", label = "Gamelan Pentatonic" }
    }
    local NOTIFICATION_TONES = {
        { file = "01_ding.wav", label = "Ding" },
        { file = "02_chime_up.wav", label = "Chime Up" },
        { file = "03_chime_down.wav", label = "Chime Down" },
        { file = "04_triple_chime.wav", label = "Triple Chime" },
        { file = "05_pop.wav", label = "Pop" },
        { file = "06_bubble.wav", label = "Bubble" },
        { file = "07_glass.wav", label = "Glass" },
        { file = "08_marimba_tap.wav", label = "Marimba Tap" },
        { file = "09_double_tap.wav", label = "Double Tap" },
        { file = "10_soft_message.wav", label = "Soft Message" },
        { file = "11_sms_classic.wav", label = "SMS Classic" },
        { file = "12_coin.wav", label = "Coin" },
        { file = "13_sparkle.wav", label = "Sparkle" },
        { file = "14_whoosh_ping.wav", label = "Whoosh Ping" },
        { file = "15_pluck_duo.wav", label = "Pluck Duo" },
        { file = "16_alert_urgent.wav", label = "Alert Urgent" },
        { file = "17_water_drop.wav", label = "Water Drop" },
        { file = "18_harp_gliss.wav", label = "Harp Gliss" },
        { file = "19_kalimba.wav", label = "Kalimba" },
        { file = "20_minimal_tick.wav", label = "Minimal Tick" }
    }
    local selectedRingtone = 1
    local selectedNotificationTone = 1
    local status = ""
    do
        local settings, settingsError = io.open(PHONE_SETTINGS_PATH, "r")
        if settings then
            for line in settings:lines() do
                local key, value = line:match("^([%w_]+)%s*=%s*(%d+)%s*$")
                local index = tonumber(value)
                if key == "ringtone" and index and RINGTONES[index] then
                    selectedRingtone = index
                elseif key == "notification" and index and NOTIFICATION_TONES[index] then
                    selectedNotificationTone = index
                end
            end
            settings:close()
        elseif settingsError and type(doesFileExist) == "function"
            and doesFileExist(PHONE_SETTINGS_PATH) then
            print("[PBRP/PKU UI] Gagal membaca pengaturan nada ponsel: " .. tostring(settingsError))
        end
    end
    local function saveSoundPreferences()
        local settings, settingsError = io.open(PHONE_SETTINGS_PATH, "w")
        if not settings then
            local message = "[PBRP/PKU UI] Gagal menyimpan pengaturan nada ponsel: "
                .. tostring(settingsError)
            print(message)
            status = "Pengaturan nada gagal disimpan. Lihat moonloader.log."
            return false
        end
        local ok, writeError = settings:write(
            "ringtone=" .. selectedRingtone .. "\nnotification=" .. selectedNotificationTone .. "\n")
        settings:close()
        if not ok then
            local message = "[PBRP/PKU UI] Gagal menulis pengaturan nada ponsel: "
                .. tostring(writeError)
            print(message)
            status = "Pengaturan nada gagal disimpan. Lihat moonloader.log."
            return false
        end
        return true
    end

    ------------------------------------------------------------------ state
    local open = false
    local page = "lock"
    local unlocked = false
    local phoneNumber = 0
    local phoneEnabled = true
    local contacts = {}
    local messages = {}
    local historyNumber = 0
    local callState = nil
    local callNumber = 0
    local callChatOpen = false
    local taxiOrderPending = false
    local videoCall = false
    local videoPeer = nil
    local nextVideoStatusAt = 0
    local cameraActionStatus = ""
    local cameraTimerModes = { 0, 3, 5, 10 }
    local cameraTimerIndex = 1
    local cameraCaptureAt = nil
    local cameraGridEnabled = true
    local cameraTagsEnabled = true
    local readyAcknowledged = false
    local lastReadyAttempt = 0
    local selectedPhoto = 1
    local photoTextures = {}
    local phoneInfo = nil
    local socialPosts = {}
    local yellowPages = {}
    local groups = {}
    local groupMessages = {}
    local activeGroupId = 0
    local activeGroupName = ""
    local emergencyService = "police"
    local soundEnabled = imgui.new.bool(true)
    local soundVolume = imgui.new.float(0.55)
    local playlists = {}
    local tracks = {}
    local trackOrder = {}
    local sharedMusic = nil
    local MUSIC_BASS_ATTRIB_VOLUME = 2
    local MUSIC_BASS_ERROR_ALREADY = 14
    local sharedAudio = {
        bass = nil,
        bassChecked = false,
        initialized = false,
        handle = nil,
        lastVolumeUpdate = 0,
        warned = false,
    }
    local selectedPlaylist = 0
    local musicView = "playlists"
    local musicPublic = imgui.new.bool(true)
    local chatNumber = nil
    local scrollChatToEnd = false
    local openedAt = 0
    local vehicles = {}
    local selectedNumber = imgui.new.char[32]()
    local dialNumber = imgui.new.char[32]()
    local contactName = imgui.new.char[33]()
    local messageInput = imgui.new.char[129]()
    local callMessageInput = imgui.new.char[129]()
    local playlistName = imgui.new.char[41]()
    local trackTitle = imgui.new.char[25]()
    local trackUrl = imgui.new.char[97]()
    local bankIdInput = imgui.new.char[16]()
    local bankAmountInput = imgui.new.int(1)
    local emergencyInput = imgui.new.char[129]()
    local socialInput = imgui.new.char[81]()
    local yellowInput = imgui.new.char[101]()
    local groupNameInput = imgui.new.char[25]()
    local groupIdInput = imgui.new.char[16]()
    local groupMessageInput = imgui.new.char[81]()

    -- state tambahan (notifikasi, animasi, suara) dikumpulkan dalam satu tabel
    local NS = {
        notifs = {},          -- daftar notifikasi terbaru
        unread = {},          -- nomor -> jumlah pesan belum dibaca
        names = {},           -- cache nomor -> nama kontak
        banner = nil,         -- banner notifikasi aktif
        peek = false,         -- HP sedang mengintip (HP tertutup + ada notif)
        peekUntil = 0,
        slide = 0,            -- posisi HP: 0 tersembunyi .. 1 penuh (pegas)
        slideVel = 0,
        shakeAt = -10,        -- waktu getar terakhir
        playingTrack = 0,
        ringtoneToken = 0,
        ringtoneStream = nil,
        navDir = 0,           -- arah transisi halaman: 1 maju, -1 mundur, 0 dari beranda
        msgAt = -10,
        streams = {},
        tg = {},              -- animasi toggle
        notifOn = imgui.new.bool(true),
        vibrateOn = imgui.new.bool(true)
    }

    local apps = {
        { id = "contacts", label = "Kontak", icon = "user", color = { 0.24, 0.72, 0.48 } },
        { id = "dialer", label = "Telepon", icon = "phone", color = { 0.20, 0.72, 0.42 } },
        { id = "messages", label = "Pesan", icon = "chat", color = { 0.20, 0.62, 0.95 } },
        { id = "bank", label = "Bank", icon = "bank", color = { 0.25, 0.62, 0.83 } },
        { id = "information", label = "Info", icon = "help", color = { 0.34, 0.62, 0.86 } },
        { id = "taxi", label = "Taxi", icon = "vehicle", color = { 0.93, 0.72, 0.22 } },
        { id = "emergency", label = "Darurat", icon = "help", color = { 0.93, 0.39, 0.32 } },
        { id = "social", label = "X / Sosial", icon = "chat", color = { 0.64, 0.42, 0.83 } },
        { id = "yellowpages", label = "Yellow Pages", icon = "map", color = { 0.91, 0.69, 0.25 } },
        { id = "groups", label = "Grup", icon = "user", color = { 0.29, 0.66, 0.77 } },
        { id = "camera", label = "Kamera", icon = "default", color = { 0.51, 0.58, 0.68 } },
        { id = "photos", label = "Foto", icon = "map", color = { 0.81, 0.48, 0.55 } },
        { id = "music", label = "Musik", icon = "chat", color = { 0.82, 0.46, 0.70 } },
        { id = "settings", label = "Pengaturan", icon = "settings", color = { 0.45, 0.49, 0.58 } }
    }
    local appById = {}
    for _, app in ipairs(apps) do appById[app.id] = app end
    local dockOrder = { "dialer", "messages", "contacts", "camera" }
    local inDock = {}
    for _, id in ipairs(dockOrder) do inDock[id] = true end

    ------------------------------------------------------------------ helpers
    local A = { gA = 1, pageAt = 0, prevPage = "lock", lastPage = "lock", lastKey = "", t = 0, last = 0, dt = 0,
        islandW = 98, callSince = nil, shutterAt = -10, homeHover = 0 }
    local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end
    local U32 = imgui.GetColorU32Vec4
    local function U(r, g, b, a) return U32(imgui.ImVec4(r, g, b, (a or 1) * A.gA)) end
    local function UV(v) return U32(imgui.ImVec4(v.x, v.y, v.z, v.w * A.gA)) end
    local padFlag = imgui.WindowFlags.AlwaysUseWindowPadding or 0
    local function wflag(name) return imgui.WindowFlags[name] or 0 end

    local K = {
        white = V4(0.97, 0.97, 1, 1),
        muted = V4(0.60, 0.60, 0.66, 1),
        green = V4(0.19, 0.82, 0.35, 1),
        blue = V4(0.04, 0.52, 1, 1),
        warn = V4(1, 0.62, 0.04, 1),
        glass = V4(0.105, 0.11, 0.135, 1),
        clear = V4(0, 0, 0, 0)
    }
    local KIND = {
        primary = { V4(0.04, 0.52, 1, 1), V4(0.26, 0.63, 1, 1) },
        success = { V4(0.19, 0.82, 0.35, 1), V4(0.32, 0.88, 0.47, 1) },
        danger = { V4(1, 0.27, 0.23, 1), V4(1, 0.40, 0.36, 1) },
        glass = { V4(0.17, 0.17, 0.19, 1), V4(0.24, 0.24, 0.27, 1) },
        ghost = { V4(0, 0, 0, 0), V4(1, 1, 1, 0.07) }
    }
    local function updateAccentPalette()
        local r, g, b = getAccent()
        K.blue = V4(r, g, b, 1)
        KIND.primary = {
            V4(r * 0.75, g * 0.75, b * 0.75, 1),
            V4(math.min(1, r * 1.15), math.min(1, g * 1.15), math.min(1, b * 1.15), 1)
        }
    end
    local DAYS = { "Minggu", "Senin", "Selasa", "Rabu", "Kamis", "Jumat", "Sabtu" }
    local MONTHS = { "Januari", "Februari", "Maret", "April", "Mei", "Juni", "Juli",
        "Agustus", "September", "Oktober", "November", "Desember" }
    local KEYS = {
        { "1", "" }, { "2", "ABC" }, { "3", "DEF" },
        { "4", "GHI" }, { "5", "JKL" }, { "6", "MNO" },
        { "7", "PQRS" }, { "8", "TUV" }, { "9", "WXYZ" }
    }

    local function dateString()
        local t = os.date("*t")
        return string.format("%s, %d %s", DAYS[t.wday], t.day, MONTHS[t.month])
    end

    local function ease(t)
        t = math.min(1, math.max(0, t))
        return 1 - (1 - t) ^ 3
    end

    local function easeBack(t)
        t = math.min(1, math.max(0, t))
        local c1 = 1.70158
        local c3 = c1 + 1
        return 1 + c3 * (t - 1) ^ 3 + c1 * (t - 1) ^ 2
    end

    local function hsv(h, s, v)
        local i = math.floor(h * 6)
        local f = h * 6 - i
        local p, q, t = v * (1 - s), v * (1 - f * s), v * (1 - (1 - f) * s)
        i = i % 6
        if i == 0 then return v, t, p elseif i == 1 then return q, v, p
        elseif i == 2 then return p, v, t elseif i == 3 then return p, q, v
        elseif i == 4 then return t, p, v else return v, p, q end
    end

    local function hashHue(text)
        local h = 7
        for i = 1, #text do h = (h * 31 + text:byte(i)) % 997 end
        return (h % 360) / 360
    end

    local function fitText(text, maxW)
        if imgui.CalcTextSize(text).x <= maxW then return text end
        while #text > 1 and imgui.CalcTextSize(text .. "..").x > maxW do
            text = text:sub(1, -2)
        end
        return text .. ".."
    end

    local function wrapHeight(text, width)
        local ok, size = pcall(imgui.CalcTextSize, text, nil, false, width)
        if ok and size then return size.y end
        return 15 * math.ceil(#text * 7 / math.max(40, width))
    end

    local function clearBuffer(buffer)
        ffi.fill(buffer, ffi.sizeof(buffer), 0)
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

    local function hoverKey(key)
        if imgui.IsItemHovered() then uiSounds.hover(key) end
    end

    local function gradientRounded(dl, x, y, w, h, r, top, bottom)
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), bottom, r)
        dl:AddRectFilled(V2(x, y), V2(x + w, y + 2 * r), top, r)
        dl:AddRectFilledMultiColor(V2(x, y + r), V2(x + w, y + h - r), top, top, bottom, bottom)
    end

    local function dlText(dl, text, x, y, col, scale)
        imgui.SetWindowFontScale(scale or 1)
        dl:AddText(V2(x, y), col, text)
        imgui.SetWindowFontScale(1)
    end

    local function dlTextC(dl, text, cx, y, col, scale)
        imgui.SetWindowFontScale(scale or 1)
        local s = imgui.CalcTextSize(text)
        dl:AddText(V2(cx - s.x / 2, y), col, text)
        imgui.SetWindowFontScale(1)
        return s
    end

    local function centerText(text, vec, scale)
        imgui.SetWindowFontScale(scale or 1)
        local size = imgui.CalcTextSize(text)
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (imgui.GetContentRegionAvail().x - size.x) / 2)
        imgui.TextColored(vec, text)
        imgui.SetWindowFontScale(1)
    end

    -- ikon aplikasi mini (dipakai di header, banner, dan kartu notifikasi)
    local function miniSquircle(dl, x, y, s, app)
        local c = app.color
        dl:AddRectFilled(V2(x + 1, y + 2), V2(x + s - 1, y + s + 2), U(0, 0, 0, 0.22), s * 0.27)
        gradientRounded(dl, x, y, s, s, s * 0.27,
            U(math.min(1, c[1] * 1.22), math.min(1, c[2] * 1.22), math.min(1, c[3] * 1.22), 1),
            U(c[1] * 0.80, c[2] * 0.80, c[3] * 0.80, 1))
        dl:AddRect(V2(x, y), V2(x + s, y + s), U(1, 1, 1, 0.20), s * 0.27, 0, 1)
        local gs = s * 0.52
        icons.draw(dl, app.icon, x + (s - gs) / 2, y + (s - gs) / 2, gs, U(1, 1, 1, 1), U(c[1], c[2], c[3], 1))
    end

    local function pillButton(label, w, h, kind)
        local c = KIND[kind or "glass"]
        imgui.PushStyleColor(imgui.Col.Button, c[1])
        imgui.PushStyleColor(imgui.Col.ButtonHovered, c[2])
        imgui.PushStyleColor(imgui.Col.ButtonActive, c[2])
        imgui.PushStyleColor(imgui.Col.Text, kind == "ghost" and K.blue or K.white)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, math.min(14, h / 2))
        local clicked = imgui.Button(label, V2(w, h))
        imgui.PopStyleVar(1)
        imgui.PopStyleColor(4)
        hoverKey(label)
        return clicked
    end

    local function styledInput(id, hint, buffer)
        imgui.PushStyleColor(imgui.Col.FrameBg, V4(0.15, 0.155, 0.18, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, V4(0.19, 0.195, 0.22, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgActive, V4(0.22, 0.225, 0.26, 1))
        imgui.PushStyleColor(imgui.Col.Border, V4(1, 1, 1, 0.08))
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 13)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameBorderSize, 1)
        imgui.PushStyleVarVec2(imgui.StyleVar.FramePadding, V2(12, 8))
        local changed = imgui.InputTextWithHint(id, hint, buffer, ffi.sizeof(buffer), 0)
        imgui.PopStyleVar(3)
        imgui.PopStyleColor(4)
        if changed then uiSounds.play("type") end
        return changed
    end

    local function beginCard(id, height, fill)
        imgui.PushStyleColor(imgui.Col.ChildBg, fill or K.glass)
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 18)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(14, 12))
        imgui.BeginChild(id, V2(-1, height), false, padFlag)
        imgui.PopStyleVar(2)
        -- garis tepi tipis + kilau atas agar terlihat seperti kaca
        local p, s = imgui.GetWindowPos(), imgui.GetWindowSize()
        local dl = imgui.GetWindowDrawList()
        dl:AddRect(V2(p.x + 0.5, p.y + 0.5), V2(p.x + s.x - 0.5, p.y + s.y - 0.5), U(1, 1, 1, 0.07), 18, 0, 1)
        dl:AddLine(V2(p.x + 16, p.y + 1), V2(p.x + s.x - 16, p.y + 1), U(1, 1, 1, 0.10), 1)
    end

    local function endCard()
        imgui.EndChild()
        imgui.PopStyleColor(1)
    end

    local function drawStatus()
        if status ~= "" then
            imgui.Spacing()
            imgui.PushStyleColor(imgui.Col.Text, K.warn)
            imgui.TextWrapped(status)
            imgui.PopStyleColor()
        end
    end

    local function avatar(dl, cx, cy, r, name)
        local red, green, blue = hsv(hashHue(name), 0.38, 0.72)
        dl:AddCircleFilled(V2(cx, cy), r, U(red * 0.82, green * 0.82, blue * 0.82, 1), 32)
        dl:AddCircleFilled(V2(cx, cy - r * 0.18), r * 0.84, U(red, green, blue, 0.55), 32)
        local letter = name:sub(1, 1):upper()
        local size = imgui.CalcTextSize(letter)
        dl:AddText(V2(cx - size.x / 2, cy - size.y / 2), U(1, 1, 1, 0.97), letter)
    end

    -- Tombol bulat; areaW/areaH opsional agar tinggi baris seragam.
    local function circleButton(id, d, fill, hoverFill, iconName, areaW, areaH)
        areaW, areaH = areaW or d, areaH or d
        local clicked = imgui.InvisibleButton(id, V2(areaW, areaH))
        local hovered = imgui.IsItemHovered()
        local held = imgui.IsItemActive()
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        local cx, cy = min.x + areaW / 2, min.y + areaH / 2
        local col = hovered and hoverFill or fill
        dl:AddCircleFilled(V2(cx, cy), d / 2 * (held and 0.92 or 1), UV(col), 40)
        if iconName then
            local s = d * 0.46
            icons.draw(dl, iconName, cx - s / 2, cy - s / 2, s, U(1, 1, 1, 1), UV(col))
        end
        hoverKey(id)
        return clicked
    end

    local function rowButton(id, w, h)
        local clicked = imgui.InvisibleButton(id, V2(w, h))
        local min = imgui.GetItemRectMin()
        local max = imgui.GetItemRectMax()
        local dl = imgui.GetWindowDrawList()
        if imgui.IsItemHovered() then
            dl:AddRectFilled(min, max, U(1, 1, 1, 0.07), 14)
        end
        hoverKey(id)
        return clicked, min, max, dl
    end

    -- saklar gaya iOS dengan animasi geser
    local function toggleSwitch(id, ptr)
        local clicked = imgui.InvisibleButton(id, V2(50, 30))
        hoverKey(id)
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        if clicked then ptr[0] = not ptr[0] end
        local target = ptr[0] and 1 or 0
        local k = NS.tg[id] or target
        k = k + (target - k) * math.min(1, A.dt * 14)
        NS.tg[id] = k
        dl:AddRectFilled(min, V2(min.x + 50, min.y + 30),
            U(0.33 - 0.14 * k, 0.33 + 0.49 * k, 0.37 - 0.02 * k, 1), 15)
        dl:AddCircleFilled(V2(min.x + 15 + 20 * k, min.y + 15), 12.5, U(0, 0, 0, 0.22), 24)
        dl:AddCircleFilled(V2(min.x + 15 + 20 * k, min.y + 14), 12.5, U(1, 1, 1, 1), 24)
        if clicked then uiSounds.play("tab") end
        return clicked
    end

    local function toggleRow(label, ptr, id)
        local w = imgui.GetContentRegionAvail().x
        local y0 = imgui.GetCursorPosY()
        imgui.SetCursorPosY(y0 + 6)
        imgui.TextColored(K.white, label)
        imgui.SetCursorPos(V2(imgui.GetCursorPosX() + w - 50, y0))
        local changed = toggleSwitch(id, ptr)
        imgui.Dummy(V2(1, 2))
        return changed
    end

    -- daftar grup ala "inset grouped list" iOS
    local function groupedList(title, rows)
        if title then
            imgui.Spacing()
            imgui.TextColored(K.muted, string.upper(title))
        end
        local avail = imgui.GetContentRegionAvail().x
        local rowH = 42
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(avail, rowH * #rows))
        local dl = imgui.GetWindowDrawList()
        local bottom = p.y + rowH * #rows
        dl:AddRectFilled(p, V2(p.x + avail, bottom), UV(K.glass), 16)
        dl:AddRect(p, V2(p.x + avail, bottom), U(1, 1, 1, 0.07), 16, 0, 1)
        for i, row in ipairs(rows) do
            local y = p.y + (i - 1) * rowH
            if i > 1 then dl:AddLine(V2(p.x + 14, y), V2(p.x + avail, y), U(1, 1, 1, 0.07), 1) end
            dl:AddText(V2(p.x + 14, y + 13), U(0.60, 0.60, 0.66, 1), row[1])
            local value = fitText(row[2], avail * 0.58)
            local ts = imgui.CalcTextSize(value)
            local c = row[3] or { 0.97, 0.97, 1 }
            dl:AddText(V2(p.x + avail - ts.x - 14, y + 13), U(c[1], c[2], c[3], 1), value)
        end
        imgui.Dummy(V2(1, 4))
    end

    -- Ikon aplikasi gaya iOS (squircle) dengan animasi pop-in bertahap + badge.
    local function drawAppIcon(app, cellW, cellH, withLabel, order)
        local clicked = imgui.InvisibleButton("##app_" .. app.id, V2(cellW, cellH))
        hoverKey("app_" .. app.id)
        local hovered = imgui.IsItemHovered()
        local held = imgui.IsItemActive()
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        local t = easeBack((A.t - math.max(A.pageAt, openedAt) - (order or 0) * 0.025) / 0.45)
        t = math.max(0, t)
        local saved = A.gA
        A.gA = saved * math.min(1, t)
        local size = 56
        local s = size * (0.55 + 0.45 * t) * (held and 0.9 or (hovered and 1.06 or 1))
        local x0 = min.x + cellW / 2 - s / 2
        local y0 = min.y + 2 + (size - s) / 2
        local c = app.color
        dl:AddRectFilled(V2(x0 + 1, y0 + 4), V2(x0 + s - 1, y0 + s + 5), U(0, 0, 0, 0.30), 15)
        gradientRounded(dl, x0, y0, s, s, 15,
            U(math.min(1, c[1] * 1.22), math.min(1, c[2] * 1.22), math.min(1, c[3] * 1.22), 1),
            U(c[1] * 0.78, c[2] * 0.78, c[3] * 0.78, 1))
        dl:AddRectFilledMultiColor(V2(x0 + 5, y0 + 5), V2(x0 + s - 5, y0 + s * 0.48),
            U(1, 1, 1, 0.17), U(1, 1, 1, 0.17), U(1, 1, 1, 0), U(1, 1, 1, 0))
        dl:AddRect(V2(x0, y0), V2(x0 + s, y0 + s), U(1, 1, 1, 0.22), 15, 0, 1)
        local gs = s * 0.5
        icons.draw(dl, app.icon, x0 + (s - gs) / 2, y0 + (s - gs) / 2, gs,
            U(1, 1, 1, 1), U(c[1], c[2], c[3], 1))
        if app.id == "messages" then
            local count = 0
            for _, n in pairs(NS.unread) do count = count + n end
            if count > 0 then
                local txt = tostring(math.min(count, 99))
                local bx, by = x0 + s - 3, y0 + 3
                local pulse = 1 + math.sin(A.t * 4) * 0.05
                dl:AddCircleFilled(V2(bx, by + 1), 11 * pulse, U(0, 0, 0, 0.30), 20)
                dl:AddCircleFilled(V2(bx, by), 10 * pulse, U(1, 0.23, 0.19, 1), 20)
                dl:AddCircle(V2(bx, by), 10 * pulse, U(1, 1, 1, 0.35), 20, 1)
                local ts = imgui.CalcTextSize(txt)
                dl:AddText(V2(bx - ts.x / 2, by - ts.y / 2), U(1, 1, 1, 1), txt)
            end
        end
        if withLabel then
            local label = fitText(app.label, cellW + 4)
            local ts = imgui.CalcTextSize(label)
            local lx, ly = min.x + (cellW - ts.x) / 2, min.y + size + 8
            dl:AddText(V2(lx + 1, ly + 1), U(0, 0, 0, 0.45), label)
            dl:AddText(V2(lx, ly), U(1, 1, 1, 0.96), label)
        end
        A.gA = saved
        return clicked
    end

    local function contactLabel(number)
        for _, c in ipairs(contacts) do
            if c.number == number then return c.name end
        end
        return NS.names[number]
    end

    local function dialAppend(digit)
        local current = ffi.string(dialNumber)
        if #current < 15 then ffi.copy(dialNumber, current .. digit) end
    end

    local function dialBackspace()
        local current = ffi.string(dialNumber)
        ffi.copy(dialNumber, current:sub(1, -2))
    end

    local function stopSharedAudio()
        local bass = sharedAudio.bass
        if sharedAudio.handle and bass then
            pcall(bass.BASS_ChannelStop, sharedAudio.handle)
            pcall(bass.BASS_StreamFree, sharedAudio.handle)
        end
        sharedAudio.handle = nil
    end

    local function sharedAudioWarning(message)
        if sharedAudio.warned then return end
        sharedAudio.warned = true
        print("[PBRP/PKU UI] " .. message)
        status = "Audio bersama gagal diputar. Periksa moonloader.log."
    end

    local function getSharedAudioBass()
        if sharedAudio.bassChecked then return sharedAudio.bass end
        sharedAudio.bassChecked = true
        local ok, bass = pcall(require, "bass")
        if not ok or not bass then
            sharedAudioWarning("Binding BASS tidak tersedia untuk audio musik bersama: " .. tostring(bass))
            return nil
        end
        sharedAudio.bass = bass
        return bass
    end

    local function startSharedAudio(url)
        stopSharedAudio()
        local bass = getSharedAudioBass()
        if not bass then return false end

        if not sharedAudio.initialized then
            local ok, initialized = pcall(bass.BASS_Init, -1, 44100, 0, nil, nil)
            local errorCode = bass.BASS_ErrorGetCode()
            if not ok or (not initialized and errorCode ~= MUSIC_BASS_ERROR_ALREADY) then
                sharedAudioWarning("BASS gagal diinisialisasi (kode " .. tostring(errorCode) .. ").")
                return false
            end
            sharedAudio.initialized = true
        end

        local ok, stream = pcall(bass.BASS_StreamCreateURL, url, 0, 0, nil, nil)
        if not ok or not stream or stream == 0 then
            sharedAudioWarning("BASS gagal membuka URL stream (kode "
                .. tostring(bass.BASS_ErrorGetCode()) .. ").")
            return false
        end
        sharedAudio.handle = stream
        pcall(bass.BASS_ChannelSetAttribute, stream, MUSIC_BASS_ATTRIB_VOLUME, 0)
        local playOk, playing = pcall(bass.BASS_ChannelPlay, stream, 1)
        if not playOk or not playing then
            sharedAudioWarning("BASS gagal memutar URL stream (kode "
                .. tostring(bass.BASS_ErrorGetCode()) .. ").")
            stopSharedAudio()
            return false
        end
        sharedAudio.lastVolumeUpdate = 0
        return true
    end

    local function updateSharedMusic()
        if not sharedMusic or not sharedAudio.handle then return end
        local now = os.clock()
        if now - sharedAudio.lastVolumeUpdate < 0.12 then return end
        sharedAudio.lastVolumeUpdate = now

        local volume = 0
        local ok, connected = pcall(sampIsPlayerConnected, sharedMusic.owner)
        if ok and connected then
            pcall(function()
                local hasPed, ped = sampGetCharHandleBySampPlayerId(sharedMusic.owner)
                if hasPed and ped and doesCharExist(ped) then
                    local px, py, pz = getCharCoordinates(PLAYER_PED)
                    local sx, sy, sz = getCharCoordinates(ped)
                    local dx, dy, dz = px - sx, py - sy, pz - sz
                    local distance = math.sqrt(dx * dx + dy * dy + dz * dz)
                    volume = math.max(0, 1 - distance / 35)
                end
            end)
        end

        local bass = sharedAudio.bass
        if bass then
            local setOk, setVolume = pcall(
                bass.BASS_ChannelSetAttribute, sharedAudio.handle,
                MUSIC_BASS_ATTRIB_VOLUME, volume)
            if not setOk or not setVolume then
                sharedAudioWarning("Gagal memperbarui volume musik bersama.")
                stopSharedAudio()
            end
        end
    end

    local function keyButton(id, d, label, sub)
        local clicked = imgui.InvisibleButton(id, V2(d, d))
        hoverKey(id)
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        local cx, cy = min.x + d / 2, min.y + d / 2
        local active = imgui.IsItemActive()
        local alpha = active and 0.34 or (imgui.IsItemHovered() and 0.24 or 0.17)
        dl:AddCircleFilled(V2(cx, cy), d / 2 * (active and 0.96 or 1), U(1, 1, 1, alpha), 44)
        imgui.SetWindowFontScale(1.7)
        local ts = imgui.CalcTextSize(label)
        dl:AddText(V2(cx - ts.x / 2, cy - ts.y / 2 - (sub ~= "" and 6 or 0)), U(1, 1, 1, 1), label)
        imgui.SetWindowFontScale(0.85)
        if sub ~= "" then
            local ss = imgui.CalcTextSize(sub)
            dl:AddText(V2(cx - ss.x / 2, cy + 9), U(1, 1, 1, 0.62), sub)
        end
        imgui.SetWindowFontScale(1)
        return clicked
    end

    ------------------------------------------------------------------ suara (getar + nada notif)
    local function loadStream(name)
        local cached = NS.streams[name]
        if cached ~= nil then return cached or nil end
        local stream
        pcall(function()
            local path = SOUND_DIR .. name .. ".wav"
            if doesFileExist(path) then stream = loadAudioStream(path) end
        end)
        NS.streams[name] = stream or false
        return stream
    end

    local function playSfx(name, volume)
        if not soundEnabled[0] then return false end
        local stream = loadStream(name)
        if not stream then return false end
        local vol = volume or math.min(1, math.max(0.08, soundVolume[0] * 1.6))
        pcall(function()
            setAudioStreamVolume(stream, vol)
            setAudioStreamState(stream, 0)
            setAudioStreamState(stream, 1)
        end)
        return true
    end

    local audioWarnings = {}
    local function audioWarning(key, message)
        if audioWarnings[key] then return end
        audioWarnings[key] = true
        print("[PBRP/PKU UI] " .. message)
    end

    local function readUInt32LE(bytes)
        local a, b, c, d = bytes:byte(1, 4)
        if not d then return nil end
        return a + b * 256 + c * 65536 + d * 16777216
    end

    local function waveDuration(path)
        local file = io.open(path, "rb")
        if not file then return 3 end
        local header = file:read(12)
        if not header or header:sub(1, 4) ~= "RIFF" or header:sub(9, 12) ~= "WAVE" then
            file:close()
            return 3
        end

        local byteRate, dataSize
        while true do
            local chunk = file:read(8)
            if not chunk then break end
            local chunkSize = readUInt32LE(chunk:sub(5, 8))
            if not chunkSize then break end
            if chunk:sub(1, 4) == "fmt " then
                local format = file:read(math.min(chunkSize, 16))
                if format and #format >= 12 then
                    byteRate = readUInt32LE(format:sub(9, 12))
                end
                file:seek("cur", math.max(0, chunkSize - (format and #format or 0)))
            elseif chunk:sub(1, 4) == "data" then
                dataSize = chunkSize
                break
            else
                file:seek("cur", chunkSize)
            end
            if chunkSize % 2 == 1 then file:seek("cur", 1) end
        end
        file:close()
        if byteRate and byteRate > 0 and dataSize and dataSize > 0 then
            return math.max(0.25, dataSize / byteRate)
        end
        return 3
    end

    local function startAudioFile(options, index)
        local option = options[index]
        if not option then return nil end
        if type(loadAudioStream) ~= "function" or type(setAudioStreamState) ~= "function" then
            audioWarning("audio-api", "API audio stream tidak tersedia; nada ponsel tidak dapat diputar.")
            return nil
        end
        local path = PHONE_SOUND_DIR .. option.file
        if type(doesFileExist) ~= "function" or not doesFileExist(path) then
            audioWarning(path, "File nada tidak ditemukan: " .. path)
            return nil
        end

        local ok, stream = pcall(loadAudioStream, path)
        if not ok or not stream or stream == 0 then
            audioWarning(path, "Gagal memuat nada ponsel " .. option.label .. ": " .. tostring(stream))
            return nil
        end
        local volume = math.min(1, math.max(0, soundVolume[0] * 1.6))
        local volumeOk, volumeError = pcall(setAudioStreamVolume, stream, volume)
        local stateOk, stateError = pcall(setAudioStreamState, stream, 1)
        if not stateOk then
            pcall(setAudioStreamState, stream, 0)
            if type(releaseAudioStream) == "function" then pcall(releaseAudioStream, stream) end
            audioWarning(path, "Gagal memutar nada ponsel " .. option.label .. ": " .. tostring(stateError))
            return nil
        end
        if not volumeOk then
            audioWarning(path .. ":volume", "Gagal mengatur volume nada ponsel: " .. tostring(volumeError))
        end
        return stream, waveDuration(path)
    end

    local function releaseAudioFile(stream)
        pcall(setAudioStreamState, stream, 0)
        if type(releaseAudioStream) == "function" then
            local ok, err = pcall(releaseAudioStream, stream)
            if not ok then audioWarning("release-audio", "Gagal melepas audio stream: " .. tostring(err)) end
        end
    end

    local function playOneShot(options, index)
        if not soundEnabled[0] then return false end
        local stream, duration = startAudioFile(options, index)
        if not stream then return false end
        if type(lua_thread) ~= "table" or type(lua_thread.create) ~= "function" then
            releaseAudioFile(stream)
            audioWarning("audio-thread", "Lua thread tidak tersedia untuk membersihkan audio stream.")
            return false
        end
        local ok, err = pcall(function()
            lua_thread.create(function()
                wait(math.ceil(duration * 1000))
                releaseAudioFile(stream)
            end)
        end)
        if not ok then
            audioWarning("audio-thread", "Gagal menjadwalkan pembersihan nada: " .. tostring(err))
            releaseAudioFile(stream)
            return false
        end
        return true
    end

    local function stopRingtone()
        NS.ringtoneToken = NS.ringtoneToken + 1
        if NS.ringtoneStream then
            releaseAudioFile(NS.ringtoneStream)
            NS.ringtoneStream = nil
        end
    end

    local function startRingtone()
        stopRingtone()
        if not soundEnabled[0] or type(lua_thread) ~= "table"
            or type(lua_thread.create) ~= "function" then
            if soundEnabled[0] then
                audioWarning("ringtone-thread", "Lua thread tidak tersedia untuk nada dering.")
            end
            return
        end
        local token = NS.ringtoneToken
        local ok, err = pcall(function()
            lua_thread.create(function()
                while token == NS.ringtoneToken and callState == "IN" do
                    local stream, duration = startAudioFile(RINGTONES, selectedRingtone)
                    if not stream then return end
                    NS.ringtoneStream = stream
                    local elapsed = 0
                    while elapsed < duration * 1000 and token == NS.ringtoneToken
                        and callState == "IN" do
                        local step = math.min(100, duration * 1000 - elapsed)
                        wait(step)
                        elapsed = elapsed + step
                    end
                    if NS.ringtoneStream == stream then
                        releaseAudioFile(stream)
                        NS.ringtoneStream = nil
                    end
                    if token == NS.ringtoneToken and callState == "IN" then wait(350) end
                end
            end)
        end)
        if not ok then
            audioWarning("ringtone-thread", "Gagal menjalankan nada dering: " .. tostring(err))
        end
    end

    local function notifySounds(withVibrate)
        if withVibrate and NS.vibrateOn[0] then playSfx("vibrate") end
        if NS.notifOn[0] then
            if not playOneShot(NOTIFICATION_TONES, selectedNotificationTone) and soundEnabled[0] then
                pcall(uiSounds.play, "success")
            end
        end
    end

    ------------------------------------------------------------------ notifikasi
    local function unreadCount()
        local n = 0
        for _, c in pairs(NS.unread) do n = n + c end
        return n
    end

    local function consumeNotifs(number)
        NS.unread[number] = nil
        for i = #NS.notifs, 1, -1 do
            local n = NS.notifs[i]
            if n.number == number and n.kind == "sms" then table.remove(NS.notifs, i) end
        end
        if NS.banner and NS.banner.number == number then NS.banner = nil end
    end

    local function pushNotification(kind, title, body, number)
        local now = os.clock()
        NS.shakeAt = now
        local inChat = kind == "sms" and open and (
            (unlocked and page == "messages" and chatNumber == number)
            or (page == "call" and callState == "ACTIVE" and callNumber == number))
        if inChat then
            -- Refresh percakapan aktif tanpa menutupi panggilan dengan banner.
            sendChat("/rpui_phone_messages " .. tostring(number))
            notifySounds(false)
            return
        end
        table.insert(NS.notifs, 1, {
            kind = kind, title = title, body = body, number = number, at = now, stamp = os.time()
        })
        while #NS.notifs > 12 do table.remove(NS.notifs) end
        if kind == "sms" and number then
            NS.unread[number] = (NS.unread[number] or 0) + 1
        end
        NS.banner = { kind = kind, title = title, body = body, number = number, at = now, stamp = os.time() }
        if not open then
            NS.peek = true
            NS.peekUntil = now + PEEK_TIME
        end
        notifySounds(true)
    end

    local function handleNotifyMessage(text)
        local kind, rest = text:match("^@PBRPUI:PHONE:NOTIFY:(%u+):(.*)$")
        if not kind then return true end
        if kind == "SMS" then
            local number, body = rest:match("^(%d+):(.*)$")
            if number then
                number = tonumber(number)
                pushNotification("sms", contactLabel(number) or tostring(number), body, number)
            end
        elseif kind == "GROUP" then
            local groupName, body = rest:match("^([^:]*):(.*)$")
            if groupName then pushNotification("group", groupName, body, nil) end
        elseif kind == "MISSED" then
            local number = tonumber(rest:match("^(%d+)"))
            if number then
                pushNotification("missed", contactLabel(number) or tostring(number), "Panggilan tak terjawab", number)
            end
        elseif kind == "INFO" then
            local title, body = rest:match("^([^:]*):(.*)$")
            if title then pushNotification("info", title, body, nil) end
        end
        return true
    end

    local function notifApp(kind)
        if kind == "sms" then return appById.messages
        elseif kind == "group" then return appById.groups
        elseif kind == "missed" then return appById.dialer end
        return appById.settings
    end

    local function agoText(stamp)
        local d = os.time() - (stamp or os.time())
        if d < 45 then return "sekarang" end
        if d < 3600 then return string.format("%d mnt lalu", math.max(1, math.floor(d / 60))) end
        return string.format("%d jam lalu", math.floor(d / 3600))
    end

    ------------------------------------------------------------------ actions
    local function close()
        if open then
            if callState then
                status = "Akhiri panggilan sebelum menutup telepon."
                return
            end
            sendChat("/rpui_phone_close")
            uiSounds.play("close")
        end
        photoMedia.restoreCamera()
        open = false
        unlocked = false
        status = ""
    end

    local function openChat(number)
        chatNumber = number
        messages = {}
        historyNumber = 0
        ffi.copy(selectedNumber, tostring(number))
        status = "Memuat percakapan..."
        page = "messages"
        NS.navDir = 1
        consumeNotifs(number)
        sendChat("/rpui_phone_messages " .. tostring(number))
    end

    local function goHome()
        photoMedia.restoreCamera()
        page = unlocked and "home" or "lock"
        chatNumber = nil
        musicView = "playlists"
        status = ""
        NS.navDir = -1
    end

    local function goBack()
        NS.navDir = -1
        if page == "music" and musicView == "tracks" then
            musicView = "playlists"
            tracks = {}
            trackOrder = {}
        elseif page == "messages" and chatNumber then
            chatNumber = nil
        else
            photoMedia.restoreCamera()
            page = unlocked and "home" or "lock"
        end
        status = ""
    end

    local function phoneAction(app)
        NS.navDir = (page == "home") and 0 or 1
        if page == "camera" and app ~= "camera" then
            photoMedia.restoreCamera()
        end
        page = app
        status = ""
        if app == "contacts" then
            sendChat("/rpui_phone_contacts")
        elseif app == "messages" then
            chatNumber = nil
            sendChat("/rpui_phone_contacts")
        elseif app == "camera" then
            cameraActionStatus = ""
            photoMedia.beginCamera()
            photoMedia.refresh()
        elseif app == "photos" then
            photoMedia.refresh()
            selectedPhoto = 1
        elseif app == "music" then
            playlists = {}
            tracks = {}
            trackOrder = {}
            selectedPlaylist = 0
            musicView = "playlists"
            sendChat("/rpui_music_list")
        elseif app == "information" or app == "bank" then
            phoneInfo = nil
            sendChat("/rpui_phone_info")
        elseif app == "taxi" then
            sendChat("/rpui_taxi_status")
        elseif app == "emergency" then
            emergencyService = "police"
        elseif app == "social" then
            socialPosts = {}
            sendChat("/rpui_social_feed")
        elseif app == "yellowpages" then
            yellowPages = {}
            sendChat("/rpui_yellow_list")
        elseif app == "groups" then
            groups = {}
            activeGroupId = 0
            activeGroupName = ""
            groupMessages = {}
            sendChat("/rpui_groups_list")
        elseif app == "settings" then
            uiSounds.setEnabled(soundEnabled[0])
            uiSounds.setVolume(soundVolume[0])
        elseif app ~= "dialer" then
            status = "Aplikasi tidak tersedia."
        end
    end

    ------------------------------------------------------------------ server messages
    local function onServerMessage(text)
        if text:find("^@PBRPUI:PHONE:NOTIFY:") then
            return handleNotifyMessage(text)
        end

        local number, enabled = text:match("^@PBRPUI:PHONE:OPEN:(%-?%d+):([01])$")
        if number then
            stopRingtone()
            photoMedia.restoreCamera()
            phoneNumber = tonumber(number) or 0
            phoneEnabled = enabled == "1"
            open = true
            openedAt = os.clock()
            NS.peek = false
            NS.banner = nil
            NS.navDir = 0
            uiSounds.play("open")
            page = "lock"
            unlocked = false
            chatNumber = nil
            contacts = {}
            messages = {}
            historyNumber = 0
            status = ""
            callState = nil
            callNumber = 0
            videoCall = false
            videoPeer = nil
            nextVideoStatusAt = 0
            readyAcknowledged = false
            lastReadyAttempt = 0
            clearBuffer(selectedNumber)
            clearBuffer(dialNumber)
            clearBuffer(contactName)
            clearBuffer(messageInput)
            clearBuffer(playlistName)
            clearBuffer(trackTitle)
            clearBuffer(trackUrl)
            phoneInfo = nil
            taxiOrderPending = false
            activeGroupId = 0
            activeGroupName = ""
            return true
        end
        if text == "@PBRPUI:PHONE:CLOSED" then
            stopRingtone()
            photoMedia.restoreCamera()
            open = false
            unlocked = false
            page = "lock"
            chatNumber = nil
            callState = nil
            callNumber = 0
            callChatOpen = false
            clearBuffer(callMessageInput)
            videoCall = false
            videoPeer = nil
            nextVideoStatusAt = 0
            readyAcknowledged = false
            return true
        end
        if text == "@PBRPUI:PHONE:READY" then
            readyAcknowledged = true
            return true
        end
        if text == "@PBRPUI:PHONE:POWER:1" then
            phoneEnabled = true
            status = "Handphone dinyalakan."
            uiSounds.play("success")
            return true
        end

        local infoId, infoNumber, cash, bank, bankId, paycheck, faction, rank =
            text:match("^@PBRPUI:PHONE:INFO:(%d+):(%d+):(%d+):(%d+):(%d+):(%d+):([^:]*):(.*)$")
        if infoId then
            phoneInfo = {
                playerId = tonumber(infoId), number = tonumber(infoNumber),
                cash = tonumber(cash), bank = tonumber(bank), bankId = tonumber(bankId),
                paycheck = tonumber(paycheck), faction = faction, rank = rank
            }
            status = ""
            return true
        end
        local updatedBank = text:match("^@PBRPUI:PHONE:BANK:UPDATED:(%d+):")
        if updatedBank then
            if phoneInfo then phoneInfo.bank = tonumber(updatedBank) end
            status = "Transfer berhasil."
            clearBuffer(bankIdInput)
            bankAmountInput[0] = 1
            uiSounds.play("success")
            return true
        end
        local taxiOrder = text:match("^@PBRPUI:PHONE:TAXI:STATUS:([01])$")
        if taxiOrder then
            taxiOrderPending = taxiOrder == "1"
            return true
        end
        if text == "@PBRPUI:PHONE:TAXI:ORDERED" then
            taxiOrderPending = true
            status = "Pesanan transportasi berhasil dikirim."
            uiSounds.play("success")
            return true
        elseif text == "@PBRPUI:PHONE:TAXI:CANCELLED" then
            taxiOrderPending = false
            status = "Pesanan transportasi dibatalkan."
            uiSounds.play("success")
            return true
        end
        if text == "@PBRPUI:PHONE:EMERGENCY:SENT" then
            status = "Laporan berhasil dikirim."
            clearBuffer(emergencyInput)
            uiSounds.play("success")
            return true
        end
        if text == "@PBRPUI:PHONE:SOCIAL:BEGIN" then
            socialPosts = {}
            return true
        end
        local postTime, postName, postText =
            text:match("^@PBRPUI:PHONE:SOCIAL:ITEM:(%d+):([^:]+):(.*)$")
        if postTime then
            socialPosts[#socialPosts + 1] = {
                time = tonumber(postTime), name = postName, text = postText
            }
            return true
        end
        if text == "@PBRPUI:PHONE:SOCIAL:END" then return true end
        if text == "@PBRPUI:PHONE:SOCIAL:POSTED" then
            status = "Postingan berhasil diterbitkan."
            clearBuffer(socialInput)
            uiSounds.play("success")
            return true
        end
        if text == "@PBRPUI:PHONE:YELLOW:BEGIN" then
            yellowPages = {}
            return true
        end
        local yellowNumber, yellowName, yellowText =
            text:match("^@PBRPUI:PHONE:YELLOW:ITEM:(%d+):([^:]+):(.*)$")
        if yellowNumber then
            yellowPages[#yellowPages + 1] = {
                number = tonumber(yellowNumber), name = yellowName, text = yellowText
            }
            return true
        end
        if text == "@PBRPUI:PHONE:YELLOW:END" then return true end
        if text == "@PBRPUI:PHONE:YELLOW:POSTED" then
            status = "Iklan berhasil dipasang."
            clearBuffer(yellowInput)
            uiSounds.play("success")
            return true
        end
        if text == "@PBRPUI:PHONE:GROUPS:BEGIN" then
            groups = {}
            return true
        end
        local groupId, groupName = text:match("^@PBRPUI:PHONE:GROUPS:ITEM:(%d+):(.*)$")
        if groupId then
            groups[#groups + 1] = { id = tonumber(groupId), name = groupName }
            return true
        end
        if text == "@PBRPUI:PHONE:GROUPS:END" then return true end
        if text == "@PBRPUI:PHONE:GROUPS:CREATED" then
            status = "Grup berhasil dibuat."
            clearBuffer(groupNameInput)
            uiSounds.play("success")
            return true
        end
        local openedGroupId, openedGroupName = text:match("^@PBRPUI:PHONE:GROUP:OPEN:(%d+):(.*)$")
        if openedGroupId then
            if activeGroupId == 0 then NS.navDir = 1 end
            activeGroupId = tonumber(openedGroupId)
            activeGroupName = openedGroupName
            groupMessages = {}
            return true
        end
        local groupMessageId = text:match("^@PBRPUI:PHONE:GROUP:MESSAGES:BEGIN:(%d+)$")
        if groupMessageId then
            if activeGroupId == 0 then NS.navDir = 1 end
            activeGroupId = tonumber(groupMessageId)
            groupMessages = {}
            return true
        end
        local senderNumber, sentAt, senderName, sentText =
            text:match("^@PBRPUI:PHONE:GROUP:MESSAGE:(%d+):(%d+):([^:]+):(.*)$")
        if senderNumber then
            groupMessages[#groupMessages + 1] = {
                number = tonumber(senderNumber), time = tonumber(sentAt),
                name = senderName, text = sentText
            }
            return true
        end
        if text == "@PBRPUI:PHONE:GROUP:MESSAGES:END" then return true end
        if text == "@PBRPUI:PHONE:GROUP:SENT" then
            clearBuffer(groupMessageInput)
            status = "Pesan grup terkirim."
            uiSounds.play("success")
            return true
        end

        if text == "@PBRPUI:PHONE:CONTACTS:BEGIN" then
            contacts = {}
            status = ""
            return true
        end

        if text == "@PBRPUI:PHONE:VEHICLES:BEGIN" then
            vehicles = {}
            return true
        end

        local vehicleId, vehicleModel, plate, vehicleStatus =
            text:match("^@PBRPUI:PHONE:VEHICLES:ITEM:(%d+):(%d+):([^:]+):(.+)$")
        if vehicleId then
            vehicles[#vehicles + 1] = {
                id = tonumber(vehicleId),
                model = tonumber(vehicleModel),
                plate = plate,
                status = vehicleStatus
            }
            return true
        end

        if text == "@PBRPUI:PHONE:VEHICLES:END" then
            return true
        end

        local slot, contactNumber, name = text:match("^@PBRPUI:PHONE:CONTACT:(%d+):(%d+):(.+)$")
        if slot then
            contacts[#contacts + 1] = {
                slot = tonumber(slot),
                number = tonumber(contactNumber),
                name = name
            }
            NS.names[tonumber(contactNumber)] = name
            return true
        end

        if text == "@PBRPUI:PHONE:CONTACTS:END" then
            return true
        end

        local messageNumber = text:match("^@PBRPUI:PHONE:MESSAGES:BEGIN:(%d+)$")
        if messageNumber then
            historyNumber = tonumber(messageNumber) or 0
            messages = {}
            scrollChatToEnd = true
            return true
        end

        local sender, timestamp, body = text:match("^@PBRPUI:PHONE:MESSAGE:(%d+):(%d+):(.+)$")
        if sender then
            messages[#messages + 1] = {
                sender = tonumber(sender),
                timestamp = tonumber(timestamp),
                body = body
            }
            NS.msgAt = os.clock()
            scrollChatToEnd = true
            return true
        end

        if text == "@PBRPUI:PHONE:MESSAGES:END" then
            status = ""
            scrollChatToEnd = true
            return true
        end

        local state, callerNumber, videoFlag =
            text:match("^@PBRPUI:PHONE:CALL:(%u+):(%d+):?(%d*)$")
        if state == "OUT" or state == "IN" or state == "ACTIVE" then
            open = true
            photoMedia.restoreCamera()
            local previousCallState = callState
            callState = state
            callNumber = tonumber(callerNumber) or 0
            videoCall = videoFlag == "1"
            videoPeer = nil
            nextVideoStatusAt = 0
            page = "call"
            if state == "IN" then
                startRingtone()
                callChatOpen = false
            elseif state == "ACTIVE" then
                stopRingtone()
                callChatOpen = true
                if previousCallState ~= "ACTIVE" then
                    sendChat("/rpui_phone_messages " .. tostring(callNumber))
                end
            else
                stopRingtone()
                callChatOpen = false
            end
            return true
        end
        local peerId, peerX, peerY, peerZ, peerInterior, peerWorld, peerActivity =
            text:match("^@PBRPUI:PHONE:VIDEO:PEER:(%d+):([%-%.%d]+):([%-%.%d]+):([%-%.%d]+):(%d+):(%d+):([^:]*)$")
        if peerId then
            videoPeer = {
                id = tonumber(peerId),
                x = tonumber(peerX),
                y = tonumber(peerY),
                z = tonumber(peerZ),
                interior = tonumber(peerInterior),
                world = tonumber(peerWorld),
                activity = peerActivity,
                updatedAt = os.clock()
            }
            return true
        end
        if text == "@PBRPUI:PHONE:CALL:CLOSED" then
            stopRingtone()
            callState = nil
            callNumber = 0
            callChatOpen = false
            clearBuffer(callMessageInput)
            videoCall = false
            videoPeer = nil
            nextVideoStatusAt = 0
            page = unlocked and "home" or "lock"
            NS.navDir = -1
            status = "Panggilan berakhir."
            return true
        end

        local sentTo = text:match("^@PBRPUI:PHONE:SMS_SENT:(%d+)$")
        if sentTo then
            status = "Pesan dikirim ke " .. sentTo .. "."
            clearBuffer(messageInput)
            if callState == "ACTIVE" and tonumber(sentTo) == callNumber then
                clearBuffer(callMessageInput)
                sendChat("/rpui_phone_messages " .. tostring(callNumber))
            end
            uiSounds.play("success")
            return true
        end

        if text == "@PBRPUI:MUSIC:PLAYLISTS:BEGIN" then
            playlists = {}
            status = ""
            return true
        end

        local playlistId, isPublic, ownerName, name =
            text:match("^@PBRPUI:MUSIC:PLAYLIST:(%d+):([01]):([^:]+):(.*)$")
        if playlistId then
            playlists[#playlists + 1] = {
                id = tonumber(playlistId),
                isPublic = isPublic == "1",
                owner = ownerName,
                name = name
            }
            return true
        end

        if text == "@PBRPUI:MUSIC:PLAYLISTS:END" then
            return true
        end

        local trackListId = text:match("^@PBRPUI:MUSIC:TRACKS:BEGIN:(%d+)$")
        if trackListId then
            selectedPlaylist = tonumber(trackListId)
            tracks = {}
            trackOrder = {}
            if musicView ~= "tracks" then NS.navDir = 1 end
            musicView = "tracks"
            return true
        end

        local trackId, title = text:match("^@PBRPUI:MUSIC:TRACK:(%d+):(.*)$")
        if trackId then
            trackId = tonumber(trackId)
            if not tracks[trackId] then
                trackOrder[#trackOrder + 1] = trackId
            end
            tracks[trackId] = tracks[trackId] or { id = trackId }
            tracks[trackId].title = title
            return true
        end

        local urlTrackId, url = text:match("^@PBRPUI:MUSIC:URL:(%d+):(.*)$")
        if urlTrackId then
            urlTrackId = tonumber(urlTrackId)
            tracks[urlTrackId] = tracks[urlTrackId] or { id = urlTrackId }
            tracks[urlTrackId].url = url
            return true
        end

        local sourceId, sharedTrackId, sharedTitle =
            text:match("^@PBRPUI:MUSIC:WORLD:START:(%d+):(%d+):(.*)$")
        if sourceId then
            stopSharedAudio()
            sharedMusic = {
                owner = tonumber(sourceId) or -1,
                track = tonumber(sharedTrackId) or 0,
                title = sharedTitle
            }
            NS.playingTrack = sharedMusic.track
            return true
        end

        local audioSource, audioUrl =
            text:match("^@PBRPUI:MUSIC:WORLD:URL:(%d+):(.*)$")
        if audioSource then
            if sharedMusic and sharedMusic.owner == tonumber(audioSource) then
                sharedMusic.url = audioUrl
                startSharedAudio(audioUrl)
            end
            return true
        end

        local stoppedSource = text:match("^@PBRPUI:MUSIC:WORLD:STOP:(%d+)$")
        if stoppedSource then
            if sharedMusic and sharedMusic.owner == tonumber(stoppedSource) then
                stopSharedAudio()
                sharedMusic = nil
                NS.playingTrack = 0
            end
            return true
        end

        local createdId = text:match("^@PBRPUI:MUSIC:CREATED:(%d+):[01]$")
        if createdId then
            status = "Playlist berhasil dibuat."
            clearBuffer(playlistName)
            uiSounds.play("success")
            return true
        end

        if text:match("^@PBRPUI:MUSIC:TRACK:ADDED:%d+$") then
            status = "Lagu berhasil ditambahkan."
            clearBuffer(trackTitle)
            clearBuffer(trackUrl)
            uiSounds.play("success")
            return true
        end

        local playingId = text:match("^@PBRPUI:MUSIC:PLAYING:(%d+)$")
        if playingId then
            NS.playingTrack = tonumber(playingId) or 0
            status = "Lagu sedang diputar."
            return true
        end

        if text == "@PBRPUI:MUSIC:STOPPED" then
            NS.playingTrack = 0
            status = "Pemutaran musik dihentikan."
            return true
        end

        return text:sub(1, 14) == "@PBRPUI:PHONE:"
            or text:sub(1, 14) == "@PBRPUI:VEHICLES"
    end

    ------------------------------------------------------------------ pages
    local pages = {}

    local function viewKey(p)
        return p .. ":" .. tostring(chatNumber or 0) .. ":" .. tostring(activeGroupId) .. ":" .. musicView
    end

    local function header(title, appId)
        local app = appById[appId or page]
        local clicked = imgui.InvisibleButton("##phone_back", V2(110, 26))
        hoverKey("##phone_back")
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        local blue = U(0.30, 0.62, 1, imgui.IsItemActive() and 0.45 or 1)
        dl:AddLine(V2(min.x + 9, min.y + 5), V2(min.x + 3, min.y + 13), blue, 2.5)
        dl:AddLine(V2(min.x + 3, min.y + 13), V2(min.x + 9, min.y + 21), blue, 2.5)
        local backLabel = (page == "music" and musicView == "tracks") and "Playlist" or "Beranda"
        dl:AddText(V2(min.x + 18, min.y + 5), blue, backLabel)
        if clicked then goBack() end
        local tp = imgui.GetCursorScreenPos()
        local availW = imgui.GetContentRegionAvail().x
        imgui.SetWindowFontScale(1.8)
        imgui.TextColored(K.white, title)
        imgui.SetWindowFontScale(1)
        if app then
            miniSquircle(imgui.GetWindowDrawList(), tp.x + availW - 34, tp.y, 32, app)
        end
        imgui.Spacing()
    end

    -- kartu notifikasi layar kunci (kaca) dengan animasi naik
    local function notifCard(dl, n, index, avail)
        local h = 66
        local clicked = imgui.InvisibleButton("##lock_notif" .. index, V2(avail, h))
        hoverKey("##lock_notif" .. index)
        local min = imgui.GetItemRectMin()
        local t = easeBack((A.t - n.at) / 0.55)
        local saved = A.gA
        A.gA = saved * math.min(1, math.max(0, t))
        local x, y = min.x, min.y + (1 - t) * 40
        dl:AddRectFilled(V2(x, y), V2(x + avail, y + h - 2), U(0.10, 0.10, 0.14, 0.66), 20)
        dl:AddRect(V2(x, y), V2(x + avail, y + h - 2), U(1, 1, 1, imgui.IsItemHovered() and 0.30 or 0.16), 20, 0, 1)
        dl:AddLine(V2(x + 18, y + 1), V2(x + avail - 18, y + 1), U(1, 1, 1, 0.14), 1)
        miniSquircle(dl, x + 12, y + 13, 38, notifApp(n.kind))
        local ago = agoText(n.stamp)
        local as = imgui.CalcTextSize(ago)
        dl:AddText(V2(x + 60, y + 11), U(1, 1, 1, 1), fitText(n.title, avail - 72 - as.x))
        dl:AddText(V2(x + avail - as.x - 12, y + 11), U(1, 1, 1, 0.50), ago)
        dl:AddText(V2(x + 60, y + 33), U(1, 1, 1, 0.80), fitText(n.body, avail - 74))
        A.gA = saved
        imgui.Dummy(V2(1, 6))
        return clicked
    end

    pages.lock = function()
        local win = imgui.GetWindowSize()
        local avail = imgui.GetContentRegionAvail().x
        local dl = imgui.GetWindowDrawList()
        local enter = ease((A.t - math.max(A.pageAt, openedAt)) / 0.55)
        local p = imgui.GetCursorScreenPos()
        local cx = p.x + avail / 2

        -- gembok
        local lc = U(1, 1, 1, 0.92)
        dl:AddRect(V2(cx - 5.5, p.y + 6), V2(cx + 5.5, p.y + 18), lc, 5.5, 0, 2)
        dl:AddRectFilled(V2(cx - 8, p.y + 14), V2(cx + 8, p.y + 28), lc, 4)
        dl:AddCircleFilled(V2(cx, p.y + 21), 2, U(0.2, 0.2, 0.3, 1), 10)
        imgui.Dummy(V2(1, 36))

        imgui.SetCursorPosY(imgui.GetCursorPosY() + (1 - enter) * 14)
        centerText(dateString(), V4(1, 1, 1, 0.88), 1.12)
        centerText(os.date("%H:%M"), K.white, 4.6)

        imgui.SetCursorPosY(imgui.GetCursorPosY() + 12)
        local shown = 0
        for i, n in ipairs(NS.notifs) do
            if i > 3 then break end
            if notifCard(dl, n, i, avail) and open and phoneEnabled then
                unlocked = true
                NS.navDir = 0
                uiSounds.play("tab")
                if n.kind == "sms" and n.number then
                    openChat(n.number)
                else
                    page = "home"
                end
            end
            shown = shown + 1
        end
        if shown == 0 then
            beginCard("##phone_lock_notice", 96, phoneEnabled
                and V4(1, 1, 1, 0.16) or V4(0.55, 0.10, 0.10, 0.60))
            imgui.TextColored(phoneEnabled and K.green or V4(1, 0.55, 0.50, 1),
                phoneEnabled and "PONSEL AKTIF" or "PONSEL MATI")
            imgui.TextWrapped(phoneEnabled
                and "Tetap terhubung dengan kontak dan warga kota lewat pesan serta panggilan."
                or "Nyalakan ponsel untuk menggunakan aplikasi dan layanan telepon.")
            imgui.TextColored(V4(1, 1, 1, 0.55), "Nomor  " .. (phoneNumber > 0 and tostring(phoneNumber) or "tidak tersedia"))
            endCard()
        end

        imgui.SetCursorPosY(win.y - 112)
        if phoneEnabled then
            local bp = imgui.GetCursorScreenPos()
            local clicked = imgui.InvisibleButton("##phone_unlock", V2(avail, 78))
            hoverKey("##phone_unlock")
            local bounce = math.sin(A.t * 3.2) * 3
            local col = U(1, 1, 1, imgui.IsItemHovered() and 1 or 0.78)
            local by = bp.y + 8 + bounce
            dl:AddLine(V2(cx - 10, by + 9), V2(cx, by), col, 2.6)
            dl:AddLine(V2(cx, by), V2(cx + 10, by + 9), col, 2.6)
            dlTextC(dl, "Klik untuk membuka", cx, bp.y + 34, col, 1.05)
            if clicked then
                unlocked = true
                NS.navDir = 0
                page = "home"
                uiSounds.play("tab")
            end
        elseif pillButton("NYALAKAN HANDPHONE##phone_power", -1, 46, "success") then
            sendChat("/rpui_phone_power")
        end
        drawStatus()
    end

    pages.home = function()
        local win = imgui.GetWindowSize()
        local avail = imgui.GetContentRegionAvail().x
        local dl = imgui.GetWindowDrawList()
        local enter = ease((A.t - math.max(A.pageAt, openedAt)) / 0.5)
        local gap = 12
        local wsz = (avail - gap) / 2
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(avail, wsz))

        local inset = wsz * (1 - (0.88 + 0.12 * enter)) / 2
        local saved = A.gA
        A.gA = saved * enter

        -- widget jam analog
        local x0, y0 = p.x + inset, p.y + inset
        local x1, y1 = p.x + wsz - inset, p.y + wsz - inset
        dl:AddRectFilled(V2(x0, y0), V2(x1, y1), U(1, 1, 1, 0.17), 24)
        dl:AddRect(V2(x0, y0), V2(x1, y1), U(1, 1, 1, 0.14), 24, 0, 1)
        local ccx, ccy = (x0 + x1) / 2, (y0 + y1) / 2
        local cr = (x1 - x0) / 2 - 14
        dl:AddCircleFilled(V2(ccx, ccy), cr, U(0, 0, 0, 0.32), 48)
        for i = 0, 11 do
            local a = i / 12 * math.pi * 2
            local major = i % 3 == 0
            local r0 = cr * (major and 0.80 or 0.87)
            dl:AddLine(V2(ccx + math.cos(a) * r0, ccy + math.sin(a) * r0),
                V2(ccx + math.cos(a) * cr * 0.95, ccy + math.sin(a) * cr * 0.95),
                U(1, 1, 1, major and 0.95 or 0.50), major and 2.2 or 1.2)
        end
        local tm = os.date("*t")
        local ha = ((tm.hour % 12) + tm.min / 60) / 12 * math.pi * 2 - math.pi / 2
        local ma = (tm.min + tm.sec / 60) / 60 * math.pi * 2 - math.pi / 2
        local sa = tm.sec / 60 * math.pi * 2 - math.pi / 2
        dl:AddLine(V2(ccx, ccy), V2(ccx + math.cos(ha) * cr * 0.50, ccy + math.sin(ha) * cr * 0.50), U(1, 1, 1, 1), 3.4)
        dl:AddLine(V2(ccx, ccy), V2(ccx + math.cos(ma) * cr * 0.76, ccy + math.sin(ma) * cr * 0.76), U(1, 1, 1, 1), 2.4)
        dl:AddLine(V2(ccx - math.cos(sa) * cr * 0.14, ccy - math.sin(sa) * cr * 0.14),
            V2(ccx + math.cos(sa) * cr * 0.84, ccy + math.sin(sa) * cr * 0.84), U(1, 0.60, 0.04, 1), 1.4)
        dl:AddCircleFilled(V2(ccx, ccy), 3.4, U(1, 0.60, 0.04, 1), 14)

        -- widget kalender
        local qx0, qy0 = p.x + wsz + gap + inset, p.y + inset
        local qx1, qy1 = p.x + wsz * 2 + gap - inset, p.y + wsz - inset
        dl:AddRectFilled(V2(qx0, qy0), V2(qx1, qy1), U(1, 1, 1, 0.17), 24)
        dl:AddRect(V2(qx0, qy0), V2(qx1, qy1), U(1, 1, 1, 0.14), 24, 0, 1)
        local qcx = (qx0 + qx1) / 2
        dlTextC(dl, string.upper(DAYS[tm.wday]), qcx, qy0 + 14, U(1, 0.36, 0.31, 1), 1.0)
        dlTextC(dl, tostring(tm.day), qcx, qy0 + 32, U(1, 1, 1, 1), 3.2)
        dlTextC(dl, MONTHS[tm.month], qcx, qy0 + 82, U(1, 1, 1, 0.80), 1.0)
        dlTextC(dl, phoneNumber > 0 and ("+" .. phoneNumber) or "-", qcx, qy1 - 22, U(1, 1, 1, 0.55), 0.9)
        A.gA = saved

        imgui.Dummy(V2(1, 6))
        local cols, cgap = 4, 4
        local cellW = (imgui.GetContentRegionAvail().x - cgap * (cols - 1)) / cols
        local n = 0
        for _, app in ipairs(apps) do
            if not inDock[app.id] then
                if n % cols ~= 0 then imgui.SameLine(0, cgap) end
                if drawAppIcon(app, cellW, 84, true, n) then phoneAction(app.id) end
                n = n + 1
            end
        end

        -- titik halaman
        imgui.SetCursorPosY(win.y - 112)
        local dp = imgui.GetCursorScreenPos()
        dl:AddCircleFilled(V2(dp.x + avail / 2 - 7, dp.y + 4), 3.2, U(1, 1, 1, 0.95), 12)
        dl:AddCircleFilled(V2(dp.x + avail / 2 + 7, dp.y + 4), 3.2, U(1, 1, 1, 0.38), 12)

        -- dock kaca
        imgui.SetCursorPosY(win.y - 92)
        local dockW = imgui.GetContentRegionAvail().x
        local dpos = imgui.GetCursorScreenPos()
        dl:AddRectFilled(dpos, V2(dpos.x + dockW, dpos.y + 80), U(1, 1, 1, 0.20), 28)
        dl:AddRect(dpos, V2(dpos.x + dockW, dpos.y + 80), U(1, 1, 1, 0.16), 28, 0, 1)
        imgui.SetCursorScreenPos(V2(dpos.x + 10, dpos.y + 11))
        local dockCell = (dockW - 20 - cgap * 3) / 4
        for i, id in ipairs(dockOrder) do
            if i > 1 then imgui.SameLine(0, cgap) end
            if drawAppIcon(appById[id], dockCell, 60, false, 12 + i) then phoneAction(id) end
        end
        drawStatus()
    end

    pages.contacts = function()
        header("Kontak")
        imgui.TextColored(K.muted, "Kontak tersimpan: " .. #contacts)
        imgui.Spacing()
        local avail = imgui.GetContentRegionAvail().x
        for index, contact in ipairs(contacts) do
            pushId(contact.slot)
            local clicked, min, _, dl = rowButton("##contact_row", avail - 84, 56)
            avatar(dl, min.x + 24, min.y + 28, 19, contact.name)
            local unread = NS.unread[contact.number]
            if unread and unread > 0 then
                dl:AddCircleFilled(V2(min.x + 38, min.y + 12), 7, U(1, 0.23, 0.19, 1), 14)
            end
            dl:AddText(V2(min.x + 52, min.y + 10), U(0.96, 0.97, 1, 1), fitText(contact.name, avail - 150))
            dl:AddText(V2(min.x + 52, min.y + 29), U(0.62, 0.67, 0.76, 1), tostring(contact.number))
            dl:AddLine(V2(min.x + 52, min.y + 55), V2(min.x + avail - 84, min.y + 55), U(1, 1, 1, 0.06), 1)
            if clicked then openChat(contact.number) end
            imgui.SameLine(0, 0)
            if circleButton("##contact_call" .. index, 34, KIND.success[1], KIND.success[2], "phone", 42, 56) then
                sendChat("/rpui_phone_call " .. contact.number)
            end
            imgui.SameLine(0, 0)
            if circleButton("##contact_sms" .. index, 34, KIND.primary[1], KIND.primary[2], "chat", 42, 56) then
                openChat(contact.number)
            end
            imgui.PopID()
        end
        if #contacts == 0 then
            imgui.TextColored(K.muted, "Belum ada kontak tersimpan.")
        end
        imgui.Spacing()
        beginCard("##phone_contact_add", 134, K.glass)
        imgui.TextColored(K.muted, "Tambah kontak")
        imgui.SetNextItemWidth(104)
        styledInput("##contact_new_number", "Nomor", selectedNumber)
        imgui.SameLine()
        imgui.SetNextItemWidth(-1)
        styledInput("##contact_new_name", "Nama kontak", contactName)
        if pillButton("SIMPAN KONTAK##phone_contact_add", -1, 34, "primary") then
            local number = ffi.string(selectedNumber):match("^%s*(.-)%s*$")
            local name = ffi.string(contactName):match("^%s*(.-)%s*$")
            if number:match("^%d+$") and name ~= "" then
                sendChat("/rpui_phone_contact_add " .. number .. " " .. name)
                status = "Menyimpan kontak..."
                clearBuffer(contactName)
            else
                status = "Masukkan nomor dan nama kontak."
            end
        end
        endCard()
        drawStatus()
    end

    pages.dialer = function()
        header("Telepon")
        local number = ffi.string(dialNumber)
        imgui.Dummy(V2(1, 2))
        if number == "" then
            centerText("Masukkan nomor", V4(0.60, 0.60, 0.66, 0.85), 1.2)
            imgui.Dummy(V2(1, 20))
        else
            centerText(number, K.white, 2.2)
            local known = number:match("^%d+$") and contactLabel(tonumber(number)) or nil
            if known then
                centerText(known, V4(0.30, 0.62, 1, 1), 1.0)
                imgui.Dummy(V2(1, 4))
            else
                imgui.Dummy(V2(1, 20))
            end
        end
        imgui.Dummy(V2(1, 2))

        local avail = imgui.GetContentRegionAvail().x
        local d = math.min(70, (avail - 36) / 3)
        local gap = (avail - d * 3) / 2
        for i, key in ipairs(KEYS) do
            if (i - 1) % 3 ~= 0 then imgui.SameLine(0, gap) end
            if keyButton("##key" .. key[1], d, key[1], key[2]) then dialAppend(key[1]) end
            if i % 3 == 0 then imgui.Dummy(V2(1, 0)) end
        end
        imgui.Dummy(V2(d, d))
        imgui.SameLine(0, gap)
        if keyButton("##key0", d, "0", "+") then dialAppend("0") end
        imgui.Dummy(V2(1, 0))

        imgui.Dummy(V2(d, d))
        imgui.SameLine(0, gap)
        if circleButton("##dial_call", d, KIND.success[1], KIND.success[2], "phone") then
            local dialed = ffi.string(dialNumber):match("^%s*(.-)%s*$")
            if dialed:match("^%d+$") then
                sendChat("/rpui_phone_call " .. dialed)
                status = "Memanggil " .. dialed .. "..."
            else
                status = "Masukkan nomor telepon berupa angka."
            end
        end
        imgui.SameLine(0, gap)
        if imgui.InvisibleButton("##dial_back", V2(d, d)) then dialBackspace() end
        hoverKey("##dial_back")
        if number ~= "" then
            local min, max = imgui.GetItemRectMin(), imgui.GetItemRectMax()
            local dl = imgui.GetWindowDrawList()
            local cx, cy = (min.x + max.x) / 2, (min.y + max.y) / 2
            local col = U(1, 1, 1, imgui.IsItemActive() and 0.55 or 0.92)
            dl:AddLine(V2(cx - 13, cy), V2(cx - 5, cy - 9), col, 2)
            dl:AddLine(V2(cx - 5, cy - 9), V2(cx + 13, cy - 9), col, 2)
            dl:AddLine(V2(cx + 13, cy - 9), V2(cx + 13, cy + 9), col, 2)
            dl:AddLine(V2(cx + 13, cy + 9), V2(cx - 5, cy + 9), col, 2)
            dl:AddLine(V2(cx - 5, cy + 9), V2(cx - 13, cy), col, 2)
            dl:AddLine(V2(cx - 1, cy - 4), V2(cx + 7, cy + 4), col, 2)
            dl:AddLine(V2(cx - 1, cy + 4), V2(cx + 7, cy - 4), col, 2)
        end
        drawStatus()
    end

    pages.messages = function()
        if not chatNumber then
            header("Pesan")
            beginCard("##phone_newchat", 106, K.glass)
            imgui.TextColored(K.muted, "Chat baru")
            imgui.SetNextItemWidth(-1)
            styledInput("##phone_sms_number", "Nomor tujuan", selectedNumber)
            if pillButton("BUKA CHAT##phone_load_messages", -1, 30, "primary") then
                local number = ffi.string(selectedNumber):match("^%s*(.-)%s*$")
                if number:match("^%d+$") then
                    openChat(tonumber(number))
                else
                    status = "Masukkan nomor tujuan terlebih dahulu."
                end
            end
            endCard()
            imgui.Spacing()
            imgui.TextColored(K.muted, "Kontak")
            local avail = imgui.GetContentRegionAvail().x
            for _, contact in ipairs(contacts) do
                pushId("chatcontact" .. contact.slot)
                local clicked, min, _, dl = rowButton("##chat_row", avail, 56)
                avatar(dl, min.x + 26, min.y + 28, 20, contact.name)
                local unread = NS.unread[contact.number] or 0
                dl:AddText(V2(min.x + 56, min.y + 10), U(0.97, 0.97, 1, 1), fitText(contact.name, avail - 100))
                dl:AddText(V2(min.x + 56, min.y + 30), U(0.60, 0.60, 0.66, 1), tostring(contact.number))
                if unread > 0 then
                    dl:AddCircleFilled(V2(min.x + avail - 18, min.y + 28), 10, U(0.04, 0.52, 1, 1), 18)
                    local txt = tostring(math.min(unread, 99))
                    local ts = imgui.CalcTextSize(txt)
                    dl:AddText(V2(min.x + avail - 18 - ts.x / 2, min.y + 28 - ts.y / 2), U(1, 1, 1, 1), txt)
                end
                dl:AddLine(V2(min.x + 56, min.y + 55), V2(min.x + avail, min.y + 55), U(1, 1, 1, 0.06), 1)
                if clicked then openChat(contact.number) end
                imgui.PopID()
            end
            if #contacts == 0 then
                imgui.TextColored(K.muted, "Belum ada kontak. Masukkan nomor di atas.")
            end
            drawStatus()
            return
        end

        -- percakapan
        local number = chatNumber
        local name = contactLabel(number) or tostring(number)
        local availW = imgui.GetContentRegionAvail().x
        if circleButton("##phone_chat_back", 30, V4(1, 1, 1, 0.12), V4(1, 1, 1, 0.20), nil, 34, 38) then
            goBack()
        end
        do
            local min = imgui.GetItemRectMin()
            local dl = imgui.GetWindowDrawList()
            local cx, cy = min.x + 17, min.y + 19
            local col = U(0.30, 0.62, 1, 1)
            dl:AddLine(V2(cx + 3, cy - 7), V2(cx - 3, cy), col, 2.4)
            dl:AddLine(V2(cx - 3, cy), V2(cx + 3, cy + 7), col, 2.4)
        end
        imgui.SameLine(0, 6)
        local ap = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(38, 38))
        avatar(imgui.GetWindowDrawList(), ap.x + 19, ap.y + 19, 18, name)
        imgui.SameLine(0, 8)
        imgui.BeginGroup()
        imgui.TextColored(K.white, fitText(name, availW - 190))
        imgui.TextColored(K.muted, tostring(number))
        imgui.EndGroup()
        imgui.SameLine(imgui.GetWindowSize().x - 14 - 80)
        if circleButton("##chat_call", 32, KIND.success[1], KIND.success[2], "phone", 38, 38) then
            sendChat("/rpui_phone_call " .. number)
        end
        imgui.SameLine(0, 2)
        if circleButton("##chat_video", 32, KIND.primary[1], KIND.primary[2], "phone", 38, 38) then
            sendChat("/rpui_phone_call " .. number .. " video")
            videoCall = true
            status = "Memulai panggilan video roleplay..."
        end
        imgui.Separator()

        local histH = math.max(80, imgui.GetContentRegionAvail().y - 62)
        imgui.PushStyleColor(imgui.Col.ChildBg, K.clear)
        imgui.BeginChild("##phone_message_history", V2(-1, histH), false)
        if historyNumber == number then
            local avail = imgui.GetContentRegionAvail().x
            for index, message in ipairs(messages) do
                local mine = message.sender == phoneNumber
                local maxText = avail * 0.72 - 20
                local ok, ts = pcall(imgui.CalcTextSize, message.body, nil, false, maxText)
                if not ok then
                    ts = V2(math.min(maxText, #message.body * 7),
                        15 * math.ceil(#message.body * 7 / maxText))
                end
                local bw = math.max(66, ts.x + 26)
                local bh = ts.y + 36
                local isLast = index == #messages
                local pop = isLast and ease((A.t - NS.msgAt) / 0.30) or 1
                if mine then imgui.SetCursorPosX(math.max(0, avail - bw)) end
                if pop < 1 then
                    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(0.05, A.gA * pop))
                end
                imgui.PushStyleColor(imgui.Col.ChildBg, mine and K.blue or V4(0.16, 0.165, 0.19, 1))
                imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 18)
                imgui.BeginChild("##phone_bubble_" .. index, V2(bw, bh), false)
                imgui.SetCursorPos(V2(12, 7))
                imgui.PushTextWrapPos(bw - 12)
                imgui.TextColored(K.white, message.body)
                imgui.PopTextWrapPos()
                local okTime, clock = pcall(os.date, "%H:%M", message.timestamp)
                imgui.SetCursorPos(V2(12, bh - 20))
                imgui.TextColored(V4(1, 1, 1, 0.50), okTime and clock or "")
                imgui.EndChild()
                imgui.PopStyleVar(1)
                imgui.PopStyleColor(1)
                if pop < 1 then imgui.PopStyleVar(1) end
                imgui.Dummy(V2(1, 3))
            end
            if #messages == 0 then
                imgui.TextColored(K.muted, "Belum ada pesan dengan nomor ini.")
            end
            if scrollChatToEnd then
                imgui.SetScrollHereY(1)
                scrollChatToEnd = false
            end
        else
            imgui.TextColored(K.muted, "Memuat percakapan...")
        end
        imgui.EndChild()
        imgui.PopStyleColor(1)

        local function sendSms()
            local message = ffi.string(messageInput):match("^%s*(.-)%s*$")
            if message ~= "" and #message <= 100 then
                sendChat("/rpui_phone_sms " .. number .. " " .. message)
                status = "Mengirim pesan..."
            else
                status = "Nomor atau isi pesan tidak valid."
            end
        end
        imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 46)
        styledInput("##phone_sms_message", "iMessage (maks. 100 karakter)", messageInput)
        imgui.SameLine(0, 6)
        if circleButton("##phone_sms", 36, KIND.primary[1], KIND.primary[2], nil) then
            sendSms()
        end
        do
            local min, max = imgui.GetItemRectMin(), imgui.GetItemRectMax()
            local dl = imgui.GetWindowDrawList()
            local cx, cy = (min.x + max.x) / 2, (min.y + max.y) / 2
            local col = U(1, 1, 1, 1)
            dl:AddLine(V2(cx, cy + 7), V2(cx, cy - 7), col, 2.4)
            dl:AddLine(V2(cx - 6, cy - 1), V2(cx, cy - 7), col, 2.4)
            dl:AddLine(V2(cx + 6, cy - 1), V2(cx, cy - 7), col, 2.4)
        end
        if status ~= "" then
            imgui.PushStyleColor(imgui.Col.Text, K.warn)
            imgui.Text(fitText(status, imgui.GetContentRegionAvail().x))
            imgui.PopStyleColor()
        end
    end

    pages.call = function()
        local avail = imgui.GetContentRegionAvail().x
        local dl = imgui.GetWindowDrawList()
        local label = contactLabel(callNumber) or tostring(callNumber)
        if videoCall and callState == "ACTIVE" and os.clock() >= nextVideoStatusAt then
            sendChat("/rpui_phone_video_status")
            nextVideoStatusAt = os.clock() + 1
        end
        local title = callState == "IN" and "Panggilan masuk..."
            or (callState == "ACTIVE" and "Terhubung" or "Memanggil...")
        if callState == "ACTIVE" and A.callSince then
            local sec = math.floor(A.t - A.callSince)
            title = string.format("%02d:%02d", math.floor(sec / 60), sec % 60)
        end
        imgui.Dummy(V2(1, 12))
        centerText(label, K.white, 1.95)
        centerText((videoCall and "Video RP  -  " or "") .. title, V4(1, 1, 1, 0.66), 1.05)
        centerText(callState == "ACTIVE" and "Voice aktif - gunakan tombol mic voice Anda"
            or "Voice tersambung setelah panggilan dijawab", V4(0.65, 0.70, 0.78, 0.85), 0.82)

        local p = imgui.GetCursorScreenPos()
        local cx = p.x + avail / 2
        if videoCall then
            local size = V2(avail, 210)
            imgui.Dummy(size)
            dl:AddRectFilled(V2(p.x, p.y + 10), V2(p.x + size.x, p.y + 10 + size.y), U(0.06, 0.08, 0.12, 1), 20)
            dl:AddRect(V2(p.x, p.y + 10), V2(p.x + size.x, p.y + 10 + size.y), U(1, 1, 1, 0.12), 20, 0, 1)
            avatar(dl, cx, p.y + 58, 30, label)
            local now = os.clock()
            local live = callState == "ACTIVE" and videoPeer and now - videoPeer.updatedAt <= 4
            local liveColor = live and U(0.20, 0.88, 0.50, 1) or U(0.75, 0.78, 0.84, 1)
            dl:AddCircleFilled(V2(p.x + 18, p.y + 108), 3.5, liveColor, 12)
            dl:AddText(V2(p.x + 27, p.y + 101), liveColor, live and "LIVE RP" or "MENUNGGU DATA")
            if live then
                local activity = fitText(videoPeer.activity, avail - 32)
                local position = string.format("X %.1f  Y %.1f  Z %.1f", videoPeer.x, videoPeer.y, videoPeer.z)
                dl:AddText(V2(p.x + 16, p.y + 124), U(0.96, 0.97, 1, 1), activity)
                dl:AddText(V2(p.x + 16, p.y + 147), U(0.72, 0.76, 0.83, 1), position)
                dl:AddText(V2(p.x + 16, p.y + 169), U(0.62, 0.66, 0.74, 1),
                    string.format("Dunia %d  /  Interior %d", videoPeer.world, videoPeer.interior))
            elseif callState == "ACTIVE" then
                dl:AddText(V2(p.x + 16, p.y + 126), U(0.78, 0.81, 0.87, 1), "Meminta posisi dan aktivitas partner...")
            else
                dl:AddText(V2(p.x + 16, p.y + 126), U(0.78, 0.81, 0.87, 1), "Video aktif setelah panggilan dijawab.")
            end
            dl:AddText(V2(p.x + 16, p.y + 190), U(0.52, 0.56, 0.64, 1),
                "Data live RP; stream gambar pemain tidak tersedia.")
        else
            imgui.Dummy(V2(1, 220))
            local cy = p.y + 112
            for i = 0, 2 do
                local ph = (A.t * 0.55 + i / 3) % 1
                dl:AddCircle(V2(cx, cy), 54 + ph * 48, U(1, 1, 1, (1 - ph) * 0.22), 56, 2)
            end
            avatar(dl, cx, cy, 54, label)
        end

        imgui.Dummy(V2(1, 10))
        local d = 66
        local rects = {}
        if callState == "IN" then
            imgui.SetCursorPosX(imgui.GetCursorPosX() + (avail - d * 2 - 60) / 2)
            if circleButton("##phone_reject", d, KIND.danger[1], KIND.danger[2], "phone") then
                sendChat("/rpui_phone_end")
            end
            rects[1] = { imgui.GetItemRectMin(), imgui.GetItemRectMax(), "Tolak" }
            imgui.SameLine(0, 60)
            if circleButton("##phone_answer", d, KIND.success[1], KIND.success[2], "phone") then
                sendChat("/rpui_phone_answer")
                status = "Menghubungkan panggilan..."
            end
            rects[2] = { imgui.GetItemRectMin(), imgui.GetItemRectMax(), "Terima" }
        else
            imgui.SetCursorPosX(imgui.GetCursorPosX() + (avail - d) / 2)
            if circleButton("##phone_hangup", d, KIND.danger[1], KIND.danger[2], "phone") then
                sendChat("/rpui_phone_end")
            end
            rects[1] = { imgui.GetItemRectMin(), imgui.GetItemRectMax(), "Akhiri" }
        end
        for _, r in ipairs(rects) do
            dlTextC(dl, r[3], (r[1].x + r[2].x) / 2, r[2].y + 6, U(1, 1, 1, 0.85), 0.95)
        end
        if callState == "ACTIVE" then
            imgui.Spacing()
            beginCard("##phone_call_chat", callChatOpen and 188 or 48, K.glass)
            if pillButton(callChatOpen and "SEMBUNYIKAN CHAT##phone_call_chat_toggle"
                or "BUKA CHAT##phone_call_chat_toggle", -1, 30, "primary") then
                callChatOpen = not callChatOpen
                if callChatOpen and historyNumber ~= callNumber then
                    sendChat("/rpui_phone_messages " .. tostring(callNumber))
                end
            end
            if callChatOpen then
                imgui.BeginChild("##phone_call_chat_history", V2(-1, 76), false)
                if historyNumber == callNumber then
                    for index = math.min(3, #messages), 1, -1 do
                        local message = messages[index]
                        local sender = message.sender == phoneNumber and "Kamu"
                            or (contactLabel(message.sender) or tostring(message.sender))
                        imgui.PushTextWrapPos(-1)
                        imgui.TextWrapped(sender .. ": " .. message.body)
                        imgui.PopTextWrapPos()
                    end
                    if #messages == 0 then
                        imgui.TextColored(K.muted, "Belum ada chat dalam panggilan ini.")
                    end
                    if scrollChatToEnd then
                        imgui.SetScrollHereY(1)
                        scrollChatToEnd = false
                    end
                else
                    imgui.TextColored(K.muted, "Memuat chat panggilan...")
                end
                imgui.EndChild()
                imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 76)
                styledInput("##phone_call_message", "Ketik pesan...", callMessageInput)
                imgui.SameLine(0, 6)
                if pillButton("KIRIM##phone_call_message_send", 62, 30, "success") then
                    local message = ffi.string(callMessageInput):match("^%s*(.-)%s*$")
                    if message ~= "" and #message <= 128 then
                        sendChat("/rpui_phone_sms " .. tostring(callNumber) .. " " .. message)
                        status = "Mengirim chat panggilan..."
                    else
                        status = "Isi chat tidak boleh kosong."
                    end
                end
            end
            endCard()
        end
        imgui.Dummy(V2(1, 22))
        drawStatus()
    end

    pages.camera = function()
        header("Kamera")
        local avail = imgui.GetContentRegionAvail()
        local vfH = math.max(115, avail.y - 225)
        local timerSeconds = cameraTimerModes[cameraTimerIndex]
        local timerLabel = timerSeconds == 0 and "TIMER OFF" or ("TIMER " .. timerSeconds .. "s")

        imgui.TextColored(V4(1, 0.84, 0.04, 1), "SAO CAMERA")
        imgui.SameLine()
        imgui.TextColored(K.muted, "FOTO LOKAL")
        imgui.SameLine(imgui.GetContentRegionAvail().x - 4)
        imgui.TextColored(K.muted, "FOV")
        local toolbarWidth = (avail.x - 12) / 3
        if pillButton(timerLabel .. "##phone_camera_timer", toolbarWidth, 28,
            timerSeconds == 0 and "glass" or "primary") then
            cameraTimerIndex = cameraTimerIndex % #cameraTimerModes + 1
            timerSeconds = cameraTimerModes[cameraTimerIndex]
        end
        imgui.SameLine(0, 6)
        if pillButton((cameraGridEnabled and "GRID ON" or "GRID OFF") .. "##phone_camera_grid",
            toolbarWidth, 28, cameraGridEnabled and "primary" or "glass") then
            cameraGridEnabled = not cameraGridEnabled
        end
        imgui.SameLine(0, 6)
        if pillButton((cameraTagsEnabled and "TAGS ON" or "TAGS OFF") .. "##phone_camera_tags",
            toolbarWidth, 28, cameraTagsEnabled and "primary" or "glass") then
            cameraTagsEnabled = not cameraTagsEnabled
        end

        imgui.Spacing()
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(avail.x, vfH))
        local dl = imgui.GetWindowDrawList()
        local x0, y0, x1, y1 = p.x, p.y, p.x + avail.x, p.y + vfH
        gradientRounded(dl, x0, y0, avail.x, vfH, 20, U(0.07, 0.07, 0.09, 1), U(0.01, 0.01, 0.02, 1))
        dl:AddRect(V2(x0, y0), V2(x1, y1), U(1, 1, 1, 0.12), 20, 0, 1)
        if cameraGridEnabled then
            local gc = U(1, 1, 1, 0.20)
            for i = 1, 2 do
                dl:AddLine(V2(x0 + avail.x * i / 3, y0 + 12),
                    V2(x0 + avail.x * i / 3, y1 - 12), gc, 1)
                dl:AddLine(V2(x0 + 12, y0 + vfH * i / 3),
                    V2(x1 - 12, y0 + vfH * i / 3), gc, 1)
            end
        end
        local cx, cy = (x0 + x1) / 2, (y0 + y1) / 2
        local fs = 38 + math.sin(A.t * 2.4) * 2
        dl:AddCircle(V2(cx, cy), fs, U(1, 0.84, 0.04, 0.75), 48, 1.6)
        dl:AddRectFilled(V2(cx - 16, y1 - 52), V2(cx + 16, y1 - 30), U(0, 0, 0, 0.45), 11)
        dlTextC(dl, tostring(photoMedia.zoom()) .. "x", cx, y1 - 49, U(1, 0.84, 0.04, 1), 0.95)
        dl:AddRectFilled(V2(x0 + 12, y0 + 12), V2(x0 + 102, y0 + 34), U(0, 0, 0, 0.42), 11)
        dlText(dl, "SAO CAMERA", x0 + 21, y0 + 16, U(1, 1, 1, 0.88), 0.78)
        if cameraTagsEnabled then
            dl:AddRectFilled(V2(x1 - 94, y0 + 12), V2(x1 - 12, y0 + 34), U(0, 0, 0, 0.42), 11)
            dlTextC(dl, "TAGS", x1 - 53, y0 + 16, U(1, 0.84, 0.04, 0.95), 0.78)
        end
        dlTextC(dl, "KONTROL FOTO GAME • HASIL VIA F8", cx, cy + fs + 12,
            U(1, 1, 1, 0.66), 0.76)
        local flash = 1 - (A.t - A.shutterAt) / 0.28
        if flash > 0 then dl:AddRectFilled(V2(x0, y0), V2(x1, y1), U(1, 1, 1, flash * 0.85), 20) end

        imgui.Spacing()
        local zoomChoices = { 0.5, 1, 2 }
        local zoomWidth = (avail.x - 16) / #zoomChoices
        for index, value in ipairs(zoomChoices) do
            if index > 1 then imgui.SameLine(0, 8) end
            local label = (value == 0.5 and "0,5x" or tostring(value) .. "x")
                .. "##phone_zoom_" .. tostring(value)
            if pillButton(label, zoomWidth, 28, photoMedia.zoom() == value and "primary" or "glass") then
                photoMedia.setZoom(value)
            end
        end
        imgui.TextColored(K.muted, "POSE KARAKTER")
        local poses = {
            { label = "Santai", anim = "Santai" },
            { label = "Melambai", anim = "Lambai" },
            { label = "Duduk", anim = "Duduk" }
        }
        local poseWidth = (avail.x - 12) / #poses
        for index, pose in ipairs(poses) do
            if index > 1 then imgui.SameLine(0, 6) end
            if pillButton(pose.label .. "##phone_pose_" .. pose.anim, poseWidth, 26, "glass") then
                sendChat("/e " .. pose.anim)
                cameraActionStatus = "Pose " .. pose.label .. " dikirim; karakter harus di kaki."
            end
        end
        imgui.Dummy(V2(1, 2))
        local busy = photoMedia.isBusy()
        local controlsWidth = avail.x
        local sideWidth = 64
        local d = 56
        imgui.SetCursorPosX(imgui.GetCursorPosX() + (controlsWidth - sideWidth * 2 - d) / 2)
        if pillButton("ALBUM##phone_camera_album", sideWidth, 38, "glass") then
            photoMedia.refresh()
            selectedPhoto = 1
            page = "photos"
            cameraCaptureAt = nil
        end
        imgui.SameLine(0, 12)
        local clicked = imgui.InvisibleButton("##phone_camera", V2(d, d))
        hoverKey("##phone_camera")
        local min = imgui.GetItemRectMin()
        local sc = V2(min.x + d / 2, min.y + d / 2)
        dl:AddCircle(sc, d / 2 - 1, U(1, 1, 1, 0.96), 48, 3.2)
        dl:AddCircleFilled(sc, (d / 2 - 8) * (imgui.IsItemActive() and 0.86 or 1),
            busy and U(0.55, 0.57, 0.62, 1) or U(1, 1, 1, 1), 40)
        if clicked and not busy then
            cameraActionStatus = ""
            local delay = cameraTimerModes[cameraTimerIndex]
            if delay > 0 then
                cameraCaptureAt = os.clock() + delay
            else
                photoMedia.capture()
                A.shutterAt = A.t
            end
        end
        imgui.SameLine(0, 12)
        if pillButton("POSE##phone_camera_pose", sideWidth, 38, "glass") then
            sendChat("/e Santai")
            cameraActionStatus = "Pose Santai dikirim; karakter harus di kaki."
        end
        if cameraCaptureAt then
            local remaining = cameraCaptureAt - os.clock()
            if remaining <= 0 then
                cameraCaptureAt = nil
                photoMedia.capture()
                A.shutterAt = A.t
            else
                status = string.format("Foto diambil dalam %d detik...", math.ceil(remaining))
            end
        end
        if photoMedia.cameraStatus() ~= "" then
            status = photoMedia.cameraStatus()
        elseif cameraActionStatus ~= "" then
            status = cameraActionStatus
        elseif cameraCaptureAt then
            status = string.format("Foto diambil dalam %d detik...",
                math.ceil(math.max(0, cameraCaptureAt - os.clock())))
        else
            status = photoMedia.status()
        end
        drawStatus()
    end

    pages.photos = function()
        header("Foto")
        if pillButton("SEGARKAN ALBUM##phone_photos_refresh", -1, 32, "glass") then
            photoMedia.refresh()
        end
        local localPhotos = photoMedia.photos()
        imgui.TextColored(K.muted, "Foto lokal: " .. #localPhotos)
        local budget = 2
        local function texture(photo)
            local tex = photoTextures[photo.path]
            if tex ~= nil then return tex or nil end
            if budget <= 0 then return nil end
            budget = budget - 1
            local ok, loaded = pcall(imgui.CreateTextureFromFile, photo.path)
            photoTextures[photo.path] = (ok and loaded) or false
            return photoTextures[photo.path] or nil
        end
        if #localPhotos == 0 then
            imgui.Spacing()
            imgui.TextColored(K.muted, "Album kosong. Ambil foto dari aplikasi Kamera.")
        else
            if selectedPhoto > #localPhotos then selectedPhoto = 1 end
            local avail = imgui.GetContentRegionAvail().x
            local current = localPhotos[selectedPhoto]
            local p = imgui.GetCursorScreenPos()
            imgui.Dummy(V2(avail, 168))
            local dl = imgui.GetWindowDrawList()
            dl:AddRectFilled(p, V2(p.x + avail, p.y + 168), U(0.04, 0.05, 0.07, 1), 14)
            local tex = texture(current)
            if tex then dl:AddImage(tex, p, V2(p.x + avail, p.y + 168)) end
            dl:AddRect(p, V2(p.x + avail, p.y + 168), U(1, 1, 1, 0.14), 14, 0, 1)
            local counter = selectedPhoto .. " / " .. #localPhotos
            local cs = imgui.CalcTextSize(counter)
            dl:AddRectFilled(V2(p.x + avail - cs.x - 22, p.y + 10), V2(p.x + avail - 10, p.y + 32), U(0, 0, 0, 0.5), 11)
            dl:AddText(V2(p.x + avail - cs.x - 16, p.y + 14), U(1, 1, 1, 0.95), counter)
            imgui.Spacing()

            local columns, gap = 3, 6
            local cellW = (avail - gap * (columns - 1)) / columns
            local cellH = cellW * 0.78
            for index, photo in ipairs(localPhotos) do
                if (index - 1) % columns ~= 0 then imgui.SameLine(0, gap) end
                pushId(index)
                local clicked = imgui.InvisibleButton("##photo", V2(cellW, cellH))
                hoverKey("##photo" .. index)
                local min, max = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                local drawList = imgui.GetWindowDrawList()
                local thumb = texture(photo)
                if thumb then
                    drawList:AddImage(thumb, min, max)
                else
                    drawList:AddRectFilled(min, max, U(0.12, 0.14, 0.19, 1), 6)
                end
                drawList:AddRect(min, max, index == selectedPhoto
                    and U(0.38, 0.64, 1, 1) or U(1, 1, 1, 0.18), 6, 0, index == selectedPhoto and 2 or 1)
                if clicked then selectedPhoto = index end
                imgui.PopID()
            end
        end
        status = photoMedia.status()
        drawStatus()
    end

    local function money(value)
        local amount = math.floor(tonumber(value) or 0)
        local digits = tostring(math.abs(amount)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("%.$", "")
        return "Rp " .. (amount < 0 and "-" or "") .. digits
    end

    pages.information = function()
        header("Informasi")
        if pillButton("SEGARKAN DATA##phone_info_refresh", -1, 32, "glass") then
            phoneInfo = nil
            sendChat("/rpui_phone_info")
        end
        if not phoneInfo then
            imgui.Spacing()
            imgui.TextColored(K.muted, "Memuat data karakter...")
        else
            -- kartu profil
            local avail = imgui.GetContentRegionAvail().x
            local p = imgui.GetCursorScreenPos()
            imgui.Dummy(V2(avail, 78))
            local dl = imgui.GetWindowDrawList()
            dl:AddRectFilled(p, V2(p.x + avail, p.y + 78), UV(K.glass), 18)
            dl:AddRect(p, V2(p.x + avail, p.y + 78), U(1, 1, 1, 0.07), 18, 0, 1)
            local who = "Warga #" .. tostring(phoneInfo.playerId)
            avatar(dl, p.x + 40, p.y + 39, 26, who)
            dl:AddText(V2(p.x + 76, p.y + 20), U(0.97, 0.97, 1, 1), who)
            dl:AddText(V2(p.x + 76, p.y + 42), U(0.60, 0.60, 0.66, 1),
                phoneInfo.faction ~= "" and phoneInfo.faction or "Warga sipil")

            groupedList("Identitas", {
                { "ID Pemain", tostring(phoneInfo.playerId) },
                { "Nomor handphone", tostring(phoneInfo.number) }
            })
            groupedList("Keuangan", {
                { "Uang tunai", money(phoneInfo.cash), { 0.35, 0.88, 0.50 } },
                { "Saldo bank", money(phoneInfo.bank), { 0.35, 0.88, 0.50 } },
                { "Nomor rekening", tostring(phoneInfo.bankId) },
                { "Gaji berikutnya", money(phoneInfo.paycheck) }
            })
            groupedList("Pekerjaan", {
                { "Faksi", phoneInfo.faction ~= "" and phoneInfo.faction or "Tidak ada" },
                { "Pangkat", phoneInfo.rank ~= "" and phoneInfo.rank or "-" }
            })
        end
        drawStatus()
    end

    pages.bank = function()
        header("Bank")
        local avail = imgui.GetContentRegionAvail().x
        if phoneInfo then
            -- kartu rekening
            local p = imgui.GetCursorScreenPos()
            local h = 150
            imgui.Dummy(V2(avail, h))
            local dl = imgui.GetWindowDrawList()
            local ar, ag, ab = K.blue.x, K.blue.y, K.blue.z
            gradientRounded(dl, p.x, p.y, avail, h, 20,
                U(ar * 0.95 + 0.04, ag * 0.95 + 0.04, ab * 0.95 + 0.04, 1), U(ar * 0.28, ag * 0.28, ab * 0.28, 1))
            dl:AddCircleFilled(V2(p.x + avail * 0.70, p.y + h * 0.52), h * 0.36, U(1, 1, 1, 0.10), 48)
            dl:AddCircleFilled(V2(p.x + avail * 0.80, p.y + h * 0.52), h * 0.36, U(1, 1, 1, 0.07), 48)
            dl:AddRect(p, V2(p.x + avail, p.y + h), U(1, 1, 1, 0.20), 20, 0, 1)
            dlText(dl, "PB BANK", p.x + 18, p.y + 14, U(1, 1, 1, 0.92), 1.05)
            -- chip
            dl:AddRectFilled(V2(p.x + 18, p.y + 46), V2(p.x + 56, p.y + 72), U(0.93, 0.78, 0.38, 1), 6)
            dl:AddLine(V2(p.x + 18, p.y + 59), V2(p.x + 56, p.y + 59), U(0.55, 0.42, 0.15, 0.8), 1)
            dl:AddLine(V2(p.x + 37, p.y + 46), V2(p.x + 37, p.y + 72), U(0.55, 0.42, 0.15, 0.8), 1)
            dlText(dl, "SALDO", p.x + 18, p.y + 84, U(1, 1, 1, 0.65), 0.85)
            dlText(dl, money(phoneInfo.bank), p.x + 18, p.y + 99, U(1, 1, 1, 1), 1.65)
            local acct = tostring(phoneInfo.bankId)
            local tail = acct:sub(-4)
            local acctText = "**** " .. tail
            local ts = imgui.CalcTextSize(acctText)
            dl:AddText(V2(p.x + avail - ts.x - 18, p.y + h - 28), U(1, 1, 1, 0.85), acctText)
            imgui.Spacing()
        else
            imgui.TextColored(K.muted, "Memuat saldo rekening...")
            sendChat("/rpui_phone_info")
        end
        imgui.Spacing()
        beginCard("##phone_bank_transfer", 176, K.glass)
        imgui.TextColored(K.white, "Transfer ke pemain online (khusus VIP)")
        imgui.Spacing()
        imgui.SetNextItemWidth(-1)
        styledInput("##bank_target", "Nomor rekening tujuan", bankIdInput)
        imgui.SetNextItemWidth(-1)
        imgui.InputInt("Jumlah transfer##bank_amount", bankAmountInput, 100, 1000)
        if bankAmountInput[0] < 1 then bankAmountInput[0] = 1 end
        if bankAmountInput[0] > 100000 then bankAmountInput[0] = 100000 end
        if pillButton("TRANSFER##phone_bank_transfer_button", -1, 34, "primary") then
            local account = ffi.string(bankIdInput):match("^%s*(.-)%s*$")
            if account:match("^%d+$") then
                sendChat(string.format("/rpui_bank_transfer %s %d", account, bankAmountInput[0]))
            else
                status = "Masukkan nomor rekening tujuan."
            end
        end
        endCard()
        drawStatus()
    end

    pages.taxi = function()
        header("Taxi / Trans")
        local avail = imgui.GetContentRegionAvail().x
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(avail, 150))
        local dl = imgui.GetWindowDrawList()
        dl:AddRectFilled(p, V2(p.x + avail, p.y + 150), UV(K.glass), 20)
        dl:AddRect(p, V2(p.x + avail, p.y + 150), U(1, 1, 1, 0.07), 20, 0, 1)
        local cx, cy = p.x + avail / 2, p.y + 66
        if taxiOrderPending then
            for i = 0, 2 do
                local ph = (A.t * 0.7 + i / 3) % 1
                dl:AddCircle(V2(cx, cy), 28 + ph * 38, U(0.93, 0.72, 0.22, (1 - ph) * 0.55), 48, 2)
            end
        end
        dl:AddCircleFilled(V2(cx, cy), 32, U(0.93, 0.72, 0.22, 1), 40)
        icons.draw(dl, "vehicle", cx - 16, cy - 16, 32, U(0.15, 0.10, 0.02, 1), U(0.93, 0.72, 0.22, 1))
        dlTextC(dl, taxiOrderPending and "Pesanan aktif" or "Tidak ada pesanan", cx, p.y + 112,
            taxiOrderPending and U(0.93, 0.72, 0.22, 1) or U(0.62, 0.62, 0.68, 1), 1.1)
        imgui.Spacing()
        imgui.TextWrapped("Permintaan dikirim kepada petugas Trans yang sedang bertugas, beserta lokasi kamu saat ini.")
        imgui.Spacing()
        if taxiOrderPending then
            if pillButton("BATALKAN PESANAN##phone_taxi_cancel", -1, 42, "danger") then
                sendChat("/rpui_taxi_cancel")
            end
        elseif pillButton("PESAN TRANSPORTASI##phone_taxi_order", -1, 42, "success") then
            sendChat("/rpui_taxi_order")
        end
        drawStatus()
    end

    pages.emergency = function()
        header("Layanan darurat")
        imgui.TextColored(K.muted, "Pilih layanan yang sesuai, lalu jelaskan situasinya.")
        imgui.Spacing()
        local services = {
            { id = "police", label = "Polisi", icon = "user", color = { 0.25, 0.47, 0.96 } },
            { id = "ems", label = "EMS", icon = "help", color = { 0.95, 0.30, 0.28 } },
            { id = "government", label = "Pemda", icon = "bank", color = { 0.62, 0.40, 0.90 } },
            { id = "mechanic", label = "Bengkel", icon = "settings", color = { 0.96, 0.62, 0.20 } },
            { id = "merchant", label = "Pedagang", icon = "map", color = { 0.22, 0.76, 0.46 } }
        }
        local avail = imgui.GetContentRegionAvail().x
        local cols, gap = 3, 8
        local cw = (avail - gap * (cols - 1)) / cols
        for index, svc in ipairs(services) do
            if (index - 1) % cols ~= 0 then imgui.SameLine(0, gap) end
            local clicked = imgui.InvisibleButton("##emg_" .. svc.id, V2(cw, 74))
            hoverKey("##emg_" .. svc.id)
            local min = imgui.GetItemRectMin()
            local dl = imgui.GetWindowDrawList()
            local sel = emergencyService == svc.id
            local c = svc.color
            if sel then
                gradientRounded(dl, min.x, min.y, cw, 74, 16,
                    U(math.min(1, c[1] * 1.15), math.min(1, c[2] * 1.15), math.min(1, c[3] * 1.15), 1),
                    U(c[1] * 0.68, c[2] * 0.68, c[3] * 0.68, 1))
                dl:AddRect(min, V2(min.x + cw, min.y + 74), U(1, 1, 1, 0.45), 16, 0, 1.5)
            else
                dl:AddRectFilled(min, V2(min.x + cw, min.y + 74),
                    U(1, 1, 1, imgui.IsItemHovered() and 0.14 or 0.09), 16)
                dl:AddRect(min, V2(min.x + cw, min.y + 74), U(1, 1, 1, 0.08), 16, 0, 1)
            end
            icons.draw(dl, svc.icon, min.x + cw / 2 - 11, min.y + 13, 22, U(1, 1, 1, 1),
                sel and U(c[1], c[2], c[3], 1) or U(0.18, 0.18, 0.21, 1))
            dlTextC(dl, svc.label, min.x + cw / 2, min.y + 46, U(1, 1, 1, sel and 1 or 0.80), 0.95)
            if clicked then emergencyService = svc.id end
        end
        imgui.Spacing()
        imgui.TextColored(K.muted, "Laporan (maksimal 128 karakter)")
        imgui.SetNextItemWidth(-1)
        styledInput("##phone_emergency_reason", "Jelaskan keadaan darurat", emergencyInput)
        if pillButton("KIRIM LAPORAN##phone_emergency_send", -1, 40, "danger") then
            local reason = ffi.string(emergencyInput):match("^%s*(.-)%s*$")
            if reason ~= "" and not reason:find(":") then
                sendChat("/rpui_emergency " .. emergencyService .. " " .. reason)
            else
                status = "Isi laporan dengan benar; tanda titik dua tidak diperbolehkan."
            end
        end
        imgui.TextWrapped("Gunakan layanan ini hanya untuk laporan roleplay yang sesuai.")
        drawStatus()
    end

    pages.social = function()
        header("X / Sosial")
        beginCard("##phone_social_compose", 104, K.glass)
        imgui.SetNextItemWidth(-1)
        styledInput("##phone_social_input", "Tulis postingan (maks. 80 karakter)", socialInput)
        if pillButton("POSTING##phone_social_post", -1, 32, "primary") then
            local post = ffi.string(socialInput):match("^%s*(.-)%s*$")
            if post ~= "" and #post <= 80 and not post:find(":") then
                sendChat("/rpui_social_post " .. post)
                status = "Menerbitkan postingan..."
            else
                status = "Isi postingan maksimal 80 karakter dan tanpa titik dua."
            end
        end
        endCard()
        imgui.Spacing()
        if pillButton("SEGARKAN##phone_social_refresh", -1, 30, "glass") then
            socialPosts = {}
            sendChat("/rpui_social_feed")
        end
        imgui.Spacing()
        local avail = imgui.GetContentRegionAvail().x
        for index, post in ipairs(socialPosts) do
            local wrapW = avail - 28 - 46
            local h = math.max(70, 44 + wrapHeight(post.text, wrapW) + 14)
            beginCard("##social_post_" .. index, h, K.glass)
            local dl = imgui.GetWindowDrawList()
            local p = imgui.GetCursorScreenPos()
            avatar(dl, p.x + 18, p.y + 18, 17, post.name)
            imgui.Indent(46)
            imgui.TextColored(K.white, fitText(post.name, wrapW - 80))
            imgui.SameLine()
            imgui.TextColored(K.muted, os.date("%d/%m %H:%M", post.time or os.time()))
            imgui.TextWrapped(post.text)
            imgui.Unindent(46)
            endCard()
            imgui.Spacing()
        end
        if #socialPosts == 0 then imgui.TextColored(K.muted, "Belum ada postingan.") end
        drawStatus()
    end

    pages.yellowpages = function()
        header("Yellow Pages")
        beginCard("##phone_yellow_post", 106, K.glass)
        imgui.SetNextItemWidth(-1)
        styledInput("##phone_yellow_input", "Tulis iklan (maks. 100 karakter)", yellowInput)
        if pillButton("PASANG IKLAN - Rp 1.500.000##phone_yellow_submit", -1, 34, "primary") then
            local post = ffi.string(yellowInput):match("^%s*(.-)%s*$")
            if post ~= "" and #post <= 100 and not post:find(":") then
                sendChat("/rpui_yellow_post " .. post)
                status = "Memasang iklan..."
            else
                status = "Iklan maksimal 100 karakter dan tanpa titik dua."
            end
        end
        endCard()
        imgui.Spacing()
        if pillButton("SEGARKAN IKLAN##phone_yellow_refresh", -1, 30, "glass") then
            yellowPages = {}
            sendChat("/rpui_yellow_list")
        end
        imgui.Spacing()
        local avail = imgui.GetContentRegionAvail().x
        for index, ad in ipairs(yellowPages) do
            pushId(index)
            local h = 24 + 20 + wrapHeight(ad.text, avail - 28) + 20 + 36
            beginCard("##yellow_ad_" .. index, h, K.glass)
            imgui.TextColored(V4(0.96, 0.78, 0.30, 1), fitText(ad.name, imgui.GetContentRegionAvail().x))
            imgui.TextWrapped(ad.text)
            imgui.TextColored(K.muted, "Nomor: " .. tostring(ad.number))
            if pillButton("TELEPON##yellow_call" .. index, -1, 28, "success") then
                sendChat("/rpui_phone_call " .. ad.number)
            end
            endCard()
            imgui.PopID()
            imgui.Spacing()
        end
        if #yellowPages == 0 then imgui.TextColored(K.muted, "Belum ada iklan aktif.") end
        drawStatus()
    end

    pages.groups = function()
        if activeGroupId > 0 then
            if pillButton("<  DAFTAR GRUP##group_list_back", 120, 28, "ghost") then
                NS.navDir = -1
                activeGroupId = 0
                activeGroupName = ""
                groupMessages = {}
                sendChat("/rpui_groups_list")
            end
            imgui.SetWindowFontScale(1.3)
            imgui.TextColored(K.white, fitText(activeGroupName, imgui.GetContentRegionAvail().x))
            imgui.SetWindowFontScale(1)
            imgui.Spacing()
            local avail = imgui.GetContentRegionAvail().x
            for index, message in ipairs(groupMessages) do
                local h = 22 + wrapHeight(message.text, avail - 28) + 26
                beginCard("##group_message_" .. index, h, K.glass)
                local r, g, b = hsv(hashHue(message.name), 0.45, 1)
                imgui.TextColored(V4(r, g, b, 1), fitText(message.name, imgui.GetContentRegionAvail().x))
                imgui.TextWrapped(message.text)
                endCard()
                imgui.Spacing()
            end
            if #groupMessages == 0 then imgui.TextColored(K.muted, "Belum ada pesan di grup ini.") end
            imgui.SetNextItemWidth(-1)
            styledInput("##group_message_input", "Tulis pesan ke grup (maks. 80 karakter)", groupMessageInput)
            if pillButton("KIRIM PESAN##group_send", -1, 34, "primary") then
                local text = ffi.string(groupMessageInput):match("^%s*(.-)%s*$")
                if text ~= "" and #text <= 80 and not text:find(":") then
                    sendChat(string.format("/rpui_group_send %d %s", activeGroupId, text))
                else
                    status = "Pesan maksimal 80 karakter dan tanpa titik dua."
                end
            end
        else
            header("Grup")
            beginCard("##phone_group_create", 92, K.glass)
            imgui.SetNextItemWidth(-1)
            styledInput("##phone_group_name", "Nama grup baru (maks. 24 karakter)", groupNameInput)
            if pillButton("BUAT GRUP##phone_group_create_button", -1, 32, "primary") then
                local name = ffi.string(groupNameInput):match("^%s*(.-)%s*$")
                if name ~= "" and #name <= 24 and not name:find(":") then
                    sendChat("/rpui_group_create " .. name)
                else
                    status = "Nama grup maksimal 24 karakter dan tanpa titik dua."
                end
            end
            endCard()
            imgui.Spacing()
            imgui.SetNextItemWidth(90)
            styledInput("##phone_group_id", "ID grup", groupIdInput)
            imgui.SameLine(0, 6)
            if pillButton("BUKA / GABUNG##phone_group_open", -1, 34, "glass") then
                local id = ffi.string(groupIdInput):match("^%s*(.-)%s*$")
                if id:match("^%d+$") then
                    sendChat("/rpui_group_open " .. id)
                    status = "Membuka grup..."
                else
                    status = "Masukkan ID grup yang valid."
                end
            end
            imgui.Spacing()
            local avail = imgui.GetContentRegionAvail().x
            for index, group in ipairs(groups) do
                pushId("group" .. index)
                local clicked, min, _, dl = rowButton("##group_row", avail, 56)
                avatar(dl, min.x + 26, min.y + 28, 20, group.name)
                dl:AddText(V2(min.x + 56, min.y + 10), U(0.97, 0.97, 1, 1), fitText(group.name, avail - 70))
                dl:AddText(V2(min.x + 56, min.y + 30), U(0.60, 0.60, 0.66, 1), "Grup #" .. group.id)
                dl:AddLine(V2(min.x + 56, min.y + 55), V2(min.x + avail, min.y + 55), U(1, 1, 1, 0.06), 1)
                if clicked then
                    sendChat("/rpui_group_open " .. group.id)
                    status = "Membuka grup..."
                end
                imgui.PopID()
            end
            if #groups == 0 then imgui.TextColored(K.muted, "Belum ada grup. Buat grup atau masukkan ID grup.") end
        end
        drawStatus()
    end

    pages.settings = function()
        header("Pengaturan")
        beginCard("##phone_settings_sound", 352, K.glass)
        imgui.TextColored(K.muted, "SUARA & NOTIFIKASI")
        imgui.Spacing()
        if toggleRow("Suara tombol", soundEnabled, "##tg_sound") then
            uiSounds.setEnabled(soundEnabled[0])
            if not soundEnabled[0] then stopRingtone() end
        end
        toggleRow("Nada notifikasi", NS.notifOn, "##tg_notif")
        toggleRow("Getar notifikasi", NS.vibrateOn, "##tg_vibrate")
        imgui.TextColored(K.muted, "Nada dering")
        imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 66)
        if imgui.BeginCombo("##phone_ringtone", RINGTONES[selectedRingtone].label, 0) then
            for index, tone in ipairs(RINGTONES) do
                if imgui.Selectable(tone.label, selectedRingtone == index) then
                    selectedRingtone = index
                    saveSoundPreferences()
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine(0, 6)
        if pillButton("TES##phone_ringtone_test", 60, 28, "glass") then
            if not playOneShot(RINGTONES, selectedRingtone) and soundEnabled[0] then
                status = "Nada dering tidak dapat diputar. Periksa file WAV."
            end
        end
        imgui.TextColored(K.muted, "Nada notifikasi")
        imgui.SetNextItemWidth(imgui.GetContentRegionAvail().x - 66)
        if imgui.BeginCombo("##phone_notification_tone",
            NOTIFICATION_TONES[selectedNotificationTone].label, 0) then
            for index, tone in ipairs(NOTIFICATION_TONES) do
                if imgui.Selectable(tone.label, selectedNotificationTone == index) then
                    selectedNotificationTone = index
                    saveSoundPreferences()
                end
            end
            imgui.EndCombo()
        end
        imgui.SameLine(0, 6)
        if pillButton("TES##phone_notification_test", 60, 28, "glass") then
            if not playOneShot(NOTIFICATION_TONES, selectedNotificationTone) and soundEnabled[0] then
                status = "Nada notifikasi tidak dapat diputar. Periksa file WAV."
            end
        end
        imgui.TextColored(K.muted, "Volume")
        imgui.SetNextItemWidth(-1)
        if imgui.SliderFloat("##phone_sound_volume", soundVolume, 0, 1, "%.2f") then
            uiSounds.setVolume(soundVolume[0])
        end
        imgui.TextColored(K.muted, "Suara panggilan memakai voice server; chat tersedia saat panggilan aktif.")
        endCard()
        imgui.Spacing()
        if pillButton("TES NOTIFIKASI##phone_test_notif", -1, 38, "primary") then
            pushNotification("info", "Tes notifikasi", "Suara dan getar berfungsi.", nil)
        end
        imgui.Spacing()
        beginCard("##phone_settings_about", 86, K.glass)
        imgui.TextColored(K.white, "PekanBaru Roleplay")
        imgui.TextWrapped("Pengaturan ini disimpan di sisi client. Data karakter dan layanan telepon tetap divalidasi oleh server.")
        endCard()
        drawStatus()
    end

    pages.music = function()
        local function drawSharedMusic()
            if not sharedMusic then return end
            beginCard("##music_shared_session", 58, K.glass)
            imgui.TextColored(K.green, "LISTEN TOGETHER  ·  " .. sharedMusic.title)
            imgui.TextColored(K.muted, string.format(
                "Sumber warga #%d  ·  audio Lua mengikuti pemutar (35 meter)",
                sharedMusic.owner))
            endCard()
            imgui.Spacing()
        end

        if musicView == "playlists" then
            header("Musik")
            drawSharedMusic()
            if pillButton("SEGARKAN PLAYLIST##music_refresh", -1, 32, "glass") then
                sendChat("/rpui_music_list")
            end
            imgui.TextColored(K.muted, "Playlist tersedia: " .. #playlists)
            local avail = imgui.GetContentRegionAvail().x
            for _, playlist in ipairs(playlists) do
                pushId(playlist.id)
                local clicked, min, _, dl = rowButton("##playlist_row", avail, 58)
                local r, g, b = hsv(hashHue(playlist.name), 0.55, 0.85)
                gradientRounded(dl, min.x + 4, min.y + 7, 44, 44, 10,
                    U(r, g, b, 1), U(r * 0.55, g * 0.55, b * 0.55, 1))
                local letter = playlist.name:sub(1, 1):upper()
                local ls = imgui.CalcTextSize(letter)
                dl:AddText(V2(min.x + 26 - ls.x / 2, min.y + 29 - ls.y / 2), U(1, 1, 1, 0.95), letter)
                dl:AddText(V2(min.x + 58, min.y + 11), U(0.96, 0.97, 1, 1), fitText(playlist.name, avail - 70))
                dl:AddText(V2(min.x + 58, min.y + 31), U(0.62, 0.67, 0.76, 1),
                    fitText(playlist.owner .. " - " .. (playlist.isPublic and "Publik" or "Pribadi"), avail - 70))
                if clicked then
                    tracks = {}
                    trackOrder = {}
                    selectedPlaylist = playlist.id
                    sendChat("/rpui_music_tracks " .. playlist.id)
                end
                imgui.PopID()
            end
            if #playlists == 0 then
                imgui.TextColored(K.muted, "Belum ada playlist. Buat playlist di bawah.")
            end
            imgui.Spacing()
            beginCard("##music_create_card", 134, K.glass)
            imgui.TextColored(K.muted, "Buat playlist")
            imgui.SetNextItemWidth(-1)
            styledInput("##music_playlist_name", "Nama playlist", playlistName)
            imgui.Checkbox("Playlist publik##music_public", musicPublic)
            if pillButton("BUAT PLAYLIST##music_create", -1, 32, "primary") then
                local name = ffi.string(playlistName):match("^%s*(.-)%s*$")
                if name ~= "" and not name:find(":", 1, true) then
                    sendChat("/rpui_music_create " .. (musicPublic[0] and "1 " or "0 ") .. name)
                    status = "Membuat playlist..."
                else
                    status = "Masukkan nama playlist yang valid."
                end
            end
            endCard()
        else
            header("Playlist #" .. tostring(selectedPlaylist))
            drawSharedMusic()
            local avail = imgui.GetContentRegionAvail().x
            for _, id in ipairs(trackOrder) do
                local track = tracks[id]
                pushId(track.id)
                local clicked, min, _, dl = rowButton("##track_row", avail - 54, 52)
                local playing = NS.playingTrack == track.id
                dl:AddText(V2(min.x + 8, min.y + 8),
                    playing and U(0.45, 0.85, 0.60, 1) or U(0.96, 0.97, 1, 1),
                    fitText(track.title or "Memuat judul", avail - 110))
                dl:AddText(V2(min.x + 8, min.y + 28), U(0.62, 0.67, 0.76, 1), "Track #" .. track.id)
                if playing then
                    -- equalizer animasi
                    for i = 0, 2 do
                        local hgt = 5 + (math.sin(A.t * 8 + i * 1.9) + 1) * 6
                        local bx = min.x + avail - 54 - 30 + i * 7
                        dl:AddRectFilled(V2(bx, min.y + 26 - hgt / 2), V2(bx + 4, min.y + 26 + hgt / 2),
                            U(0.45, 0.85, 0.60, 1), 2)
                    end
                end
                if clicked then
                    sendChat("/rpui_music_play " .. track.id)
                    status = "Memulai pemutaran..."
                end
                imgui.SameLine(0, 0)
                if circleButton("##track_play" .. track.id, 34, KIND.success[1], KIND.success[2], "chat", 54, 52) then
                    sendChat("/rpui_music_play " .. track.id)
                    status = "Memulai pemutaran..."
                end
                imgui.PopID()
            end
            if next(tracks) == nil then
                imgui.TextColored(K.muted, "Playlist ini belum memiliki lagu.")
            end
            imgui.Spacing()
            if pillButton("HENTIKAN MUSIK##music_stop", -1, 34, "danger") then
                sendChat("/rpui_music_stop")
            end
            imgui.Spacing()
            beginCard("##music_add_card", 150, K.glass)
            imgui.TextColored(K.muted, "Tambah lagu (judul tanpa spasi, pakai _)")
            imgui.SetNextItemWidth(-1)
            styledInput("##music_track_title", "Judul lagu", trackTitle)
            imgui.SetNextItemWidth(-1)
            styledInput("##music_track_url", "URL audio langsung HTTP(S)", trackUrl)
            if pillButton("TAMBAH LAGU##music_add", -1, 32, "primary") then
                local title = ffi.string(trackTitle):match("^%s*(.-)%s*$")
                local url = ffi.string(trackUrl):match("^%s*(.-)%s*$")
                if title ~= "" and not title:find("%s") and url:match("^https?://") then
                    sendChat("/rpui_music_add " .. selectedPlaylist .. " " .. title .. " " .. url)
                    status = "Menambahkan lagu..."
                else
                    status = "Isi judul tanpa spasi dan URL audio HTTP(S) langsung."
                end
            end
            endCard()
        end
        drawStatus()
    end

    ------------------------------------------------------------------ frame
    local function isBright(name)
        return name == "lock" or name == "home" or name == "call"
    end

    local function blob(dl, cx, cy, r, cr, cg, cb, a)
        for i = 0, 5 do
            dl:AddCircleFilled(V2(cx, cy), r * (1 - i * 0.14), U(cr, cg, cb, a / 6), 40)
        end
    end

    local function drawWallpaper(dl, x, y, w, h, r, bright, tint)
        local t = A.t
        if bright then
            gradientRounded(dl, x, y, w, h, r, U(0.09, 0.11, 0.34, 1), U(0.42, 0.12, 0.34, 1))
            local clipped = pcall(dl.PushClipRect, dl, V2(x, y), V2(x + w, y + h), true)
            if clipped then
                blob(dl, x + w * (0.28 + 0.06 * math.sin(t * 0.30)), y + h * (0.30 + 0.03 * math.cos(t * 0.22)),
                    120, 0.55, 0.32, 1, 0.34)
                blob(dl, x + w * (0.78 + 0.05 * math.cos(t * 0.26)), y + h * (0.58 + 0.04 * math.sin(t * 0.31)),
                    135, 1, 0.38, 0.56, 0.30)
                blob(dl, x + w * (0.40 + 0.07 * math.sin(t * 0.21)), y + h * 0.88,
                    115, 0.20, 0.60, 1, 0.28)
                blob(dl, x + w * (0.62 + 0.08 * math.sin(t * 0.17)), y + h * (0.16 + 0.03 * math.sin(t * 0.4)),
                    70, 1, 0.70, 0.40, 0.16)
                dl:PopClipRect()
            end
        else
            local c = tint or { 0.25, 0.45, 0.90 }
            gradientRounded(dl, x, y, w, h, r,
                U(c[1] * 0.30 + 0.02, c[2] * 0.30 + 0.02, c[3] * 0.30 + 0.03, 1), U(0.01, 0.01, 0.015, 1))
            local clipped = pcall(dl.PushClipRect, dl, V2(x, y), V2(x + w, y + h), true)
            if clipped then
                blob(dl, x + w * (0.22 + 0.05 * math.sin(t * 0.4)), y + 36, 150, c[1], c[2], c[3], 0.26)
                blob(dl, x + w * 0.92, y + h * 0.96, 140, c[1] * 0.7, c[2] * 0.7, c[3] * 0.7, 0.13)
                dl:PopClipRect()
            end
        end
    end

    local function drawStatusBar(dl, sx, sy, sw, dt)
        local now = A.t
        dlText(dl, os.date("%H:%M"), sx + 30, sy + 14, U(1, 1, 1, 0.97), 1.0)

        -- dynamic island (melebar saat ada panggilan / notifikasi)
        local bannerOn = NS.banner ~= nil and (now - NS.banner.at) < BANNER_TIME
        local cx = sx + sw / 2
        local target = callState and 140 or (bannerOn and 184 or 98)
        A.islandW = A.islandW + (target - A.islandW) * math.min(1, dt * 9)
        local iw = A.islandW
        dl:AddRectFilled(V2(cx - iw / 2, sy + 9), V2(cx + iw / 2, sy + 35), U(0, 0, 0, 1), 13)
        if callState then
            icons.draw(dl, "phone", cx - iw / 2 + 12, sy + 14, 16, U(0.19, 0.82, 0.35, 1), U(0, 0, 0, 1))
            for i = 0, 3 do
                local h = 4 + (math.sin(now * 9 + i * 1.7) + 1) * 4
                local bx = cx + iw / 2 - 20 - i * 7
                dl:AddRectFilled(V2(bx, sy + 22 - h / 2), V2(bx + 3.5, sy + 22 + h / 2),
                    U(0.19, 0.82, 0.35, 1), 2)
            end
        elseif bannerOn then
            icons.draw(dl, "chat", cx - iw / 2 + 12, sy + 14, 16, U(0.19, 0.82, 0.35, 1), U(0, 0, 0, 1))
            for i = 0, 2 do
                local pulse = (math.sin(now * 7 + i * 1.2) + 1) / 2
                dl:AddCircleFilled(V2(cx + iw / 2 - 18 - i * 9, sy + 22), 2.2 + pulse * 1.6,
                    U(1, 1, 1, 0.45 + 0.5 * pulse), 10)
            end
        else
            dl:AddCircleFilled(V2(cx + 32, sy + 22), 5, U(0.07, 0.09, 0.15, 1), 14)
            dl:AddCircleFilled(V2(cx + 30.5, sy + 20.5), 1.5, U(0.35, 0.45, 0.8, 0.8), 8)
        end

        -- baterai
        local bx = sx + sw - 30 - 25
        local by = sy + 16
        dl:AddRect(V2(bx, by), V2(bx + 22, by + 11), U(1, 1, 1, 0.55), 3.5, 0, 1)
        dl:AddRectFilled(V2(bx + 2, by + 2), V2(bx + 2 + 18 * 0.82, by + 9), U(1, 1, 1, 0.95), 2)
        dl:AddRectFilled(V2(bx + 23.5, by + 3.5), V2(bx + 25, by + 7.5), U(1, 1, 1, 0.55), 1)
        -- sinyal
        local sgx = bx - 12 - 17
        for i = 0, 3 do
            local h = 3 + i * 2.6
            dl:AddRectFilled(V2(sgx + i * 5, by + 11 - h), V2(sgx + i * 5 + 3.5, by + 11),
                U(1, 1, 1, i < 3 and 0.95 or 0.4), 1)
        end
        -- wifi
        if not callState then
            local wx, wy = sgx - 14, by + 12
            dl:AddCircleFilled(V2(wx, wy), 1.5, U(1, 1, 1, 0.95), 8)
            for _, r in ipairs({ 4.5, 8, 11.5 }) do
                local px, py
                for k = 0, 6 do
                    local a = -math.pi / 2 - 0.75 + 1.5 * (k / 6)
                    local x, y = wx + math.cos(a) * r, wy + math.sin(a) * r
                    if px then dl:AddLine(V2(px, py), V2(x, y), U(1, 1, 1, 0.9), 1.6) end
                    px, py = x, y
                end
            end
        end
    end

    -- banner notifikasi yang turun dari atas layar saat HP sedang dipakai
    local function drawBanner(sx, sy, sw, now)
        local b = NS.banner
        if not b then return end
        local age = now - b.at
        if age > BANNER_TIME + 0.45 then
            NS.banner = nil
            return
        end
        if not (open and unlocked) or page == "lock" or page == "call" then return end
        local inT = easeBack(age / 0.50)
        local outT = age > BANNER_TIME and ease((age - BANNER_TIME) / 0.40) or 0
        local y = sy + 44 + (inT - 1) * 96 - outT * 96
        local w, h = sw - 20, 70
        imgui.SetCursorScreenPos(V2(sx + 10, y))
        imgui.PushStyleColor(imgui.Col.ChildBg, K.clear)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0)
        imgui.BeginChild("##phone_banner", V2(w, h), false, padFlag + wflag("NoScrollbar"))
        imgui.PopStyleVar(2)
        local dl = imgui.GetWindowDrawList()
        local p = imgui.GetWindowPos()
        local alpha = math.min(1, math.max(0, 1 - outT))
        local saved = A.gA
        A.gA = saved * alpha
        imgui.SetCursorPos(V2(0, 0))
        local clicked = imgui.InvisibleButton("##banner_btn", V2(w, h))
        hoverKey("##banner_btn")
        dl:AddRectFilled(V2(p.x, p.y + 2), V2(p.x + w, p.y + h - 2), U(0.09, 0.09, 0.12, 0.97), 22)
        dl:AddRect(V2(p.x, p.y + 2), V2(p.x + w, p.y + h - 2), U(1, 1, 1, imgui.IsItemHovered() and 0.34 or 0.20), 22, 0, 1)
        miniSquircle(dl, p.x + 12, p.y + 15, 38, notifApp(b.kind))
        local ago = agoText(b.stamp)
        local as = imgui.CalcTextSize(ago)
        dl:AddText(V2(p.x + 60, p.y + 14), U(1, 1, 1, 1), fitText(b.title, w - 76 - as.x))
        dl:AddText(V2(p.x + w - as.x - 14, p.y + 14), U(1, 1, 1, 0.50), ago)
        dl:AddText(V2(p.x + 60, p.y + 36), U(1, 1, 1, 0.82), fitText(b.body, w - 76))
        A.gA = saved
        if clicked then
            uiSounds.play("tab")
            local number, kind = b.number, b.kind
            NS.banner = nil
            if kind == "sms" and number then openChat(number) end
        end
        imgui.EndChild()
        imgui.PopStyleColor(1)
    end

    imgui.OnFrame(
        function() return (open or NS.peek or NS.slide > 0.004) and isSampAvailable() and isPlayerUiReady() end,
        function(self)
            -- kursor hanya tampil saat HP benar-benar terbuka (bukan saat mengintip)
            pcall(function() self.HideCursor = not open end)
            self.LockPlayer = false
            updateAccentPalette()
            local now = os.clock()
            local dt = math.min(0.05, now - (A.last > 0 and A.last or now))
            A.last = now
            A.t = now
            A.dt = dt

            -- halaman yang digambar: saat mengintip selalu layar kunci
            local renderPage = page
            if not open and NS.peek then renderPage = "lock" end
            local key = viewKey(renderPage)
            if key ~= A.lastKey then
                A.lastKey = key
                A.pageAt = now
            end
            if renderPage ~= A.lastPage then
                A.prevPage = A.lastPage
                A.lastPage = renderPage
            end
            if not callState then
                A.callSince = nil
            elseif callState == "ACTIVE" and not A.callSince then
                A.callSince = now
            end

            local display = imgui.GetIO().DisplaySize
            local W = math.max(250, math.min(352, display.x - 24))
            local H = math.max(380, math.min(716, display.y - 24))

            -- posisi HP dengan pegas: tersembunyi -> mengintip -> penuh
            local fullY = (display.y - H) / 2
            local hiddenY = display.y + 14
            local peekH = math.min(PEEK_H, H * 0.5)
            local peekFrac = (hiddenY - (display.y - peekH)) / math.max(1, hiddenY - fullY)
            local target = 0
            if open then
                target = 1
            elseif NS.peek then
                if now > NS.peekUntil then NS.peek = false else target = peekFrac end
            end
            NS.slideVel = NS.slideVel + (target - NS.slide) * 190 * dt
            NS.slideVel = NS.slideVel * math.max(0, 1 - 14 * dt)
            NS.slide = NS.slide + NS.slideVel * dt
            if NS.slide < 0 then
                NS.slide = 0
                NS.slideVel = 0
            end
            local winY = hiddenY + (fullY - hiddenY) * NS.slide

            -- efek getar saat notifikasi masuk
            local shakeT = now - NS.shakeAt
            local shakeX = 0
            if shakeT < 0.75 then
                shakeX = math.sin(shakeT * 85) * 5 * (1 - shakeT / 0.75)
            end

            A.gA = 1
            imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
            imgui.SetNextWindowPos(V2(display.x - W - 22 + shakeX, winY), imgui.Cond.Always)

            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
                + wflag("NoBringToFrontOnFocus")
            if not open then flags = flags + wflag("NoInputs") end
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 1)
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
            imgui.Begin("##PBRP_lua_phone", nil, flags)
            imgui.PopStyleVar(2)

            local dl = imgui.GetWindowDrawList()
            local pos = imgui.GetWindowPos()
            local edge = 4
            local bx0 = pos.x + edge
            local bw = W - edge * 2
            local sx, sy = bx0 + 9, pos.y + 9
            local sw, sh = bw - 18, H - 18

            -- tombol samping (action, volume, power)
            local metal = U(0.38, 0.40, 0.46, 1)
            dl:AddRectFilled(V2(pos.x + 1, pos.y + 112), V2(pos.x + edge + 2, pos.y + 140), metal, 2)
            dl:AddRectFilled(V2(pos.x + 1, pos.y + 168), V2(pos.x + edge + 2, pos.y + 212), metal, 2)
            dl:AddRectFilled(V2(pos.x + 1, pos.y + 222), V2(pos.x + edge + 2, pos.y + 266), metal, 2)
            imgui.SetCursorScreenPos(V2(pos.x + W - 12, pos.y + 168))
            if imgui.InvisibleButton("##phone_power", V2(12, 72)) then close() end
            hoverKey("##phone_power")
            dl:AddRectFilled(V2(pos.x + W - edge - 2, pos.y + 172), V2(pos.x + W - 1, pos.y + 238),
                imgui.IsItemHovered() and U(0.60, 0.62, 0.70, 1) or metal, 2)

            -- bodi titanium (gradasi) + kilau tepi + bezel hitam
            gradientRounded(dl, bx0, pos.y, bw, H, 48, U(0.58, 0.59, 0.65, 1), U(0.30, 0.31, 0.36, 1))
            dl:AddRectFilled(V2(bx0 + 2.5, pos.y + 2.5), V2(bx0 + bw - 2.5, pos.y + H - 2.5), U(0.015, 0.015, 0.02, 1), 45.5)
            dl:AddRect(V2(bx0, pos.y), V2(bx0 + bw, pos.y + H), U(1, 1, 1, 0.30), 48, 0, 1.2)
            dl:AddRect(V2(bx0 + 3, pos.y + 3), V2(bx0 + bw - 3, pos.y + H - 3), U(1, 1, 1, 0.06), 45, 0, 1)

            -- layar: wallpaper dengan crossfade antar halaman, tema warna mengikuti aplikasi
            local enter = ease((now - math.max(A.pageAt, openedAt)) / 0.40)
            local bright = isBright(renderPage)
            local tintApp = appById[renderPage] and appById[renderPage].color or nil
            if isBright(A.prevPage) ~= bright and enter < 1 then
                drawWallpaper(dl, sx, sy, sw, sh, 38, not bright, tintApp)
                A.gA = enter
                drawWallpaper(dl, sx, sy, sw, sh, 38, bright, tintApp)
                A.gA = 1
            else
                drawWallpaper(dl, sx, sy, sw, sh, 38, bright, tintApp)
            end
            -- cincin bezel menutup sudut layar agar rapi
            dl:AddRect(V2(sx - 5, sy - 5), V2(sx + sw + 5, sy + sh + 5), U(0.015, 0.015, 0.02, 1), 43, 0, 10)
            drawStatusBar(dl, sx, sy, sw, dt)

            -- konten dengan transisi: dorong kanan/kiri antar sub-halaman, naik dari beranda
            local keepFull = renderPage == "home" or renderPage == "lock"
            local contentA = keepFull and 1 or enter
            local ox, oy = 0, 0
            if not keepFull then
                if NS.navDir == 0 then
                    oy = (1 - enter) * 30
                else
                    ox = (1 - enter) * 38 * NS.navDir
                end
            end
            A.gA = contentA
            imgui.SetCursorScreenPos(V2(sx + ox, sy + 48 + oy))
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(0.01, contentA))
            imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 3)
            imgui.PushStyleColor(imgui.Col.ScrollbarBg, K.clear)
            imgui.PushStyleColor(imgui.Col.ScrollbarGrab, V4(1, 1, 1, 0.2))
            imgui.PushStyleColor(imgui.Col.ChildBg, K.clear)
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(14, 4))
            imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 0)
            imgui.BeginChild("##phone_content", V2(sw, sh - 48 - 30), false, padFlag)
            imgui.PopStyleVar(2)
            if renderPage ~= "camera" then cameraCaptureAt = nil end
            local render = pages[renderPage] or pages.home
            render()
            imgui.EndChild()
            imgui.PopStyleColor(3)
            imgui.PopStyleVar(2)
            A.gA = 1

            -- banner notifikasi (di atas konten)
            drawBanner(sx, sy, sw, now)

            -- indikator home: di beranda/kunci menutup telepon, di aplikasi kembali ke beranda
            imgui.SetCursorScreenPos(V2(sx + sw / 2 - 60, sy + sh - 26))
            local barClicked = imgui.InvisibleButton("##phone_home_bar", V2(120, 24))
            hoverKey("##phone_home_bar")
            A.homeHover = A.homeHover + ((imgui.IsItemHovered() and 1 or 0) - A.homeHover) * math.min(1, dt * 12)
            local hbw = 104 + A.homeHover * 16
            local hcx = sx + sw / 2
            dl:AddRectFilled(V2(hcx - hbw / 2, sy + sh - 15), V2(hcx + hbw / 2, sy + sh - 10),
                U(1, 1, 1, 0.55 + 0.40 * A.homeHover), 3)
            if barClicked and page ~= "call" then
                if page == "home" or page == "lock" then close() else goHome() end
            end

            imgui.End()
            imgui.PopStyleVar(1)

            if open and not readyAcknowledged
                and os.clock() - lastReadyAttempt >= 2 then
                sendChat("/rpui_phone_lua_ready")
                lastReadyAttempt = os.clock()
            end
            uiSounds.playClickIfHovered(imgui)
        end
    )

    return {
        close = close,
        isOpen = function() return open end,
        onServerMessage = onServerMessage,
        updateSharedMusic = updateSharedMusic,
        reset = function()
            stopRingtone()
            stopSharedAudio()
            photoMedia.restoreCamera()
            open = false
            page = "lock"
            unlocked = false
            chatNumber = nil
            callState = nil
            callNumber = 0
            callChatOpen = false
            videoCall = false
            videoPeer = nil
            nextVideoStatusAt = 0
            cameraActionStatus = ""
            readyAcknowledged = false
            NS.peek = false
            NS.banner = nil
            NS.slide = 0
            NS.slideVel = 0
            NS.playingTrack = 0
            sharedMusic = nil
        end,
        -- untuk dipanggil dari skrip utama (mis. perintah tes): notify("Nama", "isi pesan", 12345)
        notify = function(title, body, number)
            pushNotification("sms", title or "Pesan baru", body or "", number)
        end
    }
end
