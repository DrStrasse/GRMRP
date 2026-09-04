--[[ Вечер-14: реализация чата — ЕДИНАЯ библиотека lua/grm_chat (лоадер
    lua/autorun/grm_chat.lua, устройство по образцу EasyChat). Этот файл —
    только точка входа режима. Если аддон не доехал (соло-установка
    gamemode-зипа), подключаем идентичную встроенную копию из
    gamemode/lib/grm_chat — гейт tools/sync_chat_addon.py --check следит за
    байтовым равенством. Тела файлов идемпотентны (флаги __core/__sv/__hud/
    __inp), поэтому двойной include (лоадером и отсюда) безопасен. ]]

if file and file.Exists and file.Exists("grm_chat/sv_net.lua", "LUA") then
    include("grm_chat/sv_net.lua")
else
    include("lib/grm_chat/sv_net.lua")
end
