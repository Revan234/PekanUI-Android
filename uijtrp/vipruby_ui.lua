return function(imgui, V2, ffi, sendChat, isPlayerUiReady)
    local theme = require("uijtrp.ui_theme")
    theme.apply(imgui)

    local ruby = imgui.ImVec4(1.0, 0.35, 0.42, 1.0)
    local open, hasAccess, page = false, false, 1
    local animationStarted = os.clock()
    local status = "Pilih fitur VIP Ruby."
    local labels, objects = {}, {}
    local musicUrl = imgui.new.char[256]()
    local labelText = imgui.new.char[129]()
    local objectModel = imgui.new.char[16]()

    local function text(buffer) return ffi.string(buffer):match("^%s*(.-)%s*$") end
    local function clear(buffer) ffi.fill(buffer, ffi.sizeof(buffer), 0) end
    local function requestSync() labels, objects = {}, {}; sendChat("/vrubysync") end

    local function onServerMessage(message)
        local allowed = message:match("^@PBRPUI:VIPRUBY:ACCESS:(%d)$")
        if allowed then
            hasAccess = allowed == "1"
            if not hasAccess then open = false end
            return true
        end
        if message == "@PBRPUI:VIPRUBY:OPEN" then
            open, page, status, animationStarted = true, 1, "Panel VIP Ruby siap.", os.clock()
            labels, objects = {}, {}
            return true
        end
        if message == "@PBRPUI:VIPRUBY:CLOSE" then open = false; return true end
        if message == "@PBRPUI:VIPRUBY:LABELS:BEGIN" then labels = {}; return true end
        if message == "@PBRPUI:VIPRUBY:OBJECTS:BEGIN" then objects = {}; return true end
        local labelId, label = message:match("^@PBRPUI:VIPRUBY:LABEL:(%d+):(.*)$")
        if labelId then labels[#labels + 1] = { id = tonumber(labelId), text = label }; return true end
        local objectId, model = message:match("^@PBRPUI:VIPRUBY:OBJECT:(%d+):(%d+)$")
        if objectId then objects[#objects + 1] = { id = tonumber(objectId), model = tonumber(model) }; return true end
        local s = message:match("^@PBRPUI:VIPRUBY:STATUS:(.*)$") or message:match("^@PBRPUI:VIPRUBY:ERROR:(.*)$")
        if s then status = s; return true end
        return message == "@PBRPUI:VIPRUBY:LABELS:END" or message == "@PBRPUI:VIPRUBY:OBJECTS:END"
    end

    local function header(title, desc)
        imgui.TextColored(ruby, title)
        imgui.TextDisabled(desc)
        imgui.Spacing()
    end

    local function pageMusic()
        header("MUSIK", "Diputar untuk pemain sekitar (25 m, interior & virtual world sama).")
        imgui.BeginChild("##m", V2(-1, 120), true)
        imgui.PushItemWidth(-1)
        imgui.InputTextWithHint("##url", "https://... (URL musik HTTP/HTTPS)", musicUrl, ffi.sizeof(musicUrl))
        imgui.PopItemWidth()
        if imgui.Button("Putar untuk sekitar", V2(180, 32)) then
            local url = text(musicUrl)
            if url == "" then status = "Masukkan URL musik terlebih dahulu."
            else sendChat("/vrubymusicplay " .. url) end
        end
        imgui.SameLine()
        if imgui.Button("Hentikan musik saya", V2(180, 32)) then sendChat("/vrubymusicstop") end
        imgui.EndChild()
    end

    local function pageLabels()
        header("TEXT 3D", "Warna: <RRGGBB> | Baris baru: n/ | Maksimal 120 karakter.")
        imgui.PushItemWidth(-150)
        imgui.InputTextWithHint("##lt", "Teks 3D", labelText, ffi.sizeof(labelText))
        imgui.PopItemWidth(); imgui.SameLine()
        if imgui.Button("Tambah di sini", V2(140, 0)) then
            local v = text(labelText)
            if v == "" then status = "Teks 3D tidak boleh kosong."
            else sendChat("/avl " .. v); clear(labelText) end
        end
        imgui.BeginChild("##vipruby_labels", V2(-1, -1), true)
        imgui.TextDisabled(("TEXT 3D MILIKMU (%d)"):format(#labels))
        imgui.Separator()
        if #labels == 0 then imgui.TextDisabled("Belum ada text 3D.") end
        for _, item in ipairs(labels) do
            imgui.PushIDStr("label" .. item.id)
            imgui.TextColored(ruby, ("#%d"):format(item.id)); imgui.SameLine()
            imgui.Text(item.text)
            imgui.SameLine(imgui.GetWindowWidth() - 70)
            if imgui.SmallButton("Hapus") then sendChat("/rvl " .. item.id) end
            imgui.PopID()
        end
        imgui.EndChild()
    end

    local function pageObjects()
        header("OBJECT 3D", "Dibuat 1,5 m di depan karakter. Maksimal 10 object per karakter; gunakan /bcopy [index] untuk menyalin.")
        imgui.PushItemWidth(-150)
        imgui.InputTextWithHint("##om", "Model ID (1-20000)", objectModel, ffi.sizeof(objectModel))
        imgui.PopItemWidth(); imgui.SameLine()
        if imgui.Button("Buat object", V2(140, 0)) then
            local model = tonumber(text(objectModel))
            if not model or model < 1 or model > 20000 then
                status = "Model ID harus berupa angka 1 sampai 20000."
            else
                sendChat("/badd " .. math.floor(model)); clear(objectModel)
            end
        end
        imgui.BeginChild("##vipruby_objects", V2(-1, -1), true)
        imgui.TextDisabled(("OBJECT MILIKMU (%d/10)"):format(#objects))
        imgui.Separator()
        if #objects == 0 then imgui.TextDisabled("Belum ada object.") end
        for _, item in ipairs(objects) do
            imgui.PushIDStr("object" .. item.id)
            imgui.TextColored(ruby, ("#%d"):format(item.id)); imgui.SameLine()
            imgui.Text(("Model %d"):format(item.model))
            imgui.SameLine(imgui.GetWindowWidth() - 190)
            if imgui.SmallButton("Salin") then sendChat("/bcopy " .. item.id) end
            imgui.SameLine()
            if imgui.SmallButton("Edit") then sendChat("/bmove " .. item.id) end
            imgui.SameLine()
            if imgui.SmallButton("Hapus") then sendChat("/brem " .. item.id) end
            imgui.PopID()
        end
        imgui.EndChild()
    end

    local function draw()
        local d = imgui.GetIO().DisplaySize
        local W, H = math.min(760, d.x - 32), math.min(510, d.y - 32)
        local slide = theme.animateWindow(imgui, animationStarted)
        imgui.SetNextWindowPos(V2((d.x - W) * 0.5, (d.y - H) * 0.5 + slide), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
        if imgui.Begin("##vipruby", nil, flags) then
            imgui.BeginChild("##side", V2(180, -1), false)
            imgui.Dummy(V2(0, 4))
            imgui.TextColored(imgui.ImVec4(theme.gold[1], theme.gold[2], theme.gold[3], 1), "PEKANBARU")
            imgui.Text("RUBY CLUB")
            imgui.TextDisabled("Premium features")
            imgui.Separator()
            imgui.Spacing()
            imgui.TextDisabled("FITUR PREMIUM")
            local nav = { "Musik sekitar", "Text 3D", "Object 3D" }
            for i, n in ipairs(nav) do
                if theme.navButton(imgui, n, page == i, 142) then page = i end
            end
            imgui.Dummy(V2(0, 10))
            imgui.Separator()
            imgui.TextDisabled("BATAS AKUN")
            imgui.TextColored(ruby, ("%d text 3D tersimpan"):format(#labels))
            imgui.TextColored(ruby, ("%d / 10 object"):format(#objects))
            imgui.Dummy(V2(0, 8))
            if imgui.Button("Sinkronkan", V2(142, 32)) then requestSync() end
            if imgui.Button("Tutup panel", V2(142, 32)) then open = false end
            imgui.EndChild(); imgui.SameLine()

            imgui.BeginChild("##content", V2(-1, -1), false)
            local titles = {
                { "Musik sekitar", "Bagikan musik ke pemain di dekatmu dalam world yang sama.", "25 M RADIUS" },
                { "Text 3D", "Buat dan kelola tulisan 3D yang tampil di dunia permainan.", ("%d TERSIMPAN"):format(#labels) },
                { "Object 3D", "Tempatkan object, lalu edit posisi atau hapus kapan saja.", ("%d / 10 OBJECT"):format(#objects) },
            }
            local heading = titles[page]
            theme.panelHeader(imgui, V2, heading[1], heading[2], heading[3], ruby)
            imgui.Spacing()
            imgui.BeginChild("##body", V2(-1, -54), false)
            if page == 1 then pageMusic() elseif page == 2 then pageLabels() else pageObjects() end
            imgui.EndChild()
            imgui.Separator()
            imgui.TextDisabled(status)
            imgui.EndChild()
        end
        imgui.End()
        imgui.PopStyleVar()
    end

    local frame = imgui.OnFrame(
        function() return open and hasAccess and isSampAvailable() and isPlayerUiReady() end, draw)
    frame.LockPlayer = false

    return {
        open = function()
            if not hasAccess then sendChat("/vrubyui"); return end
            open, animationStarted = true, os.clock()
            requestSync()
        end,
        close = function() open = false end,
        isOpen = function() return open end,
        hasAccess = function() return hasAccess end,
        onServerMessage = onServerMessage,
        reset = function() open, hasAccess, labels, objects = false, false, {}, {} end,
    }
end
