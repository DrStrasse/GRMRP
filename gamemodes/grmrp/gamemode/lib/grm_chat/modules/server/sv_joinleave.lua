--[[ Модуль (server): ПРИХОДЫ/УХОДЫ в глобальную ленту. Формулировки —
    со слов владельца (вечер-22): «Игрок X зашёл на сервер» / «Игрок X вышел
    с сервера». По умолчанию ВКЛ (запрос владельца; на RP-песочницах это
    нужный поток, отключается grmrp_chat_joinleave 0).
    Строки идут тем же каналом system, что и баннеры ядра (один владелец
    ленты — deliver/BroadcastSystem), с задержкой, чтобы игрок успел
    получить HUD. ]]
if not (SERVER and GRMRPChat and isfunction(GRMRPChat.BroadcastSystem)) then
    return end

local cv = GetConVar and GetConVar("grmrp_chat_joinleave")
    or (CreateConVar and CreateConVar("grmrp_chat_joinleave", "1",
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
            GRMRPChat.BroadcastSystem("Игрок " .. fmtName(ply) .. " зашёл на сервер")
        end
    end)
end)

hook.Add("PlayerDisconnect", "grm_chat.joinleave", function(ply)
    if not on() then return end
    GRMRPChat.BroadcastSystem("Игрок " .. fmtName(ply) .. " вышел с сервера")
end)
