--[[ Вечер-21: АВТОЗАГРУЗЧИК модулей grm_chat. Снято с живого исходника
    EasyChat (Earu/EasyChat master, lua/easychat/autoloader.lua — 129 LOC):
    каталог modules/{shared,server,client}/ подменяется файлами, каждый
    модуль грузится в pcall (сломанный модуль не валит чат), имя модуля из
    имени файла, «могильник» — data-файл module_ignore.txt (строка = имя
    файла или <realm>/<файл>, # — комментарий). Реестр GRMRPChat.Modules
    [/chatdiag показывает state].

    Порядок вызова: loader подключается ПОСЛЕ ядра (аддонский
    lua/autorun/grm_chat.lua; в режиме — в конце sv- и cl-форвардеров с
    GRMRPChat.Mount = "lib/grm_chat"). shared-модули грузятся в обоих
    реалмах; server — только сервером, client — только клиентом. ]]
GRMRPChat = GRMRPChat or {}
if GRMRPChat.__loader then return end
GRMRPChat.__loader = true

local MOUNT = GRMRPChat.Mount or "grm_chat"
GRMRPChat.MOUNT = MOUNT
GRMRPChat.Modules = GRMRPChat.Modules or {}

local IGNORE_FILE = "grm_chat/module_ignore.txt"

local function ignoredSet()
    local set = {}
    if not (file and file.Exists and file.Read) then return set end
    if not file.Exists(IGNORE_FILE, "DATA") then return set end
    local raw = file.Read(IGNORE_FILE, "DATA")
    if not isstring(raw) then return set end
    for line in raw:gmatch("[^\r\n]+") do
        local nm = line:match("^%s*(.-)%s*$")
        if nm and #nm > 0 and nm:sub(1, 1) ~= "#" then set[nm] = true end
    end
    return set
end

local function listDir(dir)
    local out = {}
    if not (file and file.Find) then return out end
    local files = file.Find(MOUNT .. "/modules/" .. dir .. "/*.lua", "LUA")
    if not istable(files) then return out end
    for _, fn in ipairs(files) do
        if isstring(fn) and #fn > 4 and fn:sub(-4) == ".lua" then
            out[#out + 1] = fn
        end
    end
    table.sort(out)
    return out
end

local loadedOnce = {}
local function loadDir(dir, ignore)
    if loadedOnce[dir] then return end
    loadedOnce[dir] = true
    for _, fn in ipairs(listDir(dir)) do
        local name = fn:sub(1, -5)
        if ignore[name] or ignore[dir .. "/" .. fn] then
            GRMRPChat.Modules[name] = { state = "ignored" }
        else
            local path = MOUNT .. "/modules/" .. dir .. "/" .. fn
            local ok, err = pcall(include, path)
            if ok then
                GRMRPChat.Modules[name] = { state = "loaded", realm = dir }
            else
                GRMRPChat.Modules[name] = { state = "error", err = tostring(err) }
                if ErrorNoHalt then
                    ErrorNoHalt("[grm_chat] модуль " .. name .. " не загрузился: "
                        .. tostring(err) .. "\n")
                end
            end
        end
    end
end

if SERVER and AddCSLuaFile then
    -- Аддонский путь: клиентские модули надо разослать (режимный бандл уже
    -- в монте клиента, AddCSLuaFile для gamemode-файлов не нужен).
    AddCSLuaFile(MOUNT .. "/loader.lua")
    for _, dir in ipairs({ "shared", "client" }) do
        for _, fn in ipairs(listDir(dir)) do
            AddCSLuaFile(MOUNT .. "/modules/" .. dir .. "/" .. fn)
        end
    end
end

local ignore = ignoredSet()
loadDir("shared", ignore)
if SERVER then
    loadDir("server", ignore)
elseif CLIENT then
    loadDir("client", ignore)
end
