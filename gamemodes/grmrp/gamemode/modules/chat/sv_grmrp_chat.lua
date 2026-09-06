--[[ Вечер-14: реализация чата — ЕДИНАЯ библиотека lua/grm_chat. Точка входа
    режима; встроенный бандл gamemode/lib/grm_chat — идентичная копия для
    соло-установки gamemode-зипа (гейт sync_chat_addon.py --check следит за
    байтовым равенством). веч.-27: бандл может отсутствовать (выборочная копия)
    — include через GRM.LibInclude, инструкция — одна на лоадере. ]]
GRMRPChat = GRMRPChat or {}
if file and file.Exists and file.Exists("grm_chat/sv_net.lua", "LUA") then
    include("grm_chat/sv_net.lua")
else
    GRM.LibInclude("lib/grm_chat/sv_net.lua")
end
if not GRMRPChat.__loader then
    GRMRPChat.Mount = "lib/grm_chat"
    if not GRM.LibInclude("lib/grm_chat/loader.lua") then
        GRM.LibChatMissing()
    end
end
