local M = {}

local allowedAssetExtensions = {
    bmp = true,
    gif = true,
    jpeg = true,
    jpg = true,
    m4a = true,
    mp3 = true,
    ogg = true,
    png = true,
    webp = true,
    wav = true,
}

function M.isAllowedPath(relativePath)
    if type(relativePath) ~= "string" then return false end
    if relativePath == "uijtrp.lua" then return true end

    local normalizedPath = relativePath:lower()
    if relativePath:find("\\", 1, true) or relativePath:find("//", 1, true)
        or relativePath:find(":", 1, true) or not relativePath:match("^[%w_%.%-/]+$") then
        return false
    end

    local segments = {}
    for segment in normalizedPath:gmatch("[^/]+") do
        if segment == "." or segment == ".." or segment:sub(1, 1) == "." then
            return false
        end
        segments[#segments + 1] = segment
    end

    if #segments < 2 then return false end

    local root = segments[1]
    local isModule = root == "uijtrp"
    local isAsset = root == "assets"
    local isPhoneAsset = root == "jtrp_phone"
    if not isModule and not isAsset and not isPhoneAsset then return false end
    if isModule and normalizedPath:sub(1, 11) == "uijtrp/web/" then return false end

    if isPhoneAsset then
        for _, segment in ipairs(segments) do
            if segment:find("notif", 1, true)
                or segment:find("notify", 1, true)
                or segment:find("ringtone", 1, true) then
                return false
            end
        end
    end

    local extension = segments[#segments]:match("%.([%w]+)$")
    if not extension then return false end
    if extension == "lua" then return isModule end
    return allowedAssetExtensions[extension] == true and not isModule
end

return M
