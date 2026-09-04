--[[ GRM:RP — клиентский вход режима: тот же цикл модулей, что на сервере
    (только sh_/cl_; порядок совпадает — обе стороны видят один реестр
    каналов/констант до первого пакета).
]]

include("shared.lua") -- namespace/net-константы/GRMAPI; движок shared сам не грузит
DEFINE_BASECLASS("gamemode_sandbox")

hook.Run("GRMRPStartedLoadingClient")

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
        include(FOLDER .. folderName .. "/" .. File)
    end

    for _, File in SortedPairs(file.Find(FOLDER .. folderName .. "/cl_*.lua", "LUA"), true) do
        include(FOLDER .. folderName .. "/" .. File)
    end
end

GRMAPI.finish()
GRMRP.Loading = false

hook.Run("GRMRPFinishedLoadingClient")

-- Вечер-14: после reload (аддонов/режима) чужие хуки могли пересоздаться —
-- снимаем повторно на поздней клиентской стадии.
if GRMRPChat and isfunction(GRMRPChat.SuppressForeignChat) then
    GRMRPChat.SuppressForeignChat()
end

-- Движковый чат скрыт: окно и лента — наши (cl_grmrp_chat*).
function GM:HUDShouldDraw(name)
    if name == "CHudChat" and GRMRPChat and GRMRPChat.Enabled
        and GRMRPChat.Enabled() then return false end
    return self.BaseClass:HUDShouldDraw(name)
end

-- Y открывает наш ввод вместо движкового (флаг — библиотечный HUDKeyPress
-- уступает, см. cl_input библиотеки).
GM.__chatOwnsStartChat = true
function GM:StartChat()
    if GRMRPChat and GRMRPChat.OpenInput and GRMRPChat.Enabled
        and GRMRPChat.Enabled() then
        GRMRPChat.OpenInput()
        return false
    end
    return self.BaseClass:StartChat()
end
