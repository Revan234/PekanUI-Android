-- vehicles_ui.lua
-- UI kendaraan & garasi ala FiveM (mimgui, aksen ungu), tanpa preview gambar kendaraan.
--
-- Protokol server (@PBRPUI:VEHICLES:*, @PBRPUI:GARAGE:*) dan perintah chat sama seperti versi sebelumnya.

local CFG = {
    previewTdId = 2040,          -- ID preview lama, dihapus untuk membersihkan sisa dari versi sebelumnya
    maxFuel     = 100,           -- untuk bar bahan bakar
    maxHealth   = 1000,          -- untuk bar kesehatan
}

-- nama kendaraan SA-MP, index mulai dari model 400
local NAMES_RAW = "Landstalker|Bravura|Buffalo|Linerunner|Perennial|Sentinel|Dumper|Firetruck|Trashmaster|Stretch|"
    .. "Manana|Infernus|Voodoo|Pony|Mule|Cheetah|Ambulance|Leviathan|Moonbeam|Esperanto|"
    .. "Taxi|Washington|Bobcat|Mr. Whoopee|BF Injection|Hunter|Premier|Enforcer|Securicar|Banshee|"
    .. "Predator|Bus|Rhino|Barracks|Hotknife|Trailer|Previon|Coach|Cabbie|Stallion|"
    .. "Rumpo|RC Bandit|Romero|Packer|Monster|Admiral|Squalo|Seasparrow|Pizzaboy|Tram|"
    .. "Trailer|Turismo|Speeder|Reefer|Tropic|Flatbed|Yankee|Caddy|Solair|RC Van|"
    .. "Skimmer|PCJ-600|Faggio|Freeway|RC Baron|RC Raider|Glendale|Oceanic|Sanchez|Sparrow|"
    .. "Patriot|Quad|Coastguard|Dinghy|Hermes|Sabre|Rustler|ZR-350|Walton|Regina|"
    .. "Comet|BMX|Burrito|Camper|Marquis|Baggage|Dozer|Maverick|News Chopper|Rancher|"
    .. "FBI Rancher|Virgo|Greenwood|Jetmax|Hotring Racer|Sandking|Blista Compact|Police Maverick|Boxville|Benson|"
    .. "Mesa|RC Goblin|Hotring Racer|Hotring Racer|Bloodring Banger|Rancher|Super GT|Elegant|Journey|Bike|"
    .. "Mountain Bike|Beagle|Cropduster|Stuntplane|Tanker|Roadtrain|Nebula|Majestic|Buccaneer|Shamal|"
    .. "Hydra|FCR-900|NRG-500|HPV1000|Cement Truck|Tow Truck|Fortune|Cadrona|FBI Truck|Willard|"
    .. "Forklift|Tractor|Combine Harvester|Feltzer|Remington|Slamvan|Blade|Freight|Brownstreak|Vortex|"
    .. "Vincent|Bullet|Clover|Sadler|Firetruck LA|Hustler|Intruder|Primo|Cargobob|Tampa|"
    .. "Sunrise|Merit|Utility Van|Nevada|Yosemite|Windsor|Monster|Monster|Uranus|Jester|"
    .. "Sultan|Stratum|Elegy|Raindance|RC Tiger|Flash|Tahoma|Savanna|Bandito|Freight Flat|"
    .. "Streak Carriage|Kart|Mower|Dune|Sweeper|Broadway|Tornado|AT-400|DFT-30|Huntley|"
    .. "Stafford|BF-400|Newsvan|Tug|Petrol Trailer|Emperor|Wayfarer|Euros|Hotdog|Club|"
    .. "Freight Box|Article Trailer|Andromada|Dodo|RC Cam|Launch|Police LS|Police SF|Police LV|Police Ranger|"
    .. "Picador|S.W.A.T.|Alpha|Phoenix|Glendale|Sadler|Baggage Trailer|Baggage Trailer|Tug Stairs|Boxville|"
    .. "Farm Trailer|Utility Trailer"

local VEHICLE_NAMES = {}
do
    local i = 399
    for n in NAMES_RAW:gmatch("[^|]+") do
        i = i + 1
        VEHICLE_NAMES[i] = n
    end
