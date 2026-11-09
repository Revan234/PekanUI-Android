-- ============================================================
--  uiPBRP/notification_ui.lua
--  Notifikasi gaya FiveM yang MEMBACA TEXTDRAW server (bukan chat).
--  Textdraw notifikasi asli diblokir, lalu ditampilkan ulang sebagai
--  kartu imgui + suara notifikasi.
--
--  Hanya pasangan judul + isi pada layout GreyNotify yang dikenali;
--  textdraw HUD lain tidak dipakai sebagai sumber notifikasi.
-- ============================================================
local NOTIFY = {
    enabled = true,
    hideOriginal = true,        -- blokir textdraw notifikasi asli
    duration = 5.2,             -- detik
    maxVisible = 5,
    spawnGrace = 6.0,           -- abaikan textdraw sesaat setelah spawn (HUD awal)
    pairWindow = 0.35,          -- waktu menunggu isi setelah judul notifikasi muncul

    -- Teks yang tidak pernah dianggap notifikasi (HUD statis, angka, dll)
    ignore = {
        "^[%d%p%s]*$",                       -- hanya angka / simbol
        "^%$[%d,%.]+$",
        "^rp[%s%.]*[%d,%.]+$",
        "km/?h", "mph", "fuel", "bensin",
    },

    minLetters = 6,             -- minimal huruf agar dianggap kalimat

}

local THEMES = {
    [0] = { title = "ERROR",      color = { 0.96, 0.30, 0.32 }, sound = "05_pop.wav" },
    [1] = { title = "BERHASIL",   color = { 0.30, 0.82, 0.57 }, sound = "19_kalimba.wav" },
    [2] = { title = "PERINGATAN", color = { 0.98, 0.68, 0.25 }, sound = "05_pop.wav" },
    [3] = { title = "INFORMASI",  color = { 0.38, 0.67, 0.98 }, sound = "02_chime_up.wav" },
}

