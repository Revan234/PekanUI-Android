-- speedometer.lua
-- Speedometer ala FiveM (aksen ungu): busur gradasi ungu -> pink -> merah, tick & angka,
-- angka digital besar, nama kendaraan, status mesin, kondisi, dan top speed per kendaraan.
-- Posisi: kanan bawah. Signature sama seperti sebelumnya (dipanggil dari uiPBRP.lua).

local CFG = {
    maxSpeed    = 280,   -- km/h di ujung busur
    speedFactor = 3.6,   -- getCarSpeed() = m/s -> km/h. Isi 1.0 untuk nilai mentah seperti versi lama.
    tickStep    = 20,    -- jarak tick kecil
    labelStep   = 40,    -- jarak tick besar + angka
    redline     = 0.86,  -- fraksi busur tempat zona merah dimulai
}

return function(imgui, V2, approach, isPlayerUiReady)
    local speedDisplay, anim, topSpeed = 0, 0, 0
    local lastVehicle = nil
    local cache = { name = "KENDARAAN", model = nil, engine = nil, health = 100, at = -10 }

    local A0 = math.pi * 0.75
    local SWEEP = math.pi * 1.5

    local function U(r, g, b, a) return imgui.GetColorU32Vec4(imgui.ImVec4(r, g, b, a or 1)) end
    local function lerp(a, b, t) return a + (b - a) * t end

    local function gradient(f)
        if f < 0.7 then
            local t = f / 0.7
            return lerp(0.62, 0.98, t), lerp(0.42, 0.38, t), lerp(1.00, 0.70, t)
        end
        local t = (f - 0.7) / 0.3
        return lerp(0.98, 1.00, t), lerp(0.38, 0.30, t), lerp(0.70, 0.35, t)
    end

    local function strokeArc(dl, cx, cy, r, a0, a1, color, thickness)
        dl:PathClear()
        dl:PathArcTo(V2(cx, cy), r, a0, a1, math.max(2, math.ceil((a1 - a0) / 0.07)))
        local ok = pcall(function() dl:PathStroke(color, 0, thickness) end)
        if not ok then dl:PathStroke(color, false, thickness) end
    end

    local function textSized(dl, x, y, text, color, size)
        local ok = pcall(function() dl:AddText(imgui.GetFont(), size, V2(x, y), color, text) end)
        if not ok then dl:AddText(V2(x, y), color, text) end
    end

    local function sizedWidth(text, size)
        return imgui.CalcTextSize(text).x * size / imgui.GetFontSize()
    end

    local function fitText(text, maxW)
        if imgui.CalcTextSize(text).x <= maxW then return text end
        while #text > 1 and imgui.CalcTextSize(text .. "..").x > maxW do
            text = text:sub(1, -2)
        end
        return text .. ".."
    end

    local function refreshVehicle(vehicle)
        local now = os.clock()
        if vehicle ~= lastVehicle then
            lastVehicle = vehicle
            topSpeed = 0
            cache.at = -10
        end
        if now - cache.at < 0.25 then return end
        cache.at = now
        pcall(function()
            local model = getCarModel(vehicle)
            if model ~= cache.model then
                cache.model = model
                local okName, name = pcall(function() return getGxtText(getNameOfVehicleModel(model)) end)
                cache.name = (okName and name and name ~= "") and name or "KENDARAAN"
            end
            cache.health = math.max(0, math.min(100, getCarHealth(vehicle) / 10))
        end)
        local okEngine, engine = pcall(isCarEngineOn, vehicle)
        cache.engine = okEngine and engine or nil
    end

    local frame
    frame = imgui.OnFrame(
        function()
            if not (isSampAvailable() and isPlayerUiReady()) then return false end
            local ok, inCar = pcall(isCharInAnyCar, PLAYER_PED)
            return (ok and inCar) or anim > 0.01
        end,
        function()
            local io = imgui.GetIO()
            local dt, ds = io.DeltaTime, io.DisplaySize

            local okCar, inCar = pcall(isCharInAnyCar, PLAYER_PED)
            inCar = okCar and inCar
            anim = approach(anim, inCar and 1 or 0, 9, dt)

            local vehicle
            if inCar then
                local okVehicle, v = pcall(getCarCharIsUsing, PLAYER_PED)
                if okVehicle then vehicle = v end
            end
            if vehicle then
                local okSpeed, raw = pcall(getCarSpeed, vehicle)
                local speed = math.max(0, math.min(CFG.maxSpeed, (okSpeed and raw or 0) * CFG.speedFactor))
                speedDisplay = approach(speedDisplay, speed, 12, dt)
                if speed > topSpeed then topSpeed = speed end
                refreshVehicle(vehicle)
            else
                speedDisplay = approach(speedDisplay, 0, 12, dt)
            end
            if anim <= 0.01 then return end

            local ease = anim * anim * (3 - 2 * anim)
            local S = math.max(0.8, math.min(1.3, ds.y / 900))
            local W, H = 312 * S, 176 * S
            local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoScrollbar + imgui.WindowFlags.NoInputs
                + imgui.WindowFlags.NoBackground
            imgui.SetNextWindowPos(V2(ds.x - W - 24, ds.y - H - 28 + (1 - ease) * 18), imgui.Cond.Always)
            imgui.SetNextWindowSize(V2(W, H), imgui.Cond.Always)
            imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, math.max(0.01, ease))
            imgui.Begin("##PBRP_speedometer", nil, flags)

            local dl = imgui.GetWindowDrawList()
            local pos = imgui.GetWindowPos()
            local function P(x, y) return V2(pos.x + x * S, pos.y + y * S) end

            local progress = math.min(1, speedDisplay / CFG.maxSpeed)
            local pr, pg, pb = gradient(progress)

            -- panel
            dl:AddRectFilled(P(0, 0), P(312, 176), U(0.040, 0.036, 0.070, 0.88), 16 * S)
            dl:AddRectFilledMultiColor(P(8, 1), P(304, 40),
                U(0.60, 0.42, 1, 0.14), U(0.60, 0.42, 1, 0.14), U(0.60, 0.42, 1, 0), U(0.60, 0.42, 1, 0))
            dl:AddRect(P(0, 0), P(312, 176), U(0.62, 0.50, 1, 0.40), 16 * S, 0, 1.2)
            dl:AddRectFilled(P(16, 0), P(296, 2), U(0.62, 0.45, 1, 0.9), 1)

            -- busur
            local cx, cy, r = 96, 98, 70
            local px, py = pos.x + cx * S, pos.y + cy * S
            strokeArc(dl, px, py, r * S, A0, A0 + SWEEP, U(1, 1, 1, 0.09), 8 * S)
            strokeArc(dl, px, py, r * S, A0 + SWEEP * CFG.redline, A0 + SWEEP, U(1, 0.30, 0.35, 0.22), 8 * S)

            local N = 48
            for i = 0, N - 1 do
                local f0, f1 = i / N, (i + 1) / N
                if f0 < progress then
                    local sr, sg, sb = gradient((f0 + f1) / 2)
                    local end1 = math.min(f1, progress)
                    strokeArc(dl, px, py, r * S, A0 + SWEEP * f0, A0 + SWEEP * end1 + 0.006,
                        U(sr, sg, sb, 1), 8 * S)
                end
            end

            -- tick & angka
            local muted = U(0.62, 0.60, 0.76, 1)
            for v = 0, CFG.maxSpeed, CFG.tickStep do
                local f = v / CFG.maxSpeed
                local ang = A0 + SWEEP * f
                local major = (v % CFG.labelStep == 0)
                local r1 = (r - (major and 17 or 13)) * S
                local r2 = (r - 8) * S
                local lit = f <= progress
                local c = math.cos(ang)
                local s2 = math.sin(ang)
                local tr, tg, tb = gradient(f)
                dl:AddLine(V2(px + c * r1, py + s2 * r1), V2(px + c * r2, py + s2 * r2),
                    lit and U(tr, tg, tb, 0.95) or U(1, 1, 1, major and 0.28 or 0.14), major and 1.6 or 1.0)
                if major then
                    local label = tostring(v)
                    local ts = imgui.CalcTextSize(label)
                    local lr = (r - 29) * S
                    dl:AddText(V2(px + c * lr - ts.x / 2, py + s2 * lr - ts.y / 2),
                        lit and U(0.92, 0.90, 1, 0.95) or muted, label)
                end
            end

            -- ujung busur bercahaya
            if progress > 0.01 then
                local ang = A0 + SWEEP * progress
                local tx, ty = px + math.cos(ang) * r * S, py + math.sin(ang) * r * S
                dl:AddCircleFilled(V2(tx, ty), 10 * S, U(pr, pg, pb, 0.14), 24)
                dl:AddCircleFilled(V2(tx, ty), 6 * S, U(pr, pg, pb, 0.40), 20)
                dl:AddCircleFilled(V2(tx, ty), 3.4 * S, U(1, 1, 1, 0.95), 16)
            end

            -- angka digital di tengah
            local speedText = tostring(math.floor(speedDisplay + 0.5))
            local size = 40 * S
            local sw = sizedWidth(speedText, size)
            textSized(dl, px - sw / 2, py - 30 * S, speedText, U(0.98, 0.97, 1, 1), size)
            local unit = "KM/H"
            local us = imgui.CalcTextSize(unit)
            dl:AddText(V2(px - us.x / 2, py + 16 * S), U(pr, pg, pb, 1), unit)
            local top = "TOP " .. math.floor(topSpeed + 0.5)
            local tsz = imgui.CalcTextSize(top)
            dl:AddText(V2(px - tsz.x / 2, py + 40 * S), muted, top)

            -- kolom informasi kanan
            local ix = 192
            local iw = 104
            dl:AddText(P(ix, 20), muted, "KENDARAAN")
            dl:AddText(P(ix, 37), U(0.96, 0.96, 1, 1), fitText(tostring(cache.name):upper(), iw * S))

            local engineText, er, eg, eb = "MESIN -", 0.62, 0.60, 0.76
            if cache.engine == true then
                engineText, er, eg, eb = "MESIN ON", 0.40, 0.90, 0.62
            elseif cache.engine == false then
                engineText, er, eg, eb = "MESIN OFF", 1.00, 0.38, 0.42
            end
            local es = imgui.CalcTextSize(engineText)
            local pw, ph = es.x + 16, es.y + 6
            dl:AddRectFilled(P(ix, 66), V2(pos.x + ix * S + pw, pos.y + 66 * S + ph), U(er, eg, eb, 0.16), ph / 2)
            dl:AddRect(P(ix, 66), V2(pos.x + ix * S + pw, pos.y + 66 * S + ph), U(er, eg, eb, 0.55), ph / 2, 0, 1)
            dl:AddText(V2(pos.x + ix * S + 8, pos.y + 66 * S + 3), U(er, eg, eb, 1), engineText)

            -- kondisi kendaraan
            local hp = cache.health
            local hr, hg, hb = 0.40, 0.90, 0.62
            if hp < 35 then hr, hg, hb = 1.00, 0.38, 0.42 elseif hp < 65 then hr, hg, hb = 1.00, 0.78, 0.30 end
            dl:AddText(P(ix, 104), muted, "KONDISI")
            local hpText = string.format("%d%%", math.floor(hp + 0.5))
            local hs = imgui.CalcTextSize(hpText)
            dl:AddText(V2(pos.x + (ix + iw) * S - hs.x, pos.y + 104 * S), U(1, 1, 1, 1), hpText)
            dl:AddRectFilled(P(ix, 124), P(ix + iw, 130), U(1, 1, 1, 0.09), 3 * S)
            if hp > 1 then
                dl:AddRectFilled(P(ix, 124), P(ix + iw * hp / 100, 130), U(hr, hg, hb, 1), 3 * S)
            end

            dl:AddText(P(ix, 146), U(0.94, 0.70, 0.25, 1), "PB  ·  SPEED")

            imgui.End()
            imgui.PopStyleVar(1)
        end
    )
    frame.HideCursor = true
    frame.LockPlayer = false
end
