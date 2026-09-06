--[[ Вечер-14: реализация чата — ЕДИНАЯ библиотека lua/grm_chat (лоадер
    lua/autorun/grm_chat.lua, устройство по образцу EasyChat). Этот файл —
    только точка входа режима. Если аддон не доехал (соло-установка
    gamemode-зипа), подключаем идентичную встроенную копию из
    gamemode/lib/grm_chat — гейт tools/sync_chat_addon.py --check следит за
    байтовым равенством. Тела файлов идемпотентны (флаги __core/__sv/__hud/
    __inp), поэтому двойной include (лоадером и отсюда) безопасен. ]]

local stale = GRMRP and isfunction(GRMRP.IsAddonChatStale)
    and GRMRP.IsAddonChatStale()
if file and file.Exists and file.Exists("grm_chat/cl_hud.lua", "LUA")
    and not stale then
    include("grm_chat/cl_hud.lua")
else
    if stale and GRMRPChat then GRMRPChat.__hud = nil end
    include("lib/grm_chat/cl_hud.lua")
end
-- Вечер-21: модули автозагрузчиком (в т.ч. карантин: у СТАРОГО аддона
-- loader'а нет — берём свой, свежий).
GRMRPChat = GRMRPChat or {}
GRMRPChat.Mount = "lib/grm_chat"
include("lib/grm_chat/loader.lua")
