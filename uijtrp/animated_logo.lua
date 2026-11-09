return function(imgui, V2, frameDirectory, shouldShow)
    local frames = {}
    imgui.OnInitialize(function()
        local frameNumber = 0
        while true do
            local path = string.format("%s/frame_%03d.png", frameDirectory, frameNumber)
            if not doesFileExist(path) then break end

            local ok, texture = pcall(imgui.CreateTextureFromFile, path)
            if not ok or not texture then
                print("[PBRP/PKU UI] Gagal memuat frame logo: " .. tostring(texture))
                break
            end
            frames[#frames + 1] = texture
            frameNumber = frameNumber + 1
        end

        if #frames == 0 then
            print("[PBRP/PKU UI] Frame animasi logo tidak ditemukan: " .. frameDirectory)
        else
            print("[PBRP/PKU UI] Animasi logo berhasil dimuat: " .. #frames .. " frame.")
        end
    end)

    local frame = imgui.OnFrame(
        function()
            return #frames > 0 and shouldShow() and isSampAvailable()
        end,
        function()
            local display = imgui.GetIO().DisplaySize
            local width, height = 112, 112
            local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoBackground
            imgui.SetNextWindowPos(V2(display.x - width - 20, 18), imgui.Cond.Always)
            imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
            imgui.SetNextWindowBgAlpha(0)
            imgui.Begin("##pbrp_animated_logo", nil, flags)

            local textureIndex = math.floor(os.clock() * 12) % #frames + 1
            local drawList = imgui.GetWindowDrawList()
            local position = imgui.GetWindowPos()
            drawList:AddImage(
                frames[textureIndex],
                position,
                V2(position.x + width, position.y + height)
            )
            imgui.End()
        end
    )
    frame.HideCursor = true
end
