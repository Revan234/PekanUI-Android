return function(imgui, V2, sendChat, isPlayerUiReady)
    local open, editing, cameraId = false, false, 0

    local function onServerMessage(message)
        local id = message:match("^@PBRPUI:CCTV:OPEN:(%d+)$")
        if id then
            cameraId, open, editing = tonumber(id) or 0, true, false
            return true
        end
        id = message:match("^@PBRPUI:CCTV:EDIT:(%d+)$")
        if id then
            cameraId, open, editing = tonumber(id) or 0, true, true
            return true
        end
        if message == "@PBRPUI:CCTV:CLOSE" then
            open = false
            return true
        end
        return false
    end

    local function button(label, command, width)
        if imgui.Button(label, V2(width or 92, 32)) then sendChat(command) end
    end

    local frame = imgui.OnFrame(
        function() return open and isPlayerUiReady() end,
        function()
            local display = imgui.GetIO().DisplaySize
            local width, height = editing and 420 or 380, editing and 182 or 130
            imgui.SetNextWindowPos(V2(display.x - width - 18, 80), imgui.Cond.Always)
            imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
            local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
                + imgui.WindowFlags.NoSavedSettings + imgui.WindowFlags.NoScrollbar
            if imgui.Begin("##cctv_control", nil, flags) then
                imgui.TextColored(imgui.ImVec4(0.86, 0.69, 0.28, 1), "PEKANBARU CCTV")
                imgui.SameLine()
                imgui.TextDisabled(("KAMERA #%d"):format(cameraId))
                imgui.Separator()
                if editing then
                    imgui.TextDisabled("Atur posisi kamera, lalu simpan atau batalkan.")
                    button("Kiri", "/cctvmove left"); imgui.SameLine()
                    button("Kanan", "/cctvmove right"); imgui.SameLine()
                    button("Maju", "/cctvmove forward"); imgui.SameLine()
                    button("Mundur", "/cctvmove back")
                    button("Naik", "/cctvmove up"); imgui.SameLine()
                    button("Turun", "/cctvmove down"); imgui.SameLine()
                    button("Rotasi -", "/cctvmove rotleft"); imgui.SameLine()
                    button("Rotasi +", "/cctvmove rotright")
                    button("Simpan", "/cctvsave", 120); imgui.SameLine()
                    button("Batal", "/cctvcancel", 120)
                else
                    button("Kiri", "/cctvturn left"); imgui.SameLine()
                    button("Kanan", "/cctvturn right"); imgui.SameLine()
                    button("Atas", "/cctvturn up"); imgui.SameLine()
                    button("Bawah", "/cctvturn down")
                    button("Sebelumnya", "/cctvprev", 120); imgui.SameLine()
                    button("Berikutnya", "/cctvnext", 120); imgui.SameLine()
                    button("Tutup", "/cctvclose", 92)
                    imgui.TextDisabled("Keyboard: panah untuk rotasi; Space/Ctrl untuk ganti kamera.")
                end
                imgui.End()
            end
        end
    )
    frame.HideCursor = false

    return {
        onServerMessage = onServerMessage,
        isOpen = function() return open end,
        close = function()
            if open then sendChat(editing and "/cctvcancel" or "/cctvclose") end
            open = false
        end,
    }
end
