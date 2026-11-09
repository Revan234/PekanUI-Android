-- ============================================================
--  uiPBRP/td_reader.lua
--  Pembaca textdraw bersama untuk notification_ui dan inventory_ui.
--  Modul ini mengembalikan SATU tabel (singleton), bukan factory.
--
--  Fungsi utama:
--    TD.items[id]      data textdraw yang sedang tampil
--    TD.onShow(fn)     fn(rec) -> nil | "hide" | "block"
--    TD.onText(fn)     fn(rec)  (teks textdraw berubah)
--    TD.onHide(fn)     fn(rec)  (textdraw disembunyikan server)
--    TD.click(id)      kirim klik textdraw ke server
--    TD.cancel()       batalkan mode pilih textdraw (sama seperti ESC)
--    TD.hide(id)       sembunyikan textdraw asli (geser keluar layar)
--    TD.unhide(id)     kembalikan ke posisi asli
--    TD.dump()         tulis semua textdraw ke uiPBRP_textdraws.txt
-- ============================================================
local sampev = require "lib.samp.events"

local TD = {
    items = {},
    version = 0,
    OFFSCREEN = -4000,
    INVALID = 65535,
}

local listeners = { show = {}, hide = {}, text = {} }

function TD.onShow(fn) listeners.show[#listeners.show + 1] = fn end
function TD.onText(fn) listeners.text[#listeners.text + 1] = fn end
function TD.onHide(fn) listeners.hide[#listeners.hide + 1] = fn end

local function logError(tag, err)
    print("[PBRP/PKU UI][td_reader] " .. tag .. ": " .. tostring(err))
end

-- jalankan semua listener; untuk "show" kembalikan keputusan terkuat
local function fire(kind, rec)
    local verdict = nil
    for _, fn in ipairs(listeners[kind]) do
        local ok, result = pcall(fn, rec)
        if not ok then
            logError(kind, result)
        elseif kind == "show" then
            if result == "block" then
                verdict = "block"
            elseif result == "hide" and verdict ~= "block" then
                verdict = "hide"
            end
        end
    end
    return verdict
end

-- ---------- util ----------
local function num(value, default)
    value = tonumber(value)
    if value == nil then return default end
    return value
end

local function hasFlag(flags, mask)
    return math.floor(flags / mask) % 2 == 1
end

-- bersihkan kode warna SA-MP / GameText dan underscore (spasi di textdraw)
function TD.clean(text)
    text = tostring(text or "")
    text = text:gsub("~n~", " ")
    text = text:gsub("~%a~", "")
    text = text:gsub("{%x%x%x%x%x%x}", "")
    text = text:gsub("_", " ")
    text = text:gsub("%s+", " ")
    return (text:match("^%s*(.-)%s*$"))
end

function TD.isBlank(text)
    return text == nil or not tostring(text):match("%S")
end

-- ---------- pembuatan record ----------
local function makeRecord(id, data)
    local now = os.clock()
    local pos = type(data.position) == "table" and data.position or {}
    local flags = num(data.flags, 0)
    local rec = {
        id = id,
        raw = tostring(data.text or ""),
        x = num(pos.x, num(data.x, 0)),
        y = num(pos.y, num(data.y, 0)),
        lw = num(data.letterWidth, 0.5),
        lh = num(data.letterHeight, 1.0),
        tw = num(data.lineWidth, 0),
        th = num(data.lineHeight, 0),
        flags = flags,
        box = hasFlag(flags, 1),
        center = hasFlag(flags, 8),
        right = hasFlag(flags, 4),
        letterColor = num(data.letterColor, 0xFFFFFFFF),
        boxColor = num(data.boxColor, 0),
        bgColor = num(data.backgroundColor, 0),
        style = num(data.style, 1),
        selectable = (data.selectable == true or data.selectable == 1),
        model = num(data.modelId, 0),
        zoom = num(data.zoom, 1),
        shown = now,
        updated = now,
        hidden = false,
    }
    rec.text = TD.clean(rec.raw)
    return rec
end

local function touch(rec)
    rec.updated = os.clock()
    TD.version = TD.version + 1
end

-- perkiraan kotak textdraw pada layar virtual 640x448: x, y, lebar, tinggi
function TD.rect(rec)
    if rec.style == 5 then
        return rec.x, rec.y, math.max(0, rec.tw), math.max(0, rec.th)
    end
    local height = math.max(8, rec.lh * 9.0)
    if rec.center then
        local width = math.max(0, rec.tw)
        return rec.x - width / 2, rec.y, width, height
    elseif rec.right then
        return rec.tw, rec.y, math.max(0, rec.x - rec.tw), height
    end
    return rec.x, rec.y, math.max(0, rec.tw - rec.x), height
end

-- ---------- menyembunyikan textdraw asli ----------
local function moveOffscreen(data)
    if type(data.position) == "table" then
        data.position.x = TD.OFFSCREEN
        data.position.y = TD.OFFSCREEN
    else
        data.x = TD.OFFSCREEN
        data.y = TD.OFFSCREEN
    end
end

function TD.hide(id)
    local rec = TD.items[id]
    if rec then rec.hidden = true end
    pcall(sampTextdrawSetPos, id, TD.OFFSCREEN, TD.OFFSCREEN)
end

function TD.unhide(id)
    local rec = TD.items[id]
    if not rec then return end
    rec.hidden = false
    pcall(sampTextdrawSetPos, id, rec.x, rec.y)
end

-- ---------- interaksi ----------
function TD.click(id)
    local ok, err = pcall(sampSendClickTextdraw, id)
    if not ok then logError("click", err) end
    return ok
end

function TD.cancel()
    return TD.click(TD.INVALID)
end

function TD.exists(id)
    local ok, result = pcall(sampTextdrawIsExists, id)
    if ok then return result and true or false end
    return TD.items[id] ~= nil
end

-- ---------- hook event samp.lua (berantai dengan handler lain) ----------
local function hook(name, fn)
    local previous = sampev[name]
    sampev[name] = function(...)
        local ok, result = pcall(fn, ...)
        if not ok then
            logError(name, result)
            result = nil
        end
        local previousResult
        if previous then
            previousResult = previous(...)
        end
        if result == false or previousResult == false then
            return false
        end
        return previousResult
    end
end

hook("onShowTextDraw", function(id, data)
    if type(data) ~= "table" then return end
    local rec = makeRecord(id, data)
    TD.items[id] = rec
    TD.version = TD.version + 1
    local verdict = fire("show", rec)
    if verdict == "block" then
        rec.blocked = true
        return false
    elseif verdict == "hide" then
        rec.hidden = true
        moveOffscreen(data)
        -- cadangan: kalau perubahan data tidak diterapkan, geser setelah tampil
        pcall(function()
            lua_thread.create(function()
                wait(0)
                if TD.items[id] == rec then TD.hide(id) end
            end)
        end)
    end
end)

hook("onTextDrawSetString", function(id, text)
    local rec = TD.items[id]
    if not rec then
        rec = makeRecord(id, { text = text })
        TD.items[id] = rec
    end
    rec.raw = tostring(text or "")
    rec.text = TD.clean(rec.raw)
    touch(rec)
    fire("text", rec)
end)

hook("onTextDrawHide", function(id)
    local rec = TD.items[id]
    TD.items[id] = nil
    TD.version = TD.version + 1
    if rec then
        rec.gone = true
        fire("hide", rec)
    end
end)

-- ---------- scan textdraw yang sudah ada sebelum script dimuat ----------
function TD.scan()
    local found = 0
    for id = 0, 2303 do
        local okExists, exists = pcall(sampTextdrawIsExists, id)
        if okExists and exists and not TD.items[id] then
            local rec = makeRecord(id, {})
            local okText, text = pcall(sampTextdrawGetString, id)
            if okText and text then
                rec.raw = tostring(text)
                rec.text = TD.clean(rec.raw)
            end
            local okPos, px, py = pcall(sampTextdrawGetPos, id)
            if okPos and px then rec.x, rec.y = px, py end
            rec.scanned = true
            TD.items[id] = rec
            found = found + 1
        end
    end
    if found > 0 then TD.version = TD.version + 1 end
    return found
end

-- ---------- dump untuk analisis ----------
function TD.dumpPath()
    local okDir, dir = pcall(getWorkingDirectory)
    return (okDir and dir or ".") .. "/uiPBRP_textdraws.txt"
end

function TD.dump(path)
    path = path or TD.dumpPath()
    local file, err = io.open(path, "w")
    if not file then return nil, err end
    local ids = {}
    for id in pairs(TD.items) do ids[#ids + 1] = id end
    table.sort(ids)
    file:write("id | x,y | tw,th | letter | style | selectable | model | box | hidden | text\n")
    for _, id in ipairs(ids) do
        local r = TD.items[id]
        file:write(string.format("%d | %.1f,%.1f | %.1f,%.1f | %.2f,%.2f | %d | %s | %d | %s | %s | %s\n",
            r.id, r.x, r.y, r.tw, r.th, r.lw, r.lh, r.style,
            tostring(r.selectable), r.model, tostring(r.box), tostring(r.hidden), r.raw))
    end
    file:close()
    return #ids, path
end

return TD
