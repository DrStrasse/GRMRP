--[[ Вечер-14: реализация чата — ЕДИНАЯ библиотека lua/grm_chat (лоадер
    lua/autorun/grm_chat.lua, устройство по образцу EasyChat). Этот файл —
    только точка входа режима. Если аддон не доехал (соло-установка
    gamemode-зипа), подключаем идентичную встроенную копию из
    gamemode/lib/grm_chat — гейт tools/sync_chat_addon.py --check следит за
    байтовым равенством. веч.-27: бандл может отсутствовать (выборочная копия)
    — include строго через GRM.LibInclude, молчаливый пропуск без паники. ]]
if file and file.Exists and file.Exists("grm_chat/sh_core.lua", "LUA") then
    include("grm_chat/sh_core.lua")
else
    GRM.LibInclude("lib/grm_chat/sh_core.lua")
end
