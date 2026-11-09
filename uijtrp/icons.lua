return function(imgui)
    local V2 = imgui.ImVec2

    local function strokePath(dl, color, thickness)
        local ok = pcall(function() dl:PathStroke(color, 0, thickness) end)
        if not ok then dl:PathStroke(color, false, thickness) end
    end

    local function draw(dl, name, x, y, size, color, darkColor)
        local cx, cy = x + size / 2, y + size / 2
        local pad = size * 0.2
        local left, right = x + pad, x + size - pad
        local top, bottom = y + pad, y + size - pad
        local function line(x1, y1, x2, y2, thick)
            dl:AddLine(V2(x1, y1), V2(x2, y2), color, thick or 1.8)
        end

        if name == "health" then
            dl:AddRectFilled(V2(left, top), V2(right, bottom), color, 3)
            dl:AddRectFilled(V2(cx - 2, top + 3), V2(cx + 2, bottom - 3), darkColor, 1)
            dl:AddRectFilled(V2(left + 3, cy - 2), V2(right - 3, cy + 2), darkColor, 1)
        elseif name == "armor" then
            dl:PathClear()
            dl:PathLineTo(V2(cx, top))
            dl:PathLineTo(V2(right, top + 4))
            dl:PathLineTo(V2(right - 2, cy + 3))
            dl:PathLineTo(V2(cx, bottom))
            dl:PathLineTo(V2(left + 2, cy + 3))
            dl:PathLineTo(V2(left, top + 4))
            dl:PathLineTo(V2(cx, top))
            strokePath(dl, color, 2)
        elseif name == "inventory" then
            dl:AddRect(V2(left, top + 4), V2(right, bottom), color, 3, 0, 1.8)
            dl:PathClear()
            dl:PathArcTo(V2(cx, top + 5), size * 0.18, math.pi, math.pi * 2, 12)
            strokePath(dl, color, 1.8)
            line(cx, cy, cx, cy + size * 0.14, 1.6)
        elseif name == "phone" then
            dl:AddRect(V2(left + 2, top), V2(right - 2, bottom), color, 3, 0, 1.8)
            line(cx - size * 0.09, top + 3, cx + size * 0.09, top + 3, 1.3)
            dl:AddCircleFilled(V2(cx, bottom - 3), size * 0.035, color, 8)
        elseif name == "vehicle" then
            dl:AddRect(V2(left, cy - 2), V2(right, cy + size * 0.17), color, 3, 0, 1.8)
            line(left + 3, cy - 2, left + size * 0.23, top + 2)
            line(left + size * 0.23, top + 2, right - size * 0.23, top + 2)
            line(right - size * 0.23, top + 2, right - 3, cy - 2)
            dl:AddCircleFilled(V2(left + size * 0.2, bottom - 1), size * 0.07, color, 12)
            dl:AddCircleFilled(V2(right - size * 0.2, bottom - 1), size * 0.07, color, 12)
        elseif name == "chat" then
            dl:AddRect(V2(left, top), V2(right, bottom - 3), color, 3, 0, 1.8)
            line(left + 4, bottom - 3, left + 2, bottom)
            line(left + 2, bottom, left + size * 0.38, bottom - 3)
            line(left + 4, cy - 2, right - 4, cy - 2, 1.4)
            line(left + 4, cy + 3, right - 4, cy + 3, 1.4)
        elseif name == "user" then
            dl:AddCircle(V2(cx, top + size * 0.16), size * 0.13, color, 16, 1.8)
            dl:PathClear()
            dl:PathArcTo(V2(cx, bottom - 1), size * 0.26, math.pi, math.pi * 2, 16)
            strokePath(dl, color, 1.8)
        elseif name == "help" then
            local ts = imgui.CalcTextSize("?")
            dl:AddText(V2(cx - ts.x / 2, cy - ts.y / 2), color, "?")
        elseif name == "settings" then
            dl:AddCircle(V2(cx, cy), size * 0.27, color, 20, 1.8)
            dl:AddCircleFilled(V2(cx, cy), size * 0.08, color, 12)
            for i = 0, 3 do
                local a = math.pi * i / 2
                line(cx + math.cos(a) * size * 0.31, cy + math.sin(a) * size * 0.31,
                    cx + math.cos(a) * size * 0.42, cy + math.sin(a) * size * 0.42)
            end
        elseif name == "briefcase" then
            dl:AddRect(V2(left, top + 4), V2(right, bottom), color, 3, 0, 1.8)
            dl:AddRect(V2(cx - size * 0.14, top), V2(cx + size * 0.14, top + 5), color, 1, 0, 1.6)
            line(left + 2, cy, right - 2, cy, 1.4)
        elseif name == "bank" then
            dl:PathClear()
            dl:PathLineTo(V2(cx, top))
            dl:PathLineTo(V2(right, top + 6))
            dl:PathLineTo(V2(left, top + 6))
            dl:PathLineTo(V2(cx, top))
            strokePath(dl, color, 1.8)
            line(left, top + 8, right, top + 8)
            line(left + 2, bottom - 2, right - 2, bottom - 2)
            for i = 0, 2 do
                local px = left + size * (0.24 + i * 0.26)
                line(px, top + 9, px, bottom - 4, 1.5)
            end
        elseif name == "home" then
            dl:PathClear()
            dl:PathLineTo(V2(left, cy))
            dl:PathLineTo(V2(cx, top))
            dl:PathLineTo(V2(right, cy))
            strokePath(dl, color, 1.8)
            dl:AddRect(V2(left + 3, cy), V2(right - 3, bottom), color, 1, 0, 1.8)
            line(cx, bottom - 1, cx, cy + size * 0.13, 1.5)
        elseif name == "map" then
            dl:AddRect(V2(left, top), V2(right, bottom), color, 2, 0, 1.8)
            line(cx, top + 1, cx, bottom - 1, 1.4)
            line(left + size * 0.18, cy, right - size * 0.18, cy, 1.4)
        elseif name == "food" then
            dl:AddCircleFilled(V2(cx, cy + 1), size * 0.23, color, 20)
            dl:AddLine(V2(cx, top + 1), V2(cx, cy - size * 0.15), color, 1.8)
            dl:AddLine(V2(cx - size * 0.07, top + 1), V2(cx - size * 0.07, cy - size * 0.15), color, 1.2)
            dl:AddLine(V2(cx + size * 0.07, top + 1), V2(cx + size * 0.07, cy - size * 0.15), color, 1.2)
            dl:AddLine(V2(right - 1, top + 1), V2(right - 1, bottom - 1), color, 1.8)
        elseif name == "drink" then
            dl:AddRect(V2(cx - size * 0.16, top + 5), V2(cx + size * 0.16, bottom), color, 4, 0, 1.8)
            dl:AddRect(V2(cx - size * 0.09, top + 1), V2(cx + size * 0.09, top + 6), color, 1, 0, 1.6)
            line(cx - size * 0.12, cy, cx + size * 0.12, cy, 1.2)
        elseif name == "medicine" then
            dl:AddRect(V2(left + 1, top + size * 0.16), V2(right - 1, bottom - size * 0.16), color, 7, 0, 1.8)
            line(cx, top + size * 0.22, cx, bottom - size * 0.22, 2)
            line(left + size * 0.22, cy, right - size * 0.22, cy, 2)
        elseif name == "device" then
            dl:AddRect(V2(left + 3, top), V2(right - 3, bottom), color, 3, 0, 1.8)
            line(cx - size * 0.08, top + 3, cx + size * 0.08, top + 3, 1.2)
            dl:AddCircleFilled(V2(cx, bottom - 3), size * 0.035, color, 8)
        elseif name == "tool" then
            dl:AddLine(V2(left + 2, bottom - 2), V2(right - 2, top + 2), color, 3)
            dl:AddCircle(V2(left + 4, bottom - 4), size * 0.13, color, 12, 1.8)
            dl:AddLine(V2(right - 5, top + 1), V2(right - 1, top + 5), color, 2)
        elseif name == "material" then
            dl:PathClear()
            dl:PathLineTo(V2(cx, top + 1))
            dl:PathLineTo(V2(right, cy - 1))
            dl:PathLineTo(V2(cx, bottom - 1))
            dl:PathLineTo(V2(left, cy + 1))
            dl:PathLineTo(V2(cx, top + 1))
            strokePath(dl, color, 1.8)
            line(cx, top + 2, cx, bottom - 2, 1.2)
            line(left + 2, cy, right - 2, cy, 1.2)
        elseif name == "fuel" then
            dl:AddRect(V2(left + 2, top + 3), V2(right - 4, bottom - 1), color, 2, 0, 1.8)
            dl:AddRect(V2(left + 5, top + 6), V2(right - 7, cy - 1), color, 1, 0, 1.2)
            line(right - 4, top + 7, right, top + 11, 1.6)
            line(right, top + 11, right, bottom - 4, 1.6)
        elseif name == "clothing" then
            dl:PathClear()
            dl:PathLineTo(V2(cx - 4, top + 2))
            dl:PathLineTo(V2(left + 1, top + 8))
            dl:PathLineTo(V2(left + 5, cy))
            dl:PathLineTo(V2(left + 9, cy - 2))
            dl:PathLineTo(V2(left + 9, bottom - 1))
            dl:PathLineTo(V2(right - 9, bottom - 1))
            dl:PathLineTo(V2(right - 9, cy - 2))
            dl:PathLineTo(V2(right - 5, cy))
            dl:PathLineTo(V2(right - 1, top + 8))
            dl:PathLineTo(V2(cx + 4, top + 2))
            strokePath(dl, color, 1.8)
        elseif name == "fish" then
            dl:AddCircle(V2(cx - size * 0.04, cy), size * 0.20, color, 20, 1.8)
            dl:PathClear()
            dl:PathLineTo(V2(right - 1, cy))
            dl:PathLineTo(V2(right - 7, cy - 5))
            dl:PathLineTo(V2(right - 7, cy + 5))
            dl:PathLineTo(V2(right - 1, cy))
            strokePath(dl, color, 1.6)
            dl:AddCircleFilled(V2(left + 5, cy - 1), 1.4, color, 8)
        elseif name == "document" then
            dl:AddRect(V2(left + 3, top + 1), V2(right - 2, bottom - 1), color, 2, 0, 1.7)
            line(left + 7, top + 7, right - 6, top + 7, 1.2)
            line(left + 7, cy, right - 6, cy, 1.2)
            line(left + 7, bottom - 6, right - 10, bottom - 6, 1.2)
        elseif name == "warning" then
            dl:PathClear()
            dl:PathLineTo(V2(cx, top + 1))
            dl:PathLineTo(V2(right, bottom - 2))
            dl:PathLineTo(V2(left, bottom - 2))
            dl:PathLineTo(V2(cx, top + 1))
            strokePath(dl, color, 1.8)
            line(cx, cy - 5, cx, cy + 2, 1.8)
            dl:AddCircleFilled(V2(cx, bottom - 5), 1.3, color, 8)
        elseif name == "money" then
            dl:AddRect(V2(left, top + 3), V2(right, bottom - 3), color, 3, 0, 1.8)
            dl:AddCircle(V2(cx, cy), size * 0.12, color, 16, 1.5)
            line(left + 3, top + 7, left + 6, top + 7, 1.3)
            line(right - 6, bottom - 7, right - 3, bottom - 7, 1.3)
        elseif name == "weapon" then
            dl:AddRectFilled(V2(left + 2, cy - 5), V2(right - 2, cy + 1), color, 2)
            dl:AddRectFilled(V2(cx - 2, cy), V2(cx + 4, bottom - 2), color, 2)
            dl:AddRect(V2(left + 2, cy - 5), V2(right - 2, cy + 1), darkColor, 2, 0, 1.2)
            dl:AddRect(V2(cx - 2, cy), V2(cx + 4, bottom - 2), darkColor, 2, 0, 1.2)
        else
            dl:AddCircle(V2(cx, cy), size * 0.30, color, 20, 1.8)
            dl:AddCircleFilled(V2(cx, cy), size * 0.08, color, 12)
        end
    end

    local commandIcons = {
        ["/myv"] = "vehicle", ["/en"] = "vehicle", ["/windows"] = "vehicle",
        ["/help"] = "help", ["/ask"] = "help", ["/report"] = "help",
        ["/me"] = "chat", ["/do"] = "chat", ["/s"] = "chat", ["/w"] = "chat", ["/b"] = "chat",
        ["/settings"] = "settings", ["/mask"] = "settings", ["/livemode"] = "settings",
        ["/stats"] = "user", ["/mylevel"] = "user"
    }

    local navigationIcons = {
        ["Beranda"] = "default", ["Aksi Roleplay"] = "chat", ["Komunikasi"] = "chat",
        ["Kendaraan"] = "vehicle", ["Faksi"] = "user", ["Karakter"] = "user",
        ["Bantuan"] = "help", ["Inventori"] = "inventory",
        ["Info Server"] = "default", ["VIP Toys"] = "settings",
        ["Handphone"] = "phone", ["Pekerjaan"] = "briefcase",
        ["Kota & Ekonomi"] = "bank", ["Aktivitas Kota"] = "map",
        ["Personalisasi"] = "settings", ["Layanan & Faksi"] = "user",
        ["Alat & HUD"] = "settings"
    }

    return {
        draw = draw,
        command = function(command) return commandIcons[command] or "default" end,
        navigation = navigationIcons
    }
end