end

return function(imgui, V2, sendChat, uiSounds, isPlayerUiReady, getAccent)
    local open = false
    local actionsOpen = false
    local garageMode = false
    local garageName = "GARASI"
    local vehicles = {}
    local selectedId = nil
    local status = ""
    local lastDrawError = nil
    local garageTextdraws = {}
    local garageTextdrawVisible = false

    local openedAt, actionsOpenedAt = 0, 0
    local lastDt = 0.016
    local hoverAnim, barAnim = {}, {}

    ------------------------------------------------------------------ util
    local function U(r, g, b, a) return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, a or 1)) end
    local function PUR(a)
        local r, g, b = getAccent()
        return U(r, g, b, a)
    end
    local function V4(r, g, b, a) return imgui.ImVec4(r, g, b, a or 1) end

    local colors = {
        text = V4(0.94, 0.95, 1.0, 1),
        muted = V4(0.62, 0.60, 0.74, 1),
        orange = V4(1.0, 0.55, 0.30, 1),
    }
    local BTN = {
        glass  = { V4(1, 1, 1, 0.09), V4(1, 1, 1, 0.17) },
    }

    local function ease(t)
        t = math.min(1, math.max(0, t))
        return 1 - (1 - t) ^ 3
    end

    local function hv(key, target)
        local v = hoverAnim[key] or 0
        v = v + (target - v) * math.min(1, lastDt * 12)
        hoverAnim[key] = v
        return v
    end

    local function pushId(id)
        if type(id) == "number" then
            imgui.PushIDInt(id)
            return
        end

        if type(id) == "string" then
            imgui.PushIDStr(id)
            return
        end

        error("ID menu kendaraan harus berupa string atau angka")
    end

    local function fitText(text, maxW)
        if maxW <= 10 then return "" end
        if imgui.CalcTextSize(text).x <= maxW then return text end
        while #text > 1 and imgui.CalcTextSize(text .. "..").x > maxW do
            text = text:sub(1, -2)
        end
        return text .. ".."
    end

    local function modelName(vehicle)
        if vehicle.name and vehicle.name ~= "" then return vehicle.name end
        if vehicle.model and VEHICLE_NAMES[vehicle.model] then return VEHICLE_NAMES[vehicle.model] end
        return "Model " .. tostring(vehicle.model or "?")
    end

    local function selectedVehicle()
        for _, vehicle in ipairs(vehicles) do
            if vehicle.id == selectedId then return vehicle end
        end
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
        imgui.PushStyleColor(imgui.Col.Text, colors.text)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 10)
        local clicked = imgui.Button(label, V2(w, h))
        imgui.PopStyleVar(1)
        imgui.PopStyleColor(4)
        if imgui.IsItemHovered() then uiSounds.hover(label) end
        return clicked
    end

    local function pill(dl, x, y, text, r, g, b, rightAlign)
        local ts = imgui.CalcTextSize(text)
        local w, h = ts.x + 16, ts.y + 6
        if rightAlign then x = x - w end
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), U(r, g, b, 0.16), h / 2)
        dl:AddRect(V2(x, y), V2(x + w, y + h), U(r, g, b, 0.55), h / 2, 0, 1)
        dl:AddText(V2(x + 8, y + 3), U(r, g, b, 1), text)
        return w, h
    end

    local function plateChip(dl, x, y, text)
        local ts = imgui.CalcTextSize(text)
        local w, h = ts.x + 18, ts.y + 6
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), U(0.94, 0.93, 0.86, 1), 5)
        dl:AddRect(V2(x + 1, y + 1), V2(x + w - 1, y + h - 1), U(0.15, 0.15, 0.20, 0.6), 4, 0, 1)
        dl:AddText(V2(x + 9, y + 3), U(0.10, 0.10, 0.14, 1), text)
        return w, h
    end

    local function panelBg(dl, x, y, w, h)
        dl:AddRectFilled(V2(x, y), V2(x + w, y + h), U(0.045, 0.040, 0.075, 0.90), 14)
        dl:AddRect(V2(x, y), V2(x + w, y + h), U(0.62, 0.50, 1, 0.18), 14, 0, 1)
    end

    ------------------------------------------------------------------ bersihkan preview 3D dari versi sebelumnya
    local function hidePreview()
        if sampTextdrawDelete then
            local ok, err = pcall(sampTextdrawDelete, CFG.previewTdId)
            if not ok then
                local message = "[PBRP/PKU UI][kendaraan] gagal membersihkan preview lama: " .. tostring(err)
                if message ~= lastDrawError then
                    lastDrawError = message
                    print(message)
                end
            end
        end
    end

    ------------------------------------------------------------------ guard
    local function shutdown()
        open = false
        actionsOpen = false
        hidePreview()
    end

    local function guardDraw(name, callback)
        return function()
            local ok, err = pcall(callback)
            if ok then return end

            shutdown()
            if garageMode then sendChat("/rpui_garage_close") end
            garageMode = false
            local message = "[PBRP/PKU UI][kendaraan] " .. name .. ": " .. tostring(err)
            if message ~= lastDrawError then
                lastDrawError = message
                print(message)
            end
        end
    end

    ------------------------------------------------------------------ protokol server
    local function onServerMessage(text)
        if text == "@PBRPUI:VEHICLES:CLOSE" then
            shutdown()
            garageMode = false
            return true
        end

        if text == "@PBRPUI:VEHICLES:BEGIN" then
            vehicles = {}
            selectedId = nil
            status = ""
            return true
        end

        local vehicleId, model, plate, vehicleStatus =
            text:match("^@PBRPUI:VEHICLES:ITEM:(%d+):(%d+):([^:]+):(.+)$")
        if vehicleId then
            vehicles[#vehicles + 1] = {
                id = tonumber(vehicleId),
                model = tonumber(model),
                plate = plate,
                status = vehicleStatus
            }
            return true
        end

        if text == "@PBRPUI:VEHICLES:END" then
            if #vehicles > 0 and not selectedId then selectedId = vehicles[1].id end
            if #vehicles == 0 then status = "Belum ada kendaraan terdaftar." end
            return true
        end

        local garageType, garageId = text:match("^@PBRPUI:GARAGE:OPEN:(%d+):(%d+)$")
        if garageType then
            garageMode = true
            garageName = (garageType == "1" and "GARASI KOTA")
                or (garageType == "2" and "GARASI RUMAH")
                or "GARASI FAMILI"
            garageName = garageName .. "  /  #" .. garageId
            vehicles = {}
            selectedId = nil
            status = "Memuat kendaraan..."
            open = true
            actionsOpen = false
            openedAt = os.clock()
            uiSounds.play("open")
            return true
        end

        local id, modelId, fuel, health, plate, name =
            text:match("^@PBRPUI:GARAGE:ITEM:(%d+):(%d+):([%d%.%-]+):([%d%.%-]+):([^:]*):(.+)$")
        if id then
            vehicles[#vehicles + 1] = {
                id = tonumber(id),
                model = tonumber(modelId),
                fuel = tonumber(fuel),
                health = tonumber(health),
                plate = plate,
                name = name,
                status = "Disimpan"
            }
            return true
        end

        if text == "@PBRPUI:GARAGE:END" then
            if #vehicles > 0 then
                selectedId = vehicles[1].id
                status = ""
            else
                status = "Tidak ada kendaraan tersimpan di garasi ini."
            end
            return true
        end

        if text == "@PBRPUI:GARAGE:CLOSE" then
            shutdown()
            garageMode = false
            return true
        end

        if text:sub(1, 14) == "@PBRPUI:GARAGE" then return true end
    end

    local function close()
        local wasGarage = garageMode
        shutdown()
        garageMode = false
        if wasGarage then sendChat("/rpui_garage_close") end
    end

    ------------------------------------------------------------------ deteksi textdraw garasi (tetap)
    local function isGarageText(value)
        value = tostring(value or ""):gsub("{%x%x%x%x%x%x}", "")
        return value:match("^Garkot%s+%d+")
            or value:match("^House%s+%d+")
            or value:match("^Families%s+%d+")
            or value:match("^List Kendaraan Yang Ada")
            or value == "Take Out Vehicle"
            or value == "Informasi Kendaraan"
    end

    local function updateGarageTextdraw(id, text)
        if isGarageText(text) then
            garageTextdraws[id] = true
        else
            garageTextdraws[id] = nil
        end
        garageTextdrawVisible = next(garageTextdraws) ~= nil
    end

    local function onShowTextDraw(id, data)
        if type(data) == "table" then
            updateGarageTextdraw(id, data.text)
        end
    end

    local function onTextDrawSetString(id, text)
        if garageTextdraws[id] or isGarageText(text) then
            updateGarageTextdraw(id, text)
        end
    end

    local function onTextDrawHide(id)
        garageTextdraws[id] = nil
        garageTextdrawVisible = next(garageTextdraws) ~= nil
    end

    ------------------------------------------------------------------ komponen gambar
    local function closeButton(id, x, y, s)
        imgui.SetCursorPos(V2(x, y))
        pushId(id)
        local clicked = imgui.InvisibleButton("##x", V2(s, s))
        local hovered = imgui.IsItemHovered()
        local min = imgui.GetItemRectMin()
        local dl = imgui.GetWindowDrawList()
        local ha = hv(id, hovered and 1 or 0)
        dl:AddRectFilled(min, V2(min.x + s, min.y + s), U(0.95, 0.32, 0.30, 0.10 + 0.22 * ha), 10)
        dl:AddRect(min, V2(min.x + s, min.y + s), U(0.95, 0.32, 0.30, 0.35 + 0.55 * ha), 10, 0, 1.2)
        local cx, cy = min.x + s / 2, min.y + s / 2
        local col = U(1, 0.50, 0.47, 1)
        dl:AddLine(V2(cx - 7, cy - 7), V2(cx + 7, cy + 7), col, 2.2)
        dl:AddLine(V2(cx + 7, cy - 7), V2(cx - 7, cy + 7), col, 2.2)
        if hovered then uiSounds.hover(id) end
        imgui.PopID()
        return clicked
    end

    local function drawVehicleCard(vehicle, w)
        pushId(vehicle.id)
        local h = 66
        local clicked = imgui.InvisibleButton("##veh", V2(w, h))
        local hovered = imgui.IsItemHovered()
        local min = imgui.GetItemRectMin()
        local max = V2(min.x + w, min.y + h)
        local dl = imgui.GetWindowDrawList()
        local sel = vehicle.id == selectedId
        local ha = hv("card" .. vehicle.id, (hovered or sel) and 1 or 0)
        local active = vehicle.status == "Aktif"

        if hovered then uiSounds.hover("veh" .. vehicle.id) end

        dl:AddRectFilled(min, max, sel and PUR(0.16) or U(1, 1, 1, 0.04 + 0.04 * ha), 10)
        dl:AddRect(min, max, sel and PUR(0.95) or PUR(0.10 + 0.40 * ha), 10, 0, sel and 1.5 or 1)
        local barCol = active and U(0.26, 0.83, 0.59, 1) or PUR(sel and 1 or 0.45)
        dl:AddRectFilled(V2(min.x, min.y + 14), V2(min.x + 3, min.y + h - 14), barCol, 2)

        local bx, by = min.x + 14, min.y + 13
        dl:AddRectFilled(V2(bx, by), V2(bx + 40, by + 40), PUR(0.16), 9)
        local mid = tostring(vehicle.model or "?")
        local ms = imgui.CalcTextSize(mid)
        dl:AddText(V2(bx + (40 - ms.x) / 2, by + (40 - ms.y) / 2), PUR(1), mid)

        local nx = bx + 40 + 12
        local stText = vehicle.status or "Disimpan"
        local sr, sg, sb = 0.68, 0.52, 1.0
        if active then sr, sg, sb = 0.26, 0.83, 0.59 end
        local pw = pill(dl, max.x - 12, min.y + 10, stText, sr, sg, sb, true)
        dl:AddText(V2(nx, min.y + 12), U(0.95, 0.96, 1, 1),
            fitText(modelName(vehicle), (max.x - 12 - pw - 8) - nx))
        plateChip(dl, nx, min.y + 36, vehicle.plate or "Tanpa plat")

        if clicked then
            selectedId = vehicle.id
            status = ""
            uiSounds.play("click")
        end
        imgui.PopID()
    end

    local function drawBar(key, label, valueText, ratio, r, g, b, avail)
        local dl = imgui.GetWindowDrawList()
        local p = imgui.GetCursorScreenPos()
        imgui.Dummy(V2(avail, 36))
        ratio = math.min(1, math.max(0, ratio))
        local a = barAnim[key] or 0
        a = a + (ratio - a) * math.min(1, lastDt * 8)
        barAnim[key] = a
        dl:AddText(V2(p.x, p.y), U(0.62, 0.60, 0.74, 1), label)
        local ts = imgui.CalcTextSize(valueText)
        dl:AddText(V2(p.x + avail - ts.x, p.y), U(0.94, 0.95, 1, 1), valueText)
        local by = p.y + 20
        dl:AddRectFilled(V2(p.x, by), V2(p.x + avail, by + 8), U(1, 1, 1, 0.08), 4)
        if a > 0.002 then
            dl:AddRectFilled(V2(p.x, by), V2(p.x + avail * a, by + 8), U(r, g, b, 1), 4)
        end
    end

    local function drawDetails(vehicle)
        local dl = imgui.GetWindowDrawList()
        local avail = imgui.GetContentRegionAvail().x

        if not vehicle then
            imgui.TextColored(colors.muted, "INFORMASI KENDARAAN")
            imgui.Spacing()
            imgui.TextWrapped(status ~= "" and status or "Pilih kendaraan dari daftar untuk melihat detailnya.")
            return
        end

        imgui.SetWindowFontScale(1.25)
        imgui.TextColored(colors.text, modelName(vehicle))
        imgui.SetWindowFontScale(1)
        imgui.TextColored(colors.muted,
            string.format("Kendaraan pribadi  ·  #%d  ·  Model %s", vehicle.id, tostring(vehicle.model or "?")))
        imgui.Spacing()

        -- tile plat & status
        local p = imgui.GetCursorScreenPos()
        local tileH = 54
        local tileW = math.floor((avail - 10) / 2)
        imgui.Dummy(V2(avail, tileH))
        dl:AddRectFilled(V2(p.x, p.y), V2(p.x + tileW, p.y + tileH), U(1, 1, 1, 0.05), 10)
        dl:AddText(V2(p.x + 12, p.y + 7), U(0.62, 0.60, 0.74, 1), "NOMOR PLAT")
        plateChip(dl, p.x + 12, p.y + 26, vehicle.plate or "-")
        local x2 = p.x + tileW + 10
        dl:AddRectFilled(V2(x2, p.y), V2(x2 + tileW, p.y + tileH), U(1, 1, 1, 0.05), 10)
        dl:AddText(V2(x2 + 12, p.y + 7), U(0.62, 0.60, 0.74, 1), "STATUS")
        local active = vehicle.status == "Aktif"
        if active then
            pill(dl, x2 + 12, p.y + 26, vehicle.status or "Aktif", 0.26, 0.83, 0.59)
        else
            pill(dl, x2 + 12, p.y + 26, vehicle.status or "Tidak diketahui", 0.68, 0.52, 1.0)
        end
        imgui.Spacing()

        if garageMode then
            local fuel = vehicle.fuel or 0
            local fr = fuel / CFG.maxFuel
            local fcol = fr < 0.2 and { 1.0, 0.45, 0.30 } or { 0.60, 0.42, 1.0 }
            drawBar("fuel" .. vehicle.id, "BAHAN BAKAR", string.format("%.1f L", fuel), fr,
                fcol[1], fcol[2], fcol[3], avail)

            local hp = vehicle.health or 0
            local hr = hp / CFG.maxHealth
            local hcol = { 0.26, 0.83, 0.59 }
            if hr < 0.35 then hcol = { 1.0, 0.40, 0.35 } elseif hr < 0.65 then hcol = { 1.0, 0.70, 0.28 } end
            drawBar("hp" .. vehicle.id, "KESEHATAN", string.format("%.0f / %d", hp, CFG.maxHealth), hr,
                hcol[1], hcol[2], hcol[3], avail)
        end

        if garageMode then
            if styledButton("AMBIL KENDARAAN##garage_takeout", -1, 44, "accent") then
                sendChat("/rpui_garage_takeout " .. vehicle.id)
                status = "Memproses pengambilan kendaraan..."
                uiSounds.play("click")
            end
        elseif active then
            if styledButton("LACAK LOKASI##vehicle_track", -1, 44, "accent") then
                sendChat("/rpui_vehicle_track " .. vehicle.id)
                status = "Meminta lokasi kendaraan..."
                uiSounds.play("click")
            end
        else
            imgui.TextColored(colors.muted, "Kendaraan ini sedang disimpan.")
            if styledButton("AMBIL VIA VALET##vehicle_valet", -1, 44, "accent") then
                sendChat("/rpui_garage_takeout " .. vehicle.id)
                status = "Membuka pilihan valet..."
                uiSounds.play("click")
            end
        end

        if status ~= "" then
            imgui.Spacing()
            imgui.TextColored(colors.orange, status)
        end
    end

    ------------------------------------------------------------------ frame utama
    local ALWAYS_PAD = imgui.WindowFlags.AlwaysUseWindowPadding or 0

    local function beginFullscreen(id, anim, ds)
        imgui.SetNextWindowSize(ds, imgui.Cond.Always)
        imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
        imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(0.01, anim))
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowBorderSize, 0)
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 0)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoMove + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoBackground
        imgui.Begin(id, nil, flags)
        imgui.PopStyleVar(4)
    end

    local function rect(dl, x1, y1, x2, y2, col)
        if x2 > x1 and y2 > y1 then dl:AddRectFilled(V2(x1, y1), V2(x2, y2), col) end
    end

    local function drawMain()
        local io = imgui.GetIO()
        local ds = io.DisplaySize
        local W, H = ds.x, ds.y
        lastDt = math.min(0.05, io.DeltaTime)
        local anim = ease((os.clock() - openedAt) / 0.25)
        local compact = W < 900

        local m = compact and 10 or 30
        local pw = math.floor(math.min(1120, W - m * 2))
        local ph = math.floor(math.min(660, H - m * 2))
        local px, py = math.floor((W - pw) / 2), math.floor((H - ph) / 2)
        local pad, headH = 18, 62
        local cy = py + headH
        local ch = ph - headH - pad
        local listW = math.floor(pw * (compact and 0.42 or 0.34))
        local lx = px + pad
        local rx = lx + listW + 14
        local rw = px + pw - pad - rx
        local prevH = math.min(120, math.floor(ch * 0.25))
        local infoY = cy + prevH + 12
        local infoH = ch - prevH - 12

        local vehicle = selectedVehicle()

        beginFullscreen("##PBRP_vehicles_ui", anim, ds)
        local dl = imgui.GetWindowDrawList()

        -- latar gelap
        local dim = U(0.02, 0.015, 0.05, 0.68)
        rect(dl, 0, 0, W, H, dim)
        if not compact and H * 0.2 < cy then
            dl:AddRectFilledMultiColor(V2(0, 0), V2(W, H * 0.2),
                U(0.45, 0.25, 0.95, 0.16), U(0.45, 0.25, 0.95, 0.16), U(0, 0, 0, 0), U(0, 0, 0, 0))
        end

        -- header
        dl:AddRectFilled(V2(px + pad, py + 14), V2(px + pad + 4, py + 48), PUR(1), 2)
        imgui.SetCursorPos(V2(px + pad + 16, py + 12))
        imgui.SetWindowFontScale(1.3)
        imgui.TextColored(colors.text, garageMode and garageName or "KENDARAAN")
        imgui.SetWindowFontScale(1)
        imgui.SetCursorPos(V2(px + pad + 16, py + 38))
        imgui.TextColored(colors.muted, garageMode
            and "Pilih kendaraan untuk melihat detail dan mengambilnya."
            or "Kendaraan pribadi, status, dan lokasi aktif.")
        if closeButton("vehicles_close", px + pw - pad - 38, py + 12, 38) then close() end
        dl:AddLine(V2(px + pad, py + headH - 4), V2(px + pw - pad, py + headH - 4), U(1, 1, 1, 0.07), 1)

        -- kartu daftar kendaraan
        panelBg(dl, lx, cy, listW, ch)
        dl:AddText(V2(lx + 14, cy + 13), U(0.62, 0.60, 0.74, 1), "DAFTAR KENDARAAN")
        pill(dl, lx + listW - 14, cy + 10, tostring(#vehicles), 0.68, 0.52, 1.0, true)

        imgui.SetCursorPos(V2(lx + 10, cy + 42))
        imgui.PushStyleColor(imgui.Col.ChildBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrab, V4(1, 1, 1, 0.18))
        imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 6)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(0, 0))
        imgui.PushStyleVarVec2(imgui.StyleVar.ItemSpacing, V2(8, 8))
        imgui.BeginChild("##garage_vehicle_list", V2(listW - 20, ch - 52), false, 0)
        imgui.PopStyleVar(3)
        if #vehicles == 0 then
            imgui.Spacing()
            imgui.TextWrapped(status ~= "" and status or "Memuat daftar kendaraan...")
        end
        local cardW = listW - 20 - 10
        for _, v in ipairs(vehicles) do drawVehicleCard(v, cardW) end
        imgui.EndChild()
        imgui.PopStyleColor(3)

        -- panel ringkas untuk kendaraan terpilih, tanpa gambar/model 3D
        local summaryW = math.min(rw, 420)
        local bx1, by1, bx2, by2 = rx + (rw - summaryW) / 2, cy, rx + (rw + summaryW) / 2, cy + prevH
        panelBg(dl, bx1, by1, summaryW, prevH)
        if vehicle then
            dl:AddText(V2(bx1 + 16, by1 + 18), U(0.96, 0.96, 1, 1), fitText(modelName(vehicle), summaryW - 32))
            dl:AddText(V2(bx1 + 16, by1 + 48), U(0.62, 0.60, 0.74, 1),
                "Model " .. tostring(vehicle.model or "?") .. "  ·  ID " .. tostring(vehicle.id))
        else
            local msg = "PILIH KENDARAAN"
            local ts = imgui.CalcTextSize(msg)
            dl:AddText(V2((bx1 + bx2) / 2 - ts.x / 2, (by1 + by2) / 2 - ts.y / 2), PUR(0.8), msg)
        end

        -- kartu informasi
        panelBg(dl, rx, infoY, rw, infoH)
        imgui.SetCursorPos(V2(rx, infoY))
        imgui.PushStyleColor(imgui.Col.ChildBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarBg, V4(0, 0, 0, 0))
        imgui.PushStyleColor(imgui.Col.ScrollbarGrab, V4(1, 1, 1, 0.18))
        imgui.PushStyleVarFloat(imgui.StyleVar.ScrollbarSize, 6)
        imgui.PushStyleVarVec2(imgui.StyleVar.WindowPadding, V2(16, 14))
        imgui.BeginChild("##garage_vehicle_details", V2(rw, infoH), false, ALWAYS_PAD)
        imgui.PopStyleVar(2)
        drawDetails(vehicle)
        imgui.EndChild()
        imgui.PopStyleColor(3)

        imgui.End()
        uiSounds.playClickIfHovered(imgui)
    end

    imgui.OnFrame(
        function() return open and isSampAvailable() and isPlayerUiReady() end,
        guardDraw("garasi", drawMain)
    )

    ------------------------------------------------------------------ menu aksi kendaraan
    local ACTIONS = {
        { label = "INFO KENDARAAN", command = "/myv",    glyph = "i" },
        { label = "KAP MESIN",      command = "/hood",   glyph = "H" },
        { label = "BAGASI",         command = "/trunk",  glyph = "B" },
        { label = "LAMPU",          command = "/lights", glyph = "L" },
        { label = "HAZARD",         command = "/toghazard", glyph = "!" },
        { label = "MESIN",          command = "/en",     glyph = "E" },
    }

    local function drawActions()
        local io = imgui.GetIO()
        local ds = io.DisplaySize
        local W, H = ds.x, ds.y
        lastDt = math.min(0.05, io.DeltaTime)
        local anim = ease((os.clock() - actionsOpenedAt) / 0.2)

        local w = math.floor(math.min(460, W - 32))
        local h = math.floor(math.min(500, H - 32))
        local x = math.floor((W - w) / 2)
        local y = math.floor((H - h) / 2 + (1 - anim) * 18)

        beginFullscreen("##PBRP_vehicle_actions", anim, ds)
        local dl = imgui.GetWindowDrawList()
        dl:AddRectFilled(V2(0, 0), V2(W, H), U(0.02, 0.015, 0.05, 0.62))
        panelBg(dl, x, y, w, h)
        dl:AddRectFilled(V2(x + 16, y), V2(x + w - 16, y + 2), PUR(0.9), 1)

        dl:AddRectFilled(V2(x + 18, y + 18), V2(x + 22, y + 52), PUR(1), 2)
        imgui.SetCursorPos(V2(x + 34, y + 16))
        imgui.SetWindowFontScale(1.25)
        imgui.TextColored(colors.text, "MENU KENDARAAN")
        imgui.SetWindowFontScale(1)
        imgui.SetCursorPos(V2(x + 34, y + 42))
        imgui.TextColored(colors.muted, "Kontrol cepat kendaraanmu")
        if closeButton("actions_close", x + w - 18 - 36, y + 16, 36) then
            actionsOpen = false
            uiSounds.play("close")
        end

        local top = y + 74
        local gap = 10
        local th = math.max(44, math.min(64, math.floor((h - 74 - 18 - gap * (#ACTIONS - 1)) / #ACTIONS)))
        for i, a in ipairs(ACTIONS) do
            local ty = top + (i - 1) * (th + gap)
            imgui.SetCursorPos(V2(x + 18, ty))
            pushId("act" .. i)
            local clicked = imgui.InvisibleButton("##tile", V2(w - 36, th))
            local hovered = imgui.IsItemHovered()
            local ha = hv("act" .. i, hovered and 1 or 0)
            local min = imgui.GetItemRectMin()
            local max = V2(min.x + w - 36, min.y + th)
            if hovered then uiSounds.hover("act" .. i) end

            dl:AddRectFilled(min, max, U(0.62, 0.50, 1, 0.05 + 0.12 * ha), 12)
            dl:AddRect(min, max, PUR(0.12 + 0.75 * ha), 12, 0, 1.2)
            local r = th * 0.5 - 8
            local cx, cy = min.x + 14 + r, min.y + th / 2
            dl:AddCircleFilled(V2(cx, cy), r, PUR(0.14 + 0.20 * ha), 24)
            local gs = imgui.CalcTextSize(a.glyph)
            dl:AddText(V2(cx - gs.x / 2, cy - gs.y / 2), PUR(1), a.glyph)
            local lbl = imgui.CalcTextSize(a.label)
            dl:AddText(V2(cx + r + 14 + 4 * ha, cy - lbl.y / 2), U(0.95, 0.96, 1, 1), a.label)
            pill(dl, max.x - 14, cy - (imgui.CalcTextSize(a.command).y + 6) / 2, a.command, 0.68, 0.52, 1.0, true)

            if clicked then
                actionsOpen = false
                sendChat(a.command)
                uiSounds.play("click")
            end
            imgui.PopID()
        end

        imgui.End()
        uiSounds.playClickIfHovered(imgui)
    end

    imgui.OnFrame(
        function() return actionsOpen and isSampAvailable() and isPlayerUiReady() end,
        guardDraw("aksi", drawActions)
    )

    ------------------------------------------------------------------ API modul
    return {
        open = function()
            garageMode = false
            hidePreview()
            open = true
            actionsOpen = false
            openedAt = os.clock()
            vehicles = {}
            selectedId = nil
            status = "Memuat kendaraan..."
            uiSounds.play("open")
            sendChat("/rpui_vehicles")
        end,
        openActions = function()
            uiSounds.play("open")
            open = false
            hidePreview()
            actionsOpen = true
            actionsOpenedAt = os.clock()
        end,
        close = close,
        isOpen = function() return open or actionsOpen end,
        onServerMessage = onServerMessage,
        onShowTextDraw = onShowTextDraw,
        onTextDrawSetString = onTextDrawSetString,
        onTextDrawHide = onTextDrawHide,
        isGarageTextdrawVisible = function() return garageTextdrawVisible end
    }
end