return function(imgui, V2, isReady, uiSounds)
    local TD = require "uijtrp.td_reader"

    local notifications = {}
    local pending = {}
    local readySince = nil
    local enabled = NOTIFY.enabled
    local inventoryOwns = function() return false end

    -- ---------- suara ----------
    local sounds = { handles = {}, failed = {} }

    local function soundDirectory()
        local ok, path = pcall(function() return thisScript().path end)
        local base = ok and path and path:match("^(.*)[\\/]") or "."
        return base .. "/jtrp_phone/notif/"
    end

    local function playSound(name)
        local handle = sounds.handles[name]
        if not handle and not sounds.failed[name] then
            local path = soundDirectory() .. name
            local okFile, exists = pcall(doesFileExist, path)
            if okFile and exists then
                local okLoad, loaded = pcall(loadAudioStream, path)
                if okLoad and loaded and loaded ~= 0 then
                    handle = loaded
                    sounds.handles[name] = handle
                end
            end
            if not handle then sounds.failed[name] = true end
        end
        if handle then
            pcall(setAudioStreamState, handle, 0)
            pcall(setAudioStreamVolume, handle, 0.6)
            pcall(setAudioStreamState, handle, 1)
            return
        end
        -- cadangan: suara bawaan GTA jika file wav tidak ada
        pcall(addOneOffSound, 0.0, 0.0, 0.0, 1058)
    end

    -- ---------- klasifikasi ----------
    local function lowerText(text)
        return tostring(text or ""):lower()
    end

    local function letterCount(text)
        local _, count = text:gsub("%a", "")
        return count
    end

    local function matchesAny(text, list)
        local lowered = lowerText(text)
        for _, pattern in ipairs(list or {}) do
            if lowered:find(pattern:lower()) then return true end
        end
        return false
    end

    local function normalizedTitle(text)
        return lowerText(text):gsub("[%p%s]", "")
    end

    local function titleKind(rec)
        if rec.selectable or rec.style == 4 or rec.style == 5
            or rec.x < 552 or rec.x > 590 or rec.y < 138 or rec.y > 410 then
            return nil
        end
        local title = normalizedTitle(rec.text)
        if title == "error" then return 0 end
        if title == "sukses" or title == "berhasil" or title == "success" then return 1 end
        if title == "warning" or title == "peringatan" then return 2 end
        if title == "info" or title == "information" or title == "informasi" then return 3 end
        if title == "syntax" then return 3 end
        return nil
    end

    local function isMessageFor(header, rec)
        return not rec.selectable and rec.style ~= 4 and rec.style ~= 5
            and rec.x >= 535 and rec.x <= 560
            and math.abs(rec.x - header.x + 17) <= 8
            and math.abs(rec.y - header.y - 18) <= 7
            and not TD.isBlank(rec.text)
            and not matchesAny(rec.text, NOTIFY.ignore)
            and letterCount(rec.text) >= NOTIFY.minLetters
    end

    local function findPendingHeader(rec)
        for id, group in pairs(pending) do
            if group.kind and group.header and isMessageFor(group.header, rec) then
                return id, group
            end
        end
        return nil, nil
    end

    local function captureCandidate(rec)
        if not enabled or inventoryOwns(rec.id) or TD.isBlank(rec.text) then
            return nil
        end
        if titleKind(rec) then
            return "header"
        end
        local headerId = findPendingHeader(rec)
        if headerId then
            return "message", headerId
        end
        return nil
    end

    local function isReadyForCapture()
        if not isReady() then
            readySince = nil
            return false
        end
        if not readySince then readySince = os.clock() end
        return os.clock() - readySince >= NOTIFY.spawnGrace
    end

    -- ---------- antrean ----------
    local function pushNotification(kind, title, message)
        local now = os.clock()
        for _, item in ipairs(notifications) do
            if item.message == message and now - item.created < 2.0 then
                item.created = now
                item.expires = now + NOTIFY.duration
                return
            end
        end
        while #notifications >= NOTIFY.maxVisible do
            table.remove(notifications, 1)
        end
        notifications[#notifications + 1] = {
            kind = kind, title = title, message = message,
            created = now, expires = now + NOTIFY.duration, y = nil,
        }
        playSound(THEMES[kind].sound)
    end

    TD.onShow(function(rec)
        if not isReadyForCapture() then return nil end
        local candidate, headerId = captureCandidate(rec)
        if not candidate then return nil end

        if candidate == "header" then
            local kind = titleKind(rec)
            pending[rec.id] = { kind = kind, header = rec, started = os.clock() }
        else
            local group = pending[headerId]
            if group then
                group.message = rec
                group.updated = os.clock()
            end
        end
        return NOTIFY.hideOriginal and "block" or nil
    end)

    TD.onText(function(rec)
        if not isReadyForCapture() then return end
        local candidate, headerId = captureCandidate(rec)
        if candidate == "header" then
            pending[rec.id] = { kind = titleKind(rec), header = rec, started = os.clock() }
        elseif candidate == "message" then
            local group = pending[headerId]
            if group then
                group.message = rec
                group.updated = os.clock()
            end
        end
    end)

    TD.onHide(function(rec)
        pending[rec.id] = nil
    end)

    -- ---------- loop ringan ----------
    local function prune(now)
        for i = #notifications, 1, -1 do
            if now > notifications[i].expires + 0.4 then
                table.remove(notifications, i)
            end
        end
    end

    local function tick()
        isReadyForCapture()
        local now = os.clock()
        for id, group in pairs(pending) do
            if group.message and now - (group.updated or group.started) >= NOTIFY.pairWindow then
                pushNotification(group.kind, THEMES[group.kind].title, group.message.text)
                pending[id] = nil
            elseif now - group.started > NOTIFY.pairWindow * 2 then
                pending[id] = nil
            end
        end
        prune(now)
    end

    local function hasItems()
        tick()
        return #notifications > 0
    end

    -- ---------- gambar ----------
    local function color(r, g, b, a)
        return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, a))
    end

    local function easeOut(t)
        t = math.max(0, math.min(1, t))
        return 1 - (1 - t) * (1 - t) * (1 - t)
    end

    local function wrapText(text, maxWidth, maxLines)
        local lines, line = {}, ""
        for word in text:gmatch("%S+") do
            local candidate = line == "" and word or (line .. " " .. word)
            if line ~= "" and imgui.CalcTextSize(candidate).x > maxWidth then
                lines[#lines + 1] = line
                line = word
            else
                line = candidate
            end
        end
        if line ~= "" then lines[#lines + 1] = line end
        if #lines == 0 then lines[1] = " " end
        if #lines > maxLines then
            local kept = {}
            for i = 1, maxLines do kept[i] = lines[i] end
            kept[maxLines] = kept[maxLines] .. ".."
            lines = kept
        end
        return lines
    end

    local function drawKindIcon(dl, kind, cx, cy, size, r, g, b, alpha)
        dl:AddCircleFilled(V2(cx, cy), size, color(r, g, b, 0.18 * alpha), 28)
        dl:AddCircle(V2(cx, cy), size, color(r, g, b, 0.85 * alpha), 28, 1.4)
        local c = color(r, g, b, alpha)
        local k = size * 0.42
        if kind == 1 then            -- centang
            dl:AddLine(V2(cx - k, cy), V2(cx - k * 0.25, cy + k * 0.75), c, 2.2)
            dl:AddLine(V2(cx - k * 0.25, cy + k * 0.75), V2(cx + k, cy - k * 0.65), c, 2.2)
        elseif kind == 0 then        -- silang
            dl:AddLine(V2(cx - k * 0.8, cy - k * 0.8), V2(cx + k * 0.8, cy + k * 0.8), c, 2.2)
            dl:AddLine(V2(cx + k * 0.8, cy - k * 0.8), V2(cx - k * 0.8, cy + k * 0.8), c, 2.2)
        elseif kind == 2 then        -- seru
            dl:AddLine(V2(cx, cy - k), V2(cx, cy + k * 0.25), c, 2.4)
            dl:AddCircleFilled(V2(cx, cy + k * 0.85), 1.5, c, 8)
        else                         -- info
            dl:AddCircleFilled(V2(cx, cy - k * 0.85), 1.6, c, 8)
            dl:AddLine(V2(cx, cy - k * 0.25), V2(cx, cy + k), c, 2.4)
        end
    end

    local function draw()
        if not isReady() then return end
        local now = os.clock()
        prune(now)
        local io = imgui.GetIO()
        local display, dt = io.DisplaySize, io.DeltaTime
        local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
            + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs
            + imgui.WindowFlags.NoBackground

        imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
        imgui.SetNextWindowSize(display, imgui.Cond.Always)
        imgui.SetNextWindowBgAlpha(0.0)
        imgui.Begin("##PBRP_notifications", nil, flags)
        local dl = imgui.GetWindowDrawList()
        local scale = math.max(0.75, math.min(1.1, display.x / 1280))

        local width = 330 * scale
        local cursorY = display.y * 0.30
        for _, item in ipairs(notifications) do
            local age = now - item.created
            local remaining = item.expires - now
            local entrance = easeOut(age / 0.38)
            local exit = math.min(1, math.max(0, remaining / 0.35))
            local alpha = entrance * exit
            local theme = THEMES[item.kind]
            local r, g, b = theme.color[1], theme.color[2], theme.color[3]
            local lines = wrapText(item.message, width - 82 * scale, 4)
            local height = (50 + #lines * 17) * scale

            -- tumpukan bergeser halus saat notifikasi lain hilang
            item.y = item.y and (item.y + (cursorY - item.y) * math.min(1, 12 * dt)) or cursorY
            local x = display.x - width - 22 * scale + (1 - entrance) * 60 * scale
            local y = item.y
            local p1, p2 = V2(x, y), V2(x + width, y + height)

            dl:AddRectFilled(V2(x + 2, y + 4), V2(x + width + 2, y + height + 4),
                color(0, 0, 0, 0.28 * alpha), 12 * scale)
            dl:AddRectFilled(p1, p2, color(0.04, 0.05, 0.075, 0.95 * alpha), 12 * scale)
            dl:AddRect(p1, p2, color(r, g, b, 0.28 * alpha), 12 * scale, 0, 1.0)
            dl:AddRectFilledMultiColor(p1, V2(x + width * 0.55, y + height),
                color(r, g, b, 0.10 * alpha), color(r, g, b, 0.0),
                color(r, g, b, 0.0), color(r, g, b, 0.10 * alpha))
            dl:AddRectFilled(V2(x + 1, y + 10 * scale), V2(x + 4 * scale, y + height - 10 * scale),
                color(r, g, b, alpha), 2 * scale)

            drawKindIcon(dl, item.kind, x + 33 * scale, y + 29 * scale, 14 * scale, r, g, b, alpha)
            dl:AddText(V2(x + 58 * scale, y + 11 * scale), color(r, g, b, alpha), item.title)
            for i, line in ipairs(lines) do
                dl:AddText(V2(x + 58 * scale, y + (31 + (i - 1) * 17) * scale),
                    color(0.92, 0.94, 0.98, alpha), line)
            end

            local progress = math.max(0, math.min(1, remaining / NOTIFY.duration))
            local bx0, bx1 = x + 14 * scale, x + width - 14 * scale
            dl:AddRectFilled(V2(bx0, y + height - 6 * scale), V2(bx1, y + height - 4 * scale),
                color(1, 1, 1, 0.07 * alpha), 1)
            dl:AddRectFilled(V2(bx0, y + height - 6 * scale),
                V2(bx0 + (bx1 - bx0) * progress, y + height - 4 * scale),
                color(r, g, b, alpha), 1)

            cursorY = cursorY + (height + 10 * scale) * math.max(0.0, exit)
        end

        imgui.End()
    end

    -- ---------- API ----------
    local function test(kind)
        kind = tonumber(kind) or 3
        if not THEMES[kind] then kind = 3 end
        pushNotification(kind, THEMES[kind].title,
            "Ini contoh notifikasi untuk menguji tampilan dan suara.")
    end

    return {
        onServerMessage = function() return false end,   -- kompatibel dengan uiPBRP.lua
        hasItems = hasItems,
        draw = draw,
        tick = tick,
        test = test,
        setEnabled = function(value) enabled = value and true or false end,
        isEnabled = function() return enabled end,
        setInventoryOwner = function(fn) inventoryOwns = fn end,
        config = NOTIFY,
    }
end
