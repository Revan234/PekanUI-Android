return function()
    local lfsOk, lfs = pcall(require, "lfs")
    local photos = {}
    local profileDirectory
    local screenshotsDirectory
    local status = ""
    local busy = false
    local cameraStatus = ""
    local originalFov
    local currentFov
    local zoom = 1

    local function directoryExists(path)
        return path ~= nil and lfsOk and lfs.attributes(path, "mode") == "directory"
    end

    local function ensureDirectory(path)
        if not path or path == "" then return false end
        if directoryExists(path) then return true end
        local ok = pcall(createDirectory, path)
        return ok and directoryExists(path)
    end

    local function copyFile(sourcePath, targetPath)
        local source, sourceError = io.open(sourcePath, "rb")
        if not source then return false, sourceError end
        local data = source:read("*a")
        source:close()

        local target, targetError = io.open(targetPath, "wb")
        if not target then return false, targetError end
        local ok, writeError = target:write(data)
        target:close()
        if not ok then return false, writeError end
        return true
    end

    local function scan(directory)
        local result = {}
        if not directoryExists(directory) then return result end

        for filename in lfs.dir(directory) do
            local extension = filename:match("%.([%w]+)$")
            if extension and (extension:lower() == "png" or extension:lower() == "jpg"
                or extension:lower() == "jpeg") then
                local path = directory .. "/" .. filename
                local attributes = lfs.attributes(path)
                if attributes and attributes.mode == "file" then
                    result[#result + 1] = {
                        name = filename,
                        path = path,
                        modified = attributes.modification or 0
                    }
                end
            end
        end

        table.sort(result, function(a, b) return a.modified > b.modified end)
        return result
    end

    local function prepare()
        if not lfsOk then
            status = "Modul lfs tidak tersedia; album lokal tidak dapat dibaca."
            return false
        end

        if profileDirectory and screenshotsDirectory then return true end

        local ok, profileName = pcall(function()
            local _, playerId = sampGetPlayerIdByCharHandle(PLAYER_PED)
            return sampGetPlayerNickname(playerId)
        end)
        if not ok or not profileName or profileName == "" then
            status = "Nama pemain lokal tidak dapat dibaca."
            return false
        end

        local safeName = profileName:gsub("[^%w%-_]", "_")
        local base = getWorkingDirectory() .. "/config"
        if not ensureDirectory(base) then
            status = "Folder MoonLoader config tidak dapat dibuat."
            return false
        end
        base = base .. "/uiPBRP"
        if not ensureDirectory(base) then
            status = "Folder profil UI PBRP/PKU tidak dapat dibuat."
            return false
        end
        base = base .. "/photos"
        if not ensureDirectory(base) then
            status = "Folder penyimpanan foto tidak dapat dibuat."
            return false
        end
        profileDirectory = base .. "/" .. safeName
        if not ensureDirectory(profileDirectory) then
            status = "Folder album pemain tidak dapat dibuat."
            profileDirectory = nil
            return false
        end

        local userProfile = os.getenv("USERPROFILE")
        if userProfile and userProfile ~= "" then
            screenshotsDirectory = userProfile
                .. "/Documents/GTA San Andreas User Files/SAMP/screens"
        else
            local candidates = {
                "/storage/emulated/0/Pictures/Screenshots",
                "/storage/emulated/0/DCIM/Screenshots",
                "/storage/emulated/0/Android/media/com.sampmobilerp.game/screenshots",
                getWorkingDirectory() .. "/screenshots",
            }
            for _, candidate in ipairs(candidates) do
                if directoryExists(candidate) then
                    screenshotsDirectory = candidate
                    break
                end
            end
            if not screenshotsDirectory then
                status = "Folder screenshot Android tidak ditemukan. Simpan screenshot ke Pictures/Screenshots."
                return false
            end
        end
        status = ""
        return true
    end

    local function refresh()
        if not prepare() then return false end
        photos = scan(profileDirectory)
        return true
    end

    local function readCameraFov()
        local getter
        if type(getCameraFov) == "function" then
            getter = getCameraFov
        elseif type(getCameraFOV) == "function" then
            getter = getCameraFOV
        end
        if not getter then return nil end

        local ok, value = pcall(getter)
        value = ok and tonumber(value) or nil
        if value and value > 0 and value < 180 then return value end
        return nil
    end

    local function setCameraFov(from, to)
        if type(cameraSetLerpFov) ~= "function" then
            cameraStatus = "API FOV kamera tidak tersedia pada versi MoonLoader ini."
            return false
        end

        local ok, result = pcall(cameraSetLerpFov, from, to, 350, 1)
        if not ok or result == false then
            cameraStatus = "FOV kamera gagal diubah."
            print("[PBRP/PKU UI] Gagal mengubah FOV kamera: " .. tostring(result))
            return false
        end
        return true
    end

    local function beginCamera()
        if originalFov then return true end
        originalFov = readCameraFov()
        if not originalFov then
            cameraStatus = "Pembacaan FOV tidak tersedia; zoom kamera dinonaktifkan."
            return false
        end
        currentFov = originalFov
        zoom = 1
        cameraStatus = ""
        return true
    end

    local function setZoom(multiplier)
        if multiplier ~= 0.5 and multiplier ~= 1 and multiplier ~= 2 then
            cameraStatus = "Pilihan zoom kamera tidak valid."
            return false
        end
        if not originalFov and not beginCamera() then return false end

        local base = math.rad(originalFov / 2)
        local targetFov = math.deg(2 * math.atan(math.tan(base) / multiplier))
        targetFov = math.max(20, math.min(110, targetFov))
        local fromFov = readCameraFov() or currentFov or originalFov
        if not setCameraFov(fromFov, targetFov) then return false end

        currentFov = targetFov
        zoom = multiplier
        cameraStatus = ""
        return true
    end

    local function restoreCamera()
        if not originalFov then return end
        local fromFov = readCameraFov() or currentFov or originalFov
        local restored = setCameraFov(fromFov, originalFov)
        if restored then
            originalFov = nil
            currentFov = nil
            zoom = 1
            cameraStatus = ""
        end
    end

    local function capture()
        cameraStatus = ""
        if busy then
            status = "Kamera sedang memproses foto sebelumnya."
            return
        end
        if not prepare() then return end
        if type(setVirtualKeyDown) ~= "function" then
            status = "API tombol virtual tidak tersedia; kamera tidak dapat mengambil screenshot."
            return
        end
        if not ensureDirectory(screenshotsDirectory) then
            status = "Folder screenshot SA-MP tidak dapat dibuat."
            return
        end

        local before = {}
        for _, photo in ipairs(scan(screenshotsDirectory)) do
            before[photo.name] = true
        end

        busy = true
        status = "Mengambil screenshot melalui tombol kamera SA-MP..."
        lua_thread.create(function()
            setVirtualKeyDown(0x77, true)
            wait(100)
            setVirtualKeyDown(0x77, false)
            wait(1200)

            local created
            for _, photo in ipairs(scan(screenshotsDirectory)) do
                if not before[photo.name] then
                    created = photo
                    break
                end
            end

            if not created then
                status = "Screenshot baru tidak ditemukan. Pastikan SA-MP menyimpan tombol F8 ke folder Documents standar."
                busy = false
                return
            end

            local extension = created.name:match("%.([%w]+)$") or "png"
            local index = #scan(profileDirectory) + 1
            local targetPath = string.format("%s/foto_%s_%03d.%s",
                profileDirectory, os.date("%Y%m%d_%H%M%S"), index, extension)
            local copied, copyError = copyFile(created.path, targetPath)
            if not copied then
                status = "Foto gagal disalin ke album: " .. tostring(copyError)
                busy = false
                return
            end

            refresh()
            status = "Foto tersimpan lokal untuk profil " .. profileDirectory:match("([^/]+)$") .. "."
            busy = false
        end)
    end

    return {
        capture = capture,
        refresh = refresh,
        beginCamera = beginCamera,
        setZoom = setZoom,
        restoreCamera = restoreCamera,
        zoom = function() return zoom end,
        cameraStatus = function() return cameraStatus end,
        photos = function() return photos end,
        status = function() return status end,
        isBusy = function() return busy end
    }
end
