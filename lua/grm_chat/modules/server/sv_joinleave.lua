--[[ Модуль (server): ПРИХОДЫ/УХОДЫ в глобальную ленту — демонстрация
    модульной системы и реальный запрос владельцев песочниц. По умолчанию
    ВЫКЛЮЧЕН (RP-серверам не нужен; включается grmrp_chat_joinleave 1).
    Строки идут тем же каналом system, что и баннеры ядра (один владелец
    ленты — deliver/BroadcastSystem), с задержкой, чтобы игрок успел
    получить HUD. ]]
if not (SERVER and GRMRPChat and isfunction(GRMRPChat.BroadcastSystem)) then
    return end

local cv = GetConVar and GetConVar("grmrp_chat_joinleave")
    or (CreateConVar and CreateConVar("grmrp_chat_joinleave", "0",
        { FCVAR_REPLICATED, FCVAR_NOTIFY },
        "Объявлять о приходе/уходе игрока в глобальный чат"))

local function on()
    return cv and cv:GetBool()
end

local function fmtName(ply)
    local raw = (IsValid(ply) and ply:Nick()) and ply:Nick() or "?"
    return GRMRPChat.Sanitize and GRMRPChat.Sanitize(raw, 64) or raw
end

hook.Add("PlayerInitialSpawn", "grm_chat.joinleave", function(ply)
    if not on() then return end
    timer.Simple(4, function()
        if IsValid(ply) then
            GRMRPChat.BroadcastSystem("* " .. fmtName(ply)
                .. " присоединился к городу")
        end
    end)
end)

hook.Add("PlayerDisconnect", "grm_chat.joinleave", function(ply)
    if not on() then return end
    GRMRPChat.BroadcastSystem("* " .. fmtName(ply) .. " покинул город")
end)
