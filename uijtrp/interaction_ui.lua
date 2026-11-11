return function(imgui, V2, color, sendChat, inventoryUI, isPlayerUiReady,
    isChatInputActive, isDialogActive, keyWasPressed)
    local state = {
        target = nil,
        menuTarget = nil,
        menuOpen = false,
        payAmount = imgui.new.int(100),
        scanAt = 0,
    }
    local frame

    local function distanceBetween(x1, y1, z1, x2, y2, z2)
        return getDistanceBetweenCoords3d(x1, y1, z1, x2, y2, z2)
    end

    local function getPlayerTarget()
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local closest, closestDistance

        for playerId = 0, 999 do
            local ok, ped = sampGetCharHandleBySampPlayerId(playerId)
            if ok and ped ~= PLAYER_PED and doesCharExist(ped) then
                local x, y, z = getCharCoordinates(ped)
                local distance = distanceBetween(px, py, pz, x, y, z)
                if distance <= 2.5 and (not closestDistance or distance < closestDistance) then
                    local screenX, screenY = convert3DCoordsToScreen(x, y, z + 1.0)
                    if screenX and screenY then
                        closest = {
                            kind = "player",
                            id = playerId,
                            name = sampGetPlayerNickname(playerId),
                            x = x,
                            y = y,
                            z = z,
                            screenX = screenX,
                            screenY = screenY,
                            distance = distance,
                        }
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    local function getVehicleTarget()
        local px, py, pz = getCharCoordinates(PLAYER_PED)
        local closest, closestDistance
        if type(sampGetCarHandleBySampVehicleId) ~= "function" then
            return nil
        end

        for vehicleId = 0, 1999 do
            local ok, vehicle = sampGetCarHandleBySampVehicleId(vehicleId)
            if ok and doesVehicleExist(vehicle) then
                local x, y, z = getCarCoordinates(vehicle)
                local distance = distanceBetween(px, py, pz, x, y, z)
                if distance <= 4.0 and (not closestDistance or distance < closestDistance) then
                    local screenX, screenY = convert3DCoordsToScreen(x, y, z + 1.2)
                    if screenX and screenY then
                        closest = {
                            kind = "vehicle",
                            id = vehicleId,
                            x = x,
                            y = y,
                            z = z,
                            screenX = screenX,
                            screenY = screenY,
                            distance = distance,
                        }
                        closestDistance = distance
                    end
                end
            end
        end
        return closest
    end

    local function sameTarget(first, second)
        return first and second and first.kind == second.kind and first.id == second.id
    end

    local function isPlayerInVehicle()
        if type(isCharInAnyCar) ~= "function" then return false end
        local ok, inVehicle = pcall(isCharInAnyCar, PLAYER_PED)
        return ok and inVehicle
    end

    local function update(enabled)
        enabled = enabled and isPlayerUiReady()
        if not enabled or isPlayerInVehicle() then
            state.target = nil
            state.menuTarget = nil
            state.menuOpen = false
            if frame then frame.HideCursor = true end
            return
        end

        local now = os.clock()
        if now >= state.scanAt then
            state.scanAt = now + 0.12
            local playerTarget = getPlayerTarget()
            local vehicleTarget = getVehicleTarget()
            if playerTarget and vehicleTarget then
                state.target = playerTarget.distance <= vehicleTarget.distance and playerTarget or vehicleTarget
            else
                state.target = playerTarget or vehicleTarget
            end
        end

        if state.menuOpen and not sameTarget(state.target, state.menuTarget) then
            state.menuOpen = false
            state.menuTarget = nil
        end

        if state.menuOpen then
            if keyWasPressed(0x1B) then
                state.menuOpen = false
                state.menuTarget = nil
            end
            return
        end

        if frame then frame.HideCursor = true end
        if state.target and not isChatInputActive() and not isDialogActive() then
            if keyWasPressed(0x12) then
                state.menuTarget = state.target
                state.menuOpen = true
                state.payAmount[0] = 100
                if frame then frame.HideCursor = false end
            end
        end
    end

    local function drawEye(drawList, x, y)
        local points = {}
        for index = 0, 8 do
            local t = index / 8
            points[index + 1] = V2(x - 9 + t * 18, y - 5 + math.sin(t * math.pi) * 5)
        end
        for index = 1, 8 do
            drawList:AddLine(points[index], points[index + 1], color(0.94, 0.96, 1.0, 1), 1.7)
            local lowerA = V2(points[index].x, y + 5 - (points[index].y - (y - 5)))
            local lowerB = V2(points[index + 1].x, y + 5 - (points[index + 1].y - (y - 5)))
            drawList:AddLine(lowerA, lowerB, color(0.94, 0.96, 1.0, 1), 1.7)
        end
        drawList:AddCircleFilled(V2(x, y), 3.2, color(0.94, 0.96, 1.0, 1), 16)
        drawList:AddCircleFilled(V2(x, y), 1.4, color(0.10, 0.12, 0.16, 1), 12)
    end

    local function drawPrompt(drawList, target)
        local key = "ALT"
        local subject = target.kind == "player" and target.name or "Kendaraan"
        if #subject > 14 then subject = subject:sub(1, 13) .. "..." end
        local width, height = 204, 52
        local x, y = target.screenX - width / 2, target.screenY - height - 12
        drawList:AddRectFilled(V2(x + 2, y + 3), V2(x + width + 2, y + height + 3),
            color(0, 0, 0, 0.42), 10)
        drawList:AddRectFilled(V2(x, y), V2(x + width, y + height),
            color(0.035, 0.045, 0.065, 0.96), 10)
        drawList:AddRect(V2(x, y), V2(x + width, y + height),
            color(0.86, 0.12, 0.16, 0.68), 10, 0, 1)
        drawList:AddRectFilled(V2(x, y + 10), V2(x + 3, y + height - 10),
            color(0.92, 0.16, 0.20, 1), 2)
        drawEye(drawList, x + 23, y + 25)
        drawList:AddText(V2(x + 44, y + 8),
            color(0.62, 0.68, 0.78, 1),
            target.kind == "player" and "PEMAIN TERDEKAT" or "KENDARAAN TERDEKAT")
        drawList:AddText(V2(x + 44, y + 27), color(0.96, 0.97, 1, 1), subject)
        local keyX = x + width - 46
        drawList:AddRectFilled(V2(keyX, y + 10), V2(keyX + 34, y + 42),
            color(0.86, 0.12, 0.16, 0.24), 6)
        drawList:AddRect(V2(keyX, y + 10), V2(keyX + 34, y + 42),
            color(0.92, 0.24, 0.28, 0.72), 6, 0, 1)
        local keySize = imgui.CalcTextSize(key)
        drawList:AddText(V2(keyX + (34 - keySize.x) / 2, y + 17),
            color(1, 0.93, 0.94, 1), key)
        drawList:AddLine(V2(target.screenX, y + height), V2(target.screenX, target.screenY - 5),
            color(0.86, 0.12, 0.16, 0.78), 1.3)
    end

    local function sendPlayerAction(command)
        if not state.menuTarget or state.menuTarget.kind ~= "player" then return end
        sendChat(command)
        state.menuOpen = false
        state.menuTarget = nil
    end

    local function drawActionButton(label, id, height)
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.11, 0.075, 0.08, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.27, 0.09, 0.12, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.40, 0.10, 0.13, 1))
        local clicked = imgui.Button(label .. "##" .. id, V2(-1, height))
        imgui.PopStyleColor(3)
        return clicked
    end

    local function drawMenu(display)
        local target = state.menuTarget
        if not state.menuOpen or not target then return end

        local isPlayer = target.kind == "player"
        local width, height = isPlayer and 330 or 310, isPlayer and 445 or 360
        local x = math.max(12, math.min(display.x - width - 12, target.screenX + 18))
        local y = math.max(12, math.min(display.y - height - 12, target.screenY - 20))
        imgui.SetNextWindowPos(V2(x, y), imgui.Cond.Always)
        imgui.SetNextWindowSize(V2(width, height), imgui.Cond.Always)
        local flags = imgui.WindowFlags.NoTitleBar + imgui.WindowFlags.NoResize
            + imgui.WindowFlags.NoCollapse + imgui.WindowFlags.NoSavedSettings
            + imgui.WindowFlags.NoScrollbar
        imgui.PushStyleColor(imgui.Col.WindowBg, imgui.ImVec4(0.035, 0.040, 0.055, 0.98))
        imgui.PushStyleColor(imgui.Col.Border, imgui.ImVec4(0.86, 0.12, 0.16, 0.58))
        imgui.PushStyleColor(imgui.Col.ChildBg, imgui.ImVec4(0.085, 0.050, 0.060, 1))
        imgui.PushStyleColor(imgui.Col.FrameBg, imgui.ImVec4(0.10, 0.11, 0.15, 1))
        imgui.PushStyleColor(imgui.Col.FrameBgHovered, imgui.ImVec4(0.16, 0.09, 0.11, 1))
        imgui.PushStyleVarFloat(imgui.StyleVar.WindowRounding, 12)
        imgui.PushStyleVarFloat(imgui.StyleVar.FrameRounding, 7)
        if not imgui.Begin("##PBRP_context_card", nil, flags) then
            imgui.End()
            imgui.PopStyleVar(2)
            imgui.PopStyleColor(5)
            return
        end

        imgui.BeginChild("##PBRP_context_header", V2(-1, 76), true)
        local headerPos = imgui.GetCursorScreenPos()
        local headerDraw = imgui.GetWindowDrawList()
        headerDraw:AddRectFilledMultiColor(
            V2(headerPos.x - 8, headerPos.y - 7), V2(headerPos.x + width - 20, headerPos.y - 4),
            color(0.94, 0.16, 0.20, 1), color(0.48, 0.08, 0.12, 0.35),
            color(0.48, 0.08, 0.12, 0.35), color(0.94, 0.16, 0.20, 1))
        drawEye(headerDraw, headerPos.x + 13, headerPos.y + 27)
        imgui.SetCursorPosX(34)
        imgui.BeginGroup()
        imgui.TextColored(imgui.ImVec4(0.95, 0.43, 0.47, 1),
            isPlayer and "INTERAKSI PEMAIN" or "INTERAKSI KENDARAAN")
        imgui.TextColored(imgui.ImVec4(0.97, 0.98, 1, 1),
            isPlayer and target.name or ("Kendaraan #" .. tostring(target.id)))
        imgui.TextDisabled(string.format("ID %d  /  %.1f m", target.id, target.distance))
        imgui.EndGroup()
        imgui.EndChild()
        imgui.Spacing()

        if isPlayer then
            imgui.TextDisabled("AKSI CEPAT")
            imgui.InputInt("Jumlah bayar", state.payAmount, 100, 1000)
            if drawActionButton("BAYAR  /  TRANSFER", "context_pay", 34) then
                if state.payAmount[0] > 0 then
                    sendPlayerAction(string.format("/pay %d %d", target.id, state.payAmount[0]))
                end
            end
            if drawActionButton("MINTA GENDONG", "context_carry", 34) then
                sendPlayerAction("/carry " .. target.id)
            end
            if drawActionButton("BAGIKAN ITEM", "context_give", 34) then
                inventoryUI.openForPlayer(target.id)
                state.menuOpen = false
                state.menuTarget = nil
            end
            if drawActionButton("BERSALAMAN", "context_handshake", 34) then
                sendPlayerAction("/rpui_handshake " .. target.id)
            end
        else
            imgui.TextDisabled("AKSES KENDARAAN")
            if drawActionButton("MULAI SERVICE BENGKEL", "context_service", 40) then
                sendChat("/service")
                state.menuOpen = false
                state.menuTarget = nil
            end
            if drawActionButton("BUKA / TUTUP HOOD", "context_hood", 40) then
                sendChat("/rpui_vehicle hood " .. target.id)
                state.menuOpen = false
                state.menuTarget = nil
            end
            if drawActionButton("BUKA / TUTUP BAGASI", "context_trunk", 40) then
                sendChat("/rpui_vehicle trunk " .. target.id)
                state.menuOpen = false
                state.menuTarget = nil
            end
        end

        imgui.Spacing()
        imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0.12, 0.13, 0.17, 1))
        imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.20, 0.12, 0.14, 1))
        imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.25, 0.13, 0.15, 1))
        if imgui.Button("TUTUP##context_close", V2(-1, 30)) then
            state.menuOpen = false
            state.menuTarget = nil
        end
        imgui.PopStyleColor(3)
        imgui.End()
        imgui.PopStyleVar(2)
        imgui.PopStyleColor(5)
    end

    frame = imgui.OnFrame(
        function()
            return isPlayerUiReady() and (state.target ~= nil or state.menuOpen)
        end,
        function()
            local display = imgui.GetIO().DisplaySize
            local flags = imgui.WindowFlags.NoDecoration + imgui.WindowFlags.NoMove
                + imgui.WindowFlags.NoResize + imgui.WindowFlags.NoSavedSettings
                + imgui.WindowFlags.NoInputs + imgui.WindowFlags.NoBackground
            imgui.SetNextWindowPos(V2(0, 0), imgui.Cond.Always)
            imgui.SetNextWindowSize(display, imgui.Cond.Always)
            imgui.Begin("##PBRP_interaction_overlay", nil, flags)
            local drawList = imgui.GetWindowDrawList()
            if state.target and not state.menuOpen then
                drawPrompt(drawList, state.target)
            end
            imgui.End()
            drawMenu(display)
        end
    )
    frame.HideCursor = false

    return {
        update = update,
        isOpen = function() return state.menuOpen end,
    }
end
