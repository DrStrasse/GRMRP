--[[ Вечер-14: реализация чата — ЕДИНАЯ библиотека lua/grm_chat (лоадер
    lua/autorun/grm_chat.lua, устройство по образцу EasyChat). Этот файл —
    только точка входа режима. Если аддон не доехал (соло-установка
    gamemode-зипа), подключаем идентичную встроенную копию из
    gamemode/lib/grm_chat — гейт tools/sync_chat_addon.py --check следит за
    байтовым равенством. Тела файлов идемпотентны (флаги __core/__sv/__hud/
    __inp), поэтому двойной include (лоадером и отсюда) безопасен. ]]

local stale = GRMRP and isfunction(GRMRP.IsAddonChatStale)
    and GRMRP.IsAddonChatStale()
if file and file.Exists and file.Exists("grm_chat/cl_input.lua", "LUA")
    and not stale then
    include("grm_chat/cl_input.lua")
else
    if stale and GRMRPChat then GRMRPChat.__inp = nil end
    include("lib/grm_chat/cl_input.lua")
end
