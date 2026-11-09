-- ui_sounds.lua
-- Suara UI ala FiveM. Nada dibuat otomatis sebagai file WAV di
-- moonloader/resource/uiPBRP/sounds saat pertama kali dimuat:
--   * bell    : nada lonceng kaca (ada partial tidak harmonik) untuk open / success / notify
--   * chirp   : nada meluncur naik/turun untuk click / radial / error
--   * echo    : gema pendek supaya terasa "ruang", bukan beep kering
--
-- Mau pakai suara sendiri? Taruh file bernama click / hover / open / close / type / tab /
-- success / error / notify / radial dengan ekstensi .wav, .mp3, atau .ogg di folder tersebut.
-- File buatan sendiri selalu diprioritaskan.
--
-- Jika loadAudioStream tidak tersedia, dipakai fallback sampPlaySound (ID GTA).

return function()
    local RATE = 44100
    local VERSION = "v2"            -- naik versi = file bawaan dibuat ulang
    local TWO_PI = math.pi * 2
    local TAIL = 0.18               -- detik ekor gema di akhir tiap suara

    local fallbackIds = {
        click = 1052, open = 1057, type = 1056, close = 1052, tab = 1052,
        success = 1057, error = 1052, notify = 1057, radial = 1052
        -- hover sengaja tanpa fallback: tick GTA terlalu keras untuk hover
    }

    local volume = 0.55
    local enabled = true
    local minInterval = { hover = 0.045, type = 0.03, radial = 0.08 }
    local lastPlayAt = {}
    local lastHoverKey = nil
    local active = {}
    local files = {}
    local prepared = false
    local warned = {}

    ---------------------------------------------------------------- synth
    local seed = 20260
    local function rnd()
        seed = (seed * 16807) % 2147483647
        return seed / 1073741823.5 - 1
    end

    local function tone(t, freq, amp, decay)
        if t < 0 then return 0 end
        local attack = math.min(1, t / 0.0025)
        return math.sin(TWO_PI * freq * t) * attack * math.exp(-t * decay) * amp
    end

    -- lonceng kaca: nada dasar + partial tidak harmonik
    local function bell(t, freq, amp, decay)
        if t < 0 then return 0 end
        return tone(t, freq, amp, decay)
            + tone(t, freq * 2.76, amp * 0.22, decay * 2.2)
            + tone(t, freq * 5.40, amp * 0.08, decay * 3.5)
    end

    -- nada meluncur dari f0 ke f1 selama T detik
    local function chirp(t, f0, f1, T, amp, decay)
        if t < 0 then return 0 end
        local phase
        if t < T then
            phase = TWO_PI * (f0 * t + (f1 - f0) * t * t / (2 * T))
        else
            phase = TWO_PI * (f0 * T + (f1 - f0) * T / 2 + f1 * (t - T))
        end
        local attack = math.min(1, t / 0.002)
        return math.sin(phase) * attack * math.exp(-t * decay) * amp
    end

    -- klik noise sangat singkat (memberi kesan "tap")
    local function tick(t, amp, decay)
        if t < 0 or t > 0.012 then return 0 end
        return rnd() * amp * math.exp(-t * decay)
    end

    local definitions = {
        click = { duration = 0.10, fn = function(t)
            return chirp(t, 1900, 950, 0.03, 0.40, 60) + tone(t, 640, 0.14, 45) + tick(t, 0.10, 500)
        end },
        hover = { duration = 0.05, fn = function(t)
            return tone(t, 2400, 0.10, 170) + tone(t, 3600, 0.04, 260)
        end },
        tab = { duration = 0.10, fn = function(t)
            return tone(t, 1300, 0.26, 80) + tone(t - 0.035, 1750, 0.26, 80)
        end },
        type = { duration = 0.06, fn = function(t)
            return tone(t, 900, 0.22, 120) + tick(t, 0.07, 600)
        end },
        open = { duration = 0.44, fn = function(t)
            return chirp(t, 320, 880, 0.16, 0.13, 14)
                + bell(t - 0.05, 659, 0.26, 9) + bell(t - 0.12, 988, 0.28, 8)
        end },
        close = { duration = 0.40, fn = function(t)
            return chirp(t, 880, 320, 0.16, 0.13, 14)
                + bell(t, 988, 0.26, 10) + bell(t - 0.07, 659, 0.28, 9)
        end },
        success = { duration = 0.60, fn = function(t)
            return bell(t, 523, 0.24, 7) + bell(t - 0.07, 659, 0.26, 7)
                + bell(t - 0.14, 784, 0.28, 7) + bell(t - 0.21, 1047, 0.30, 7)
        end },
        error = { duration = 0.32, fn = function(t)
            return chirp(t, 240, 170, 0.12, 0.38, 10)
                + chirp(t - 0.09, 200, 140, 0.12, 0.34, 11)
                + tone(t, 480, 0.08, 14)
        end },
        notify = { duration = 0.46, fn = function(t)
            return bell(t, 880, 0.30, 8) + bell(t - 0.09, 1320, 0.28, 7)
        end },
        radial = { duration = 0.26, fn = function(t)
            return chirp(t, 260, 760, 0.14, 0.20, 16) + tone(t - 0.08, 1100, 0.12, 20)
        end },
    }

    local function u16(n)
        return string.char(n % 256, math.floor(n / 256) % 256)
    end

    local function u32(n)
        return string.char(n % 256, math.floor(n / 256) % 256,
            math.floor(n / 65536) % 256, math.floor(n / 16777216) % 256)
    end

    local function writeWav(path, duration, fn)
        local total = duration + TAIL
        local count = math.floor(RATE * total)
        seed = 20260

        local samples = {}
        for i = 0, count - 1 do
            samples[i + 1] = fn(i / RATE)
        end

        -- gema ringan (umpan balik) untuk kesan ruang
        local d1, d2 = math.floor(RATE * 0.029), math.floor(RATE * 0.047)
        for i = 1, count do
            local e = 0
            if i > d1 then e = e + samples[i - d1] * 0.26 end
            if i > d2 then e = e + samples[i - d2] * 0.14 end
            samples[i] = samples[i] + e
        end

        local peak = 0
        for i = 1, count do
            local a = math.abs(samples[i])
            if a > peak then peak = a end
        end
        local gain = peak > 0.92 and (0.92 / peak) or 1

        local chunks, buffer = {}, {}
        for i = 0, count - 1 do
            local t = i / RATE
            local fade = math.min(1, (total - t) / 0.008)
            local v = samples[i + 1] * gain * fade
            if v > 1 then v = 1 elseif v < -1 then v = -1 end
            local s = math.floor(v * 30000)
            if s < 0 then s = s + 65536 end
            buffer[#buffer + 1] = u16(s)
            if #buffer >= 2048 then
                chunks[#chunks + 1] = table.concat(buffer)
                buffer = {}
            end
        end
        chunks[#chunks + 1] = table.concat(buffer)
        local data = table.concat(chunks)

        local file = io.open(path, "wb")
        if not file then return false end
        file:write("RIFF", u32(36 + #data), "WAVE", "fmt ", u32(16), u16(1), u16(1),
            u32(RATE), u32(RATE * 2), u16(2), u16(16), "data", u32(#data), data)
        file:close()
        return true
    end

    local function fileExists(path)
        local f = io.open(path, "rb")
        if f then f:close() return true end
        return false
    end

    ---------------------------------------------------------------- setup
    local function prepare()
        if prepared then return end
        prepared = true
        pcall(function()
            local base = getWorkingDirectory() .. "/resource"
            pcall(createDirectory, base)
            base = base .. "/uiPBRP"
            pcall(createDirectory, base)
            base = base .. "/sounds"
            pcall(createDirectory, base)

            for kind, def in pairs(definitions) do
                local custom
                for _, ext in ipairs({ "wav", "mp3", "ogg" }) do
                    local candidate = string.format("%s/%s.%s", base, kind, ext)
                    if fileExists(candidate) then custom = candidate break end
                end
                if custom then
                    files[kind] = { path = custom, ttl = 4 }
                else
                    local path = string.format("%s/%s_%s.wav", base, kind, VERSION)
                    if not fileExists(path) then
                        pcall(writeWav, path, def.duration, def.fn)
                    end
                    if fileExists(path) then
                        files[kind] = { path = path, ttl = def.duration + TAIL + 0.4 }
                    end
                end
            end
        end)
    end

    local function cleanup(now)
        for i = #active, 1, -1 do
            if now >= active[i].expire then
                pcall(releaseAudioStream, active[i].handle)
                table.remove(active, i)
            end
        end
    end

    local function playFile(kind)
        local entry = files[kind]
        if not entry or type(loadAudioStream) ~= "function" then return false end
        local ok, handle = pcall(loadAudioStream, entry.path)
        if not ok or not handle or handle == 0 then return false end
        pcall(setAudioStreamVolume, handle, volume)
        pcall(setAudioStreamState, handle, 1)
        active[#active + 1] = { handle = handle, expire = os.clock() + entry.ttl }
        return true
    end

    ---------------------------------------------------------------- api
    local function play(kind)
        if not definitions[kind] then
            -- suara tidak dikenal tidak boleh mematikan UI; catat sekali saja
            if not warned[kind] then
                warned[kind] = true
                print("[PBRP/PKU UI] Suara tidak dikenal: " .. tostring(kind))
            end
            return
        end
        if not enabled then return end

        local now = os.clock()
        local interval = minInterval[kind]
        if interval and lastPlayAt[kind] and now - lastPlayAt[kind] < interval then return end
        lastPlayAt[kind] = now

        prepare()
        cleanup(now)
        if playFile(kind) then return end

        local soundId = fallbackIds[kind]
        if not soundId then return end
        if not isSampAvailable() or not sampIsLocalPlayerSpawned() then return end
        local x, y, z = getCharCoordinates(PLAYER_PED)
        sampPlaySound(soundId, x, y, z)
    end

    -- Panggil tepat setelah item imgui; key membedakan item agar tick hanya berbunyi
    -- ketika kursor berpindah ke item baru.
    local function hover(key)
        if key == lastHoverKey then return end
        lastHoverKey = key
        play("hover")
    end

    local function playClickIfHovered(imgui)
        local anyHovered = imgui.IsAnyItemHovered()
        if not anyHovered then lastHoverKey = nil end
        if imgui.IsMouseClicked(0) and anyHovered then
            play("click")
        end
    end

    local function setVolume(value)
        volume = math.max(0, math.min(1, tonumber(value) or volume))
    end

    local function setEnabled(value)
        enabled = value and true or false
    end

    return {
        play = play,
        hover = hover,
        playClickIfHovered = playClickIfHovered,
        setVolume = setVolume,
        setEnabled = setEnabled
    }
end
