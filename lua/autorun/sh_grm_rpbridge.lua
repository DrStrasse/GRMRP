--[[ GRM.RPBroadcast — ЕДИНАЯ шина RP-отыгровок серверной originates (вечер-13).

    До этого каждый модуль (документы, образование/дипломы) сам реализовывал
    трёхветочную развилку «EasyChat → GRM_RPChat_Msg → ChatPrint»: дубли кода,
    мёртвая ветка EasyChat (чат вырезан по указанию владельца), а на сервере
    с режимным чатом строки шли МИМО ленты режима. Теперь точка входа одна:

      1) живой владелец чата (GRMRPChat режима или GRMChat-порт песочницы,
         если не подавлен) — доставка через его RPAction("me") с echo автора,
         RP-именем и радиусом события;
      2) нет владельца — старая net-шина GRM_RPChat_Msg (если грузилась);
      3) и нет её — ChatPrint по радиусу.

    Правила подключения модулей (записаны в OWNER_REPORTS.md): новый код НЕ
    выбирает канал сам — только GRM.RPBroadcast.
]]

GRM = GRM or {}

function GRM.GetRPName(ply)
    if not IsValid(ply) then return "?" end
    local n = ply:GetNWString("GRM_RPName", "")
    return (n ~= "" and n) or ply:Nick()
end

if not SERVER then return end

-- Порядок обхода не порождает двойную доставку: в новом мире GRMChat —
-- АЛИАС того же стола GRMRPChat (lua/grm_chat/sh_core), цикл возвращается
-- на первом владельце. Отдельный стол «GRMChat» бывает только при смешанной
-- установке старого аддона; его подавитель помечает SUPPRESSED — шина
-- его пропускает и уходит на GRMRPChat (или фолбэк GRM_RPChat_Msg).
local CHAT_OWNERS = { "GRMRPChat", "GRMChat" }

--- meText — текст действия без ведущей «* » (сама шина добавит формат);
--- radius — юниты (по умолчанию 400, как у бланков веч.-8…12).
--- Возвращает строку-ошибку владельца (или nil), как RPAction.
function GRM.RPBroadcast(ply, meText, radius)
    if not IsValid(ply) or not ply:IsPlayer() then return end
    meText = string.Trim(tostring(meText or ""))
    if meText == "" then return end
    radius = math.Clamp(tonumber(radius) or 400, 64, 4096)

    for i = 1, #CHAT_OWNERS do
        local owner = rawget(_G, CHAT_OWNERS[i])
        if istable(owner) and istable(owner.Channels) and not owner.SUPPRESSED
            and isfunction(owner.RPAction)
            and (not isfunction(owner.Enabled) or owner.Enabled()) then
            local body = isfunction(owner.Sanitize)
                and owner.Sanitize(meText, owner.HARD_MAX) or meText
            return owner.RPAction("me", ply, body, nil, {
                echoAuthor = true, -- серверное событие: автору шлём (у него нет
                                   -- локального эха клиентского ввода)
                rpName = GRM.GetRPName(ply),
                range = radius,
            })
        end
    end

    -- Владельца нет: старая net-шина (её приёмник переживает подавление
    -- хуков — net.Receive не снимается) либо прямой ChatPrint.
    local full = "* " .. GRM.GetRPName(ply) .. " " .. meText
    local useNet = util and util.NetworkStringToID
        and util.NetworkStringToID("GRM_RPChat_Msg") ~= 0
    local origin = ply:GetPos()
    local targets = (GRM.Perf and GRM.Perf.Players) and GRM.Perf.Players() or player.GetAll()
    for _, p in ipairs(targets) do
        if IsValid(p) and p:GetPos():DistToSqr(origin) <= radius * radius then
            if useNet then
                net.Start("GRM_RPChat_Msg")
                    net.WriteUInt(2, 8)
                    net.WriteBool(true)
                    net.WriteUInt(200, 8) net.WriteUInt(160, 8) net.WriteUInt(255, 8)
                    net.WriteBool(false)
                    net.WriteString(full)
                net.Send(p)
            else
                p:ChatPrint(full)
            end
        end
    end
end
