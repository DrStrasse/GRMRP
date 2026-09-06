--[[ GRM:RP — серверный вход режима.

    Порядок (WIKI 4.16.1): базовый sandbox → реестры деклараций модулей →
    GRMAPI.finish() → флаг загрузки снят → хук готовности.
]]

-- Движок НЕ подгружает shared.lua сам: каждый вход включает его явно
-- (wiki «Gamemode Creation»). DeriveGamemode живёт в shared.lua.
AddCSLuaFile("cl_init.lua")
AddCSLuaFile("shared.lua")
AddCSLuaFile("grm_api.lua")
include("shared.lua")

DEFINE_BASECLASS("gamemode_sandbox")

GRMRP.GM = GM

hook.Run("GRMRPStartedLoading")

-- Вечер-22 (инцидент «слетело меню персонажа/стартовые экраны/ESC»): голый
-- include в цикле вешает весь недозагруженный режим — если в gamemodes/grmrp
-- остались файлы СТАРОЙ установки, один из них роняет загрузку до ui/chat и
-- все клиентские системы исчезают, хотя чат (живёт отдельным каналом) цел.
-- Каждый файл теперь под pcall: битый — в лог и пропущен, остальные грузятся.
local badFiles = {}
local function grminclude(path)
    local ok, err = pcall(include, path)
    if not ok then
        badFiles[#badFiles + 1] = path
        if ErrorNoHalt then
            ErrorNoHalt("[GRMRP] пропущен битый/устаревший файл: " .. path ..
                "\n" .. tostring(err) .. "\n")
        end
    end
    return ok
end
local FOLDER = GM.FolderName .. "/gamemode/modules/"

local files, folders = file.Find(FOLDER .. "*", "LUA")

for _, v in ipairs(files) do
    if string.GetExtensionFromFilename(v) ~= "lua" then continue end
    grminclude(FOLDER .. v)
end

for _, folderName in SortedPairs(folders, true) do
    if folderName == "." or folderName == ".." then continue end
    if GRMRP.Modules and GRMRP.Modules[folderName] and GRMRP.Modules[folderName].disabled then
        continue
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/sh_*.lua", "LUA"), true) do
        AddCSLuaFile(FOLDER .. folderName .. "/" .. File)
        grminclude(FOLDER .. folderName .. "/" .. File)
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/sv_*.lua", "LUA"), true) do
        grminclude(FOLDER .. folderName .. "/" .. File)
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/cl_*.lua", "LUA"), true) do
        AddCSLuaFile(FOLDER .. folderName .. "/" .. File)
    end
end

GRMAPI.finish()
GRMRP.Loading = false

hook.Run("GRMRPFinishedLoading")

function GM:Initialize(reason)
    if self.BaseClass.Initialize then self.BaseClass:Initialize(self, reason) end
    GRMRP.Log("режим GRM:RP v" .. GRMRP.VERSION .. " инициализирован")
end

if #badFiles > 0 then
    if ErrorNoHalt then
        ErrorNoHalt(("[GRMRP] ВАЖНО: %d файл(ов) режима пропущены как битые/устаревшие (%s). ")
            :format(#badFiles, table.concat(badFiles, ", ")) ..
            "Смешанная установка ломает меню и экраны: удалите gamemodes/grmrp ЦЕЛИКОМ и распакуйте grmrp_gamemode.zip на чистое место.\n")
    end
end

function GM:InitPostEntity()
    if self.BaseClass.InitPostEntity then self.BaseClass:InitPostEntity(self) end
    hook.Run("GRMRPPostEntity")
end

-- Чат: полный перехват. Возврат "" глушит движковую рассылку — режим
-- никогда не отдаётsay наружу, кроме явного BaseClass-fallback при
-- выключенном модуле (чтобы чат не «исчез молча»).
-- Вечер-14: режим — владелец say целиком; библиотечный хук
-- GRMRPChat_Capture по этому флагу уступает (двойной обработки нет).
GM.__chatOwnsPlayerSay = true

function GM:PlayerSay(ply, text, teamChat, isDead)
    if GRMRPChat and GRMRPChat.Enabled and GRMRPChat.Enabled() then
        -- ProcessLine сам дёргает цепочку PlayerSay ради внешних команд
        -- модулей (вечер-12) — вложенный вызов methods глушим точкой входа
        if GRMRPChat._inExternal then return "" end
        -- вечер-22: чат не имеет права ронять GM:PlayerSay — pcall+лог.
        local ok, err = pcall(GRMRPChat.OnPlayerSay, ply, text, teamChat, isDead)
        if not ok and ErrorNoHalt then
            ErrorNoHalt("[grm_chat] сбой обработки say: " .. tostring(err) .. "\n")
        end
        return ""
    end
    return self.BaseClass:PlayerSay(ply, text, teamChat, isDead)
end

-- Голос: канал живёт в модуле связи (будущий mob); пока — только PVS.
function GM:PlayerCanHearPlayersVoice(listener, talker)
    if not IsValid(listener) or not IsValid(talker) then return false end
    if listener:GetPos():DistToSqr(talker:GetPos()) > 806400 then return false end -- 896 юнитов
    return true
end

-- Спавн: намеренно НЕ переопределён — базовый sandbox; физ-заморозку
-- «руками не трогать» включит core.character (карта систем 7.2), и только
-- он. Пустых переопределений «ради будущего» не заводим (§5.2).
