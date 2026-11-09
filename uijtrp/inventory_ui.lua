-- inventory_ui.lua
-- Inventory ala FiveM (mimgui): grid slot | kolom aksi | panel detail + sekitar.
--
-- SUMBER DATA
--   1) TEXTDRAW server  -> dibaca lewat samp.events (onShowTextDraw / onTextDrawSetString /
--                          onTextDrawHide), diklik lewat sampSendClickTextdraw().
--
-- PERINTAH BANTU (di game)
--   /invtd    : tulis semua textdraw yang sedang tampil ke moonloader/inventory_textdraw_dump.txt
--               (kirim isinya kalau auto-deteksi belum pas dengan server kamu)
--   /invdemo  : buka preview UI dengan item palsu (tanpa server)

------------------------------------------------------------------ KONFIGURASI
local CFG = {
    hideNative   = false,
    autoHook     = false,
    autoTextdrawOpen = true,
    triggerMinSelectable = 2,
    -- batasi ID textdraw inventory (disarankan kalau sudah tahu), contoh: { 2100, 2300 }
    idRange      = nil,
    burstWindow  = 1.5,    -- detik; textdraw yang muncul sebelum trigger dianggap satu paket
    slotMargin   = 14,     -- toleransi (koordinat 640x480) teks dianggap milik slot
    actionMargin = 48,     -- jarak maksimal label tombol ke area klik textdraw
    -- teks textdraw yang bisa diklik dan dipetakan ke tombol aksi (huruf kecil, harus sama persis)
    actionWords  = {
        use   = { "gunakan", "pakai", "use" },
        give  = { "beri", "berikan", "give" },
        drop  = { "buang", "drop" },
        amount = { "amount" },
        close = { "tutup", "close", "x" },
    },
    debugFile    = "inventory_textdraw_dump.txt",
}

local function formatRupiah(amount)
    local value = math.floor(tonumber(amount) or 0)
    local negative = value < 0
    local digits = tostring(math.abs(value)):reverse():gsub("(%d%d%d)", "%1."):reverse():gsub("%.$", "")
    return (negative and "-" or "") .. digits
end

------------------------------------------------------------------ PARSER TEXTDRAW (murni, tanpa imgui)
local function cleanText(s)
    s = tostring(s or "")
    s = s:gsub("~n~", " "):gsub("~%a~", ""):gsub("{%x%x%x%x%x%x}", "")
    s = s:gsub("_", " "):gsub("%s+", " ")
    return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

local function parseQty(s)
    local n = s:match("^[xX]%s*(%d+)$") or s:match("^(%d+)%s*[xX]$") or s:match("^(%d+)$")
        or s:match("^%[(%d+)%]$") or s:match("^%((%d+)%)$")
    return n and tonumber(n) or nil
end

local function parseWeight(s)
    local low = s:lower()
    if not (low:find("kg", 1, true) or low:find(".", 1, true)) then return nil end
    local a, b = s:match("(%d+[%.,]?%d*)%s*[kK]?[gG]?%s*/%s*(%d+[%.,]?%d*)")
    if not a then return nil end
    return tonumber((a:gsub(",", "."))), tonumber((b:gsub(",", ".")))
end

local function actionOf(text, cfg)
    local low = text:lower()
    for key, list in pairs(cfg.actionWords) do
        for _, w in ipairs(list) do
            if low == w then return key end
        end
    end
    return nil
end

local function rectOf(t)
    if t.style == 5 then return t.x, t.y, t.x + t.lw, t.y + t.lh end
    local x2 = (t.lw > t.x) and t.lw or (t.x + 30)
    return t.x, t.y, x2, t.y + math.max(t.lsh * 17.6, 16)
end

