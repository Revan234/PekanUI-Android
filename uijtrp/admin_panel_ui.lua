-- admin_panel_ui.lua : PekanAdmin Console (tema merah-hitam, layout ala Fox Admin Dashboard)
-- Dipanggil sama seperti sebelumnya:
--   require("admin_panel_ui")(imgui, V2, ffi, sendChat, isPlayerUiReady, logoPath)
-- Self-contained untuk styling (tidak butuh uijtrp.ui_theme lagi), tetap butuh uijtrp.admin_commands.
return function(imgui, V2, ffi, sendChat, isPlayerUiReady, logoPath)
    local commands = require("uijtrp.admin_commands")
    local ImVec4 = imgui.ImVec4

    ---------------------------------------------------------------- palette (edit di sini)
    local P = {
        bg      = { 12, 12, 15 },
        panel   = { 19, 19, 24 },
        card    = { 26, 26, 32 },
        cardHi  = { 38, 38, 47 },
        line    = { 46, 46, 56 },
        red     = { 225, 29, 46 },
        redDark = { 120, 14, 24 },
        redSoft = { 255, 92, 104 },
        text    = { 236, 236, 240 },
        muted   = { 138, 138, 150 },
        green   = { 52, 211, 120 },
        amber   = { 250, 190, 60 },
        blue    = { 96, 165, 250 },
    }

    ---------------------------------------------------------------- helpers
    local galpha = 1 -- alpha global untuk drawlist (drawlist tidak ikut style Alpha)
    local function clamp(v, a, b) return math.max(a, math.min(b, v)) end
    local function ease(t) return 1 - (1 - t) ^ 3 end
    local function U(c, a)
        return imgui.ColorConvertFloat4ToU32(ImVec4(c[1] / 255, c[2] / 255, c[3] / 255, (a or 1) * galpha))
    end
    local function V4(c, a) return ImVec4(c[1] / 255, c[2] / 255, c[3] / 255, a or 1) end

    local dt = 0.016
    local anim = {}
    local function approach(key, target, speed)
        local v = anim[key]
        if v == nil then v = target end
        v = v + (target - v) * math.min(1, dt * speed)
        if math.abs(target - v) < 0.001 then v = target end
        anim[key] = v
        return v
    end

    local sizedOK = true
    local function text(dl, x, y, size, col, s)
        if sizedOK then
            local ok = pcall(function() dl:AddTextFontPtr(imgui.GetFont(), size, V2(x, y), col, s) end)
            if ok then return end
            sizedOK = false
        end
        dl:AddText(V2(x, y), col, s)
    end
    local function tw(s, size) return imgui.CalcTextSize(s).x * size / imgui.GetFontSize() end

    local function pill(dl, x, y, label, size, bg, fg)
        local w = tw(label, size) + 18
        dl:AddRectFilled(V2(x, y), V2(x + w, y + size + 10), bg, (size + 10) / 2)
        text(dl, x + 9, y + 5, size, fg, label)
        return w
    end

    local function icon(dl, kind, cx, cy, col)
        if kind == 1 then
            for i = 0, 1 do for j = 0, 1 do
                local x, y = cx - 7 + i * 8, cy - 7 + j * 8
                dl:AddRectFilled(V2(x, y), V2(x + 6, y + 6), col, 1.5)
            end end
        elseif kind == 2 then
            dl:AddCircleFilled(V2(cx, cy - 4), 4, col, 16)
            dl:AddRectFilled(V2(cx - 7, cy + 2), V2(cx + 7, cy + 8), col, 3)
        elseif kind == 3 then
            dl:AddLine(V2(cx - 6, cy - 4), V2(cx - 1, cy), col, 2)
            dl:AddLine(V2(cx - 1, cy), V2(cx - 6, cy + 4), col, 2)
            dl:AddLine(V2(cx + 1, cy + 5), V2(cx + 7, cy + 5), col, 2)
        else
            for i = -1, 1 do
                dl:AddRectFilled(V2(cx - 7, cy + i * 5 - 2), V2(cx + 7, cy + i * 5 + 2), col, 2)
            end
        end
    end

    local function cardBg(dl, x, y, w, h, borderCol)
        dl:AddRectFilled(V2(x + 1, y + 4), V2(x + w + 1, y + h + 4), U({ 0, 0, 0 }, 0.35), 12)
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), U(P.card), 12)
        dl:AddRect(V2(x, y), V2(x + w, y + h), borderCol or U(P.line, 0.7), 12)
    end

    local function str(buf) return ffi.string(buf):match("^%s*(.-)%s*$") end
    local function split(s, sep)
        local t = {}
        for part in (s .. sep):gmatch("(.-)" .. sep:gsub("%p", "%%%0")) do t[#t + 1] = part end
        return t
    end

    ---------------------------------------------------------------- logo
    local logoTexture
    imgui.OnInitialize(function()
        if not logoPath or not doesFileExist(logoPath) then
            print("[PBRP/PKU UI] Logo panel admin tidak ditemukan: " .. tostring(logoPath))
            return
        end
        local ok, texture = pcall(imgui.CreateTextureFromFile, logoPath)
        if ok and texture then
            logoTexture = texture
        else
            print("[PBRP/PKU UI] Gagal memuat logo panel admin: " .. tostring(texture))
        end
    end)

    ---------------------------------------------------------------- state
    local open, closing, level, tab = false, nil, 0, 1
    local collapsed = false
    local animationStarted, tabStart = os.clock(), os.clock()
    local status, statusKind = "Panel admin siap.", "info"
    local players, selected = {}, nil
    local history = {}
    local actionLog = {}
    local myName = "Admin"
    local lastReq = 0
    local playerSearch = imgui.new.char[32]()
    local cmdSearch = imgui.new.char[48]()
    local reason = imgui.new.char[96]()
    local minutes = imgui.new.char[8]("10")
    local autoRefresh = imgui.new.bool(false)
    local tables, curTable, cols, rows = {}, nil, {}, {}
    local dbPage, dbTotal = 1, 1
    local dbSearch = imgui.new.char[48]()

    local function addLog(msg, kind)
        table.insert(actionLog, 1, { t = os.date("%H:%M:%S"), msg = msg, kind = kind or "info" })
        if #actionLog > 40 then table.remove(actionLog) end
    end

    local function refreshName()
        local ok, nm = pcall(function()
            local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
            return sampGetPlayerNickname(id)
        end)
        if ok and nm and nm ~= "" then myName = (nm:gsub("_", " ")) end
    end

    local function setTab(i)
        if i ~= tab then tab, tabStart = i, os.clock() end
    end

    local function requestPlayers() players = {}; lastReq = os.clock(); sendChat("/apanelplayers") end
    local function requestTables() tables = {}; sendChat("/adbtables") end
    local function requestRows(name, page)
        curTable, dbPage = name, page or 1
        cols, rows = {}, {}
        sendChat(("/adbrows %s %d %s"):format(name, dbPage, str(dbSearch)))
    end

    local function requestClose() if open and not closing then closing = os.clock() end end

    local function openPanel()
        open, closing, tab = true, nil, 1
        animationStarted, tabStart = os.clock(), os.clock()
        refreshName()
        addLog("Panel dibuka", "info")
        requestPlayers()
    end

    ---------------------------------------------------------------- protokol server (@PBRPUI:ADMIN:...)
    local function onServerMessage(m)
        local lv = m:match("^@PBRPUI:ADMIN:ACCESS:(%d+)$")
        if lv then
            level = math.floor(tonumber(lv) or 0)
            if level < 1 then open, closing = false, nil end
            return true
        end
        if m == "@PBRPUI:ADMIN:OPEN" then openPanel(); return true end
        if m == "@PBRPUI:ADMIN:CLOSE" then requestClose(); return true end
        if m == "@PBRPUI:ADMIN:PLAYERS:BEGIN" then players = {}; return true end
        local id, name, ping, score = m:match("^@PBRPUI:ADMIN:PLAYER:(%d+):([^:]*):(%d+):(%d+)$")
        if id then
            players[#players + 1] = { id = tonumber(id), name = name, ping = tonumber(ping), score = tonumber(score) }
            return true
        end
        local t = m:match("^@PBRPUI:ADMIN:DB:TABLE:(.+)$")
        if t then tables[#tables + 1] = t; return true end
        local c = m:match("^@PBRPUI:ADMIN:DB:COLS:(.+)$")
        if c then cols = split(c, "|"); return true end
        local r = m:match("^@PBRPUI:ADMIN:DB:ROW:(.*)$")
        if r then rows[#rows + 1] = split(r, "|"); return true end
        local p, tot = m:match("^@PBRPUI:ADMIN:DB:PAGE:(%d+):(%d+)$")
        if p then
            dbPage = math.floor(tonumber(p) or 1)
            dbTotal = math.max(1, math.floor(tonumber(tot) or 1))
            return true
        end
        local s = m:match("^@PBRPUI:ADMIN:STATUS:(.*)$")
        local e = m:match("^@PBRPUI:ADMIN:ERROR:(.*)$")
        if s or e then
            status, statusKind = s or e, e and "err" or "ok"
            addLog(status, statusKind)
            return true
        end
        if m == "@PBRPUI:ADMIN:PLAYERS:END" then
            history[#history + 1] = #players
            if #history > 20 then table.remove(history, 1) end
            return true
        end
        return m == "@PBRPUI:ADMIN:DB:END"
    end

    ---------------------------------------------------------------- komponen kartu
    local function beginCard(id, w, h)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(14, 12))
        imgui.PushStyleVarFloat(imgui.StyleVar.ChildRounding, 12)
        imgui.PushStyleColor(imgui.Col.ChildBg, V4(P.card))
        imgui.BeginChild(id, V2(w, h), true)
    end
    local function endCard()
        imgui.EndChild()
        imgui.PopStyleColor(1)
        imgui.PopStyleVar(2)
    end

    local function statCard(id, label, value, sub, acc, w, h)
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(w, h))
        local hovered = imgui.IsItemHovered()
        local hv = approach("card" .. id, hovered and 1 or 0, 14)
        local e = ease(clamp((os.clock() - tabStart) * 2.4 - id * 0.18, 0, 1))
        local keep = galpha
        galpha = keep * e
        local dl = imgui.GetWindowDrawList()
        local x, y = p.x, p.y + (1 - e) * 16 - hv * 3
        cardBg(dl, x, y, w, h, U(acc, 0.15 + hv * 0.7))
        dl:AddRectFilled(V2(x, y + 16), V2(x + 4, y + h - 16), U(acc), 2)
        local shown = math.floor(approach("val" .. id, value, 7) + 0.5)
        text(dl, x + 18, y + 14, 12, U(P.muted), label)
        text(dl, x + 18, y + 32, 32, U(P.text), tostring(shown))
        text(dl, x + 18, y + h - 22, 12, U(acc), sub)
        local cx, cy = x + w - 36, y + h / 2
        dl:AddCircleFilled(V2(cx, cy), 20 + hv * 2, U(acc, 0.16), 28)
        dl:AddCircleFilled(V2(cx, cy), 6, U(acc), 20)
        galpha = keep
    end

    ---------------------------------------------------------------- tabs
    local function tabDashboard(w, h)
        local gap = 14
        local cw = (w - gap * 3) / 4
        local cardH = 94
        local usable = 0
        for _, c in ipairs(commands) do if c.level <= level then usable = usable + 1 end end
        local cards = {
            { "PLAYER ONLINE", #players, "pemain terdeteksi", P.red },
            { "LEVEL ADMIN", level, "dari maksimal 7", P.amber },
            { "COMMAND AKTIF", usable, "bisa kamu pakai", P.green },
            { "TOTAL COMMAND", #commands, "terdaftar di server", P.blue },
        }
        for i, c in ipairs(cards) do
            statCard(i, c[1], c[2], c[3], c[4], cw, cardH)
            if i < 4 then imgui.SameLine(0, gap) end
        end

        local rest = h - cardH - gap * 2
        local chartH = math.max(150, math.floor(rest * 0.52))
        local logH = math.max(90, rest - chartH)
        local lw = math.floor(w * 0.6 - gap / 2)
        local rw = w - lw - gap
        local dl = imgui.GetWindowDrawList()

        -- grafik garis: riwayat player
        local p0 = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(lw, chartH))
        imgui.SameLine(0, gap)
        local p1 = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(rw, chartH))

        cardBg(dl, p0.x, p0.y, lw, chartH)
        text(dl, p0.x + 18, p0.y + 14, 15, U(P.text), "Aktivitas Player")
        text(dl, p0.x + 18, p0.y + 34, 12, U(P.muted), "Jumlah player online tiap refresh")
        local nowTxt = tostring(#players) .. " online"
        pill(dl, p0.x + lw - tw(nowTxt, 12) - 36, p0.y + 14, nowTxt, 12, U(P.red, 0.18), U(P.redSoft))

        local ax, ay, aw, ah = p0.x + 48, p0.y + 66, lw - 72, chartH - 96
        local m = 3
        for _, v in ipairs(history) do if v > m then m = v end end
        local hmax = approach("hmax", math.ceil(m / 3) * 3, 6)
        for i = 0, 3 do
            local gy = ay + ah * (i / 3)
            dl:AddLine(V2(ax, gy), V2(ax + aw, gy), U(P.line, 0.5), 1)
            text(dl, p0.x + 16, gy - 7, 11, U(P.muted), tostring(math.floor(hmax * (1 - i / 3) + 0.5)))
        end
        local n = #history
        if n >= 2 then
            local reveal = ease(clamp((os.clock() - tabStart - 0.2) / 0.9, 0, 1))
            local lastSeg = (n - 1) * reveal
            local function pt(i) return ax + aw * (i - 1) / (n - 1), ay + ah - (history[i] / hmax) * ah end
            for i = 1, n - 1 do
                if i - 1 < lastSeg then
                    local x1, y1 = pt(i)
                    local x2, y2 = pt(i + 1)
                    local f = clamp(lastSeg - (i - 1), 0, 1)
                    x2, y2 = x1 + (x2 - x1) * f, y1 + (y2 - y1) * f
                    dl:AddQuadFilled(V2(x1, y1), V2(x2, y2), V2(x2, ay + ah), V2(x1, ay + ah), U(P.red, 0.13))
                    dl:AddLine(V2(x1, y1), V2(x2, y2), U(P.red), 2.5)
                end
            end
            for i = 1, n do
                if i - 1 <= lastSeg then
                    local x, y = pt(i)
                    dl:AddCircleFilled(V2(x, y), 4, U(P.red), 14)
                    dl:AddCircleFilled(V2(x, y), 2, U(P.text), 10)
                    if i == n then
                        local pulse = (os.clock() % 1.4) / 1.4
                        dl:AddCircle(V2(x, y), 5 + pulse * 10, U(P.red, 1 - pulse), 24, 1.5)
                    end
                end
            end
            text(dl, ax, ay + ah + 8, 11, U(P.muted), "lalu")
            text(dl, ax + aw - tw("sekarang", 11), ay + ah + 8, 11, U(P.muted), "sekarang")
        else
            local msg = "Tekan Refresh di tab Players untuk mengumpulkan data."
            text(dl, ax + aw / 2 - tw(msg, 12) / 2, ay + ah / 2 - 6, 12, U(P.muted), msg)
        end

        -- bar chart: distribusi command per level
        cardBg(dl, p1.x, p1.y, rw, chartH)
        text(dl, p1.x + 18, p1.y + 14, 15, U(P.text), "Command per Level")
        text(dl, p1.x + 18, p1.y + 34, 12, U(P.muted), "Merah = bisa kamu akses")
        local counts, maxc = {}, 1
        for _, c in ipairs(commands) do
            counts[c.level] = (counts[c.level] or 0) + 1
            if counts[c.level] > maxc then maxc = counts[c.level] end
        end
        local bx, by, bw, bh = p1.x + 18, p1.y + 66, rw - 36, chartH - 100
        local slot = bw / 7
        for lv = 1, 7 do
            local cnt = counts[lv] or 0
            local e = ease(clamp((os.clock() - tabStart - 0.15 - lv * 0.07) * 2.2, 0, 1))
            local bhh = math.max(3, (cnt / maxc) * bh * e)
            local x1 = bx + (lv - 1) * slot + 6
            local x2 = bx + lv * slot - 6
            local unlocked = lv <= level
            local col = unlocked and P.red or { 64, 64, 74 }
            if unlocked then dl:AddRectFilled(V2(x1 - 2, by + bh - bhh - 2), V2(x2 + 2, by + bh + 2), U(P.red, 0.14), 7) end
            dl:AddRectFilled(V2(x1, by + bh - bhh), V2(x2, by + bh), U(col), 5)
            text(dl, (x1 + x2) / 2 - tw(tostring(cnt), 11) / 2, by + bh - bhh - 16, 11, U(P.text, e), tostring(cnt))
            text(dl, (x1 + x2) / 2 - tw("L" .. lv, 11) / 2, by + bh + 8, 11, U(unlocked and P.text or P.muted), "L" .. lv)
        end

        -- log aktivitas
        local p2 = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(w, logH))
        cardBg(dl, p2.x, p2.y, w, logH)
        text(dl, p2.x + 18, p2.y + 12, 15, U(P.text), "Log Aktivitas")
        if #actionLog == 0 then
            text(dl, p2.x + 18, p2.y + 42, 12, U(P.muted), "Belum ada aktivitas.")
        else
            local maxRows = math.max(1, math.floor((logH - 46) / 24))
            for i = 1, math.min(maxRows, #actionLog) do
                local a = actionLog[i]
                local e = ease(clamp((os.clock() - tabStart) * 2 - i * 0.1, 0, 1))
                local ry = p2.y + 40 + (i - 1) * 24
                local col = a.kind == "err" and P.red or (a.kind == "ok" and P.green or P.blue)
                local keep = galpha
                galpha = keep * e
                dl:AddCircleFilled(V2(p2.x + 24, ry + 8), 4, U(col), 12)
                text(dl, p2.x + 38, ry + 1, 12, U(P.muted), a.t)
                text(dl, p2.x + 108, ry + 1, 13, U(P.text), a.msg)
                galpha = keep
            end
        end
    end

    local acts = {
        { "Spec", 1, "spec %d" }, { "Goto", 1, "goto %d" }, { "Gethere", 1, "gethere %d" },
        { "Freeze", 1, "freeze %d" }, { "Unfreeze", 2, "unfreeze %d" }, { "Slap", 1, "slap %d" },
        { "Revive", 1, "arevive %d" }, { "Warn", 1, "warn %d %s", true }, { "Kick", 1, "kick %d %s", true },
        { "Jail", 1, "jail %d %m %s", true }, { "Unjail", 1, "unjail %d" }, { "Ban", 3, "ban %d %s", true },
    }

    local function runAction(fmt)
        local mins = str(minutes)
        if mins == "" then mins = "10" end
        local cmd = fmt:gsub("%%(%a)", function(k)
            if k == "d" then return tostring(selected) end
            if k == "m" then return mins end
            return str(reason)
        end)
        cmd = cmd:gsub("%s+$", "")
        sendChat("/" .. cmd)
        addLog("/" .. cmd, "info")
    end

    local function pingColor(p) return p <= 80 and P.green or (p <= 160 and P.amber or P.red) end

    local function tabPlayers(w, h)
        imgui.PushItemWidth(220)
        imgui.InputTextWithHint("##ps", "Cari nama / ID", playerSearch, ffi.sizeof(playerSearch))
        imgui.PopItemWidth(); imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Button, V4(P.red, 0.9))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, V4(P.redSoft))
        if imgui.Button("Refresh", V2(90, 0)) then requestPlayers() end
        imgui.PopStyleColor(2)
        imgui.SameLine()
        imgui.Checkbox("Auto refresh 20 dtk", autoRefresh)
        imgui.SameLine()
        imgui.TextDisabled(("%d pemain"):format(#players))

        local cardH = h - 46
        local lw = math.floor(w * 0.6)
        beginCard("##plist", lw, cardH)
        local dl = imgui.GetWindowDrawList()
        imgui.TextDisabled("ID"); imgui.SameLine(64); imgui.TextDisabled("NAMA")
        imgui.SameLine(lw - 150); imgui.TextDisabled("PING"); imgui.SameLine(lw - 84); imgui.TextDisabled("LV")
        imgui.Separator()
        local q = str(playerSearch):lower()
        local idx = 0
        for _, p in ipairs(players) do
            if q == "" or p.name:lower():find(q, 1, true) or tostring(p.id) == q then
                idx = idx + 1
                if imgui.Selectable("##row" .. p.id, selected == p.id, 0, V2(0, 34)) then selected = p.id end
                local a, b = imgui.GetItemRectMin(), imgui.GetItemRectMax()
                local e = ease(clamp((os.clock() - tabStart) * 2.4 - idx * 0.05, 0, 1))
                local keep = galpha
                galpha = keep * e
                local ox = (1 - e) * 16
                local ty = a.y + (34 - imgui.GetTextLineHeight()) / 2
                if selected == p.id then dl:AddRectFilled(V2(a.x, a.y + 4), V2(a.x + 3, b.y - 4), U(P.red), 2) end
                text(dl, a.x + 10 + ox, ty, imgui.GetFontSize(), U(P.muted), tostring(p.id))
                dl:AddCircleFilled(V2(a.x + 80 + ox, a.y + 17), 11, U(P.red, 0.2), 16)
                text(dl, a.x + 76 + ox, ty, imgui.GetFontSize(), U(P.redSoft), p.name:sub(1, 1):upper())
                text(dl, a.x + 100 + ox, ty, imgui.GetFontSize(), U(P.text), p.name)
                local pc = pingColor(p.ping)
                dl:AddCircleFilled(V2(a.x + lw - 156 + ox, a.y + 17), 4, U(pc), 10)
                text(dl, a.x + lw - 144 + ox, ty, imgui.GetFontSize(), U(P.text), tostring(p.ping))
                text(dl, a.x + lw - 90 + ox, ty, imgui.GetFontSize(), U(P.text), tostring(p.score))
                galpha = keep
            end
        end
        endCard()
        imgui.SameLine(0, 14)

        beginCard("##pact", w - lw - 14, cardH)
        local dl2 = imgui.GetWindowDrawList()
        local sp
        for _, p in ipairs(players) do if p.id == selected then sp = p end end
        if not sp then
            imgui.TextDisabled("Pilih player di kiri untuk melihat aksi.")
        else
            local c = imgui.GetCursorScreenPos()
            imgui.Dummy(V2(10, 46))
            dl2:AddCircleFilled(V2(c.x + 22, c.y + 22), 22, U(P.red, 0.2), 28)
            text(dl2, c.x + 15, c.y + 10, 24, U(P.redSoft), sp.name:sub(1, 1):upper())
            text(dl2, c.x + 54, c.y + 4, 16, U(P.text), sp.name)
            local pc = pingColor(sp.ping)
            pill(dl2, c.x + 54, c.y + 24, ("ID %d  |  %d ms"):format(sp.id, sp.ping), 11, U(pc, 0.18), U(pc))
            imgui.PushItemWidth(-1)
            imgui.InputTextWithHint("##rs", "Alasan", reason, ffi.sizeof(reason))
            imgui.InputTextWithHint("##mn", "Menit (jail)", minutes, ffi.sizeof(minutes))
            imgui.PopItemWidth()
            imgui.Separator()
            local bw = (imgui.GetContentRegionAvail().x - 10) / 2
            for i, a in ipairs(acts) do
                local locked = level < a[2]
                if locked then imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.35) end
                if a[4] then
                    imgui.PushStyleColor(imgui.Col.Button, V4(P.redDark, 0.9))
                    imgui.PushStyleColor(imgui.Col.ButtonHovered, V4(P.red))
                end
                if imgui.Button(a[1], V2(bw, 32)) and not locked then runAction(a[3]) end
                if a[4] then imgui.PopStyleColor(2) end
                if locked then imgui.PopStyleVar() end
                if i % 2 == 1 then imgui.SameLine(0, 10) end
            end
        end
        endCard()
    end

    local function tabCommands(w, h)
        imgui.PushItemWidth(280)
        imgui.InputTextWithHint("##cs", "Cari command...", cmdSearch, ffi.sizeof(cmdSearch))
        imgui.PopItemWidth()
        imgui.SameLine(); imgui.TextDisabled("Klik command untuk mengisi chat (yang terkunci redup).")
        beginCard("##cmds", w, h - 46)
        local dl = imgui.GetWindowDrawList()
        local q = str(cmdSearch):lower()
        local last, lineX, first = 0, 0, true
        local startX = imgui.GetCursorPosX()
        local availW = imgui.GetWindowWidth() - 28
        imgui.PushStyleColor(imgui.Col.Button, V4(P.cardHi))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, V4(P.red, 0.85))
        for _, c in ipairs(commands) do
            if q == "" or c.name:find(q, 1, true) then
                if c.level ~= last then
                    last, first = c.level, true
                    imgui.Dummy(V2(1, 4))
                    local p = imgui.GetCursorScreenPos()
                    dl:AddRectFilled(V2(p.x, p.y + 1), V2(p.x + 3, p.y + 16), U(c.level <= level and P.red or P.muted), 2)
                    text(dl, p.x + 10, p.y, 14, U(c.level <= level and P.redSoft or P.muted), "LEVEL " .. c.level)
                    imgui.Dummy(V2(1, 24))
                end
                local label = "/" .. c.name
                local bw = imgui.CalcTextSize(label).x + 22
                if not first and lineX + 8 + bw <= availW then
                    imgui.SameLine(0, 8); lineX = lineX + 8 + bw
                else
                    lineX = bw
                end
                first = false
                local locked = c.level > level
                if locked then imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.35) end
                if imgui.Button(label .. "##" .. c.name, V2(bw, 26)) and not locked then
                    sampSetChatInputText("/" .. c.name .. " ")
                    sampSetChatInputEnabled(true)
                    requestClose()
                end
                if locked then imgui.PopStyleVar() end
            end
        end
        imgui.PopStyleColor(2)
        endCard()
    end

    local function tabDatabase(w, h)
        if level < 6 then
            local p = imgui.GetCursorScreenPos()
            local dl = imgui.GetWindowDrawList()
            imgui.Dummy(V2(w, h - 10))
            cardBg(dl, p.x, p.y, w, h - 10)
            local cx, cy = p.x + w / 2, p.y + (h - 10) / 2
            dl:AddCircleFilled(V2(cx, cy - 24), 30, U(P.red, 0.14), 32)
            dl:AddRectFilled(V2(cx - 11, cy - 26), V2(cx + 11, cy - 8), U(P.redSoft), 4)
            dl:AddCircle(V2(cx, cy - 30), 8, U(P.redSoft), 20, 3)
            local msg = "Database browser membutuhkan level admin 6+"
            text(dl, cx - tw(msg, 15) / 2, cy + 20, 15, U(P.text), msg)
            return
        end
        beginCard("##dbtables", 190, h - 10)
        imgui.TextDisabled("TABEL")
        imgui.SameLine()
        if imgui.SmallButton("Muat") then requestTables() end
        imgui.Separator()
        for _, t in ipairs(tables) do
            if imgui.Selectable(t, curTable == t) then requestRows(t, 1) end
        end
        endCard()
        imgui.SameLine(0, 14)

        beginCard("##dbrows", w - 204, h - 10)
        if not curTable then
            imgui.TextDisabled("Pilih tabel (read-only).")
        else
            imgui.TextColored(V4(P.redSoft), curTable); imgui.SameLine()
            imgui.PushItemWidth(180)
            imgui.InputTextWithHint("##dbs", "Cari...", dbSearch, ffi.sizeof(dbSearch))
            imgui.PopItemWidth(); imgui.SameLine()
            if imgui.Button("Cari") then requestRows(curTable, 1) end
            imgui.SameLine()
            if imgui.Button("<") and dbPage > 1 then requestRows(curTable, dbPage - 1) end
            imgui.SameLine(); imgui.Text(("%d / %d"):format(dbPage, dbTotal)); imgui.SameLine()
            if imgui.Button(">") and dbPage < dbTotal then requestRows(curTable, dbPage + 1) end
            imgui.Separator()
            imgui.BeginChild("##dbgrid", V2(-1, -1), false, imgui.WindowFlags.HorizontalScrollbar)
            if #cols > 0 then
                imgui.Columns(#cols, "##dbcols", true)
                for _, cname in ipairs(cols) do
                    imgui.TextColored(V4(P.amber), cname); imgui.NextColumn()
                end
                imgui.Separator()
                for _, row in ipairs(rows) do
                    for i = 1, #cols do imgui.Text(row[i] or "NULL"); imgui.NextColumn() end
                end
                imgui.Columns(1)
            end
            imgui.EndChild()
        end
        endCard()
    end

    ---------------------------------------------------------------- style
    local styleCols
    local function pushStyle(alpha)
        if not styleCols then
            local C = imgui.Col
            styleCols = {
                { C.Text, V4(P.text) }, { C.TextDisabled, V4(P.muted) },
                { C.WindowBg, V4(P.bg) }, { C.ChildBg, ImVec4(0, 0, 0, 0) },
                { C.Border, V4(P.line, 0.8) }, { C.PopupBg, V4(P.panel) },
                { C.FrameBg, V4(P.panel) }, { C.FrameBgHovered, V4(P.cardHi) }, { C.FrameBgActive, V4(P.cardHi) },
                { C.Button, V4(P.cardHi) }, { C.ButtonHovered, V4(P.red, 0.85) }, { C.ButtonActive, V4(P.redDark) },
                { C.Header, V4(P.red, 0.30) }, { C.HeaderHovered, V4(P.red, 0.18) }, { C.HeaderActive, V4(P.red, 0.45) },
                { C.ScrollbarBg, ImVec4(0, 0, 0, 0) }, { C.ScrollbarGrab, V4(P.line) },
                { C.ScrollbarGrabHovered, V4(P.red, 0.8) }, { C.ScrollbarGrabActive, V4(P.red) },
                { C.Separator, V4(P.line, 0.8) }, { C.CheckMark, V4(P.redSoft) },
                { C.TextSelectedBg, V4(P.red, 0.35) },
            }
        end
        for _, s in ipairs(styleCols) do imgui.PushStyleColor(s[1], s[2]) end
        local S = imgui.StyleVar
        imgui.PushStyleVarFloat(S.Alpha, alpha)
        imgui.PushStyleVarFloat(S.WindowRounding, 12)
        imgui.PushStyleVarFloat(S.WindowBorderSize, 1)
        imgui.PushStyleVarVec2(S.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(S.FrameRounding, 8)
        imgui.PushStyleVarVec2(S.ItemSpacing, V2(10, 10))
        imgui.PushStyleVarVec2(S.FramePadding, V2(10, 7))
        imgui.PushStyleVarFloat(S.ChildRounding, 12)
        imgui.PushStyleVarFloat(S.ScrollbarSize, 8)
        imgui.PushStyleVarFloat(S.ScrollbarRounding, 8)
        imgui.PushStyleVarFloat(S.GrabRounding, 8)
    end
    local function popStyle()
        imgui.PopStyleVar(11)
        imgui.PopStyleColor(#styleCols)
    end

    ---------------------------------------------------------------- window
    local TOP = 52
    local titles = {
        { "Dashboard", "Ringkasan akses admin dan aktivitas server.", "OVERVIEW" },
        { "Manajemen Pemain", "Cari pemain dan jalankan tindakan sesuai level akses.", "LIVE PLAYERS" },
        { "Daftar Command", "Telusuri command admin yang tersedia untuk levelmu.", "COMMAND CENTER" },
        { "Database Browser", "Lihat tabel yang diizinkan dalam mode read-only.", "READ ONLY" },
    }
    local navNames = { "Dashboard", "Players", "Commands", "Database" }

    local function draw()
        local io = imgui.GetIO()
        dt = io.DeltaTime > 0 and io.DeltaTime or 0.016
        local d = io.DisplaySize
        local W, H = math.min(1040, d.x - 32), math.min(640, d.y - 32)

        local e
        if closing then
            local k = clamp((os.clock() - closing) / 0.22, 0, 1)
            if k >= 1 then open, closing = false, nil; return end
            e = 1 - ease(k)
        else
            e = ease(clamp((os.clock() - animationStarted) / 0.5, 0, 1))
        end
        e = math.max(e, 0.02)
        galpha = e

        if autoRefresh[0] and os.clock() - lastReq > 20 then requestPlayers() end

        imgui.SetNextWindowPos(V2((d.x - W) / 2, (d.y - H) / 2 + (1 - e) * 30), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
        pushStyle(e)
        local WF = imgui.WindowFlags
        imgui.Begin("##adminpanel", nil, WF.NoTitleBar + WF.NoResize + WF.NoSavedSettings
            + WF.NoScrollbar + WF.NoScrollWithMouse + WF.NoCollapse)
        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()

        ---------------- topbar (gradient merah)
        local cL, cR = { 210, 24, 40 }, { 120, 12, 22 }
        dl:AddRectFilled(wp, V2(wp.x + 40, wp.y + TOP), U(cL), 12)
        dl:AddRectFilled(V2(wp.x, wp.y + 24), V2(wp.x + 40, wp.y + TOP), U(cL))
        dl:AddRectFilled(V2(wp.x + W - 40, wp.y), V2(wp.x + W, wp.y + TOP), U(cR), 12)
        dl:AddRectFilled(V2(wp.x + W - 40, wp.y + 24), V2(wp.x + W, wp.y + TOP), U(cR))
        dl:AddRectFilledMultiColor(V2(wp.x + 20, wp.y), V2(wp.x + W - 20, wp.y + TOP), U(cL), U(cR), U(cR), U(cL))
        dl:AddLine(V2(wp.x, wp.y + TOP), V2(wp.x + W, wp.y + TOP), U({ 0, 0, 0 }, 0.5), 1)

        if logoTexture then
            dl:AddImage(logoTexture, V2(wp.x + 16, wp.y + 8), V2(wp.x + 52, wp.y + 44))
        else
            dl:AddRectFilled(V2(wp.x + 16, wp.y + 10), V2(wp.x + 48, wp.y + 42), U({ 0, 0, 0 }, 0.3), 9)
            text(dl, wp.x + 26, wp.y + 15, 22, U(P.text), "P")
        end
        text(dl, wp.x + 60, wp.y + 14, 22, U(P.text), "PekanAdmin")

        -- hamburger (collapse sidebar)
        imgui.SetCursorPos(V2(216, 10))
        if imgui.InvisibleButton("##burger", V2(32, 32)) then collapsed = not collapsed end
        local bh = approach("burger", imgui.IsItemHovered() and 1 or 0, 14)
        dl:AddRectFilled(V2(wp.x + 216, wp.y + 10), V2(wp.x + 248, wp.y + 42), U({ 255, 255, 255 }, 0.12 * bh), 8)
        for i = -1, 1 do
            dl:AddLine(V2(wp.x + 224, wp.y + 26 + i * 5), V2(wp.x + 240, wp.y + 26 + i * 5), U(P.text), 2)
        end

        -- badge level + status online + tombol tutup
        local pulse = (os.clock() % 1.6) / 1.6
        local lvTxt = ("ADMIN LV %d"):format(level)
        local pw = tw(lvTxt, 12) + 18
        pill(dl, wp.x + W - 66 - pw, wp.y + 14, lvTxt, 12, U({ 0, 0, 0 }, 0.28), U(P.text))
        local ox = wp.x + W - 66 - pw - 74
        dl:AddCircleFilled(V2(ox, wp.y + 26), 4, U(P.green), 12)
        dl:AddCircle(V2(ox, wp.y + 26), 4 + pulse * 6, U(P.green, 1 - pulse), 16, 1.5)
        text(dl, ox + 12, wp.y + 19, 13, U(P.text), "ONLINE")

        imgui.SetCursorPos(V2(W - 48, 10))
        if imgui.InvisibleButton("##close", V2(32, 32)) then requestClose() end
        local ch = approach("closeb", imgui.IsItemHovered() and 1 or 0, 14)
        local cx, cy = wp.x + W - 32, wp.y + 26
        dl:AddCircleFilled(V2(cx, cy), 16, U({ 0, 0, 0 }, 0.18 + 0.25 * ch), 20)
        dl:AddLine(V2(cx - 5, cy - 5), V2(cx + 5, cy + 5), U(P.text), 2)
        dl:AddLine(V2(cx - 5, cy + 5), V2(cx + 5, cy - 5), U(P.text), 2)

        ---------------- sidebar
        local sbW = approach("sb", collapsed and 68 or 212, 11)
        local ta = clamp((sbW - 110) / 90, 0, 1)
        local sx, sy = wp.x, wp.y + TOP
        dl:AddRectFilled(V2(sx, sy), V2(sx + sbW, wp.y + H), U(P.panel), 12)
        dl:AddRectFilled(V2(sx, sy), V2(sx + sbW, wp.y + H - 12), U(P.panel))
        dl:AddRectFilled(V2(sx + sbW - 12, wp.y + H - 12), V2(sx + sbW, wp.y + H), U(P.panel))
        dl:AddLine(V2(sx + sbW, sy), V2(sx + sbW, wp.y + H), U(P.line, 0.8), 1)

        imgui.SetCursorPos(V2(0, TOP))
        imgui.PushStyleColor(imgui.Col.ChildBg, ImVec4(0, 0, 0, 0))
        imgui.BeginChild("##side", V2(sbW, H - TOP), false, WF.NoScrollbar)
        local sdl = imgui.GetWindowDrawList()
        local o = imgui.GetWindowPos()
        local keep = galpha

        -- profil
        local av = V2(o.x + 34, o.y + 38)
        sdl:AddCircleFilled(av, 22, U(P.red, 0.2), 28)
        sdl:AddCircle(av, 22, U(P.red, 0.8), 28, 2)
        text(sdl, av.x - 7, av.y - 11, 22, U(P.redSoft), myName:sub(1, 1):upper())
        sdl:AddCircleFilled(V2(av.x + 16, av.y + 16), 5, U(P.panel), 12)
        sdl:AddCircleFilled(V2(av.x + 16, av.y + 16), 3.5, U(P.green), 12)
        galpha = keep * ta
        text(sdl, o.x + 66, o.y + 24, 15, U(P.text), myName:sub(1, 16))
        text(sdl, o.x + 66, o.y + 44, 12, U(P.green), "Online")
        galpha = keep

        -- search
        if ta > 0.3 then
            imgui.SetCursorPos(V2(14, 78))
            imgui.PushItemWidth(sbW - 28)
            if imgui.InputTextWithHint("##sidesearch", "Cari command...", cmdSearch, ffi.sizeof(cmdSearch)) then
                setTab(3)
            end
            imgui.PopItemWidth()
        end

        -- navigasi
        local navY = 126
        local indY = approach("navY", (tab - 1) * 50, 14)
        local iw = sbW - 20
        galpha = keep
        sdl:AddRectFilled(V2(o.x + 8, o.y + navY + indY - 2), V2(o.x + 12 + iw, o.y + navY + indY + 44), U(P.red, 0.12), 12)
        sdl:AddRectFilledMultiColor(V2(o.x + 10, o.y + navY + indY), V2(o.x + 10 + iw, o.y + navY + indY + 42),
            U(P.red), U(P.redDark), U(P.redDark), U(P.red))
        for i, n in ipairs(navNames) do
            imgui.SetCursorPos(V2(10, navY + (i - 1) * 50))
            if imgui.InvisibleButton("##nav" .. i, V2(iw, 42)) then
                setTab(i)
                if i == 4 and #tables == 0 and level >= 6 then requestTables() end
            end
            local hovered = imgui.IsItemHovered()
            local hv = approach("nav" .. i, hovered and 1 or 0, 14)
            local act = approach("navact" .. i, tab == i and 1 or 0, 12)
            local a, b = imgui.GetItemRectMin(), imgui.GetItemRectMax()
            if tab ~= i then
                sdl:AddRectFilled(a, b, U(P.cardHi, hv * 0.8), 10)
            end
            local colv = {
                P.muted[1] + (P.text[1] - P.muted[1]) * math.max(act, hv * 0.8),
                P.muted[2] + (P.text[2] - P.muted[2]) * math.max(act, hv * 0.8),
                P.muted[3] + (P.text[3] - P.muted[3]) * math.max(act, hv * 0.8),
            }
            icon(sdl, i, a.x + 24, (a.y + b.y) / 2, U(colv))
            galpha = keep * ta
            text(sdl, a.x + 50 + hv * 3, (a.y + b.y) / 2 - 8, 15, U(colv), n)
            galpha = keep
            if hovered and collapsed then imgui.SetTooltip(n) end
        end

        -- hak akses (bawah)
        local fy = H - TOP - 96
        if ta > 0.05 then
            galpha = keep * ta
            sdl:AddRectFilled(V2(o.x + 12, o.y + fy), V2(o.x + sbW - 12, o.y + fy + 62), U(P.card), 10)
            text(sdl, o.x + 24, o.y + fy + 10, 11, U(P.muted), "HAK AKSES")
            text(sdl, o.x + 24, o.y + fy + 26, 14, U(P.redSoft), ("ADMIN LEVEL %d"):format(level))
            local lv = approach("lvbar", level / 7, 5)
            dl = sdl
            sdl:AddRectFilled(V2(o.x + 24, o.y + fy + 48), V2(o.x + sbW - 24, o.y + fy + 53), U(P.line), 3)
            sdl:AddRectFilled(V2(o.x + 24, o.y + fy + 48), V2(o.x + 24 + (sbW - 48) * lv, o.y + fy + 53), U(P.red), 3)
            galpha = keep
        else
            text(sdl, o.x + 34 - tw("L" .. level, 14) / 2, o.y + fy + 20, 14, U(P.redSoft), "L" .. level)
        end
        galpha = keep * ta
        text(sdl, o.x + 18, o.y + H - TOP - 26, 11, U(P.muted), "PekanCommunity (c) 2026")
        galpha = keep
        imgui.EndChild()
        imgui.PopStyleColor(1)

        ---------------- konten
        local cw0 = W - sbW
        imgui.SetCursorPos(V2(sbW, TOP))
        imgui.PushStyleColor(imgui.Col.ChildBg, ImVec4(0, 0, 0, 0))
        imgui.BeginChild("##content", V2(cw0, H - TOP), false, WF.NoScrollbar)
        local cdl = imgui.GetWindowDrawList()
        local co = imgui.GetWindowPos()
        local te = ease(clamp((os.clock() - tabStart) / 0.35, 0, 1))
        local base = galpha
        local heading = titles[tab]

        galpha = base * te
        text(cdl, co.x + 20, co.y + 14 + (1 - te) * 8, 22, U(P.text), "Hi, " .. myName)
        text(cdl, co.x + 20, co.y + 42 + (1 - te) * 8, 13, U(P.muted), heading[1] .. "  -  " .. heading[2])
        local tagW = tw(heading[3], 11) + 20
        pill(cdl, co.x + cw0 - tagW - 36, co.y + 18, heading[3], 11, U(P.red, 0.16), U(P.redSoft))
        cdl:AddLine(V2(co.x + 20, co.y + 72), V2(co.x + cw0 - 20, co.y + 72), U(P.line, 0.6), 1)

        imgui.SetCursorPos(V2(20, 84 + (1 - te) * 10))
        local cw, ch = cw0 - 40, H - TOP - 84 - 36
        if tab == 1 then tabDashboard(cw, ch)
        elseif tab == 2 then tabPlayers(cw, ch)
        elseif tab == 3 then tabCommands(cw, ch)
        else tabDatabase(cw, ch) end

        -- status bar
        galpha = base
        local sc = statusKind == "err" and P.red or (statusKind == "ok" and P.green or P.blue)
        local by = co.y + H - TOP - 24
        cdl:AddCircleFilled(V2(co.x + 26, by + 8), 4, U(sc), 12)
        text(cdl, co.x + 38, by, 13, U(P.muted), status)
        imgui.EndChild()
        imgui.PopStyleColor(1)

        imgui.End()
        popStyle()
        galpha = 1
    end

    local frame = imgui.OnFrame(
        function() return open and level >= 1 and isSampAvailable() and isPlayerUiReady() end, draw)
    frame.LockPlayer = true

    return {
        open = function()
            if level < 1 then sendChat("/apanel"); return end
            openPanel()
        end,
        close = requestClose,
        isOpen = function() return open end,
        onServerMessage = onServerMessage,
        reset = function() open, closing, level, players, tables, rows = false, nil, 0, {}, {}, {} end,
    }
end
