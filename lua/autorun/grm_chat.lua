--[[ grm_chat — ЕДИНАЯ БИБЛИОТЕКА ЧАТА GRM:RP (вечер-14).

    Устройство по образцу EasyChat 4.21: тонкий autorun-лоадер + папка
    модулей lua/grm_chat/. Один код на все сценарии: песочница, любой
    чужой геймод (через хук PlayerSay с флагом-уступкой) и режим GRMRP
    (его modules/chat/* — форвардеры сюда же; при отсутствии аддона
    режим тянет идентичную встроенную копию gamemode/lib/grm_chat,
    байтовое равенство сторожит tools/sync_chat_addon.py --check).

    Реестр модулей (realm-клей — как в движковом примере):
      sh_core  — чистое ядро: sanitize/ParseSay/каналы/реестр внешних
                 команд/лестница/подавление чужих владельцев;
      sv_net   — cvar'ы, net-контракт, deliver, RPAction, PlayerSay-вход;
      cl_hud   — лента-панель, архив/хранение, chat.AddText-мост;
      cl_input — Y-окно: ввод, чипы каналов, Tab, память ввода, окно
                 истории (архив), диaгностика /chatdiag.
]]

AddCSLuaFile()

local MODULES_SHARED = { "sh_core.lua" }
local MODULES_SERVER = { "sv_net.lua" }
local MODULES_CLIENT = { "cl_hud.lua", "cl_input.lua" }

local function each(list) return ipairs(list) end

if SERVER then
    for _, f in each(MODULES_SHARED) do AddCSLuaFile("grm_chat/" .. f) end
    for _, f in each(MODULES_CLIENT) do AddCSLuaFile("grm_chat/" .. f) end
    for _, f in each(MODULES_SHARED) do include("grm_chat/" .. f) end
    for _, f in each(MODULES_SERVER) do include("grm_chat/" .. f) end
else
    for _, f in each(MODULES_SHARED) do include("grm_chat/" .. f) end
    for _, f in each(MODULES_CLIENT) do include("grm_chat/" .. f) end
end
