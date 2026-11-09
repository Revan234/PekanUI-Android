-- ui_theme.lua : tema gelap modern (ala txAdmin) untuk semua panel
local M = {}

M.accent = { 0.86, 0.12, 0.16 }
M.gold = { 0.94, 0.70, 0.25 }

function M.apply(imgui)
    imgui.OnInitialize(function()
        local s = imgui.GetStyle()
        local c, C = s.Colors, imgui.Col
        local a = M.accent
        local function v(r, g, b, al) return imgui.ImVec4(r, g, b, al or 1) end

        s.WindowRounding, s.ChildRounding, s.FrameRounding = 12, 10, 7
        s.PopupRounding, s.GrabRounding, s.ScrollbarRounding = 8, 7, 9
        s.WindowPadding = imgui.ImVec2(18, 16)
        s.FramePadding = imgui.ImVec2(11, 7)
        s.ItemSpacing = imgui.ImVec2(9, 9)
        s.WindowBorderSize, s.FrameBorderSize, s.ChildBorderSize = 1, 0, 1
        s.ScrollbarSize = 10

        c[C.WindowBg]       = v(0.025, 0.025, 0.030, 0.98)
        c[C.ChildBg]        = v(0.055, 0.055, 0.060, 1)
        c[C.PopupBg]        = v(0.055, 0.055, 0.060, 1)
        c[C.Border]         = v(0.22, 0.16, 0.10, 1)
        c[C.TitleBg]        = v(0.025, 0.025, 0.030, 1)
        c[C.TitleBgActive]  = v(0.025, 0.025, 0.030, 1)
        c[C.FrameBg]        = v(0.09, 0.075, 0.065, 1)
        c[C.FrameBgHovered] = v(0.15, 0.085, 0.075, 1)
        c[C.FrameBgActive]  = v(0.20, 0.095, 0.075, 1)
        c[C.Button]         = v(0.11, 0.065, 0.055, 1)
        c[C.ButtonHovered]  = v(a[1] * 0.8, a[2] * 0.8, a[3] * 0.8, 1)
        c[C.ButtonActive]   = v(a[1], a[2], a[3], 1)
        c[C.Header]         = v(a[1], a[2], a[3], 0.20)
        c[C.HeaderHovered]  = v(a[1], a[2], a[3], 0.34)
        c[C.HeaderActive]   = v(a[1], a[2], a[3], 0.48)
        c[C.Separator]      = v(0.17, 0.18, 0.22, 1)
        c[C.PlotHistogram]  = v(a[1], a[2], a[3], 1)
        c[C.ScrollbarBg]    = v(0, 0, 0, 0)
        c[C.ScrollbarGrab]  = v(0.24, 0.26, 0.32, 1)
        c[C.Text]           = v(0.92, 0.94, 0.98, 1)
        c[C.TextDisabled]   = v(0.48, 0.51, 0.59, 1)
    end)
end

-- tombol sidebar: aktif = warna aksen
function M.navButton(imgui, label, active, w)
    local a = M.accent
    if active then
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(a[1], a[2], a[3], 0.24))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(a[1], a[2], a[3], 0.34))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(a[1], a[2], a[3], 0.46))
    else
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.04, 0.04, 0.04, 0))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15, 0.08, 0.07, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.22, 0.09, 0.07, 1))
    end
    imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 7)
    local caption = active and (">  " .. label) or ("   " .. label)
    local clicked = imgui.Button(caption, imgui.ImVec2(w, 36))
    imgui.PopStyleVar()
    imgui.PopStyleColor(3)
    return clicked
end

-- kartu statistik kecil
function M.card(imgui, id, title, value, w)
    imgui.BeginChild(id, imgui.ImVec2(w, 76), true)
    imgui.TextDisabled(title:upper())
    imgui.TextColored(imgui.ImVec4(M.gold[1], M.gold[2], M.gold[3], 1), tostring(value))
    imgui.EndChild()
end

function M.animateWindow(imgui, startedAt)
    local progress = math.min(1, math.max(0, (os.clock() - startedAt) / 0.28))
    local eased = 1 - (1 - progress) * (1 - progress) * (1 - progress)
    imgui.PushStyleVarFloat(imgui.StyleVar.Alpha, 0.35 + eased * 0.65)
    return 18 * (1 - eased)
end

function M.panelHeader(imgui, V2, title, subtitle, badge, accent)
    local color = accent or imgui.ImVec4(M.accent[1], M.accent[2], M.accent[3], 1)
    imgui.BeginChild("##panel_header_" .. title, V2(-1, 68), true)
    imgui.TextColored(color, title)
    imgui.SameLine()
    imgui.TextDisabled(" / " .. badge)
    imgui.TextDisabled(subtitle)
    imgui.EndChild()
end

return M
