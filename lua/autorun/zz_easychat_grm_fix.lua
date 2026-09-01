--[[--------------------------------------------------------------------
    GRM EasyChat fixes (load after easychat_init)
    - module ignore for gamemode-specific modules that spam lua_refresh
    - re-assert nick engine binding if overflow-prone state detected
----------------------------------------------------------------------]]

if SERVER then AddCSLuaFile() end

-- Ignore list for EasyChat autoloader (DATA file)
local IGNORE_PATH = "easychat/module_ignore_list.txt"
local IGNORE_LINES = {
    "server/murder.lua",  -- only for Murder gamemode; causes Unhandled Lua Refresh elsewhere
}

local function ensure_ignore_list()
    if not file.IsDir("easychat", "DATA") then
        file.CreateDir("easychat")
    end
    local existing = ""
    if file.Exists(IGNORE_PATH, "DATA") then
        existing = file.Read(IGNORE_PATH, "DATA") or ""
    end
    local changed = false
    for _, line in ipairs(IGNORE_LINES) do
        if not string.find(existing, line, 1, true) then
            existing = existing .. line .. "\n"
            changed = true
        end
    end
    if changed or not file.Exists(IGNORE_PATH, "DATA") then
        file.Write(IGNORE_PATH, existing)
    end
end

if SERVER then
    ensure_ignore_list()
end

-- Client also needs ignore list if modules load clientside
if CLIENT then
    ensure_ignore_list()
end

-- Safety: if NativeNick somehow points at Nick wrapper again, rebind
timer.Simple(2, function()
    if not EasyChat or not FindMetaTable then return end
    local PLY = FindMetaTable("Player")
    if not PLY then return end
    if isfunction(PLY.EngineNick) then
        EasyChat._TrueNativeNick = PLY.EngineNick
        EasyChat.NativeNick = PLY.EngineNick
    end
end)

print("[GRM] EasyChat fix loaded (NativeNick/EngineNick + module ignore)")
