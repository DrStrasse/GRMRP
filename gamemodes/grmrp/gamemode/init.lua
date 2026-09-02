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

local FOLDER = GM.FolderName .. "/gamemode/modules/"

local files, folders = file.Find(FOLDER .. "*", "LUA")

for _, v in ipairs(files) do
    if string.GetExtensionFromFilename(v) ~= "lua" then continue end
    include(FOLDER .. v)
end

for _, folderName in SortedPairs(folders, true) do
    if folderName == "." or folderName == ".." then continue end
    if GRMRP.Modules and GRMRP.Modules[folderName] and GRMRP.Modules[folderName].disabled then
        continue
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/sh_*.lua", "LUA"), true) do
        AddCSLuaFile(FOLDER .. folderName .. "/" .. File)
        include(FOLDER .. folderName .. "/" .. File)
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/sv_*.lua", "LUA"), true) do
        include(FOLDER .. folderName .. "/" .. File)
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

function GM:InitPostEntity()
    if self.BaseClass.InitPostEntity then self.BaseClass:InitPostEntity(self) end
    hook.Run("GRMRPPostEntity")
end

-- Чат: полный перехват. Возврат "" глушит движковую рассылку — режим
-- никогда не отдаётsay наружу, кроме явного BaseClass-fallback при
-- выключенном модуле (чтобы чат не «исчез молча»).
function GM:PlayerSay(ply, text, teamChat, isDead)
    if GRMRPChat and GRMRPChat.Enabled() then
        GRMRPChat.OnPlayerSay(ply, text, teamChat, isDead)
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