-- tds: array of { id, text, x, y, model, selectable, style, lw, lh, lsw, lsh }
local function buildFromTextdraws(tds, cfg)
    local out = { slots = {}, count = 0, actions = {}, weight = nil, maxWeight = nil }
    local clickables, texts, actionLabels = {}, {}, {}

    for _, t in ipairs(tds) do
        local act = actionOf(t.text, cfg)
        if act then
            if t.selectable then
                out.actions[act] = out.actions[act] or t.id
            else
                actionLabels[#actionLabels + 1] = { action = act, textdraw = t }
            end
        elseif t.selectable then
            clickables[#clickables + 1] = t
        elseif t.style ~= 4 and t.style ~= 5 and t.text ~= "" then
            texts[#texts + 1] = t
            local cur, max = parseWeight(t.text)
            if cur then out.weight, out.maxWeight = cur, max end
        end
    end

    -- urut baris -> kolom (baris dikuantisasi supaya comparator konsisten)
    table.sort(clickables, function(a, b)
        local ra, rb = math.floor(a.y / 6 + 0.5), math.floor(b.y / 6 + 0.5)
        if ra ~= rb then return ra < rb end
        if a.x ~= b.x then return a.x < b.x end
        return a.id < b.id
    end)

    -- Tombol inventory sering memakai textdraw gambar yang selectable dan label teks
    -- terpisah yang tidak selectable. Petakan label ke area klik terdekat.
    for _, label in ipairs(actionLabels) do
        local best, bd
        for _, button in ipairs(clickables) do
            local x1, y1, x2, y2 = rectOf(button)
            local dx = math.max(x1 - label.textdraw.x, 0, label.textdraw.x - x2)
            local dy = math.max(y1 - label.textdraw.y, 0, label.textdraw.y - y2)
            local d = dx * dx + dy * dy
            if not bd or d < bd then best, bd = button, d end
        end
        if best and bd <= cfg.actionMargin * cfg.actionMargin then
            out.actions[label.action] = out.actions[label.action] or best.id
        end
    end

    local slotClickables = {}
    for _, button in ipairs(clickables) do
        local isAction = false
        for _, id in pairs(out.actions) do
            if id == button.id then isAction = true break end
        end
        if not isAction then slotClickables[#slotClickables + 1] = button end
    end

    -- tempel teks (nama / jumlah) ke slot terdekat
    local attach = {}
    local m = cfg.slotMargin
    for _, tx in ipairs(texts) do
        local best, bd
        for i, s in ipairs(slotClickables) do
            local x1, y1, x2, y2 = rectOf(s)
            if tx.x >= x1 - m and tx.x <= x2 + m and tx.y >= y1 - m and tx.y <= y2 + m * 2 then
                local d = (tx.x - (x1 + x2) / 2) ^ 2 + (tx.y - (y1 + y2) / 2) ^ 2
                if not bd or d < bd then best, bd = i, d end
            end
        end
        if best then
            attach[best] = attach[best] or {}
            table.insert(attach[best], tx)
        end
    end

    for i, s in ipairs(slotClickables) do
        local name, qty
        if s.style ~= 4 and s.style ~= 5 and s.text ~= "" then
            local q = parseQty(s.text)
            if q then qty = q else name = s.text end
        end
        local list = attach[i]
        if list then
            table.sort(list, function(a, b)
                if a.y ~= b.y then return a.y < b.y end
                return a.x < b.x
            end)
            for _, tx in ipairs(list) do
                local q = parseQty(tx.text)
                if q then qty = qty or q
                elseif tx.text:find("%a") then name = name or tx.text end
            end
        end
        if name or (s.model or 0) > 0 then
            out.slots[i] = {
                slot = i, model = s.model, quantity = qty or 1,
                name = name or ("Item " .. tostring(s.model)),
                clickId = s.id, source = "td",
            }
        end
    end
    out.count = #slotClickables
    return out
end

------------------------------------------------------------------ ATURAN IKON
local ICON_RULES = {
    { "medicine", "bandage", "medkit", "alprazolam" },
    { "device", "smartphone", "tablet", "earphone", "radio", "laptop", "boombox", "hacking card" },
    { "drink", "kopi", "sprunk", "teh", "jus", "susu", "botol", "vape" },
    { "food", "nasi", "snack", "ayam", "makanan", "pecel", "bubur", "kebab", "bakso", "daging", "tahu bulat" },
    { "fish", "ikan", "hiu", "penyu" },
    { "fuel", "petrol", "=gas", "jerigen", "oil" },
    { "clothing", "pakaian", "masker", "kevlar", "backpack" },
    { "document", "kta", "document", "surat" },
    { "tool", "clip", "tools", "repair", "pancing", "umpan", "linggis", "kunci", "lockpick",
        "korek", "senter", "pilox" },
    { "warning", "kanabis", "marijuana", "bomb", "petasan" },
    { "money", "uang", "cash", "money" },
    { "weapon", "pistol", "senjata", "weapon", "ammunition" },
    { "material", "batu", "besi", "tembaga", "berlian", "emas", "kayu", "benang", "kain", "boxmats",
        "baja", "material", "kaca", "karet", "plastik", "alumunium", "component", "chip", "uranium",
        "garam", "gula", "beras", "padi", "tebu", "cabe", "bibit" },
}

local function iconForItem(name)
    local value = name:lower()
    for _, rule in ipairs(ICON_RULES) do
        for i = 2, #rule do
            local k = rule[i]
            if k:sub(1, 1) == "=" then
                if value == k:sub(2) then return rule[1] end
            elseif value:find(k, 1, true) then
                return rule[1]
            end
        end
    end
    return "inventory"
end

------------------------------------------------------------------ MODUL
return function(imgui, icons, V2, color, accent, getAccent, sendChat, uiSounds, isPlayerUiReady)
    local MIN_SLOTS = 30

    local open = false
    local weight, maxWeight = 0, 50
    local items = {}
    local nearbyPlayers = {}
    local preferredGiveTarget = nil
    local selectedSlot = nil
    local giveMode = false
    local amount = imgui.new.int(1)
    local openedAt = 0
    local source = "td"             -- "td" | "server" | "demo"
    local shopOpen = false
    local shopSuppressed = false
    local shopTitle = ""
    local shopItems = {}
    local selectedShopItem = nil
    local shopAmount = imgui.new.int(1)

    -- state textdraw
    local tdAll, tdSession = {}, {}
    local tdActive, tdTrigger, tdTriggerGone = false, nil, nil
    local pendingTrigger, pendingTriggerAt = nil, nil
    local tdSlots, tdSlotCount, tdActions = {}, 0, {}
    local dirty, lastRebuild = false, 0

    local noticeText, noticeUntil = "", 0
    local animNow = 1
    local imguiStack = {}

    local function beginTracked(method, ...)
        local result = imgui[method](...)
        imguiStack[#imguiStack + 1] = method
        return result
    end

    local function endTracked(method, endMethod)
        imgui[endMethod]()
        if imguiStack[#imguiStack] == method then
            imguiStack[#imguiStack] = nil
        end
    end

    local function unwindImguiStack()
        while #imguiStack > 0 do
            local method = imguiStack[#imguiStack]
            imguiStack[#imguiStack] = nil
            local endMethod = method == "Begin" and "End"
                or method == "BeginChild" and "EndChild"
                or "EndTooltip"
            pcall(imgui[endMethod])
        end
    end

    ------------------------------------------------------------------ util
    local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end
    local GRAY = V4(0.64, 0.62, 0.74, 1)
    local WHITE = V4(0.96, 0.95, 0.98, 1)
    local BTN = {
        danger = { V4(0.86, 0.26, 0.24, 1), V4(0.96, 0.34, 0.31, 1) },
        glass  = { V4(1, 1, 1, 0.09), V4(1, 1, 1, 0.17) },
    }

    local function C(r, g, b, a) return color(r, g, b, (a or 1) * animNow) end
    local function ACC(a)
        local r, g, b = getAccent()
        return C(r, g, b, a)
    end

    local function ease(t)
        t = math.min(1, math.max(0, t))
        return 1 - (1 - t) ^ 3
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

    local function tintFor(name)
        local h = 11
        for i = 1, #name do h = (h * 31 + name:byte(i)) % 997 end
        return hsv((h % 360) / 360, 0.55, 0.95)
    end

    local function fitText(text, maxW)
        if imgui.CalcTextSize(text).x <= maxW then return text end
        while #text > 1 and imgui.CalcTextSize(text .. "..").x > maxW do
            text = text:sub(1, -2)
        end
        return text .. ".."
    end

    local function say(msg)
        if sampAddChatMessage then pcall(sampAddChatMessage, "[INV] " .. msg, -1) end
    end

    local function playHover(key)
        if uiSounds and type(uiSounds.hover) == "function" then
            uiSounds.hover(key)
        end
    end

    local function notice(msg)
        noticeText, noticeUntil = msg, os.clock() + 2.6
    end

    local function later(fn)
        if lua_thread and lua_thread.create then lua_thread.create(fn) else fn() end
    end

    local function pause(ms)
        if lua_thread and wait then wait(ms) end
    end

    local function clickTd(id)
        if sampSendClickTextdraw then pcall(sampSendClickTextdraw, id) end
    end

    local function styledButton(label, w, h, kind)
        local c = BTN[kind or "glass"]
        if kind == "accent" then
            local r, g, b = getAccent()
            c = {
                V4(r * 0.75, g * 0.75, b * 0.75, 1),
                V4(math.min(1, r * 1.15), math.min(1, g * 1.15), math.min(1, b * 1.15), 1)
            }
        end
        imgui.PushStyleColor(imgui.Col.Button, c[1])
        imgui.PushStyleColor(imgui.Col.ButtonHovered, c[2])
        imgui.PushStyleColor(imgui.Col.ButtonActive, c[2])
        imgui.PushStyleColor(imgui.Col.Text, WHITE)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 9)
        local clicked = imgui.Button(label, V2(w, h))
        imgui.PopStyleVar(1)
        imgui.PopStyleColor(4)
        if imgui.IsItemHovered() then playHover(label) end
        return clicked
    end

    ------------------------------------------------------------------ data slot
    local function getSlot(i)
        if source == "td" then return tdSlots[i] end
        return items[i]
    end

    local function slotCount()
        if source == "td" then return tdSlotCount end
        return #items
    end

    local function findSelected()
        if not selectedSlot then return nil end
        for i = 1, slotCount() do
            local it = getSlot(i)
            if it and it.slot == selectedSlot then return it end
        end
        return nil
    end

    ------------------------------------------------------------------ textdraw: tangkap & susun
    local function inRange(id)
        local r = CFG.idRange
        return not r or (id >= r[1] and id <= r[2])
    end

    local function matchesTrigger(text)
        return text:lower():find("kg", 1, true) ~= nil and parseWeight(text) ~= nil
    end

    local function recordTd(id, d)
        local pos = d.position or {}
        local sel = d.selectable
        local t = {
            id = id, text = cleanText(d.text),
            x = pos.x or 0, y = pos.y or 0,
            model = d.modelId or 0,
            selectable = (sel == true) or (type(sel) == "number" and sel ~= 0),
            style = d.style or 0,
            lw = d.lineWidth or 0, lh = d.lineHeight or 0,
            lsw = d.letterWidth or 0, lsh = d.letterHeight or 0,
            shown = os.clock(),
        }
        tdAll[id] = t
        return t
    end

    local function rebuildFromTextdraws()
        dirty = false
        lastRebuild = os.clock()
        local sub = {}
        for id in pairs(tdSession) do
            if tdAll[id] then sub[#sub + 1] = tdAll[id] end
        end
        local res = buildFromTextdraws(sub, CFG)
        tdSlots, tdSlotCount, tdActions = res.slots, res.count, res.actions
        if res.weight then
            weight = res.weight
            if res.maxWeight then maxWeight = res.maxWeight end
        end
    end

    local function deactivateTextdraw()
        tdActive, tdTrigger, tdTriggerGone = false, nil, nil
        tdSession = {}
        if source == "td" then
            open = false
            shopOpen, shopItems, selectedShopItem = false, {}, nil
            selectedSlot = nil
            giveMode = false
        end
    end

    local function activateTextdraw(triggerId)
        pendingTrigger, pendingTriggerAt = nil, nil
        tdActive, tdTrigger, tdTriggerGone = true, triggerId, nil
        tdSession = {}
        local now = os.clock()
        for id, t in pairs(tdAll) do
            if inRange(id) and (CFG.idRange or now - t.shown <= CFG.burstWindow) then
                tdSession[id] = true
                if CFG.hideNative and id ~= triggerId then pcall(sampTextdrawDelete, id) end
            end
        end
        source = "td"
        if not open then
            uiSounds.play("open")
            openedAt = os.clock()
        end
        open = true
        selectedSlot = nil
        giveMode = false
        dirty = true
    end

    local function openForPlayer(targetId)
        targetId = tonumber(targetId)
        if not targetId or targetId < 0 then return false end
        preferredGiveTarget = targetId
        sendChat("/rpui_inventory_data")
        return true
    end

    -- dipanggil dari hook samp.events (atau manual dari script utama)
    local function onShowTextDraw(id, data)
        if shopSuppressed then return nil end
        if not tdActive and not CFG.autoTextdrawOpen then return nil end
        local t = recordTd(id, data)
        if not tdActive then
            local now = os.clock()
            if inRange(id) and matchesTrigger(t.text) then
                pendingTrigger, pendingTriggerAt = id, now
            end
            if pendingTrigger and now - pendingTriggerAt > CFG.burstWindow then
                pendingTrigger, pendingTriggerAt = nil, nil
            end
            if pendingTrigger then
                local selectableCount = 0
                for candidateId, candidate in pairs(tdAll) do
                    if inRange(candidateId) and candidate.selectable
                        and now - candidate.shown <= CFG.burstWindow then
                        selectableCount = selectableCount + 1
                    end
                end
                if selectableCount >= CFG.triggerMinSelectable then
                    activateTextdraw(pendingTrigger)
                end
            end
            if tdActive then
                if CFG.hideNative then return false end
            end
            return nil
        end
        if tdTriggerGone and matchesTrigger(t.text) then
            tdTrigger, tdTriggerGone = id, nil
        end
        if inRange(id) then
            tdSession[id] = true
            dirty = true
            if CFG.hideNative then return false end
        end
        return nil
    end

    local function onTextDrawSetString(id, text)
        if shopSuppressed then return nil end
        local t = tdAll[id]
        if t then
            t.text = cleanText(text)
            if tdSession[id] then
                dirty = true
                if CFG.hideNative then return false end
            end
        end
        return nil
    end

    local function onTextDrawHide(id)
        local wasSession = tdSession[id]
        tdAll[id] = nil
        if id == pendingTrigger then pendingTrigger, pendingTriggerAt = nil, nil end
        if wasSession then
            tdSession[id] = nil
            dirty = true
            if id == tdTrigger then tdTriggerGone = os.clock() end
        end
        return nil
    end

    ------------------------------------------------------------------ dump & demo
    local function dumpTextdraws()
        local base = (getWorkingDirectory and getWorkingDirectory()) or "."
        local path = base .. "/" .. CFG.debugFile
        local f = io.open(path, "w")
        if not f then say("Gagal menulis " .. path) return end
        local ids = {}
        for id in pairs(tdAll) do ids[#ids + 1] = id end
        table.sort(ids)
        f:write(string.format("# total textdraw terekam: %d | session aktif: %s\n", #ids, tostring(tdActive)))
        for _, id in ipairs(ids) do
            local t = tdAll[id]
            f:write(string.format(
                "id=%d style=%d sel=%s model=%d pos=(%.1f,%.1f) lineW/H=(%.1f,%.1f) letter=(%.2f,%.2f) session=%s text=%q\n",
                id, t.style, tostring(t.selectable), t.model, t.x, t.y, t.lw, t.lh, t.lsw, t.lsh,
                tostring(tdSession[id] == true), t.text))
        end
        f:close()
        say(string.format("%d textdraw ditulis ke %s", #ids, path))
    end

    local function loadDemo()
        source = "demo"
        open = true
        openedAt = os.clock()
        selectedSlot, giveMode = nil, false
        weight, maxWeight = 18.40, 50
        amount[0] = 1
        local list = {
            { "Smartphone", 1 }, { "Nasi Bungkus", 4 }, { "Kopi Susu", 2 }, { "Bandage", 6 },
            { "Pistol", 1 }, { "Uang Cash", 15000 }, { "Linggis", 1 }, { "Lockpick", 3 },
            { "Ikan Hiu", 2 }, { "Besi", 12 }, { "Kain", 8 }, { "Jerigen", 1 },
            { "Radio", 1 }, { "Kevlar", 1 }, { "KTA", 1 },
        }
        items = {}
        for i, e in ipairs(list) do
            items[#items + 1] = { slot = i, model = 0, quantity = e[2], name = e[1], source = "demo" }
        end
    end

    ------------------------------------------------------------------ aksi
    local function reload()
        if source == "td" then dirty = true end
        if source == "server" then sendChat("/rpui_inventory_data") end
    end

    local function show()
        if not tdActive then return end
        if shopOpen then sendChat("/rpui_shop_close") end
        shopOpen, shopItems, selectedShopItem = false, {}, nil
        uiSounds.play("open")
        open = true
        openedAt = os.clock()
        selectedSlot = nil
        giveMode = false
        nearbyPlayers = {}
        source = "td"
        dirty = true
    end

    local function close()
        if open then
            if shopOpen then sendChat("/rpui_shop_close") end
            if source == "td" then
                if tdActions.close then clickTd(tdActions.close) else clickTd(65535) end
            elseif source == "server" then
                sendChat("/rpui_inventory_close")
            end
            uiSounds.play("close")
        end
        if source == "td" then
            tdActive, tdTrigger, tdTriggerGone = false, nil, nil
            tdSession = {}
        end
        open = false
        selectedSlot = nil
        giveMode = false
    end

    local function runTdAction(item, key, label)
        local btn = tdActions[key]
        later(function()
            clickTd(item.clickId)
            if btn then
                pause(120)
                clickTd(btn)
            else
                notice("Tombol '" .. label .. "' tidak ditemukan di textdraw (item hanya dipilih)")
            end
        end)
    end

    local function demoConsume(item, qty)
        item.quantity = item.quantity - qty
        if item.quantity <= 0 then
            for i, it in ipairs(items) do
                if it == item then table.remove(items, i) break end
            end
            for i, it in ipairs(items) do it.slot = i end
            selectedSlot = nil
        end
    end

    local function useItem(item)
        uiSounds.play("success")
        if item.source == "td" then
            runTdAction(item, "use", "Gunakan")
        elseif item.source == "server" then
            sendChat(string.format("/rpui_inv_use %d", item.slot))
        else
            notice("Demo: memakai " .. item.name)
            demoConsume(item, 1)
        end
    end

    local function dropItem(item, qty)
        if item.source == "td" then
            runTdAction(item, "drop", "Buang")
        elseif item.source == "server" then
            sendChat(string.format("/rpui_inv_drop %d %d", item.slot, qty))
        else
            notice("Demo: membuang " .. qty .. " " .. item.name)
            demoConsume(item, qty)
        end
    end

    local function loadNearbyPlayers()
        nearbyPlayers = {}
        if source == "demo" then
            nearbyPlayers = { { id = 12, name = "Budi_Santoso" }, { id = 27, name = "Siti_Aminah" } }
        elseif source == "server" then
            sendChat("/rpui_inv_nearby")
        end
    end

    local function giveItem(item)
        if item.source == "td" then
            runTdAction(item, "give", "Beri")
        else
            giveMode = true
            loadNearbyPlayers()
        end
    end

    local function giveTo(item, qty, target)
        if source == "demo" then
            notice(string.format("Demo: memberi %d %s ke %s", qty, item.name, target.name))
            demoConsume(item, qty)
            giveMode = false
        elseif source == "server" then
            sendChat(string.format("/rpui_inv_give %d %d %d", item.slot, qty, target.id))
            giveMode = false
        end
    end

    ------------------------------------------------------------------ protokol server
    local function onServerMessage(text)
        text = tostring(text or "")
            :gsub("{%x%x%x%x%x%x}", "")
            :gsub("^%s+", "")
            :gsub("%s+$", "")

        if text == "@PBRPUI:INV:NATIVE:SHOP:OPEN" then
            shopSuppressed = true
            deactivateTextdraw()
            open = false
            selectedSlot = nil
            giveMode = false
            shopOpen, shopItems, selectedShopItem = false, {}, nil
            return true
        elseif text == "@PBRPUI:INV:NATIVE:SHOP:CLOSE" then
            shopSuppressed = false
            return true
        end

        local inventoryWeight = text:match("^@PBRPUI:INV:BEGIN:([%d%.%-]+):%d+$")
        if inventoryWeight then
            weight = tonumber(inventoryWeight) or 0
            maxWeight = 50
            items = {}
            nearbyPlayers = {}
            selectedSlot = nil
            giveMode = false
            source = "server"
            shopOpen, shopItems, selectedShopItem = false, {}, nil
            if not open then
                openedAt = os.clock()
                uiSounds.play("open")
            end
            open = true
            return true
        end

        local slot, model, quantity, name =
            text:match("^@PBRPUI:INV:ITEM:(%d+):(%d+):(%d+):(.+)$")
        if slot then
            if source == "server" then
                items[#items + 1] = {
                    slot = tonumber(slot),
                    model = tonumber(model),
                    quantity = tonumber(quantity),
                    name = name,
                    source = "server",
                }
            end
            return true
        end
        if text == "@PBRPUI:INV:END" then
            return true
        end
        if text == "@PBRPUI:INV:CLOSE" then
            open = false
            selectedSlot = nil
            giveMode = false
            items = {}
            preferredGiveTarget = nil
            return true
        end
        if text == "@PBRPUI:INV:PLAYERS:BEGIN" then
            nearbyPlayers = {}
            return true
        end
        local playerId, playerName = text:match("^@PBRPUI:INV:PLAYER:(%d+):(.+)$")
        if playerId then
            local parsedId = tonumber(playerId)
            if not preferredGiveTarget or parsedId == preferredGiveTarget then
                nearbyPlayers[#nearbyPlayers + 1] = {
                    id = parsedId,
                    name = playerName,
                }
            end
            return true
        end
        if text == "@PBRPUI:INV:PLAYERS:END" then
            preferredGiveTarget = nil
            return true
        end

        if text == "@PBRPUI:INV:REFRESH" then
            sendChat("/rpui_inventory_data")
            return true
        end

        ------------------------------------------------------------------ protokol toko
        local currentShopType, currentShopTitle = text:match("^@PBRPUI:SHOP:BEGIN:(%d+):(.+)$")
        if currentShopType then
            shopOpen = true
            shopTitle = currentShopTitle
            shopItems = {}
            selectedShopItem = nil
            shopAmount[0] = 1
            return true
        end
        local shopIndex, shopModel, shopPrice, shopName =
            text:match("^@PBRPUI:SHOP:ITEM:(%d+):(%d+):(%d+):(.+)$")
        if shopIndex then
            shopItems[#shopItems + 1] = {
                index = tonumber(shopIndex),
                model = tonumber(shopModel),
                price = tonumber(shopPrice),
                name = shopName,
            }
            return true
        end
        if text == "@PBRPUI:SHOP:END" then
            return true
        end
        local shopResult = text:match("^@PBRPUI:SHOP:RESULT:(.+)$")
        if shopResult then
            notice(shopResult)
            return true
        end
        return false
    end

    ------------------------------------------------------------------ drawing: komponen
    local function panelBg(dl, x, y, w, h)
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), C(0.045, 0.040, 0.075, 0.84), 12)
        dl:AddRect(V2(x, y), V2(x + w, y + h), C(0.62, 0.50, 1, 0.18), 12, 0, 1)
        dl:AddRectFilled(V2(x + 14, y), V2(x + w - 14, y + 2), ACC(0.85), 1)
    end

    local function drawSlot(index, item, w)
        local clicked = imgui.InvisibleButton("##slot_" .. index, V2(w, w))
        local hovered = imgui.IsItemHovered()
        local held = imgui.IsItemActive()
        local min = imgui.GetItemRectMin()
        local max = V2(min.x + w, min.y + w)
        local dl = imgui.GetWindowDrawList()
        local isSelected = item ~= nil and selectedSlot == item.slot

        if hovered then playHover("slot" .. index) end

        local fill = item and 0.080 or 0.040
        if hovered then fill = fill + 0.05 end
        if held then fill = fill + 0.04 end
        dl:AddRectFilled(min, max, C(0.58, 0.48, 0.95, fill), 7)
        if isSelected then dl:AddRectFilled(min, max, ACC(0.16), 7) end
        local border = C(1, 1, 1, 0.07)
        if isSelected then border = ACC(1)
        elseif hovered then border = ACC(0.70)
        elseif item then border = C(0.62, 0.50, 1, 0.30) end
        dl:AddRect(min, max, border, 7, 0, isSelected and 1.6 or 1)

        dl:AddText(V2(min.x + 5, min.y + 3), C(1, 1, 1, 0.30), tostring(index))

        if item then
            local r, g, b = tintFor(item.name)
            local size = math.floor(w * 0.42)
            local cx, cy = min.x + w / 2, min.y + w * 0.40
            dl:AddCircleFilled(V2(cx, cy), w * 0.27, C(r, g, b, 0.17), 32)
            icons.draw(dl, iconForItem(item.name), cx - size / 2, cy - size / 2, size,
                C(r, g, b, 1), C(0.07, 0.08, 0.11, 1))
            dl:AddRectFilled(V2(min.x + 8, max.y - 4), V2(max.x - 8, max.y - 2), C(r, g, b, 0.75), 1)

            local q = "x" .. item.quantity
            local qs = imgui.CalcTextSize(q)
            dl:AddText(V2(max.x - qs.x - 5, min.y + 3), C(1, 1, 1, 0.92), q)

            local label = fitText(item.name, w - 8)
            local ls = imgui.CalcTextSize(label)
            dl:AddText(V2(min.x + (w - ls.x) / 2, max.y - ls.y - 7), C(0.94, 0.93, 0.98, 1), label)

            if hovered then
                beginTracked("BeginTooltip")
                imgui.TextColored(WHITE, item.name)
                imgui.TextColored(GRAY, string.format("Slot %d  ·  Jumlah %d", item.slot, item.quantity))
                imgui.TextColored(GRAY, "Klik dua kali untuk menggunakan")
                endTracked("BeginTooltip", "EndTooltip")
                if imgui.IsMouseDoubleClicked(0) then
                    selectedSlot = item.slot
                    useItem(item)
                end
            end
        end

        if clicked then
            if item then
                selectedSlot = item.slot
                amount[0] = 1
                -- mode textdraw: pilih item di server juga supaya state-nya sama
                if item.source == "td" then clickTd(item.clickId) end
            else
                selectedSlot = nil
            end
        end
    end

    local function drawGrid(w, h, cols, slotW, gap)
        local total = math.max(MIN_SLOTS, math.ceil(slotCount() / cols) * cols)

        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(gap, gap))
        for i = 1, total do
            if (i - 1) % cols ~= 0 then imgui.SameLine(0, gap) end
            drawSlot(i, getSlot(i), slotW)
        end
        imgui.PopStyleVar(1)

        local dl = imgui.GetWindowDrawList()
        local wp = imgui.GetWindowPos()
        local cx, cy = wp.x + w / 2, wp.y + h / 2
        if source == "td" and slotCount() == 0 then
            local msg = "Textdraw slot tidak terdeteksi. Ketik /invtd lalu kirim file dump-nya."
            local ts = imgui.CalcTextSize(msg)
            dl:AddText(V2(cx - ts.x / 2, cy - ts.y / 2), C(1, 0.65, 0.35, 1), msg)
        end
    end

    ------------------------------------------------------------------ aksi (tombol tengah)
    local ACTIONS = {
        { id = "use",     label = "PAKAI", icon = "medicine",  kind = "accent", needsItem = true },
        { id = "give",    label = "BERI",  icon = "inventory", kind = "accent", needsItem = true },
        { id = "drop",    label = "BUANG", icon = "warning",   kind = "danger", needsItem = true },
        { id = "refresh", label = "MUAT",  icon = "tool",      kind = "accent" },
        { id = "close",   label = "TUTUP", icon = "document",  kind = "danger" },
    }

    local function actionButton(a, w, h, enabled)
        local clicked = imgui.InvisibleButton("##action_" .. a.id, V2(w, h))
        local hovered = imgui.IsItemHovered()
        local held = imgui.IsItemActive()
        local min = imgui.GetItemRectMin()
        local max = V2(min.x + w, min.y + h)
        local dl = imgui.GetWindowDrawList()
        local dim = enabled and 1 or 0.35
        local r, g, b = 0.62, 0.50, 1.0
        if a.kind == "danger" then r, g, b = 0.95, 0.32, 0.30 end
        local fill = 0.10
        if enabled and hovered then fill = fill + 0.10 end
        if enabled and held then fill = fill + 0.06 end
        dl:AddRectFilled(min, max, C(r, g, b, fill * dim), 10)
        dl:AddRect(min, max, C(r, g, b, (enabled and hovered) and 0.9 or 0.4 * dim), 10, 0, 1.2)
        local col = C(r, g, b, dim)
        if a.id == "close" then
            local cx, cy = min.x + w / 2, min.y + h * 0.36
            dl:AddLine(V2(cx - 8, cy - 8), V2(cx + 8, cy + 8), col, 2.4)
            dl:AddLine(V2(cx + 8, cy - 8), V2(cx - 8, cy + 8), col, 2.4)
        else
            icons.draw(dl, a.icon, min.x + w / 2 - 12, min.y + 8, 24, col, C(0.07, 0.08, 0.11, 1))
        end
        local ts = imgui.CalcTextSize(a.label)
        dl:AddText(V2(min.x + (w - ts.x) / 2, max.y - ts.y - 6), C(0.95, 0.94, 0.98, 0.9 * dim), a.label)
        if enabled and hovered then playHover("act" .. a.id) end
        return clicked and enabled
    end

    local function handleAction(id)
        local item = findSelected()
        if id == "use" and item then useItem(item)
        elseif id == "give" and item then giveItem(item)
        elseif id == "drop" and item then
            local qty = math.max(1, math.min(item.quantity, amount[0]))
            dropItem(item, qty)
        elseif id == "refresh" then reload()
        elseif id == "close" then close() end
    end

    local function actionEnabled(action)
        if action.needsItem and not findSelected() then return false end
        if source == "td" and action.id ~= "refresh" and not tdActions[action.id] then
            return false
        end
        return true
    end

    local function drawActionColumn(x, y, w, h)
        local bh, gap = 58, 10
        local total = #ACTIONS * bh + (#ACTIONS - 1) * gap
        local startY = y + (h - total) / 2
        for i, a in ipairs(ACTIONS) do
            imgui.SetCursorPos(V2(x, startY + (i - 1) * (bh + gap)))
            if actionButton(a, w, bh, actionEnabled(a)) then handleAction(a.id) end
        end
    end

    local function drawActionRow(avail)
        local gap = 6
        local bw = math.max(40, math.min(58, math.floor((avail - gap * (#ACTIONS - 1)) / #ACTIONS)))
        for i, a in ipairs(ACTIONS) do
            if i > 1 then imgui.SameLine(0, gap) end
            if actionButton(a, bw, 54, actionEnabled(a)) then handleAction(a.id) end
        end
    end

    ------------------------------------------------------------------ panel kiri & kanan
    local function drawInventoryPanel(dl, x, y, w, h, cols, slotW, pad, gap)
        panelBg(dl, x, y, w, h)

        imgui.SetCursorPos(V2(x + pad, y + 12))
        imgui.SetWindowFontScale(1.2)
        imgui.TextColored(WHITE, "INVENTORY")
        imgui.SetWindowFontScale(1)
        imgui.SetCursorPos(V2(x + pad, y + 34))
        imgui.TextColored(GRAY, "Tas pribadi")

        local ratio = math.min(1, weight / math.max(1, maxWeight))
        local wtxt = string.format("%.2f / %.2f kg", weight, maxWeight)
        local ts = imgui.CalcTextSize(wtxt)
        local barW = math.min(150, w * 0.42)
        dl:AddText(V2(x + w - pad - ts.x, y + 12), C(0.82, 0.80, 0.92, 1), wtxt)
        local bx, by = x + w - pad - barW, y + 36
        dl:AddRectFilled(V2(bx, by), V2(bx + barW, by + 6), C(1, 1, 1, 0.10), 3)
        local barColor = ACC(1)
        if ratio > 0.9 then barColor = C(0.95, 0.30, 0.28, 1)
        elseif ratio > 0.7 then barColor = C(1, 0.65, 0.25, 1) end
        if ratio > 0 then dl:AddRectFilled(V2(bx, by), V2(bx + barW * ratio, by + 6), barColor, 3) end

        local top = 62
        local gw, gh = w - pad * 2, h - top - pad
        imgui.SetCursorPos(V2(x + pad, y + top))
        imgui.PushStyleColor(imgui.Col.ChildBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrab, V4(1, 1, 1, 0.18))
        imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 6)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        beginTracked("BeginChild", "##inventory_items", V2(gw, gh), false, 0)
        imgui.PopStyleVar(2)
        drawGrid(gw, gh, cols, slotW, gap)
        endTracked("BeginChild", "EndChild")
        imgui.PopStyleColor(3)
    end

    local function drawSide(compact, cols)
        local dl = imgui.GetWindowDrawList()
        local avail = imgui.GetContentRegionAvail().x
        local item = findSelected()

        if shopOpen then
            imgui.TextColored(WHITE, shopTitle)
            imgui.TextColored(GRAY, "Pilih barang toko, atur jumlah, lalu beli.")
            imgui.Separator()

            if selectedShopItem then
                local r, g, b = tintFor(selectedShopItem.name)
                local p = imgui.GetCursorScreenPos()
                imgui.Dummy(V2(avail, 72))
                icons.draw(dl, iconForItem(selectedShopItem.name),
                    p.x + 8, p.y + 8, 48, C(r, g, b, 1), C(0.07, 0.08, 0.11, 1))
                imgui.SetCursorScreenPos(V2(p.x + 64, p.y + 8))
                imgui.TextColored(WHITE, selectedShopItem.name)
                imgui.SetCursorScreenPos(V2(p.x + 64, p.y + 32))
                imgui.TextColored(GRAY, string.format("Rp %s per item", formatRupiah(selectedShopItem.price * 15000)))

                imgui.InputInt("Jumlah##shop_amount", shopAmount, 1, 10)
                if shopAmount[0] < 1 then shopAmount[0] = 1 end
                if shopAmount[0] > 100 then shopAmount[0] = 100 end
                imgui.TextColored(GRAY,
                    string.format("Total: Rp %s", formatRupiah(selectedShopItem.price * shopAmount[0] * 15000)))
                if styledButton("BELI##shop_buy", -1, 38, "accent") then
                    sendChat(string.format("/rpui_shop_buy %d %d",
                        selectedShopItem.index, shopAmount[0]))
                end
            else
                imgui.TextColored(GRAY, "Pilih barang dari daftar toko.")
            end

            imgui.Spacing()
            local listHeight = math.max(100, imgui.GetContentRegionAvail().y - 48)
            beginTracked("BeginChild", "##shop_catalog", V2(0, listHeight), true)
            if #shopItems == 0 then
                imgui.TextColored(GRAY, "Katalog toko kosong.")
            end
            for _, entry in ipairs(shopItems) do
                local selected = selectedShopItem == entry
                local label = string.format("%s  -  Rp %s##shop_item_%d",
                    entry.name, formatRupiah(entry.price * 15000), entry.index)
                if styledButton(label, -1, 38, selected and "accent" or "glass") then
                    selectedShopItem = entry
                    shopAmount[0] = 1
                end
            end
            endTracked("BeginChild", "EndChild")
            if styledButton("KEMBALI KE INVENTORY##shop_close", -1, 34, "danger") then
                sendChat("/rpui_shop_close")
                shopOpen, shopItems, selectedShopItem = false, {}, nil
            end
            return
        end

        if giveMode and item then
            if styledButton("KEMBALI KE ITEM", -1, 30, "glass") then
                giveMode = false
                return
            end
            imgui.Spacing()
            imgui.TextColored(WHITE, "BERI ITEM KE PEMAIN TERDEKAT")
            imgui.TextColored(GRAY, "Pemain harus berada dalam jarak 2,5 meter.")
            imgui.Spacing()
            if #nearbyPlayers == 0 then imgui.TextColored(GRAY, "Tidak ada pemain terdekat.") end
            for _, target in ipairs(nearbyPlayers) do
                if styledButton(target.name .. "  [ID " .. target.id .. "]##give_target_" .. target.id,
                    -1, 38, "glass") then
                    giveTo(item, math.max(1, math.min(item.quantity, amount[0])), target)
                end
                imgui.Spacing()
            end
            if styledButton("CARI ULANG PEMAIN", -1, 34, "accent") then loadNearbyPlayers() end
            if compact then imgui.Spacing(); drawActionRow(avail) end
            return
        end
        giveMode = false

        imgui.TextColored(GRAY, "DETAIL ITEM")
        imgui.Spacing()

        if not item then
            local p = imgui.GetCursorScreenPos()
            imgui.Dummy(V2(avail, 84))
            local cx = p.x + avail / 2
            dl:AddCircleFilled(V2(cx, p.y + 34), 28, C(1, 1, 1, 0.05), 32)
            icons.draw(dl, "inventory", cx - 12, p.y + 22, 24, C(1, 1, 1, 0.35), C(0.07, 0.08, 0.11, 1))
            imgui.TextColored(WHITE, "Pilih sebuah item")
            imgui.TextWrapped("Klik slot untuk memilih, dua kali untuk langsung memakai.")
        else
            local r, g, b = tintFor(item.name)
            local p = imgui.GetCursorScreenPos()
            local box = 64
            imgui.Dummy(V2(avail, box + 6))
            dl:AddRectFilled(V2(p.x, p.y), V2(p.x + box, p.y + box), C(r, g, b, 0.14), 12)
            dl:AddRect(V2(p.x, p.y), V2(p.x + box, p.y + box), C(r, g, b, 0.5), 12, 0, 1.2)
            icons.draw(dl, iconForItem(item.name), p.x + box / 2 - 16, p.y + box / 2 - 16, 32,
                C(r, g, b, 1), C(0.07, 0.08, 0.11, 1))
            dl:AddText(V2(p.x + box + 12, p.y + 10), C(0.97, 0.95, 0.99, 1), fitText(item.name, avail - box - 12))
            dl:AddText(V2(p.x + box + 12, p.y + 32), C(0.64, 0.62, 0.74, 1),
                string.format("Slot %d  ·  x%d", item.slot, item.quantity))

            if item.source ~= "td" then
                if amount[0] < 1 then amount[0] = 1 end
                if amount[0] > item.quantity then amount[0] = item.quantity end
                imgui.TextColored(GRAY, "JUMLAH")
                if styledButton("-##amt_dec", 30, 28, "glass") then amount[0] = math.max(1, amount[0] - 1) end
                imgui.SameLine(0, 6)
                imgui.SetNextItemWidth(64)
                imgui.InputInt("##inventory_amount", amount, 0, 0)
                imgui.SameLine(0, 6)
                if styledButton("+##amt_inc", 30, 28, "glass") then amount[0] = math.min(item.quantity, amount[0] + 1) end
                imgui.SameLine(0, 6)
                if styledButton("MAX##amt_max", -1, 28, "glass") then amount[0] = item.quantity end
                if amount[0] < 1 then amount[0] = 1 end
                if amount[0] > item.quantity then amount[0] = item.quantity end
            else
                imgui.TextColored(GRAY, "Aksi diteruskan ke textdraw server.")
            end
        end

        imgui.Spacing()
        if compact then
            drawActionRow(avail)
            return
        end

        imgui.Separator()
        imgui.Spacing()
        imgui.TextColored(GRAY, "SEKITAR")
        imgui.Spacing()
        local gap = 6
        local gsz = math.floor((avail - (cols - 1) * gap) / cols)
        local availY = imgui.GetContentRegionAvail().y
        local rows = math.min(4, math.floor((availY + gap) / (gsz + gap)))
        if rows > 0 then
            local gp = imgui.GetCursorScreenPos()
            for rr = 0, rows - 1 do
                for cc = 0, cols - 1 do
                    local sx, sy = gp.x + cc * (gsz + gap), gp.y + rr * (gsz + gap)
                    dl:AddRectFilled(V2(sx, sy), V2(sx + gsz, sy + gsz), C(1, 1, 1, 0.03), 7)
                    dl:AddRect(V2(sx, sy), V2(sx + gsz, sy + gsz), C(1, 1, 1, 0.06), 7, 0, 1)
                end
            end
            imgui.Dummy(V2(avail, rows * (gsz + gap) - gap))
        end
    end

    ------------------------------------------------------------------ frame
    imgui.OnFrame(
        function() return open and isSampAvailable() and isPlayerUiReady() end,
        function()
            imguiStack = {}
            local ok, err = xpcall(function()
            if tdActive and tdTriggerGone and os.clock() - tdTriggerGone > 0.4 then
                deactivateTextdraw()
                if not open then return end
            end
            if source == "td" and dirty and os.clock() - lastRebuild > 0.1 then
                rebuildFromTextdraws()
            end

            local ds = imgui.GetIO().DisplaySize
            local W, H = ds.x, ds.y
            animNow = ease((os.clock() - openedAt) / 0.22)
            local compact = W < 900
            local gap = 6
            local pad = compact and 12 or 14

            local cols, slotW, panelH, invW, sideW, invX, sideX, actX, actW, y0
            if compact then
                local m = 10
                cols = 4
                panelH = math.floor(H - m * 2)
                invW = math.floor(W * 0.56)
                slotW = math.max(36, math.floor((invW - pad * 2 - 8 - (cols - 1) * gap) / cols))
                invX, y0 = m, m + (1 - animNow) * 24
                sideX = invX + invW + m
                sideW = W - sideX - m
            else
                cols = 5
                panelH = math.floor(math.min(H - 60, 660))
                slotW = math.floor(math.min(84, math.max(48,
                    (W * 0.30 - pad * 2 - 8 - (cols - 1) * gap) / cols)))
                invW = cols * slotW + (cols - 1) * gap + 8 + pad * 2
                sideW, actW = invW, 62
                local totalW = invW + 22 + actW + 22 + sideW
                invX = math.floor((W - totalW) / 2)
                actX = invX + invW + 22
                sideX = actX + actW + 22
                y0 = math.floor((H - panelH) / 2) + (1 - animNow) * 24
            end

            imgui.SetNextWindowSize(ds, imgui.Cond.Always)
            imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(0.01, animNow))
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
            imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
            beginTracked("Begin", "##PBRP_lua_inventory", nil, flags)
            imgui.PopStyleVar(4)

            local dl = imgui.GetWindowDrawList()

            -- latar gelap + glow ungu di bawah (mirip gambar referensi)
            dl:AddRectFilled(V2(0, 0), V2(W, H), C(0.02, 0.015, 0.05, 0.60))
            dl:AddRectFilledMultiColor(V2(0, H * 0.45), V2(W, H),
                C(0, 0, 0, 0), C(0, 0, 0, 0), C(0.35, 0.20, 0.80, 0.22), C(0.35, 0.20, 0.80, 0.22))

            drawInventoryPanel(dl, invX, y0, invW, panelH, cols, slotW, pad, gap)

            if not compact then
                drawActionColumn(actX, y0, actW, panelH)
            end

            panelBg(dl, sideX, y0, sideW, panelH)
            imgui.SetCursorPos(V2(sideX + pad, y0 + 12))
            imgui.PushStyleColor(imgui.Col.ChildBg, V4(0, 0, 0, 0))
            imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
            beginTracked("BeginChild", "##inventory_side", V2(sideW - pad * 2, panelH - 24), false, 0)
            imgui.PopStyleVar(1)
            drawSide(compact, cols)
            endTracked("BeginChild", "EndChild")
            imgui.PopStyleColor(1)

            -- notifikasi singkat
            if os.clock() < noticeUntil then
                local ts = imgui.CalcTextSize(noticeText)
                local nx, ny = (W - ts.x) / 2, H - 70
                dl:AddRectFilled(V2(nx - 16, ny - 8), V2(nx + ts.x + 16, ny + ts.y + 8), C(0.04, 0.03, 0.08, 0.92), 12)
                dl:AddRect(V2(nx - 16, ny - 8), V2(nx + ts.x + 16, ny + ts.y + 8), ACC(0.8), 12, 0, 1)
                dl:AddText(V2(nx, ny), C(0.97, 0.95, 0.99, 1), noticeText)
            end

            endTracked("Begin", "End")

            uiSounds.playClickIfHovered(imgui)
            end, debug.traceback)
            if not ok then
                unwindImguiStack()
                open = false
                selectedSlot = nil
                giveMode = false
                local message = "[PBRP/PKU UI][inventory] " .. tostring(err)
                print(message)
                say("UI inventory mengalami error dan ditutup. Detail tercatat di moonloader.log.")
            end
        end
    )

    ------------------------------------------------------------------ hook & command
    if CFG.autoHook then
        local ok, sampev = pcall(require, "samp.events")
        if ok and type(sampev) == "table" then
            local function chain(name, fn)
                local prev = sampev[name]
                sampev[name] = function(...)
                    if fn(...) == false then return false end
                    if prev then return prev(...) end
                end
            end
            chain("onShowTextDraw", onShowTextDraw)
            chain("onTextDrawSetString", onTextDrawSetString)
            chain("onTextDrawHide", onTextDrawHide)
        end
    end

    if lua_thread and lua_thread.create then
        pcall(lua_thread.create, function()
            while not isSampAvailable() do wait(100) end
            sampRegisterChatCommand("invtd", dumpTextdraws)
            sampRegisterChatCommand("invdemo", loadDemo)
        end)
    end

    return {
        config = CFG,
        open = show,
        openForPlayer = openForPlayer,
        close = close,
        demo = loadDemo,
        dump = dumpTextdraws,
        isOpen = function() return open end,
        ownsTextdraw = function(id) return tdActive and tdSession[id] == true end,
        onServerMessage = onServerMessage,
        -- panggil manual dari script utama kalau CFG.autoHook = false
        onShowTextDraw = onShowTextDraw,
        onTextDrawSetString = onTextDrawSetString,
        onTextDrawHide = onTextDrawHide,
    }
end